"""Build the Patrick Face delivery theme pack without deleting source files.

The script composes the corrected transparent Season-1 2D and smooth Toon-3D
layers into device-sized static assets. It also synthesizes original,
non-vocal sound cues and creates machine-readable manifests.
"""

from __future__ import annotations


# Retirement guard: this runs before image libraries or filesystem setup.
# The implementation below is preserved as historical source evidence only.
# It cannot be executed or imported to recreate obsolete runtime artwork.
import argparse as _retired_argparse
import json as _retired_json

_RETIRED_MESSAGE = (
    "The historical static theme-pack builder is retired. "
    "It cannot rebuild or overwrite assets, including custom output paths. "
    "Retained artwork is historical research, not approval of the new "
    "expression/pose animation. Use --status to inspect this state."
)


def _retired_entrypoint() -> None:
    parser = _retired_argparse.ArgumentParser(description=_RETIRED_MESSAGE)
    parser.add_argument("--status", action="store_true", help="Print retirement metadata without writing files.")
    args, unsupported = parser.parse_known_args()
    if not args.status or unsupported:
        parser.error(_RETIRED_MESSAGE)
    print(_retired_json.dumps({
        "lifecycle": "retired-static-delivery",
        "retiredAt": "2026-09-27",
        "generationEnabled": False,
        "currentApproval": False,
        "newAnimationIntegrated": False,
        "message": _RETIRED_MESSAGE,
    }, indent=2))


if __name__ == "__main__":
    _retired_entrypoint()
    raise SystemExit(0)
raise RuntimeError(_RETIRED_MESSAGE)


import argparse
import csv
import hashlib
import json
import math
import shutil
import struct
import subprocess
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


PACKAGE = Path(__file__).resolve().parent.parent
PROJECT = PACKAGE.parent.parent
FONT_REGULAR = Path(r"C:\Windows\Fonts\segoeui.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\segoeuib.ttf")
PACKAGE_VERSION = "1.0.1"

SOURCES = {
    "2d_body_preview": PROJECT / "preview" / "assets" / "season1-body-normal.png",
    "2d_body_clean": PROJECT / "preview" / "assets" / "season1-body-normal.png",
    "2d_hour_arm": PROJECT / "preview" / "assets" / "season1-hour-arm.png",
    "2d_minute_arm": PROJECT / "preview" / "assets" / "season1-minute-arm.png",
    "3d_body": PROJECT / "preview" / "assets" / "season1-3d-body.png",
    "3d_arm": PROJECT / "preview" / "assets" / "season1-3d-arm.png",
}

IPHONE_DISPLAYS = {
    "iphone-16": (1179, 2556),
    "iphone-16-plus": (1290, 2796),
    "iphone-16-pro": (1206, 2622),
    "iphone-16-pro-max": (1320, 2868),
}

WATCH_DISPLAYS = {
    "series-10-42mm": (374, 446),
    "series-10-46mm": (416, 496),
    "ultra-2-49mm": (410, 502),
}

STYLE_META = {
    "2d": {
        "label": "Season-1 clean cel",
        "source": (
            "Candidate RGBA body from preview/assets/season1-body-normal.png "
            "with clean hour/minute arm layers from preview/assets"
        ),
        "top": (4, 10, 29),
        "bottom": (9, 46, 64),
        "glow": (232, 100, 124, 105),
        "accent": (178, 205, 45),
    },
    "3d": {
        "label": "Season-1 smooth Toon 3D",
        "source": (
            "Candidate RGBA body and arm layers from "
            "preview/assets/season1-3d-body.png and season1-3d-arm.png"
        ),
        "top": (13, 6, 29),
        "bottom": (47, 25, 56),
        "glow": (240, 116, 103, 100),
        "accent": (125, 78, 139),
    },
}

ASSET_RECORDS: list[dict[str, Any]] = []


def ensure_sources() -> None:
    missing = [str(path) for path in SOURCES.values() if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing candidate source layer(s):\n" + "\n".join(missing))


def relative(path: Path) -> str:
    return path.relative_to(PACKAGE).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def add_record(
    path: Path,
    *,
    category: str,
    style: str,
    source: str,
    destination: str,
    width: int | None = None,
    height: int | None = None,
    duration_seconds: float | None = None,
    sample_rate: int | None = None,
    channels: int | None = None,
    codec: str | None = None,
    notes: str = "",
) -> None:
    record: dict[str, Any] = {
        "path": relative(path),
        "category": category,
        "format": path.suffix.lower().lstrip("."),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "source": source,
        "style": style,
        "intended_destination": destination,
    }
    if width is not None:
        record["width"] = width
    if height is not None:
        record["height"] = height
    if duration_seconds is not None:
        record["duration_seconds"] = round(duration_seconds, 3)
    if sample_rate is not None:
        record["sample_rate_hz"] = sample_rate
    if channels is not None:
        record["channels"] = channels
    if codec is not None:
        record["codec"] = codec
    if notes:
        record["notes"] = notes
    ASSET_RECORDS.append(record)


def save_image(
    image: Image.Image,
    path: Path,
    *,
    category: str,
    style: str,
    source: str,
    destination: str,
    notes: str = "",
    quality: int = 94,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {".jpg", ".jpeg"}:
        image.convert("RGB").save(path, quality=quality, optimize=True, progressive=True)
    else:
        image.save(path, optimize=True)
    add_record(
        path,
        category=category,
        style=style,
        source=source,
        destination=destination,
        width=image.width,
        height=image.height,
        notes=notes,
    )


def load_rgba(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] == 255:
        raise ValueError(f"Expected transparent RGBA layer: {path}")
    return image


def resize_contain(image: Image.Image, max_width: int, max_height: int) -> Image.Image:
    scale = min(max_width / image.width, max_height / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


def star_points(
    cx: float,
    cy: float,
    outer: float,
    inner: float | None = None,
    rotation: float = -math.pi / 2,
) -> list[tuple[float, float]]:
    inner = inner if inner is not None else outer * 0.46
    points: list[tuple[float, float]] = []
    for index in range(10):
        radius = outer if index % 2 == 0 else inner
        angle = rotation + index * math.pi / 5
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def paste_arm(
    canvas: Image.Image,
    arm: Image.Image,
    *,
    pivot: tuple[int, int],
    length: int,
    angle: float,
    mirror: bool = False,
) -> None:
    source = ImageOps.mirror(arm) if mirror else arm
    width = max(1, round(length * source.width / source.height))
    resized = source.resize((width, length), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", canvas.size)
    x = pivot[0] - width // 2
    y = pivot[1] - length
    layer.alpha_composite(resized, (x, y))
    rotated = layer.rotate(
        angle,
        resample=Image.Resampling.BICUBIC,
        center=pivot,
        expand=False,
    )
    canvas.alpha_composite(rotated)


def compose_character(
    style: str,
    body: Image.Image,
    hour_arm: Image.Image,
    minute_arm: Image.Image,
) -> Image.Image:
    body_height = 1500
    body_width = round(body.width / body.height * body_height)
    body_scaled = body.resize((body_width, body_height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (1900, 1780))
    body_x = (canvas.width - body_width) // 2
    body_y = 245
    pivot_y = body_y + round(body_height * (0.48 if style == "3d" else 0.47))
    pivot_x = canvas.width // 2
    paste_arm(
        canvas,
        hour_arm,
        pivot=(pivot_x - 18, pivot_y),
        length=650 if style == "2d" else 625,
        angle=55,
        mirror=True,
    )
    paste_arm(
        canvas,
        minute_arm,
        pivot=(pivot_x + 18, pivot_y),
        length=795 if style == "2d" else 780,
        angle=-55,
        mirror=False,
    )
    canvas.alpha_composite(body_scaled, (body_x, body_y))
    bbox = canvas.getchannel("A").getbbox()
    if not bbox:
        raise RuntimeError(f"Character composition is empty: {style}")
    left, top, right, bottom = bbox
    pad = 24
    return canvas.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(canvas.width, right + pad),
            min(canvas.height, bottom + pad),
        )
    )


def make_background(width: int, height: int, style: str, seed: int) -> Image.Image:
    meta = STYLE_META[style]
    top = np.array(meta["top"], dtype=np.float32)
    bottom = np.array(meta["bottom"], dtype=np.float32)
    y = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None, None]
    rgb = top[None, None, :] * (1.0 - y) + bottom[None, None, :] * y
    rgb = np.repeat(rgb, width, axis=1)

    x_norm = np.linspace(-1.0, 1.0, width, dtype=np.float32)[None, :]
    y_norm = np.linspace(-1.0, 1.0, height, dtype=np.float32)[:, None]
    vignette = np.clip((x_norm * x_norm * 0.52 + y_norm * y_norm * 0.18), 0.0, 1.0)
    rgb *= (1.0 - vignette[..., None] * 0.23)

    rng = np.random.default_rng(seed)
    noise_small = rng.normal(0, 1.8, (max(2, height // 16), max(2, width // 16), 1))
    noise_small = np.repeat(noise_small, 3, axis=2)
    noise = Image.fromarray(np.uint8(np.clip(noise_small + 128, 0, 255)), "RGB").resize(
        (width, height), Image.Resampling.BILINEAR
    )
    image = Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), "RGB").convert("RGBA")
    texture = Image.blend(Image.new("RGB", (width, height), (128, 128, 128)), noise, 0.35)
    image = Image.blend(image.convert("RGB"), Image.blend(image.convert("RGB"), texture, 0.055), 0.4).convert("RGBA")

    glow = Image.new("RGBA", (width, height))
    glow_draw = ImageDraw.Draw(glow)
    radius = int(min(width, height) * 0.53)
    cx = int(width * (0.50 if width < height else (0.28 if style == "2d" else 0.72)))
    cy = int(height * (0.70 if width < height else 0.56))
    color = meta["glow"]
    glow_draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(max(24, int(radius * 0.42))))
    image.alpha_composite(glow)

    bubbles = Image.new("RGBA", (width, height))
    bubble_draw = ImageDraw.Draw(bubbles)
    for index in range(22):
        radius = int(rng.uniform(0.008, 0.032) * min(width, height))
        bx = int(rng.uniform(0.05, 0.95) * width)
        by = int(rng.uniform(0.08, 0.92) * height)
        alpha = int(rng.uniform(10, 30))
        stroke = max(1, round(min(width, height) / 500))
        bubble_draw.ellipse(
            (bx - radius, by - radius, bx + radius, by + radius),
            outline=(225, 239, 244, alpha),
            width=stroke,
        )
        if index % 3 == 0:
            bubble_draw.ellipse(
                (
                    bx - radius * 0.45,
                    by - radius * 0.58,
                    bx - radius * 0.16,
                    by - radius * 0.29,
                ),
                fill=(255, 255, 255, alpha + 9),
            )
    image.alpha_composite(bubbles)
    return image


def paste_character(
    background: Image.Image,
    character: Image.Image,
    *,
    max_width: int,
    max_height: int,
    center_x: int,
    bottom_y: int,
    opacity: float = 1.0,
    shadow_blur: int | None = None,
) -> Image.Image:
    output = background.convert("RGBA")
    scaled = resize_contain(character, max_width, max_height)
    if opacity < 1.0:
        alpha = scaled.getchannel("A").point(lambda value: round(value * opacity))
        scaled.putalpha(alpha)
    x = center_x - scaled.width // 2
    y = bottom_y - scaled.height
    shadow_mask = scaled.getchannel("A")
    blur = shadow_blur if shadow_blur is not None else max(12, round(min(background.size) * 0.022))
    shadow = Image.new("RGBA", output.size)
    shadow_shape = Image.new("RGBA", scaled.size, (0, 0, 0, 0))
    shadow_shape.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(blur)))
    dark = Image.new("RGBA", scaled.size, (0, 0, 0, 118))
    dark.putalpha(shadow_shape.getchannel("A"))
    shadow.alpha_composite(dark, (x + blur // 3, y + blur // 2))
    output.alpha_composite(shadow)
    output.alpha_composite(scaled, (x, y))
    return output


def make_wallpaper(
    width: int,
    height: int,
    style: str,
    character: Image.Image,
    kind: str,
    seed: int,
) -> Image.Image:
    background = make_background(width, height, style, seed)
    if kind == "lock":
        output = paste_character(
            background,
            character,
            max_width=round(width * 1.02),
            max_height=round(height * 0.64),
            center_x=width // 2,
            bottom_y=round(height * 0.982),
        )
        top_shade = Image.new("RGBA", (width, round(height * 0.36)), (0, 0, 0, 0))
        alpha = Image.linear_gradient("L").resize(top_shade.size).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        alpha = alpha.point(lambda value: round(value * 0.25))
        top_shade.putalpha(alpha)
        output.alpha_composite(top_shade, (0, 0))
    elif kind == "home":
        center = round(width * (0.69 if style == "2d" else 0.31))
        output = paste_character(
            background,
            character,
            max_width=round(width * 0.80),
            max_height=round(height * 0.50),
            center_x=center,
            bottom_y=round(height * 0.99),
            opacity=0.83,
        )
        readability = Image.new("RGBA", output.size, (1, 5, 17, 58))
        output.alpha_composite(readability)
    else:
        raise ValueError(kind)
    return output.convert("RGB")


def make_standby(
    width: int,
    height: int,
    style: str,
    character: Image.Image,
    seed: int,
) -> Image.Image:
    background = make_background(width, height, style, seed)
    character_center = round(width * (0.27 if style == "2d" else 0.73))
    output = paste_character(
        background,
        character,
        max_width=round(width * 0.47),
        max_height=round(height * 0.92),
        center_x=character_center,
        bottom_y=round(height * 0.98),
    )
    safe_overlay = Image.new("RGBA", output.size)
    draw = ImageDraw.Draw(safe_overlay)
    if style == "2d":
        draw.rounded_rectangle(
            (
                round(width * 0.53),
                round(height * 0.15),
                round(width * 0.92),
                round(height * 0.85),
            ),
            radius=round(height * 0.08),
            fill=(1, 5, 17, 34),
            outline=(255, 255, 255, 14),
            width=max(1, height // 300),
        )
    else:
        draw.rounded_rectangle(
            (
                round(width * 0.08),
                round(height * 0.15),
                round(width * 0.47),
                round(height * 0.85),
            ),
            radius=round(height * 0.08),
            fill=(1, 5, 17, 34),
            outline=(255, 255, 255, 14),
            width=max(1, height // 300),
        )
    output.alpha_composite(safe_overlay)
    return output.convert("RGB")


def make_watch_face(
    width: int,
    height: int,
    style: str,
    character: Image.Image,
    time_position: str,
) -> Image.Image:
    background = make_background(width, height, style, width * 13 + height)
    draw = ImageDraw.Draw(background)
    margin = max(10, round(width * 0.045))
    draw.rounded_rectangle(
        (margin, margin, width - margin, height - margin),
        radius=max(20, round(width * 0.13)),
        outline=(255, 255, 255, 25),
        width=max(1, width // 190),
    )
    if time_position == "top":
        max_height = round(height * 0.68)
        bottom = round(height * 0.97)
    else:
        max_height = round(height * 0.66)
        bottom = round(height * 0.72)
    output = paste_character(
        background,
        character,
        max_width=round(width * 0.96),
        max_height=max_height,
        center_x=width // 2,
        bottom_y=bottom,
        shadow_blur=max(5, width // 35),
    )
    return output.convert("RGB")


def make_widget(
    width: int,
    height: int,
    style: str,
    character: Image.Image,
    family: str,
) -> Image.Image:
    background = make_background(width, height, style, width + height * 7)
    draw = ImageDraw.Draw(background)
    accent = STYLE_META[style]["accent"]
    stroke = max(4, round(min(width, height) * 0.018))
    draw.arc(
        (
            round(width * 0.08),
            round(height * 0.08),
            round(width * 0.44),
            round(height * 0.44),
        ),
        190,
        350,
        fill=(*accent, 125),
        width=stroke,
    )
    if family == "small":
        output = paste_character(
            background,
            character,
            max_width=round(width * 0.98),
            max_height=round(height * 0.88),
            center_x=round(width * 0.57),
            bottom_y=round(height * 1.02),
            shadow_blur=max(8, width // 28),
        )
    elif family == "medium":
        center = round(width * (0.27 if style == "2d" else 0.73))
        output = paste_character(
            background,
            character,
            max_width=round(width * 0.52),
            max_height=round(height * 0.95),
            center_x=center,
            bottom_y=round(height * 1.05),
            shadow_blur=max(8, height // 24),
        )
        empty_left = style == "3d"
        x0 = round(width * (0.07 if empty_left else 0.56))
        x1 = round(width * (0.44 if empty_left else 0.93))
        overlay = Image.new("RGBA", output.size)
        odraw = ImageDraw.Draw(overlay)
        for index in range(3):
            y = round(height * (0.30 + index * 0.18))
            odraw.rounded_rectangle(
                (x0, y, x1 - index * round(width * 0.045), y + round(height * 0.045)),
                radius=round(height * 0.02),
                fill=(255, 255, 255, 24),
            )
        output.alpha_composite(overlay)
    elif family == "large":
        output = paste_character(
            background,
            character,
            max_width=round(width * 0.94),
            max_height=round(height * 0.82),
            center_x=width // 2,
            bottom_y=round(height * 1.01),
            shadow_blur=max(8, width // 25),
        )
    else:
        raise ValueError(family)
    return output.convert("RGB")


def make_accessory(
    width: int,
    height: int,
    style: str,
    character: Image.Image,
    family: str,
    transparent: bool = False,
) -> Image.Image:
    if transparent:
        output = Image.new("RGBA", (width, height))
        draw = ImageDraw.Draw(output)
        size = min(width, height) * 0.41
        draw.polygon(
            star_points(width / 2, height / 2, size, size * 0.43),
            fill=(255, 255, 255, 255),
        )
        inner = size * 0.19
        draw.ellipse(
            (
                width / 2 - inner,
                height / 2 - inner,
                width / 2 + inner,
                height / 2 + inner,
            ),
            fill=(0, 0, 0, 0),
        )
        return output

    background = make_background(width, height, style, width * 3 + height * 11)
    if family == "circular":
        side = min(width, height)
        crop = resize_contain(character, round(side * 1.15), round(side * 1.25))
        x = width // 2 - crop.width // 2
        y = round(height * 0.14)
        background.alpha_composite(crop, (x, y))
        mask = Image.new("L", (width, height))
        ImageDraw.Draw(mask).ellipse((1, 1, width - 2, height - 2), fill=255)
        background.putalpha(mask)
    else:
        center = round(width * (0.20 if style == "2d" else 0.80))
        background = paste_character(
            background,
            character,
            max_width=round(width * 0.42),
            max_height=round(height * 1.22),
            center_x=center,
            bottom_y=round(height * 1.10),
            shadow_blur=max(3, height // 18),
        )
        draw = ImageDraw.Draw(background)
        if style == "2d":
            start, end = round(width * 0.47), round(width * 0.92)
        else:
            start, end = round(width * 0.08), round(width * 0.53)
        for index, factor in enumerate((1.0, 0.82, 0.62)):
            y = round(height * (0.31 + index * 0.20))
            draw.rounded_rectangle(
                (start, y, start + round((end - start) * factor), y + max(3, height // 28)),
                radius=max(2, height // 56),
                fill=(255, 255, 255, 45),
            )
    return background


def draw_heart(draw: ImageDraw.ImageDraw, center: tuple[int, int], size: int, fill: tuple[int, ...]) -> None:
    points: list[tuple[float, float]] = []
    for index in range(181):
        t = index / 180 * math.pi * 2
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((center[0] + x / 34 * size, center[1] - y / 34 * size))
    draw.polygon(points, fill=fill)


def draw_icon_glyph(
    draw: ImageDraw.ImageDraw,
    name: str,
    color: tuple[int, int, int, int],
    accent: tuple[int, int, int, int],
) -> None:
    sw = 42
    box = (264, 264, 760, 760)
    if name == "phone":
        draw.arc((286, 270, 724, 730), 128, 315, fill=color, width=88)
        draw.rounded_rectangle((250, 555, 390, 710), 50, fill=color)
        draw.rounded_rectangle((630, 280, 770, 435), 50, fill=color)
    elif name == "messages":
        draw.rounded_rectangle((230, 275, 795, 680), 150, fill=color)
        draw.polygon([(350, 650), (280, 790), (475, 670)], fill=color)
        for x in (390, 512, 634):
            draw.ellipse((x - 25, 455 - 25, x + 25, 455 + 25), fill=accent)
    elif name == "mail":
        draw.rounded_rectangle((210, 300, 814, 718), 65, outline=color, width=sw)
        draw.line((235, 337, 512, 555, 789, 337), fill=color, width=sw, joint="curve")
        draw.line((235, 681, 430, 502), fill=color, width=sw)
        draw.line((789, 681, 594, 502), fill=color, width=sw)
    elif name == "safari":
        draw.ellipse(box, outline=color, width=sw)
        draw.line((512, 310, 430, 545), fill=accent, width=64)
        draw.polygon([(512, 300), (455, 540), (572, 477)], fill=accent)
        draw.polygon([(512, 724), (569, 484), (452, 547)], fill=color)
    elif name == "camera":
        draw.rounded_rectangle((210, 340, 814, 728), 85, outline=color, width=sw)
        draw.rounded_rectangle((350, 275, 520, 380), 34, fill=color)
        draw.ellipse((390, 408, 634, 652), outline=color, width=sw)
        draw.ellipse((470, 488, 554, 572), fill=accent)
    elif name == "photos":
        for index, petal_color in enumerate(
            [(245, 116, 112, 255), (244, 177, 75, 255), (183, 205, 51, 255), (70, 182, 169, 255), (111, 135, 207, 255), (143, 90, 158, 255)]
        ):
            angle = index * math.pi / 3 - math.pi / 2
            cx = 512 + math.cos(angle) * 145
            cy = 512 + math.sin(angle) * 145
            draw.ellipse((cx - 105, cy - 145, cx + 105, cy + 145), fill=petal_color)
        draw.ellipse((430, 430, 594, 594), fill=color)
    elif name == "music":
        draw.line((460, 300, 690, 250, 690, 620), fill=color, width=sw)
        draw.line((460, 355, 690, 305), fill=color, width=sw)
        draw.ellipse((320, 585, 500, 735), fill=color)
        draw.ellipse((550, 545, 730, 695), fill=color)
        draw.line((460, 340, 460, 640), fill=color, width=sw)
    elif name == "maps":
        draw.ellipse((325, 240, 699, 614), fill=color)
        draw.polygon([(365, 520), (512, 790), (659, 520)], fill=color)
        draw.ellipse((430, 345, 594, 509), fill=accent)
    elif name == "calendar":
        draw.rounded_rectangle((230, 250, 794, 760), 68, fill=color)
        draw.rectangle((230, 250, 794, 390), fill=accent)
        font = ImageFont.truetype(str(FONT_BOLD), 255)
        text = "24"
        text_box = draw.textbbox((0, 0), text, font=font)
        tx = 512 - (text_box[2] - text_box[0]) / 2
        draw.text((tx, 410), text, font=font, fill=(22, 21, 36, 255))
    elif name == "clock":
        draw.ellipse(box, outline=color, width=sw)
        draw.line((512, 512, 512, 350), fill=color, width=sw)
        draw.line((512, 512, 638, 590), fill=accent, width=sw)
        draw.ellipse((484, 484, 540, 540), fill=color)
    elif name == "notes":
        draw.rounded_rectangle((245, 220, 779, 795), 66, fill=color)
        draw.rectangle((245, 220, 779, 340), fill=accent)
        for y, factor in ((435, 1.0), (535, 0.82), (635, 0.92)):
            draw.rounded_rectangle((330, y, 330 + round(360 * factor), y + 30), 15, fill=(33, 33, 50, 180))
    elif name == "reminders":
        for index, dot in enumerate([(238, 170, 193, 255), (180, 205, 53, 255), (121, 90, 157, 255)]):
            y = 340 + index * 170
            draw.ellipse((250, y - 37, 324, y + 37), fill=dot)
            draw.rounded_rectangle((370, y - 20, 770, y + 20), 20, fill=color)
    elif name == "settings":
        for index in range(8):
            angle = index * math.pi / 4
            x1 = 512 + math.cos(angle) * 165
            y1 = 512 + math.sin(angle) * 165
            x2 = 512 + math.cos(angle) * 245
            y2 = 512 + math.sin(angle) * 245
            draw.line((x1, y1, x2, y2), fill=color, width=90)
        draw.ellipse((330, 330, 694, 694), fill=color)
        draw.ellipse((430, 430, 594, 594), fill=accent)
    elif name == "wallet":
        draw.rounded_rectangle((210, 310, 814, 735), 85, fill=color)
        draw.rounded_rectangle((470, 425, 835, 620), 65, fill=accent)
        draw.ellipse((715, 485, 765, 535), fill=color)
        draw.rounded_rectangle((270, 245, 690, 390), 45, fill=(177, 204, 50, 255))
    elif name == "weather":
        draw.ellipse((505, 255, 745, 495), fill=(241, 184, 72, 255))
        draw.ellipse((230, 455, 560, 725), fill=color)
        draw.ellipse((405, 380, 700, 720), fill=color)
        draw.rounded_rectangle((255, 560, 790, 730), 85, fill=color)
    elif name == "health":
        draw_heart(draw, (512, 525), 540, (242, 102, 123, 255))
        draw.line((280, 525, 405, 525, 465, 410, 550, 635, 615, 525, 745, 525), fill=color, width=34, joint="curve")
    elif name == "files":
        draw.rounded_rectangle((205, 350, 819, 770), 78, fill=color)
        draw.polygon([(205, 350), (205, 270), (465, 270), (550, 350)], fill=color)
        draw.rounded_rectangle((205, 390, 819, 770), 78, fill=(221, 236, 244, 255))
    elif name == "shortcuts":
        draw.rounded_rectangle((262, 250, 620, 610), 100, outline=color, width=70)
        draw.rounded_rectangle((405, 405, 762, 765), 100, outline=accent, width=70)
    elif name == "home":
        draw.polygon([(185, 500), (512, 235), (839, 500)], fill=color)
        draw.rounded_rectangle((270, 465, 754, 770), 45, fill=color)
        draw.rounded_rectangle((445, 560, 580, 770), 30, fill=accent)
    elif name == "calculator":
        draw.rounded_rectangle((250, 220, 774, 804), 80, outline=color, width=sw)
        draw.rounded_rectangle((325, 300, 699, 410), 24, fill=color)
        for row in range(2):
            for col in range(3):
                cx = 365 + col * 148
                cy = 535 + row * 145
                draw.ellipse((cx - 47, cy - 47, cx + 47, cy + 47), fill=accent if col == 2 else color)
    else:
        raise ValueError(name)


def make_app_icon(name: str, color_index: int) -> Image.Image:
    palettes = [
        ((8, 20, 43), (17, 52, 72), (243, 141, 164), (184, 207, 51)),
        ((24, 10, 37), (60, 31, 65), (239, 125, 115), (188, 210, 62)),
        ((4, 27, 39), (13, 70, 72), (240, 142, 158), (131, 89, 153)),
        ((27, 14, 28), (74, 39, 58), (183, 204, 51), (244, 139, 158)),
    ]
    top, bottom, glyph, accent = palettes[color_index % len(palettes)]
    y = np.linspace(0.0, 1.0, 1024, dtype=np.float32)[:, None, None]
    rgb = np.array(top)[None, None, :] * (1 - y) + np.array(bottom)[None, None, :] * y
    rgb = np.repeat(rgb, 1024, axis=1)
    image = Image.fromarray(np.uint8(rgb), "RGB").convert("RGBA")
    draw = ImageDraw.Draw(image)
    draw.polygon(star_points(835, 842, 285, 125, -0.94), fill=(241, 128, 145, 34))
    draw.ellipse((98, 91, 926, 919), outline=(255, 255, 255, 18), width=4)
    draw_icon_glyph(draw, name, (*glyph, 255), (*accent, 255))
    return image.convert("RGB")


def envelope(length: int, attack: float, release: float, decay: float = 0.0) -> np.ndarray:
    values = np.ones(length, dtype=np.float64)
    attack_count = max(1, round(length * attack))
    release_count = max(1, round(length * release))
    values[:attack_count] = np.linspace(0.0, 1.0, attack_count)
    values[-release_count:] *= np.linspace(1.0, 0.0, release_count)
    if decay > 0:
        values *= np.exp(-np.linspace(0.0, decay, length))
    return values


def add_tone(
    output: np.ndarray,
    sample_rate: int,
    start: float,
    duration: float,
    frequency: float,
    amplitude: float,
    pan: float,
    *,
    harmonics: tuple[tuple[float, float], ...] = (),
    attack: float = 0.03,
    release: float = 0.35,
    decay: float = 1.5,
    end_frequency: float | None = None,
) -> None:
    first = round(start * sample_rate)
    count = min(round(duration * sample_rate), output.shape[0] - first)
    if count <= 0:
        return
    t = np.arange(count, dtype=np.float64) / sample_rate
    if end_frequency is None:
        phase = 2 * math.pi * frequency * t
    else:
        slope = (end_frequency - frequency) / max(duration, 1e-6)
        phase = 2 * math.pi * (frequency * t + 0.5 * slope * t * t)
    wave_data = np.sin(phase)
    for multiple, level in harmonics:
        wave_data += level * np.sin(phase * multiple + multiple * 0.13)
    wave_data *= envelope(count, attack, release, decay) * amplitude
    left_gain = math.cos((pan + 1) * math.pi / 4)
    right_gain = math.sin((pan + 1) * math.pi / 4)
    output[first : first + count, 0] += wave_data * left_gain
    output[first : first + count, 1] += wave_data * right_gain


def synthesize_cue(name: str, sample_rate: int = 48_000) -> np.ndarray:
    durations = {
        "charge": 1.45,
        "disconnect": 1.10,
        "hour-chime": 2.75,
        "low-battery": 1.55,
        "sleep-focus": 3.60,
    }
    output = np.zeros((round(durations[name] * sample_rate), 2), dtype=np.float64)
    bell_harmonics = ((2.01, 0.32), (3.98, 0.13), (6.12, 0.06))
    soft_harmonics = ((2.0, 0.12), (3.0, 0.05))
    if name == "charge":
        for start, freq, pan in ((0.00, 523.25, -0.35), (0.18, 659.25, 0.0), (0.38, 783.99, 0.35)):
            add_tone(output, sample_rate, start, 0.82, freq, 0.33, pan, harmonics=bell_harmonics, decay=2.7)
        add_tone(output, sample_rate, 0.16, 0.62, 310, 0.15, 0.0, end_frequency=920, decay=3.5, attack=0.08)
    elif name == "disconnect":
        for start, freq, pan in ((0.00, 698.46, 0.25), (0.17, 493.88, 0.0), (0.34, 349.23, -0.25)):
            add_tone(output, sample_rate, start, 0.62, freq, 0.31, pan, harmonics=soft_harmonics, decay=3.0)
        add_tone(output, sample_rate, 0.04, 0.54, 520, 0.11, 0.0, end_frequency=190, decay=4.0)
    elif name == "hour-chime":
        for start, freq, pan in ((0.00, 293.66, -0.22), (0.34, 440.00, 0.22), (0.73, 587.33, -0.10), (1.14, 880.00, 0.10)):
            add_tone(output, sample_rate, start, 1.45, freq, 0.28, pan, harmonics=bell_harmonics, decay=2.3, release=0.45)
        add_tone(output, sample_rate, 0.0, 2.55, 73.42, 0.06, 0.0, harmonics=((2.0, 0.5),), decay=2.0, attack=0.15)
    elif name == "low-battery":
        for start, freq, pan in ((0.00, 220.00, -0.12), (0.54, 174.61, 0.12)):
            add_tone(output, sample_rate, start, 0.62, freq, 0.34, pan, harmonics=((2.0, 0.08),), decay=3.8, attack=0.02)
        add_tone(output, sample_rate, 0.02, 1.22, 310, 0.10, 0.0, end_frequency=130, decay=3.2, attack=0.08)
    elif name == "sleep-focus":
        for freq, pan, amp in ((174.61, -0.45, 0.14), (220.00, 0.0, 0.13), (261.63, 0.45, 0.12)):
            add_tone(output, sample_rate, 0.0, 3.45, freq, amp, pan, harmonics=((2.0, 0.08),), attack=0.22, release=0.42, decay=0.65)
        for start, freq, pan in ((0.25, 523.25, -0.2), (1.10, 392.00, 0.2), (1.95, 329.63, -0.1)):
            add_tone(output, sample_rate, start, 1.10, freq, 0.17, pan, harmonics=bell_harmonics, decay=2.7, attack=0.06)
    else:
        raise ValueError(name)

    peak = float(np.max(np.abs(output)))
    if peak:
        output *= 0.82 / peak
    fade = max(1, round(sample_rate * 0.035))
    output[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None]
    return output


def write_wav(path: Path, samples: np.ndarray, sample_rate: int = 48_000) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        with wave.open(str(path), "rb") as handle:
            expected_frames = samples.shape[0]
            if (
                handle.getnchannels() != 2
                or handle.getsampwidth() != 2
                or handle.getframerate() != sample_rate
                or handle.getnframes() != expected_frames
            ):
                raise ValueError(f"Existing WAV does not match expected format: {path}")
        return
    pcm = np.int16(np.clip(samples, -1.0, 1.0) * 32767)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm.astype("<i2").tobytes())


def make_waveform_sheet(wav_paths: list[Path]) -> Image.Image:
    width = 1800
    row_height = 250
    margin = 80
    image = Image.new("RGB", (width, margin * 2 + len(wav_paths) * row_height), (7, 11, 24))
    draw = ImageDraw.Draw(image)
    title_font = ImageFont.truetype(str(FONT_BOLD), 34)
    label_font = ImageFont.truetype(str(FONT_REGULAR), 28)
    for index, path in enumerate(wav_paths):
        with wave.open(str(path), "rb") as handle:
            frames = handle.readframes(handle.getnframes())
            channels = handle.getnchannels()
        samples = np.frombuffer(frames, dtype="<i2").reshape(-1, channels).mean(axis=1) / 32768.0
        graph_left = 390
        graph_right = width - 90
        graph_width = graph_right - graph_left
        step = max(1, len(samples) // graph_width)
        reduced = np.array(
            [np.max(np.abs(samples[pos : pos + step])) for pos in range(0, len(samples), step)]
        )[:graph_width]
        y_center = margin + index * row_height + row_height // 2
        draw.rounded_rectangle(
            (graph_left - 20, y_center - 88, graph_right + 20, y_center + 88),
            28,
            fill=(13, 28, 45),
            outline=(255, 255, 255, 22),
            width=2,
        )
        points_top = [
            (graph_left + x, y_center - float(value) * 70) for x, value in enumerate(reduced)
        ]
        points_bottom = [
            (graph_left + x, y_center + float(value) * 70)
            for x, value in reversed(list(enumerate(reduced)))
        ]
        draw.polygon(points_top + points_bottom, fill=(238, 128, 151))
        draw.text((85, y_center - 30), path.stem.replace("-", " ").upper(), font=label_font, fill=(244, 241, 244))
    draw.text((80, 24), "ORIGINAL NON-VOCAL THEME CUES", font=title_font, fill=(244, 241, 244))
    return image


def make_contact_sheet(
    entries: list[tuple[Path, str]],
    *,
    columns: int,
    thumb_size: tuple[int, int],
    title: str,
) -> Image.Image:
    cell_width = thumb_size[0] + 54
    cell_height = thumb_size[1] + 92
    rows = math.ceil(len(entries) / columns)
    sheet = Image.new(
        "RGB",
        (columns * cell_width + 54, rows * cell_height + 130),
        (8, 11, 20),
    )
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.truetype(str(FONT_BOLD), 38)
    label_font = ImageFont.truetype(str(FONT_REGULAR), 21)
    draw.text((54, 38), title, font=title_font, fill=(245, 241, 244))
    for index, (path, label) in enumerate(entries):
        col = index % columns
        row = index // columns
        left = 54 + col * cell_width
        top = 112 + row * cell_height
        source = Image.open(path).convert("RGBA")
        thumb = resize_contain(source, thumb_size[0], thumb_size[1])
        frame = Image.new("RGBA", thumb_size, (15, 22, 34, 255))
        x = (thumb_size[0] - thumb.width) // 2
        y = (thumb_size[1] - thumb.height) // 2
        frame.alpha_composite(thumb, (x, y))
        sheet.paste(frame.convert("RGB"), (left, top))
        clipped = label if len(label) <= 31 else label[:29] + "…"
        draw.text((left, top + thumb_size[1] + 18), clipped, font=label_font, fill=(202, 195, 204))
    return sheet


def write_qr(payload: str, payload_path: Path, image_path: Path) -> None:
    payload_path.parent.mkdir(parents=True, exist_ok=True)
    if payload_path.exists():
        if payload_path.read_bytes() != payload.encode("utf-8"):
            raise ValueError(f"Existing QR payload differs: {payload_path}")
    else:
        # Do not append CR/LF: qrencodesrc treats every byte as payload data.
        payload_path.write_bytes(payload.encode("utf-8"))
    if not image_path.exists():
        escaped = payload_path.resolve().as_posix().replace(":", r"\:")
        filter_value = (
            f"qrencodesrc=textfile='{escaped}':"
            "qrcode_width=780:padded_qrcode_width=900:level=H:expansion=none:"
            "foreground_color=0x111827:background_color=0xF8FAFC"
        )
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            filter_value,
            "-frames:v",
            "1",
            str(image_path),
        ]
        subprocess.run(command, check=True)
    image = Image.open(image_path)
    add_record(
        image_path,
        category="qr-deep-link",
        style="Official Shortcuts URL-scheme fallback",
        source=f"Payload: {payload}",
        destination="Scan with iPhone Camera; requires the named shortcut to already exist when using run-shortcut.",
        width=image.width,
        height=image.height,
        notes="QR is a launcher/fallback only. It does not import a personal automation.",
    )


def copy_source_layers() -> None:
    target = PACKAGE / "source-layers"
    target.mkdir(parents=True, exist_ok=True)
    copy_names = {
        "2d_body_preview": "season1-2d-body-preview-approved.png",
        "2d_body_clean": "season1-2d-body-clean-approved.png",
        "2d_hour_arm": "season1-2d-hour-arm-approved.png",
        "2d_minute_arm": "season1-2d-minute-arm-approved.png",
        "3d_body": "season1-3d-body-approved.png",
        "3d_arm": "season1-3d-arm-approved.png",
    }
    for key, filename in copy_names.items():
        destination = target / filename
        shutil.copy2(SOURCES[key], destination)
        image = Image.open(destination)
        add_record(
            destination,
            category="candidate-source-layer",
            style="Current runtime source; visual approval pending",
            source=str(SOURCES[key].relative_to(PROJECT)).replace("\\", "/"),
            destination=(
                "Approved comparison render reference; not used as a transparent layer."
                if key == "3d_comparison"
                else "Source reference for future derivative exports; preserve alpha."
            ),
            width=image.width,
            height=image.height,
            notes=f"RGBA mode: {image.mode}. Historical filename is not current user approval.",
        )


def export_composites(characters: dict[str, Image.Image]) -> None:
    for style, image in characters.items():
        save_image(
            image,
            PACKAGE / "source-layers" / f"composite-{style}-1010-transparent.png",
            category="transparent-character-composite",
            style=STYLE_META[style]["label"],
            source=STYLE_META[style]["source"],
            destination="Reusable transparent 10:10 pose master for theme artwork.",
            notes="Character body overlays candidate independent arm layers; transparent background.",
        )


def export_wallpapers(characters: dict[str, Image.Image]) -> list[tuple[Path, str]]:
    sheet_entries: list[tuple[Path, str]] = []
    for display_index, (device, (width, height)) in enumerate(IPHONE_DISPLAYS.items()):
        for style in ("2d", "3d"):
            for kind in ("lock", "home"):
                path = (
                    PACKAGE
                    / "wallpapers"
                    / "iphone"
                    / style
                    / kind
                    / f"{device}-{width}x{height}-{kind}.png"
                )
                image = make_wallpaper(
                    width,
                    height,
                    style,
                    characters[style],
                    kind,
                    1100 + display_index * 37 + (0 if style == "2d" else 11) + (0 if kind == "lock" else 5),
                )
                save_image(
                    image,
                    path,
                    category=f"iphone-{kind}-wallpaper",
                    style=STYLE_META[style]["label"],
                    source=STYLE_META[style]["source"],
                    destination=f"{device} {kind.title()} Screen wallpaper (native {width}×{height}px).",
                    notes=(
                        "Lock version keeps the upper clock/widget zone quiet."
                        if kind == "lock"
                        else "Home version is darkened for icon-label readability."
                    ),
                )
                sheet_entries.append((path, f"{style.upper()} {device} {kind}"))

            landscape_width, landscape_height = height, width
            standby_path = (
                PACKAGE
                / "wallpapers"
                / "standby"
                / style
                / f"{device}-{landscape_width}x{landscape_height}-standby.png"
            )
            standby = make_standby(
                landscape_width,
                landscape_height,
                style,
                characters[style],
                2200 + display_index * 31 + (0 if style == "2d" else 13),
            )
            save_image(
                standby,
                standby_path,
                category="standby-landscape-photo",
                style=STYLE_META[style]["label"],
                source=STYLE_META[style]["source"],
                destination=(
                    f"{device} landscape Photos/StandBy photo source "
                    f"(native {landscape_width}×{landscape_height}px)."
                ),
                notes=(
                    "Use as a Photos source or in a photo-widget provider. "
                    "iOS StandBy does not expose a generic wallpaper picker."
                ),
            )
            sheet_entries.append((standby_path, f"{style.upper()} {device} StandBy"))
    return sheet_entries


def export_watch_faces(characters: dict[str, Image.Image]) -> list[tuple[Path, str]]:
    entries: list[tuple[Path, str]] = []
    for device, (width, height) in WATCH_DISPLAYS.items():
        for style in ("2d", "3d"):
            for time_position in ("top", "bottom"):
                path = (
                    PACKAGE
                    / "watch"
                    / "photo-faces"
                    / style
                    / f"{device}-{width}x{height}-time-{time_position}.png"
                )
                image = make_watch_face(
                    width,
                    height,
                    style,
                    characters[style],
                    time_position,
                )
                save_image(
                    image,
                    path,
                    category="apple-watch-photo-face-fallback",
                    style=STYLE_META[style]["label"],
                    source=STYLE_META[style]["source"],
                    destination=(
                        f"Apple Watch Photos face source for {device}; "
                        f"choose the system time position “{time_position}”."
                    ),
                    notes="Static photo fallback only; arms do not become live clock hands.",
                )
                entries.append((path, f"{style.upper()} {device} {time_position}"))
    return entries


def export_icons() -> list[tuple[Path, str]]:
    apps = [
        ("phone", "Phone"),
        ("messages", "Messages"),
        ("mail", "Mail"),
        ("safari", "Safari"),
        ("camera", "Camera"),
        ("photos", "Photos"),
        ("music", "Music"),
        ("maps", "Maps"),
        ("calendar", "Calendar"),
        ("clock", "Clock"),
        ("notes", "Notes"),
        ("reminders", "Reminders"),
        ("settings", "Settings"),
        ("wallet", "Wallet"),
        ("weather", "Weather"),
        ("health", "Health"),
        ("files", "Files"),
        ("shortcuts", "Shortcuts"),
        ("home", "Home"),
        ("calculator", "Calculator"),
    ]
    entries: list[tuple[Path, str]] = []
    icon_index: list[dict[str, str]] = []
    for index, (slug, app) in enumerate(apps):
        path = PACKAGE / "shortcuts-icons" / "1024" / f"{slug}-1024.png"
        image = make_app_icon(slug, index)
        save_image(
            image,
            path,
            category="shortcuts-home-screen-icon",
            style="Coherent coral/lime/purple ocean-night glyph system",
            source="Original geometric icon artwork derived from the approved theme palette; no copied app artwork.",
            destination=f"Shortcuts “Add to Home Screen” custom icon for the {app} Open App shortcut.",
            notes="Square source; iOS applies the Home Screen icon mask. Do not pre-round.",
        )
        entries.append((path, app))
        icon_index.append(
            {
                "app": app,
                "icon": relative(path),
                "shortcut_action": "Open App",
                "home_screen_label": app,
            }
        )
    index_path = PACKAGE / "shortcuts-icons" / "icon-index.json"
    index_content = json.dumps(icon_index, indent=2, ensure_ascii=False) + "\n"
    if index_path.exists():
        if index_path.read_text(encoding="utf-8") != index_content:
            raise ValueError(f"Existing icon index differs: {index_path}")
    else:
        index_path.write_text(index_content, encoding="utf-8")
    return entries


def export_widgets(characters: dict[str, Image.Image]) -> list[tuple[Path, str]]:
    entries: list[tuple[Path, str]] = []
    iphone_families = {
        "small": (510, 510),
        "medium": (1092, 510),
        "large": (1092, 1146),
    }
    for style in ("2d", "3d"):
        for family, (width, height) in iphone_families.items():
            path = (
                PACKAGE
                / "widgets"
                / "iphone"
                / style
                / f"system-{family}-{width}x{height}@3x.png"
            )
            image = make_widget(width, height, style, characters[style], family)
            save_image(
                image,
                path,
                category="iphone-widget-background",
                style=STYLE_META[style]["label"],
                source=STYLE_META[style]["source"],
                destination=(
                    f"@3x image master for a {family} WidgetKit/photo-widget layout "
                    "on the 428/430-point iPhone class."
                ),
                notes="A third-party photo-widget app or a WidgetKit app is required to display this image as a widget.",
            )
            entries.append((path, f"{style.upper()} iPhone {family}"))

        lock_families = {
            "accessory-circular": (228, 228),
            "accessory-rectangular": (516, 228),
        }
        for family, (width, height) in lock_families.items():
            path = (
                PACKAGE
                / "widgets"
                / "iphone-lock-screen"
                / style
                / f"{family}-{width}x{height}@3x.png"
            )
            image = make_accessory(
                width,
                height,
                style,
                characters[style],
                "circular" if "circular" in family else "rectangular",
            )
            save_image(
                image,
                path,
                category="iphone-lock-screen-widget-art",
                style=STYLE_META[style]["label"],
                source=STYLE_META[style]["source"],
                destination=f"WidgetKit {family} artwork master for the 428/430-point iPhone class.",
                notes="Developer handoff; static PNG cannot become a native Lock Screen widget by itself.",
            )
            entries.append((path, f"{style.upper()} iPhone {family}"))

    watch_sizes = {
        "smart-stack-41mm": (330, 145),
        "smart-stack-45mm": (368, 161),
        "smart-stack-49mm": (382, 163),
        "accessory-circular-45-49mm": (100, 100),
        "accessory-rectangular-with-title-45-49mm": (357, 112),
        "accessory-rectangular-full-45-49mm": (386, 164),
    }
    for style in ("2d", "3d"):
        for family, (width, height) in watch_sizes.items():
            accessory_family = "circular" if "circular" in family else "rectangular"
            path = (
                PACKAGE
                / "widgets"
                / "watch"
                / style
                / f"{family}-{width}x{height}@2x.png"
            )
            image = make_accessory(
                width,
                height,
                style,
                characters[style],
                accessory_family,
            )
            save_image(
                image,
                path,
                category="watch-widget-complication-art",
                style=STYLE_META[style]["label"],
                source=STYLE_META[style]["source"],
                destination=f"WidgetKit/watchOS image master for {family}.",
                notes="Developer handoff; requires a signed watchOS app/widget extension.",
            )
            entries.append((path, f"{style.upper()} Watch {family}"))

    template_path = (
        PACKAGE
        / "widgets"
        / "watch"
        / "template"
        / "accessory-circular-template-100x100@2x.png"
    )
    template = make_accessory(100, 100, "2d", characters["2d"], "circular", transparent=True)
    save_image(
        template,
        template_path,
        category="watch-complication-template",
        style="Monochrome alpha template",
        source="Original five-point theme mark.",
        destination="WidgetKit accessoryCircular template image at @2x.",
        notes="Transparent PNG intended for system tinting; requires a watchOS widget extension.",
    )
    entries.append((template_path, "Watch circular template"))
    return entries


def export_audio() -> tuple[list[Path], list[tuple[Path, str]]]:
    wav_paths: list[Path] = []
    contact_entries: list[tuple[Path, str]] = []
    destinations = {
        "charge": "Shortcuts Charger → Is Connected helper shortcut.",
        "disconnect": "Shortcuts Charger → Is Disconnected helper shortcut.",
        "hour-chime": "Shortcuts Time of Day helper shortcut; create one automation per desired hour.",
        "low-battery": "Shortcuts Battery Level → Falls Below helper shortcut.",
        "sleep-focus": "Shortcuts Sleep/Focus → When Turning On helper shortcut.",
    }
    for name in destinations:
        samples = synthesize_cue(name)
        duration = samples.shape[0] / 48_000
        wav_path = PACKAGE / "sounds" / "wav" / f"{name}-48k-stereo.wav"
        write_wav(wav_path, samples)
        add_record(
            wav_path,
            category="original-theme-sound",
            style="Original non-vocal synthesized cue",
            source="Generated from additive sine/bell synthesis; no speech, voice model, sample library, or voice imitation.",
            destination=destinations[name],
            duration_seconds=duration,
            sample_rate=48_000,
            channels=2,
            codec="PCM signed 16-bit little-endian",
        )
        wav_paths.append(wav_path)
        contact_entries.append((wav_path, name))

        m4a_path = PACKAGE / "sounds" / "m4a" / f"{name}-aac-192k.m4a"
        m4a_path.parent.mkdir(parents=True, exist_ok=True)
        if not m4a_path.exists():
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-i",
                    str(wav_path),
                    "-c:a",
                    "aac",
                    "-b:a",
                    "192k",
                    "-movflags",
                    "+faststart",
                    str(m4a_path),
                ],
                check=True,
            )
        add_record(
            m4a_path,
            category="original-theme-sound",
            style="Original non-vocal synthesized cue",
            source="AAC encoding of the matching original WAV master.",
            destination=destinations[name] + " Recommended iPhone delivery format.",
            duration_seconds=duration,
            sample_rate=48_000,
            channels=2,
            codec="AAC-LC approximately 192 kb/s",
        )
    return wav_paths, contact_entries


def export_qr_codes() -> None:
    qr_dir = PACKAGE / "qr"

    payloads = {
        "verified-create-new-shortcut": "shortcuts://create-shortcut",
        "verified-run-patrick-mode": "shortcuts://run-shortcut?name=Patrick%20Mode",
        "verified-official-shortcuts-guide": "https://support.apple.com/guide/shortcuts/welcome/ios",
    }
    for name, payload in payloads.items():
        write_qr(
            payload,
            qr_dir / "payloads" / f"{name}.txt",
            qr_dir / f"{name}-900x900.png",
        )
    ndef_path = qr_dir / "NFC-NDEF-FALLBACK.txt"
    ndef_content = (
        "Recommended URL record after the local shortcut has been created:\n"
        "shortcuts://run-shortcut?name=Patrick%20Mode\n\n"
        "Important: a Shortcuts NFC personal automation identifies the scanned tag by its "
        "unique identifier and ignores the tag contents. The URL record is only a fallback "
        "for a normal background NFC read; it does not import or create the automation.\n"
    )
    if ndef_path.exists():
        if ndef_path.read_text(encoding="utf-8") != ndef_content:
            raise ValueError(f"Existing NFC fallback differs: {ndef_path}")
    else:
        ndef_path.write_text(ndef_content, encoding="utf-8")


def save_contact_sheets(
    wallpaper_entries: list[tuple[Path, str]],
    watch_entries: list[tuple[Path, str]],
    icon_entries: list[tuple[Path, str]],
    widget_entries: list[tuple[Path, str]],
    wav_paths: list[Path],
) -> None:
    sheets = [
        (
            make_contact_sheet(
                wallpaper_entries,
                columns=6,
                thumb_size=(250, 430),
                title="IPHONE LOCK · HOME · STANDBY EXPORTS",
            ),
            PACKAGE / "contact-sheets" / "wallpapers-contact-sheet.jpg",
            "Wallpaper and StandBy visual QA sheet.",
        ),
        (
            make_contact_sheet(
                watch_entries,
                columns=6,
                thumb_size=(220, 265),
                title="APPLE WATCH PHOTO-FACE FALLBACKS",
            ),
            PACKAGE / "contact-sheets" / "watch-faces-contact-sheet.jpg",
            "Apple Watch photo-face visual QA sheet.",
        ),
        (
            make_contact_sheet(
                icon_entries,
                columns=5,
                thumb_size=(230, 230),
                title="SHORTCUTS HOME-SCREEN ICON PACK",
            ),
            PACKAGE / "contact-sheets" / "shortcuts-icons-contact-sheet.jpg",
            "Shortcuts icon visual QA sheet.",
        ),
        (
            make_contact_sheet(
                widget_entries,
                columns=5,
                thumb_size=(260, 220),
                title="WIDGET · LOCK-SCREEN · COMPLICATION ART",
            ),
            PACKAGE / "contact-sheets" / "widgets-contact-sheet.jpg",
            "Widget and complication visual QA sheet.",
        ),
        (
            make_waveform_sheet(wav_paths),
            PACKAGE / "contact-sheets" / "audio-waveforms-contact-sheet.png",
            "Waveform visual QA sheet for the five original cues.",
        ),
    ]
    for image, path, destination in sheets:
        save_image(
            image,
            path,
            category="contact-sheet",
            style="Delivery QA overview",
            source="Thumbnails or decoded waveforms of generated package assets.",
            destination=destination,
            notes="Inspection aid only; use the individual full-resolution files for installation.",
        )


def write_manifests() -> None:
    assets = sorted(ASSET_RECORDS, key=lambda item: item["path"])
    manifest = {
        "schema_version": "1.0",
        "package_name": "Patrick Face Season-1 Theme Pack",
        "package_version": PACKAGE_VERSION,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "root": str(PACKAGE),
        "source_project": str(PROJECT),
        "source_policy": (
            "Character imagery uses the source layers named in each record. "
            "All art remains a candidate pending current user review; historical "
            "approved filenames do not establish approval."
        ),
        "delivery_notes": {
            "standby": "Landscape files are photo sources; StandBy has no generic wallpaper importer.",
            "watch": "Photo-face files are static fallbacks; complication PNGs require a signed WidgetKit app.",
            "shortcuts": "Personal automations are device-specific and must be created manually.",
            "nfc": "A passive NFC tag triggers software only; it cannot power LEDs or other case hardware.",
            "audio": "All sounds are original synthesis with no speech or voice imitation.",
        },
        "asset_count": len(assets),
        "assets": assets,
    }
    json_path = PACKAGE / "MANIFEST.json"
    json_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    csv_path = PACKAGE / "MANIFEST.csv"
    fieldnames = [
        "path",
        "category",
        "format",
        "width",
        "height",
        "duration_seconds",
        "sample_rate_hz",
        "channels",
        "codec",
        "bytes",
        "sha256",
        "style",
        "source",
        "intended_destination",
        "notes",
    ]
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(assets)

    summary: dict[str, int] = {}
    for asset in assets:
        summary[asset["category"]] = summary.get(asset["category"], 0) + 1
    summary_path = PACKAGE / "ASSET-SUMMARY.json"
    summary_path.write_text(
        json.dumps(
            {
                "asset_count": len(assets),
                "total_asset_bytes": sum(asset["bytes"] for asset in assets),
                "category_counts": dict(sorted(summary.items())),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="Rebuild existing output after a verified external backup.")
    args = parser.parse_args()
    ensure_sources()
    if (PACKAGE / "MANIFEST.json").exists():
        if not args.overwrite:
            parser.error("Existing media retained. Use --overwrite only when an intentional rebuild is required.")
        backup = Path.home() / ".codex" / "backups" / ("PatrickFace-theme-pack-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
        shutil.copytree(
            PACKAGE,
            backup,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
        for source in PACKAGE.rglob("*"):
            if source.is_file() and "__pycache__" not in source.parts and source.suffix != ".pyc":
                if sha256(source) != sha256(backup / source.relative_to(PACKAGE)):
                    raise RuntimeError(f"Backup verification failed: {source}")
    PACKAGE.mkdir(parents=True, exist_ok=True)
    copy_source_layers()

    body_2d = load_rgba(SOURCES["2d_body_preview"])
    hour_2d = load_rgba(SOURCES["2d_hour_arm"])
    minute_2d = load_rgba(SOURCES["2d_minute_arm"])
    body_3d = load_rgba(SOURCES["3d_body"])
    arm_3d = load_rgba(SOURCES["3d_arm"])
    characters = {
        "2d": compose_character("2d", body_2d, hour_2d, minute_2d),
        "3d": compose_character("3d", body_3d, arm_3d, ImageOps.mirror(arm_3d)),
    }
    export_composites(characters)

    wallpaper_entries = export_wallpapers(characters)
    watch_entries = export_watch_faces(characters)
    icon_entries = export_icons()
    widget_entries = export_widgets(characters)
    wav_paths, _ = export_audio()
    export_qr_codes()
    save_contact_sheets(
        wallpaper_entries,
        watch_entries,
        icon_entries,
        widget_entries,
        wav_paths,
    )
    write_manifests()

    print(f"Built {len(ASSET_RECORDS)} media assets in {PACKAGE}")
    print(f"Manifest: {PACKAGE / 'MANIFEST.json'}")


if __name__ == "__main__":
    main()
