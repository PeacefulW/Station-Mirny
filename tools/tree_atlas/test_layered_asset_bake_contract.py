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
BUSH_DIR = ROOT / "assets" / "sprites" / "flora" / "layered_bushes"
WORLD_STREAMER_PATH = ROOT / "core" / "systems" / "world" / "world_streamer.gd"
TREE_IDS = ("tree_01", "tree_02", "tree_03", "tree_04", "tree_05", "tree_06")
CATALOG_PATH = ROOT / "core" / "systems" / "world" / "world_layered_object_asset_catalog.gd"
ROCK_LAYER_PATH = ROOT / "core" / "systems" / "world" / "layered_rock_object_layer.gd"
LIGHTING_PROFILE_PATH = ROOT / "core" / "systems" / "world" / "world_visual_lighting_profile.gd"
SHADOW_SHADER_PATH = ROOT / "assets" / "shaders" / "layered_object_shadow_batch.gdshader"
ROCK_IDS = tuple(f"small_rock_{index:02d}" for index in range(1, 23))
BUSH_IDS = ("alien_bush_01",)


class LayeredAssetBakeContractTest(unittest.TestCase):
    def test_shared_bake_profile_exists_and_matches_current_contract(self) -> None:
        self.assertTrue(PROFILE_PATH.is_file(), "Layered asset bake profile must be versioned as JSON.")
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))

        self.assertEqual(profile["profile_id"], "station_peaceful_layered_asset_bake_v1")
        self.assertEqual(profile["version"], 4)
        self.assertEqual(profile["frame_size"], 768)
        self.assertEqual(profile["orientation"]["default_yaw_degrees"], 90.0)
        self.assertEqual(profile["lighting"]["sun_azimuth_degrees"], 225.0)
        self.assertEqual(profile["lighting"]["fixed_shadow_direction"], "screen_south_east")
        self.assertEqual(profile["lighting"]["albedo_sun_energy"], 7.5)
        self.assertEqual(profile["render"]["exposure"], 0.0)
        # The shaded face is lifted from below by a ground bounce, never by a
        # frontal fill and never by exposure: both of those also lift the sunlit
        # tops, which is how the canopy got washed out.
        bounce = profile["lighting"]["bounce"]
        self.assertEqual(bounce["energy"], 150.0)
        self.assertGreater(bounce["pitch_degrees"], 90.0)
        self.assertLess(bounce["location"][2], 0.0)
        self.assertFalse(bounce["casts_shadow"])
        self.assertFalse(bounce["in_shadow_pass"])
        self.assertNotIn("fill_energy", profile["lighting"])
        # Layer passes must keep the other layers as shadow casters, or the
        # composited tree has no self-shadowing at all.
        self.assertTrue(profile["runtime"]["layer_cross_shadows"])
        self.assertEqual(profile["lighting"]["albedo_sun_elevation_degrees"], 52.0)
        self.assertEqual(profile["lighting"]["shadow_sun_elevation_degrees"], 42.0)
        self.assertEqual(profile["planting"]["root_embed_fraction"], 0.07)
        self.assertFalse(profile["runtime"]["normal_maps_enabled"])

    def test_contract_doc_exists_and_names_required_rules(self) -> None:
        self.assertTrue(DOC_PATH.is_file(), "Layered asset bake contract must be documented.")
        text = DOC_PATH.read_text(encoding="utf-8")

        for required in (
            "station_peaceful_layered_asset_bake_v1",
            "sun_azimuth_degrees: 225",
            "shadow_sun_elevation_degrees: 42",
            "root_embed_fraction: 0.07",
            "default_yaw_degrees: 90",
            "normal maps are generated but disabled in runtime",
            "ground bounce",
            "layer cross-shadows",
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

    def test_small_rock_assets_record_the_shared_profile(self) -> None:
        """The rock family migrated to the current sun; every member must agree.

        A single asset left on the old revision would cast north-east while its
        neighbours cast south-east, which is why this asserts the whole family.
        """
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        expected = {
            "profile_id": profile["profile_id"],
            "version": profile["version"],
            "frame_size": profile["frame_size"],
            "sun_azimuth_degrees": profile["lighting"]["sun_azimuth_degrees"],
            "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
            "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
            "rock_bounce_energy_scale": 0.30,
            "rock_bounce_energy": profile["lighting"]["bounce"]["energy"] * 0.30,
        }

        for rock_id in ROCK_IDS:
            with self.subTest(rock_id=rock_id):
                asset_dir = ROCK_DIR / rock_id
                meta_path = asset_dir / "meta.json"
                self.assertTrue(meta_path.is_file())
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                bake_profile = meta.get("bake_profile", {})
                for key, value in expected.items():
                    self.assertEqual(bake_profile.get(key), value)
                self.assertGreaterEqual(float(bake_profile["root_embed_fraction"]), 0.0)
                self.assertLessEqual(float(bake_profile["root_embed_fraction"]), 0.45)
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

    def test_bush_assets_record_the_shared_profile(self) -> None:
        """Bushes ride the tree channel set, so they must ride the tree sun too.

        The family is procedural (no source GLB), which is exactly why the
        recorded bake profile matters: nothing else ties the generator output to
        the shipped contract.
        """
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

        for bush_id in BUSH_IDS:
            with self.subTest(bush_id=bush_id):
                asset_dir = BUSH_DIR / bush_id
                meta_path = asset_dir / "meta.json"
                self.assertTrue(meta_path.is_file())
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                self.assertEqual(meta.get("bake_profile"), expected)
                # Walk-through decor: a bush must never acquire a tree collider.
                self.assertEqual(meta.get("collision_radius"), 0)
                self.assertFalse(meta.get("blocks_movement"))
                for required_file in (
                    "albedo.png",
                    "trunk.png",
                    "foliage.png",
                    "shadow.png",
                    "wind_mask.png",
                    "snow_mask.png",
                    "snow_overlay.png",
                    "season_mask.png",
                ):
                    self.assertTrue((asset_dir / required_file).is_file(), f"{bush_id} missing {required_file}")

    def test_runtime_shadow_stretch_matches_the_baked_sun(self) -> None:
        """A stretch that runs opposite the baked shadow walks off its own sprite."""
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(profile["lighting"]["fixed_shadow_direction"], "screen_south_east")
        self.assertTrue(CATALOG_PATH.is_file())
        catalog = CATALOG_PATH.read_text(encoding="utf-8")

        self.assertTrue(LIGHTING_PROFILE_PATH.is_file())
        lighting_profile = LIGHTING_PROFILE_PATH.read_text(encoding="utf-8")
        self.assertIn(
            "const FIXED_SHADOW_DIRECTION: Vector2 = Vector2(0.887216, 0.461354)",
            lighting_profile,
        )
        self.assertIn(
            "const TREE_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION",
            catalog,
        )
        self.assertIn(
            "const BUSH_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION",
            catalog,
        )
        self.assertIn("const TREE_SHADOW_OUTPUT_UV_MIN: Vector2 = Vector2(-0.10, -0.10)", catalog)
        self.assertIn("const TREE_SHADOW_OUTPUT_UV_MAX: Vector2 = Vector2(1.70, 1.50)", catalog)
        # Rocks migrated to the same sun, so their framing must open south-east too.
        self.assertIn(
            "const SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION",
            catalog,
        )
        self.assertIn("const SHADOW_OUTPUT_UV_MIN: Vector2 = Vector2(-0.10, -0.10)", catalog)
        self.assertIn("const SHADOW_OUTPUT_UV_MAX: Vector2 = Vector2(1.70, 1.50)", catalog)

        # The rock layer carries its own copy of the stretch direction; if the two
        # disagree the shadow stretches away from where it was rasterised.
        self.assertTrue(ROCK_LAYER_PATH.is_file())
        rock_layer = ROCK_LAYER_PATH.read_text(encoding="utf-8")
        self.assertIn(
            "const SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION",
            rock_layer,
        )

        self.assertTrue(SHADOW_SHADER_PATH.is_file())
        shadow_shader = SHADOW_SHADER_PATH.read_text(encoding="utf-8")
        self.assertIn("uniform vec2 shadow_direction = vec2(0.887216, 0.461354);", shadow_shader)
        self.assertIn("if (forward_distance > 0.0)", shadow_shader)
        self.assertIn(
            "delta -= direction * forward_distance * (1.0 - 1.0 / safe_scale);",
            shadow_shader,
        )

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
