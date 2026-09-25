"""Sync approved runtime layers into the watchOS asset catalog."""

from __future__ import annotations

import json
import shutil
from pathlib import Path


ROOT = Path(r"<PROJECT_DIR>")
SOURCE = ROOT / "preview" / "assets"
CATALOG = ROOT / "PatrickFace" / "Assets.xcassets"

ASSETS = {
    "season1-body-normal": SOURCE / "season1-body-normal.png",
    "season1-hour-arm": SOURCE / "season1-hour-arm.png",
    "season1-minute-arm": SOURCE / "season1-minute-arm.png",
    "season1-3d-body": SOURCE / "season1-3d-body.png",
    "season1-3d-arm": SOURCE / "season1-3d-arm.png",
}

for name, source in ASSETS.items():
    if not source.exists():
        raise FileNotFoundError(source)

    destination = CATALOG / f"{name}.imageset"
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / f"{name}.png"
    shutil.copy2(source, target)

    contents = {
        "images": [{"filename": target.name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (destination / "Contents.json").write_text(
        json.dumps(contents, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"synced {name}: {target.stat().st_size} bytes")
