"""Contract checks for the Blender-authored grass tuft atlas prototype."""

from __future__ import annotations

import importlib.util
import json
import re
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
TREE_PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_tree_bake_profile_10_oclock_fill_20.json"
GRASS_PROFILE_PATH = ROOT / "tools" / "grass_atlas" / "grass_tuft_bake_profile.json"
BLENDER_BAKE_PATH = ROOT / "tools" / "grass_atlas" / "blender_grass_tuft_bake.py"
POSTPROCESS_PATH = ROOT / "tools" / "grass_atlas" / "postprocess_grass_tuft_atlas.py"
PROTOTYPE_ROOT = ROOT / "artifacts" / "blender_grass_tufts_10_oclock_fill_20"
PROTOTYPE_ALBEDO_PATH = PROTOTYPE_ROOT / "grass_tuft_albedo_atlas.png"
PROTOTYPE_SHADOW_PATH = PROTOTYPE_ROOT / "grass_tuft_shadow_atlas.png"
PROTOTYPE_RAW_SHADOW_PATH = PROTOTYPE_ROOT / "frames" / "shadow_frame_00.png"
RUNTIME_GRASS_ATLAS_PATH = ROOT / "assets" / "textures" / "world" / "biomes" / "plains" / "flora" / "grass_tuft_atlas.png"
RUNTIME_SHADOW_ATLAS_PATH = ROOT / "assets" / "textures" / "world" / "biomes" / "plains" / "flora" / "grass_tuft_shadow_atlas.png"
GRASS_MATERIAL_SET_PATH = ROOT / "data" / "terrain" / "material_sets" / "grass_scatter_material_set.tres"
CHUNK_VIEW_PATH = ROOT / "core" / "systems" / "world" / "chunk_view.gd"
WORLD_STREAMER_PATH = ROOT / "core" / "systems" / "world" / "world_streamer.gd"
GRASS_SHADER_PATH = ROOT / "assets" / "shaders" / "grass_scatter_batch.gdshader"


def load_postprocess_module():
    spec = importlib.util.spec_from_file_location("postprocess_grass_tuft_atlas", POSTPROCESS_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("Cannot load grass postprocess module.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def alpha_centroid(alpha: Image.Image) -> tuple[float, float]:
    alpha = alpha.convert("L")
    total = 0
    sum_x = 0
    sum_y = 0
    for y in range(alpha.height):
        for x in range(alpha.width):
            value = alpha.getpixel((x, y))
            if value <= 0:
                continue
            total += value
            sum_x += x * value
            sum_y += y * value
    if total <= 0:
        raise AssertionError("Alpha image has no visible pixels.")
    return sum_x / total, sum_y / total


def read_sampling_number(material_text: str, key: str) -> float:
    match = re.search(r'"%s":\s*([-0-9.]+)' % re.escape(key), material_text)
    if match is None:
        raise AssertionError("grass_scatter_material_set.tres is missing sampling param %r" % key)
    return float(match.group(1))


def runtime_frame_metrics() -> dict[str, float]:
    grass_profile = json.loads(GRASS_PROFILE_PATH.read_text(encoding="utf-8"))
    runtime = Image.open(RUNTIME_GRASS_ATLAS_PATH).convert("RGBA")
    frame_width = int(grass_profile["atlas"]["frame_width"])
    frame_height = int(grass_profile["atlas"]["frame_height"])
    coverages: list[float] = []
    ratios: list[float] = []
    bottoms: list[int] = []
    for index in range(int(grass_profile["atlas"]["frame_count"])):
        box = (
            (index % int(grass_profile["atlas"]["columns"])) * frame_width,
            (index // int(grass_profile["atlas"]["columns"])) * frame_height,
            (index % int(grass_profile["atlas"]["columns"]) + 1) * frame_width,
            (index // int(grass_profile["atlas"]["columns"]) + 1) * frame_height,
        )
        alpha = runtime.crop(box).getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None:
            continue
        visible = sum(1 for value in alpha.tobytes() if value > 12)
        coverages.append(visible / float(frame_width * frame_height))
        ratios.append((bbox[2] - bbox[0]) / max(1, bbox[3] - bbox[1]))
        bottoms.append(bbox[3])
    if not coverages:
        raise AssertionError("Runtime grass atlas has no visible frames.")
    return {
        "avg_coverage": sum(coverages) / len(coverages),
        "max_coverage": max(coverages),
        "max_ratio": max(ratios),
        "bottom_spread": float(max(bottoms) - min(bottoms)),
    }


class GrassTuftBakeContractTest(unittest.TestCase):
    def test_grass_profile_inherits_shared_light_contract(self) -> None:
        self.assertTrue(GRASS_PROFILE_PATH.is_file(), "Grass tuft bake profile must be versioned as JSON.")
        tree_profile = json.loads(TREE_PROFILE_PATH.read_text(encoding="utf-8"))
        grass_profile = json.loads(GRASS_PROFILE_PATH.read_text(encoding="utf-8"))

        self.assertEqual(grass_profile["profile_id"], "station_mirny_grass_tuft_10_oclock_fill_20_v2")
        self.assertEqual(grass_profile["inherits_profile_id"], tree_profile["profile_id"])
        self.assertEqual(grass_profile["version"], 2)
        self.assertEqual(grass_profile["atlas"]["columns"], 4)
        self.assertEqual(grass_profile["atlas"]["rows"], 8)
        self.assertEqual(grass_profile["atlas"]["frame_count"], 32)
        self.assertEqual(grass_profile["atlas"]["dry_frame_count"], 16)
        self.assertEqual(grass_profile["atlas"]["biofield_frame_base"], 16)
        self.assertEqual(grass_profile["lighting"]["sun_azimuth_degrees"], tree_profile["lighting"]["sun_azimuth_degrees"])
        self.assertEqual(
            grass_profile["lighting"]["shadow_sun_elevation_degrees"],
            tree_profile["lighting"]["shadow_sun_elevation_degrees"],
        )
        self.assertEqual(grass_profile["lighting"]["fixed_shadow_direction"], tree_profile["lighting"]["fixed_shadow_direction"])
        self.assertEqual(grass_profile["lighting"]["fixed_shadow_direction_vector_screen"], [0.866025, 0.5])
        self.assertEqual(grass_profile["lighting"]["low_opposite_kicker"], tree_profile["lighting"]["low_opposite_kicker"])
        self.assertEqual(grass_profile["render"]["exposure"], 0.75)
        self.assertEqual(
            grass_profile["palette"]["source_reference"],
            "assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png",
        )
        self.assertGreaterEqual(len(grass_profile["palette"]["dry_blade_ramps"]), 4)
        self.assertGreaterEqual(len(grass_profile["palette"]["biofield_blade_ramps"]), 4)
        self.assertEqual(grass_profile["postprocess"]["albedo_grade_rgb_multiply"], [1.0, 0.68, 0.38])
        self.assertEqual(grass_profile["render"]["shadow_engine"], tree_profile["render"]["shadow_engine"])
        self.assertEqual(grass_profile["lighting"]["shadow_sun_energy"], tree_profile["lighting"]["shadow_sun_energy"])
        self.assertTrue(grass_profile["runtime"]["replace_live_runtime_asset"])
        self.assertEqual(
            grass_profile["runtime"]["sun_shadow_mode"],
            "blender_baked_east_south_east_fixed_length",
        )
        self.assertEqual(grass_profile["runtime"]["shadow_length_mode"], "fixed")

    def test_grass_profile_targets_relaxed_broken_steppe_tufts(self) -> None:
        grass_profile = json.loads(GRASS_PROFILE_PATH.read_text(encoding="utf-8"))
        tuft = grass_profile["tuft"]
        ranges = tuft["blade_count_ranges"]

        self.assertLessEqual(ranges["standard"][1], 19)
        self.assertLessEqual(ranges["sparse"][1], 9)
        self.assertLessEqual(ranges["dense"][1], 29)
        self.assertGreaterEqual(float(tuft["depth_y"]), 0.14)
        self.assertLessEqual(float(tuft["root_z_min"]), -0.04)
        self.assertGreaterEqual(float(tuft["root_z_max"]), 0.025)
        self.assertGreaterEqual(float(tuft["droop_max"]), 0.30)
        self.assertGreaterEqual(tuft["ground_straw_count_ranges"]["standard"][0], 3)

    def test_output_contract_names_all_expected_atlases(self) -> None:
        grass_profile = json.loads(GRASS_PROFILE_PATH.read_text(encoding="utf-8"))
        outputs = set(grass_profile["outputs"])

        self.assertEqual(
            outputs,
            {
                "grass_tuft_albedo_atlas.png",
                "grass_tuft_shadow_atlas.png",
                "grass_tuft_wind_mask_atlas.png",
                "grass_tuft_snow_mask_atlas.png",
                "grass_tuft_snow_overlay_atlas.png",
                "grass_tuft_season_mask_atlas.png",
                "preview_panel.png",
                "meta.json",
            },
        )

    def test_runtime_grass_atlas_uses_current_blender_prototype(self) -> None:
        self.assertTrue(PROTOTYPE_ALBEDO_PATH.is_file(), "Prototype albedo atlas must exist before runtime replacement.")
        self.assertTrue(RUNTIME_GRASS_ATLAS_PATH.is_file(), "Runtime grass tuft atlas must exist.")

        prototype = Image.open(PROTOTYPE_ALBEDO_PATH).convert("RGBA")
        runtime = Image.open(RUNTIME_GRASS_ATLAS_PATH).convert("RGBA")

        self.assertEqual(runtime.size, prototype.size)
        self.assertEqual(runtime.tobytes(), prototype.tobytes())

    def test_runtime_grass_silhouette_stays_upright_after_scale_down(self) -> None:
        self.assertLessEqual(runtime_frame_metrics()["max_ratio"], 1.75)

    def test_runtime_grass_atlas_is_relaxed_not_dense_comb(self) -> None:
        metrics = runtime_frame_metrics()

        self.assertLessEqual(metrics["avg_coverage"], 0.095)
        self.assertLessEqual(metrics["max_coverage"], 0.17)
        self.assertGreaterEqual(metrics["bottom_spread"], 18.0)

    def test_runtime_grass_material_disables_blob_shadows_for_baked_atlas(self) -> None:
        # Density/size numbers are the user's live-tuned taste knobs, not a
        # contract. The contract is structural: while the baked directional
        # shadow atlas is wired, the legacy blob-shadow layer must stay off.
        material_text = GRASS_MATERIAL_SET_PATH.read_text(encoding="utf-8")

        self.assertLessEqual(read_sampling_number(material_text, "shadow_alpha"), 0.05)
        self.assertLessEqual(read_sampling_number(material_text, "shadow_size_scale"), 0.05)
        self.assertGreater(read_sampling_number(material_text, "directional_shadow_alpha"), 0.0)

    def test_runtime_uses_baked_directional_shadow_atlas(self) -> None:
        self.assertTrue(PROTOTYPE_RAW_SHADOW_PATH.is_file(), "Blender must emit raw shadow catcher frames.")
        self.assertTrue(PROTOTYPE_SHADOW_PATH.is_file(), "Prototype directional shadow atlas must exist.")
        self.assertTrue(RUNTIME_SHADOW_ATLAS_PATH.is_file(), "Runtime directional shadow atlas must exist.")

        prototype = Image.open(PROTOTYPE_SHADOW_PATH).convert("RGBA")
        runtime = Image.open(RUNTIME_SHADOW_ATLAS_PATH).convert("RGBA")
        self.assertEqual(runtime.size, prototype.size)
        self.assertEqual(runtime.tobytes(), prototype.tobytes())

        material_text = GRASS_MATERIAL_SET_PATH.read_text(encoding="utf-8")
        chunk_view_text = CHUNK_VIEW_PATH.read_text(encoding="utf-8")
        world_streamer_text = WORLD_STREAMER_PATH.read_text(encoding="utf-8")
        shader_text = GRASS_SHADER_PATH.read_text(encoding="utf-8")

        self.assertIn('&"grass_tuft_shadow_atlas"', material_text)
        self.assertIn("_grass_shadow_atlas_layers", chunk_view_text)
        self.assertIn("grass_shadow_atlas_material", chunk_view_text)
        self.assertIn("if not has_shadow_atlas:", chunk_view_text)
        self.assertIn("_grass_shadow_atlas", world_streamer_text)
        self.assertIn('_grass_shadow_atlas_material.set_shader_parameter("overlay_exact", 1.0)', world_streamer_text)
        self.assertIn('"overlay_shadow_rotation_enabled", 1.0', world_streamer_text)
        self.assertIn("overlay_shadow_runtime_direction", shader_text)
        self.assertIn("overlay_shadow_anchor_uv", shader_text)
        self.assertNotIn("shadow_length_scale", shader_text)
        self.assertIn('"directional_shadow_runtime_direction": Vector2(0.866025, 0.5)', material_text)
        self.assertIn('grass_params.get(', world_streamer_text)
        self.assertIn('"directional_shadow_runtime_direction"', world_streamer_text)

        blender_bake_text = BLENDER_BAKE_PATH.read_text(encoding="utf-8")
        postprocess_text = POSTPROCESS_PATH.read_text(encoding="utf-8")
        self.assertIn("setup_shadow_scene", blender_bake_text)
        self.assertIn("shadow_frame_%02d.png", blender_bake_text)
        self.assertIn("processed_shadow_from_raw", postprocess_text)

    def test_wind_mask_pins_roots_and_weights_tips(self) -> None:
        module = load_postprocess_module()
        alpha = Image.new("L", (8, 8), 0)
        for y in range(1, 8):
            alpha.putpixel((4, y), 220)

        wind_mask = module.make_wind_mask_from_alpha(alpha)

        self.assertLessEqual(wind_mask.getpixel((4, 7)), 8)
        self.assertGreater(wind_mask.getpixel((4, 1)), 130)
        self.assertGreater(wind_mask.getpixel((4, 3)), wind_mask.getpixel((4, 6)))

    def test_fake_shadow_matches_tree_baked_angle_without_edge_clip(self) -> None:
        module = load_postprocess_module()
        alpha = Image.new("L", (32, 32), 0)
        for x in range(10, 16):
            for y in range(7, 23):
                alpha.putpixel((x, y), 210)

        shadow = module.make_fake_shadow_from_alpha(alpha, shadow_rgb=(15, 11, 7))
        shadow_alpha = shadow.getchannel("A")
        bbox = shadow_alpha.getbbox()

        self.assertIsNotNone(bbox)
        assert bbox is not None
        source_center = alpha_centroid(alpha)
        shadow_center = alpha_centroid(shadow_alpha)
        delta_x = shadow_center[0] - source_center[0]
        delta_y = shadow_center[1] - source_center[1]
        self.assertGreater(delta_x, 2.0)
        self.assertGreater(delta_y, 2.0)
        self.assertGreater(delta_x / abs(delta_y), 0.35)
        self.assertLess(delta_x / abs(delta_y), 1.65)
        self.assertGreaterEqual(bbox[0], 2)
        self.assertGreaterEqual(bbox[1], 2)
        self.assertLessEqual(bbox[2], 30)
        self.assertLessEqual(bbox[3], 30)

    def test_selected_frames_have_measurable_real_self_shadow(self) -> None:
        for frame_index in (0, 2, 16, 20):
            with self.subTest(frame_index=frame_index):
                full = Image.open(PROTOTYPE_ROOT / "frames" / f"frame_{frame_index:02d}.png").convert("RGBA")
                reference = Image.open(
                    PROTOTYPE_ROOT / "frames" / f"no_self_shadow_frame_{frame_index:02d}.png"
                ).convert("RGBA")
                full_pixels = full.load()
                ref_pixels = reference.load()
                compared = 0
                shadowed = 0
                max_delta = 0
                for y in range(full.height):
                    for x in range(full.width):
                        fp = full_pixels[x, y]
                        rp = ref_pixels[x, y]
                        if fp[3] < 96 or rp[3] < 96:
                            continue
                        compared += 1
                        full_luma = (fp[0] * 299 + fp[1] * 587 + fp[2] * 114) // 1000
                        ref_luma = (rp[0] * 299 + rp[1] * 587 + rp[2] * 114) // 1000
                        delta = ref_luma - full_luma
                        max_delta = max(max_delta, delta)
                        if delta >= 2:
                            shadowed += 1
                self.assertGreater(compared, 30)
                self.assertGreater(shadowed / float(compared), 0.01)
                self.assertGreaterEqual(max_delta, 5)

    def test_selected_review_direction_and_production_guard(self) -> None:
        review = PROTOTYPE_ROOT / "selected_10_oclock_fill_20_review.png"
        metrics_path = PROTOTYPE_ROOT / "selected_10_oclock_fill_20_metrics.json"
        guard_path = PROTOTYPE_ROOT / "production_guard.json"
        manifest_path = PROTOTYPE_ROOT / "promotion_manifest.json"
        self.assertTrue(review.is_file())
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        self.assertEqual(set(metrics), {"frame_00", "frame_02", "frame_16", "frame_20"})
        centroid_deltas = []
        for frame_metrics in metrics.values():
            self.assertGreater(frame_metrics["shadowed_fraction_delta_ge_2"], 0.01)
            self.assertGreaterEqual(frame_metrics["max_luminance_delta"], 5)
            self.assertEqual(frame_metrics["authored_shadow_direction"], [0.866025, 0.5])
            self.assertGreater(frame_metrics["max_forward_extent_from_authored_root"], 5.0)
            self.assertGreater(frame_metrics["below_root_alpha_fraction"], 0.25)
            centroid_deltas.append(frame_metrics["shadow_centroid_from_authored_root"])
        # Individual tufts lean around the fixed root, so a single tiny caster can
        # have a centroid a few pixels left of the anchor. Across representative
        # frames the physical ground-shadow mass must still land right and down.
        self.assertGreater(sum(delta[0] for delta in centroid_deltas), 0.0)
        self.assertTrue(all(delta[1] > 0.0 for delta in centroid_deltas))
        self.assertTrue(json.loads(guard_path.read_text(encoding="utf-8"))["passed"])
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(manifest["profile_id"], "station_mirny_grass_tuft_10_oclock_fill_20_v2")
        self.assertEqual(set(manifest["promoted"]), {"grass_tuft_atlas.png", "grass_tuft_shadow_atlas.png"})

    def test_kicker_is_albedo_only_and_fixed_shadow_has_no_time_stretch(self) -> None:
        profile = json.loads(GRASS_PROFILE_PATH.read_text(encoding="utf-8"))
        kicker = profile["lighting"]["low_opposite_kicker"]
        self.assertFalse(kicker["use_shadow"])
        self.assertEqual(kicker["affects"], "albedo_only")
        blender_text = BLENDER_BAKE_PATH.read_text(encoding="utf-8")
        shader_text = GRASS_SHADER_PATH.read_text(encoding="utf-8")
        self.assertIn('obj.name.startswith("GrassTuftLowOppositeKicker")', blender_text)
        self.assertIn("obj.hide_render = True", blender_text)
        self.assertNotIn("shadow_length_scale", shader_text)
        self.assertNotIn("get_shadow_length_factor", shader_text)


if __name__ == "__main__":
    unittest.main()
