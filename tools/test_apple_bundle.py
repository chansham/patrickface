"""Packaging verifier regression tests. These do not compile Apple source."""
from pathlib import Path
import hashlib
import json
import plistlib
import tempfile
import unittest
from check_apple_bundle import IDS, verify

class AppleBundleChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = Path(self.temp.name) / "PatrickCompanion.app"
        for relative, identifier in IDS.items():
            folder = self.app / relative
            folder.mkdir(parents=True)
            info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "program", "CFBundleVersion": "8", "CFBundleShortVersionString": "1.0"}
            if relative == "Watch/PatrickFace.app":
                info.update(WKCompanionAppBundleIdentifier=IDS[""], WKWatchOnly=False,
                            WKRunsIndependentlyOfCompanionApp=True, NSHealthShareUsageDescription="Read on request")
            (folder / "Info.plist").write_bytes(plistlib.dumps(info))
            (folder / "program").write_bytes(b"test-only fake executable")
        for product in [self.app, self.app / "Watch/PatrickFace.app"]:
            for name in ["Animation", "Experience"]:
                folder = product / name; folder.mkdir()
                (folder / "sample.json").write_bytes(b"{}")
                manifest = {"files": [{"destination": "sample.json", "sha256": hashlib.sha256(b"{}").hexdigest(), "active": True}]}
                (folder / "managed-assets.json").write_text(json.dumps(manifest), encoding="utf-8")
    def tearDown(self):
        self.temp.cleanup()
    def test_all_four_products_required(self):
        verify(self.app)
        (self.app / "Watch/PatrickFace.app/PlugIns/PatrickFaceComplications.appex/program").unlink()
        with self.assertRaises(AssertionError): verify(self.app)
    def test_modified_bundle_asset_rejected(self):
        (self.app / "Watch/PatrickFace.app/Animation/sample.json").write_bytes(b"wrong")
        with self.assertRaises(AssertionError): verify(self.app)
    def test_version_mismatch_rejected(self):
        path = self.app / "Watch/PatrickFace.app/Info.plist"
        value = plistlib.loads(path.read_bytes()); value["CFBundleVersion"] = "1"
        path.write_bytes(plistlib.dumps(value))
        with self.assertRaises(AssertionError): verify(self.app)

if __name__ == "__main__": unittest.main(verbosity=2)
