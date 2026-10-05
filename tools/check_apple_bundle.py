"""Check an actual built iPhone .app/archive payload, not merely project text."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib

IDS = {
    "": "com.chans.patrickface.companion",
    "PlugIns/PatrickWidgets.appex": "com.chans.patrickface.companion.widgets",
    "Watch/PatrickFace.app": "com.chans.patrickface.companion.watchkitapp",
    "Watch/PatrickFace.app/PlugIns/PatrickFaceComplications.appex": "com.chans.patrickface.companion.watchkitapp.complications",
}

def verify(app: Path) -> None:
    root_info = plistlib.loads((app / "Info.plist").read_bytes())
    for relative, identifier in IDS.items():
        product = app / relative
        info = plistlib.loads((product / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == identifier, f"Wrong bundle ID: {relative}"
        assert (product / info["CFBundleExecutable"]).is_file(), f"Missing executable: {relative}"
        for key in ["CFBundleVersion", "CFBundleShortVersionString"]:
            assert info[key] == root_info[key], f"Version mismatch: {relative}/{key}"
    watch = app / "Watch/PatrickFace.app"
    info = plistlib.loads((watch / "Info.plist").read_bytes())
    assert info["WKCompanionAppBundleIdentifier"] == IDS[""]
    assert info.get("WKWatchOnly") is False
    assert info.get("WKRunsIndependentlyOfCompanionApp") is True
    assert info.get("NSHealthShareUsageDescription"), "Missing HealthKit read purpose"
    for product in [app, watch]:
        for folder in ["Animation", "Experience"]:
            directory = product / folder
            manifest = json.loads((directory / "managed-assets.json").read_text(encoding="utf-8"))
            records = manifest.get("files", manifest.get("assets", []))
            assert records, f"Missing managed assets: {product.name}/{folder}"
            if isinstance(records, dict):
                records = list(records.values())
            for record in records:
                if record.get("active") is False:
                    continue
                relative = record["destination"]
                target = directory / relative
                assert target.resolve().is_relative_to(directory.resolve()), "Unsafe asset path"
                assert hashlib.sha256(target.read_bytes()).hexdigest() == record["sha256"], f"Asset mismatch: {relative}"
    print("PASS: iPhone + widget + embedded Watch + complication, versions and bundled asset SHA.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    verify(args.app)
