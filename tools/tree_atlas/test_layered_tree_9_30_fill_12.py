"""Focused checks for screen 9:30 Sun, 12% kicker, and physical shadow."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_9_30_fill_12"


class LayeredTree930Fill12Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile = json.loads((OUT / "profile.json").read_text(encoding="utf-8"))
        cls.metrics = json.loads((OUT / "metrics.json").read_text(encoding="utf-8"))

    def test_physical_shadow_is_near_expected_three_thirty_direction(self) -> None:
        lighting = self.profile["lighting"]
        self.assertEqual(lighting["screen_sun_direction"], "west_north_west_9_30_oclock")
        self.assertEqual(lighting["fixed_shadow_direction_vector_screen"], [0.965926, 0.258819])
        angle = self.metrics["physical_cast_shadow"]["screen_angle_degrees"]
        self.assertAlmostEqual(angle, 15.0, delta=2.0)
        comparisons = self.metrics["comparison_cast_angles_degrees"]
        self.assertLess(comparisons["9_00"], comparisons["9_30"])
        self.assertLess(comparisons["9_30"], comparisons["10_00"])

    def test_low_opposite_kicker_is_midway_and_measured_twelve_percent(self) -> None:
        kicker = self.metrics["kicker"]
        calibration = self.metrics["calibration"]
        self.assertIn("opposite_9_30", kicker["screen_side"])
        self.assertFalse(kicker["use_shadow"])
        self.assertAlmostEqual(kicker["location"][0], 2.45, delta=0.001)
        self.assertAlmostEqual(kicker["location"][1], -1.025, delta=0.001)
        self.assertAlmostEqual(calibration["measured_trunk_lift_percent"], 12.0, delta=0.15)

    def test_self_shadow_remains_physical(self) -> None:
        strict = json.loads((OUT / "diagnostic" / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(strict["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertEqual(strict["candidate_lift_percent"], 12.0)
        self.assertGreater(self.metrics["self_shadow"]["delta_ge_2_fraction"], 0.10)
        self.assertGreater(self.metrics["self_shadow"]["delta_max_8bit"], 20)

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((OUT / "sun_9_30_fill_12_with_shadow.png").is_file())
        self.assertTrue((OUT / "sun_9_30_shadow_directions.png").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
