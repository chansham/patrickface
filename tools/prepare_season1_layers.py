"""Prepare newly generated Season-1 body and arm layers for animation."""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(r"<PROJECT_DIR>")
GENERATED = Path(r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets")
TARGET = ROOT / "comparison-season1-3d"
SOURCES = TARGET / "sources"
ASSETS = TARGET / "assets"
SOURCES.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)

FILES = {
    "season1-body-source.png": "season1-clean-body-source.png",
    "season1-hour-arm-source.png": "season1-clean-hour-arm-source-v2.png",
    "season1-minute-arm-source.png": "season1-clean-minute-arm-source-v2.png",
}


def key_magenta(image: Image.Image, pad: int = 5) -> Image.Image:
    rgb = np.asarray(image.convert("RGB")).astype(np.float32)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]

    # Generated backgrounds are saturated magenta; Season-1 skin has much more
    # green, so this cleanly separates cel art without altering ink or palette.
    core_bg = (
        (red > 178)
        & (blue > 82)
        & (green < 72)
        & ((red - green) > 105)
        & ((blue - green) > 52)
    )
    alpha = np.full(red.shape, 255.0, dtype=np.float32)
    alpha[core_bg] = 0

    fringe = (
        (~core_bg)
        & (red > 175)
        & (blue > 78)
        & (green >= 72)
        & (green < 110)
        & ((red - green) > 78)
    )
    alpha[fringe] = np.clip((green[fringe] - 72) / 38 * 255, 0, 255)

    rgba = np.dstack([rgb, alpha]).astype(np.uint8)
    result = Image.fromarray(rgba, "RGBA")
    bbox = Image.fromarray(np.uint8(alpha > 8) * 255, "L").getbbox()
    if bbox:
        x0, y0, x1, y1 = bbox
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(result.width, x1 + pad), min(result.height, y1 + pad)
        result = result.crop((x0, y0, x1, y1))
    return result


for destination, source in FILES.items():
    raw = GENERATED / source
    shutil.copyfile(raw, SOURCES / destination)
    keyed_name = destination.replace("-source", "")
    keyed = key_magenta(Image.open(raw))
    keyed.save(ASSETS / keyed_name, optimize=True)
    print(keyed_name, keyed.size)
