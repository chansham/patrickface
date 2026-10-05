"""Synthetic device-bundle/ZIP regressions, not signing or device-install tests."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

from archive_apple import (IDS, PackageError, entitlement_requirements, macho_slices,
                           product_records, tree_snapshot, verify_unsigned_ipa)


def binary(platform=2, cpu=0x0100000C, signed=False, endian="<", legacy=False):
    command = (struct.pack(endian + "IIII", 0x25 if platform == 2 else 0x30, 16, 0, 0) if legacy
               else struct.pack(endian + "IIIIII", 0x32, 24, platform, 0, 0, 0))
    if signed:
        command += struct.pack(endian + "IIII", 0x1D, 16, 0, 0)
    return struct.pack(endian + "IiiIIIII", 0xFEEDFACF, cpu, 0, 2, 2 if signed else 1, len(command), 0, 0) + command


def fat(parts):
    table_size = 8 + len(parts) * 20
    table, payload, offset = b"", b"", table_size
    for data in parts:
        table += struct.pack(">iiIII", 0x0100000C, 0, offset, len(data), 0)
        payload += data; offset += len(data)
    return struct.pack(">II", 0xCAFEBABE, len(parts)) + table + payload


class UnsignedPackageChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / "PatrickCompanion.app"
        for relative, identifier in IDS.items():
            folder = self.app / relative; folder.mkdir(parents=True)
            watch = relative.startswith("Watch/")
            info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "program",
                    "CFBundleVersion": "19", "CFBundleShortVersionString": "1.0",
                    "CFBundleSupportedPlatforms": ["WatchOS" if watch else "iPhoneOS"],
                    "DTPlatformName": "watchos" if watch else "iphoneos"}
            if relative == "Watch/PatrickFace.app":
                info["WKCompanionAppBundleIdentifier"] = IDS[""]
            (folder / "Info.plist").write_bytes(plistlib.dumps(info))
            (folder / "program").write_bytes(binary(4 if watch else 2))
            (folder / "program").chmod(0o755)
            (folder / "fixture-resource.bin").write_bytes(b"unchanged resource\0\x80")
        self.expected = tree_snapshot(self.app)
        # Windows cannot represent POSIX execute bits. ZIP fixtures model the
        # actual macOS mode explicitly; production packaging uses real lstat.
        for relative in IDS:
            self.expected[(relative + "/" if relative else "") + "program"]["mode"] = 0o755

    def tearDown(self):
        self.temporary.cleanup()

    def write_zip(self, *, omit=(), replacements=None, modes=None, extra=()):
        replacements, modes = replacements or {}, modes or {}
        path = self.root / "fixture.ipa"
        with warnings.catch_warnings(), zipfile.ZipFile(path, "w") as archive:
            warnings.simplefilter("ignore", UserWarning)
            for name, record in self.expected.items():
                if name in omit:
                    continue
                kind = record["type"]
                full = "Payload/PatrickCompanion.app" + ("/" + name if name else "")
                info = zipfile.ZipInfo(full + ("/" if kind == "directory" else ""))
                info.create_system = 3
                type_bits = {"directory": stat.S_IFDIR, "file": stat.S_IFREG, "symlink": stat.S_IFLNK}[kind]
                info.external_attr = (type_bits | modes.get(name, record["mode"])) << 16
                if kind == "directory":
                    data = b""
                elif kind == "symlink":
                    data = os.fsencode(record["target"])
                else:
                    data = replacements.get(name, (self.app / name).read_bytes())
                archive.writestr(info, data)
            for name, data in extra:
                info = zipfile.ZipInfo(name); info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(info, data)
        return path

    def test_all_four_device_products_and_exact_bytes(self):
        report = verify_unsigned_ipa(self.write_zip(), self.expected)
        self.assertEqual(len(report["products"]), 4)
        self.assertEqual([p["platform"] for p in report["products"]], ["iPhoneOS", "iPhoneOS", "WatchOS", "WatchOS"])
        self.assertTrue(report["allOriginalBytesIdentical"])
        self.assertEqual(report["verifiedEntryCount"], len(self.expected))

    def test_missing_watch_or_extension_is_rejected(self):
        for name in ("Watch/PatrickFace.app/program", "PlugIns/PatrickWidgets.appex/Info.plist"):
            with self.subTest(name=name), self.assertRaises(PackageError):
                verify_unsigned_ipa(self.write_zip(omit=[name]), self.expected)

    def test_modified_resources_and_permissions_are_rejected(self):
        with self.assertRaises(PackageError):
            verify_unsigned_ipa(self.write_zip(replacements={"fixture-resource.bin": b"changed"}), self.expected)
        with self.assertRaises(PackageError):
            verify_unsigned_ipa(self.write_zip(modes={"program": 0o644}), self.expected)

    def test_unsafe_duplicate_or_extra_zip_paths_are_rejected(self):
        for name in ("../outside", "/absolute", "Payload/../outside", "Payload//bad", "C:/bad",
                     "Payload/PatrickCompanion.app/Info.plist", "Payload/PatrickCompanion.app/INFO.PLIST",
                     "Payload/Other.app/program", "Payload/PatrickCompanion.app/new-file"):
            with self.subTest(name=name), self.assertRaises(PackageError):
                verify_unsigned_ipa(self.write_zip(extra=[(name, b"unexpected")]), self.expected)

    def test_appledouble_is_limited_to_existing_payload(self):
        good = "__MACOSX/Payload/PatrickCompanion.app/._fixture-resource.bin"
        report = verify_unsigned_ipa(self.write_zip(extra=[(good, b"\0\5\x16\7metadata")]), self.expected)
        self.assertEqual(report["appleDoubleEntries"], [good])
        for name, data in [(good, b"not AppleDouble"), ("__MACOSX/._unrelated", b"\0\5\x16\7")]:
            with self.subTest(name=name), self.assertRaises(PackageError):
                verify_unsigned_ipa(self.write_zip(extra=[(name, data)]), self.expected)

    def test_zip_symlink_payload_is_target_bytes(self):
        target = b"fixture-resource.bin"
        self.expected["resource-link"] = {"type": "symlink", "mode": 0o777, "target": target.decode(),
                                           "size": len(target), "sha256": hashlib.sha256(target).hexdigest()}
        self.assertTrue(verify_unsigned_ipa(self.write_zip(), self.expected)["permissionsAndSymlinksPreserved"])

    def test_tree_snapshot_refuses_escape_and_does_not_follow_safe_link(self):
        link = self.app / "resource-link"
        try:
            link.symlink_to("fixture-resource.bin")
        except OSError as error:
            self.skipTest(f"Host cannot create test symlinks: {error}")
        self.assertEqual(tree_snapshot(self.app)["resource-link"]["type"], "symlink")
        link.unlink(); (self.root / "outside").write_bytes(b"outside")
        link.symlink_to("../outside")
        with self.assertRaises(PackageError): tree_snapshot(self.app)

    def test_device_plist_and_safe_executable_are_required(self):
        path = self.app / "Info.plist"
        original = plistlib.loads(path.read_bytes())
        for changes in ({"CFBundleSupportedPlatforms": ["iPhoneSimulator"]},
                        {"CFBundleExecutable": "../outside"}, {"CFBundleIdentifier": "different.id"}):
            path.write_bytes(plistlib.dumps({**original, **changes}))
            with self.subTest(changes=changes), self.assertRaises(PackageError):
                product_records(lambda name: (self.app / name).read_bytes(), lambda name: (self.app / name).exists())

    def test_signing_provisioning_and_simulator_binaries_are_rejected(self):
        for data in (binary(7), binary(2, signed=True), binary(2, cpu=0x01000007), b"not Mach-O"):
            with self.subTest(data=data[:12]), self.assertRaises(PackageError): macho_slices(data, 2)
        (self.app / "embedded.mobileprovision").write_bytes(b"profile")
        with self.assertRaises(PackageError):
            product_records(lambda name: (self.app / name).read_bytes(), lambda name: (self.app / name).exists())

    def test_every_fat_slice_and_endian_is_checked(self):
        self.assertEqual(len(macho_slices(fat([binary(), binary(endian=">")]), 2)), 2)
        self.assertEqual(macho_slices(binary(4, legacy=True), 4)[0]["platform"], 4)
        for data in (fat([binary(), binary(7)]), fat([binary()])[:-1], binary()[:30]):
            with self.subTest(size=len(data)), self.assertRaises(PackageError): macho_slices(data, 2)

    def test_entitlement_templates_are_requirements_not_signed_claims(self):
        requirements = entitlement_requirements()
        self.assertEqual(len(requirements), 4)
        self.assertTrue(all(r["requiredAppGroups"] == ["group.com.chans.patrickface.shared"] for r in requirements))
        self.assertEqual([r["bundleID"] for r in requirements if r["requiresHealthKit"]], [IDS["Watch/PatrickFace.app"]])
        self.assertTrue(all(len(r["templateSHA256"]) == 64 for r in requirements))

    def test_signed_and_unsigned_flags_are_mutually_exclusive(self):
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("archive_apple.py")),
                                 "--package-unsigned", "--signing-config", "unused.json"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not allowed with argument", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
