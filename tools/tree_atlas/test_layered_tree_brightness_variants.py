"""Focused acceptance checks for the isolated A/B/C brightness proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "tools" / "tree_atlas" / "layered_tree_brightness_variants_manifest.json"
OUTPUT_ROOT = ROOT / "artifacts" / "layered_tree_brightness_variants"


class LayeredTreeBrightnessVariantsTest(unittest.TestCase):
    def test_manifest_defines_exactly_the_three_approved_variants(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        variants = {item["id"]: item for item in manifest["variants"]}
        self.assertEqual(
            set(variants),
            {"a_exposure_080", "b_ambient_070", "c_clock_10_exposure_075"},
        )
        self.assertEqual(variants["a_exposure_080"]["overrides"]["render"]["exposure"], 0.8)
        self.assertFalse(variants["a_exposure_080"]["overrides"]["lighting"]["ambient_fill"]["enabled"])
        ambient = variants["b_ambient_070"]["overrides"]["lighting"]["ambient_fill"]
        self.assertEqual(variants["b_ambient_070"]["overrides"]["render"]["exposure"], 0.7)
        self.assertTrue(ambient["enabled"])
        self.assertEqual(ambient["light_count"], 4)
        self.assertEqual(ambient["total_energy"], 128.0)
        self.assertEqual(variants["c_clock_10_exposure_075"]["overrides"]["render"]["exposure"], 0.75)
        self.assertEqual(variants["c_clock_10_exposure_075"]["overrides"]["lighting"]["sun_azimuth_degrees"], 219.0)

    def test_candidates_keep_complete_physical_shadow_and_self_shadow(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        required = {
            "albedo.png",
            "trunk.png",
            "foliage.png",
            "shadow_raw.png",
            "shadow.png",
            "classification.json",
            "meta.json",
            "profile.json",
            "preview_panel.png",
        }
        for item in manifest["variants"]:
            asset_dir = OUTPUT_ROOT / item["id"]
            with self.subTest(variant=item["id"]):
                self.assertTrue(required.issubset({path.name for path in asset_dir.iterdir() if path.is_file()}))
                classification = json.loads((asset_dir / "classification.json").read_text(encoding="utf-8"))
                self.assertEqual(classification.get("suppressed_shadow_casters", []), [])
                manifest_ab = json.loads((asset_dir / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
                metrics_ab = json.loads((asset_dir / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
                self.assertEqual(manifest_ab["controlled_difference"], "LayeredTreeSun.data.use_shadow")
                self.assertGreater(metrics_ab["delta_ge_2_fraction"], 0.10)
                self.assertGreater(metrics_ab["delta_max_8bit"], 20)

    def test_brightness_and_cast_direction_metrics_match_the_brief(self) -> None:
        metrics = json.loads((OUTPUT_ROOT / "metrics.json").read_text(encoding="utf-8"))
        baseline = metrics["baseline_production"]["luminance"]["mean"]
        variants = metrics["variants"]
        for variant_id in variants:
            self.assertGreater(variants[variant_id]["luminance"]["mean"], baseline, variant_id)
        for variant_id in ("a_exposure_080", "b_ambient_070"):
            self.assertGreaterEqual(variants[variant_id]["shadow_screen_angle_degrees"], 38.0)
            self.assertLessEqual(variants[variant_id]["shadow_screen_angle_degrees"], 52.0)
        c_angle = variants["c_clock_10_exposure_075"]["shadow_screen_angle_degrees"]
        self.assertGreaterEqual(c_angle, 20.0)
        self.assertLess(c_angle, 38.0)

    def test_review_sheet_and_production_guard_exist(self) -> None:
        self.assertTrue((OUTPUT_ROOT / "brightness_review_sheet.png").is_file())
        guard = json.loads((OUTPUT_ROOT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
