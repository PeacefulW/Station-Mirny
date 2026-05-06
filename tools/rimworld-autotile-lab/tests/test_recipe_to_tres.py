import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "recipe_to_tres.py"


def write_png(path: Path, width: int, height: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw_rows = b"".join(b"\x00" + (b"\x00\x00\x00\xff" * width) for _ in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw_rows))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def write_recipe(path: Path, asset_name: str, export_mode: str = "Full47") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "request": {
                    "asset_name": asset_name,
                    "export_mode": export_mode,
                    "tile_size": 64,
                    "variant_count": 6,
                    "shader_family_id": "terrain.ground_hybrid",
                }
            }
        ),
        encoding="utf-8",
    )


def write_material_textures(asset_dir: Path, asset_name: str) -> None:
    for slot in (
        "top_albedo",
        "face_albedo",
        "top_modulation",
        "face_modulation",
        "top_normal",
        "face_normal",
    ):
        write_png(asset_dir / f"{asset_name}_{slot}.png", 64, 64)


def run_bridge(project_root: Path, recipe: Path, target: Path, *extra_args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(recipe),
            "--asset-dir",
            str(recipe.parent),
            "--target",
            str(target),
            "--project-root",
            str(project_root),
            *extra_args,
        ],
        cwd=project_root,
        text=True,
        capture_output=True,
        check=False,
    )


class RecipeToTresBridgeTests(unittest.TestCase):
    def test_full47_writes_shape_and_material_resources(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_root = Path(tmp) / "project"
            asset_dir = project_root / "assets" / "textures" / "terrain" / "plains_ground"
            target = project_root / "data" / "terrain"
            recipe = asset_dir / "plains_ground_recipe.json"
            write_recipe(recipe, "plains_ground", "Full47")
            write_png(asset_dir / "plains_ground_atlas_mask.png", 47 * 64, 6 * 64)
            write_png(asset_dir / "plains_ground_atlas_normal.png", 47 * 64, 6 * 64)
            write_material_textures(asset_dir, "plains_ground")

            result = run_bridge(project_root, recipe, target)

            self.assertEqual(result.returncode, 0, result.stderr)
            shape_tres = target / "shape_sets" / "plains_ground_shape_set.tres"
            material_tres = target / "material_sets" / "plains_ground_material_set.tres"
            self.assertTrue(shape_tres.exists())
            self.assertTrue(material_tres.exists())

            shape_text = shape_tres.read_text(encoding="utf-8")
            self.assertIn('script = ExtResource("1")', shape_text)
            self.assertIn('id = &"terrain:plains_ground_shape_set"', shape_text)
            self.assertIn('topology_family_id = &"autotile_47"', shape_text)
            self.assertIn('path="res://assets/textures/terrain/plains_ground/plains_ground_atlas_mask.png"', shape_text)
            self.assertIn('path="res://assets/textures/terrain/plains_ground/plains_ground_atlas_normal.png"', shape_text)
            self.assertIn("case_count = 47", shape_text)
            self.assertIn("variant_count = 6", shape_text)

            material_text = material_tres.read_text(encoding="utf-8")
            self.assertIn('script = ExtResource("1")', material_text)
            self.assertIn('id = &"terrain:plains_ground_material_set"', material_text)
            self.assertIn('shader_family_id = &"terrain.ground_hybrid"', material_text)
            self.assertIn("top_albedo = ExtResource", material_text)
            self.assertIn("face_normal = ExtResource", material_text)

    def test_dry_run_prints_planned_resources_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_root = Path(tmp) / "project"
            asset_dir = project_root / "assets" / "textures" / "terrain" / "plains_ground"
            target = project_root / "data" / "terrain"
            recipe = asset_dir / "plains_ground_recipe.json"
            write_recipe(recipe, "plains_ground", "Full47")
            write_png(asset_dir / "plains_ground_atlas_mask.png", 47 * 64, 6 * 64)
            write_png(asset_dir / "plains_ground_atlas_normal.png", 47 * 64, 6 * 64)
            write_material_textures(asset_dir, "plains_ground")

            result = run_bridge(project_root, recipe, target, "--dry-run")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("plains_ground_shape_set.tres", result.stdout)
            self.assertIn("[gd_resource type=\"Resource\" script_class=\"TerrainShapeSet\"", result.stdout)
            self.assertFalse((target / "shape_sets" / "plains_ground_shape_set.tres").exists())
            self.assertFalse((target / "material_sets" / "plains_ground_material_set.tres").exists())

    def test_each_export_mode_routes_to_expected_resource_family(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_root = Path(tmp) / "project"
            target = project_root / "data" / "terrain"

            base_dir = project_root / "assets" / "textures" / "terrain" / "ground_base"
            base_recipe = base_dir / "ground_base_recipe.json"
            write_recipe(base_recipe, "ground_base", "BaseVariantsOnly")
            write_material_textures(base_dir, "ground_base")
            write_png(base_dir / "ground_base_atlas_albedo.png", 64, 6 * 64)
            self.assertEqual(run_bridge(project_root, base_recipe, target).returncode, 0)
            self.assertTrue((target / "material_sets" / "ground_base_material_set.tres").exists())
            self.assertFalse((target / "shape_sets" / "ground_base_shape_set.tres").exists())

            mask_dir = project_root / "assets" / "textures" / "terrain" / "transition_mask"
            mask_recipe = mask_dir / "transition_mask_recipe.json"
            write_recipe(mask_recipe, "transition_mask", "MaskOnly")
            write_png(mask_dir / "transition_mask_atlas_mask.png", 47 * 64, 6 * 64)
            self.assertEqual(run_bridge(project_root, mask_recipe, target).returncode, 0)
            self.assertTrue((target / "shape_sets" / "transition_mask_shape_set.tres").exists())
            self.assertFalse((target / "material_sets" / "transition_mask_material_set.tres").exists())

            decal_dir = project_root / "assets" / "textures" / "terrain" / "first_biome"
            decal_recipe = decal_dir / "first_biome_recipe.json"
            write_recipe(decal_recipe, "first_biome", "Full47")
            write_png(decal_dir / "first_biome_decal_atlas.png", 4 * 64, 4 * 64)
            (decal_dir / "first_biome_decal_metadata.json").write_text(
                json.dumps(
                    {
                        "asset_name": "first_biome",
                        "atlas_columns": 4,
                        "atlas_rows": 4,
                        "cell_size_px": 64,
                        "cells": [
                            {"index": i, "size_class": "small", "pivot": [0.5, 0.5]}
                            for i in range(16)
                        ],
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(run_bridge(project_root, decal_recipe, target, "--mode", "Decals").returncode, 0)
            self.assertTrue((target / "decals" / "first_biome_atlas.tres").exists())

            silhouette_dir = project_root / "assets" / "textures" / "terrain" / "first_biome_rock_wall"
            silhouette_recipe = silhouette_dir / "first_biome_rock_wall_recipe.json"
            write_recipe(silhouette_recipe, "first_biome_rock_wall", "Full47")
            write_png(silhouette_dir / "first_biome_rock_wall_silhouette_atlas.png", 3 * 64, 8 * 96)
            (silhouette_dir / "first_biome_rock_wall_silhouette_metadata.json").write_text(
                json.dumps(
                    {
                        "asset_name": "first_biome_rock_wall",
                        "tile_size_px": 64,
                        "silhouette_height_px": 96,
                        "variant_count": 3,
                        "directions": ["N", "E", "S", "W", "NE", "SE", "SW", "NW"],
                        "has_corner_sprites": True,
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                run_bridge(project_root, silhouette_recipe, target, "--mode", "Silhouettes").returncode,
                0,
            )
            silhouette_text = (target / "silhouettes" / "first_biome_rock_wall.tres").read_text(encoding="utf-8")
            self.assertIn('topology_family_id = &"mountain_silhouette_cardinal_corner"', silhouette_text)
            self.assertIn("case_count = 8", silhouette_text)
            self.assertIn("variant_count = 3", silhouette_text)

    def test_wrong_atlas_dimensions_report_clear_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_root = Path(tmp) / "project"
            asset_dir = project_root / "assets" / "textures" / "terrain" / "bad_mask"
            target = project_root / "data" / "terrain"
            recipe = asset_dir / "bad_mask_recipe.json"
            write_recipe(recipe, "bad_mask", "MaskOnly")
            write_png(asset_dir / "bad_mask_atlas_mask.png", 64, 64)

            result = run_bridge(project_root, recipe, target)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("atlas dimensions", result.stderr)
            self.assertIn("bad_mask_atlas_mask.png", result.stderr)


if __name__ == "__main__":
    unittest.main()
