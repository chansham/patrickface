"""Historical premium-art chroma export; never restore retired runtime copies."""
import argparse
import math
from pathlib import Path

from PIL import Image

SRC = Path(r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets")
ROOT = Path(__file__).resolve().parents[1]


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="A new archive/review folder; runtime destinations are forbidden.")
    args = parser.parse_args()
    output = args.output.resolve()
    runtime_roots = [ROOT / "preview", ROOT / "PatrickFace", ROOT / "iOSCompanion"]
    if any(output == path or path in output.parents for path in runtime_roots):
        parser.error("Legacy art cannot be exported into preview or application runtime folders.")
    if output.exists():
        parser.error("Choose a new output directory to preserve existing artwork.")
    sources = {
        "body.png": "patrick-premium-body.png",
        "body-night.png": "patrick-premium-sleep.png",
        "arm.png": "patrick-premium-arm.png",
    }
    required = list(sources.values()) + ["dial.png", "wallpaper-phone.png", "icon-face.png"]
    if any(not (SRC / name).is_file() for name in required):
        parser.error("Historical input assets are missing; no outputs were created.")
    output.mkdir(parents=True)
    for name, source in sources.items():
        with Image.open(SRC / source) as im:
            crop_visible(chroma_magenta(im)).save(output / name)
    with Image.open(SRC / "dial.png") as im:
        mask_circle(im).save(output / "dial.png")
    for source, name in [("wallpaper-phone.png", "wallpaper.png"), ("icon-face.png", "icon.png")]:
        with Image.open(SRC / source) as im:
            im.convert("RGB").save(output / name, format="PNG")
    print(f"Historical candidates exported to {output}; runtime unchanged.")


if __name__ == "__main__":
    main()
