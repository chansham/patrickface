"""Safety/freshness regressions in verified temporary folders; never edit art."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from sync_animation_bundle import MANAGED, ROOT, confined_path, relative_parts, synchronize


class BundleSyncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="patrick-animation-sync-test-")
        self.root = Path(self.directory.name).resolve()
        self.assertTrue(self.root.is_relative_to(Path(tempfile.gettempdir()).resolve()))
        self.source = self.root / "animation"
        self.source.mkdir()
        (self.source / "yawn-v1").mkdir()
        original = ROOT / "animation/yawn-v1/atlas-eyes-v2.png"
        shutil.copyfile(original, self.source / "yawn-v1/atlas.png")
        self.catalog = {
            "master": {"id": "test", "anchorNormalized": [0.5, 0.88], "scale": 1, "cellAspect": 1},
            "clips": [{"id": "yawn", "title": "Yawn", "category": "once", "status": "direction-accepted-rough",
                       "triggerKinds": ["manual"], "atlas": "animation/yawn-v1/atlas.png", "width": 1774,
                       "height": 887, "columns": 4, "rows": 2, "frameCount": 8, "durationsMs": [100] * 8,
                       "sha256": hashlib.sha256(original.read_bytes()).hexdigest()}],
            "plannedClips": ["not-produced"],
        }
        self.save_catalog()
        self.destination = self.root / "PatrickFace/Animation"

    def tearDown(self):
        # The only recursive cleanup is this invocation's known temporary tree.
        resolved = self.root.resolve()
        if resolved.parent != Path(tempfile.gettempdir()).resolve() or not resolved.name.startswith("patrick-animation-sync-test-"):
            raise RuntimeError("Refusing cleanup outside the known temporary test folder.")
        self.directory.cleanup()

    def save_catalog(self):
        (self.source / "catalog.json").write_text(json.dumps(self.catalog), encoding="utf-8")

    def test_check_creates_nothing_and_copy_is_byte_exact(self):
        report = synchronize(self.root, check=True)
        self.assertEqual(report["status"], "OUT_OF_DATE")
        self.assertFalse(self.destination.exists())
        report = synchronize(self.root)
        self.assertEqual(report["status"], "SYNCED")
        self.assertEqual((self.source / "catalog.json").read_bytes(), (self.destination / "catalog.json").read_bytes())
        self.assertEqual((self.source / "yawn-v1/atlas.png").read_bytes(), (self.destination / "yawn-v1/atlas.png").read_bytes())
        self.assertEqual(synchronize(self.root, check=True)["status"], "UP_TO_DATE")
        self.assertEqual(report["availableClipIds"], ["yawn"])
        self.assertEqual(report["plannedClipIds"], ["not-produced"])

    def test_unmanaged_conflict_prevents_all_copies(self):
        self.destination.mkdir(parents=True)
        (self.destination / "catalog.json").write_bytes(b"user content")
        with self.assertRaisesRegex(ValueError, "unmanaged"):
            synchronize(self.root)
        self.assertEqual((self.destination / "catalog.json").read_bytes(), b"user content")
        self.assertFalse((self.destination / "yawn-v1").exists())
        self.assertFalse((self.destination / MANAGED).exists())

    def test_owned_catalog_updates_but_local_edits_are_protected(self):
        synchronize(self.root)
        self.catalog["version"] = 2
        self.save_catalog()
        self.assertEqual(synchronize(self.root)["status"], "SYNCED")
        (self.destination / "catalog.json").write_bytes(b"local edit")
        self.catalog["version"] = 3
        self.save_catalog()
        with self.assertRaisesRegex(ValueError, "local edits"):
            synchronize(self.root)
        self.assertEqual((self.destination / "catalog.json").read_bytes(), b"local edit")

    def test_unknown_files_and_retired_managed_files_are_not_deleted(self):
        synchronize(self.root)
        unknown = self.destination / "keep-me.txt"
        unknown.write_bytes(b"keep")
        # Reuse the same bytes under a new source path: old resource stays archived.
        shutil.copyfile(self.source / "yawn-v1/atlas.png", self.source / "yawn-v1/next.png")
        self.catalog["clips"][0]["atlas"] = "animation/yawn-v1/next.png"
        self.save_catalog()
        report = synchronize(self.root)
        self.assertIn("yawn-v1/atlas.png", report["retainedPreviouslyManaged"])
        self.assertTrue((self.destination / "yawn-v1/atlas.png").is_file())
        self.assertEqual(unknown.read_bytes(), b"keep")

    def test_iphone_target_is_separate_and_read_only_check_creates_nothing(self):
        phone = self.root / "iOSCompanion/PatrickCompanion/Animation"
        self.assertEqual(synchronize(self.root, check=True, target="iphone")["status"], "OUT_OF_DATE")
        self.assertFalse(phone.exists())
        self.assertEqual(synchronize(self.root, target="iphone")["status"], "SYNCED")
        self.assertEqual((phone / "catalog.json").read_bytes(), (self.source / "catalog.json").read_bytes())
        self.assertFalse(self.destination.exists())
        with self.assertRaisesRegex(ValueError, "Unknown bundle target"):
            synchronize(self.root, target="../outside")

    def test_invalid_hash_stops_before_destination_exists(self):
        self.catalog["clips"][0]["sha256"] = "0" * 64
        self.save_catalog()
        with self.assertRaisesRegex(ValueError, "validation failed"):
            synchronize(self.root)
        self.assertFalse(self.destination.exists())

    def test_paths_cannot_escape_or_use_other_source_trees(self):
        for value in ("../x", "/x", "C:/x", "a\\b", "a//b", "a/./b"):
            with self.assertRaises(ValueError):
                relative_parts(value)
        self.catalog["clips"][0]["atlas"] = "preview/assets/old.png"
        self.save_catalog()
        with self.assertRaisesRegex(ValueError, "ROOT/animation"):
            synchronize(self.root)
        self.assertFalse(self.destination.exists())

    def test_contour_metadata_is_copied_and_its_hash_is_required(self):
        original = json.loads((ROOT / "animation/yawn-v1/regions-v1.json").read_text(encoding="utf-8"))
        original["source"]["path"] = "animation/yawn-v1/atlas.png"
        payload = json.dumps(original).encode("utf-8")
        source_metadata = self.source / "yawn-v1/regions-v1.json"
        source_metadata.write_bytes(payload)
        clip = self.catalog["clips"][0]
        clip["anchorNormalized"] = original["canvas"]["anchorNormalized"]
        clip["frameRegions"] = {"path": "animation/yawn-v1/regions-v1.json", "version": 1,
                                "sha256": hashlib.sha256(payload).hexdigest()}
        self.save_catalog()
        report = synchronize(self.root)
        self.assertEqual(report["fileCount"], 3)
        self.assertEqual((self.destination / "yawn-v1/regions-v1.json").read_bytes(), payload)
        self.assertEqual(synchronize(self.root, check=True)["status"], "UP_TO_DATE")
        source_metadata.write_bytes(payload + b" ")
        with self.assertRaisesRegex(ValueError, "Contour metadata SHA"):
            synchronize(self.root)
        self.assertEqual((self.destination / "yawn-v1/regions-v1.json").read_bytes(), payload)

    def test_symlink_redirect_is_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = self.source / "redirect"
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("This Windows account cannot create a symbolic link.")
        with self.assertRaises(ValueError):
            confined_path(self.source, "redirect/atlas.png")


if __name__ == "__main__":
    unittest.main()
