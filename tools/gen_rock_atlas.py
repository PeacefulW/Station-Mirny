"""Generate rock_atlas.png — 47-tile blob tileset for mountain auto-tiling.
Layout: 12 columns × 4 rows = 48 cells (47 tiles + 1 empty).
Each tile 64×64px. Smooth clay style with south walls, side walls, corners.

The 47 tiles cover all possible 3×3 neighbor configurations for
"Match Corners and Sides" terrain mode in Godot 4.

Run: python tools/gen_rock_atlas.py
Output: assets/textures/terrain/rock_atlas.png
"""

import os, hashlib
from PIL import Image, ImageDraw, ImageFilter

TILE = 64
COLS = 12
ROWS = 4
OUT = "assets/textures/terrain/rock_atlas.png"

# Colors — earthy purple-brown rock
TOP = (77, 64, 82)
TOP_VAR = (82, 69, 87)
WALL_S = (48, 38, 54)       # South wall (darkest)
WALL_SE = (55, 44, 60)      # Side wall
LIP = (110, 92, 115)        # Bright edge/lip
SHADOW_N = (35, 28, 40)     # North shadow (under overhang above)
GROUND = (0, 0, 0, 0)       # Transparent (ground shows through)


def noise(x: int, y: int, seed: int = 42) -> float:
    h = hashlib.md5(f"{x},{y},{seed}".encode()).hexdigest()
    return int(h[:4], 16) / 65535.0


def lerp_c(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


# 47-tile blob mapping.
# Each entry: bitmask of present neighbors.
# Bits: N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128
# Index in this list = position in atlas (left-to-right, top-to-bottom).
BLOB_47 = [
    # Row 0 (y=0): 12 tiles
    0,    # 0: isolated (no neighbors)
    1,    # 1: N only
    4,    # 2: E only
    5,    # 3: N+E
    7,    # 4: N+NE+E
    16,   # 5: S only
    17,   # 6: N+S
    20,   # 7: E+S
    21,   # 8: N+E+S
    23,   # 9: N+NE+E+S
    28,   # 10: E+SE+S
    29,   # 11: N+E+SE+S
    # Row 1 (y=1)
    31,   # 12: N+NE+E+SE+S
    64,   # 13: W only
    65,   # 14: N+W
    68,   # 15: E+W
    69,   # 16: N+E+W
    71,   # 17: N+NE+E+W
    80,   # 18: S+W
    81,   # 19: N+S+W
    84,   # 20: E+S+W
    85,   # 21: N+E+S+W (cross, no corners)
    87,   # 22: N+NE+E+S+W
    92,   # 23: E+SE+S+W
    # Row 2 (y=2)
    93,   # 24: N+E+SE+S+W
    95,   # 25: N+NE+E+SE+S+W
    112,  # 26: S+SW+W
    113,  # 27: N+S+SW+W
    116,  # 28: E+S+SW+W
    117,  # 29: N+E+S+SW+W
    119,  # 30: N+NE+E+S+SW+W
    124,  # 31: E+SE+S+SW+W
    125,  # 32: N+E+SE+S+SW+W
    127,  # 33: N+NE+E+SE+S+SW+W
    192,  # 34: W+NW
    193,  # 35: N+W+NW
    # Row 3 (y=3)
    197,  # 36: N+E+W+NW
    199,  # 37: N+NE+E+W+NW
    208,  # 38: S+W+NW
    209,  # 39: N+S+W+NW
    212,  # 40: E+S+W+NW
    213,  # 41: N+E+S+W+NW
    215,  # 42: N+NE+E+S+W+NW
    240,  # 43: S+SW+W+NW
    241,  # 44: N+S+SW+W+NW
    245,  # 45: N+E+S+SW+W+NW
    247,  # 46: N+NE+E+S+SW+W+NW (= 255-SE)
    # Last one to fill 48
    255,  # 47: ALL neighbors (full interior)
]


def has_bit(mask: int, bit: int) -> bool:
    return (mask & bit) != 0


def draw_tile(mask: int) -> Image.Image:
    """Draw a single 64×64 tile based on neighbor bitmask."""
    img = Image.new("RGBA", (TILE, TILE), GROUND)
    px = img.load()

    n = has_bit(mask, 1)
    ne = has_bit(mask, 2)
    e = has_bit(mask, 4)
    se = has_bit(mask, 8)
    s = has_bit(mask, 16)
    sw = has_bit(mask, 32)
    w = has_bit(mask, 64)
    nw = has_bit(mask, 128)

    # Define edge zones
    wall_south = 14   # pixels of south wall
    wall_side = 10    # pixels of side wall
    lip_size = 2      # lip highlight
    shadow_size = 4   # north shadow

    for y in range(TILE):
        for x in range(TILE):
            # Default: transparent (no rock here)
            color = None

            # --- Determine if this pixel is "rock" ---
            # Start with full tile, then cut edges where no neighbor
            is_rock = True

            # Cut south edge if no S neighbor
            if not s and y >= TILE - wall_south:
                is_rock = False
            # Cut north edge if no N neighbor
            if not n and y < shadow_size:
                is_rock = False
            # Cut west edge if no W neighbor
            if not w and x < wall_side:
                is_rock = False
            # Cut east edge if no E neighbor
            if not e and x >= TILE - wall_side:
                is_rock = False

            # Cut corners (internal corners — bigger cut for visibility)
            corner_w = wall_side + 4
            corner_n = shadow_size + 6
            corner_s = wall_south
            if not nw and x < corner_w and y < corner_n:
                is_rock = False
            if not ne and x >= TILE - corner_w and y < corner_n:
                is_rock = False
            if not sw and x < corner_w and y >= TILE - corner_s:
                is_rock = False
            if not se and x >= TILE - corner_w and y >= TILE - corner_s:
                is_rock = False

            if not is_rock:
                # --- Draw wall/edge effects on cut areas ---

                # South wall (visible face) — рисуется на всю ширину
                if not s and y >= TILE - wall_south and y < TILE:
                    depth = (y - (TILE - wall_south)) / wall_south
                    c = lerp_c(WALL_SE, WALL_S, depth)
                    if y == TILE - wall_south:
                        c = LIP
                    elif y == TILE - wall_south + 1:
                        c = lerp_c(LIP, WALL_SE, 0.5)
                    n_val = noise(x, y, 100)
                    offset = int((n_val - 0.5) * 8)
                    color = (max(0, min(255, c[0] + offset)),
                             max(0, min(255, c[1] + offset)),
                             max(0, min(255, c[2] + offset)), 255)

                # West wall
                elif not w and x < wall_side:
                    depth = (wall_side - x) / wall_side
                    c = lerp_c(WALL_SE, WALL_S, depth * 0.7)
                    if x == wall_side - 1:
                        c = lerp_c(c, LIP, 0.4)
                    n_val = noise(x, y, 200)
                    offset = int((n_val - 0.5) * 6)
                    color = (max(0, min(255, c[0] + offset)),
                             max(0, min(255, c[1] + offset)),
                             max(0, min(255, c[2] + offset)), 255)

                # East wall
                elif not e and x >= TILE - wall_side:
                    depth = (x - (TILE - wall_side)) / wall_side
                    c = lerp_c(WALL_SE, WALL_S, depth * 0.7)
                    if x == TILE - wall_side:
                        c = lerp_c(c, LIP, 0.4)
                    n_val = noise(x, y, 300)
                    offset = int((n_val - 0.5) * 6)
                    color = (max(0, min(255, c[0] + offset)),
                             max(0, min(255, c[1] + offset)),
                             max(0, min(255, c[2] + offset)), 255)
            else:
                # --- Top surface ---
                n_val = noise(x, y, 400)
                c = lerp_c(TOP, TOP_VAR, n_val)

                # North shadow (if no N neighbor, shadow on top edge of rock)
                if not n and y < shadow_size + 3:
                    shadow_t = 1.0 - (y - shadow_size) / 3.0 if y >= shadow_size else 1.0
                    c = lerp_c(c, SHADOW_N, shadow_t * 0.6)

                color = (*c, 255)

            if color:
                px[x, y] = color

    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    atlas_w = COLS * TILE
    atlas_h = ROWS * TILE
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    for i, mask in enumerate(BLOB_47):
        col = i % COLS
        row = i // COLS
        tile = draw_tile(mask)
        # Light blur for smoothness
        tile = tile.filter(ImageFilter.GaussianBlur(radius=0.3))
        atlas.paste(tile, (col * TILE, row * TILE))

    atlas.save(OUT)
    print(f"OK: {OUT} ({atlas_w}x{atlas_h}, {len(BLOB_47)} tiles)")

    # Print mapping for reference when setting up terrain in Godot Editor
    print("\n--- Blob47 atlas mapping (index → bitmask → atlas_coords) ---")
    for i, mask in enumerate(BLOB_47):
        col = i % COLS
        row = i // COLS
        print(f"  [{i:2d}] mask={mask:3d} (0b{mask:08b}) → atlas({col},{row})")


if __name__ == "__main__":
    main()
