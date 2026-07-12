"""Checks that layered Blender bakes use one shared art contract."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_asset_bake_profile.json"
DOC_PATH = ROOT / "docs" / "art" / "layered_asset_bake_contract.md"
TREE_DIR = ROOT / "assets" / "sprites" / "flora" / "layered_trees"
ROCK_DIR = ROOT / "assets" / "sprites" / "decor" / "plains" / "layered_small_rocks"
WORLD_STREAMER_PATH = ROOT / "core" / "systems" / "world" / "world_streamer.gd"
TREE_IDS = ("tree_01", "tree_02", "tree_03", "tree_04", "tree_05")
ROCK_IDS = tuple(f"small_rock_{index:02d}" for index in range(1, 11))


class LayeredAssetBakeContractTest(unittest.TestCase):
    def test_shared_bake_profile_exists_and_matches_current_contract(self) -> None:
        self.assertTrue(PROFILE_PATH.is_file(), "Layered asset bake profile must be versioned as JSON.")
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))

        self.assertEqual(profile["profile_id"], "station_peaceful_layered_asset_bake_v1")
        self.assertEqual(profile["version"], 1)
        self.assertEqual(profile["frame_size"], 768)
        self.assertEqual(profile["orientation"]["default_yaw_degrees"], 90.0)
        self.assertEqual(profile["lighting"]["sun_azimuth_degrees"], 315.0)
        self.assertEqual(profile["lighting"]["albedo_sun_elevation_degrees"], 52.0)
        self.assertEqual(profile["lighting"]["shadow_sun_elevation_degrees"], 42.0)
        self.assertEqual(profile["planting"]["root_embed_fraction"], 0.065)
        self.assertFalse(profile["runtime"]["normal_maps_enabled"])
        self.assertEqual(
            profile["runtime"]["sun_shadow_mode"],
            "baked_north_east_rotated_to_runtime_shadow_axis_then_stretched",
        )

    def test_contract_doc_exists_and_names_required_rules(self) -> None:
        self.assertTrue(DOC_PATH.is_file(), "Layered asset bake contract must be documented.")
        text = DOC_PATH.read_text(encoding="utf-8")

        for required in (
            "station_peaceful_layered_asset_bake_v1",
            "sun_azimuth_degrees: 315",
            "shadow_sun_elevation_degrees: 42",
            "root_embed_fraction: 0.065",
            "default_yaw_degrees: 90",
            "normal maps are generated but disabled in runtime",
        ):
            self.assertIn(required, text)

    def test_existing_tree_assets_record_the_shared_profile(self) -> None:
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        expected = {
            "profile_id": profile["profile_id"],
            "version": profile["version"],
            "frame_size": profile["frame_size"],
            "sun_azimuth_degrees": profile["lighting"]["sun_azimuth_degrees"],
            "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
            "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
            "root_embed_fraction": profile["planting"]["root_embed_fraction"],
        }

        for tree_id in TREE_IDS:
            with self.subTest(tree_id=tree_id):
                meta_path = TREE_DIR / tree_id / "meta.json"
                self.assertTrue(meta_path.is_file())
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                self.assertEqual(meta.get("bake_profile"), expected)

    def test_existing_small_rock_assets_record_the_shared_profile(self) -> None:
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        expected = {
            "profile_id": profile["profile_id"],
            "version": profile["version"],
            "frame_size": profile["frame_size"],
            "sun_azimuth_degrees": profile["lighting"]["sun_azimuth_degrees"],
            "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
            "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
            "root_embed_fraction": profile["planting"]["root_embed_fraction"],
        }

        for rock_id in ROCK_IDS:
            with self.subTest(rock_id=rock_id):
                asset_dir = ROCK_DIR / rock_id
                meta_path = asset_dir / "meta.json"
                self.assertTrue(meta_path.is_file())
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                self.assertEqual(meta.get("bake_profile"), expected)
                self.assertFalse(meta.get("blocks_movement"))
                self.assertEqual(meta.get("collision_radius"), 0)
                self.assertEqual(meta.get("wind_strength"), 0.0)
                for required_file in (
                    "albedo.png",
                    "shadow.png",
                    "snow_mask.png",
                    "snow_overlay.png",
                    "height.png",
                    "normal.png",
                ):
                    self.assertTrue((asset_dir / required_file).is_file(), f"{rock_id} missing {required_file}")
                self.assertFalse((asset_dir / "wind_mask.png").exists(), f"{rock_id} must not include wind_mask.png")

    def test_runtime_streamer_registers_all_layered_tree_assets(self) -> None:
        self.assertTrue(WORLD_STREAMER_PATH.is_file(), "World streamer must declare layered tree assets.")
        world_streamer = WORLD_STREAMER_PATH.read_text(encoding="utf-8")

        for tree_id in TREE_IDS:
            with self.subTest(tree_id=tree_id):
                self.assertIn(f'"res://assets/sprites/flora/layered_trees/{tree_id}"', world_streamer)

    def test_runtime_streamer_registers_all_layered_small_rock_assets(self) -> None:
        self.assertTrue(WORLD_STREAMER_PATH.is_file(), "World streamer must declare layered small rock assets.")
        world_streamer = WORLD_STREAMER_PATH.read_text(encoding="utf-8")

        for rock_id in ROCK_IDS:
            with self.subTest(rock_id=rock_id):
                self.assertIn(f'"res://assets/sprites/decor/plains/layered_small_rocks/{rock_id}"', world_streamer)


if __name__ == "__main__":
    unittest.main()
