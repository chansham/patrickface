from pathlib import Path
import math
import shutil

from PIL import Image, ImageDraw


SOURCE = Path(
    r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets"
)
OUTPUT = Path(r"<PROJECT_DIR>\comparison")
ASSETS = OUTPUT / "assets"
ASSETS.mkdir(parents=True, exist_ok=True)


def key_background(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    background = pixels[2, 2][:3]
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            distance = math.dist((r, g, b), background)
            if distance < 48:
                pixels[x, y] = (r, g, b, 0)
            elif distance < 96:
                pixels[x, y] = (r, g, b, int(a * (distance - 48) / 48))
    bounds = image.getchannel("A").getbbox()
    return image.crop(bounds) if bounds else image


def place_rotated(
    canvas: Image.Image,
    image: Image.Image,
    center: tuple[int, int],
    length: int,
    angle_degrees: float,
) -> None:
    width = round(length * image.width / image.height * 0.82)
    resized = image.resize((width, length), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", (length * 2, length * 2), (0, 0, 0, 0))
    layer.alpha_composite(
        resized,
        (layer.width // 2 - resized.width // 2, layer.height // 2 - resized.height),
    )
    rotated = layer.rotate(-angle_degrees, resample=Image.Resampling.BICUBIC)
    canvas.alpha_composite(
        rotated,
        (center[0] - rotated.width // 2, center[1] - rotated.height // 2),
    )


canvas = Image.new("RGBA", (768, 1024), (0, 0, 0, 255))
body = key_background(SOURCE / "body-armless.png")
arm = key_background(SOURCE / "arm-straight.png")

body_height = 580
body_width = round(body_height * body.width / body.height)
body = body.resize((body_width, body_height), Image.Resampling.LANCZOS)
body_left = (canvas.width - body.width) // 2
body_top = 340
pivot = (canvas.width // 2, body_top + round(body_height * 0.52))

# Fixed 10:10 presentation pose. The same guide is used for all six style generations.
place_rotated(canvas, arm, pivot, 330, -50)
place_rotated(canvas, arm, pivot, 330, 50)
canvas.alpha_composite(body, (body_left, body_top))

draw = ImageDraw.Draw(canvas)
draw.rounded_rectangle(
    (22, 22, canvas.width - 22, canvas.height - 22),
    radius=118,
    outline=(54, 54, 58, 255),
    width=4,
)

path = ASSETS / "pose-guide.png"
canvas.convert("RGB").save(path, quality=96)
print(path)

style_sources = {
    "style-01-cel.png": "style-01-cel-v2.png",
    "style-02-line.png": "style-02-line.png",
    "style-03-painted.png": "style-03-painted.png",
    "style-04-halftone.png": "style-04-halftone.png",
    "style-05-clay.png": "style-05-clay.png",
    "style-06-designer-toy.png": "style-06-designer-toy-v2.png",
}
for destination, source in style_sources.items():
    shutil.copyfile(SOURCE / source, ASSETS / destination)
    print(ASSETS / destination)
