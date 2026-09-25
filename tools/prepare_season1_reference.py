"""Crop Patrick from the authenticated 2000 main-character model sheet."""

from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps


ROOT = Path(r"<PROJECT_DIR>")
SOURCE = ROOT / "references" / "season1" / "main-characters-model-sheet.gif"
OUTPUT = ROOT / "references" / "season1" / "patrick-model-sheet-crop.png"

sheet = Image.open(SOURCE).convert("RGB")

# Patrick is the fifth principal character, between SpongeBob and Squidward.
crop = sheet.crop((198, 42, 264, 176))
crop = ImageOps.expand(crop, border=8, fill="white")
crop = crop.resize((656, 1200), Image.Resampling.LANCZOS)
crop = ImageEnhance.Contrast(crop).enhance(1.18)
crop.save(OUTPUT)

print(f"wrote {OUTPUT} ({crop.width}x{crop.height})")
