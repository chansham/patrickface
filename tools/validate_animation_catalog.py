"""Read-only catalog/grid checks. Never crops, rewrites, or approves animation art.

Paths in a catalog are relative to the project root. Each source cell keeps the
same fractional grid dimensions; alpha bounds are diagnostics, never fit boxes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path, PurePosixPath

from PIL import Image
from frame_region_contract import read_regions


ROOT = Path(__file__).resolve().parents[1]
BLOCKED = {"planned", "pending-generation", "generation-blocked", "revision-blocked", "blocked"}
PER_FRAME_FIT_KEYS = {
    "frameScales", "frameAnchors", "frameTransforms", "autoFitFrames",
    "fitToAlpha", "cropToAlpha", "normalizeEachFrame", "perFrameScale",
}


def finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def normalized_pair(value: object) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(
        finite_number(part) and 0 <= part <= 1 for part in value
    )


def validate_catalog(data: object, project_root: Path = ROOT) -> dict:
    report = {
        "scope": "Read-only structural, hash and alpha-grid diagnostics; no visual approval",
        "artApproval": "not-assessed", "errors": [], "warnings": [], "clips": [],
    }

    def issue(level: str, code: str, message: str, clip_id: str | None = None, **details) -> None:
        record = {"code": code, "message": message}
        if clip_id is not None:
            record["clipId"] = clip_id
        record.update(details)
        report[level].append(record)

    def finish() -> dict:
        report["status"] = "FAIL" if report["errors"] else (
            "TECHNICAL_PASS_WITH_WARNINGS" if report["warnings"] else "TECHNICAL_PASS"
        )
        report["counts"] = {"clips": len(report["clips"]), "errors": len(report["errors"]),
                            "warnings": len(report["warnings"])}
        return report

    if not isinstance(data, dict):
        issue("errors", "catalog-type", "Catalog must be an object.")
        return finish()
    clips = data.get("clips")
    if not isinstance(clips, list) or not clips:
        issue("errors", "clips-missing", "Catalog requires a nonempty clips array.")
        return finish()

    master = data.get("master")
    if not isinstance(master, dict):
        issue("errors", "master-missing", "Declare one matched master for clip registration.")
        master = {}
    if not isinstance(master.get("id"), str) or not master["id"]:
        issue("errors", "master-id", "master.id must identify the shared character/camera master.")
    if not normalized_pair(master.get("anchorNormalized")):
        issue("errors", "master-anchor", "master.anchorNormalized must be two numbers in [0,1].")
    if not finite_number(master.get("scale", 1)) or master.get("scale", 1) <= 0:
        issue("errors", "master-scale", "master.scale must be one positive, fixed scale.")
    if not finite_number(master.get("cellAspect")) or master["cellAspect"] <= 0:
        issue("errors", "master-aspect", "master.cellAspect must declare the reference cell width/height.")
    display = master.get("displayRectNormalized")
    if display is not None and not (
        isinstance(display, list) and len(display) == 4 and all(finite_number(v) for v in display)
        and display[0] >= 0 and display[1] >= 0 and display[2] > 0 and display[3] > 0
        and display[0] + display[2] <= 1.000001 and display[1] + display[3] <= 1.000001
    ):
        issue("errors", "master-display", "master.displayRectNormalized must fit within the display.")

    seen = set()
    project_root = project_root.resolve()
    comparable = []
    for position, clip in enumerate(clips):
        if not isinstance(clip, dict):
            issue("errors", "clip-type", f"Clip {position} must be an object.")
            continue
        clip_id = clip.get("id")
        if not isinstance(clip_id, str) or not clip_id:
            clip_id = f"index:{position}"
            issue("errors", "clip-id", "Clip requires a nonempty id.", clip_id)
        if clip_id in seen:
            issue("errors", "duplicate-id", "Clip id must be unique.", clip_id)
        seen.add(clip_id)
        item = {"id": clip_id, "status": clip.get("status"), "sourceCells": []}
        report["clips"].append(item)
        for key in ("title", "category", "status"):
            if not isinstance(clip.get(key), str) or not clip[key]:
                issue("errors", "clip-metadata", f"{key} must be a nonempty string.", clip_id)
        triggers = clip.get("triggerKinds")
        if not isinstance(triggers, list) or not all(isinstance(v, str) and v for v in triggers):
            issue("errors", "triggers", "triggerKinds must be an array of nonempty strings.", clip_id)
        if not clip.get("atlas") and isinstance(clip.get("status"), str) and clip["status"] in BLOCKED:
            issue("warnings", "not-produced", "No atlas: this entry is not delivered animation.", clip_id)
            item["available"] = False
            continue

        master_id = clip.get("masterId", master.get("id"))
        if master_id != master.get("id"):
            issue("errors", "master-mismatch", "Clip must explicitly match the catalog master.", clip_id)
        anchor = clip.get("anchorNormalized", master.get("anchorNormalized"))
        scale = clip.get("scale", master.get("scale", 1))
        item["registration"] = {"masterId": master_id, "anchorNormalized": anchor, "scale": scale}
        if not normalized_pair(anchor):
            issue("errors", "clip-anchor", "One fixed normalized anchor is required for all frames.", clip_id)
        if not finite_number(scale) or scale <= 0:
            issue("errors", "clip-scale", "One positive, fixed scale is required for all frames.", clip_id)
        if any(clip.get(key) not in (None, False) for key in PER_FRAME_FIT_KEYS):
            issue("errors", "per-frame-fit", "Per-frame fitting/alpha cropping would hide scale or anchor drift.", clip_id)
        if clip.get("fit") in ("frame", "bbox", "alpha", "per-frame", "content"):
            issue("errors", "per-frame-fit", "Use the full fixed source cell, not each frame's visible bounds.", clip_id)
        frames = clip.get("frames")
        if isinstance(frames, list) and any(isinstance(frame, dict) and any(
            key in frame for key in ("scale", "anchor", "anchorNormalized", "transform", "sourceRect")
        ) for frame in frames):
            issue("errors", "per-frame-transform", "Frame-specific transforms/crops are outside this fixed-grid contract.", clip_id)

        fields = ("columns", "rows", "frameCount", "width", "height")
        if any(not positive_int(clip.get(key)) for key in fields):
            issue("errors", "grid-metadata", "columns, rows, frameCount, width and height must be positive integers.", clip_id)
            continue
        columns, rows, count, width, height = (clip[key] for key in fields)
        total_cells = columns * rows
        indices = clip.get("frameIndices", list(range(count)))
        if not isinstance(indices, list) or len(indices) != count or any(
            not isinstance(v, int) or isinstance(v, bool) or v < 0 or v >= total_cells for v in indices
        ):
            issue("errors", "frame-indices", "frameIndices must map every playback frame to an in-bounds source cell.", clip_id)
            continue
        durations = clip.get("durationsMs")
        if not isinstance(durations, list) or len(durations) != count or any(
            not finite_number(v) or v <= 0 for v in durations
        ):
            issue("errors", "frame-durations", "durationsMs requires one positive finite duration per playback frame.", clip_id)
        else:
            item["durationMs"] = sum(durations)
            if min(durations) < 16:
                issue("warnings", "very-short-frame", "Sub-16ms timing needs actual-device cadence review.", clip_id)
        cell_width, cell_height = width / columns, height / rows
        item.update({"sourceCellSize": [cell_width, cell_height], "sourceCellCount": total_cells,
                     "playbackFrameCount": count, "frameIndices": indices})
        if cell_width < 1 or cell_height < 1:
            issue("errors", "subpixel-cell", "Grid has more rows/columns than image pixels.", clip_id)
            continue
        if not clip.get("frameRegions") and (width % columns or height % rows):
            issue("warnings", "fractional-grid", "Use fixed fractional source rectangles; do not round each cell to a new scale.", clip_id)
        if not clip.get("frameRegions") and finite_number(master.get("cellAspect")) and master["cellAspect"] > 0 and abs(
            cell_width / cell_height / master["cellAspect"] - 1
        ) > 0.01:
            issue("warnings", "master-aspect-difference", "Cell aspect differs from the master: verify one fixed uniform registration, without per-frame fitting.", clip_id)

        raw_path = clip.get("atlas")
        if not isinstance(raw_path, str) or not raw_path:
            issue("errors", "atlas-path", "atlas must be a project-relative file path.", clip_id)
            continue
        portable = PurePosixPath(raw_path.replace("\\", "/"))
        path = (project_root / str(portable)).resolve()
        if portable.is_absolute() or ".." in portable.parts or ":" in raw_path or not path.is_relative_to(project_root):
            issue("errors", "atlas-path", "Atlas must remain inside the project root.", clip_id)
            continue
        if not path.is_file():
            issue("errors", "atlas-missing", "Declared atlas does not exist.", clip_id, atlas=raw_path)
            item["available"] = False
            continue
        item["available"] = True
        actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        item["actualSha256"] = actual_hash
        declared_hash = clip.get("sha256")
        if not isinstance(declared_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", declared_hash):
            issue("errors", "sha256-missing", "Declare the exact atlas SHA-256.", clip_id)
        elif declared_hash.lower() != actual_hash:
            issue("errors", "sha256-mismatch", "Atlas bytes differ from catalog SHA-256.", clip_id)
        try:
            with Image.open(path) as image:
                if image.format != "PNG":
                    issue("errors", "atlas-format", "Atlas must actually be PNG, regardless of filename.", clip_id)
                if image.size != (width, height):
                    issue("errors", "atlas-size", "Decoded dimensions differ from catalog width/height.", clip_id,
                          actualSize=list(image.size))
                    continue
                if getattr(image, "n_frames", 1) != 1:
                    issue("errors", "animated-container", "A grid atlas must be a single still PNG, not APNG.", clip_id)
                if "A" not in image.getbands() and "transparency" not in image.info:
                    issue("warnings", "no-transparency", "PNG has no transparency; inspect its background manually.", clip_id)
                alpha = image.convert("RGBA").getchannel("A")
                if clip.get("frameRegions"):
                    try:
                        item["contours"] = read_regions(clip, project_root, alpha)
                        for observation in item["contours"]["frames"]:
                            if observation["sourceOuterEdgePixels128"]:
                                issue("warnings", "source-outer-edge", "Original art touches the outer PNG edge; extraction cannot reconstruct pixels outside the source.", clip_id, sourceFrame=observation["index"])
                    except (OSError, ValueError, TypeError, KeyError) as error:
                        issue("errors", "frame-regions", str(error), clip_id)
                    continue
                used = set(indices)
                widths, heights, areas = [], [], []
                for source_index in range(total_cells):
                    column, row = source_index % columns, source_index // columns
                    x, y = column * cell_width, row * cell_height
                    rect = (math.floor(x), math.floor(y), math.ceil(x + cell_width), math.ceil(y + cell_height))
                    cell_alpha = alpha.crop(rect)  # Memory-only inspection; never saved or used for playback fitting.
                    bounds = cell_alpha.getbbox()
                    solid = cell_alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
                    cell = {"index": source_index, "used": source_index in used,
                            "sourceRect": [x, y, cell_width, cell_height], "inspectionRect": list(rect),
                            "alphaBounds": list(bounds) if bounds else None,
                            "alpha16Bounds": list(solid) if solid else None}
                    item["sourceCells"].append(cell)
                    if not bounds:
                        if source_index in used:
                            issue("errors", "empty-frame", "A referenced source cell is fully transparent.", clip_id, sourceCell=source_index)
                        continue
                    cell_w, cell_h = cell_alpha.size
                    if bounds[0] <= 0 or bounds[1] <= 0 or bounds[2] >= cell_w or bounds[3] >= cell_h:
                        issue("warnings", "alpha-touches-cell", "Alpha reaches a grid boundary: possible clipping, neighbor bleed or fringe; inspect visually.", clip_id, sourceCell=source_index)
                    if source_index in used and solid:
                        bw, bh = solid[2] - solid[0], solid[3] - solid[1]
                        widths.append(bw / cell_width)
                        heights.append(bh / cell_height)
                        areas.append(bw * bh / (cell_width * cell_height))
                if widths:
                    variation = {"widthRatio": max(widths) / min(widths), "heightRatio": max(heights) / min(heights),
                                 "boundsAreaRatio": max(areas) / min(areas)}
                    item["boundsVariation"] = variation
                    if variation["widthRatio"] > 1.35 or variation["heightRatio"] > 1.35 or variation["boundsAreaRatio"] > 1.8:
                        issue("warnings", "large-bounds-change", "Large visible-bounds change may be intentional acting; inspect pose, body volume and anchor. Never auto-resize frames to suppress it.", clip_id, **variation)
                    if finite_number(scale) and scale > 0:
                        comparable.append((clip_id, max(widths) * scale, max(heights) * scale))
        except (OSError, ValueError, Image.DecompressionBombError) as error:
            issue("errors", "atlas-decode", str(error), clip_id)

    if len(comparable) > 1:
        ref_id, ref_width, ref_height = comparable[0]
        for clip_id, width, height in comparable[1:]:
            ratio_w, ratio_h = width / ref_width, height / ref_height
            if not (0.7 <= ratio_w <= 1.4 and 0.7 <= ratio_h <= 1.4):
                issue("warnings", "cross-clip-bounds-change", "Compare against the matched master: sitting/standing or props may explain height changes; verify head/body proportions visually, not equal-height normalization.", clip_id,
                      referenceClip=ref_id, widthRatio=ratio_w, heightRatio=ratio_h)
    planned = data.get("plannedClips", [])
    if not isinstance(planned, list) or not all(isinstance(value, str) and value for value in planned):
        issue("errors", "planned-clips", "plannedClips must be an array of nonempty clip ids.")
    else:
        report["plannedClipCount"] = len(planned)
        for clip_id in planned:
            if clip_id not in seen:
                issue("warnings", "not-produced", "Planned clip has no delivered catalog entry.", clip_id)
    return finish()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "animation" / "catalog.json")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--json", action="store_true", help="Print machine-readable diagnostics to stdout; writes no file.")
    parser.add_argument("--strict-warnings", action="store_true", help="Exit 2 on warnings, distinct from invalid catalog (exit 1).")
    args = parser.parse_args()
    try:
        data = json.loads(args.catalog.read_text(encoding="utf-8-sig"))
        report = validate_catalog(data, args.root)
    except (OSError, ValueError) as error:
        report = {"status": "FAIL", "artApproval": "not-assessed", "errors": [{"code": "catalog-read", "message": str(error)}], "warnings": [], "clips": []}
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"{report['status']}: {len(report['clips'])} clips, {len(report['errors'])} errors, {len(report['warnings'])} warnings; visual approval NOT assessed.")
        for level in ("errors", "warnings"):
            for item in report[level]:
                print(f"{level.upper()} [{item['code']}] {item.get('clipId', 'catalog')}: {item['message']}")
    return 1 if report["errors"] else 2 if args.strict_warnings and report["warnings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
