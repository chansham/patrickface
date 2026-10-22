#!/usr/bin/env python3
"""Crop a Patrick head from the existing season-1 flat-colour body.

Source, unchanged:
  PatrickFace/Assets.xcassets/season1-body-normal.imageset/season1-body-normal.png

The crop keeps the baked dome, brows, eyelids, eyes and mouth, and stops
above the green shorts. Nothing here is redrawn. The result still needs
art approval; this script only cuts and scales pixels that are already
in the repository.

Watch complication bitmaps stay small. The iPhone widget / Live Activity
catalog uses the same names at higher pixel sizes so @3x lock-screen and
Dynamic Island slots stay sharp. accessoryInline cannot show a custom
image, so no inline bitmap is produced.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "PatrickFace"
    / "Assets.xcassets"
    / "season1-body-normal.imageset"
    / "season1-body-normal.png"
)

# Inclusive top, exclusive bottom of the source. Measured from the opaque
# silhouette: the dome starts at y=4, the mouth ends before y=360, and the
# arms / shorts begin below that.
CROP_TOP = 2
CROP_BOTTOM = 360

WATCH_CATALOG = ROOT / "PatrickFaceComplications" / "Avatar.xcassets"
PHONE_CATALOG = ROOT / "iOSCompanion" / "PatrickWidgets" / "Avatar.xcassets"

# Pixel sizes are the delivered bitmap, not points. Frames in SwiftUI are
# smaller than these so watch @2x and phone @3x both downsample.
SIZES = {
    "watch": {
        "PatrickHeadCircular": 96,
        "PatrickHeadRectangular": 80,
        "PatrickHeadCorner": 48,
    },
    "phone": {
        "PatrickHeadCircular": 180,
        "PatrickHeadRectangular": 120,
        "PatrickHeadCorner": 64,
        "PatrickHeadActivity": 288,
    },
}

MAX_PNG_BYTES = 48_000


def contents_json(filename: str | None = None) -> dict:
    if filename is None:
        return {"info": {"author": "xcode", "version": 1}}
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def crop_head(source: Image.Image) -> Image.Image:
    image = source.convert("RGBA")
    alpha = np.array(image.getchannel("A"))
    band = alpha[CROP_TOP:CROP_BOTTOM]
    ys, xs = np.where(band > 12)
    if len(xs) == 0:
        raise SystemExit("season-1 body has no opaque pixels in the head band")
    left_edge = int(xs.min())
    right_edge = int(xs.max()) + 1
    height = CROP_BOTTOM - CROP_TOP
    side = max(height, right_edge - left_edge)
    center = (left_edge + right_edge) / 2
    left = int(round(center - side / 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    src_left = max(0, left)
    src_top = CROP_TOP
    src_right = min(image.width, left + side)
    src_bottom = min(image.height, CROP_TOP + side)
    piece = image.crop((src_left, src_top, src_right, src_bottom))
    canvas.paste(piece, (src_left - left, src_top - CROP_TOP))
    return canvas


def rim_mask(opaque: np.ndarray, radius: int = 2) -> np.ndarray:
    """Opaque pixels within `radius` of transparency. Those are the outline."""
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
    """White skin silhouette plus white facial marks for accented rendering.

    Accented widgets keep alpha and drop RGB. The skin layer is marked
    accentable so the dome takes the watch accent. Brows, eyelids, eye
    whites and the mouth stay in the other group so they render light.
    Pupils are holes in that second layer, so the accent colour shows
    through the eyes.
    """
    arr = np.array(color)
    red = arr[:, :, 0].astype(np.int16)
    green = arr[:, :, 1].astype(np.int16)
    blue = arr[:, :, 2].astype(np.int16)
    alpha = arr[:, :, 3]
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
    # Pupils are the darkest marks that sit inside the eye, not the brows.
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


def save_png(image: Image.Image, path: Path, *, quantize: bool) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    stored = image
    if quantize:
        # Flat cel colours survive a small palette. This is compression of
        # the crop, not a redraw.
        stored = image.quantize(
            colors=64,
            method=Image.Quantize.FASTOCTREE,
            dither=Image.Dither.NONE,
        )
    stored.save(path, format="PNG", optimize=True, compress_level=9)
    size = path.stat().st_size
    if size > MAX_PNG_BYTES:
        raise SystemExit(f"{path} is {size} bytes, over the {MAX_PNG_BYTES} budget")
    return size


def write_imageset(catalog: Path, name: str, image: Image.Image, *, quantize: bool) -> int:
    folder = catalog / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    write_json(folder / "Contents.json", contents_json(filename))
    return save_png(image, folder / filename, quantize=quantize)


def write_catalog(catalog: Path, sizes: dict[str, int], master: Image.Image) -> dict:
    if catalog.exists():
        for child in catalog.rglob("*"):
            if child.is_file():
                child.unlink()
    catalog.mkdir(parents=True, exist_ok=True)
    write_json(catalog / "Contents.json", contents_json())
    report = {}
    for name, side in sizes.items():
        color = master.resize((side, side), Image.Resampling.LANCZOS)
        skin, features = split_layers(color)
        report[name] = {
            "pixels": side,
            "colorBytes": write_imageset(catalog, name, color, quantize=True),
            "skinBytes": write_imageset(catalog, f"{name}Skin", skin, quantize=False),
            "featureBytes": write_imageset(catalog, f"{name}Features", features, quantize=False),
        }
    return report


def render_preview(master: Image.Image, destination: Path) -> None:
    """Contact sheet of the phone-catalog sizes: colour, and an accent preview."""
    slots = [
        ("circular 180", 180),
        ("rectangular 120", 120),
        ("corner 64", 64),
        ("activity 288", 288),
    ]
    # Display every slot at a readable review size, plus the real corner bitmap.
    thumb = 180
    pad = 16
    label_h = 28
    cols = len(slots)
    rows = 2
    width = pad + cols * (thumb + pad)
    height = pad + rows * (thumb + label_h + pad)
    sheet = Image.new("RGB", (width, height), (32, 32, 36))
    try:
        from PIL import ImageDraw, ImageFont

        draw = ImageDraw.Draw(sheet)
        font = ImageFont.load_default()
    except Exception:
        draw = None
        font = None

    for index, (label, side) in enumerate(slots):
        color = master.resize((side, side), Image.Resampling.LANCZOS)
        skin, features = split_layers(color)
        accent = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        tint = Image.new("RGBA", (side, side), (255, 105, 180, 255))
        tint.putalpha(skin.getchannel("A"))
        accent.alpha_composite(tint)
        accent.alpha_composite(features)
        for row, (plate, caption) in enumerate(
            (
                (color, f"full colour {label}"),
                (accent, f"accented {label}"),
            )
        ):
            shown = plate.resize((thumb, thumb), Image.Resampling.NEAREST if side <= 64 else Image.Resampling.LANCZOS)
            x = pad + index * (thumb + pad)
            y = pad + row * (thumb + label_h + pad)
            tile = Image.new("RGBA", (thumb, thumb), (16, 16, 20, 255))
            tile.alpha_composite(shown)
            sheet.paste(tile.convert("RGB"), (x, y))
            if draw is not None:
                draw.text((x, y + thumb + 6), caption, fill=(230, 230, 230), font=font)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, quality=90)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--preview",
        type=Path,
        help="optional contact-sheet path; not part of the app bundle",
    )
    args = parser.parse_args()
    if not SOURCE.is_file():
        raise SystemExit(f"missing source frame: {SOURCE}")
    master = crop_head(Image.open(SOURCE))
    opaque = np.array(master.getchannel("A"))
    coverage = float((opaque > 12).mean())
    if coverage < 0.25 or coverage > 0.85:
        raise SystemExit(f"head crop coverage {coverage:.2f} is outside the expected range")
    report = {
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "cropTop": CROP_TOP,
        "cropBottom": CROP_BOTTOM,
        "masterPixels": master.size[0],
        "note": "Cropped from existing art. Not a new drawing. Still needs art approval.",
        "watch": write_catalog(WATCH_CATALOG, SIZES["watch"], master),
        "phone": write_catalog(PHONE_CATALOG, SIZES["phone"], master),
    }
    if args.preview:
        render_preview(master, args.preview)
        report["preview"] = str(args.preview)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
