"""Create the focused Season-1 foot/scale decision board.

The clean Season-1 body, face, palette and arm layers stay fixed.  Only the
feet are redrawn.  Three cel-foot constructions and one matching matte 3D
normal-foot translation are exported as real source assets.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(r"<PROJECT_DIR>")
OLD = ROOT / "comparison-season1-3d"
OUT = ROOT / "comparison-season1-feet"
ASSETS = OUT / "assets"
SOURCES = OUT / "sources"
ASSETS.mkdir(parents=True, exist_ok=True)
SOURCES.mkdir(parents=True, exist_ok=True)

BODY = Image.open(OLD / "assets" / "season1-body.png").convert("RGBA")
HOUR_ARM = Image.open(OLD / "assets" / "season1-hour-arm.png").convert("RGBA")
MINUTE_ARM = Image.open(OLD / "assets" / "season1-minute-arm.png").convert("RGBA")
THREE_D = Image.open(OLD / "assets" / "season1-faithful-3d.png").convert("RGB")

INK = (61, 31, 36, 255)
PINK = (216, 112, 113, 255)
PINK_LIGHT = (222, 122, 120, 255)
SCALE = 4


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msjhbd.ttc" if bold else r"C:\Windows\Fonts\msjh.ttc"),
        Path(r"C:\Windows\Fonts\seguisb.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def scaled(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    return [(x * SCALE, y * SCALE) for x, y in points]


FOOT_SHAPES: dict[str, tuple[list[tuple[int, int]], list[tuple[int, int]]]] = {
    # Short, compact, unmistakably feet rather than toy nubs.
    "a-compact": (
        [(91, 788), (172, 790), (177, 808), (190, 829), (185, 847),
         (164, 862), (131, 869), (92, 867), (62, 857), (54, 844),
         (62, 829), (78, 812)],
        [(267, 790), (351, 788), (368, 809), (389, 828), (395, 843),
         (384, 856), (354, 865), (315, 868), (283, 861), (259, 847),
         (254, 830), (265, 810)],
    ),
    # Neutral candidate: medium visual weight, slight turn, no long flipper toe.
    "b-normal": (
        [(88, 786), (174, 790), (180, 808), (196, 829), (197, 846),
         (184, 862), (159, 874), (124, 880), (84, 878), (49, 868),
         (28, 854), (29, 839), (44, 823), (68, 807)],
        [(268, 790), (354, 786), (377, 804), (401, 819), (417, 835),
         (420, 850), (405, 864), (377, 875), (342, 880), (301, 877),
         (270, 867), (250, 851), (248, 834), (259, 810)],
    ),
    # Deliberately graphic and wide; retained as the most outward-splayed option.
    "c-wide": (
        [(86, 786), (176, 790), (183, 808), (203, 829), (205, 844),
         (194, 857), (166, 867), (125, 872), (75, 870), (34, 861),
         (8, 848), (7, 835), (25, 820), (59, 802)],
        [(268, 790), (357, 786), (387, 800), (420, 816), (440, 832),
         (439, 846), (418, 859), (381, 868), (334, 873), (291, 870),
         (260, 862), (239, 848), (239, 832), (252, 807)],
    ),
}


def draw_cel_feet(shapes: tuple[list[tuple[int, int]], list[tuple[int, int]]]) -> tuple[Image.Image, Image.Image]:
    """Render a clean high-resolution foot source and its production-size layer."""
    high = Image.new("RGBA", (BODY.width * SCALE, BODY.height * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(high)
    for index, shape in enumerate(shapes):
        pts = scaled(shape)
        draw.polygon(pts, fill=PINK)
        draw.line(pts + [pts[0]], fill=INK, width=2 * SCALE, joint="curve")

        # One restrained cel-paint accent.  It follows the shape and is not a
        # material/filter treatment.
        if index == 0:
            accent = [(77, 813), (65, 827), (61, 842), (69, 850)]
        else:
            accent = [(374, 811), (393, 826), (401, 841), (395, 850)]
        draw.line(scaled(accent), fill=(228, 128, 124, 120), width=SCALE, joint="curve")

    production = high.resize(BODY.size, Image.Resampling.LANCZOS)
    return high, production


def assemble_body(feet: Image.Image) -> Image.Image:
    """Put newly drawn feet behind the fixed body and shorts."""
    result = feet.copy()
    # Keep all fixed body art through the shorts/leg root, but discard the old
    # long flipper silhouettes below it.
    upper = BODY.crop((0, 0, BODY.width, 812))
    result.alpha_composite(upper, (0, 0))
    return result


BODY_VARIANTS: dict[str, Image.Image] = {}
for key, shapes in FOOT_SHAPES.items():
    high_source, foot_layer = draw_cel_feet(shapes)
    high_source.save(SOURCES / f"season1-feet-{key}-source-4x.png", optimize=True)
    foot_layer.save(ASSETS / f"season1-feet-{key}-layer.png", optimize=True)
    assembled = assemble_body(foot_layer)
    assembled.save(ASSETS / f"season1-body-{key}.png", optimize=True)
    BODY_VARIANTS[key] = assembled


def old_3d_foot_mask(image: Image.Image) -> Image.Image:
    """Select the old small pink 3D feet, including their antialiased edge."""
    regions = Image.new("L", image.size, 0)
    region_draw = ImageDraw.Draw(regions)
    region_draw.polygon(
        [(205, 748), (349, 753), (379, 790), (371, 833), (187, 839), (184, 785)],
        fill=255,
    )
    region_draw.polygon(
        [(425, 752), (555, 758), (585, 794), (575, 838), (402, 840), (401, 790)],
        fill=255,
    )
    mask = Image.new("L", image.size, 0)
    src = image.load()
    dst = mask.load()
    region_pixels = regions.load()
    for y in range(740, 850):
        for x in range(image.width):
            if not region_pixels[x, y]:
                continue
            r, g, b = src[x, y]
            if r > 145 and 45 < g < 160 and 35 < b < 150 and r > g * 1.28:
                dst[x, y] = 255
    expanded = mask.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(1.0))
    # Never let dilation escape the two old-foot regions.
    return Image.composite(expanded, Image.new("L", image.size, 0), regions)


def matte_3d_foot_layer() -> Image.Image:
    """Paint the NORMAL foot construction as restrained matte sculpture."""
    layer = Image.new("RGBA", THREE_D.size, (0, 0, 0, 0))
    shapes = [
        [(239, 765), (346, 767), (363, 787), (374, 808), (367, 827),
         (345, 841), (310, 848), (269, 845), (229, 835), (207, 821),
         (208, 805), (221, 787)],
        [(438, 767), (544, 764), (569, 781), (598, 799), (617, 815),
         (615, 830), (594, 841), (560, 848), (518, 847), (479, 839),
         (451, 826), (432, 809), (429, 790)],
    ]
    for index, shape in enumerate(shapes):
        mask = Image.new("L", THREE_D.size, 0)
        ImageDraw.Draw(mask).polygon(shape, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.1))

        colored = Image.new("RGBA", THREE_D.size, (0, 0, 0, 0))
        pixels = colored.load()
        for y in range(750, 860):
            for x in range(180, 640):
                if mask.getpixel((x, y)):
                    side_light = max(-14, min(18, (430 - x) // 13))
                    bottom = max(-24, -(y - 792) // 2)
                    pixels[x, y] = (
                        max(0, min(255, 218 + side_light + bottom)),
                        max(0, min(255, 108 + side_light // 2 + bottom // 2)),
                        max(0, min(255, 94 + side_light // 3 + bottom // 2)),
                        mask.getpixel((x, y)),
                    )
        edge = mask.filter(ImageFilter.MaxFilter(9))
        ring = Image.new("L", THREE_D.size, 0)
        ep, mp, rp = edge.load(), mask.load(), ring.load()
        for y in range(748, 860):
            for x in range(175, 645):
                rp[x, y] = max(0, ep[x, y] - mp[x, y])
        contour = Image.new("RGBA", THREE_D.size, (72, 37, 32, 0))
        contour.putalpha(ring)
        layer.alpha_composite(contour)
        layer.alpha_composite(colored)

        # Soft top highlight models shallow volume without gloss.
        highlight = Image.new("RGBA", THREE_D.size, (255, 174, 151, 0))
        hmask = Image.new("L", THREE_D.size, 0)
        hd = ImageDraw.Draw(hmask)
        x0 = 235 if index == 0 else 465
        hd.ellipse((x0, 775, x0 + 95, 817), fill=42)
        hmask = hmask.filter(ImageFilter.GaussianBlur(13))
        highlight.putalpha(hmask)
        layer.alpha_composite(highlight)
    return layer


THREE_D_FEET = matte_3d_foot_layer()
THREE_D_FEET.save(ASSETS / "season1-3d-normal-feet-layer.png", optimize=True)

old_mask = old_3d_foot_mask(THREE_D)
base_rgba = THREE_D.convert("RGBA")
base_alpha = Image.new("L", THREE_D.size, 0)
src_pixels = THREE_D.load()
alpha_pixels = base_alpha.load()
old_pixels = old_mask.load()
for y in range(THREE_D.height):
    for x in range(THREE_D.width):
        r, g, b = src_pixels[x, y]
        if max(r, g, b) > 14:
            alpha_pixels[x, y] = 255 - old_pixels[x, y]
base_rgba.putalpha(base_alpha)
three_d_normal = Image.new("RGBA", THREE_D.size, (0, 0, 0, 255))
three_d_normal.alpha_composite(THREE_D_FEET)
three_d_normal.alpha_composite(base_rgba)
three_d_normal = three_d_normal.convert("RGB")
three_d_normal.save(ASSETS / "season1-3d-normal-feet.png", optimize=True)


def resize_contain(image: Image.Image, max_w: int, max_h: int) -> Image.Image:
    scale = min(max_w / image.width, max_h / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)


def add_arm(screen: Image.Image, arm: Image.Image, pivot: tuple[int, int], length: int, degrees: float) -> None:
    width = round(length * arm.width / arm.height)
    scaled_arm = arm.resize((width, length), Image.Resampling.LANCZOS)
    staging = Image.new("RGBA", screen.size, (0, 0, 0, 0))
    staging.alpha_composite(scaled_arm, (pivot[0] - width // 2, pivot[1] - length))
    rotated = staging.rotate(degrees, center=pivot, resample=Image.Resampling.BICUBIC)
    screen.alpha_composite(rotated)


def ticks(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rx, ry = (x1 - x0) * .45, (y1 - y0) * .45
    for hour in range(12):
        angle = math.radians(hour * 30 - 90)
        x = cx + math.cos(angle) * rx
        y = cy + math.sin(angle) * ry
        major = hour % 3 == 0
        if major:
            if hour in (0, 6):
                draw.rounded_rectangle((x - 7, y - 1.5, x + 7, y + 1.5), radius=2, fill=(225, 225, 225, 195))
            else:
                draw.rounded_rectangle((x - 1.5, y - 7, x + 1.5, y + 7), radius=2, fill=(225, 225, 225, 195))
        else:
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(210, 210, 210, 115))


def watch_preview(body: Image.Image | None = None, image_3d: Image.Image | None = None) -> Image.Image:
    """Render one 540×680 OLED screen at the corrected normal scale."""
    screen = Image.new("RGBA", (540, 680), (0, 0, 0, 255))
    if body is not None:
        # 544/680 = 80%; identical scale for A/B/C.
        body_h = 544
        body_w = round(body_h * body.width / body.height)
        top = 88
        pivot_y = top + round(body_h * .47)
        add_arm(screen, HOUR_ARM, (270 - 6, pivot_y), 226, 60)
        add_arm(screen, MINUTE_ARM, (270 + 6, pivot_y), 284, -60)
        scaled_body = body.resize((body_w, body_h), Image.Resampling.LANCZOS)
        screen.alpha_composite(scaled_body, ((540 - body_w) // 2, top))
    elif image_3d is not None:
        # Enlarge the native 3D render for the watch composition only.  It is
        # still downsampled into the board, so no upscale artifacts are shown.
        crop = image_3d.crop((115, 105, 750, 870))
        fitted = resize_contain(crop, 505, 557)
        screen.alpha_composite(fitted.convert("RGBA"), ((540 - fitted.width) // 2, 96))

    d = ImageDraw.Draw(screen)
    ticks(d, (0, 0, screen.width, screen.height))
    text_font = font(43)
    label = "10:10"
    bbox = d.textbbox((0, 0), label, font=text_font)
    d.text(((540 - (bbox[2] - bbox[0])) / 2, 30), label, font=text_font, fill=(247, 247, 247, 242))
    return screen


PREVIEWS = {key: watch_preview(body=image) for key, image in BODY_VARIANTS.items()}
PREVIEW_3D = watch_preview(image_3d=three_d_normal)
for key, image in PREVIEWS.items():
    image.convert("RGB").save(ASSETS / f"watch-{key}.png", optimize=True)
PREVIEW_3D.convert("RGB").save(ASSETS / "watch-3d-normal.png", optimize=True)


W, H = 3600, 3200
board = Image.new("RGB", (W, H), (15, 15, 19))
draw = ImageDraw.Draw(board)
white = (244, 241, 243)
muted = (171, 164, 171)
accent = (243, 148, 173)
line = (47, 45, 51)
panel = (24, 24, 30)

draw.text((180, 120), "1999 SEASON-1 · FOOT / SCALE DECISION", font=font(65, True), fill=white)
draw.text((180, 205), "固定同一身體、臉、色盤與 10:10 指針，只比較腳型；角色錶面高度統一為 80%。",
          font=font(31), fill=muted)
draw.text((3420, 145), "APPLE WATCH · PURE BLACK OLED", anchor="ra", font=font(26, True), fill=accent)
draw.line((180, 285, 3420, 285), fill=line, width=3)


def panel_box(box: tuple[int, int, int, int], radius: int = 34) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=panel, outline=line, width=3)


def draw_watch_card(x: int, key: str, title: str, subtitle: str, primary: bool = False) -> None:
    card = (x, 355, x + 1020, 1680)
    panel_box(card, 42)
    if primary:
        draw.rounded_rectangle((x + 2, 357, x + 1018, 1678), radius=40, outline=accent, width=5)
    screen = PREVIEWS[key].resize((675, 850), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (735, 910), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, 734, 909), radius=150, fill=(47, 47, 53), outline=(105, 105, 112), width=18)
    fd.rounded_rectangle((30, 30, 705, 880), radius=127, fill=(0, 0, 0))
    frame.alpha_composite(screen, (30, 30))
    board.paste(frame, (x + 142, 405), frame)
    draw.text((x + 65, 1360), title, font=font(37, True), fill=accent if primary else white)
    draw.text((x + 65, 1420), subtitle, font=font(27), fill=muted)
    if primary:
        draw.rounded_rectangle((x + 680, 1350, x + 955, 1410), radius=30, fill=(243, 148, 173))
        draw.text((x + 818, 1380), "NORMAL · PRIMARY", anchor="mm", font=font(23, True), fill=(28, 17, 22))
    draw.text((x + 65, 1510), "BODY 80%  ·  DIGITAL 10:10  ·  ARMS = POINTERS",
              font=font(22, True), fill=(202, 195, 201))


draw_watch_card(180, "a-compact", "A · COMPACT CANONICAL", "短、收斂；更接近早期卡通簡化腳。")
draw_watch_card(1290, "b-normal", "B · NORMAL PROPORTION", "中等重量、自然接腿、微外轉；不小也不扁長。", True)
draw_watch_card(2400, "c-wide", "C · WIDE GRAPHIC", "較寬、較平、外撇；圖形感最強。")

draw.text((180, 1760), "SHORTS → LEG → FOOT CONNECTION · 1:1 SOURCE CROP", font=font(32, True), fill=white)
draw.text((3420, 1760), "三款均為重新繪製輪廓，不是把原腳縮放或拉寬。", anchor="ra", font=font(25), fill=muted)

for index, key in enumerate(("a-compact", "b-normal", "c-wide")):
    x = 180 + index * 1110
    box = (x, 1820, x + 1020, 2300)
    panel_box(box, 32)
    source = BODY_VARIANTS[key]
    crop = source.crop((0, 700, source.width, source.height))
    crop = resize_contain(crop, 930, 420)
    crop_panel = Image.new("RGBA", (930, 420), (0, 0, 0, 255))
    crop_panel.alpha_composite(crop, ((930 - crop.width) // 2, (420 - crop.height) // 2))
    board.paste(crop_panel.convert("RGB"), (x + 45, 1850))
    letter = ("A", "B · NORMAL", "C")[index]
    draw.rounded_rectangle((x + 65, 2215, x + 260, 2265), radius=20, fill=(17, 17, 20))
    draw.text((x + 162, 2240), letter, anchor="mm", font=font(22, True), fill=accent if index == 1 else white)

# Matching faithful 3D translation of B only.
panel_box((180, 2380, 3420, 3060), 42)
draw.text((250, 2450), "B / NORMAL → FAITHFUL MATTE 3D", font=font(43, True), fill=white)
draw.text((250, 2520), "只翻譯中性腳型：保留短寬比例與微外轉，增加淺層體積；沒有改成亮面玩具或大眼公仔。",
          font=font(28), fill=muted)
draw.text((250, 2605), "2D normal", font=font(25, True), fill=accent)
normal_2d = PREVIEWS["b-normal"].resize((420, 529), Image.Resampling.LANCZOS)
board.paste(normal_2d.convert("RGB"), (760, 2445))
draw.text((1355, 2605), "3D normal", font=font(25, True), fill=accent)
normal_3d = PREVIEW_3D.resize((420, 529), Image.Resampling.LANCZOS)
board.paste(normal_3d.convert("RGB"), (1840, 2445))
draw.text((2420, 2600), "SCALE CHECK", font=font(25, True), fill=accent)
draw.text((2420, 2655), "角色高度：80%\n數字與頭頂：保留安全間距\n刻度：只沿邊緣\n圓形錶盤：無\n雙臂：10:10 清楚可讀",
          font=font(28), fill=white, spacing=18)

draw.line((180, 3120, 3420, 3120), fill=line, width=3)
draw.text((180, 3150), "RECOMMENDED: B / NORMAL · neutral mass, readable connection, no flipper silhouette",
          font=font(24, True), fill=accent)
draw.text((3420, 3150), "SOURCE ASSETS: transparent cel feet/body + separate matte 3D normal feet",
          anchor="ra", font=font(22), fill=muted)

FINAL = OUT / "season1-feet-scale-board-final.png"
board.save(FINAL, optimize=True)

print(FINAL)
for path in sorted(ASSETS.glob("*.png")):
    with Image.open(path) as image:
        print(path.name, image.size, image.mode)
print("board", board.size, board.mode)
