"""Build corrected Season-1 2D/3D character layers for the runtime.

The generated source renders use an edge-connected blue screen.  This script
keys that screen, corrects the overly tall generator proportions, shortens only
the two lower star points, and preserves the previous runtime files as rejected
references before replacing them.
"""

from __future__ import annotations

import shutil
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


GENERATED = Path(r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets")
PROJECT = Path(r"<PROJECT_DIR>")
PREVIEW = PROJECT / "preview" / "assets"
SOURCES = PROJECT / "sources" / "rebuilt-season1"
REJECTED = PROJECT / "sources" / "rejected-runtime"
REJECTED_RIG_SCREENSHOT = Path(
    r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets"
    r"\<USER_HOME>_.cursor_projects_<PROJECT_SLUG>_assets_<USER_HOME>_"
    r"AppData_Roaming_Cursor_User_workspaceStorage_e3578c596abe3e051a6fc784b89a5c20_"
    r"images_image-8c462809-2b24-40ae-b55d-d3aca909aae4.png"
)

PREVIEW.mkdir(parents=True, exist_ok=True)
SOURCES.mkdir(parents=True, exist_ok=True)
REJECTED.mkdir(parents=True, exist_ok=True)

if REJECTED_RIG_SCREENSHOT.exists():
    rejected_copy = REJECTED / "rejected-separate-shoulder-rig-20260924.png"
    if not rejected_copy.exists():
        shutil.copy2(REJECTED_RIG_SCREENSHOT, rejected_copy)


def remove_blue_screen(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size

    def is_screen_blue(x: int, y: int) -> bool:
        red, green, blue, _ = pixels[x, y]
        # Keep the lavender eyelids and dark-purple shorts flowers even where
        # they touch the outer silhouette.  The royal-blue screen has very
        # little red; the character purples do not.
        return (
            red < 100
            and blue > 125
            and blue > red * 1.7
            and blue > green * 1.3
        )

    # Only remove blue connected to an image edge. This preserves isolated purple
    # flower details inside the character while handling the generator's blue
    # vignette from bright center to dark corners.
    background = Image.new("L", (width, height), 0)
    background_pixels = background.load()
    queue: deque[tuple[int, int]] = deque()

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

    alpha = rgba.getchannel("A")
    bounds = alpha.getbbox()
    if not bounds:
        raise RuntimeError("Blue-screen removal erased the complete image")

    left, top, right, bottom = bounds
    padding = 5
    return rgba.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(width, right + padding),
            min(height, bottom + padding),
        )
    )


def correct_body_proportions(image: Image.Image) -> Image.Image:
    """Restore the shorter, broader early silhouette without filtering the art."""
    split = round(image.height * 0.86)
    upper = image.crop((0, 0, image.width, split))
    lower = image.crop((0, split, image.width, image.height))
    lower = lower.resize(
        (image.width, max(1, round(lower.height * 0.58))),
        Image.Resampling.LANCZOS,
    )

    joined = Image.new(
        "RGBA",
        (image.width, upper.height + lower.height),
        (0, 0, 0, 0),
    )
    joined.alpha_composite(upper, (0, 0))
    joined.alpha_composite(lower, (0, upper.height))
    return joined.resize(
        (round(joined.width * 1.12), round(joined.height * 0.94)),
        Image.Resampling.LANCZOS,
    )


JOBS = {
    "patrick-season1-authentic-armless-v2.png": (
        "season1-body-normal.png",
        True,
    ),
    "patrick-season1-authentic-arm.png": (
        "season1-hour-arm.png",
        False,
    ),
    "patrick-season1-toon3d-armless-v4.png": (
        "season1-3d-body.png",
        True,
    ),
    "patrick-season1-toon3d-arm.png": (
        "season1-3d-arm.png",
        False,
    ),
}

for source_name, (output_name, is_body) in JOBS.items():
    source = GENERATED / source_name
    if not source.exists():
        raise FileNotFoundError(source)

    shutil.copy2(source, SOURCES / source_name)
    destination = PREVIEW / output_name
    backup = REJECTED / output_name
    if destination.exists() and not backup.exists():
        shutil.copy2(destination, backup)
    if not is_body:
        front_layer_backup = REJECTED / f"pre-root-feather-{output_name}"
        if destination.exists() and not front_layer_backup.exists():
            shutil.copy2(destination, front_layer_backup)

    processed = remove_blue_screen(Image.open(source))
    if is_body:
        processed = correct_body_proportions(processed)
    processed.save(destination, optimize=True)
    print(
        f"{output_name}: {processed.width}x{processed.height}, "
        f"alpha={processed.getchannel('A').getextrema()}"
    )

# The same clean 2D arm art is used at two lengths by the real clock-hand rig.
minute_arm = PREVIEW / "season1-minute-arm.png"
if minute_arm.exists() and not (REJECTED / minute_arm.name).exists():
    shutil.copy2(minute_arm, REJECTED / minute_arm.name)
shutil.copy2(PREVIEW / "season1-hour-arm.png", minute_arm)
