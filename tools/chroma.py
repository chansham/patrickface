"""把洋紅色背景扣成透明，錶盤外圈的白底也去掉。"""
import math
import shutil
from pathlib import Path

from PIL import Image

SRC = Path(r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets")
OUT = Path(r"<PROJECT_DIR>\preview\assets")
OUT.mkdir(parents=True, exist_ok=True)


def chroma_magenta(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    pix = im.load()
    w, h = im.size
    bg = pix[2, 2][:3]
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            dist = math.dist((r, g, b), bg)
            if dist < 48:
                pix[x, y] = (r, g, b, 0)
            elif dist < 96:
                fade = (dist - 48) / 48
                pix[x, y] = (r, g, b, int(a * fade))
    return im


def crop_visible(im: Image.Image, pad: int = 4) -> Image.Image:
    alpha = im.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad)
    y1 = min(im.height, y1 + pad)
    return im.crop((x0, y0, x1, y1))


def mask_circle(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    pix = im.load()
    w, h = im.size
    cx, cy = w / 2, h / 2
    radius = min(w, h) * 0.492
    for y in range(h):
        for x in range(w):
            dist = math.hypot(x - cx, y - cy)
            r, g, b, a = pix[x, y]
            if dist > radius:
                pix[x, y] = (r, g, b, 0)
            elif dist > radius - 3:
                fade = (radius - dist) / 3
                pix[x, y] = (r, g, b, int(a * fade))
    return im


jobs = {
    "body.png": ("patrick-premium-body.png", True),
    "body-night.png": ("patrick-premium-sleep.png", True),
    "arm.png": ("patrick-premium-arm.png", True),
}
for dest, (src, keyed) in jobs.items():
    im = Image.open(SRC / src)
    if keyed:
        im = crop_visible(chroma_magenta(im))
    im.save(OUT / dest)
    print(dest, im.size)

dial = mask_circle(Image.open(SRC / "dial.png"))
dial.save(OUT / "dial.png")
print("dial", dial.size)

shutil.copyfile(SRC / "wallpaper-phone.png", OUT / "wallpaper.png")
shutil.copyfile(SRC / "icon-face.png", OUT / "icon.png")
print("copied wallpaper and icon")
