"""Bundle safety regressions in checked, task-owned temporary directories."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from sync_experience_bundle import MANAGED, ROOT, synchronize


class ExperienceSyncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="patrick-experience-sync-test-")
        self.root = Path(self.directory.name).resolve()
        self.source = self.root / "experience"
        (self.source / "audio").mkdir(parents=True)
        for original in (ROOT / "experience/audio").iterdir():
            if original.suffix in {".wav", ".json"}:
                shutil.copyfile(original, self.source / "audio" / original.name)
        self.contract = {"schemaVersion": 1, "settings": {"soundEnabled": False},
                         "themesPath": "experience/themes.json", "soundsPath": "experience/audio/manifest.json",
                         "clockPath": "experience/clock/manifest.json",
                         "clockContract": {"status": "awaiting-generated-art"}}
        (self.source / "contract.json").write_text(json.dumps(self.contract), encoding="utf-8")
        (self.source / "themes.json").write_text('{"outfits": []}', encoding="utf-8")
        (self.root / "animation").mkdir()
        (self.root / "animation/catalog.json").write_text('{"clips": []}', encoding="utf-8")

    def tearDown(self):
        if (self.root.parent != Path(tempfile.gettempdir()).resolve()
                or not self.root.name.startswith("patrick-experience-sync-test-")):
            raise RuntimeError("Refusing cleanup outside this test's temporary directory.")
        self.directory.cleanup()

    def test_read_only_freshness_and_byte_exact_copy_to_two_separate_targets(self):
        for target, folder in (("watch", "PatrickFace/Experience"), ("iphone", "iOSCompanion/PatrickCompanion/Experience")):
            destination = self.root / folder
            report = synchronize(self.root, check=True, target=target)
            self.assertEqual(report["status"], "OUT_OF_DATE")
            self.assertFalse(destination.exists())
            self.assertEqual(synchronize(self.root, target=target)["status"], "SYNCED")
            self.assertEqual((destination / "audio/feed.wav").read_bytes(), (self.source / "audio/feed.wav").read_bytes())
            self.assertEqual(synchronize(self.root, check=True, target=target)["status"], "UP_TO_DATE")

    def test_unmanaged_conflict_and_managed_local_changes_are_preserved(self):
        destination = self.root / "PatrickFace/Experience"
        destination.mkdir(parents=True)
        contract = destination / "contract.json"
        contract.write_bytes(b"user content")
        with self.assertRaisesRegex(ValueError, "unmanaged"):
            synchronize(self.root)
        self.assertFalse((destination / "audio").exists())
        self.assertEqual(contract.read_bytes(), b"user content")
        contract.write_bytes((self.source / "contract.json").read_bytes())
        synchronize(self.root)
        contract.write_bytes(b"local edit")
        with self.assertRaisesRegex(ValueError, "local edits"):
            synchronize(self.root)
        self.assertEqual(contract.read_bytes(), b"local edit")

    def test_hash_mismatch_or_traversal_prevents_any_destination_write(self):
        manifest = self.source / "audio/manifest.json"
        original = manifest.read_bytes()
        data = json.loads(original)
        data["cues"][0]["sha256"] = "0" * 64
        manifest.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "SHA mismatch"):
            synchronize(self.root)
        self.assertFalse((self.root / "PatrickFace").exists())
        manifest.write_bytes(original)
        (self.source / "themes.json").write_text('{"outfits":[],"layer":{"path":"experience/../outside.png"}}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unsafe relative path"):
            synchronize(self.root)

    def test_clock_assets_copy_without_editing_and_unknown_target_files_remain(self):
        clock = self.source / "clock"
        clock.mkdir()
        raw = (ROOT / "experience/clock/layers-v1.png").read_bytes()
        for name in ("layers-v1.png", "manifest.json", "regions-v1.json"):
            shutil.copyfile(ROOT / "experience/clock" / name, clock / name)
        synchronize(self.root)
        destination = self.root / "PatrickFace/Experience"
        self.assertEqual((destination / "clock/layers-v1.png").read_bytes(), raw)
        unknown = destination / "keep-user-file.txt"
        unknown.write_bytes(b"keep")
        synchronize(self.root)
        self.assertEqual(unknown.read_bytes(), b"keep")
        self.assertTrue((destination / MANAGED).is_file())

    def test_invalid_clock_pivot_prevents_the_entire_copy(self):
        clock = self.source / "clock"
        clock.mkdir()
        for name in ("layers-v1.png", "manifest.json", "regions-v1.json"):
            shutil.copyfile(ROOT / "experience/clock" / name, clock / name)
        manifest = json.loads((clock / "manifest.json").read_text(encoding="utf-8-sig"))
        manifest["hands"][0]["pivotPixels"] = [0, 0]
        (clock / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Declared hand geometry"):
            synchronize(self.root)
        self.assertFalse((self.root / "PatrickFace").exists())

    def test_required_theme_missing_is_not_silently_called_usable(self):
        self.contract["themesPath"] = "experience/not-generated.json"
        (self.source / "contract.json").write_text(json.dumps(self.contract), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Required source resource is missing"):
            synchronize(self.root)
        self.assertFalse((self.root / "PatrickFace").exists())

    def test_theme_pointing_at_nonexistent_action_fails_before_copy(self):
        (self.source / "themes.json").write_text(json.dumps({"outfits": [
            {"id": "chef", "clipId": "missing-feed", "actions": {"feed": "missing-feed"}}
        ]}), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "unavailable main animation"):
            synchronize(self.root)
        self.assertFalse((self.root / "PatrickFace").exists())

    def test_calendar_must_match_the_exact_existing_web_source(self):
        (self.root / "preview").mkdir()
        shutil.copyfile(ROOT / "preview/holiday-calendar.js", self.root / "preview/holiday-calendar.js")
        shutil.copyfile(ROOT / "preview/pet-core.js", self.root / "preview/pet-core.js")
        shutil.copyfile(ROOT / "experience/calendar.json", self.source / "calendar.json")
        self.contract["calendarPath"] = "experience/calendar.json"
        (self.source / "contract.json").write_text(json.dumps(self.contract), encoding="utf-8")
        synchronize(self.root)
        self.assertEqual((self.root / "PatrickFace/Experience/calendar.json").read_bytes(),
                         (self.source / "calendar.json").read_bytes())
        web_data = self.root / "preview/holiday-calendar.js"
        web_data.write_bytes(web_data.read_bytes() + b"\n// changed source\n")
        with self.assertRaisesRegex(ValueError, "calendar is stale"):
            synchronize(self.root)


if __name__ == "__main__":
    unittest.main()
