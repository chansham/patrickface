#!/usr/bin/env python3
"""Read-only checks for hashed clock art, contour ownership and hand geometry."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from PIL import Image
from frame_region_contract import read_regions
from sync_animation_bundle import confined_path, relative_parts

ROOT = Path(__file__).resolve().parents[1]


def validate(project_root: Path = ROOT) -> dict:
    project_root = project_root.resolve()
    base = project_root / "experience/clock"
    if base.resolve() != base:
        raise ValueError("Clock source directory must not redirect.")
    manifest = json.loads(confined_path(base, "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest.get("schemaVersion") != 1:
        raise ValueError("Unsupported clock schema.")
    source = manifest["source"]
    for reference in (source, manifest["frameRegions"]):
        parts = relative_parts(reference["path"])
        if parts[:2] != ("experience", "clock"):
            raise ValueError("Clock source references must remain in experience/clock/.")
        path = confined_path(base, "/".join(parts[2:]))
        if hashlib.sha256(path.read_bytes()).hexdigest() != reference["sha256"]:
            raise ValueError("Clock source or sidecar SHA mismatch.")
    with Image.open(project_root / source["path"]) as image:
        if image.format != "PNG" or image.size != (source["width"], source["height"]) or "A" not in image.getbands():
            raise ValueError("Clock source format or dimensions are invalid.")
        alpha = image.getchannel("A")
    clip = {"atlas": source["path"], "sha256": source["sha256"], "width": source["width"],
            "height": source["height"], "columns": 3, "rows": 1,
            "anchorNormalized": manifest["canvas"]["anchorNormalized"],
            "frameRegions": manifest["frameRegions"]}
    read_regions(clip, project_root, alpha)
    data = json.loads((project_root / manifest["frameRegions"]["path"]).read_text(encoding="utf-8-sig"))
    if manifest["canvas"] != data["canvas"]:
        raise ValueError("Clock canvas differs from contour metadata.")
    frames = data["frames"]
    body = manifest["body"]
    if body["regionIndex"] != 0 or body["anchorPixels"] != data["canvas"]["anchorPixels"]:
        raise ValueError("Body must use the complete first contour and its anchor.")
    if {hand["id"] for hand in manifest["hands"]} != {"hour", "minute"} or len(manifest["hands"]) != 2:
        raise ValueError("Exactly two named time hands are required.")
    if {hand["regionIndex"] for hand in manifest["hands"]} != {1, 2}:
        raise ValueError("Clock arms must use separate short/long source contours.")
    stage = manifest["layout"]["coordinateSize"]
    stage_pivot = manifest["layout"]["pivot"]
    if any(not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0
           for value in [*stage, body["pixelScale"], *[hand["displayLength"] for hand in manifest["hands"]]]):
        raise ValueError("Invalid stage dimensions or shared layer scales.")
    warnings, hands = [], []

    def contains(frame: dict, x: int, y: int) -> bool:
        return any(row[0] == y and any(left <= x < right for left, right in zip(row[1::2], row[2::2]))
                   for row in frame["rows"])

    for hand in manifest["hands"]:
        frame = frames[hand["regionIndex"]]
        px, py = hand["pivotPixels"]
        tipx, tipy = hand["tipPixels"]
        tx, ty = frame["translation"]
        length = math.hypot(tipx - px, tipy - py)
        direction = math.degrees(math.atan2(tipy - py, tipx - px))
        if abs(length - hand["lengthPixels"]) > .00001 or abs(direction - hand["sourceDirectionDegrees"]) > .00001:
            raise ValueError(f"{hand['id']}: Declared hand geometry does not match pivot/tip.")
        for label, x, y in (("pivot", px, py), ("tip", tipx, tipy)):
            sx, sy = x - tx, y - ty
            if not isinstance(sx, int) or not isinstance(sy, int) or not contains(frame, sx, sy):
                raise ValueError(f"{hand['id']}: {label} must sit on its actual source silhouette.")
            if alpha.getpixel((sx, sy)) < 128:
                warnings.append(f"{hand['id']}: {label} is on a weak-alpha edge; review registration.")
        radius = 0.0
        for row in frame["rows"]:
            y = row[0] + ty
            for x in [*row[1::2], *[right - 1 for right in row[2::2]]]:
                radius = max(radius, math.hypot(x + tx - px, y - py))
        display_radius = radius * hand["displayLength"] / length
        if any(stage_pivot[axis] - display_radius < 0 or stage_pivot[axis] + display_radius > stage[axis] for axis in (0, 1)):
            warnings.append(f"{hand['id']}: Some preserved faint pixels may leave the stage at certain clock angles.")
        hands.append({"id": hand["id"], "regionIndex": hand["regionIndex"],
                      "pivotOnSource": True, "tipOnSource": True,
                      "sourceLengthPixels": length, "maximumRotatedDisplayRadius": round(display_radius, 3)})
    if any(frame["diagnostics"]["coreSourceEdgeTouches"] for frame in frames):
        warnings.append("A strong source contour touches the source PNG edge.")
    if manifest.get("rules", {}).get("primaryDigitalTime") is not True:
        raise ValueError("Digital time must remain the primary time display.")
    return {"status": "PASS", "sourceSha256": source["sha256"], "contours": 3,
            "sourcePixelsAssignedExactlyOnce": True, "hands": hands, "warnings": warnings,
            "artApproved": False, "scope": "Source pixels, hashes and geometry; visual joint/face overlap and live clock rendering require review."}


if __name__ == "__main__":
    try:
        result = validate()
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        result = {"status": "FAIL", "error": str(error), "artApproved": False}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["status"] == "PASS" else 1)
