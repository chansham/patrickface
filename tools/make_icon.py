# 生成派大星 App 圖示（1024x1024）
import math
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGB", (S, S), (9, 17, 38))
d = ImageDraw.Draw(img)


def pseudo(i):
    v = math.sin(i * 12.9898) * 43758.5453
    return v - math.floor(v)


# 星空背景
for i in range(140):
    x = pseudo(i * 3 + 1) * S
    y = pseudo(i * 3 + 2) * S
    r = 1 + pseudo(i * 3 + 3) * 3
    a = 0.35 + 0.6 * pseudo(i * 5 + 4)
    c = tuple(int(200 + 55 * a) for _ in range(3))
    d.ellipse([x - r, y - r, x + r, y + r], fill=(int(180 * a), int(195 * a), int(235 * a)))

PINK = (247, 168, 196)
OUTLINE = (201, 107, 147)

# 派大星：胖五角星身體
cx, cy = 512, 600
outer, inner = 400, 300
pts = []
for k in range(5):
    a1 = -math.pi / 2 + k * (2 * math.pi / 5)
    a2 = a1 + math.pi / 5
    pts.append((cx + outer * math.cos(a1), cy + outer * math.sin(a1)))
    pts.append((cx + inner * math.cos(a2), cy + inner * math.sin(a2)))
d.polygon(pts, fill=PINK, outline=OUTLINE, width=12)

# 眼睛
for ex in (408, 616):
    d.ellipse([ex - 62, 268, ex + 62, 480], fill=(255, 255, 255), outline=OUTLINE, width=8)
    d.ellipse([ex - 24, 372, ex + 24, 420], fill=(38, 32, 42))
    d.ellipse([ex - 14, 380, ex - 2, 392], fill=(255, 255, 255))

# 眉毛
d.arc([330, 210, 486, 300], start=200, end=340, fill=(90, 59, 77), width=16)
d.arc([538, 210, 694, 300], start=200, end=340, fill=(90, 59, 77), width=16)

# 嘴巴（開口笑）
d.pieslice([392, 470, 632, 660], start=15, end=165, fill=(122, 46, 61), outline=OUTLINE, width=8)
d.ellipse([462, 560, 562, 610], fill=(232, 140, 160))

img.save(r"<PROJECT_DIR>\PatrickFace\Assets.xcassets\AppIcon.appiconset\AppIcon.png")
print("icon saved")
