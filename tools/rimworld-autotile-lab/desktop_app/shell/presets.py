from __future__ import annotations

import random
from copy import deepcopy

PRESETS = {
    "mountain": {
        "tile_size": 128,
        "south_height": 64,
        "north_height": 0,
        "side_height": 0,
        "roughness": 10.0,
        "face_power": 2.5,
        "back_drop": 0.8,
        "crown_bevel": 10,
        "outer_corner_radius": 40,
        "inner_corner_radius": 40,
        "corner_round_px": 32,
        "diagonal_smooth_px": 64,
        "contour_relax": 1.0,
        "contour_warp_px": 1.5,
        "corner_variation": 0.55,
        "rim_width": 16,
        "mountain_outline_enabled": True,
        "mountain_outline_width": 6,
        "edge_debris": 0.8,
        "edge_color_strength": 0.35,
        "geometry_variance": 0.75,
        "shape_supersampling": 4,
        "normal_strength": 8.0,
        "normal_detail_strength": 4.0,
        "top_world_scale_px": 224.0,
        "face_world_scale_px": 112.0,
        "macro_world_scale_px": 448.0,
        "variants": 6,
        "texture_scale": 1.0,
        "bake_height_shading": False,
        "light_angle_deg": 234.0,
        "preview_mode": "lit",
        "textures": {
            "top": "",
            "face": "",
            "base": "",
        },
        "colors": {
            "top": "#705940",
            "face": "#3e2f25",
            "edge": "#49382c",
            "back": "#564436",
            "base": "#b88d58",
        },
    },
    "wall": {
        "tile_size": 128,
        "south_height": 20,
        "north_height": 12,
        "side_height": 16,
        "roughness": 14.0,
        "face_power": 1.34,
        "back_drop": 0.24,
        "crown_bevel": 1,
        "outer_corner_radius": 12,
        "inner_corner_radius": 8,
        "corner_round_px": 16,
        "diagonal_smooth_px": 6,
        "contour_relax": 0.35,
        "contour_warp_px": 2.5,
        "corner_variation": 0.16,
        "rim_width": 8,
        "mountain_outline_enabled": False,
        "mountain_outline_width": 4,
        "edge_debris": 0.25,
        "edge_color_strength": 0.35,
        "geometry_variance": 0.15,
        "shape_supersampling": 4,
        "normal_detail_strength": 0.8,
        "top_world_scale_px": 224.0,
        "face_world_scale_px": 112.0,
        "macro_world_scale_px": 448.0,
        "variants": 3,
        "texture_scale": 1.0,
        "colors": {
            "top": "#765439",
            "face": "#473328",
            "edge": "#5c3f2d",
            "back": "#5e4636",
            "base": "#bb9361",
        },
    },
    "earth": {
        "tile_size": 128,
        "south_height": 16,
        "north_height": 10,
        "side_height": 14,
        "roughness": 26.0,
        "face_power": 0.82,
        "back_drop": 0.28,
        "crown_bevel": 2,
        "outer_corner_radius": 16,
        "inner_corner_radius": 12,
        "corner_round_px": 20,
        "diagonal_smooth_px": 8,
        "contour_relax": 0.55,
        "contour_warp_px": 3.0,
        "corner_variation": 0.25,
        "rim_width": 10,
        "mountain_outline_enabled": False,
        "mountain_outline_width": 4,
        "edge_debris": 0.45,
        "edge_color_strength": 0.35,
        "geometry_variance": 0.3,
        "shape_supersampling": 4,
        "normal_detail_strength": 1.0,
        "top_world_scale_px": 224.0,
        "face_world_scale_px": 112.0,
        "macro_world_scale_px": 448.0,
        "variants": 4,
        "texture_scale": 1.0,
        "colors": {
            "top": "#7b5027",
            "face": "#5a3822",
            "edge": "#654326",
            "back": "#6b452a",
            "base": "#a56a36",
        },
    },
}


DEFAULT_MAP_ROWS = (
    "000000000011100010000",
    "011111111111111111110",
    "011111111111111111110",
    "111111111111111111111",
    "011111111111111111111",
    "111111111111111111111",
    "011111111111111111111",
    "011111111111111111110",
    "000111111111100001110",
    "001111111111000000000",
    "011111111111100000110",
    "001111111111100000000",
    "011111111111110000000",
    "000111011111100000000",
    "000000000010000000000",
)


def make_default_map() -> dict:
    width = len(DEFAULT_MAP_ROWS[0])
    cells = [1 if cell == "1" else 0 for row in DEFAULT_MAP_ROWS for cell in row]
    return {"width": width, "height": len(DEFAULT_MAP_ROWS), "cells": cells}


def make_blob_map(width: int = 18, height: int = 12) -> dict:
    cells: list[int] = []
    cx = width / 2.0
    cy = height / 2.0
    for y in range(height):
        for x in range(width):
            dx = (x - cx) / (width * 0.38)
            dy = (y - cy) / (height * 0.38)
            radial = 1.0 - (dx * dx + dy * dy) ** 0.5
            cells.append(1 if radial > 0.36 else 0)
    return {"width": width, "height": height, "cells": cells}


def make_room_map(width: int = 18, height: int = 12) -> dict:
    cells = [0 for _ in range(width * height)]
    for y in range(2, height - 2):
        for x in range(3, width - 3):
            border = x == 3 or y == 2 or x == width - 4 or y == height - 3
            cells[y * width + x] = 1 if border else 0
    return {"width": width, "height": height, "cells": cells}


def make_cave_map(seed: int, width: int = 18, height: int = 12) -> dict:
    rng = random.Random(seed)
    cells = [1 if rng.random() > 0.45 else 0 for _ in range(width * height)]

    def sample(x: int, y: int) -> int:
        if x < 0 or y < 0 or x >= width or y >= height:
            return 0
        return cells[y * width + x]

    for _ in range(3):
        next_cells = cells[:]
        for y in range(height):
            for x in range(width):
                count = 0
                for oy in (-1, 0, 1):
                    for ox in (-1, 0, 1):
                        if ox == 0 and oy == 0:
                            continue
                        count += sample(x + ox, y + oy)
                next_cells[y * width + x] = 1 if count >= 4 else 0
        cells = next_cells

    return {"width": width, "height": height, "cells": cells}


def clone_preset(name: str) -> dict:
    preset = PRESETS.get(name, PRESETS["mountain"])
    return deepcopy(preset)
