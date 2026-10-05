"""Build Season-1 Patrick ARM layers used as analog clock hands.

These are character arms (star limbs), not geometric clock needles painted pink.
Both hour and minute arms share one transparent layout so they meet at one hub:

  - rounded tip at the top of the image
  - thicker organic root at the bottom center (the shared pivot)
  - Season-1 cel / smooth toon shading
"""

from __future__ import annotations


# Retirement guard: this runs before image libraries or filesystem setup.
# The implementation below is preserved as historical source evidence only.
# It cannot be executed or imported to recreate obsolete runtime artwork.
import argparse as _retired_argparse
import json as _retired_json

_RETIRED_MESSAGE = (
    "The historical clock-hand generator is retired. "
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
        "lifecycle": "retired-clock-hand-generator",
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


import shutil
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


PROJECT = Path(r"<PROJECT_DIR>")
PREVIEW = PROJECT / "preview" / "assets"
SOURCES = PROJECT / "sources" / "clock-hands"
REJECTED = PROJECT / "sources" / "rejected-runtime"
GENERATED = Path(r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets")
PREVIEW.mkdir(parents=True, exist_ok=True)
SOURCES.mkdir(parents=True, exist_ok=True)
REJECTED.mkdir(parents=True, exist_ok=True)

WIDTH = 420
HEIGHT = 1400
INK = (61, 31, 36, 255)
PINK = (250, 116, 109, 255)
PINK_LIGHT = (255, 148, 138, 255)
PINK_DARK = (214, 86, 82, 255)


def remove_blue_screen(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    background = Image.new("L", (width, height), 0)
    background_pixels = background.load()
    queue: deque[tuple[int, int]] = deque()

    def is_screen_blue(x: int, y: int) -> bool:
        red, green, blue, _ = pixels[x, y]
        return red < 100 and blue > 125 and blue > red * 1.7 and blue > green * 1.3

    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(height):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        if background_pixels[x, y] or not is_screen_blue(x, y):
            continue
        background_pixels[x, y] = 255
        if x:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    fringe = background.filter(ImageFilter.MaxFilter(5))
    fringe_pixels = fringe.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if background_pixels[x, y]:
                pixels[x, y] = (red, green, blue, 0)
                continue
            if fringe_pixels[x, y] and red < 120 and blue > max(red, green):
                dominance = blue - max(red, green)
                alpha = int(alpha * max(0.0, 1 - dominance / 42))
                blue = min(blue, max(red, green) + 4)
            pixels[x, y] = (red, green, blue, alpha)

    bounds = rgba.getchannel("A").getbbox()
    if not bounds:
        raise RuntimeError("blue-screen removal erased the arm")
    left, top, right, bottom = bounds
    return rgba.crop(
        (
            max(0, left - 6),
            max(0, top - 6),
            min(width, right + 6),
            min(height, bottom + 6),
        )
    )


def arm_polygon(root_w: float, tip_w: float) -> list[tuple[float, float]]:
    """Thick Season-1 star arm: rounded tip up, fleshy root on the hub."""
    cx = WIDTH / 2
    top = 70
    bottom = HEIGHT - 36
    upper = top + (bottom - top) * 0.22
    mid = top + (bottom - top) * 0.52
    lower = top + (bottom - top) * 0.82
    return [
        (cx, top),
        (cx + tip_w * 0.85, top + 55),
        (cx + tip_w * 1.15, upper),
        (cx + tip_w * 1.35, mid),
        (cx + root_w * 0.95, lower),
        (cx + root_w * 0.88, bottom - 28),
        (cx + root_w * 0.35, bottom - 6),
        (cx, bottom),
        (cx - root_w * 0.35, bottom - 6),
        (cx - root_w * 0.88, bottom - 28),
        (cx - root_w * 0.95, lower),
        (cx - tip_w * 1.35, mid),
        (cx - tip_w * 1.15, upper),
        (cx - tip_w * 0.85, top + 55),
    ]


def render_cel_arm(root_w: float, tip_w: float) -> Image.Image:
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    points = arm_polygon(root_w, tip_w)
    draw.polygon(points, fill=PINK)
    draw.line(points + [points[0]], fill=INK, width=16, joint="curve")
    # Soft cel highlight, not a center needle crease.
    highlight = [
        (WIDTH / 2 - tip_w * 0.35, 140),
        (WIDTH / 2 - tip_w * 0.45, HEIGHT * 0.4),
        (WIDTH / 2 - root_w * 0.35, HEIGHT - 160),
    ]
    draw.line(highlight, fill=(255, 170, 160, 95), width=18, joint="curve")
    # Tiny pore dots so it reads as Patrick flesh, not a painted needle.
    for y, x_off in ((220, -18), (410, 22), (640, -28), (860, 16), (1080, -12)):
        draw.ellipse(
            (WIDTH / 2 + x_off - 4, y - 4, WIDTH / 2 + x_off + 4, y + 4),
            fill=(232, 92, 88, 180),
        )
    return image.filter(ImageFilter.SMOOTH)


def render_toon_arm(root_w: float, tip_w: float) -> Image.Image:
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(mask).polygon(arm_polygon(root_w, tip_w), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    shaded = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    pixels = shaded.load()
    mask_pixels = mask.load()
    cx = WIDTH / 2
    for y in range(HEIGHT):
        for x in range(WIDTH):
            alpha = mask_pixels[x, y]
            if not alpha:
                continue
            t = (x - cx) / max(1, WIDTH * 0.28)
            tone = max(-1.0, min(1.0, -t))
            r = int(PINK[0] + tone * 16 + (1 - y / HEIGHT) * 6)
            g = int(PINK[1] + tone * 9)
            b = int(PINK[2] + tone * 7)
            if x > cx + 12:
                r = int(PINK_DARK[0] * 0.3 + r * 0.7)
                g = int(PINK_DARK[1] * 0.3 + g * 0.7)
                b = int(PINK_DARK[2] * 0.3 + b * 0.7)
            if x < cx - 14 and 120 < y < HEIGHT - 140:
                r = min(255, int(r * 0.6 + PINK_LIGHT[0] * 0.4))
                g = min(255, int(g * 0.6 + PINK_LIGHT[1] * 0.4))
                b = min(255, int(b * 0.6 + PINK_LIGHT[2] * 0.4))
            pixels[x, y] = (
                max(0, min(255, r)),
                max(0, min(255, g)),
                max(0, min(255, b)),
                alpha,
            )
    edge = mask.filter(ImageFilter.MaxFilter(9))
    rim = Image.new("L", (WIDTH, HEIGHT), 0)
    ep, mp, rp = edge.load(), mask.load(), rim.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            rp[x, y] = max(0, ep[x, y] - mp[x, y])
    contour = Image.new("RGBA", (WIDTH, HEIGHT), (72, 37, 32, 0))
    contour.putalpha(rim.filter(ImageFilter.GaussianBlur(0.9)))
    out = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    out.alpha_composite(contour)
    out.alpha_composite(shaded)
    return out


def crop_content(image: Image.Image, pad: int = 14) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if not bounds:
        raise RuntimeError("empty arm render")
    left, top, right, bottom = bounds
    return image.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(image.width, right + pad),
            min(image.height, bottom + pad),
        )
    )


def preserve(path: Path) -> None:
    if path.exists() and not (REJECTED / path.name).exists():
        shutil.copy2(path, REJECTED / path.name)


def normalize_arm_canvas(image: Image.Image) -> Image.Image:
    """Keep tip-up, root-down, and center the fleshy root on the hub column."""
    cropped = crop_content(image)
    # Ensure height is dominant so runtime length mapping stays tip-forward.
    if cropped.width > cropped.height:
        cropped = cropped.rotate(90, expand=True, resample=Image.Resampling.BICUBIC)
        cropped = crop_content(cropped)
    target = Image.new("RGBA", (max(220, cropped.width + 24), max(900, cropped.height + 24)), (0, 0, 0, 0))
    target.alpha_composite(
        cropped,
        ((target.width - cropped.width) // 2, (target.height - cropped.height) // 2),
    )
    return crop_content(target, pad=8)


AUTHENTIC = GENERATED / "patrick-season1-authentic-arm.png"
TOON_SRC = GENERATED / "patrick-season1-toon3d-arm.png"

if AUTHENTIC.exists():
    cel_base = normalize_arm_canvas(remove_blue_screen(Image.open(AUTHENTIC)))
else:
    cel_base = crop_content(render_cel_arm(168, 78))

if TOON_SRC.exists():
    toon_base = normalize_arm_canvas(remove_blue_screen(Image.open(TOON_SRC)))
else:
    toon_base = crop_content(render_toon_arm(160, 72))

# Hour arm is the same character limb, drawn shorter at runtime.
# Minute gets a slightly longer canvas so the tip reads thinner farther out.
minute_cel = cel_base.resize(
    (cel_base.width, int(cel_base.height * 1.08)),
    Image.Resampling.LANCZOS,
)
hour_cel = cel_base
minute_toon = toon_base.resize(
    (toon_base.width, int(toon_base.height * 1.08)),
    Image.Resampling.LANCZOS,
)

JOBS = {
    "season1-hour-arm.png": hour_cel,
    "season1-minute-arm.png": minute_cel,
    "season1-3d-arm.png": minute_toon,
}

for name, image in JOBS.items():
    image.save(SOURCES / name.replace(".png", "-arm-source.png"), optimize=True)
    destination = PREVIEW / name
    preserve(destination)
    image.save(destination, optimize=True)
    print(f"{name}: {image.size}, alpha={image.getchannel('A').getextrema()}")

print("character-arm clock hands ready")
