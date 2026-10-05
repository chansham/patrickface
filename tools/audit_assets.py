"""Inventory media without changing it; optionally render review contact sheets.

The audit separates file integrity from aesthetic approval. It never calls an
art generator, deletes media, or promotes a candidate to user-approved status.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
RASTER = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MEDIA = RASTER | {".svg", ".wav", ".m4a", ".mp4"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def category(rel: str) -> str:
    if rel.startswith("concepts/"):
        return "new-scene-concept"
    if rel.startswith(("references/", "style-library/reference/")) or "reference" in Path(rel).name:
        return "reference"
    if rel.startswith("delivery/theme-pack-before-"):
        return "historical-backup"
    if "/.playwright-cli/" in rel:
        return "qa-screenshot"
    if rel.startswith("style-library/assets-"):
        return "style-library-" + Path(rel).parts[3]
    if rel.startswith("style-library/previews/"):
        return "style-preview"
    if rel.startswith("delivery/theme-pack/"):
        return "theme-" + Path(rel).parts[2]
    if rel.startswith("motion-lab/"):
        return "motion-effect"
    if rel.startswith("sources/"):
        return "source-or-superseded-art"
    if rel.startswith("comparison"):
        return "comparison-candidate"
    return "runtime-or-preview"


def inspect(path: Path) -> dict:
    rel = path.relative_to(ROOT).as_posix()
    role = category(rel)
    item = {
        "path": rel, "status": "retained" if role in {"reference", "historical-backup", "qa-screenshot"} else "pending-review",
        "category": role, "reason": "Preserved as evidence/reference." if role in {"reference", "historical-backup", "qa-screenshot"} else "Retained candidate; no current visual approval is implied.",
        "exists": True, "bytes": path.stat().st_size, "sha256": digest(path),
        "technicalStatus": "unchecked", "visualReview": "not-inspected-individually",
    }
    if rel.startswith("style-library/assets-"):
        item["family"] = path.relative_to(ROOT).parts[2]
    try:
        if path.suffix.lower() in RASTER:
            with Image.open(path) as im:
                im.load()
                item.update(format=im.format, width=im.width, height=im.height, mode=im.mode, frames=getattr(im, "n_frames", 1))
                expected = "JPEG" if path.suffix.lower() in {".jpg", ".jpeg"} else path.suffix[1:].upper()
                issues = []
                if im.format != expected:
                    issues.append(f"Extension declares {expected}; content is {im.format}.")
                if "A" in im.getbands():
                    alpha = im.getchannel("A")
                    item["alphaRange"] = list(alpha.getextrema())
                    item["alphaBounds"] = alpha.getbbox()
                    if alpha.getbbox() is None:
                        issues.append("Image is fully transparent/empty.")
                    if role.startswith("style-library-"):
                        tier = 1024 if "/assets-src/" in rel else 256
                        if im.size != (tier, tier) or im.mode != "RGBA":
                            issues.append("Component violates its registered RGBA canvas dimensions.")
                        if alpha.getextrema()[0] != 0:
                            issues.append("Component has no transparent background.")
                        if role == "style-library-arms":
                            pivot = (512, 500) if tier == 1024 else (128, 125)
                            if alpha.getpixel(pivot) == 0:
                                issues.append("Arm pivot is transparent.")
                elif role.startswith("style-library-"):
                    issues.append("Component lacks alpha channel.")
                item["technicalIssues"] = issues
                item["technicalStatus"] = "issue" if issues else "decode-passed"
        elif path.suffix.lower() == ".svg":
            ET.parse(path)
            item["technicalStatus"] = "xml-parse-passed"
        elif path.suffix.lower() in {".wav", ".m4a"}:
            item["technicalStatus"] = "covered-by-theme-validator" if rel.startswith("delivery/theme-pack/") else "not-auditioned"
    except Exception as exc:
        item["technicalStatus"] = "issue"
        item["technicalIssues"] = [str(exc)]
    return item


def sheets(items: list[dict]) -> list[str]:
    out = DOCS / "asset-audit-sheets"
    out.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(r"C:\Windows\Fonts\segoeui.ttf", 13)
    groups = {}
    for item in items:
        rel = item["path"]
        if not item.get("exists") or Path(rel).suffix.lower() not in RASTER:
            continue
        if rel.startswith("style-library/assets-src/"):
            group = "style-" + item["family"]
        elif rel.startswith("delivery/theme-pack/") and "/contact-sheets/" not in rel:
            group = "theme"
        elif rel.startswith("preview/assets/") or rel.startswith("sources/rejected-runtime/"):
            group = "legacy-runtime"
        else:
            continue
        groups.setdefault(group, []).append(item)
    outputs = []
    for name, members in groups.items():
        for page in range(math.ceil(len(members) / 24)):
            chunk = members[page * 24:(page + 1) * 24]
            board = Image.new("RGB", (1200, math.ceil(len(chunk) / 6) * 240 + 40), "#111722")
            draw = ImageDraw.Draw(board)
            draw.text((10, 10), f"{name} / {page + 1} / candidates, not approval", fill="white", font=font)
            for index, item in enumerate(chunk):
                x, y = (index % 6) * 200, 40 + (index // 6) * 240
                for cy in range(0, 190, 10):
                    for cx in range(0, 190, 10):
                        draw.rectangle((x + cx + 5, y + cy, x + cx + 14, y + cy + 9), fill="#cccccc" if (cx + cy) % 20 else "#999999")
                with Image.open(ROOT / item["path"]) as source:
                    im = source.convert("RGBA")
                    if "A" in source.getbands() and source.getchannel("A").getextrema()[0] == 0:
                        bbox = im.getchannel("A").getbbox()
                        if bbox:
                            im = im.crop(bbox)
                    im.thumbnail((180, 180), Image.Resampling.LANCZOS)
                    board.paste(im, (x + (200 - im.width) // 2, y + (190 - im.height) // 2), im)
                name_parts = Path(item["path"]).name
                for line, start in enumerate(range(0, min(len(name_parts), 78), 26)):
                    draw.text((x + 4, y + 192 + line * 14), name_parts[start:start + 26], font=font, fill="white")
            target = out / f"{name}-{page + 1:02d}.jpg"
            board.save(target, quality=90)
            outputs.append(target.relative_to(ROOT).as_posix())
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheets", action="store_true")
    args = parser.parse_args()
    DOCS.mkdir(parents=True, exist_ok=True)
    decisions_path = DOCS / "asset-audit-decisions.json"
    decisions = json.loads(decisions_path.read_text(encoding="utf-8")) if decisions_path.exists() else {"items": []}
    overrides = {item["path"]: item for item in decisions["items"]}
    items = []
    for path in sorted(ROOT.rglob("*")):
        relative_parts = path.relative_to(ROOT).parts
        if not path.is_file() or path.suffix.lower() not in MEDIA or ".git" in path.parts or "docs" in relative_parts or relative_parts[0] in {"output", ".cache", "node_modules"}:
            continue
        if relative_parts[:2] == ("wardrobe", "qa"):
            continue  # Browser verification screenshots are not character assets.
        item = inspect(path)
        item.update(overrides.pop(item["path"], {}))
        items.append(item)
    for item in overrides.values():
        items.append({**item, "exists": (ROOT / item["path"]).exists()})
    result = {"schemaVersion": "1.0", "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
              "scope": "Project-wide media inventory; technical integrity and aesthetic approval are separate.",
              "approvalPolicy": "No automatic user approval. pending-review includes valid but unselected art.",
              "backup": decisions.get("backup"), "summary": dict(Counter(i["status"] for i in items)), "items": items}
    if args.sheets:
        result["contactSheets"] = sheets(items)
    else:
        result["contactSheets"] = [p.relative_to(ROOT).as_posix() for p in sorted((DOCS / "asset-audit-sheets").glob("*.jpg"))]
    target = DOCS / "asset-audit.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"items": len(items), "statuses": result["summary"], "issues": [i["path"] for i in items if i.get("technicalStatus") == "issue"], "report": str(target)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
