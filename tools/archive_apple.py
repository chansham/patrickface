"""Create a local device archive. No uploads, provisioning downloads or installs.

Unsigned is the default structural archive check. --package-unsigned additionally
creates an unsigned IPA for an external re-signing tool; it is NOT installable.
Signed mode requires existing certificates/profiles and explicit local config.
"""
from pathlib import Path, PurePosixPath
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import platform
import plistlib
import re
import stat
import struct
import subprocess
import tempfile
import unicodedata
import zipfile
from check_apple_bundle import IDS, verify

ROOT = Path(__file__).resolve().parents[1]
PROFILE_KEYS = ["PATRICK_PHONE_PROFILE", "PATRICK_WIDGET_PROFILE", "PATRICK_WATCH_PROFILE", "PATRICK_COMPLICATION_PROFILE"]
ENTITLEMENT_TEMPLATES = {
    "": "iOSCompanion/PatrickCompanion/PatrickCompanion.entitlements",
    "PlugIns/PatrickWidgets.appex": "iOSCompanion/PatrickWidgets/PatrickWidgets.entitlements",
    "Watch/PatrickFace.app": "PatrickFace/PatrickFace.entitlements",
    "Watch/PatrickFace.app/PlugIns/PatrickFaceComplications.appex": "PatrickFaceComplications/PatrickFaceComplications.entitlements",
}


class PackageError(ValueError):
    """Unverified inputs must never be labeled as a ready re-signing package."""


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_relative(name: str) -> str:
    if not name or name.startswith("/") or "\\" in name or ":" in name or "\0" in name:
        raise PackageError(f"Unsafe package path: {name!r}")
    if any(part in {"", ".", ".."} for part in name.split("/")):
        raise PackageError(f"Unsafe package path: {name!r}")
    return name


def tree_snapshot(app: Path) -> dict:
    """Inventory without following links; each portable link stays in this app."""
    if app.is_symlink() or not app.is_dir():
        raise PackageError("The root app must be a real directory")
    root = app.resolve(strict=True)
    records, folded = {}, set()
    pending = [(app, "")]
    while pending:
        path, relative = pending.pop()
        if relative:
            safe_relative(relative)
        normalized = unicodedata.normalize("NFC", relative).casefold()
        if normalized in folded:
            raise PackageError(f"Case/Unicode collision in app: {relative}")
        folded.add(normalized)
        mode = path.lstat().st_mode
        record = {"mode": stat.S_IMODE(mode)}
        if stat.S_ISLNK(mode):
            target = os.readlink(path)
            if not target or PurePosixPath(target).is_absolute() or "\\" in target or ":" in target or "\0" in target:
                raise PackageError(f"Non-portable symlink: {relative}")
            try:
                resolved = path.resolve(strict=True)
            except (OSError, RuntimeError) as error:
                raise PackageError(f"Broken/cyclic symlink: {relative}") from error
            if not resolved.is_relative_to(root):
                raise PackageError(f"Symlink escapes the app: {relative}")
            raw = os.fsencode(target)
            record.update(type="symlink", target=target, size=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        elif stat.S_ISDIR(mode):
            record["type"] = "directory"
            for child in sorted(path.iterdir(), key=lambda p: p.name, reverse=True):
                pending.append((child, f"{relative}/{child.name}" if relative else child.name))
        elif stat.S_ISREG(mode):
            record.update(type="file", size=path.stat().st_size, sha256=sha_file(path))
        else:
            raise PackageError(f"Unsupported filesystem object in app: {relative}")
        records[relative] = record
    return dict(sorted(records.items()))


def macho_slices(data: bytes, expected_platform: int) -> list[dict]:
    """Check every Mach-O slice, device platform and absence of code signatures."""
    fat = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
           b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    thin = {b"\xce\xfa\xed\xfe": ("<", False), b"\xfe\xed\xfa\xce": (">", False),
            b"\xcf\xfa\xed\xfe": ("<", True), b"\xfe\xed\xfa\xcf": (">", True)}
    if data[:4] in fat:
        endian, wide = fat[data[:4]]
        if len(data) < 8:
            raise PackageError("Truncated fat Mach-O header")
        count = struct.unpack_from(endian + "I", data, 4)[0]
        size = 32 if wide else 20
        if not 1 <= count <= 64 or 8 + count * size > len(data):
            raise PackageError("Invalid fat Mach-O slice table")
        result, ranges = [], []
        for index in range(count):
            fields = struct.unpack_from(endian + ("iiQQII" if wide else "iiIII"), data, 8 + index * size)
            cpu, offset, length = fields[0], fields[2], fields[3]
            if offset < 8 + count * size or length < 28 or offset + length > len(data):
                raise PackageError("Fat Mach-O slice exceeds file bounds")
            if any(offset < end and start < offset + length for start, end in ranges):
                raise PackageError("Overlapping Mach-O slices")
            ranges.append((offset, offset + length))
            part = data[offset:offset + length]
            if part[:4] not in thin:
                raise PackageError("Fat Mach-O must contain only thin slices")
            checked = macho_slices(part, expected_platform)
            if checked[0]["cpuType"] != cpu:
                raise PackageError("Fat and thin Mach-O CPU types disagree")
            result.extend(checked)
        return result
    if data[:4] not in thin:
        raise PackageError("Product executable is not Mach-O")
    endian, wide = thin[data[:4]]
    header_size = 32 if wide else 28
    if len(data) < header_size:
        raise PackageError("Truncated Mach-O header")
    fields = struct.unpack_from(endian + ("IiiIIIII" if wide else "IiiIIII"), data)
    cpu, file_type, count, size = fields[1], fields[3], fields[4], fields[5]
    if cpu not in {12, 0x0100000C, 0x0200000C} or file_type != 2:
        raise PackageError("Product must be an ARM device executable, not an Intel simulator or library")
    if count == 0 or count > 65536 or header_size + size > len(data):
        raise PackageError("Invalid Mach-O load-command bounds")
    cursor, found = header_size, []
    legacy = {0x25: 2, 0x30: 4}  # LC_VERSION_MIN_IPHONEOS / LC_VERSION_MIN_WATCHOS
    for _ in range(count):
        if cursor + 8 > header_size + size:
            raise PackageError("Truncated Mach-O load command")
        command, command_size = struct.unpack_from(endian + "II", data, cursor)
        if command_size < 8 or cursor + command_size > header_size + size:
            raise PackageError("Invalid Mach-O load-command size")
        if command == 0x1D:  # LC_CODE_SIGNATURE, including an ad-hoc signature
            raise PackageError("Product has a code-signature command; no signature will be stripped or replaced")
        if command == 0x32:  # LC_BUILD_VERSION
            if command_size < 24:
                raise PackageError("Truncated LC_BUILD_VERSION")
            found.append(struct.unpack_from(endian + "I", data, cursor + 8)[0])
        elif command in legacy:
            if command_size < 16:
                raise PackageError("Truncated legacy platform command")
            found.append(legacy[command])
        cursor += command_size
    if cursor != header_size + size or not found or any(value != expected_platform for value in found):
        raise PackageError(f"Mach-O is not the expected device platform {expected_platform}: {found}")
    return [{"cpuType": cpu, "platform": expected_platform, "codeSignature": "absent"}]


def product_records(read_bytes, exists) -> list[dict]:
    result, root_version = [], None
    for relative, identifier in IDS.items():
        prefix = relative + "/" if relative else ""
        info = plistlib.loads(read_bytes(prefix + "Info.plist"))
        expected = "WatchOS" if relative.startswith("Watch/") else "iPhoneOS"
        expected_dt = "watchos" if expected == "WatchOS" else "iphoneos"
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or safe_relative(executable) != executable or "/" in executable:
            raise PackageError(f"Invalid executable path: {relative}")
        if info.get("CFBundleIdentifier") != identifier:
            raise PackageError(f"Unexpected bundle ID: {relative}")
        if info.get("CFBundleSupportedPlatforms") != [expected] or info.get("DTPlatformName", expected_dt) != expected_dt:
            raise PackageError(f"Product is not a {expected} device build: {relative}")
        versions = (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
        if not all(isinstance(value, str) and value for value in versions):
            raise PackageError(f"Missing product versions: {relative}")
        if root_version is None:
            root_version = versions
        if versions != root_version:
            raise PackageError(f"Product version differs from phone: {relative}")
        for forbidden in ("_CodeSignature", "embedded.mobileprovision"):
            if exists(prefix + forbidden):
                raise PackageError(f"Signed/provisioned product found: {relative}/{forbidden}")
        executable_path = prefix + executable
        binary = read_bytes(executable_path)
        slices = macho_slices(binary, 4 if expected == "WatchOS" else 2)
        if relative == "Watch/PatrickFace.app" and info.get("WKCompanionAppBundleIdentifier") != IDS[""]:
            raise PackageError("Watch companion bundle identifier changed")
        result.append({"path": relative or ".", "bundleID": identifier, "version": versions[0],
                       "build": versions[1], "platform": expected, "executable": executable_path,
                       "executableSHA256": hashlib.sha256(binary).hexdigest(), "machOSlices": slices})
    return result


def entitlement_requirements() -> list[dict]:
    records = []
    for relative, template in ENTITLEMENT_TEMPLATES.items():
        data = (ROOT / template).read_bytes()
        parsed = plistlib.loads(data)
        if not isinstance(parsed, dict):
            raise PackageError(f"Invalid entitlement template: {template}")
        records.append({"product": relative or ".", "bundleID": IDS[relative], "templatePath": template,
                        "templateSHA256": hashlib.sha256(data).hexdigest(), "templateValues": parsed,
                        "requiredAppGroups": parsed.get("com.apple.security.application-groups", []),
                        "requiresHealthKit": parsed.get("com.apple.developer.healthkit") is True})
    return records


def verify_unsigned_ipa(ipa: Path, expected: dict) -> dict:
    prefix = "Payload/PatrickCompanion.app"
    payload_entries = {prefix + ("/" + name if name else ""): record for name, record in expected.items()}
    seen, folded, metadata = {}, set(), []
    with zipfile.ZipFile(ipa) as archive:
        for entry in archive.infolist():
            name = safe_relative(entry.filename[:-1] if entry.is_dir() else entry.filename)
            normalized = unicodedata.normalize("NFC", name).casefold()
            if normalized in folded:
                raise PackageError(f"Duplicate/colliding ZIP path: {name}")
            folded.add(normalized)
            if entry.flag_bits & 1:
                raise PackageError("Encrypted ZIP entries are not supported")
            unix_mode = entry.external_attr >> 16
            if stat.S_IFMT(unix_mode) not in {stat.S_IFDIR, stat.S_IFREG, stat.S_IFLNK}:
                raise PackageError(f"Missing/unsupported Unix object type in ZIP: {name}")
            kind = "directory" if stat.S_ISDIR(unix_mode) else "symlink" if stat.S_ISLNK(unix_mode) else "file"
            if entry.is_dir() != (kind == "directory"):
                raise PackageError(f"ZIP name and Unix object type disagree: {name}")
            if name == "Payload" and kind == "directory":
                continue
            if name.startswith("__MACOSX"):
                # ditto's resource metadata is allowed only for an actual payload
                # object. No arbitrary second payload or metadata symlink is legal.
                if name == "__MACOSX" and kind == "directory":
                    metadata.append(name); continue
                rest = name.removeprefix("__MACOSX/")
                if rest == name or kind == "symlink":
                    raise PackageError(f"Unsafe AppleDouble metadata: {name}")
                if kind == "directory":
                    if rest != "Payload" and rest not in payload_entries:
                        raise PackageError(f"Unrelated metadata directory: {name}")
                else:
                    path = PurePosixPath(rest)
                    target = str(path.with_name(path.name[2:])) if path.name.startswith("._") and len(path.name) > 2 else ""
                    if target != "Payload" and target not in payload_entries:
                        raise PackageError(f"Unrelated AppleDouble metadata: {name}")
                    if archive.read(entry)[:4] != b"\x00\x05\x16\x07":
                        raise PackageError(f"Invalid AppleDouble header: {name}")
                metadata.append(name); continue
            record = payload_entries.get(name)
            if record is None or kind != record["type"]:
                raise PackageError(f"Missing/unexpected payload object type: {name}")
            if stat.S_IMODE(unix_mode) != record["mode"]:
                raise PackageError(f"ZIP changed object permissions: {name}")
            if kind != "directory":
                digest = hashlib.sha256()
                with archive.open(entry) as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
                if entry.file_size != record["size"] or digest.hexdigest() != record["sha256"]:
                    raise PackageError(f"ZIP changed original bytes: {name}")
            seen[name] = entry
        if set(seen) != set(payload_entries):
            raise PackageError("ZIP omitted original app entries: " + ", ".join(sorted(set(payload_entries) - set(seen))[:8]))
        products = product_records(lambda name: archive.read(prefix + "/" + name),
                                   lambda name: prefix + "/" + name in seen)
        for product in products:
            executable = seen[prefix + "/" + product["executable"]]
            if not (executable.external_attr >> 16) & 0o111:
                raise PackageError(f"ZIP product executable lacks execute permission: {product['path']}")
    return {"products": products, "verifiedEntryCount": len(seen), "appleDoubleEntries": metadata,
            "allOriginalBytesIdentical": True, "permissionsAndSymlinksPreserved": True}


def package_unsigned(app: Path, output: Path) -> Path:
    """Create a verified re-signing input; never fake, remove or replace signing."""
    if platform.system() != "Darwin":
        raise PackageError("Unsigned IPA creation requires macOS ditto")
    before = tree_snapshot(app)
    products = product_records(lambda name: (app / name).read_bytes(), lambda name: (app / name).exists())
    entitlements = entitlement_requirements()
    for product in products:
        entry = before[product["executable"]]
        if entry["type"] != "file" or not entry["mode"] & 0o111:
            raise PackageError(f"Product executable lacks execute permission: {product['path']}")
    directory = output / "Unsigned"
    directory.mkdir(exist_ok=False)
    ipa = directory / "PatrickCompanion-unsigned.ipa"
    pending = directory / "PatrickCompanion-unsigned.ipa.pending"
    manifest_path = directory / "PatrickCompanion-unsigned.manifest.json"
    # ditto preserves links and modes; never use a Python copy/ZIP fallback.
    # Apple: https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
    with tempfile.TemporaryDirectory(prefix="patrick-unsigned-stage-", dir=output) as temporary:
        payload = Path(temporary) / "Payload"
        payload.mkdir()
        copied = payload / "PatrickCompanion.app"
        subprocess.run(["/usr/bin/ditto", "--rsrc", str(app), str(copied)], check=True)
        if tree_snapshot(app) != before or tree_snapshot(copied) != before:
            raise PackageError("Source changed during copy or ditto did not preserve every file/link/mode")
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--rsrc", "--sequesterRsrc", "--keepParent", str(payload), str(pending)], check=True)
        verification = verify_unsigned_ipa(pending, before)
        if tree_snapshot(app) != before or tree_snapshot(copied) != before:
            raise PackageError("Source or staging tree changed during ZIP creation")
    if entitlement_requirements() != entitlements:
        raise PackageError("Source entitlement templates changed during packaging")
    manifest = {"schemaVersion": 1, "createdAt": datetime.now(timezone.utc).isoformat(),
                "status": "verified-unsigned-resigning-input", "signed": False, "directlyInstallable": False,
                "purpose": "External re-signing input only. Not a signed or directly installable IPA.",
                "sourceApp": str(app.resolve()), "ipa": ipa.name, "ipaBytes": pending.stat().st_size,
                "ipaSHA256": sha_file(pending), "products": products, "verification": verification,
                "entitlementRequirements": entitlements,
                "actualSigning": {"productMachOCodeSignature": "absent", "codesignInspection": "unchecked",
                                  "embeddedProvisioningProfiles": "absent", "signedEntitlements": "absent"},
                "resigningRequirements": [
                    "Source entitlement templates are reference requirements; they were not applied or injected into this unsigned package.",
                    "After Sideloadly or any other tool re-signs, inspect all four actual codesign entitlements and provisioning profiles.",
                    "Verify App Groups on all four products and HealthKit on the Watch app against the signing account's capabilities.",
                    "Free-account eligibility and a re-signing tool's preservation of these capabilities are not established by this package.",
                    "No entitlement, extension, Watch product, bundle identifier or artwork was removed to make packaging succeed."],
                "sourceEntries": before}
    pending.rename(ipa)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (directory / "PatrickCompanion-unsigned.ipa.sha256").write_text(f"{manifest['ipaSHA256']}  {ipa.name}\n", encoding="utf-8")
    print(f"Unsigned IPA for re-signing only (NOT directly installable): {ipa}")
    print(f"Unsigned IPA verification manifest: {manifest_path}")
    return ipa


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--signing-config", type=Path, help="Explicit local JSON; omit for unsigned archive")
    mode.add_argument("--package-unsigned", action="store_true", help="Create a verified unsigned IPA for external re-signing, not direct installation")
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("A Mac with Xcode is required; nothing built.")
    if not re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", args.build_number):
        parser.error("Invalid build number")
    config = None
    if args.signing_config:
        config = json.loads(args.signing_config.read_text(encoding="utf-8"))
        if not re.fullmatch(r"[A-Z0-9]{10}", config.get("teamID", "")):
            parser.error("Set your actual Team ID; the example is not runnable")
        if set(config.get("profiles", {})) != set(IDS.values()):
            parser.error("All four exact product profiles are required")
        if any(not isinstance(v, str) or not v or v.startswith("YOUR_") for v in config["profiles"].values()):
            parser.error("Replace profile-name placeholders with profiles installed on this Mac")
        if config.get("method") not in {"app-store-connect", "release-testing", "debugging"}:
            parser.error("Use a current Xcode export method: app-store-connect, release-testing or debugging")
        if config.get("signingCertificate") not in {"Apple Distribution", "Apple Development"}:
            parser.error("Choose Apple Distribution or Apple Development")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="patrick-device-archive-"))
    if output.exists() and any(output.iterdir()):
        parser.error("Output must be empty, to preserve any previous archive")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "PatrickCompanion.xcarchive"
    subprocess.run(["xcodebuild", "-version"], check=True)
    subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], check=True)
    subprocess.run(["xcrun", "--sdk", "watchos", "--show-sdk-path"], check=True)
    command = ["xcodebuild", "-workspace", str(ROOT / "iOSCompanion/PatrickFaceSuite.xcworkspace"),
        "-scheme", "PatrickCompanion", "-configuration", "Release", "-destination", "generic/platform=iOS",
        "-archivePath", str(archive), "-derivedDataPath", str(output / "DerivedData"),
        f"CURRENT_PROJECT_VERSION={args.build_number}"]
    if config:
        command += [f"DEVELOPMENT_TEAM={config['teamID']}", "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={config['signingCertificate']}"]
        command += [f"{key}={config['profiles'][identifier]}" for key, identifier in zip(PROFILE_KEYS, IDS.values())]
    else:
        command += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM="]
    subprocess.run(command + ["archive"], check=True)
    app = archive / "Products/Applications/PatrickCompanion.app"
    verify(app)
    if (app / "PlugIns/PatrickFieldTestNotification.appex").exists():
        raise PackageError(
            "Field-test notification extension must stay out of the default archive"
        )
    if config:
        for relative in IDS:
            subprocess.run(["codesign", "--verify", "--strict", str(app / relative)], check=True)
        options = {"method": config["method"], "destination": "export", "teamID": config["teamID"],
            "signingStyle": "manual", "signingCertificate": config["signingCertificate"],
            "provisioningProfiles": config["profiles"], "manageAppVersionAndBuildNumber": False,
            "uploadSymbols": False}
        if config["method"] == "app-store-connect":
            options["testFlightInternalTestingOnly"] = bool(config.get("testFlightInternalTestingOnly", True))
        plist = output / "ExportOptions.plist"
        plist.write_bytes(plistlib.dumps(options))
        subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
            "-exportPath", str(output / "Export"), "-exportOptionsPlist", str(plist)], check=True)
        print("Signed archive/export completed locally. No upload or installation performed.")
    else:
        print("Unsigned device archive checked. It cannot be installed or submitted.")
        if args.package_unsigned:
            package_unsigned(app, output)
    print(f"Output: {output}")

if __name__ == "__main__":
    main()
