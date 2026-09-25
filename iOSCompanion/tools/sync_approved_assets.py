#!/usr/bin/env python3
"""Copy approved watch artwork into the companion asset catalog.

The source catalog is read-only. Existing destination files are replaced only
when --write is passed; --check verifies provenance without changing files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "PatrickFace" / "Assets.xcassets"
DESTINATION = ROOT / "Resources" / "Assets.xcassets"

APPROVED_ASSETS = {
    "season1-body-normal": "season1-body-normal.png",
    "season1-hour-arm": "season1-hour-arm.png",
    "season1-minute-arm": "season1-minute-arm.png",
    "season1-3d-body": "season1-3d-body.png",
    "season1-3d-arm": "season1-3d-arm.png",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def build_catalog() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    write_json(
        DESTINATION / "Contents.json",
        {"info": {"author": "xcode", "version": 1}},
    )

    for asset_name, filename in APPROVED_ASSETS.items():
        source = SOURCE / f"{asset_name}.imageset" / filename
        destination_dir = DESTINATION / f"{asset_name}.imageset"
        destination_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination_dir / filename)
        write_json(
            destination_dir / "Contents.json",
            {
                "images": [{"filename": filename, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            },
        )

    app_icon_source = SOURCE / "AppIcon.appiconset" / "AppIcon.png"
    app_icon_dir = DESTINATION / "AppIcon.appiconset"
    app_icon_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(app_icon_source, app_icon_dir / "AppIcon.png")
    write_json(
        app_icon_dir / "Contents.json",
        {
            "images": [
                {
                    "filename": "AppIcon.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    write_json(
        DESTINATION / "AccentColor.colorset" / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {
                            "alpha": "1.000",
                            "blue": "0.769",
                            "green": "0.659",
                            "red": "0.969",
                        },
                    },
                    "idiom": "universal",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    write_json(
        DESTINATION / "LaunchBackground.colorset" / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {
                            "alpha": "1.000",
                            "blue": "0.000",
                            "green": "0.000",
                            "red": "0.000",
                        },
                    },
                    "idiom": "universal",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    provenance = {
        "source": "../PatrickFace/Assets.xcassets",
        "policy": "Byte-for-byte copies of approved source PNGs; runtime overlays are derived in SwiftUI.",
        "files": {},
    }
    copied_files = {
        **{
            f"{name}.imageset/{filename}": SOURCE
            / f"{name}.imageset"
            / filename
            for name, filename in APPROVED_ASSETS.items()
        },
        "AppIcon.appiconset/AppIcon.png": app_icon_source,
    }
    for relative, source in copied_files.items():
        provenance["files"][relative] = {
            "source": str(source.relative_to(ROOT.parent)).replace("\\", "/"),
            "sha256": digest(source),
        }
    write_json(ROOT / "Resources" / "asset-provenance.json", provenance)


def check_catalog() -> list[str]:
    errors: list[str] = []
    for asset_name, filename in APPROVED_ASSETS.items():
        source = SOURCE / f"{asset_name}.imageset" / filename
        destination = DESTINATION / f"{asset_name}.imageset" / filename
        if not source.is_file():
            errors.append(f"missing approved source: {source}")
        elif not destination.is_file():
            errors.append(f"missing copied asset: {destination}")
        elif digest(source) != digest(destination):
            errors.append(f"asset differs from approved source: {destination}")

    icon_source = SOURCE / "AppIcon.appiconset" / "AppIcon.png"
    icon_destination = DESTINATION / "AppIcon.appiconset" / "AppIcon.png"
    if not icon_destination.is_file() or digest(icon_source) != digest(icon_destination):
        errors.append("iOS app icon does not match the approved Patrick icon")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write",
        action="store_true",
        help="create or refresh the companion asset catalog",
    )
    args = parser.parse_args()

    if args.write:
        build_catalog()

    errors = check_catalog()
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1
    print("PASS: approved Patrick asset copies match their watch-project sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
