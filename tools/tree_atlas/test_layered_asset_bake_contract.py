"""Checks that layered Blender bakes use one shared art contract."""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_asset_bake_profile.json"
TREE_PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_tree_bake_profile_10_oclock_fill_20.json"
DOC_PATH = ROOT / "docs" / "art" / "layered_asset_bake_contract.md"
TREE_DIR = ROOT / "assets" / "sprites" / "flora" / "layered_trees"
ROCK_DIR = ROOT / "assets" / "sprites" / "decor" / "plains" / "layered_small_rocks"
WORLD_STREAMER_PATH = ROOT / "core" / "systems" / "world" / "world_streamer.gd"
WORLD_CORE_PATH = ROOT / "gdextension" / "src" / "world_core.cpp"
TREE_IDS = tuple(f"tree_{index:02d}" for index in range(1, 7))
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
            "station_mirny_layered_tree_fixed_nw_winter_v2",
            "station_mirny_layered_tree_10_oclock_lamp100_root7_v5",
            "sun_azimuth_degrees: 315",
            "sun_azimuth_degrees: 205.201124",
            "sun_azimuth_degrees: 219",
            "shadow_sun_elevation_degrees: 42",
            "root_embed_fraction: 0.065",
            "root_embed_fraction: 0.07",
            "physical_mesh_bisect",
            "default_yaw_degrees: 90",
            "normal maps are generated but disabled in runtime",
        ):
            self.assertIn(required, text)

    def test_existing_tree_assets_record_the_shared_profile(self) -> None:
        profile = json.loads(TREE_PROFILE_PATH.read_text(encoding="utf-8"))
        expected = {
            "profile_id": profile["profile_id"],
            "version": profile["version"],
            "frame_size": profile["frame_size"],
            "sun_azimuth_degrees": profile["lighting"]["sun_azimuth_degrees"],
            "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
            "albedo_sun_angular_diameter_degrees": profile["lighting"]["albedo_sun_angular_diameter_degrees"],
            "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
            "root_embed_fraction": profile["planting"]["root_embed_fraction"],
            "ground_clip": profile["planting"]["ground_clip"],
            "screen_sun_direction": profile["lighting"]["screen_sun_direction"],
            "fixed_shadow_direction": profile["lighting"]["fixed_shadow_direction"],
            "fixed_shadow_direction_vector_screen": profile["lighting"]["fixed_shadow_direction_vector_screen"],
            "sun_shadow_mode": profile["runtime"]["sun_shadow_mode"],
            "shadow_contact_lock_source_px": profile["runtime"]["shadow_contact_lock_source_px"],
            "low_opposite_kicker": profile["lighting"]["low_opposite_kicker"],
        }

        for index, tree_id in enumerate(TREE_IDS, start=1):
            with self.subTest(tree_id=tree_id):
                meta_path = TREE_DIR / tree_id / "meta.json"
                self.assertTrue(meta_path.is_file())
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                expected_for_tree = expected | {"yaw_degrees": 180.0 if index == 6 else 90.0}
                self.assertEqual(meta.get("bake_profile"), expected_for_tree)
                for required_file in (
                    "albedo.png",
                    "trunk.png",
                    "foliage.png",
                    "shadow.png",
                    "wind_mask.png",
                    "snow_mask.png",
                    "snow_overlay.png",
                    "season_mask.png",
                    "height.png",
                    "normal.png",
                    "preview_panel.png",
                ):
                    self.assertTrue((TREE_DIR / tree_id / required_file).is_file(), f"{tree_id} missing {required_file}")

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

    def test_native_tree_variant_range_reaches_every_runtime_asset(self) -> None:
        source = WORLD_CORE_PATH.read_text(encoding="utf-8")
        match = re.search(r"TREE_ATLAS_VARIANT_COUNT\s*=\s*(\d+)", source)
        self.assertIsNotNone(match, "Native tree variant count must stay explicit.")
        self.assertGreaterEqual(int(match.group(1)), len(TREE_IDS))

    def test_runtime_streamer_registers_all_layered_small_rock_assets(self) -> None:
        self.assertTrue(WORLD_STREAMER_PATH.is_file(), "World streamer must declare layered small rock assets.")
        world_streamer = WORLD_STREAMER_PATH.read_text(encoding="utf-8")

        for rock_id in ROCK_IDS:
            with self.subTest(rock_id=rock_id):
                self.assertIn(f'"res://assets/sprites/decor/plains/layered_small_rocks/{rock_id}"', world_streamer)


if __name__ == "__main__":
    unittest.main()
