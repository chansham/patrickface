#!/usr/bin/env python3
"""Crop a Patrick head from the existing season-1 flat-colour body.

Source, unchanged:
  PatrickFace/Assets.xcassets/season1-body-normal.imageset/season1-body-normal.png

The square is centered on the midpoint between the two eyes. Sizes of 80px
and up keep the pointed head, with a flat cut below the mouth and at least
4% of the canvas clear of the outline on both sides. The 48px and 64px
corner bitmaps are a face-only crop: the point is cut off, the window
starts just above the eyebrows, and both eyes together cover at least 55%
of the canvas. Nothing is redrawn. The result still needs art approval.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "PatrickFace"
    / "Assets.xcassets"
    / "season1-body-normal.imageset"
    / "season1-body-normal.png"
)
WATCH_CATALOG = ROOT / "PatrickFaceComplications" / "Avatar.xcassets"
PHONE_CATALOG = ROOT / "iOSCompanion" / "PatrickWidgets" / "Avatar.xcassets"

# Name -> (pixel size, face-only crop). Face-only is the corner pair.
SLOTS = {
    "watch": [
        ("PatrickHeadCircular", 96, False),
        ("PatrickHeadRectangular", 80, False),
        ("PatrickHeadCorner", 48, True),
    ],
    "phone": [
        ("PatrickHeadCircular", 180, False),
        ("PatrickHeadRectangular", 120, False),
        ("PatrickHeadCorner", 64, True),
        ("PatrickHeadActivity", 288, False),
    ],
}

MAX_PNG_BYTES = 48_000
MARGIN = 0.04


def contents_json(filename: str | None = None) -> dict:
    if filename is None:
        return {"info": {"author": "xcode", "version": 1}}
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def channels(image: Image.Image):
    arr = np.array(image.convert("RGBA"))
    parts = [arr[:, :, i].astype(np.int16) for i in range(4)]
    return arr, parts[0], parts[1], parts[2], parts[3]


def components(mask: np.ndarray, min_count: int) -> list[dict]:
    visited = np.zeros(mask.shape, dtype=bool)
    found = []
    ys, xs = np.where(mask)
    height, width = mask.shape
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if visited[y0, x0]:
            continue
        stack = [(y0, x0)]
        visited[y0, x0] = True
        points = []
        while stack:
            y, x = stack.pop()
            points.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dy == 0 and dx == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if (
                        0 <= ny < height
                        and 0 <= nx < width
                        and mask[ny, nx]
                        and not visited[ny, nx]
                    ):
                        visited[ny, nx] = True
                        stack.append((ny, nx))
        if len(points) < min_count:
            continue
        yy = np.array([p[0] for p in points])
        xx = np.array([p[1] for p in points])
        found.append(
            {
                "n": len(points),
                "x0": int(xx.min()),
                "x1": int(xx.max()),
                "y0": int(yy.min()),
                "y1": int(yy.max()),
                "cx": float(xx.mean()),
                "cy": float(yy.mean()),
            }
        )
    return found


def detect_landmarks(source: Image.Image) -> dict:
    """Eyes, brows, and mouth on the season-1 body. Positions are source pixels."""
    _, red, green, blue, alpha = channels(source)
    opaque = alpha > 20
    rows = np.where(opaque.any(1))[0]
    head_top = int(rows[0])
    white = (
        (alpha > 180)
        & (red > 220)
        & (green > 205)
        & (blue > 190)
        & (np.abs(red - green) < 35)
    )
    white[:head_top] = False
    white[head_top + 420 :] = False
    eyes = sorted(components(white, 400), key=lambda item: item["cx"])
    if len(eyes) < 2:
        raise SystemExit("could not find two eyes on season1-body-normal")
    left, right = eyes[0], eyes[1]
    mid_x = ((left["x0"] + left["x1"]) / 2 + (right["x0"] + right["x1"]) / 2) / 2
    eye_top = min(left["y0"], right["y0"])
    eye_bottom = max(left["y1"], right["y1"])

    dark = (alpha > 160) & ((red + green + blue) < 180) & (red < 90)
    rim = np.zeros(opaque.shape, dtype=bool)
    padded = np.pad(opaque.astype(np.uint8), 2, constant_values=0)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if dx * dx + dy * dy > 4:
                continue
            rim |= (
                padded[
                    2 + dy : 2 + dy + opaque.shape[0],
                    2 + dx : 2 + dx + opaque.shape[1],
                ]
                == 0
            )
    brows = dark & ~rim
    brows[eye_top - 80 : eye_top - 4, left["x0"] - 20 : right["x1"] + 20] &= True
    brow_rows = np.where(brows[eye_top - 80 : eye_top].any(1))[0]
    if len(brow_rows) == 0:
        raise SystemExit("could not find eyebrows on season1-body-normal")
    brow_top = int(brow_rows[0] + eye_top - 80)

    # The mouth is the dark mark under the eyes, after a run of plain skin.
    below = dark & ~rim
    below[: eye_bottom + 8] = False
    below[eye_bottom + 80 :] = False
    below[:, : left["x0"] - 10] = False
    below[:, right["x1"] + 10 :] = False
    mouth_rows = np.where(below.any(1))[0]
    if len(mouth_rows) == 0:
        raise SystemExit("could not find the mouth on season1-body-normal")
    mouth_bottom = int(mouth_rows.max())
    return {
        "headTop": head_top,
        "browTop": brow_top,
        "mouthBottom": mouth_bottom,
        "headHeight": mouth_bottom - head_top,
        "eyeMidX": mid_x,
        "leftEye": [left["x0"], left["y0"], left["x1"], left["y1"]],
        "rightEye": [right["x0"], right["y0"], right["x1"], right["y1"]],
        "combinedEyeWidth": (left["x1"] - left["x0"] + 1) + (right["x1"] - right["x0"] + 1),
    }


def paste_window(source: Image.Image, left: int, top: int, side: int) -> Image.Image:
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    src_left = max(0, left)
    src_top = max(0, top)
    src_right = min(source.width, left + side)
    src_bottom = min(source.height, top + side)
    if src_right <= src_left or src_bottom <= src_top:
        return canvas
    piece = source.crop((src_left, src_top, src_right, src_bottom))
    canvas.paste(piece, (src_left - left, src_top - top))
    return canvas


def outline_bounds(source: Image.Image, top: int, bottom: int) -> tuple[int, int]:
    alpha = np.array(source.convert("RGBA").getchannel("A"))
    columns = np.where((alpha[top:bottom] > 16).any(0))[0]
    return int(columns.min()), int(columns.max())


def frame_full_head(source: Image.Image, marks: dict) -> Image.Image:
    """Pointed head, flat cut below the mouth, eyes on the horizontal center."""
    top = int(marks["headTop"])
    bottom = int(marks["mouthBottom"]) + 12
    left_edge, right_edge = outline_bounds(source, top, bottom)
    mid = float(marks["eyeMidX"])
    left_extent = mid - left_edge
    right_extent = right_edge - mid
    content_height = bottom - top
    # Extra square space sits above the point. The bottom stays the flat cut.
    # Search the side margin until every delivered size still clears 4%.
    chosen = None
    for margin in np.arange(0.05, 0.18, 0.005):
        half = max(left_extent, right_extent) / (1 - 2 * margin)
        side = int(np.ceil(max(content_height, 2 * half)))
        left = int(round(mid - side / 2))
        window_top = bottom - side
        framed = paste_window(source, left, window_top, side)
        if framed_margins_hold(framed):
            chosen = framed
            break
    if chosen is None:
        raise SystemExit("full-head crop cannot keep a 4% side margin")
    return chosen


def framed_margins_hold(master: Image.Image) -> bool:
    for side in (288, 180, 120, 96, 80):
        sample = quantize_color(master.resize((side, side), Image.Resampling.LANCZOS))
        stats = measure(sample)
        if stats["leftMargin"] < MARGIN * 100 or stats["rightMargin"] < MARGIN * 100:
            return False
        if abs(stats["eyeOffset"]) > 1.5:
            return False
    return True


def frame_face(source: Image.Image, marks: dict) -> tuple[Image.Image, float]:
    """Face-only square. The point is above the window and gets cut off."""
    head_height = int(marks["headHeight"])
    brow_top = int(marks["browTop"])
    mouth_bottom = int(marks["mouthBottom"]) + 10
    ideal_top = brow_top - 0.15 * head_height
    ideal_side = int(round(mouth_bottom - ideal_top))
    mid = float(marks["eyeMidX"])
    # Start at the 15% forehead window and tighten until 48px and 64px
    # both keep the eyes at least 55% wide after the side gutter.
    for side in range(ideal_side, 200, -2):
        top = mouth_bottom - side
        left = int(round(mid - side / 2))
        framed = paste_window(source, left, top, side)
        if face_sizes_hold(framed):
            return framed, (brow_top - top) / head_height
    raise SystemExit("face crop cannot keep eyes at 55% of the canvas with 4% margins")


def face_sizes_hold(master: Image.Image) -> bool:
    for side in (64, 48):
        sample = finish_face(master, side)
        stats = measure(sample)
        if stats["eyeWidthPercent"] < 55:
            return False
        if stats["leftMargin"] < MARGIN * 100 or stats["rightMargin"] < MARGIN * 100:
            return False
        if abs(stats["eyeOffset"]) > 1.5:
            return False
    return True


def quantize_color(image: Image.Image) -> Image.Image:
    reduced = image.quantize(
        colors=64,
        method=Image.Quantize.FASTOCTREE,
        dither=Image.Dither.NONE,
    )
    return reduced.convert("RGBA")


def apply_side_gutter(image: Image.Image) -> Image.Image:
    arr = np.array(image.convert("RGBA"))
    width = arr.shape[1]
    gutter = max(1, int(round(width * MARGIN)))
    arr[:, :gutter, 3] = 0
    arr[:, width - gutter :, 3] = 0
    return Image.fromarray(arr)


def finish_face(master: Image.Image, side: int) -> Image.Image:
    resized = master.resize((side, side), Image.Resampling.LANCZOS)
    reduced = quantize_color(resized)
    return apply_side_gutter(reduced)


def finish_full(master: Image.Image, side: int) -> Image.Image:
    resized = master.resize((side, side), Image.Resampling.LANCZOS)
    return quantize_color(resized)


def rim_mask(opaque: np.ndarray, radius: int = 2) -> np.ndarray:
    padded = np.pad(opaque.astype(np.uint8), radius, constant_values=0)
    near_clear = np.zeros(opaque.shape, dtype=bool)
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            window = padded[
                radius + dy : radius + dy + opaque.shape[0],
                radius + dx : radius + dx + opaque.shape[1],
            ]
            near_clear |= window == 0
    return opaque & near_clear


def split_layers(color: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Skin silhouette and face marks from the exact full-colour crop."""
    arr, red, green, blue, alpha = channels(color)
    opaque = alpha > 24
    skin = (
        opaque
        & (red > 165)
        & (red > green + 22)
        & (red > blue + 22)
        & (green > 45)
        & (green < 200)
    )
    interior = opaque & ~rim_mask(opaque, radius=2)
    light_face = interior & (red > 200) & (green > 185) & (blue > 175)
    purple_lids = interior & (blue > 110) & (blue + 12 > red) & (red > 90) & ~skin
    dark_marks = interior & ((red + green + blue) < 220) & ~skin
    features = (light_face | purple_lids | dark_marks) & ~skin
    pupil = features & ((red + green + blue) < 90) & (green < 40)
    features &= ~pupil

    def white(mask: np.ndarray) -> Image.Image:
        layer = np.zeros_like(arr)
        layer[:, :, 0] = 255
        layer[:, :, 1] = 255
        layer[:, :, 2] = 255
        layer[:, :, 3] = np.where(mask, alpha, 0)
        return Image.fromarray(layer, "RGBA")

    return white(opaque), white(features)


def measure(image: Image.Image, thresh: int = 12) -> dict:
    arr, red, green, blue, alpha = channels(image)
    height, width = alpha.shape
    white = (alpha > 80) & (red > 185) & (green > 165) & (blue > 155) & ((red + green + blue) > 500)
    white[: int(height * 0.15)] = False
    white[int(height * 0.90) :] = False
    ys, xs = np.where(white)
    if len(xs) < 8:
        raise SystemExit(f"eyes disappeared in a {width}px crop")
    center_a = float(np.percentile(xs, 15))
    center_b = float(np.percentile(xs, 85))
    for _ in range(16):
        left = np.abs(xs - center_a) <= np.abs(xs - center_b)
        if not left.any() or not (~left).any():
            break
        center_a = float(xs[left].mean())
        center_b = float(xs[~left].mean())
    if center_a > center_b:
        center_a, center_b = center_b, center_a

    def box(center: float, other: float) -> tuple[int, float]:
        selected = np.abs(xs - center) <= np.abs(xs - other)
        return int(xs[selected].max() - xs[selected].min() + 1), float(xs[selected].mean())

    width_a, mid_a = box(center_a, center_b)
    width_b, mid_b = box(center_b, center_a)
    columns = np.where((alpha > thresh).any(0))[0]
    eye_mid = (mid_a + mid_b) / 2
    return {
        "eyeOffset": round(eye_mid - width / 2, 2),
        "leftMargin": round(columns.min() / width * 100, 2),
        "rightMargin": round((width - 1 - columns.max()) / width * 100, 2),
        "eyeWidthPercent": round((width_a + width_b) / width * 100, 2),
    }


def save_png(image: Image.Image, path: Path) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)
    size = path.stat().st_size
    if size > MAX_PNG_BYTES:
        raise SystemExit(f"{path} is {size} bytes, over the {MAX_PNG_BYTES} budget")
    return size


def write_imageset(catalog: Path, name: str, image: Image.Image) -> int:
    folder = catalog / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    write_json(folder / "Contents.json", contents_json(filename))
    return save_png(image, folder / filename)


def write_catalog(catalog: Path, slots: list, masters: dict[bool, Image.Image]) -> dict:
    if catalog.exists():
        for child in catalog.rglob("*"):
            if child.is_file():
                child.unlink()
    catalog.mkdir(parents=True, exist_ok=True)
    write_json(catalog / "Contents.json", contents_json())
    report = {}
    for name, side, face_only in slots:
        color = finish_face(masters[True], side) if face_only else finish_full(masters[False], side)
        skin, features = split_layers(color)
        stats = measure(color)
        if face_only and stats["eyeWidthPercent"] < 55:
            raise SystemExit(f"{name} eyes are {stats['eyeWidthPercent']}% of the canvas")
        if stats["leftMargin"] < MARGIN * 100 or stats["rightMargin"] < MARGIN * 100:
            raise SystemExit(f"{name} side margin dropped below 4%: {stats}")
        if abs(stats["eyeOffset"]) > 1.5:
            raise SystemExit(f"{name} eyes are off center: {stats}")
        report[name] = {
            "pixels": side,
            "faceOnly": face_only,
            "colorBytes": write_imageset(catalog, name, color),
            "skinBytes": write_imageset(catalog, f"{name}Skin", skin),
            "featureBytes": write_imageset(catalog, f"{name}Features", features),
            **stats,
        }
    return report


def render_sheet(destination: Path) -> None:
    slots = [
        ("手表角落 48", WATCH_CATALOG, "PatrickHeadCorner"),
        ("手机角落 64", PHONE_CATALOG, "PatrickHeadCorner"),
        ("手表矩形 80", WATCH_CATALOG, "PatrickHeadRectangular"),
        ("手表圆形 96", WATCH_CATALOG, "PatrickHeadCircular"),
        ("手机矩形 120", PHONE_CATALOG, "PatrickHeadRectangular"),
        ("手机圆形 180", PHONE_CATALOG, "PatrickHeadCircular"),
        ("实时活动 288", PHONE_CATALOG, "PatrickHeadActivity"),
    ]
    font = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 22)
    small = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 16)
    thumb = 150
    pad = 18
    label_h = 36
    width = pad + len(slots) * (thumb + pad)
    height = 58 + pad + 2 * (thumb + label_h + pad)
    sheet = Image.new("RGB", (width, height), (28, 28, 32))
    draw = ImageDraw.Draw(sheet)
    draw.text((pad, 16), "派大星头像重裁  ·  深色 / 浅色底  ·  仍待美术确认", fill=(245, 245, 245), font=font)
    for index, (label, catalog, name) in enumerate(slots):
        color = Image.open(catalog / f"{name}.imageset" / f"{name}.png").convert("RGBA")
        for row, (bg, caption) in enumerate((((16, 16, 20), "深色底"), ((236, 236, 236), "浅色底"))):
            plate = Image.new("RGBA", (thumb, thumb), bg + (255,))
            shown = color.resize((thumb, thumb), Image.Resampling.NEAREST if color.size[0] <= 64 else Image.Resampling.LANCZOS)
            plate.alpha_composite(shown)
            x = pad + index * (thumb + pad)
            y = 58 + pad + row * (thumb + label_h + pad)
            sheet.paste(plate.convert("RGB"), (x, y))
            draw.text((x, y + thumb + 6), f"{label} · {caption}", fill=(230, 230, 230), font=small)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="contact sheet of the shipped PNGs")
    args = parser.parse_args()
    if not SOURCE.is_file():
        raise SystemExit(f"missing source frame: {SOURCE}")
    source = Image.open(SOURCE)
    marks = detect_landmarks(source)
    full = frame_full_head(source, marks)
    face, above = frame_face(source, marks)
    report = {
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "landmarks": marks,
        "faceForegroundFractionAboveBrows": round(above, 3),
        "note": "Cropped from existing art. Not a new drawing. Still needs art approval.",
        "watch": write_catalog(WATCH_CATALOG, SLOTS["watch"], {False: full, True: face}),
        "phone": write_catalog(PHONE_CATALOG, SLOTS["phone"], {False: full, True: face}),
    }
    if args.preview:
        render_sheet(args.preview)
        report["preview"] = str(args.preview)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
