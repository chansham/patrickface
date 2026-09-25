from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(r"<PROJECT_DIR>")
ASSETS = ROOT / "comparison" / "assets"
OUTPUT = ROOT / "comparison" / "style-board-final.png"

W = H = 1024
canvas = Image.new("RGB", (W, H), (15, 15, 19))
draw = ImageDraw.Draw(canvas)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    names = (
        [r"C:\Windows\Fonts\msjhbd.ttc", r"C:\Windows\Fonts\msyhbd.ttc"]
        if bold
        else [r"C:\Windows\Fonts\msjh.ttc", r"C:\Windows\Fonts\msyh.ttc"]
    )
    names += [r"C:\Windows\Fonts\arial.ttf"]
    for name in names:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


TITLE = font(35, True)
SUBTITLE = font(15)
STYLE = font(10, True)
NAME = font(18, True)
BODY = font(11)
DIGITAL = font(22)
FOOTER = font(11)


styles = [
    (
        "01",
        "原版電視動畫感",
        "辨識度最高、最接近角色本人；靠準確線條建立質感。",
        "style-01-cel.png",
    ),
    (
        "02",
        "精緻表現線稿",
        "最輕、最俐落；黑底閱讀性佳，但奢華材質較少。",
        "style-02-line.png",
    ),
    (
        "03",
        "編輯繪畫插畫",
        "有收藏插畫感；縮小後需控制筆觸，避免細節流失。",
        "style-03-painted.png",
    ),
    (
        "04",
        "90 年代網點印刷",
        "復古潮流個性最強；量產時需避免網點摩爾紋。",
        "style-04-halftone.png",
    ),
    (
        "05",
        "黏土定格動畫",
        "手作生命感最鮮明；會比原版平面動畫更具物質感。",
        "style-05-clay.png",
    ),
    (
        "06",
        "成熟設計師玩具",
        "產品級光影最強；高級但也最偏離傳統電視畫風。",
        "style-06-designer-toy.png",
    ),
]


def fit_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def rounded_paste(
    destination: Image.Image,
    source: Image.Image,
    box: tuple[int, int, int, int],
    radius: int,
) -> None:
    x0, y0, x1, y1 = box
    source = source.resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    mask = Image.new("L", source.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, source.width - 1, source.height - 1), radius, fill=255)
    destination.paste(source, (x0, y0), mask)


def split_two_lines(text: str, limit: int = 18) -> tuple[str, str]:
    if len(text) <= limit:
        return text, ""
    split = min(limit, len(text))
    for index in range(split, max(4, split - 6), -1):
        if text[index] in "，；、。":
            split = index + 1
            break
    return text[:split], text[split:]


def marker(draw_context: ImageDraw.ImageDraw, x: int, y: int, major: str | None = None) -> None:
    color = (180, 180, 185) if major else (100, 100, 106)
    if major in ("12", "6"):
        draw_context.rounded_rectangle((x - 5, y - 1, x + 5, y + 1), radius=1, fill=color)
    elif major in ("3", "9"):
        draw_context.rounded_rectangle((x - 1, y - 5, x + 1, y + 5), radius=1, fill=color)
    else:
        draw_context.ellipse((x - 1, y - 1, x + 1, y + 1), fill=color)


# Header
draw.text((35, 28), "派大星 Apple Watch 畫風比較", font=TITLE, fill=(247, 244, 246))
draw.text(
    (36, 73),
    "同一個 10:10 版式：雙臂＝時針/分針 · 邊緣刻度 · 數字時間 · 純黑 OLED",
    font=SUBTITLE,
    fill=(174, 166, 174),
)
draw.line((35, 105, W - 35, 105), fill=(45, 44, 50), width=1)

card_w, card_h = 306, 412
gap_x, gap_y = 18, 18
start_x, start_y = 35, 125

for index, (number, name, tradeoff, filename) in enumerate(styles):
    row, col = divmod(index, 3)
    x = start_x + col * (card_w + gap_x)
    y = start_y + row * (card_h + gap_y)

    draw.rounded_rectangle(
        (x, y, x + card_w, y + card_h),
        radius=24,
        fill=(22, 22, 27),
        outline=(45, 44, 51),
        width=1,
    )

    watch_w, watch_h = 176, 220
    watch_x = x + (card_w - watch_w) // 2
    watch_y = y + 16
    draw.rounded_rectangle(
        (watch_x, watch_y, watch_x + watch_w, watch_y + watch_h),
        radius=44,
        fill=(38, 38, 43),
        outline=(89, 89, 96),
        width=3,
    )

    inset = 7
    sx0, sy0 = watch_x + inset, watch_y + inset
    sx1, sy1 = watch_x + watch_w - inset, watch_y + watch_h - inset
    screen = fit_cover(Image.open(ASSETS / filename).convert("RGB"), (sx1 - sx0, sy1 - sy0))
    rounded_paste(canvas, screen, (sx0, sy0, sx1, sy1), radius=37)

    # Identical time architecture on every style.
    cx, cy = (sx0 + sx1) // 2, (sy0 + sy1) // 2
    top, bottom = sy0 + 10, sy1 - 10
    left, right = sx0 + 10, sx1 - 10
    marker(draw, cx, top, "12")
    marker(draw, right, cy, "3")
    marker(draw, cx, bottom, "6")
    marker(draw, left, cy, "9")
    points = [
        (int(sx0 + (sx1 - sx0) * 0.75), int(sy0 + (sy1 - sy0) * 0.08)),
        (int(sx0 + (sx1 - sx0) * 0.92), int(sy0 + (sy1 - sy0) * 0.27)),
        (int(sx0 + (sx1 - sx0) * 0.92), int(sy0 + (sy1 - sy0) * 0.73)),
        (int(sx0 + (sx1 - sx0) * 0.75), int(sy0 + (sy1 - sy0) * 0.92)),
        (int(sx0 + (sx1 - sx0) * 0.25), int(sy0 + (sy1 - sy0) * 0.92)),
        (int(sx0 + (sx1 - sx0) * 0.08), int(sy0 + (sy1 - sy0) * 0.73)),
        (int(sx0 + (sx1 - sx0) * 0.08), int(sy0 + (sy1 - sy0) * 0.27)),
        (int(sx0 + (sx1 - sx0) * 0.25), int(sy0 + (sy1 - sy0) * 0.08)),
    ]
    for px, py in points:
        marker(draw, px, py)

    digital_box = draw.textbbox((0, 0), "10:10", font=DIGITAL)
    digital_w = digital_box[2] - digital_box[0]
    draw.text(
        (cx - digital_w // 2, sy0 + 18),
        "10:10",
        font=DIGITAL,
        fill=(243, 241, 243),
    )

    label_y = y + 252
    draw.text((x + 18, label_y), f"STYLE {number}", font=STYLE, fill=(243, 142, 172))
    draw.text((x + 18, label_y + 20), name, font=NAME, fill=(247, 244, 246))
    line1, line2 = split_two_lines(tradeoff)
    draw.text((x + 18, label_y + 52), line1, font=BODY, fill=(166, 158, 166))
    if line2:
        draw.text((x + 18, label_y + 70), line2, font=BODY, fill=(166, 158, 166))

draw.text(
    (35, 988),
    "固定不變：Apple Watch 矩形螢幕、純黑背景、角色比例、10:10 雙臂、周邊刻度與數字時間。",
    font=FOOTER,
    fill=(137, 131, 138),
)

canvas.save(OUTPUT, optimize=True)
print(OUTPUT)
