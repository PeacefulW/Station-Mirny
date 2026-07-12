"""Focused acceptance checks for the 10 o'clock low rear fill proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "low_rear_fill_10_oclock"


class LayeredTreeLowRearFillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))

    def test_exact_measured_lift_targets_and_primary(self) -> None:
        variants = self.manifest["variants"]
        self.assertEqual([item["target_lift_percent"] for item in variants], [0.0, 2.0, 4.0, 6.0, 8.0])
        self.assertEqual([item["target_lift_percent"] for item in variants if item["primary"]], [2.0])
        for item in variants:
            self.assertTrue((OUT / item["file"]).is_file())
            self.assertAlmostEqual(
                item["measured_trunk_lift_percent"], item["target_lift_percent"], delta=0.15
            )

    def test_spot_is_low_opposite_upward_and_shadowless(self) -> None:
        self.assertEqual(self.manifest["sun"]["screen_direction"], "west_north_west_10_oclock")
        self.assertTrue(self.manifest["sun"]["use_shadow"])
        kicker = self.manifest["kicker"]
        self.assertEqual(kicker["type"], "SPOT")
        self.assertEqual(kicker["placement"], "low")
        self.assertEqual(kicker["aim"], "upward_to_middle_lower_trunk")
        self.assertFalse(kicker["use_shadow"])
        self.assertIn("opposite_10_oclock_sun", kicker["screen_side"])
        self.assertTrue(all(self.manifest["fixed_scene"].values()))

    def test_primary_retains_sun_self_shadow(self) -> None:
        strict_manifest = json.loads((OUT / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
        strict_metrics = json.loads((OUT / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
        self.assertEqual(strict_manifest["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertEqual(strict_manifest["candidate_lift_percent"], 2.0)
        self.assertGreater(strict_metrics["delta_ge_2_fraction"], 0.10)
        self.assertGreater(strict_metrics["delta_max_8bit"], 20)

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((OUT / "low_rear_fill_review_sheet.png").is_file())
        self.assertTrue((OUT / "low_rear_fill_closeups.png").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
