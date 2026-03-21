"""Конвертирует cliff PNG: чёрный фон → прозрачный (RGBA).
Запуск: python tools/prepare_cliff_sprites.py
"""
from PIL import Image
import os

INPUT_DIR = "assets/textures/cliffs/raw"
OUTPUT_DIR = "assets/textures/cliffs"
BLACK_THRESHOLD = 15

def convert(filename: str) -> None:
    path = os.path.join(INPUT_DIR, filename)
    if not os.path.exists(path):
        print(f"SKIP: {path} not found")
        return
    img = Image.open(path).convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r < BLACK_THRESHOLD and g < BLACK_THRESHOLD and b < BLACK_THRESHOLD:
                pixels[x, y] = (0, 0, 0, 0)
    out_path = os.path.join(OUTPUT_DIR, filename)
    img.save(out_path)
    print(f"OK: {filename} ({w}x{h})")

FILES = [
    "cliff-sides.png", "cliff-sides-lower.png", "cliff-sides-shadow.png",
    "cliff-outer.png", "cliff-outer-lower.png", "cliff-outer-shadow.png",
    "cliff-inner.png", "cliff-inner-lower.png", "cliff-inner-shadow.png",
    "cliff-entrance.png", "cliff-entrance-lower.png", "cliff-entrance-shadow.png",
]

os.makedirs(OUTPUT_DIR, exist_ok=True)
for f in FILES:
    convert(f)
