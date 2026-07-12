"""Focused checks for the west 9 o'clock Sun plus 8% kicker proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_9_oclock_fill_08"


class LayeredTree9OclockFillTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile = json.loads((OUT / "profile.json").read_text(encoding="utf-8"))
        cls.metrics = json.loads((OUT / "metrics.json").read_text(encoding="utf-8"))

    def test_profile_is_west_sun_and_east_cast(self) -> None:
        lighting = self.profile["lighting"]
        self.assertEqual(lighting["sun_azimuth_degrees"], 270.0)
        self.assertEqual(lighting["screen_sun_direction"], "west_9_oclock")
        self.assertEqual(lighting["fixed_shadow_direction"], "screen_east")
        self.assertEqual(lighting["fixed_shadow_direction_vector_screen"], [1.0, 0.0])
        self.assertLessEqual(abs(self.metrics["physical_cast_shadow"]["screen_angle_degrees"]), 2.0)

    def test_kicker_is_low_east_shadowless_and_measured_eight_percent(self) -> None:
        kicker = self.metrics["kicker"]
        calibration = self.metrics["calibration"]
        self.assertIn("east_opposite_9_oclock", kicker["screen_side"])
        self.assertEqual(kicker["placement"], "low")
        self.assertFalse(kicker["use_shadow"])
        self.assertGreater(kicker["location"][0], 0.0)
        self.assertAlmostEqual(kicker["location"][1], 0.0, delta=0.001)
        self.assertAlmostEqual(calibration["measured_trunk_lift_percent"], 8.0, delta=0.15)

    def test_primary_retains_physical_self_shadow(self) -> None:
        self_shadow = self.metrics["self_shadow"]
        strict = json.loads((OUT / "diagnostic" / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(strict["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertEqual(strict["candidate_lift_percent"], 8.0)
        self.assertGreater(self_shadow["delta_ge_2_fraction"], 0.10)
        self.assertGreater(self_shadow["delta_max_8bit"], 20)

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((OUT / "sun_9_oclock_review_sheet.png").is_file())
        self.assertTrue((OUT / "sun_9_oclock_closeups.png").is_file())
        self.assertTrue((OUT / "sun_9_oclock_shadow_proof.png").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
