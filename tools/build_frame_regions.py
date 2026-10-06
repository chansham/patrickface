#!/usr/bin/env python3
"""Describe atlas frame masks and 1:1 placement without writing image pixels.

Strong alpha components seed individual characters. Weak connected fringes grow
from all seeds simultaneously; detached pieces belong to the nearest actual core
outline. Every source pixel with nonzero alpha is preserved exactly once.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ALGORITHM = "alpha-component-regions-v1"
SOURCES = (
    ("animation/yawn-v1/atlas-eyes-v2.png", 4, 2),
    ("animation/yawn-v3/atlas-generated.png", 4, 4),
    ("animation/focus-v1/atlas-generated.png", 4, 4),
    ("animation/celebrate-v1/atlas-generated.png", 4, 4),
    ("animation/bath-v1/atlas-generated.png", 4, 2),
    ("animation/wake-v1/atlas-generated.png", 4, 2),
)

# Reviewed against the actual feet, not a general remedy for animation jitter.
# The hash gate prevents this stationary seated-pose rule reaching new artwork,
# including future running/jumping poses with intentional ground movement.
REVIEWED_SUPPORT_POLICIES = {
    ("animation/exercise-v2/atlas-generated.png",
     "e49971a249f9405651121d30c23bc7e05a94635698de25af6729125f4a0f347f"): {
        "id": "exercise-v2-feet-12px-20261006",
        "kind": "fixed-bottom-core-band",
        "depthPixels": 12,
        "reason": "Visually inspected seated feet: the original lower-15-percent band also included the lowered dumbbell. The bottom 12 source pixels contain both feet and exclude that prop.",
    },
    ("animation/exercise-v3/atlas-generated.png",
     "0a3fdcd7fc489fb89457b76145ce3e249f2a401c3ffc0a1a566872cb7da1627f"): {
        "id": "exercise-v3-reviewed-support-12px-20261006",
        "kind": "fixed-bottom-core-band",
        "depthPixels": 12,
        "reason": "Separately inspected all 16 seated frames on this exact new source: visible feet share the core bottom. The lowest 12-pixel support silhouette also includes shorts and minor dumbbell overlap; it is not an anatomical foot-only mask. This narrower reviewed support band reduces registered top-head horizontal range from 21 to 3 source pixels, without per-frame scaling or smoothing. Do not apply to another source hash.",
    },
}


def apply_reviewed_support_policy(data: dict, alpha: np.ndarray, policy: dict) -> None:
    """Register an explicitly reviewed support band; keep mask, canvas and scale.

    This only changes integer translation. It does not repaint, resize, discard
    pixels, smooth body motion, or infer a policy for unreviewed source atlases.
    """
    depth = policy.get("depthPixels")
    if (policy.get("kind") != "fixed-bottom-core-band" or isinstance(depth, bool)
            or not isinstance(depth, int) or depth <= 0):
        raise ValueError("invalid reviewed support-band policy")
    target_x, target_y = data["canvas"]["anchorPixels"]
    updates = []
    for frame in data["frames"]:
        left, top, right, bottom = frame["diagnostics"]["coreBounds"]
        if depth > bottom - top:
            raise ValueError("reviewed support band exceeds the character core")
        start = bottom - depth
        support = []
        for row in frame["rows"]:
            y = row[0]
            if not start <= y < bottom:
                continue
            for x0, x1 in zip(row[1::2], row[2::2]):
                x0, x1 = max(left, x0), min(right, x1)
                if x0 < x1:
                    support.extend((np.flatnonzero(alpha[y, x0:x1] >= 128) + x0).tolist())
        if not support:
            raise ValueError("reviewed support band contains no strong pixels")
        anchor = [round_positive((min(support) + max(support) + 1) / 2), bottom]
        translation = [target_x - anchor[0], target_y - anchor[1]]
        x, y, w, h = frame["sourceBounds"]
        placement = [x + translation[0], y + translation[1]]
        if not (0 <= placement[0] <= placement[0] + w <= data["canvas"]["width"]
                and 0 <= placement[1] <= placement[1] + h <= data["canvas"]["height"]):
            raise ValueError("reviewed anchor would exceed the unchanged common canvas")
        updates.append((frame, anchor, translation, placement, start))
    for frame, anchor, translation, placement, start in updates:
        frame["anchorSource"] = anchor
        frame["translation"] = translation
        frame["placement"] = placement
        frame["diagnostics"]["supportBandStartY"] = start
    data["diagnostics"]["supportAnchorPolicy"] = dict(policy)


def normalized_source(relative: str) -> str:
    """Accept explicit project paths, never traversal or an absolute/drive path."""
    if not isinstance(relative, str):
        raise ValueError("source must be a project-relative PNG path")
    normalized = relative.replace("\\", "/")
    parts = normalized.split("/")
    if (len(parts) < 2 or parts[0] != "animation"
            or any(part in ("", ".", "..") or ":" in part for part in parts)
            or not parts[-1].lower().endswith(".png")):
        raise ValueError("source must be a PNG path under animation/ without traversal")
    return normalized


def valid_grid(columns: int, rows: int) -> None:
    if any(isinstance(v, bool) or not isinstance(v, int) or v <= 0
           for v in (columns, rows)):
        raise ValueError("columns and rows must both be positive integers")


def selected_sources(source: str | None, columns: int | None,
                     rows: int | None) -> tuple[tuple[str, int, int], ...]:
    """Known invocations stay compatible; new sources require an explicit grid."""
    if source is None:
        if columns is not None or rows is not None:
            raise ValueError("columns/rows require one explicit --source")
        return SOURCES
    source = normalized_source(source)
    known = next((entry for entry in SOURCES if entry[0] == source), None)
    if columns is None and rows is None:
        if known:
            return (known,)
        raise ValueError("a new source requires both --columns and --rows")
    if columns is None or rows is None:
        raise ValueError("provide both --columns and --rows")
    valid_grid(columns, rows)
    if known and (columns, rows) != known[1:]:
        raise ValueError("explicit grid disagrees with the known source grid")
    return ((source, columns, rows),)


def round_positive(value: float) -> int:
    return int(math.floor(value + 0.5))


def connected_components(mask: np.ndarray) -> tuple[np.ndarray, list[dict]]:
    """Eight-connected components; IDs include small detached marks."""
    height, width = mask.shape
    padded = np.pad(mask, 1)
    stride = width + 2
    remaining = padded.ravel()
    labels = np.zeros(remaining.size, dtype=np.int32)
    offsets = (-stride - 1, -stride, -stride + 1, -1, 1,
               stride - 1, stride, stride + 1)
    components = []
    for seed_value in np.flatnonzero(remaining):
        seed = int(seed_value)
        if not remaining[seed]:
            continue
        component_id = len(components) + 1
        remaining[seed] = False
        labels[seed] = component_id
        queue = deque([seed])
        count = 0
        left, top, right, bottom = width + 2, height + 2, 0, 0
        while queue:
            current = queue.popleft()
            y, x = divmod(current, stride)
            count += 1
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x), max(bottom, y)
            for offset in offsets:
                neighbor = current + offset
                if remaining[neighbor]:
                    remaining[neighbor] = False
                    labels[neighbor] = component_id
                    queue.append(neighbor)
        components.append({"id": component_id, "pixelCount": count,
                           "bounds": [left - 1, top - 1, right, bottom]})
    return labels.reshape(height + 2, width + 2)[1:-1, 1:-1], components


def ordered_cores(components: list[dict], columns: int, rows: int,
                  min_core_pixels: int) -> list[dict]:
    cores = [c for c in components if c["pixelCount"] >= min_core_pixels]
    expected = columns * rows
    if len(cores) != expected:
        raise ValueError(f"expected {expected} strong character cores; found {len(cores)}")
    # Rows only establish reading order; they never define source crop lines.
    cores.sort(key=lambda c: (c["bounds"][1] + c["bounds"][3]) / 2)
    result = []
    for start in range(0, expected, columns):
        band = cores[start:start + columns]
        band.sort(key=lambda c: (c["bounds"][0] + c["bounds"][2]) / 2)
        result.extend(band)
    return result


def propagate(seed_labels: np.ndarray, allowed: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Multi-source eight-neighbor BFS; first/lower row-major core wins ties."""
    height, width = allowed.shape
    stride = width + 2
    owners = np.pad(seed_labels, 1).ravel()
    valid = np.pad(allowed, 1).ravel()
    distance = np.full(owners.size, -1, dtype=np.int32)
    initial = np.flatnonzero(owners)
    # Stable ID-first initialization makes exact-distance ties reproducible.
    initial = initial[np.argsort(owners[initial], kind="stable")]
    distance[initial] = 0
    queue = deque(int(i) for i in initial)
    offsets = (-stride - 1, -stride, -stride + 1, -1, 1,
               stride - 1, stride, stride + 1)
    while queue:
        current = queue.popleft()
        owner, next_distance = owners[current], distance[current] + 1
        for offset in offsets:
            neighbor = current + offset
            if valid[neighbor] and distance[neighbor] < 0:
                owners[neighbor] = owner
                distance[neighbor] = next_distance
                queue.append(neighbor)
    shape = (height + 2, width + 2)
    return (owners.reshape(shape)[1:-1, 1:-1],
            distance.reshape(shape)[1:-1, 1:-1])


def frame_rows(mask: np.ndarray) -> list[list[int]]:
    result = []
    for y in np.flatnonzero(mask.any(axis=1)):
        padded = np.pad(mask[int(y)].astype(np.int8), 1)
        changes = np.flatnonzero(np.diff(padded))
        result.append([int(y), *(int(x) for x in changes)])
    return result


def build_regions(alpha: np.ndarray, columns: int, rows: int,
                  min_core_pixels: int = 10000, padding: int = 12) -> dict:
    valid_grid(columns, rows)
    if alpha.ndim != 2 or alpha.dtype != np.uint8:
        raise ValueError("alpha must be a uint8 two-dimensional array")
    height, width = alpha.shape
    labels, components = connected_components(alpha >= 128)
    cores = ordered_cores(components, columns, rows, min_core_pixels)
    seeds = np.zeros(alpha.shape, dtype=np.int32)
    for index, core in enumerate(cores, 1):
        seeds[labels == core["id"]] = index
    owners, _ = propagate(seeds, alpha > 0)
    missing = (alpha > 0) & (owners == 0)
    detached_records = []
    if missing.any():
        # Background traversal is only a distance measurement for genuinely
        # detached pieces. It never adds background pixels to a frame mask.
        nearest_owner, nearest_distance = propagate(seeds, np.ones(alpha.shape, dtype=bool))
        fragment_labels, fragments = connected_components(missing)
        for fragment in fragments:
            fx0, fy0, fx1, fy1 = fragment["bounds"]
            region = np.s_[fy0:fy1, fx0:fx1]
            fragment_mask = fragment_labels[region] == fragment["id"]
            distances = nearest_distance[region][fragment_mask]
            min_distance = int(distances.min())
            nearest = nearest_owner[region][fragment_mask][distances == min_distance]
            values, counts = np.unique(nearest, return_counts=True)
            chosen = int(values[np.argmax(counts)])
            owners[region][fragment_mask] = chosen
            detached_records.append({
                "bounds": fragment["bounds"], "pixelCount": fragment["pixelCount"],
                "frame": chosen, "distanceFromCore": min_distance,
                "nearestCoreCandidates": [int(v) for v in values],
                "maxAlpha": int(alpha[region][fragment_mask].max()),
            })
    frames = []
    extents = []
    for index, core in enumerate(cores, 1):
        mask = (owners == index) & (alpha > 0)
        ys, xs = np.where(mask)
        x0, y0 = int(xs.min()), int(ys.min())
        x1, y1 = int(xs.max()) + 1, int(ys.max()) + 1
        core_mask = seeds == index
        core_y, core_x = np.where(core_mask)
        core_top, core_bottom = int(core_y.min()), int(core_y.max()) + 1
        support_start = core_top + math.floor((core_bottom - core_top) * 0.85)
        support_x = core_x[core_y >= support_start]
        anchor_x = round_positive((int(support_x.min()) + int(support_x.max()) + 1) / 2)
        anchor_y = core_bottom
        extents.append((anchor_x - x0, x1 - anchor_x, anchor_y - y0, y1 - anchor_y))
        frames.append({
            "sourceBounds": [x0, y0, x1 - x0, y1 - y0],
            "anchorSource": [anchor_x, anchor_y],
            "placement": None,
            "rows": frame_rows(mask),
            "diagnostics": {
                "coreBounds": core["bounds"],
                "corePixelCount": core["pixelCount"],
                "pixelCount": int(mask.sum()),
                "supportBandStartY": support_start,
                "sourceEdgeTouches": [side for side, hit in (
                    ("left", x0 == 0), ("top", y0 == 0),
                    ("right", x1 == width), ("bottom", y1 == height)) if hit],
                "coreSourceEdgeTouches": [side for side, hit in (
                    ("left", core["bounds"][0] == 0), ("top", core_top == 0),
                    ("right", core["bounds"][2] == width),
                    ("bottom", core_bottom == height)) if hit],
            },
        })
    left = max(e[0] for e in extents)
    right = max(e[1] for e in extents)
    up = max(e[2] for e in extents)
    down = max(e[3] for e in extents)
    initial_size = max(2 * (max(left, right) + padding),
                       (up + padding) / 0.88, (down + padding) / 0.12)
    size = int(math.ceil(initial_size / 4) * 4)
    while True:
        target_x, target_y = round_positive(size * 0.5), round_positive(size * 0.88)
        if (target_x - left >= padding and size - target_x - right >= padding
                and target_y - up >= padding and size - target_y - down >= padding):
            break
        size += 4
    for frame in frames:
        x, y, _, _ = frame["sourceBounds"]
        ax, ay = frame["anchorSource"]
        frame["translation"] = [target_x - ax, target_y - ay]
        frame["placement"] = [x + frame["translation"][0], y + frame["translation"][1]]
    original_count = int((alpha > 0).sum())
    assigned_count = sum(f["diagnostics"]["pixelCount"] for f in frames)
    if assigned_count != original_count or np.any((alpha > 0) & (owners == 0)):
        raise ValueError("nonzero-alpha pixel coverage is incomplete")
    result = {
        "schemaVersion": 1, "algorithm": ALGORITHM,
        "canvas": {"width": size, "height": size,
                   "anchorPixels": [target_x, target_y],
                   "anchorNormalized": [target_x / size, target_y / size]},
        "frames": frames,
        "diagnostics": {
            "sourceNonzeroAlphaPixels": original_count,
            "assignedPixels": assigned_count, "unassignedPixels": 0,
            "discardedPixels": 0, "coreThreshold": 128,
            "coreCount": len(cores), "coreMinimumPixels": min_core_pixels,
            "frameOrder": "row-major by strong-core centers; grid used only for order",
            "assignment": "eight-neighbor multi-source shortest paths over alpha>0; detached components assigned whole to nearest strong outline using Chebyshev distance",
            "tieBreak": "lower row-major seed wins path ties; detached ties use most nearest pixels then lower ID",
            "detachedComponentCount": len(detached_records),
            "detachedComponents": detached_records,
            "minimumCanvasPadding": padding,
            "scalePerFrame": 1,
            "warnings": [
                "All nonzero-alpha pixels, including isolated faint noise, are preserved; this can enlarge source bounds and common canvas.",
                "Translation only; focus artwork size differences are preserved.",
                "Lower-15-percent support-center anchoring may show small shifts when foot shape changes; manual playback review remains required.",
                "A silhouette already cut by the original PNG boundary cannot be recovered by extraction metadata.",
                "Low-alpha bridges are partitioned deterministically; exact artist intent at ambiguous fringe contacts is not known.",
            ],
        },
    }
    return result


def validate_regions(data: dict, alpha: np.ndarray) -> dict:
    height, width = alpha.shape
    coverage = np.zeros(alpha.shape, dtype=np.uint8)
    size = data["canvas"]["width"]
    if data["canvas"]["height"] != size or size % 4:
        raise ValueError("canvas must be a shared square with a multiple-of-four size")
    target = data["canvas"]["anchorPixels"]
    for index, frame in enumerate(data["frames"], 1):
        x, y, w, h = frame["sourceBounds"]
        dx, dy = frame["placement"]
        tx, ty = frame["translation"]
        ax, ay = frame["anchorSource"]
        if not (0 <= x < x + w <= width and 0 <= y < y + h <= height):
            raise ValueError(f"frame {index} source bounds outside PNG")
        if not (0 <= dx <= dx + w <= size and 0 <= dy <= dy + h <= size):
            raise ValueError(f"frame {index} destination outside common canvas")
        if [dx + ax - x, dy + ay - y] != target:
            raise ValueError(f"frame {index} anchor is inconsistent")
        if [x + tx, y + ty] != [dx, dy] or [ax + tx, ay + ty] != target:
            raise ValueError(f"frame {index} translation and placement disagree")
        last_y = -1
        for row in frame["rows"]:
            yy, *runs = row
            if yy <= last_y or not (y <= yy < y + h) or len(runs) % 2:
                raise ValueError(f"frame {index} invalid mask row")
            last_y = yy
            last_end = x - 1
            for start, end in zip(runs[::2], runs[1::2]):
                if not (x <= start < end <= x + w) or start <= last_end:
                    raise ValueError(f"frame {index} invalid or overlapping run")
                if not np.all(alpha[yy, start:end] > 0):
                    raise ValueError("mask includes fully transparent source pixels")
                coverage[yy, start:end] += 1
                last_end = end
    if np.any(coverage > 1):
        raise ValueError("a source pixel belongs to multiple frames")
    if not np.array_equal(coverage == 1, alpha > 0):
        raise ValueError("frame masks do not exactly cover source alpha>0")
    return {"assignedPixels": int(coverage.sum()), "overlapPixels": 0,
            "unassignedPixels": 0, "status": "METADATA_VALID_ART_NOT_APPROVED"}


def confined_source(relative: str) -> Path:
    relative = normalized_source(relative)
    path = ROOT / relative
    resolved = path.resolve(strict=True)
    animation_root = (ROOT / "animation").resolve()
    if (not resolved.is_relative_to(animation_root) or resolved != path.absolute()
            or not resolved.is_file()):
        raise ValueError("source must be an ordinary file within project animation/")
    return resolved


def run_source(relative: str, columns: int, rows: int, check: bool,
               max_canvas_ratio: float = 2.0) -> dict:
    relative = normalized_source(relative)
    valid_grid(columns, rows)
    source_path = confined_source(relative)
    before = source_path.read_bytes()
    source_sha = hashlib.sha256(before).hexdigest()
    with Image.open(source_path) as image:
        if image.format != "PNG" or "A" not in image.getbands():
            raise ValueError("source must be a PNG with an explicit alpha channel")
        alpha = np.asarray(image.getchannel("A"))
        width, height = image.size
    destination = source_path.with_name("regions-v1.json")
    if destination.is_symlink() or destination.resolve() != destination.absolute():
        raise ValueError("metadata destination must not redirect through a link")
    if check:
        data = json.loads(destination.read_text(encoding="utf-8-sig"))
        if data.get("algorithm") != ALGORITHM or data.get("source") != {
                "path": relative, "sha256": source_sha, "width": width, "height": height}:
            raise ValueError("metadata source/algorithm does not match current PNG")
    else:
        if destination.exists():
            existing = json.loads(destination.read_text(encoding="utf-8-sig"))
            if existing.get("algorithm") != ALGORITHM:
                raise ValueError("refusing to replace unknown metadata")
            if existing.get("source", {}).get("path") != relative:
                raise ValueError("refusing to replace metadata belonging to another PNG")
        data = build_regions(alpha, columns, rows)
        nominal_cell = max(width / columns, height / rows)
        data["diagnostics"]["canvasToNominalCellRatio"] = data["canvas"]["width"] / nominal_cell
        data["diagnostics"]["maximumCanvasRatioExplicitLimit"] = max_canvas_ratio
        if data["canvas"]["width"] > max_canvas_ratio * nominal_cell:
            raise ValueError(f"canvas inflated to {data['canvas']['width']}px; inspect faint-fragment ownership before writing metadata")
        data["source"] = {"path": relative, "sha256": source_sha,
                          "width": width, "height": height}
    if len(data["frames"]) != columns * rows:
        raise ValueError("metadata frame count does not match the explicit source grid")
    policy = REVIEWED_SUPPORT_POLICIES.get((relative, source_sha))
    if policy:
        if check:
            from copy import deepcopy
            expected = deepcopy(data)
            apply_reviewed_support_policy(expected, alpha, policy)
            if expected != data:
                raise ValueError("metadata does not apply the reviewed source-specific support policy")
        else:
            apply_reviewed_support_policy(data, alpha, policy)
    result = validate_regions(data, alpha)
    if source_path.read_bytes() != before:
        raise ValueError("source bytes changed during analysis; not writing metadata")
    if not check:
        destination.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return {"source": relative, "metadata": destination.relative_to(ROOT).as_posix(),
            "frames": len(data["frames"]), "canvas": data["canvas"],
            "sha256": source_sha, "sourceUnchanged": True,
            "detachedComponents": data["diagnostics"]["detachedComponentCount"], **result}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="read-only metadata coverage/hash validation")
    parser.add_argument("--source", help="one explicit animation/ PNG; new paths also require --columns and --rows")
    parser.add_argument("--columns", type=int, help="source reading-order column count; required for a new path")
    parser.add_argument("--rows", type=int, help="source reading-order row count; required for a new path")
    parser.add_argument("--max-canvas-ratio", type=float, default=2.0,
                        help="explicit reviewed limit relative to nominal cell; default 2, use 3 for preserved distant celebration specks")
    args = parser.parse_args()
    try:
        if not math.isfinite(args.max_canvas_ratio) or args.max_canvas_ratio <= 0:
            raise ValueError("max canvas ratio must be finite and positive")
        for source, columns, rows in selected_sources(args.source, args.columns, args.rows):
            print(json.dumps(run_source(source, columns, rows, args.check,
                                        args.max_canvas_ratio), ensure_ascii=False), flush=True)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
