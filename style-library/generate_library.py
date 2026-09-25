from __future__ import annotations

import hashlib
import json
import math
import random
import shutil
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
REFERENCE = Path(
    r"<USER_HOME>\.cursor\projects\<PROJECT_SLUG>\assets"
    r"\<USER_HOME>_.cursor_projects_<PROJECT_SLUG>_assets_<USER_HOME>_AppData_Roaming_Cursor_User_workspaceStorage_e3578c596abe3e051a6fc784b89a5c20_images_image-fcb3bfe4-b8b5-4443-9300-f0908dc0e1ad.png"
)
CANVAS = (1024, 1024)
RUNTIME = (256, 256)
CLOCK_PIVOT = (512, 500)


FAMILIES = {
    "cel-1999": {
        "name": "Clean 1999 broadcast cel",
        "short": "CEL 1999",
        "skin": (244, 133, 121, 255),
        "skin_dark": (207, 87, 83, 255),
        "line": (43, 34, 39, 255),
        "cloth": (173, 201, 75, 255),
        "accent": (118, 69, 154, 255),
        "paper": (255, 248, 230, 255),
        "construction": "Uneven single-pass cel contour with flat hand-painted fills.",
        "edge": "Firm ink edge, tiny registration wobble, no digital smoothing aesthetic.",
        "material": "Opaque cel paint with restrained two-tone spot accents.",
    },
    "model-sheet-bw": {
        "name": "B/W animation model sheet",
        "short": "MODEL SHEET",
        "skin": (250, 248, 240, 242),
        "skin_dark": (208, 208, 202, 255),
        "line": (28, 29, 28, 255),
        "cloth": (245, 245, 238, 245),
        "accent": (35, 35, 35, 255),
        "paper": (255, 255, 250, 255),
        "construction": "Redrawn graphite/ink contour with visible searching strokes.",
        "edge": "Double-line corrections, broken construction arcs, variable pressure.",
        "material": "Strict black, white, and neutral gray animation-paper logic.",
    },
    "pen-line": {
        "name": "Expressive pen-line illustration",
        "short": "PEN LINE",
        "skin": (235, 170, 149, 235),
        "skin_dark": (168, 83, 68, 255),
        "line": (64, 43, 37, 255),
        "cloth": (179, 177, 94, 245),
        "accent": (119, 75, 102, 255),
        "paper": (246, 231, 203, 245),
        "construction": "Loose nib redraw with elastic curves and deliberate overshoot.",
        "edge": "Dry pen skips, parallel contour searching, directional hatching.",
        "material": "Transparent watercolor-like fill under warm brown pen.",
    },
    "sumi-e": {
        "name": "Chinese ink-wash 水墨",
        "short": "SUMI-E",
        "skin": (170, 119, 108, 150),
        "skin_dark": (126, 48, 39, 220),
        "line": (31, 30, 28, 230),
        "cloth": (106, 126, 76, 190),
        "accent": (178, 53, 38, 230),
        "paper": (230, 225, 207, 175),
        "construction": "Shape rebuilt as overlapping wet washes and calligraphic strokes.",
        "edge": "Feathered ink diffusion, broken dry-brush perimeter, lost-and-found contour.",
        "material": "Translucent carbon wash with restrained cinnabar and moss accents.",
    },
    "riso-woodcut": {
        "name": "Vintage woodcut / risograph",
        "short": "RISO CUT",
        "skin": (232, 90, 81, 245),
        "skin_dark": (127, 42, 70, 255),
        "line": (45, 34, 70, 255),
        "cloth": (57, 152, 145, 245),
        "accent": (91, 50, 112, 255),
        "paper": (245, 224, 175, 245),
        "construction": "Angular block-cut silhouette with independently registered plates.",
        "edge": "Coarse carved contour, teal misregistration, clipped hatch channels.",
        "material": "Two-ink riso overprint, visible halftone and carved negative marks.",
    },
    "clay-3d": {
        "name": "Faithful non-cute clay 3D",
        "short": "CLAY 3D",
        "skin": (220, 112, 100, 255),
        "skin_dark": (132, 55, 53, 255),
        "line": (91, 47, 47, 220),
        "cloth": (137, 166, 65, 255),
        "accent": (94, 53, 130, 255),
        "paper": (231, 207, 171, 255),
        "construction": "Re-sculpted pear volume with small face and long un-cute taper.",
        "edge": "Soft occlusion edge, asymmetric compression, modeled seam at sockets.",
        "material": "Layered clay shading, finger dents, matte roughness, no toy gloss.",
    },
}


ASSET_SPECS = [
    ("body", "armless-base"),
    ("arms", "hour"),
    ("arms", "minute"),
    ("feet", "corrected"),
    ("eyes-lids-brows", "eyes-sleepy"),
    ("eyes-lids-brows", "eyes-alert"),
    ("eyes-lids-brows", "lids-half"),
    ("eyes-lids-brows", "brows-annoyed"),
    ("mouths", "neutral"),
    ("mouths", "happy"),
    ("mouths", "surprised"),
    ("clothing", "trunks-classic"),
    ("clothing", "sleep-robe"),
    ("accessories", "nightcap"),
    ("accessories", "party-hat"),
    ("overlays", "sleep"),
    ("overlays", "charging"),
    ("overlays", "low-battery"),
    ("overlays", "happy"),
    ("overlays", "surprised"),
]


def ensure_dirs() -> None:
    for name in ("assets-src", "assets-watchos", "previews", "spec", "reference"):
        (ROOT / name).mkdir(parents=True, exist_ok=True)


def font(size: int, bold: bool = False, mono: bool = False) -> ImageFont.FreeTypeFont:
    if mono:
        candidates = [r"C:\Windows\Fonts\consolab.ttf", r"C:\Windows\Fonts\consola.ttf"]
    elif bold:
        candidates = [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\seguisb.ttf", r"C:\Windows\Fonts\arialbd.ttf"]
    else:
        candidates = [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\arial.ttf"]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def catmull_rom(points: list[tuple[float, float]], steps: int = 18) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = points[(i - 1) % n], points[i], points[(i + 1) % n], points[(i + 2) % n]
        for step in range(steps):
            t = step / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * (
                (2 * p1[0])
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                (2 * p1[1])
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            )
            result.append((round(x), round(y)))
    return result


def jitter(points: list[tuple[int, int]], amount: float, seed: int) -> list[tuple[int, int]]:
    rnd = random.Random(seed)
    return [(round(x + rnd.uniform(-amount, amount)), round(y + rnd.uniform(-amount, amount))) for x, y in points]


def shift(points: list[tuple[int, int]], dx: int, dy: int) -> list[tuple[int, int]]:
    return [(x + dx, y + dy) for x, y in points]


def shape_mask(points: list[tuple[int, int]]) -> Image.Image:
    mask = Image.new("L", CANVAS, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def clipped(layer: Image.Image, mask: Image.Image) -> Image.Image:
    layer = layer.copy()
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return layer


def alpha_composite(base: Image.Image, layer: Image.Image) -> None:
    base.alpha_composite(layer)


def body_points(slug: str) -> list[tuple[int, int]]:
    controls = {
        "cel-1999": [(512, 105), (466, 200), (390, 290), (316, 448), (286, 620), (323, 750), (405, 815), (510, 803), (620, 819), (699, 754), (740, 618), (707, 452), (631, 290), (557, 197)],
        "model-sheet-bw": [(501, 112), (451, 205), (377, 304), (305, 470), (286, 634), (328, 759), (417, 814), (520, 798), (629, 812), (706, 744), (731, 603), (696, 443), (621, 282), (548, 191)],
        "pen-line": [(517, 99), (470, 193), (395, 281), (321, 439), (291, 609), (315, 746), (396, 818), (503, 807), (614, 826), (702, 758), (744, 626), (712, 456), (640, 300), (566, 202)],
        "sumi-e": [(509, 110), (458, 211), (382, 305), (310, 463), (292, 626), (332, 752), (413, 808), (514, 794), (616, 814), (695, 743), (726, 607), (694, 451), (626, 293), (551, 196)],
        "riso-woodcut": [(508, 108), (462, 197), (378, 301), (305, 459), (286, 631), (329, 763), (410, 813), (509, 800), (624, 820), (704, 751), (741, 612), (704, 444), (630, 284), (557, 194)],
        "clay-3d": [(515, 101), (472, 190), (398, 280), (327, 437), (297, 604), (325, 742), (404, 812), (511, 805), (619, 824), (698, 764), (733, 629), (709, 470), (642, 303), (566, 198)],
    }
    return catmull_rom(controls[slug], 20)


def semantic_color(cfg: dict, semantic: str) -> tuple[int, int, int, int]:
    if semantic == "skin":
        return cfg["skin"]
    if semantic == "cloth":
        return cfg["cloth"]
    if semantic == "paper":
        return cfg["paper"]
    return cfg["accent"]


def pattern_inside(base: Image.Image, mask: Image.Image, painter: Image.Image) -> None:
    base.alpha_composite(clipped(painter, mask))


def paint_shape(
    points: list[tuple[int, int]],
    slug: str,
    semantic: str = "skin",
    seed: int = 1,
    mask_extra: Image.Image | None = None,
) -> Image.Image:
    cfg = FAMILIES[slug]
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    mask = shape_mask(points)
    if mask_extra is not None:
        mask = ImageChops.lighter(mask, mask_extra)
    draw = ImageDraw.Draw(out)
    fill = semantic_color(cfg, semantic)
    line = cfg["line"]

    if slug == "cel-1999":
        draw.polygon(points, fill=fill)
        draw.line(points + [points[0]], fill=line, width=11, joint="curve")
        draw.line(jitter(points, 1.7, seed) + [jitter(points, 1.7, seed)[0]], fill=(72, 44, 48, 100), width=3, joint="curve")
    elif slug == "model-sheet-bw":
        draw.polygon(points, fill=fill)
        draw.line(jitter(points, 2.4, seed) + [jitter(points, 2.4, seed)[0]], fill=line, width=7, joint="curve")
        draw.line(jitter(points, 4.5, seed + 7) + [jitter(points, 4.5, seed + 7)[0]], fill=(35, 35, 35, 118), width=3, joint="curve")
        hatch = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hatch)
        for x in range(250, 780, 34):
            hd.line((x, 720, x + 65, 650), fill=(20, 20, 20, 58), width=2)
        pattern_inside(out, mask, hatch)
    elif slug == "pen-line":
        draw.polygon(points, fill=fill)
        draw.line(jitter(points, 3.0, seed) + [jitter(points, 3.0, seed)[0]], fill=line, width=7, joint="curve")
        draw.line(jitter(points, 5.0, seed + 2) + [jitter(points, 5.0, seed + 2)[0]], fill=(74, 44, 36, 108), width=2, joint="curve")
        hatch = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hatch)
        for x in range(245, 790, 23):
            y = 330 + ((x * 7) % 170)
            hd.line((x, y, x + 75, y + 115), fill=(77, 45, 36, 47), width=3)
        pattern_inside(out, mask, hatch)
    elif slug == "sumi-e":
        rnd = random.Random(seed)
        for i in range(8):
            pts = shift(jitter(points, 5 + i * 0.8, seed + i), rnd.randint(-5, 5), rnd.randint(-4, 7))
            ImageDraw.Draw(out).polygon(pts, fill=(fill[0], fill[1], fill[2], 20 + i * 8))
        wash = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        wd = ImageDraw.Draw(wash)
        for _ in range(130):
            x, y = rnd.randint(270, 750), rnd.randint(120, 830)
            r = rnd.randint(2, 14)
            wd.ellipse((x - r, y - r, x + r, y + r), fill=(24, 23, 22, rnd.randint(5, 22)))
        pattern_inside(out, mask.filter(ImageFilter.GaussianBlur(2.2)), wash)
        contour = jitter(points, 4.8, seed + 30)
        cd = ImageDraw.Draw(out)
        for start in range(0, len(contour), 18):
            segment = contour[start : start + 14]
            if len(segment) > 1:
                cd.line(segment, fill=(line[0], line[1], line[2], random.Random(seed + start).randint(135, 225)), width=random.Random(seed + start + 1).randint(5, 13), joint="curve")
    elif slug == "riso-woodcut":
        shadow = shift(points, 9, 6)
        draw.polygon(shadow, fill=(28, 144, 143, 155))
        draw.polygon(points, fill=fill)
        angular = points[::9]
        draw.line(angular + [angular[0]], fill=line, width=16, joint="curve")
        hatch = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hatch)
        for x in range(210, 820, 29):
            hd.line((x, 820, x + 235, 280), fill=(45, 34, 70, 92), width=7)
        for y in range(170, 850, 34):
            offset = 12 if (y // 34) % 2 else 0
            for x in range(300 + offset, 740, 32):
                hd.ellipse((x, y, x + 4, y + 4), fill=(245, 224, 175, 125))
        pattern_inside(out, mask, hatch)
    else:
        base = Image.new("RGBA", CANVAS, fill)
        base.putalpha(mask)
        out.alpha_composite(base)
        shade = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shade)
        sd.ellipse((420, 110, 900, 900), fill=(73, 20, 30, 105))
        sd.ellipse((250, 120, 585, 685), fill=(255, 225, 190, 78))
        shade = shade.filter(ImageFilter.GaussianBlur(95))
        pattern_inside(out, mask, shade)
        draw = ImageDraw.Draw(out)
        draw.line(points + [points[0]], fill=line, width=8, joint="curve")
        texture = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        td = ImageDraw.Draw(texture)
        rnd = random.Random(seed)
        for _ in range(115):
            x, y, r = rnd.randint(280, 735), rnd.randint(130, 825), rnd.randint(2, 10)
            tone = (74, 29, 33, rnd.randint(7, 24)) if rnd.random() < 0.6 else (255, 225, 192, rnd.randint(6, 19))
            td.ellipse((x - r * 2, y - r, x + r * 2, y + r), fill=tone)
        pattern_inside(out, mask, texture.filter(ImageFilter.GaussianBlur(1.6)))
    return out


def body_asset(slug: str) -> Image.Image:
    points = body_points(slug)
    out = paint_shape(points, slug, "skin", seed=101)
    cfg = FAMILIES[slug]
    mask = shape_mask(points)
    details = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(details)
    spots = [(360, 397, 13), (682, 459, 10), (642, 275, 8), (382, 611, 9), (664, 668, 11), (457, 191, 7)]
    for i, (x, y, r) in enumerate(spots):
        if slug == "model-sheet-bw":
            d.ellipse((x - r, y - r, x + r, y + r), outline=(35, 35, 35, 150), width=2)
        elif slug == "sumi-e":
            d.ellipse((x - r * 2, y - r, x + r * 2, y + r), fill=(126, 48, 39, 75))
        elif slug == "riso-woodcut":
            d.rectangle((x - r, y - r // 2, x + r, y + r // 2), fill=cfg["accent"])
        elif slug == "clay-3d":
            d.ellipse((x - r, y - r, x + r, y + r), fill=(108, 49, 47, 65))
            d.arc((x - r, y - r, x + r, y + r), 185, 350, fill=(255, 204, 181, 55), width=2)
        else:
            d.ellipse((x - r, y - r, x + r, y + r), fill=cfg["skin_dark"])
    pattern_inside(out, mask, details)
    return out


def arm_points(slug: str, variant: str) -> list[tuple[int, int]]:
    px, py = CLOCK_PIVOT
    minute = variant == "minute"
    length = (354 if minute else 257) + {"pen-line": 7, "sumi-e": -5, "clay-3d": 4}.get(slug, 0)
    half = 31 if minute else 45
    tip = py - length
    # Three intentionally blunt fingers preserve the early, non-cute hand language.
    points = [
        (px - half, py + 26), (px - half + 8, py - 38), (px - 24, tip + 66),
        (px - 43, tip + 47), (px - 31, tip + 29), (px - 14, tip + 43),
        (px - 9, tip + 2), (px + 7, tip + 22), (px + 20, tip - 8),
        (px + 26, tip + 31), (px + 50, tip + 19), (px + 34, tip + 69),
        (px + half - 7, py - 36), (px + half, py + 26),
    ]
    if slug == "model-sheet-bw":
        points = shift(points, -3, 0)
    elif slug == "pen-line":
        points = jitter(points, 4.2, 230 if minute else 220)
    elif slug == "sumi-e":
        points = jitter(points, 7.0, 330 if minute else 320)
    elif slug == "riso-woodcut":
        points = points[::2] + [points[-1]]
    elif slug == "clay-3d":
        points = jitter(points, 2.2, 430 if minute else 420)
    return points


def arm_asset(slug: str, variant: str) -> Image.Image:
    points = arm_points(slug, variant)
    joint = Image.new("L", CANVAS, 0)
    radius = 51 if variant == "hour" else 43
    ImageDraw.Draw(joint).ellipse(
        (CLOCK_PIVOT[0] - radius, CLOCK_PIVOT[1] - radius, CLOCK_PIVOT[0] + radius, CLOCK_PIVOT[1] + radius),
        fill=255,
    )
    out = paint_shape(points, slug, "skin", seed=201 if variant == "hour" else 211, mask_extra=joint)
    cfg = FAMILIES[slug]
    d = ImageDraw.Draw(out)
    if slug == "model-sheet-bw":
        d.ellipse((477, 465, 547, 535), outline=cfg["line"], width=4)
        d.line((486, 500, 538, 500), fill=(30, 30, 30, 70), width=2)
    elif slug == "clay-3d":
        d.arc((470, 458, 554, 542), 195, 345, fill=(255, 201, 178, 90), width=7)
        d.arc((470, 458, 554, 542), 15, 165, fill=(89, 35, 41, 100), width=8)
    return out


def feet_points() -> tuple[list[tuple[int, int]], list[tuple[int, int]]]:
    left = catmull_rom([(385, 765), (355, 807), (326, 862), (353, 890), (420, 876), (458, 827), (449, 777)], 12)
    right = catmull_rom([(569, 777), (558, 828), (593, 878), (663, 892), (696, 861), (665, 811), (637, 766)], 12)
    return left, right


def feet_asset(slug: str) -> Image.Image:
    left, right = feet_points()
    out = paint_shape(left, slug, "skin", seed=301)
    out.alpha_composite(paint_shape(right, slug, "skin", seed=302))
    cfg = FAMILIES[slug]
    d = ImageDraw.Draw(out)
    toe = cfg["line"] if slug != "sumi-e" else (31, 30, 28, 150)
    for x in (350, 374, 617, 645):
        d.arc((x - 16, 846, x + 20, 886), 205, 330, fill=toe, width=3 if slug != "riso-woodcut" else 6)
    return out


def style_line(
    image: Image.Image,
    slug: str,
    points: list[tuple[int, int]],
    width: int = 7,
    fill: tuple[int, int, int, int] | None = None,
    seed: int = 1,
    closed: bool = False,
) -> None:
    cfg = FAMILIES[slug]
    fill = fill or cfg["line"]
    pts = points + ([points[0]] if closed else [])
    d = ImageDraw.Draw(image)
    if slug == "model-sheet-bw":
        d.line(jitter(pts, 1.6, seed), fill=fill, width=max(2, width - 2), joint="curve")
        d.line(jitter(pts, 3.4, seed + 1), fill=(28, 28, 28, 105), width=2, joint="curve")
    elif slug == "pen-line":
        d.line(jitter(pts, 2.2, seed), fill=fill, width=max(2, width - 1), joint="curve")
        d.line(jitter(pts, 4.0, seed + 1), fill=(64, 43, 37, 80), width=2, joint="curve")
    elif slug == "sumi-e":
        rough = jitter(pts, 3.5, seed)
        for i in range(0, len(rough) - 1, 2):
            d.line(rough[i : i + 2], fill=fill, width=width + (i % 5), joint="curve")
    elif slug == "riso-woodcut":
        d.line(pts, fill=fill, width=width + 4, joint="curve")
        d.line(shift(pts, 4, 3), fill=(31, 150, 145, 100), width=max(2, width // 3), joint="curve")
    elif slug == "clay-3d":
        d.line(pts, fill=(255, 206, 186, 75), width=width + 8, joint="curve")
        d.line(shift(pts, 2, 3), fill=fill, width=width, joint="curve")
    else:
        d.line(pts, fill=fill, width=width, joint="curve")


def face_asset(slug: str, variant: str) -> Image.Image:
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    cfg = FAMILIES[slug]
    line = cfg["line"]
    d = ImageDraw.Draw(out)
    if variant.startswith("eyes-"):
        alert = variant == "eyes-alert"
        boxes = [(466, 276, 506, 345), (516, 270, 558, 342)]
        if not alert:
            boxes = [(468, 291, 507, 337), (518, 287, 557, 334)]
        for i, box in enumerate(boxes):
            if slug == "model-sheet-bw":
                fill = (255, 255, 251, 248)
            elif slug == "sumi-e":
                fill = (235, 229, 211, 190)
            else:
                fill = (247, 242, 220, 255)
            d.ellipse(box, fill=fill)
            style_line(out, slug, [(box[0] + 5, (box[1] + box[3]) // 2), ((box[0] + box[2]) // 2, box[1]), (box[2] - 4, (box[1] + box[3]) // 2), ((box[0] + box[2]) // 2, box[3])], 5, line, 400 + i, True)
            px = (box[0] + box[2]) // 2 + (-2 if i == 0 else -5)
            py = box[1] + (34 if alert else 25)
            r = 6 if alert else 5
            d.ellipse((px - r, py - r, px + r, py + r), fill=line)
        if not alert:
            style_line(out, slug, [(467, 300), (487, 309), (507, 301)], 7, line, 412)
            style_line(out, slug, [(517, 297), (537, 305), (558, 295)], 7, line, 413)
    elif variant == "lids-half":
        style_line(out, slug, [(466, 304), (486, 315), (508, 305)], 9, line, 420)
        style_line(out, slug, [(516, 301), (538, 311), (559, 299)], 9, line, 421)
    else:
        style_line(out, slug, [(466, 271), (486, 259), (505, 269)], 9, line, 430)
        style_line(out, slug, [(519, 266), (538, 254), (559, 263)], 9, line, 431)
    return out


def mouth_asset(slug: str, variant: str) -> Image.Image:
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    cfg = FAMILIES[slug]
    line = cfg["line"]
    d = ImageDraw.Draw(out)
    if variant == "neutral":
        style_line(out, slug, [(482, 385), (504, 390), (530, 385), (547, 392)], 8, line, 501)
        d.ellipse((472, 377, 481, 386), fill=line)
    elif variant == "happy":
        points = catmull_rom([(474, 375), (490, 406), (520, 423), (551, 397), (557, 376), (523, 389)], 8)
        d.polygon(points, fill=(91, 37, 47, 240) if slug != "model-sheet-bw" else (250, 250, 246, 255))
        style_line(out, slug, points, 7, line, 502, True)
        d.arc((487, 389, 546, 423), 5, 175, fill=(230, 119, 126, 220) if slug != "model-sheet-bw" else line, width=5)
    else:
        d.ellipse((490, 371, 538, 427), fill=(89, 35, 45, 235) if slug != "model-sheet-bw" else (250, 250, 246, 255))
        style_line(out, slug, catmull_rom([(514, 370), (490, 395), (514, 428), (538, 397)], 8), 7, line, 503, True)
    return out


def clothing_asset(slug: str, variant: str) -> Image.Image:
    cfg = FAMILIES[slug]
    if variant == "trunks-classic":
        points = catmull_rom([(311, 646), (351, 704), (382, 790), (443, 806), (511, 792), (580, 810), (644, 791), (681, 702), (716, 644), (626, 660), (512, 650), (401, 662)], 10)
        out = paint_shape(points, slug, "cloth", seed=601)
        mask = shape_mask(points)
        pat = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        d = ImageDraw.Draw(pat)
        flower = cfg["accent"] if slug != "model-sheet-bw" else cfg["line"]
        for x, y in ((401, 707), (520, 754), (622, 700)):
            for a in range(0, 360, 90):
                dx, dy = math.cos(math.radians(a)) * 15, math.sin(math.radians(a)) * 15
                d.ellipse((x + dx - 10, y + dy - 6, x + dx + 10, y + dy + 6), fill=flower)
            d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=cfg["paper"])
        pattern_inside(out, mask, pat)
        return out
    points = catmull_rom([(326, 535), (352, 700), (383, 812), (510, 793), (640, 814), (681, 702), (704, 536), (603, 562), (511, 548), (415, 563)], 10)
    out = paint_shape(points, slug, "paper", seed=602)
    style_line(out, slug, [(355, 570), (512, 676), (676, 566)], 8, cfg["line"], 603)
    style_line(out, slug, [(511, 548), (511, 791)], 4, cfg["line"], 604)
    return out


def accessory_asset(slug: str, variant: str) -> Image.Image:
    cfg = FAMILIES[slug]
    if variant == "nightcap":
        points = catmull_rom([(458, 159), (487, 78), (551, 49), (618, 75), (574, 91), (544, 174)], 10)
        out = paint_shape(points, slug, "cloth", seed=701)
        d = ImageDraw.Draw(out)
        d.ellipse((603, 61, 641, 99), fill=cfg["accent"])
        return out
    points = [(458, 169), (518, 46), (581, 168)]
    out = paint_shape(points, slug, "paper", seed=702)
    d = ImageDraw.Draw(out)
    for y, color in ((89, cfg["accent"]), (125, cfg["cloth"])):
        d.line((481, y, 559, y), fill=color, width=14)
    d.ellipse((502, 28, 534, 60), fill=cfg["accent"])
    return out


def overlay_asset(slug: str, variant: str) -> Image.Image:
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    cfg = FAMILIES[slug]
    line, accent = cfg["line"], cfg["accent"]
    d = ImageDraw.Draw(out)
    if variant == "sleep":
        for i, (x, y, size) in enumerate(((690, 267, 48), (746, 211, 38), (790, 165, 29))):
            text = "Z"
            d.text((x, y), text, font=font(size, bold=True), fill=line, anchor="mm")
            if slug in ("pen-line", "model-sheet-bw"):
                d.text((x + 3, y + 2), text, font=font(size, bold=True), fill=(line[0], line[1], line[2], 75), anchor="mm")
    elif variant == "charging":
        d.arc((753, 86, 923, 256), 45, 315, fill=(99, 207, 115, 235) if slug != "model-sheet-bw" else line, width=16)
        d.polygon([(842, 120), (805, 184), (839, 179), (817, 232), (877, 160), (843, 165)], fill=(99, 207, 115, 245) if slug != "model-sheet-bw" else line)
    elif variant == "low-battery":
        red = (215, 67, 62, 245) if slug != "model-sheet-bw" else line
        d.rounded_rectangle((760, 120, 908, 194), radius=15, outline=red, width=12)
        d.rectangle((910, 143, 927, 173), fill=red)
        d.rectangle((778, 139, 815, 176), fill=red)
    elif variant == "happy":
        for a in range(0, 360, 45):
            r1, r2 = 360, 420
            x1, y1 = CLOCK_PIVOT[0] + math.cos(math.radians(a)) * r1, CLOCK_PIVOT[1] + math.sin(math.radians(a)) * r1
            x2, y2 = CLOCK_PIVOT[0] + math.cos(math.radians(a)) * r2, CLOCK_PIVOT[1] + math.sin(math.radians(a)) * r2
            style_line(out, slug, [(round(x1), round(y1)), (round(x2), round(y2))], 7, accent, 800 + a)
    else:
        for a in (-70, -45, -20, 200, 225, 250):
            x1, y1 = 512 + math.cos(math.radians(a)) * 330, 450 + math.sin(math.radians(a)) * 330
            x2, y2 = 512 + math.cos(math.radians(a)) * 430, 450 + math.sin(math.radians(a)) * 430
            style_line(out, slug, [(round(x1), round(y1)), (round(x2), round(y2))], 10, line, 900 + a)
    return out


def render_asset(slug: str, category: str, variant: str) -> Image.Image:
    if category == "body":
        return body_asset(slug)
    if category == "arms":
        return arm_asset(slug, variant)
    if category == "feet":
        return feet_asset(slug)
    if category == "eyes-lids-brows":
        return face_asset(slug, variant)
    if category == "mouths":
        return mouth_asset(slug, variant)
    if category == "clothing":
        return clothing_asset(slug, variant)
    if category == "accessories":
        return accessory_asset(slug, variant)
    return overlay_asset(slug, variant)


def filename(slug: str, category: str, variant: str, runtime: bool = False) -> str:
    tier = "rt_256" if runtime else "src_1024"
    return f"pf_{slug}_{category}_{variant}_{tier}.png"


def rel_asset_path(slug: str, category: str, variant: str, runtime: bool = False) -> Path:
    root = "assets-watchos" if runtime else "assets-src"
    return Path(root) / slug / category / filename(slug, category, variant, runtime)


def save_png(image: Image.Image, path: Path, runtime: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if runtime:
        image = image.resize(RUNTIME, Image.Resampling.LANCZOS)
        image.save(path, "PNG", optimize=True, compress_level=9)
    else:
        image.save(path, "PNG", compress_level=6)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def build_assets() -> list[dict]:
    records: list[dict] = []
    for slug, cfg in FAMILIES.items():
        for category, variant in ASSET_SPECS:
            image = render_asset(slug, category, variant)
            source_rel = rel_asset_path(slug, category, variant)
            runtime_rel = rel_asset_path(slug, category, variant, True)
            source_path, runtime_path = ROOT / source_rel, ROOT / runtime_rel
            save_png(image, source_path)
            save_png(image, runtime_path, runtime=True)
            bounds = image.getbbox()
            record = {
                "id": f"pf.{slug}.{category}.{variant}",
                "family": slug,
                "category": category,
                "variant": variant,
                "source": source_rel.as_posix(),
                "runtime": runtime_rel.as_posix(),
                "sourceDimensions": list(CANVAS),
                "runtimeDimensions": list(RUNTIME),
                "transparentCanvas": True,
                "opaqueBoundsSource": list(bounds) if bounds else None,
                "pivotSourcePx": list(CLOCK_PIVOT) if category == "arms" else None,
                "pivotNormalized": [0.5, round(CLOCK_PIVOT[1] / CANVAS[1], 6)] if category == "arms" else None,
                "canonicalDirection": "12-o'clock/up" if category == "arms" else None,
                "sourceBytes": source_path.stat().st_size,
                "runtimeBytes": runtime_path.stat().st_size,
                "sourceSha256": sha256(source_path),
                "provenance": (
                    "Original style-specific redraw generated from independent geometry and mark logic. "
                    "Morphology informed by the supplied watch screenshot; no family is a filter, "
                    "desaturation, or recolor of another family."
                ),
                "notes": f"{cfg['construction']} {cfg['edge']} {cfg['material']}",
            }
            records.append(record)
    return records


def open_asset(slug: str, category: str, variant: str) -> Image.Image:
    return Image.open(ROOT / rel_asset_path(slug, category, variant)).convert("RGBA")


def rotate_hand(image: Image.Image, clockwise_degrees: float) -> Image.Image:
    return image.rotate(-clockwise_degrees, resample=Image.Resampling.BICUBIC, center=CLOCK_PIVOT)


def compose_character(slug: str, hour: int = 10, minute: int = 8, mood: str = "neutral") -> Image.Image:
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(open_asset(slug, "feet", "corrected"))
    out.alpha_composite(open_asset(slug, "body", "armless-base"))
    out.alpha_composite(open_asset(slug, "clothing", "trunks-classic"))
    eyes = "eyes-alert" if mood in ("happy", "surprised") else "eyes-sleepy"
    out.alpha_composite(open_asset(slug, "eyes-lids-brows", eyes))
    out.alpha_composite(open_asset(slug, "mouths", mood))
    hour_angle = (hour % 12) * 30 + minute * 0.5
    minute_angle = minute * 6
    out.alpha_composite(rotate_hand(open_asset(slug, "arms", "hour"), hour_angle))
    out.alpha_composite(rotate_hand(open_asset(slug, "arms", "minute"), minute_angle))
    return out


def checkerboard(size: tuple[int, int], cell: int = 30) -> Image.Image:
    image = Image.new("RGB", size, (229, 232, 234))
    d = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(198, 203, 207))
    return image.convert("RGBA")


def fit_paste(base: Image.Image, item: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    item.thumbnail((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    x = x0 + (x1 - x0 - item.width) // 2
    y = y0 + (y1 - y0 - item.height) // 2
    base.alpha_composite(item, (x, y))


def add_wrapped(draw: ImageDraw.ImageDraw, text: str, xy: tuple[int, int], width: int, face: ImageFont.FreeTypeFont, fill, leading: int = 8) -> int:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textbbox((0, 0), trial, font=face)[2] <= width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    x, y = xy
    line_h = face.size + leading
    for line in lines:
        draw.text((x, y), line, font=face, fill=fill)
        y += line_h
    return y


def family_contact_sheet() -> None:
    sheet = Image.new("RGBA", (2500, 1780), (20, 24, 29, 255))
    d = ImageDraw.Draw(sheet)
    d.text((90, 58), "PATRICK WATCH — SIX INDEPENDENT REDRAW FAMILIES", font=font(54, True), fill=(246, 240, 224))
    d.text((92, 126), "Common 1024 px transparent rig • canonical hands point to 12 • preview time 10:08", font=font(25), fill=(157, 170, 179))
    slugs = list(FAMILIES)
    for index, slug in enumerate(slugs):
        col, row = index % 3, index // 3
        x, y = 80 + col * 810, 205 + row * 765
        d.rounded_rectangle((x, y, x + 760, y + 700), radius=38, fill=(31, 37, 44), outline=(77, 88, 98), width=2)
        preview = compose_character(slug)
        fit_paste(sheet, preview, (x + 18, y + 45, x + 480, y + 535))
        d.text((x + 38, y + 28), FAMILIES[slug]["short"], font=font(25, True), fill=(236, 204, 91))
        d.text((x + 485, y + 86), FAMILIES[slug]["name"], font=font(28, True), fill=(246, 240, 224))
        yy = add_wrapped(d, FAMILIES[slug]["construction"], (x + 485, y + 145), 240, font(18), (185, 195, 201), 6)
        yy = add_wrapped(d, FAMILIES[slug]["edge"], (x + 485, yy + 12), 240, font(17), (145, 160, 169), 5)
        d.text((x + 38, y + 548), "SOURCE LOGIC", font=font(16, True), fill=(117, 203, 190))
        add_wrapped(d, FAMILIES[slug]["material"], (x + 38, y + 578), 675, font(18), (204, 211, 215), 5)
        palette = ["skin", "line", "cloth", "accent"]
        for pi, key in enumerate(palette):
            d.ellipse((x + 520 + pi * 46, y + 492, x + 550 + pi * 46, y + 522), fill=FAMILIES[slug][key])
    sheet.convert("RGB").save(ROOT / "previews" / "contact-sheet-families.png", quality=95)


def components_contact_sheet() -> None:
    sheet = checkerboard((2500, 1900), 32)
    shade = Image.new("RGBA", sheet.size, (17, 22, 27, 214))
    sheet.alpha_composite(shade)
    d = ImageDraw.Draw(sheet)
    d.text((88, 55), "MODULAR ASSET INVENTORY", font=font(56, True), fill=(248, 242, 226))
    d.text((90, 124), "Every part is a full transparent canvas. Arms share the same clock pivot.", font=font(25), fill=(176, 188, 194))
    categories = [
        ("body", "armless-base", "ARMLESS BODY"),
        ("arms", "hour", "HOUR ARM"),
        ("arms", "minute", "MINUTE ARM"),
        ("feet", "corrected", "CORRECTED FEET"),
        ("eyes-lids-brows", "eyes-sleepy", "EYES / LIDS"),
        ("mouths", "happy", "MOUTHS"),
        ("clothing", "trunks-classic", "CLOTHING"),
        ("accessories", "nightcap", "HATS / ACCESSORIES"),
        ("overlays", "charging", "STATE OVERLAYS"),
    ]
    for i, (category, variant, label) in enumerate(categories):
        col, row = i % 5, i // 5
        x, y = 80 + col * 480, 215 + row * 580
        d.rounded_rectangle((x, y, x + 430, y + 520), radius=28, fill=(244, 239, 224, 238), outline=(112, 120, 123, 255), width=2)
        asset = open_asset("cel-1999", category, variant)
        fit_paste(sheet, asset, (x + 15, y + 46, x + 415, y + 420))
        d.text((x + 28, y + 20), label, font=font(20, True), fill=(38, 42, 45))
        d.text((x + 28, y + 448), f"{category}/{variant}", font=font(16, mono=True), fill=(69, 76, 80))
        d.text((x + 28, y + 477), "1024² source → 256² runtime", font=font(15), fill=(105, 111, 114))
    y = 1425
    d.rounded_rectangle((80, y, 2420, 1810), radius=30, fill=(27, 33, 39, 245), outline=(96, 111, 120), width=2)
    d.text((120, y + 35), "VARIANTS INCLUDED IN EACH FAMILY", font=font(28, True), fill=(236, 204, 91))
    labels = [
        "body: armless-base", "arms: hour, minute", "feet: corrected",
        "eyes: sleepy, alert", "lids: half", "brows: annoyed",
        "mouths: neutral, happy, surprised", "clothing: trunks, sleep robe",
        "accessories: nightcap, party hat", "overlays: sleep, charging, low battery, happy, surprised",
    ]
    for i, label in enumerate(labels):
        col, row = i % 2, i // 2
        d.text((125 + col * 1110, y + 95 + row * 48), "• " + label, font=font(21), fill=(207, 216, 220))
    sheet.convert("RGB").save(ROOT / "previews" / "contact-sheet-components.png", quality=95)


def make_watch_sample(slug: str, size: tuple[int, int] = (900, 1080)) -> Image.Image:
    image = Image.new("RGB", size, (232, 229, 220))
    d = ImageDraw.Draw(image)
    case = (110, 50, size[0] - 110, size[1] - 80)
    d.rounded_rectangle(case, radius=145, fill=(18, 19, 21), outline=(62, 65, 68), width=10)
    d.rounded_rectangle((132, 72, size[0] - 132, size[1] - 102), radius=125, fill=(1, 3, 4))
    cx, cy = size[0] // 2, (72 + size[1] - 102) // 2
    radius = min(size) * 0.335
    for minute in range(60):
        angle = math.radians(minute * 6 - 90)
        inner = radius - (20 if minute % 5 == 0 else 11)
        outer = radius
        color = (86, 94, 98) if minute % 5 == 0 else (43, 49, 52)
        width = 4 if minute % 5 == 0 else 2
        d.line((cx + math.cos(angle) * inner, cy + math.sin(angle) * inner, cx + math.cos(angle) * outer, cy + math.sin(angle) * outer), fill=color, width=width)
    character = compose_character(slug)
    fit_paste(image.convert("RGBA"), character, (185, 155, size[0] - 185, size[1] - 185))
    # Re-compose on a retained RGBA instance.
    rgba = image.convert("RGBA")
    fit_paste(rgba, character, (185, 155, size[0] - 185, size[1] - 185))
    d = ImageDraw.Draw(rgba)
    d.text((cx, 107), "10:08", font=font(34, True, True), fill=(188, 198, 202), anchor="mm")
    d.text((cx, size[1] - 133), FAMILIES[slug]["short"], font=font(18, True), fill=(105, 119, 125), anchor="mm")
    d.ellipse((case[2] + 8, 340, case[2] + 27, 435), fill=(54, 56, 59), outline=(87, 89, 92), width=2)
    return rgba


def watch_samples() -> None:
    board = Image.new("RGB", (2500, 1800), (220, 218, 211))
    d = ImageDraw.Draw(board)
    d.text((88, 55), "BLACK-OLED APPLE WATCH STUDIES", font=font(54, True), fill=(30, 33, 35))
    d.text((90, 122), "Subtle edge ticks • digital time • live modular hour/minute arms at 10:08", font=font(25), fill=(84, 91, 94))
    for i, slug in enumerate(FAMILIES):
        sample = make_watch_sample(slug, (720, 760))
        x, y = 70 + (i % 3) * 810, 200 + (i // 3) * 770
        board.paste(sample.convert("RGB"), (x, y))
        sample.convert("RGB").save(ROOT / "previews" / f"watch-sample-{slug}.png", quality=95)
    board.save(ROOT / "previews" / "apple-watch-samples.png", quality=95)


def rig_sheet() -> None:
    sheet = checkerboard((2200, 1400), 36)
    veil = Image.new("RGBA", sheet.size, (18, 22, 26, 220))
    sheet.alpha_composite(veil)
    d = ImageDraw.Draw(sheet)
    d.text((78, 54), "COMMON TRANSPARENT-CANVAS RIG", font=font(52, True), fill=(247, 241, 226))
    d.text((82, 120), "Source canvas 1024 × 1024 px • runtime canvas 256 × 256 px", font=font(25), fill=(175, 188, 194))
    comp = compose_character("cel-1999")
    fit_paste(sheet, comp, (100, 180, 1120, 1250))
    sx, sy = 100, 180
    # The fitted composition is 1020 square, so points map one-to-one with a tiny offset.
    pivot = (sx + CLOCK_PIVOT[0], sy + CLOCK_PIVOT[1])
    d.ellipse((pivot[0] - 18, pivot[1] - 18, pivot[0] + 18, pivot[1] + 18), fill=(255, 215, 77), outline=(23, 24, 25), width=4)
    d.line((pivot[0] - 100, pivot[1], pivot[0] + 100, pivot[1]), fill=(255, 215, 77), width=3)
    d.line((pivot[0], pivot[1] - 100, pivot[0], pivot[1] + 100), fill=(255, 215, 77), width=3)
    d.text((pivot[0] + 26, pivot[1] + 16), "clockPivot  [512, 500]", font=font(23, True), fill=(255, 224, 101))
    panel = (1190, 190, 2110, 1260)
    d.rounded_rectangle(panel, radius=36, fill=(244, 239, 224, 245), outline=(104, 117, 124), width=3)
    d.text((1240, 235), "ANCHOR CONTRACT", font=font(31, True), fill=(35, 39, 42))
    anchors = [
        ("Clock pivot", "[512, 500]", "Both rotating hands"),
        ("Hour socket", "[484, 500]", "Anatomical shoulder cue"),
        ("Minute socket", "[540, 500]", "Anatomical shoulder cue"),
        ("Face group", "[512, 326]", "Eyes / lids / brows"),
        ("Mouth group", "[512, 395]", "Expression swap"),
        ("Clothing", "[512, 662]", "Waist registration"),
        ("Feet L / R", "[404, 810] / [620, 810]", "Corrected stance"),
        ("Accessory", "[512, 126]", "Hat registration"),
    ]
    yy = 310
    for name, coord, note in anchors:
        d.text((1240, yy), name, font=font(21, True), fill=(44, 49, 52))
        d.text((1510, yy), coord, font=font(20, mono=True), fill=(133, 58, 52))
        d.text((1240, yy + 30), note, font=font(17), fill=(98, 106, 110))
        yy += 88
    d.line((1240, yy + 4, 2040, yy + 4), fill=(176, 173, 162), width=2)
    add_wrapped(d, "Rotation: canonical hand points to 12. Render clockwise by minute × 6° and (hour mod 12) × 30° + minute × 0.5°. Keep a full-canvas bitmap so rotation never changes the registration origin.", (1240, yy + 34), 800, font(20), (55, 62, 66), 7)
    sheet.convert("RGB").save(ROOT / "previews" / "rig-specification.png", quality=95)


def transparency_sheet() -> None:
    sheet = checkerboard((2500, 1530), 30)
    d = ImageDraw.Draw(sheet)
    d.rectangle((0, 0, 2500, 150), fill=(18, 23, 27, 235))
    d.text((70, 45), "TRANSPARENCY + REGISTRATION PROOF", font=font(48, True), fill=(245, 240, 226))
    for i, slug in enumerate(FAMILIES):
        x, y = 55 + i * 405, 190
        d.rounded_rectangle((x, y, x + 365, 1265), radius=24, fill=(255, 255, 255, 82), outline=(70, 76, 79, 170), width=2)
        d.text((x + 22, y + 18), FAMILIES[slug]["short"], font=font(20, True), fill=(29, 33, 35))
        body = open_asset(slug, "body", "armless-base")
        hour = open_asset(slug, "arms", "hour")
        minute = open_asset(slug, "arms", "minute")
        fit_paste(sheet, body, (x + 6, y + 60, x + 359, y + 510))
        fit_paste(sheet, hour, (x + 6, y + 520, x + 359, y + 850))
        fit_paste(sheet, minute, (x + 6, y + 850, x + 359, y + 1190))
        d.text((x + 18, y + 1218), "body / hour / minute", font=font(16, mono=True), fill=(52, 58, 61))
    d.rounded_rectangle((65, 1320, 2435, 1465), radius=24, fill=(20, 25, 29, 235))
    d.text((105, 1350), "PASS", font=font(28, True), fill=(102, 214, 151))
    d.text((225, 1352), "All source assets are RGBA, corner alpha = 0, and share the same 1024 × 1024 registration canvas.", font=font(23), fill=(220, 228, 230))
    sheet.convert("RGB").save(ROOT / "previews" / "transparency-proof.png", quality=95)


def library_board() -> None:
    board = Image.new("RGB", (2800, 2000), (237, 232, 219))
    d = ImageDraw.Draw(board)
    d.rectangle((0, 0, 2800, 190), fill=(22, 27, 31))
    d.text((90, 50), "PATRICK APPLE WATCH — MODULAR STYLE LIBRARY", font=font(58, True), fill=(248, 241, 220))
    d.text((94, 127), "Independent redraw system • early Season-1 pear morphology • production-safe pivots", font=font(26), fill=(167, 182, 188))
    chips = [("6", "style families"), ("120", "source assets"), ("120", "watchOS PNGs"), ("1024²", "master canvas"), ("256²", "runtime tier")]
    for i, (big, small) in enumerate(chips):
        x = 90 + i * 520
        d.rounded_rectangle((x, 225, x + 470, 345), radius=24, fill=(252, 248, 236), outline=(177, 170, 151), width=2)
        d.text((x + 30, 248), big, font=font(39, True), fill=(172, 66, 58))
        d.text((x + 150, 264), small, font=font(20), fill=(64, 70, 73))
    for i, slug in enumerate(FAMILIES):
        x, y = 80 + i * 450, 405
        d.rounded_rectangle((x, y, x + 410, y + 650), radius=26, fill=(250, 246, 234), outline=(161, 156, 144), width=2)
        d.text((x + 24, y + 20), FAMILIES[slug]["short"], font=font(20, True), fill=(53, 57, 60))
        fit_paste(board.convert("RGBA"), compose_character(slug), (x + 5, y + 55, x + 405, y + 475))
        # Paste again on retained RGB board.
        preview = compose_character(slug)
        preview.thumbnail((395, 410), Image.Resampling.LANCZOS)
        tmp = Image.new("RGBA", board.size, (0, 0, 0, 0))
        tmp.alpha_composite(preview, (x + (410 - preview.width) // 2, y + 55))
        board.paste(tmp.convert("RGB"), (0, 0), tmp.getchannel("A"))
        d = ImageDraw.Draw(board)
        d.text((x + 25, y + 485), FAMILIES[slug]["name"], font=font(20, True), fill=(45, 49, 52))
        add_wrapped(d, FAMILIES[slug]["edge"], (x + 25, y + 525), 355, font(16), (91, 97, 100), 5)
    exists = (80, 1120, 1710, 1900)
    remains = (1770, 1120, 2720, 1900)
    d.rounded_rectangle(exists, radius=32, fill=(27, 34, 39), outline=(93, 108, 116), width=2)
    d.rounded_rectangle(remains, radius=32, fill=(252, 248, 236), outline=(177, 170, 151), width=2)
    d.text((125, 1160), "WHAT EXISTS NOW", font=font(34, True), fill=(244, 210, 99))
    delivered = [
        "6 genuinely rebuilt visual families; no filter-derived variants",
        "Armless body + separate co-axial hour and minute arms in every family",
        "Corrected feet, sleepy/alert eyes, lids, brows, and 3 mouth expressions",
        "Classic trunks, sleep robe, nightcap, party hat",
        "Sleep, charging, low-battery, happy, and surprised overlays",
        "1024 px masters + optimized 256 px watchOS tier + SHA-256 manifest",
        "Family sheet, component sheet, rig diagram, transparency proof, OLED watches",
    ]
    yy = 1225
    for text in delivered:
        d.ellipse((126, yy + 8, 140, yy + 22), fill=(89, 199, 151))
        yy = add_wrapped(d, text, (158, yy), 1470, font(21), (220, 227, 229), 7) + 18
    d.text((1815, 1160), "REMAINS FOR PRODUCTION", font=font(30, True), fill=(151, 62, 55))
    remaining = [
        "Reconcile silhouette against the separate clean Season-1 master when it lands.",
        "Hand-tune shoulder occlusion masks for final watch hand angles.",
        "Run device tests for OLED black crush, Always-On dim state, and gamut.",
        "Select a shipping subset; keep all 1024 px masters outside the app bundle.",
        "Complete trademark / licensing review before distribution.",
    ]
    yy = 1230
    for text in remaining:
        d.rectangle((1817, yy + 8, 1831, yy + 22), fill=(201, 109, 76))
        yy = add_wrapped(d, text, (1852, yy), 780, font(21), (62, 68, 71), 7) + 24
    d.line((1815, yy + 8, 2645, yy + 8), fill=(196, 190, 174), width=2)
    d.text((1815, yy + 40), "RIG GUARANTEE", font=font(23, True), fill=(53, 58, 61))
    add_wrapped(d, "Every source file is full-canvas RGBA. Both hand assets rotate around [512, 500], so family swaps do not shift time.", (1815, yy + 82), 780, font(20), (87, 94, 97), 7)
    board.save(ROOT / "previews" / "style-library-board.png", quality=95)


def write_specs(records: list[dict]) -> None:
    rig = {
        "schemaVersion": "1.0.0",
        "coordinateSystem": {"origin": "top-left", "x": "right", "y": "down", "units": "pixels"},
        "sourceCanvas": {"width": 1024, "height": 1024, "format": "RGBA PNG", "background": "transparent"},
        "runtimeCanvas": {"width": 256, "height": 256, "scaleFromSource": 0.25},
        "clockPivot": {"sourcePx": [512, 500], "runtimePx": [128, 125], "normalized": [0.5, 0.48828125]},
        "canonicalHandDirection": "12-o'clock/up",
        "rotationFormulaClockwiseDegrees": {"minute": "minute * 6", "hour": "(hour % 12) * 30 + minute * 0.5"},
        "anchors": {
            "hourShoulderSocket": {"sourcePx": [484, 500], "normalized": [0.47265625, 0.48828125]},
            "minuteShoulderSocket": {"sourcePx": [540, 500], "normalized": [0.52734375, 0.48828125]},
            "faceGroup": {"sourcePx": [512, 326]},
            "mouthGroup": {"sourcePx": [512, 395]},
            "clothingWaist": {"sourcePx": [512, 662]},
            "leftFoot": {"sourcePx": [404, 810]},
            "rightFoot": {"sourcePx": [620, 810]},
            "headAccessory": {"sourcePx": [512, 126]},
        },
        "compositeOrderBackToFront": ["feet", "body", "clothing", "eyes-lids-brows", "mouths", "arms", "accessories", "overlays"],
        "morphologyBaseline": [
            "Large bottom-heavy pear body",
            "Long tapering head, never oversized baby head",
            "Small, low-energy sleepy face",
            "Uneven early hand-ink asymmetry",
            "Long triangular arms and compact corrected feet",
            "Explicitly non-cute proportions",
        ],
    }
    (ROOT / "spec" / "rig-spec.json").write_text(json.dumps(rig, indent=2, ensure_ascii=False), encoding="utf-8")
    reference_rel = None
    if REFERENCE.exists():
        copied = ROOT / "reference" / "user-watch-reference.png"
        shutil.copy2(REFERENCE, copied)
        reference_rel = copied.relative_to(ROOT).as_posix()
    manifest = {
        "schemaVersion": "1.0.0",
        "library": "Patrick Apple Watch Modular Style Library",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "rootContract": "All generated work is contained below this manifest's directory.",
        "reference": {
            "suppliedPath": str(REFERENCE),
            "localCopy": reference_rel,
            "usage": "Morphology/context reference only; generated assets are independent redraws.",
        },
        "rigSpec": "spec/rig-spec.json",
        "optimization": {
            "sourceTier": "1024×1024 RGBA PNG for review, re-export, and future vector/paint replacement",
            "runtimeTier": "256×256 optimized RGBA PNG, 25% linear dimensions",
            "shippingGuidance": "Ship only selected family/state combinations; keep assets-src and previews outside the watch app bundle.",
            "recommendedFuture": "Use indexed PNG where alpha permits; validate ASTC/asset-catalog output on device.",
        },
        "families": [{"id": slug, **cfg} for slug, cfg in FAMILIES.items()],
        "counts": {
            "families": len(FAMILIES),
            "assetsPerFamily": len(ASSET_SPECS),
            "sourceAssets": len(records),
            "runtimeAssets": len(records),
            "previewImages": 6 + len(FAMILIES),
        },
        "assets": records,
        "previews": [
            "previews/contact-sheet-families.png",
            "previews/contact-sheet-components.png",
            "previews/apple-watch-samples.png",
            "previews/rig-specification.png",
            "previews/transparency-proof.png",
            "previews/style-library-board.png",
        ] + [f"previews/watch-sample-{slug}.png" for slug in FAMILIES],
        "provenanceNote": (
            "Every family is drawn from common rig constraints but has independent silhouette coordinates, "
            "mark construction, edge behavior, texture generation, and material treatment. No family is "
            "produced by recoloring, desaturating, or filtering a shared final raster."
        ),
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


def write_readme() -> None:
    text = """# Patrick Apple Watch Modular Style Library

This directory is a self-contained, independently generated asset system. It does not modify the parallel clean Season-1 master workstream.

## Core contract

- Every component is a transparent, full-registration canvas.
- Source masters: `1024 × 1024` RGBA PNG.
- watchOS tier: `256 × 256` optimized RGBA PNG.
- Both arm assets point to 12 o'clock and rotate around source pixel `[512, 500]`.
- Rotation: `minute × 6°`; `(hour mod 12) × 30° + minute × 0.5°`.
- Composite order: feet → body → clothing → face → arms → accessories → overlays.

## Structure

- `assets-src/` — high-quality source PNG masters.
- `assets-watchos/` — size-conscious runtime PNGs.
- `spec/rig-spec.json` — canvas, pivots, anchors, layer order, and morphology contract.
- `manifest.json` — every file, bounds, dimensions, byte size, SHA-256, provenance, and style notes.
- `previews/` — contact sheets, watch mockups, rig board, transparency proof, and library status board.
- `generate_library.py` — deterministic procedural redraw source.

## Production note

The library is ready for visual selection and integration prototyping. Before shipping, reconcile the chosen family against the separate clean Season-1 master, tune shoulder occlusion, test OLED/Always-On behavior on device, and complete rights review.
"""
    (ROOT / "README.md").write_text(text, encoding="utf-8")


def validate(records: list[dict]) -> dict:
    errors: list[str] = []
    pivot_checks = 0
    source_total = 0
    runtime_total = 0
    for record in records:
        for key in ("source", "runtime"):
            path = ROOT / record[key]
            if not path.exists():
                errors.append(f"missing: {record[key]}")
                continue
            if key == "source":
                source_total += path.stat().st_size
            else:
                runtime_total += path.stat().st_size
            with Image.open(path) as im:
                expected = CANVAS if key == "source" else RUNTIME
                if im.size != expected:
                    errors.append(f"wrong size: {record[key]} -> {im.size}")
                if im.mode != "RGBA":
                    errors.append(f"wrong mode: {record[key]} -> {im.mode}")
                if im.getpixel((0, 0))[3] != 0:
                    errors.append(f"nontransparent corner: {record[key]}")
                if im.getbbox() is None:
                    errors.append(f"empty asset: {record[key]}")
                if record["category"] == "arms":
                    pivot = CLOCK_PIVOT if key == "source" else (128, 125)
                    if im.getpixel(pivot)[3] == 0:
                        errors.append(f"transparent arm pivot: {record[key]}")
                    else:
                        pivot_checks += 1
    key_hashes = [
        record["sourceSha256"]
        for record in records
        if record["category"] in {"body", "arms"}
    ]
    if len(set(key_hashes)) != len(key_hashes):
        errors.append("body/hour/minute masters are not unique across redraw families")
    covered = sorted({record["category"] for record in records})
    expected_categories = sorted({category for category, _ in ASSET_SPECS})
    if covered != expected_categories:
        errors.append(f"category coverage mismatch: {covered}")
    report = {
        "passed": not errors,
        "checkedFiles": len(records) * 2,
        "expectedSourceAssets": len(FAMILIES) * len(ASSET_SPECS),
        "categoryCoverage": covered,
        "distinctKeyRedraws": len(set(key_hashes)),
        "expectedDistinctKeyRedraws": len(FAMILIES) * 3,
        "opaqueArmPivotChecks": pivot_checks,
        "expectedArmPivotChecks": len(FAMILIES) * 2 * 2,
        "sourceTierBytes": source_total,
        "runtimeTierBytes": runtime_total,
        "runtimeReductionPercent": round((1 - runtime_total / source_total) * 100, 2),
        "errors": errors,
    }
    (ROOT / "validation-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main() -> None:
    ensure_dirs()
    records = build_assets()
    write_specs(records)
    write_readme()
    family_contact_sheet()
    components_contact_sheet()
    watch_samples()
    rig_sheet()
    transparency_sheet()
    library_board()
    report = validate(records)
    print(json.dumps({
        "root": str(ROOT),
        "source_assets": len(records),
        "runtime_assets": len(records),
        "validation": report,
        "previews": 6 + len(FAMILIES),
    }, indent=2))


if __name__ == "__main__":
    main()
