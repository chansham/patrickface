"""Replace toe-like 3D feet with faithful flat Season-1 lower wedges."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(r"<PROJECT_DIR>")
SOURCE = Path(
    r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets"
    r"\patrick-season1-faithful-3d-feet-final.png"
)
OUT_DIR = ROOT / "comparison-season1-3d" / "assets"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT = OUT_DIR / "season1-faithful-3d.png"

SCALE = 4
RNG = np.random.default_rng(2000)


def render_matte_wedge(size: tuple[int, int], points: list[tuple[int, int]], light_bias: float) -> Image.Image:
    w, h = size
    high = [(x * SCALE, y * SCALE) for x, y in points]
    high_mask = Image.new("L", (w * SCALE, h * SCALE), 0)
    ImageDraw.Draw(high_mask).polygon(high, fill=255)
    mask = high_mask.resize((w, h), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(0.35))

    yy, xx = np.indices((h, w))
    x_light = (1 - xx / w) * 27 + light_bias
    bottom_shade = np.clip((yy - 878) / 48, 0, 1) * -25
    contact_shadow = -18 * np.exp(-((yy - 853) / 13) ** 2)
    low_noise = RNG.normal(0, 1, (max(2, h // 18), max(2, w // 18)))
    low_noise = Image.fromarray(np.uint8(np.clip((low_noise + 3) * 40, 0, 255)), "L")
    low_noise = low_noise.resize((w, h), Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(5))
    texture = (np.asarray(low_noise).astype(np.float32) - 120) / 120 * 3.4

    color = np.empty((h, w, 3), np.float32)
    color[:] = (211, 113, 96)
    color[..., 0] += x_light + bottom_shade + contact_shadow + texture
    color[..., 1] += x_light * 0.48 + bottom_shade * 0.58 + contact_shadow * 0.65 + texture
    color[..., 2] += x_light * 0.36 + bottom_shade * 0.48 + contact_shadow * 0.58 + texture

    # Soft sculpted bevel: darken the outer shell while leaving the center matte.
    eroded = mask.filter(ImageFilter.MinFilter(11))
    edge = (np.asarray(mask).astype(np.float32) - np.asarray(eroded).astype(np.float32)) / 255
    color -= edge[..., None] * np.array([19, 12, 10], dtype=np.float32)
    rgb = Image.fromarray(np.uint8(np.clip(color, 0, 255)), "RGB")

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(rgb, (0, 0), mask)
    return layer


base = Image.open(SOURCE).convert("RGBA")
w, h = base.size

left = [
    (275, 848), (391, 853), (388, 872), (374, 891), (350, 906),
    (315, 913), (277, 910), (248, 900), (236, 887), (243, 873), (258, 859),
]
right = [
    (432, 854), (552, 848), (575, 858), (598, 875), (612, 889),
    (607, 903), (580, 915), (545, 920), (506, 914), (476, 902), (451, 884),
]

canvas = Image.new("RGBA", base.size, (0, 0, 0, 255))
canvas = Image.alpha_composite(canvas, render_matte_wedge(base.size, left, 2.0))
canvas = Image.alpha_composite(canvas, render_matte_wedge(base.size, right, -3.0))

# Preserve all original art above the leg roots, plus green/purple shorts below
# that line. Original pink toe geometry is deliberately excluded.
array = np.asarray(base.convert("RGB"))
red = array[..., 0].astype(np.float32)
green = array[..., 1].astype(np.float32)
blue = array[..., 2].astype(np.float32)
visible = array.max(axis=2) > 12
rows = np.indices((h, w))[0]
upper_character = visible & (rows < 852)
shorts_color = (
    ((green > red * 0.78) & (green > blue * 1.10) & (green > 55))
    | ((blue > 70) & (blue > green * 1.08) & (blue > red * 0.74) & (rows > 620))
)
shorts_mask = Image.fromarray(np.uint8(shorts_color) * 255, "L").filter(ImageFilter.MaxFilter(9))
keep = np.maximum(np.uint8(upper_character) * 255, np.asarray(shorts_mask))
keep_alpha = Image.fromarray(keep, "L").filter(ImageFilter.GaussianBlur(0.45))
original_without_feet = base.copy()
original_without_feet.putalpha(keep_alpha)
canvas = Image.alpha_composite(canvas, original_without_feet)

canvas.convert("RGB").save(OUT, optimize=True)
print(OUT, canvas.size)
