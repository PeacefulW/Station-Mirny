from __future__ import annotations

import random
from copy import deepcopy


PRESETS = {
    "mountain": {
        "tile_size": 64,
        "south_height": 18,
        "north_height": 10,
        "side_height": 16,
        "roughness": 52.0,
        "face_power": 1.0,
        "back_drop": 0.34,
        "crown_bevel": 2,
        "variants": 4,
        "texture_scale": 1.0,
        "colors": {
            "top": "#705940",
            "face": "#3e2f25",
            "back": "#564436",
            "base": "#b88d58",
        },
    },
    "wall": {
        "tile_size": 64,
        "south_height": 10,
        "north_height": 6,
        "side_height": 8,
        "roughness": 18.0,
        "face_power": 1.34,
        "back_drop": 0.24,
        "crown_bevel": 1,
        "variants": 3,
        "texture_scale": 1.0,
        "colors": {
            "top": "#765439",
            "face": "#473328",
            "back": "#5e4636",
            "base": "#bb9361",
        },
    },
    "earth": {
        "tile_size": 64,
        "south_height": 8,
        "north_height": 5,
        "side_height": 7,
        "roughness": 34.0,
        "face_power": 0.82,
        "back_drop": 0.28,
        "crown_bevel": 2,
        "variants": 4,
        "texture_scale": 1.0,
        "colors": {
            "top": "#7b5027",
            "face": "#5a3822",
            "back": "#6b452a",
            "base": "#a56a36",
        },
    },
}


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
