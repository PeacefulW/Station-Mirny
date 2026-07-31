"""Checks that layered Blender bakes use one shared art contract."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_asset_bake_profile.json"
RUST_CROWN_PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "rust_crown_tree_profiles.json"
RUST_CROWN_GENERATOR_PATH = ROOT / "tools" / "tree_atlas" / "blender_rust_crown_tree_bake.py"
RUST_CROWN_ARTIFACT_DIR = ROOT / "artifacts" / "rust_crown_tree"
DOC_PATH = ROOT / "docs" / "art" / "layered_asset_bake_contract.md"
TREE_DIR = ROOT / "assets" / "sprites" / "flora" / "layered_trees"
ROCK_DIR = ROOT / "assets" / "sprites" / "decor" / "plains" / "layered_small_rocks"
BUSH_DIR = ROOT / "assets" / "sprites" / "flora" / "layered_bushes"
WORLD_STREAMER_PATH = ROOT / "core" / "systems" / "world" / "world_streamer.gd"
TREE_IDS = tuple(f"rust_crown_{index:02d}" for index in range(1, 9))
RUST_CROWN_FOOTPRINTS = (
    {"offset_x_px": 49, "width_px": 68, "depth_px": 31},
    {"offset_x_px": -48, "width_px": 67, "depth_px": 31},
    {"offset_x_px": 6, "width_px": 47, "depth_px": 26},
    {"offset_x_px": 21, "width_px": 46, "depth_px": 26},
    {"offset_x_px": 25, "width_px": 85, "depth_px": 36},
    {"offset_x_px": -35, "width_px": 77, "depth_px": 35},
    {"offset_x_px": -79, "width_px": 81, "depth_px": 36},
    {"offset_x_px": 24, "width_px": 94, "depth_px": 36},
)
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

    def test_rust_crown_uses_a_continuous_data_driven_fork_transition(self) -> None:
        profile = json.loads(RUST_CROWN_PROFILE_PATH.read_text(encoding="utf-8"))
        transition = profile["geometry"]["trunk_transition"]
        braid = profile["geometry"]["trunk"]["braid"]
        branching = profile["geometry"]["branching"]
        generator = RUST_CROWN_GENERATOR_PATH.read_text(encoding="utf-8")

        self.assertEqual(profile["version"], 2)
        self.assertGreater(transition["length_fraction"], 0.0)
        self.assertLess(transition["length_fraction"], transition["core_start_fraction"])
        self.assertLess(transition["core_start_fraction"], transition["cord_continuation_fraction"])
        self.assertLessEqual(transition["cord_continuation_fraction"], 1.0)
        self.assertGreaterEqual(transition["cord_segments"], 8)
        self.assertGreaterEqual(transition["rings"], 4)
        self.assertEqual(transition["first_order_sides"], profile["geometry"]["trunk"]["sides"])
        self.assertGreater(transition["first_order_relief_scale"], 0.5)
        self.assertGreaterEqual(transition["radius_floor_fraction"], 0.9)
        self.assertLessEqual(transition["cord_turns"], 0.25)
        self.assertGreater(transition["cord_end_radius_fraction"], 0.0)
        self.assertLessEqual(transition["cord_end_radius_fraction"], 0.15)
        self.assertGreaterEqual(transition["cord_core_inset"], 1.0)
        self.assertGreater(transition["area_radius_scale"], 0.0)
        self.assertGreater(transition["core_entry_radius_fraction"], 0.0)
        self.assertLess(transition["core_entry_radius_fraction"], 1.0)
        self.assertGreater(transition["cord_tip_flare_start_fraction"], 0.5)
        self.assertLess(transition["cord_tip_flare_start_fraction"], 1.0)
        self.assertGreater(transition["cord_tip_flare_scale"], 1.0)
        self.assertLess(transition["bark_trunk_end"], 1.0)
        self.assertGreater(braid["fork_open_fraction"], 0.0)
        self.assertLess(braid["fork_open_fraction"], 1.0)
        self.assertGreater(braid["fork_open_start_fraction"], 0.5)
        self.assertLess(braid["fork_open_start_fraction"], 1.0)
        self.assertGreater(braid["sub"]["fork_open_fraction"], 0.0)
        self.assertLess(braid["sub"]["fork_open_fraction"], 1.0)
        self.assertGreater(braid["sub"]["fork_open_start_fraction"], 0.5)
        self.assertLess(braid["sub"]["fork_open_start_fraction"], 1.0)
        self.assertGreater(min(branching["radius_fraction"]), 0.0)
        self.assertLessEqual(max(branching["radius_fraction"]), 1.0)
        self.assertGreaterEqual(
            transition["radius_floor_fraction"],
            max(branching["radius_fraction"]),
        )
        for required in (
            "def hermite_fork_points(",
            "def add_fork_continuations(",
            "tail_tangent = slope_start * (1.0 - fork_open_start_fraction)",
            "fork_open_fraction <= 0.0 or t <= fork_open_start_fraction",
            "envelope = h00 * bulge_start + h10 * tail_tangent + h01 * fork_open_fraction",
            '"entry_direction": visual_tip_direction',
            '"branch_direction": branch_tip_direction',
            "cap_start=not first_order_transition",
            'combined_points = cord["points"] + rib_points[1:]',
            "embedded_offset = max(core_radius - rib_radius * cord_core_inset, 0.0)",
            "core_scale = lerp_float(core_entry_radius_fraction, 1.0, merge)",
            "tip_flare_scale = float(transition[\"cord_tip_flare_scale\"])",
            "tip_radius = shaft_root_radius * taper",
            "tier_blend_end=bark_end",
            "relief_path_t=relief_path_t",
            "ramp_start=bark_start",
            "end_tier_index=target_tier",
        ):
            self.assertIn(required, generator)

    def test_rust_crown_collision_footprints_flow_from_profile_to_assets(self) -> None:
        profile = json.loads(RUST_CROWN_PROFILE_PATH.read_text(encoding="utf-8"))
        variants = profile["variants"]
        generator = RUST_CROWN_GENERATOR_PATH.read_text(encoding="utf-8")

        self.assertEqual(len(variants), len(RUST_CROWN_FOOTPRINTS))
        self.assertIn('"collision_footprint": dict(variant["collision_footprint"])', generator)
        for index, expected in enumerate(RUST_CROWN_FOOTPRINTS, start=1):
            variant_id = f"var_{index:02d}"
            tree_id = f"rust_crown_{index:02d}"
            with self.subTest(tree_id=tree_id):
                self.assertEqual(variants[index - 1]["id"], variant_id)
                self.assertEqual(variants[index - 1]["collision_footprint"], expected)

                production_meta = json.loads(
                    (TREE_DIR / tree_id / "meta.json").read_text(encoding="utf-8")
                )
                artifact_classification = json.loads(
                    (RUST_CROWN_ARTIFACT_DIR / variant_id / "classification.json").read_text(
                        encoding="utf-8"
                    )
                )
                artifact_meta = json.loads(
                    (RUST_CROWN_ARTIFACT_DIR / variant_id / "meta.json").read_text(encoding="utf-8")
                )
                artifact_variation = json.loads(
                    (RUST_CROWN_ARTIFACT_DIR / variant_id / "variation.json").read_text(
                        encoding="utf-8"
                    )
                )

                self.assertEqual(artifact_classification["collision_footprint"], expected)
                self.assertEqual(artifact_meta["collision_footprint"], expected)
                self.assertEqual(
                    artifact_variation["variant"]["collision_footprint"],
                    expected,
                )
                self.assertEqual(production_meta["collision_footprint"], expected)
                self.assertNotIn("collision_radius", artifact_meta)
                self.assertNotIn("collision_radius", production_meta)

    def test_rust_crown_collision_footprints_align_with_the_dense_trunk_base(self) -> None:
        for index, footprint in enumerate(RUST_CROWN_FOOTPRINTS, start=1):
            tree_id = f"rust_crown_{index:02d}"
            with self.subTest(tree_id=tree_id):
                asset_dir = TREE_DIR / tree_id
                metadata = json.loads(
                    (asset_dir / "meta.json").read_text(encoding="utf-8")
                )
                anchor_x, anchor_y = metadata["anchor"]
                center_x = anchor_x + footprint["offset_x_px"]
                left = round(center_x - footprint["width_px"] * 0.5)
                right = round(center_x + footprint["width_px"] * 0.5)
                top = anchor_y - footprint["depth_px"]
                alpha = Image.open(asset_dir / "trunk.png").convert("RGBA").getchannel("A")
                opaque_by_column = [
                    sum(
                        alpha.getpixel((x, y)) >= 32
                        for y in range(top, anchor_y + 1)
                    )
                    for x in range(alpha.width)
                ]
                footprint_width = right - left + 1
                authored_opaque = sum(opaque_by_column[left : right + 1])
                best_opaque = max(
                    sum(opaque_by_column[x : x + footprint_width])
                    for x in range(alpha.width - footprint_width + 1)
                )
                alignment = authored_opaque / best_opaque

                self.assertGreaterEqual(
                    alignment,
                    0.85,
                    f"{tree_id} collision footprint is horizontally misaligned",
                )

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
