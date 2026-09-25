"""Replace shoe-like Season-1 feet with short asymmetric starfish stubs."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(r"<PROJECT_DIR>")
SOURCE = ROOT / "comparison" / "assets" / "style-01-1999-cel.png"
OUT_DIR = ROOT / "comparison-season1-3d" / "assets"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT = OUT_DIR / "season1-2d-revised.png"

SCALE = 4
RNG = np.random.default_rng(1999)


def catmull_rom(points: list[tuple[float, float]], samples: int = 12) -> list[tuple[float, float]]:
    """Closed Catmull-Rom spline through control points."""
    result: list[tuple[float, float]] = []
    count = len(points)
    for i in range(count):
        p0 = np.array(points[(i - 1) % count], dtype=float)
        p1 = np.array(points[i], dtype=float)
        p2 = np.array(points[(i + 1) % count], dtype=float)
        p3 = np.array(points[(i + 2) % count], dtype=float)
        for step in range(samples):
            t = step / samples
            t2, t3 = t * t, t * t * t
            point = 0.5 * (
                2 * p1
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
            )
            result.append((float(point[0]), float(point[1])))
    return result


def render_foot(size: tuple[int, int], points: list[tuple[float, float]]) -> Image.Image:
    w, h = size
    # The direct high-resolution contour is intentionally a little angular and
    # asymmetric, matching early hand-inked television cels without spline
    # overshoot that can make the tiny feet look shoe-like.
    hi_points = [(round(x * SCALE), round(y * SCALE)) for x, y in points]

    hi_mask = Image.new("L", (w * SCALE, h * SCALE), 0)
    ImageDraw.Draw(hi_mask).polygon(hi_points, fill=255)
    mask = hi_mask.resize((w, h), Image.Resampling.LANCZOS)

    noise = RNG.normal(0, 2.1, (h, w, 1))
    base = np.empty((h, w, 3), dtype=np.float32)
    base[:] = (231, 132, 132)
    # A small vertical cel-paint variation, not glossy shading.
    yy = np.linspace(-1, 1, h, dtype=np.float32)[:, None, None]
    base += noise + yy * np.array([1.8, 0.8, 0.8], dtype=np.float32)
    texture = Image.fromarray(np.uint8(np.clip(base, 0, 255)), "RGB")

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(texture, (0, 0), mask)

    hi_outline = Image.new("RGBA", (w * SCALE, h * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(hi_outline)
    draw.line(hi_points + [hi_points[0]], fill=(74, 27, 34, 255), width=3 * SCALE, joint="curve")
    outline = hi_outline.resize(size, Image.Resampling.LANCZOS)
    return Image.alpha_composite(layer, outline)


base = Image.open(SOURCE).convert("RGBA")
w, h = base.size

# The roots sit under the shorts, while the lower silhouette is wider than tall,
# slightly outward-splayed, and intentionally not mirror-symmetric.
left = [
    (302, 826),
    (384, 830),
    (380, 850),
    (371, 869),
    (358, 883),
    (336, 891),
    (309, 890),
    (288, 883),
    (278, 873),
    (282, 860),
    (294, 844),
]
right = [
    (478, 830),
    (555, 825),
    (560, 844),
    (571, 860),
    (584, 873),
    (581, 885),
    (562, 895),
    (536, 897),
    (511, 890),
    (496, 878),
    (488, 856),
]

canvas = Image.new("RGBA", base.size, (0, 0, 0, 255))
canvas = Image.alpha_composite(canvas, render_foot(base.size, left))
canvas = Image.alpha_composite(canvas, render_foot(base.size, right))

# Keep the whole original character above the leg opening. Below that line,
# retain only shorts colors (plus their nearby ink contour), removing every
# pixel belonging to the old shoe-shaped legs.
array = np.asarray(base.convert("RGB"))
red = array[..., 0].astype(np.float32)
green = array[..., 1].astype(np.float32)
blue = array[..., 2].astype(np.float32)
visible = array.max(axis=2) > 18
rows = np.indices((h, w))[0]
upper_character = visible & (rows < 835)
shorts_color = (
    ((green > red * 0.82) & (green > blue * 1.18) & (green > 65))
    | ((blue > 95) & (blue > green * 1.16) & (blue > red * 0.90) & (red < 175) & (rows > 690))
)
shorts_mask = Image.fromarray(np.uint8(shorts_color) * 255, "L").filter(ImageFilter.MaxFilter(7))
keep = np.maximum(np.uint8(upper_character) * 255, np.asarray(shorts_mask))
keep_alpha = Image.fromarray(keep, "L").filter(ImageFilter.GaussianBlur(0.35))
original_without_feet = base.copy()
original_without_feet.putalpha(keep_alpha)
canvas = Image.alpha_composite(canvas, original_without_feet)

canvas.convert("RGB").save(OUT, optimize=True)
print(OUT, canvas.size)
