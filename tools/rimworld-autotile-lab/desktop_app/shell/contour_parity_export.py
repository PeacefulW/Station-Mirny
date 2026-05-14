"""Deterministic generator reference export for mountain contour parity probes."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

import app
from core_bridge import run_core, stop_core_server
from presets import clone_preset

REFERENCE_EXPORT_MODE = app.RUNTIME_SDF_EXPORT_MODE
PARITY_SEED = 90213


PARITY_CASES: dict[str, tuple[str, ...]] = {
    "single_tile": (
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000100000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
    "two_by_two_blob": (
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000110000000",
        "0000000110000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
    "large_blob": (
        "0000000000000000",
        "0000000000000000",
        "0000001111000000",
        "0000111111110000",
        "0001111111111000",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0001111111111000",
        "0000111111110000",
        "0000001111000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
    "large_cave_like_cut": (
        "0000011100000000",
        "0000111110000000",
        "0001111111000000",
        "0011111111100000",
        "0111111111110000",
        "1111111111111000",
        "1111111111111100",
        "1111111001111100",
        "1111110000111100",
        "1111100000011100",
        "1111110000111110",
        "1111111001111110",
        "0111111111111110",
        "0011111111111100",
        "0001111111111000",
        "0000000000000000",
    ),
    "thin_diagonal_opening": (
        "0000000000000000",
        "0000000000000000",
        "0011111111110000",
        "0011111111100000",
        "0011111111000000",
        "0011111110001100",
        "0011111100011100",
        "0011111000111100",
        "0011110001111100",
        "0011100011111100",
        "0011000111111100",
        "0000001111111100",
        "0000011111111100",
        "0000111111111100",
        "0000000000000000",
        "0000000000000000",
    ),
    "inner_dug_hole": (
        "0000000000000000",
        "0000000000000000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111001111000",
        "0001111001111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0000000000000000",
        "0000000000000000",
    ),
    "straight_south_face": (
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0011111111111100",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
    "chunk_seam_edge": (
        "0000000000000000",
        "0000000000000000",
        "0000000000011111",
        "0000000000111111",
        "0000000001111111",
        "0000000011111111",
        "0000000011111111",
        "0000000011111111",
        "0000000011111111",
        "0000000001111111",
        "0000000000111111",
        "0000000000011111",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
    "mined_tile_notch": (
        "0000000000000000",
        "0000000000000000",
        "0000111111110000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111111111000",
        "0001111101111000",
        "0001111000111000",
        "0001110000011000",
        "0001111111111000",
        "0001111111111000",
        "0000111111110000",
        "0000000000000000",
        "0000000000000000",
        "0000000000000000",
    ),
}


def build_reference_request(case_name: str) -> dict:
    if case_name not in PARITY_CASES:
        raise KeyError(f"Unknown contour parity case: {case_name}")
    preset = clone_preset("mountain")
    request = {
        "asset_name": f"parity_{case_name}",
        "export_mode": REFERENCE_EXPORT_MODE,
        "preset": "mountain",
        "tile_size": 64,
        "south_height": preset["south_height"],
        "north_height": preset["north_height"],
        "side_height": preset["side_height"],
        "roughness": preset["roughness"],
        "face_power": preset["face_power"],
        "back_drop": preset["back_drop"],
        "crown_bevel": preset["crown_bevel"],
        "outer_corner_radius": preset["outer_corner_radius"],
        "inner_corner_radius": preset["inner_corner_radius"],
        "corner_round_px": preset["corner_round_px"],
        "diagonal_smooth_px": preset["diagonal_smooth_px"],
        "contour_relax": preset["contour_relax"],
        "contour_warp_px": preset["contour_warp_px"],
        "corner_variation": preset["corner_variation"],
        "rim_width": preset["rim_width"],
        "mountain_outline_enabled": preset["mountain_outline_enabled"],
        "mountain_outline_width": preset["mountain_outline_width"],
        "edge_debris": preset["edge_debris"],
        "edge_color_strength": preset["edge_color_strength"],
        "geometry_variance": preset["geometry_variance"],
        "shape_supersampling": preset["shape_supersampling"],
        "variants": 1,
        "forced_variant": 0,
        "seed": PARITY_SEED,
        "texture_scale": preset["texture_scale"],
        "normal_strength": preset["normal_strength"],
        "normal_detail_strength": preset["normal_detail_strength"],
        "bake_height_shading": preset["bake_height_shading"],
        "light_angle_deg": preset["light_angle_deg"],
        "texture_color_overlay": False,
        "preview_mode": "lit",
        "textures": {"top": "", "face": "", "base": ""},
        "colors": preset["colors"],
        "materials": app.MATERIAL_DEFAULTS,
        "map": _map_from_rows(PARITY_CASES[case_name]),
    }
    return request


def export_references(output_dir: Path, case_names: Iterable[str] | None = None) -> dict:
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    selected_cases = list(case_names) if case_names is not None else list(PARITY_CASES.keys())
    index: dict[str, dict] = {}
    try:
        for case_name in selected_cases:
            request = build_reference_request(case_name)
            case_dir = output_dir / case_name / "generator"
            manifest = run_core("full", request, case_dir)
            index[case_name] = {
                "request": request,
                "manifest": manifest,
            }
    finally:
        stop_core_server()

    index_path = output_dir / "generator_reference_index.json"
    index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False), encoding="utf-8")
    return index


def _map_from_rows(rows: tuple[str, ...]) -> dict:
    width = len(rows[0])
    if width == 0 or any(len(row) != width for row in rows):
        raise ValueError("Parity mask rows must be non-empty and rectangular.")
    cells: list[int] = []
    for row in rows:
        for value in row:
            if value not in {"0", "1"}:
                raise ValueError("Parity mask rows may contain only 0 or 1.")
            cells.append(1 if value == "1" else 0)
    return {
        "width": width,
        "height": len(rows),
        "cells": cells,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[4] / "artifacts" / "mountain_contour_parity",
        help="Directory where deterministic parity references will be written.",
    )
    parser.add_argument(
        "--case",
        dest="cases",
        action="append",
        choices=tuple(PARITY_CASES.keys()),
        help="Specific parity case to export. Repeat to export multiple cases.",
    )
    args = parser.parse_args()
    index = export_references(args.output, args.cases)
    print(json.dumps({"ok": True, "case_count": len(index), "output": str(args.output)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
