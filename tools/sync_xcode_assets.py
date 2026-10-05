"""Read-only check of retained native assets; the old preview sync is retired.

The web preview is being rebuilt with an expression/pose atlas. Its artwork is
not interchangeable with the five historical watch layers below. Keep these
native copies until a separately reviewed native animation migration replaces
them. This compatibility entry point never copies or creates files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "PatrickFace" / "Assets.xcassets"
READ_ONLY = True
LIFECYCLE = "retired-sync-retained-native-assets"
RETAINED_ASSETS = (
    "season1-body-normal",
    "season1-hour-arm",
    "season1-minute-arm",
    "season1-3d-body",
    "season1-3d-arm",
)


def inspect_retained_assets() -> list[dict[str, object]]:
    records = []
    for name in RETAINED_ASSETS:
        image_set = CATALOG / f"{name}.imageset"
        image = image_set / f"{name}.png"
        contents = json.loads((image_set / "Contents.json").read_text(encoding="utf-8"))
        filenames = [item.get("filename") for item in contents.get("images", []) if item.get("filename")]
        if filenames != [image.name]:
            raise ValueError(f"Retained native asset metadata is inconsistent: {name}")
        data = image.read_bytes()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Retained native asset is not a PNG: {name}")
        records.append({
            "name": name,
            "path": image.relative_to(ROOT).as_posix(),
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", action="store_true", help="Report retirement status and retained native files as JSON.")
    args = parser.parse_args()
    try:
        records = inspect_retained_assets()
    except (OSError, ValueError) as error:
        parser.exit(1, f"Retained native asset check failed: {error}\n")
    if args.status:
        print(json.dumps({
            "lifecycle": LIFECYCLE,
            "readOnly": READ_ONLY,
            "currentApproval": False,
            "newAnimationIntegrated": False,
            "assets": records,
        }, indent=2))
    else:
        print(f"PASS: {len(records)} retained native layers are present. Read-only; no assets synced.")
        print("Preview sync is retired. These historical layers are not the new expression/pose animation.")


if __name__ == "__main__":
    main()
