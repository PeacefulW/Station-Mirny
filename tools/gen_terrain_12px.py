"""Generate terrain_atlas.png (60x36px) for 12px tiles.

5 columns (ground, rock, water, sand, grass) x 3 rows (dark, normal, light).
Each tile is 12x12px with hand-placed pixel details.
"""

from PIL import Image, ImageDraw
import random

TILE = 12
COLS = 5  # ground, rock, water, sand, grass
ROWS = 3  # dark, normal, light
OUT = "assets/textures/terrain_atlas.png"

# Base colors (normal variant)
BASE_COLORS = {
    "ground": (120, 90, 60),
    "rock":   (130, 128, 125),
    "water":  (50, 100, 180),
    "sand":   (200, 180, 120),
    "grass":  (70, 140, 55),
}

def clamp(v: int) -> int:
    return max(0, min(255, v))

def shift(color: tuple, delta: int) -> tuple:
    return tuple(clamp(c + delta) for c in color)

def fill_tile(img: Image.Image, ox: int, oy: int, color: tuple) -> None:
    for y in range(TILE):
        for x in range(TILE):
            img.putpixel((ox + x, oy + y), color)

def add_ground_details(img: Image.Image, ox: int, oy: int, base: tuple) -> None:
    """2-3 pebbles + 1 crack."""
    dark = shift(base, -25)
    light = shift(base, 15)
    # Pebbles
    img.putpixel((ox + 3, oy + 4), dark)
    img.putpixel((ox + 4, oy + 4), dark)
    img.putpixel((ox + 8, oy + 7), dark)
    img.putpixel((ox + 9, oy + 7), dark)
    img.putpixel((ox + 5, oy + 9), dark)
    # Crack
    img.putpixel((ox + 2, oy + 6), shift(base, -30))
    img.putpixel((ox + 3, oy + 7), shift(base, -30))
    img.putpixel((ox + 4, oy + 8), shift(base, -30))

def add_rock_details(img: Image.Image, ox: int, oy: int, base: tuple) -> None:
    """1-2 cracks + 1 highlight."""
    dark = shift(base, -30)
    light = shift(base, 25)
    # Cracks
    img.putpixel((ox + 2, oy + 3), dark)
    img.putpixel((ox + 3, oy + 4), dark)
    img.putpixel((ox + 4, oy + 5), dark)
    img.putpixel((ox + 7, oy + 8), dark)
    img.putpixel((ox + 8, oy + 9), dark)
    # Highlight
    img.putpixel((ox + 6, oy + 2), light)
    img.putpixel((ox + 7, oy + 2), light)

def add_water_details(img: Image.Image, ox: int, oy: int, base: tuple) -> None:
    """1-2 wave lines + 1 highlight."""
    light = shift(base, 30)
    dark = shift(base, -20)
    # Wave 1
    for x in range(2, 10):
        y_off = 4 if x % 3 == 0 else 3
        img.putpixel((ox + x, oy + y_off), light)
    # Wave 2
    for x in range(3, 9):
        y_off = 8 if x % 3 == 1 else 7
        img.putpixel((ox + x, oy + y_off), dark)
    # Highlight
    img.putpixel((ox + 5, oy + 2), shift(base, 45))

def add_sand_details(img: Image.Image, ox: int, oy: int, base: tuple) -> None:
    """5-6 grains + 1 wind line."""
    dark = shift(base, -20)
    light = shift(base, 15)
    # Grains
    positions = [(2, 3), (5, 2), (8, 4), (3, 7), (7, 8), (10, 6)]
    for px, py in positions:
        img.putpixel((ox + px, oy + py), dark)
    # Wind line
    for x in range(3, 9):
        img.putpixel((ox + x, oy + 10), light)

def add_grass_details(img: Image.Image, ox: int, oy: int, base: tuple) -> None:
    """4-5 grass blades."""
    dark = shift(base, -20)
    light = shift(base, 20)
    # Blades (vertical strokes)
    blades = [(2, 3), (4, 2), (7, 4), (9, 3), (6, 8)]
    for bx, by in blades:
        img.putpixel((ox + bx, oy + by), light)
        img.putpixel((ox + bx, oy + by + 1), dark)
        img.putpixel((ox + bx, oy + by + 2), dark)

DETAIL_FUNCS = [
    add_ground_details,
    add_rock_details,
    add_water_details,
    add_sand_details,
    add_grass_details,
]

def main() -> None:
    width = COLS * TILE   # 60
    height = ROWS * TILE  # 36
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))

    color_keys = ["ground", "rock", "water", "sand", "grass"]
    brightness_shifts = [-12, 0, 10]  # dark, normal, light

    for col, key in enumerate(color_keys):
        base = BASE_COLORS[key]
        for row, bs in enumerate(brightness_shifts):
            color = shift(base, bs)
            ox = col * TILE
            oy = row * TILE
            fill_tile(img, ox, oy, color)
            DETAIL_FUNCS[col](img, ox, oy, color)

    img.save(OUT)
    print(f"Saved {OUT} ({width}x{height})")

if __name__ == "__main__":
    main()
