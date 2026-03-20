"""Generate resource_atlas.png (60x12px) for 12px tiles.

5 columns (iron, copper, stone, water_source, sporestalk) x 1 row.
Each tile is 12x12px with transparent background.
"""

from PIL import Image

TILE = 12
COLS = 5
OUT = "assets/textures/resource_atlas.png"


def draw_iron(img: Image.Image, ox: int, oy: int) -> None:
    """Brown rock with 1-2 rust-orange pixels."""
    brown = (110, 80, 55, 255)
    dark = (85, 60, 40, 255)
    rust = (180, 100, 40, 255)
    # Rock shape
    for y in range(4, 10):
        for x in range(3, 10):
            if (x - 6) ** 2 + (y - 7) ** 2 <= 10:
                img.putpixel((ox + x, oy + y), brown)
    img.putpixel((ox + 4, oy + 5), dark)
    img.putpixel((ox + 7, oy + 8), dark)
    # Rust veins
    img.putpixel((ox + 5, oy + 6), rust)
    img.putpixel((ox + 6, oy + 7), rust)


def draw_copper(img: Image.Image, ox: int, oy: int) -> None:
    """Rock with 1-2 green-turquoise pixels."""
    gray = (100, 90, 80, 255)
    dark = (75, 65, 55, 255)
    green = (60, 180, 120, 255)
    for y in range(4, 10):
        for x in range(3, 10):
            if (x - 6) ** 2 + (y - 7) ** 2 <= 10:
                img.putpixel((ox + x, oy + y), gray)
    img.putpixel((ox + 5, oy + 5), dark)
    img.putpixel((ox + 7, oy + 7), dark)
    # Green veins
    img.putpixel((ox + 6, oy + 6), green)
    img.putpixel((ox + 7, oy + 5), green)


def draw_stone(img: Image.Image, ox: int, oy: int) -> None:
    """Gray rock with 1 crack."""
    gray = (140, 138, 130, 255)
    dark = (100, 95, 90, 255)
    for y in range(4, 10):
        for x in range(3, 10):
            if (x - 6) ** 2 + (y - 7) ** 2 <= 10:
                img.putpixel((ox + x, oy + y), gray)
    # Crack
    img.putpixel((ox + 5, oy + 5), dark)
    img.putpixel((ox + 6, oy + 6), dark)
    img.putpixel((ox + 7, oy + 7), dark)


def draw_water_source(img: Image.Image, ox: int, oy: int) -> None:
    """Blue drop/puddle."""
    blue = (60, 140, 220, 255)
    light = (100, 180, 240, 255)
    # Puddle shape
    for y in range(5, 10):
        for x in range(4, 9):
            if (x - 6) ** 2 + (y - 7.5) ** 2 <= 6:
                img.putpixel((ox + x, oy + y), blue)
    # Drop top
    img.putpixel((ox + 6, oy + 4), blue)
    img.putpixel((ox + 6, oy + 3), blue)
    # Highlight
    img.putpixel((ox + 5, oy + 5), light)


def draw_sporestalk(img: Image.Image, ox: int, oy: int) -> None:
    """Brown trunk + orange cap."""
    trunk = (100, 70, 45, 255)
    cap = (210, 130, 50, 255)
    cap_light = (230, 160, 70, 255)
    # Trunk
    for y in range(6, 11):
        img.putpixel((ox + 6, oy + y), trunk)
        img.putpixel((ox + 5, oy + y), trunk)
    # Cap
    for x in range(3, 9):
        img.putpixel((ox + x, oy + 4), cap)
        img.putpixel((ox + x, oy + 5), cap)
    for x in range(4, 8):
        img.putpixel((ox + x, oy + 3), cap)
    img.putpixel((ox + 5, oy + 3), cap_light)
    img.putpixel((ox + 6, oy + 4), cap_light)


DRAW_FUNCS = [draw_iron, draw_copper, draw_stone, draw_water_source, draw_sporestalk]


def main() -> None:
    width = COLS * TILE   # 60
    height = TILE         # 12
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    for col, func in enumerate(DRAW_FUNCS):
        func(img, col * TILE, 0)

    img.save(OUT)
    print(f"Saved {OUT} ({width}x{height})")


if __name__ == "__main__":
    main()
