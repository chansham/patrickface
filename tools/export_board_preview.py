from pathlib import Path

from PIL import Image


SOURCE = Path(
    r"<USER_HOME>\AppData\Local\Temp\cursor\screenshots\patrick-style-board-v2.png"
)
OUTPUT = Path(r"<PROJECT_DIR>\comparison\style-board.png")

image = Image.open(SOURCE).convert("RGB")
scale = min(1024 / image.width, 1024 / image.height, 1)
size = (round(image.width * scale), round(image.height * scale))
image.resize(size, Image.Resampling.LANCZOS).save(OUTPUT, optimize=True)
print(f"{OUTPUT}: {size[0]}x{size[1]}")
