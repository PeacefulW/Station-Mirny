"""Generate rock_tiles.png placeholder atlas for mountain TileMapLayer.
Simple colored tiles with edge variations.

Run: python tools/gen_rock_tiles.py
Output: assets/textures/terrain/rock_tiles.png (single 64x64 flat tile for now)
"""

from PIL import Image
import os, hashlib

TILE = 64  # Must match WorldGenBalance.tile_size
OUT = "assets/textures/terrain/rock_tiles.png"

# Colors
TOP = (77, 64, 82)         # Interior top surface
WALL_S = (51, 41, 56)      # South wall (darker)
LIP = (115, 97, 120)       # Lip/edge highlight
SHADOW = (31, 25, 36)      # North shadow


def noise(x: int, y: int, seed: int = 42) -> float:
    h = hashlib.md5(f"{x},{y},{seed}".encode()).hexdigest()
    return int(h[:4], 16) / 65535.0


def make_flat_tile() -> Image.Image:
    """Interior flat top — slab of rock viewed from above."""
    img = Image.new("RGBA", (TILE, TILE), (*TOP, 255))
    px = img.load()
    # Add subtle noise for texture
    for y in range(TILE):
        for x in range(TILE):
            n = noise(x, y, 100)
            r, g, b = TOP
            offset = int((n - 0.5) * 12)
            px[x, y] = (
                max(0, min(255, r + offset)),
                max(0, min(255, g + offset)),
                max(0, min(255, b + offset)),
                255
            )
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    # For now: single flat tile. Better Terrain auto-tiling will select
    # the same tile for all configs. Edges will be added later with a
    # proper 47-tile blob set.
    tile = make_flat_tile()
    tile.save(OUT)
    print(f"OK: {OUT} ({tile.size[0]}x{tile.size[1]})")


if __name__ == "__main__":
    main()
