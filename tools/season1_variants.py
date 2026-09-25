"""Build historically plausible finish variants from one fixed Season-1 drawing."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter


ROOT = Path(r"<PROJECT_DIR>")
SOURCE = ROOT / "comparison" / "assets" / "style-01-1999-cel.png"
OUT = ROOT / "comparison-season1" / "assets"
OUT.mkdir(parents=True, exist_ok=True)

RNG = np.random.default_rng(1999)


def character_mask(image: Image.Image) -> Image.Image:
    """Close internal black details so treatments cover the whole silhouette."""
    array = np.asarray(image.convert("RGB"))
    visible = (array.max(axis=2) > 18).astype(np.uint8) * 255
    mask = Image.fromarray(visible, "L")
    mask = mask.filter(ImageFilter.MaxFilter(15))
    mask = mask.filter(ImageFilter.MinFilter(15))
    return mask.filter(ImageFilter.GaussianBlur(0.55))


def composite_black(processed: Image.Image, mask: Image.Image) -> Image.Image:
    black = Image.new("RGB", processed.size, (0, 0, 0))
    return Image.composite(processed.convert("RGB"), black, mask)


def shifted(channel: Image.Image, dx: int, dy: int = 0) -> Image.Image:
    result = Image.new("L", channel.size, 0)
    result.paste(channel, (dx, dy))
    return result


def clean_master(base: Image.Image, mask: Image.Image) -> Image.Image:
    # Broadcast cel masters retain a trace of optical softness without looking aged.
    soft = base.filter(ImageFilter.GaussianBlur(0.28))
    soft = ImageEnhance.Color(soft).enhance(0.98)
    soft = ImageEnhance.Contrast(soft).enhance(0.99)
    return composite_black(soft, mask)


def physical_acetate(base: Image.Image, mask: Image.Image) -> Image.Image:
    array = np.asarray(base).astype(np.float32)
    h, w, _ = array.shape
    low = RNG.normal(0, 1, (max(2, h // 28), max(2, w // 28)))
    low = Image.fromarray(np.uint8(np.clip((low + 3) * 40, 0, 255)), "L")
    low = low.resize((w, h), Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(7))
    variation = (np.asarray(low).astype(np.float32) - 120) / 120
    array *= (1 + variation[..., None] * 0.025)
    result = Image.fromarray(np.uint8(np.clip(array, 0, 255)), "RGB")

    # Sparse dust and tiny paint pinholes, confined to the character silhouette.
    dust = Image.new("L", base.size, 0)
    dust_array = np.zeros((h, w), np.uint8)
    coords = RNG.integers([0, 0], [h, w], size=(170, 2))
    for y, x in coords:
        dust_array[y, x] = RNG.integers(45, 120)
    dust = Image.fromarray(dust_array, "L").filter(ImageFilter.MaxFilter(3))
    dust = Image.composite(dust, Image.new("L", base.size, 0), mask)
    pale = Image.new("RGB", base.size, (235, 220, 205))
    result = Image.composite(pale, result, dust)
    return composite_black(result, mask)


def film_transfer(base: Image.Image, mask: Image.Image) -> Image.Image:
    # One-pixel gate weave plus restrained warm stock and luminance grain.
    woven = Image.new("RGB", base.size, (0, 0, 0))
    woven.paste(base, (1, -1))
    array = np.asarray(woven).astype(np.float32)
    array[..., 0] *= 1.025
    array[..., 1] *= 1.002
    array[..., 2] *= 0.955
    grain = RNG.normal(0, 2.6, array.shape[:2])
    array += grain[..., None]
    result = Image.fromarray(np.uint8(np.clip(array, 0, 255)), "RGB")
    result = ImageEnhance.Contrast(result).enhance(0.96)
    return composite_black(result, mask)


def vhs_broadcast(base: Image.Image, mask: Image.Image) -> Image.Image:
    softened = base.filter(ImageFilter.GaussianBlur(0.65))
    r, g, b = softened.split()
    # Mild analog chroma delay rather than a destructive glitch.
    r = shifted(r, 1)
    b = shifted(b, -2)
    result = Image.merge("RGB", (r, g, b))
    array = np.asarray(result).astype(np.float32)
    rows = np.arange(array.shape[0])
    scan = 1 - ((rows % 3) == 2).astype(np.float32) * 0.035
    array *= scan[:, None, None]
    result = Image.fromarray(np.uint8(np.clip(array, 0, 255)), "RGB")
    return composite_black(result, mask)


def gouache_archive(base: Image.Image, mask: Image.Image) -> Image.Image:
    array = np.asarray(base).astype(np.float32)
    h, w, _ = array.shape
    tooth = RNG.normal(0, 1, (h, w))
    tooth_img = Image.fromarray(np.uint8(np.clip((tooth + 3) * 40, 0, 255)), "L")
    tooth_img = tooth_img.filter(ImageFilter.GaussianBlur(0.45))
    tooth = (np.asarray(tooth_img).astype(np.float32) - 120) / 120
    array *= 1 + tooth[..., None] * 0.055
    # Slightly opaque, matte hand-painted palette.
    array = np.round(array / 5) * 5
    result = Image.fromarray(np.uint8(np.clip(array, 0, 255)), "RGB")
    result = ImageEnhance.Color(result).enhance(0.93)
    result = ImageEnhance.Contrast(result).enhance(0.96)
    return composite_black(result, mask)


def merch_print(base: Image.Image, mask: Image.Image) -> Image.Image:
    # Coarse but period-plausible separation with small ink-trap offsets.
    quantized = base.quantize(colors=20, method=Image.Quantize.MEDIANCUT).convert("RGB")
    r, g, b = quantized.split()
    r = shifted(r, 1, 0)
    g = shifted(g, 0, 1)
    b = shifted(b, -1, 0)
    result = Image.merge("RGB", (r, g, b)).filter(ImageFilter.GaussianBlur(0.22))

    array = np.asarray(result).astype(np.float32)
    yy, xx = np.indices(array.shape[:2])
    cell = 7
    distance = np.sqrt(((xx % cell) - cell / 2) ** 2 + ((yy % cell) - cell / 2) ** 2)
    clustered_dots = np.where(distance < 1.55, 0.88, 1.0)
    array *= clustered_dots[..., None]
    result = Image.fromarray(np.uint8(np.clip(array, 0, 255)), "RGB")
    return composite_black(result, mask)


base = Image.open(SOURCE).convert("RGB")
mask = character_mask(base)

variants = {
    "season1-01-clean.png": clean_master(base, mask),
    "season1-02-acetate.png": physical_acetate(base, mask),
    "season1-03-film.png": film_transfer(base, mask),
    "season1-04-vhs.png": vhs_broadcast(base, mask),
    "season1-05-gouache.png": gouache_archive(base, mask),
    "season1-06-print.png": merch_print(base, mask),
}

for filename, image in variants.items():
    image.save(OUT / filename, optimize=True)
    print(filename, image.size)
