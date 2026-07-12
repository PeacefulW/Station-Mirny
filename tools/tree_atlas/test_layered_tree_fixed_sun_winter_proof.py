"""Focused acceptance checks for the isolated tree_01 fixed-sun winter proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image

from build_layered_tree_proof_report import collect_metrics


ROOT = Path(__file__).resolve().parents[2]
PROFILE_PATH = ROOT / "tools" / "tree_atlas" / "layered_asset_bake_profile_v2_proof.json"
CANDIDATE_DIR = ROOT / "artifacts" / "layered_tree_01_nw_winter_proof" / "candidate_v3_physical"
SELF_SHADOW_DIR = (
    ROOT
    / "artifacts"
    / "layered_tree_01_nw_winter_proof"
    / "self_shadow_diagnostic"
    / "strict_ab_v3_physical"
)
LAB_DIR = ROOT / "artifacts" / "layered_tree_01_nw_winter_proof" / "lab"
FROZEN_FOLIAGE_SHADER_PATH = ROOT / "scenes" / "dev" / "layered_tree_asset_lab_frozen_foliage.gdshader"


class LayeredTreeFixedSunWinterProofTest(unittest.TestCase):
    def test_profile_encodes_fixed_screen_compass_contract(self) -> None:
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(profile["profile_id"], "station_mirny_layered_tree_fixed_nw_winter_proof_v2")
        self.assertEqual(profile["version"], 2)
        self.assertAlmostEqual(profile["lighting"]["sun_azimuth_degrees"], 205.201124, places=5)
        self.assertAlmostEqual(profile["lighting"]["albedo_sun_elevation_degrees"], 38.0, places=5)
        self.assertAlmostEqual(profile["lighting"]["albedo_sun_angular_diameter_degrees"], 4.0, places=5)
        self.assertAlmostEqual(profile["lighting"]["fill_energy"], 0.0, places=5)
        self.assertAlmostEqual(profile["render"]["exposure"], 0.5, places=5)
        self.assertEqual(profile["lighting"]["screen_sun_direction"], "north_west")
        self.assertEqual(profile["lighting"]["fixed_shadow_direction"], "screen_south_east")
        self.assertEqual(profile["lighting"]["fixed_shadow_direction_vector_screen"], [0.707107, 0.707107])
        self.assertEqual(profile["runtime"]["sun_shadow_mode"], "baked_fixed_south_east_stretch_only")
        self.assertAlmostEqual(profile["runtime"]["shadow_contact_lock_source_px"], 48.0, places=5)
        self.assertNotIn("shadow_casters", profile)
        self.assertNotIn("root_shadow_footprint", profile["postprocess"])

    def test_candidate_contains_complete_layered_pass_set(self) -> None:
        required = {
            "albedo.png",
            "trunk.png",
            "foliage.png",
            "shadow_raw.png",
            "classification.json",
            "shadow.png",
            "wind_mask.png",
            "snow_mask.png",
            "snow_overlay.png",
            "season_mask.png",
            "height.png",
            "normal.png",
            "meta.json",
            "preview_panel.png",
        }
        self.assertTrue(CANDIDATE_DIR.is_dir(), "Run the candidate proof bake before acceptance tests.")
        actual = {
            path.name
            for path in CANDIDATE_DIR.iterdir()
            if path.is_file() and not path.name.endswith(".import")
        }
        self.assertEqual(required, actual)

    def test_shadow_points_screen_south_east(self) -> None:
        metrics = collect_metrics(CANDIDATE_DIR)
        delta_x, delta_y = metrics["shadow_centroid_delta"]
        self.assertGreater(delta_x, 0.0)
        self.assertGreater(delta_y, 0.0)
        self.assertGreaterEqual(metrics["shadow_screen_angle_degrees"], 38.0)
        self.assertLessEqual(metrics["shadow_screen_angle_degrees"], 52.0)

    def test_visible_geometry_and_shadow_receiver_share_the_ground_plane(self) -> None:
        profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        classification = json.loads((CANDIDATE_DIR / "classification.json").read_text(encoding="utf-8"))
        receiver_z = -0.012
        geometry_min_z = min(float(item["min_z"]) for item in classification["classification"].values())
        self.assertAlmostEqual(profile["planting"]["root_embed_fraction"], 0.011, places=6)
        self.assertAlmostEqual(float(classification["root_embed_fraction"]), 0.011, places=6)
        self.assertGreater(geometry_min_z, receiver_z)
        self.assertLessEqual(geometry_min_z - receiver_z, 0.0011)
        self.assertNotIn("root_contact_shadow", profile["postprocess"])

        self.assertEqual(classification.get("suppressed_shadow_casters", []), [])

        anchor_x, anchor_y = (int(value) for value in classification["anchor"])
        raw_shadow_alpha = Image.open(CANDIDATE_DIR / "shadow_raw.png").convert("RGBA").getchannel("A")
        strong_contact_distances = [
            (x - anchor_x) ** 2 + (y - anchor_y) ** 2
            for y in range(max(0, anchor_y - 8), min(raw_shadow_alpha.height, anchor_y + 9))
            for x in range(max(0, anchor_x - 8), min(raw_shadow_alpha.width, anchor_x + 9))
            if raw_shadow_alpha.getpixel((x, y)) > 192
        ]
        self.assertTrue(strong_contact_distances)
        self.assertLessEqual(min(strong_contact_distances), 64)

    def test_processed_shadow_preserves_the_physical_root_footprint(self) -> None:
        classification = json.loads((CANDIDATE_DIR / "classification.json").read_text(encoding="utf-8"))
        anchor_x, anchor_y = (int(value) for value in classification["anchor"])
        shadow_alpha = Image.open(CANDIDATE_DIR / "shadow.png").convert("RGBA").getchannel("A")
        root_pixels = [
            shadow_alpha.getpixel((x, y))
            for y in range(max(0, anchor_y - 32), min(shadow_alpha.height, anchor_y + 28))
            for x in range(max(0, anchor_x - 55), min(shadow_alpha.width, anchor_x + 56))
        ]
        forward_pixels = [
            shadow_alpha.getpixel((x, y))
            for y in range(anchor_y + 42, min(shadow_alpha.height, anchor_y + 130))
            for x in range(anchor_x + 35, min(shadow_alpha.width, anchor_x + 145))
        ]
        root_mean = sum(root_pixels) / max(len(root_pixels), 1)
        self.assertGreater(root_mean, 70.0)
        self.assertGreater(max(forward_pixels, default=0), 80)

    def test_strict_self_shadow_pair_changes_only_shadow_casting(self) -> None:
        manifest = json.loads((SELF_SHADOW_DIR / "manifest.json").read_text(encoding="utf-8"))
        metrics = json.loads((SELF_SHADOW_DIR / "metrics.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertTrue(manifest["on_value"])
        self.assertFalse(manifest["off_value"])
        self.assertFalse(manifest["fill_use_shadow"])
        self.assertAlmostEqual(float(manifest["sun_elevation_degrees"]), 38.0, places=5)
        self.assertAlmostEqual(float(manifest["sun_angular_diameter_degrees"]), 4.0, places=5)
        self.assertAlmostEqual(float(manifest["fill_energy"]), 0.0, places=5)
        self.assertAlmostEqual(float(manifest["exposure"]), 0.5, places=5)
        self.assertGreater(float(metrics["delta_ge_2_fraction"]), 0.30)
        self.assertGreater(int(metrics["delta_max_8bit"]), 40)

    def test_lab_captures_pinned_physical_shadow_and_full_foliage_winter(self) -> None:
        snapshots = json.loads((LAB_DIR / "snapshots.json").read_text(encoding="utf-8"))
        by_capture = {str(item["capture"]): item for item in snapshots}
        required = {
            "root_shadow_physical_13h",
            "root_shadow_physical_14_5h",
            "root_shadow_physical_16h",
            "summer_full_foliage",
            "early_winter_frost_035",
            "deep_winter_snow_070",
            "full_winter_frozen_100",
            "thawed_after_full_winter",
        }
        self.assertEqual(required, set(by_capture))
        for item in by_capture.values():
            self.assertEqual(item["shadow_direction_screen"], "south_east")
            self.assertEqual(float(item["wind_strength_px"]), 0.0)
            self.assertNotIn("leaf_drop_strength", item)
            self.assertTrue(Path(item["path"]).is_file())
        dawn = by_capture["root_shadow_physical_13h"]
        neutral = by_capture["root_shadow_physical_14_5h"]
        dusk = by_capture["root_shadow_physical_16h"]
        self.assertGreater(float(dawn["shadow_length_scale"]), 1.8)
        self.assertEqual(float(neutral["shadow_length_scale"]), 1.0)
        self.assertGreater(float(dusk["shadow_length_scale"]), 1.8)
        self.assertAlmostEqual(float(neutral["shadow_contact_lock_source_px"]), 48.0, places=5)
        for distance in ("0", "16", "32", "48"):
            for component in range(2):
                expected = float(neutral["shadow_probe_local_points"][distance][component])
                self.assertAlmostEqual(float(dawn["shadow_probe_local_points"][distance][component]), expected, places=4)
                self.assertAlmostEqual(float(dusk["shadow_probe_local_points"][distance][component]), expected, places=4)
        neutral_tip = neutral["shadow_probe_local_points"]["303"]
        dawn_tip = dawn["shadow_probe_local_points"]["303"]
        self.assertGreater(sum(float(value) ** 2 for value in dawn_tip), sum(float(value) ** 2 for value in neutral_tip))
        self.assertAlmostEqual(float(by_capture["early_winter_frost_035"]["season_amount"]), 0.35, places=5)
        self.assertAlmostEqual(float(by_capture["deep_winter_snow_070"]["season_amount"]), 0.70, places=5)
        self.assertEqual(float(by_capture["full_winter_frozen_100"]["season_amount"]), 1.0)
        self.assertEqual(float(by_capture["thawed_after_full_winter"]["season_amount"]), 0.0)

    def test_winter_keeps_foliage_alpha_and_disables_drop_mask(self) -> None:
        season_mask = Image.open(CANDIDATE_DIR / "season_mask.png").convert("RGBA")
        self.assertEqual(season_mask.getchannel("G").getextrema(), (0, 0))
        shader = FROZEN_FOLIAGE_SHADER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("leaf_drop", shader)
        self.assertNotIn("albedo.a", shader)

    def test_winter_overlay_preserves_trunk_roots_and_has_directional_relief(self) -> None:
        metrics = collect_metrics(CANDIDATE_DIR)
        self.assertLessEqual(metrics["visible_trunk_snow_alpha_mean"], 0.20)
        self.assertLessEqual(metrics["root_band_snow_alpha_mean"], 0.05)
        self.assertLessEqual(metrics["root_zone_64_snow_alpha_mean"], 0.05)
        self.assertGreaterEqual(metrics["foliage_dark_gap_fraction"], 0.15)
        self.assertGreaterEqual(metrics["foliage_covered_fraction"], 0.25)
        self.assertGreater(metrics["active_snow_luma_stddev"], 4.0)
        self.assertGreater(metrics["active_snow_luma_range"], 20.0)
        self.assertGreater(metrics["north_west_sample_count"], 100)
        self.assertGreater(metrics["south_east_sample_count"], 100)
        self.assertGreaterEqual(metrics["north_west_minus_south_east_luma"], 8.0)


if __name__ == "__main__":
    unittest.main()
