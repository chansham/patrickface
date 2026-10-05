"""Validate contour extraction metadata against unchanged atlas pixels."""
import hashlib
import json
from pathlib import PurePosixPath


def integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def read_regions(clip, root, alpha):
    ref = clip.get("frameRegions")
    if not isinstance(ref, dict) or ref.get("version") != 1:
        raise ValueError("frameRegions requires version 1 and a hashed metadata file")
    name = ref.get("path")
    if not isinstance(name, str) or "\\" in name or ":" in name:
        raise ValueError("Invalid contour metadata path")
    portable = PurePosixPath(name)
    path = root.joinpath(*portable.parts)
    if portable.is_absolute() or any(p in ("", ".", "..") for p in name.split("/")) or not path.resolve().is_relative_to(root):
        raise ValueError("Contour metadata must stay inside the project")
    payload = path.read_bytes()
    if hashlib.sha256(payload).hexdigest() != ref.get("sha256"):
        raise ValueError("Contour metadata SHA does not match catalog")
    data = json.loads(payload.decode("utf-8-sig"))
    if data.get("schemaVersion") != 1:
        raise ValueError("Unsupported contour metadata schema")
    source = data.get("source", {})
    for key, expected in (("path", clip["atlas"]), ("sha256", clip["sha256"]), ("width", clip["width"]), ("height", clip["height"])):
        if source.get(key) != expected:
            raise ValueError(f"Contour source {key} differs from atlas")
    canvas = data.get("canvas", {})
    cw, ch = canvas.get("width"), canvas.get("height")
    anchor = canvas.get("anchorPixels")
    if not all(integer(n) and 1 <= n <= 4096 for n in (cw, ch)):
        raise ValueError("Invalid common contour canvas")
    if not isinstance(anchor, list) or len(anchor) != 2 or not all(integer(n) for n in anchor) or not (0 <= anchor[0] <= cw and 0 <= anchor[1] <= ch):
        raise ValueError("Invalid common pixel anchor")
    normalized = [anchor[0] / cw, anchor[1] / ch]
    if canvas.get("anchorNormalized") != normalized or clip.get("anchorNormalized") != normalized:
        raise ValueError("Clip and common-canvas anchors must match exact pixel registration")
    frames = data.get("frames")
    if not isinstance(frames, list) or len(frames) != clip["columns"] * clip["rows"]:
        raise ValueError("Contour regions must describe every original source pose")
    width, height = alpha.size
    source_alpha = alpha.tobytes()
    coverage = bytearray(width * height)
    observations = []
    for index, frame in enumerate(frames):
        if any(key in frame for key in ("scale", "rotation", "fit", "resize")):
            raise ValueError("Per-pose resize or rotation is not allowed")
        bounds, translation = frame.get("sourceBounds"), frame.get("translation")
        placement, foot = frame.get("placement"), frame.get("anchorSource")
        for value, count in ((bounds, 4), (translation, 2), (placement, 2), (foot, 2)):
            if not isinstance(value, list) or len(value) != count or not all(integer(n) for n in value):
                raise ValueError(f"Frame {index + 1} has invalid integer geometry")
        x, y, w, h = bounds
        tx, ty = translation
        if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > height:
            raise ValueError("Contour source bounds exceed atlas")
        if placement != [x + tx, y + ty] or [foot[0] + tx, foot[1] + ty] != anchor:
            raise ValueError("Contour placement does not register to common feet anchor")
        if placement[0] < 0 or placement[1] < 0 or placement[0] + w > cw or placement[1] + h > ch:
            raise ValueError("Complete contour exceeds common canvas")
        rows = frame.get("rows")
        if not isinstance(rows, list) or not rows:
            raise ValueError("Missing contour mask rows")
        previous_y, pixels, edge_pixels = -1, 0, 0
        for row in rows:
            if not isinstance(row, list) or len(row) < 3 or len(row) % 2 != 1 or not all(integer(n) for n in row):
                raise ValueError("Invalid contour row spans")
            ry = row[0]
            if ry <= previous_y or not y <= ry < y + h:
                raise ValueError("Contour rows must be sorted inside bounds")
            previous_y, previous_end = ry, -1
            for left, right in zip(row[1::2], row[2::2]):
                if left < previous_end or not x <= left < right <= x + w:
                    raise ValueError("Contour spans overlap or exceed source bounds")
                previous_end = right
                start, end = ry * width + left, ry * width + right
                if 1 in coverage[start:end]:
                    raise ValueError("A source pixel belongs to more than one pose")
                if 0 in source_alpha[start:end]:
                    raise ValueError("Contour mask includes fully transparent source pixels")
                coverage[start:end] = b"\x01" * (end - start)
                pixels += end - start
                if ry in (0, height - 1):
                    edge_pixels += sum(v >= 128 for v in source_alpha[start:end])
                else:
                    if left == 0 and source_alpha[start] >= 128: edge_pixels += 1
                    if right == width and source_alpha[end - 1] >= 128: edge_pixels += 1
        observations.append({"index": index, "sourceBounds": bounds, "pixelCount": pixels,
                             "footAnchor": anchor, "sourceOuterEdgePixels128": edge_pixels})
    expected = len(source_alpha) - source_alpha.count(0)
    if sum(coverage) != expected:
        raise ValueError("Contour ownership does not preserve every nontransparent source pixel")
    return {"metadata": name, "commonCanvas": [cw, ch], "anchorPixels": anchor,
            "sourcePixelsPreserved": expected, "sourcePixelsDuplicated": 0,
            "frames": observations, "rendering": "contour-mask; fixed 1:1 pixels, integer foot registration"}
