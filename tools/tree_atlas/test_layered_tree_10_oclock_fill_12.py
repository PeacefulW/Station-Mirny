"""Focused checks for screen 10 o'clock Sun plus 12% kicker proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_10_oclock_fill_12"


class LayeredTree10OclockFill12Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.metrics = json.loads((OUT / "metrics.json").read_text(encoding="utf-8"))

    def test_reuses_ten_oclock_physical_sun(self) -> None:
        sun = self.metrics["sun"]
        self.assertEqual(sun["screen_direction"], "west_north_west_10_oclock")
        self.assertEqual(sun["azimuth_degrees"], 219.0)
        self.assertTrue(sun["use_shadow"])
        angle = self.metrics["physical_cast_shadow"]["screen_angle_degrees"]
        self.assertGreaterEqual(angle, 20.0)
        self.assertLessEqual(angle, 38.0)

    def test_kicker_is_shadowless_and_measured_twelve_percent(self) -> None:
        kicker = self.metrics["kicker"]
        calibration = self.metrics["calibration"]
        self.assertIn("opposite_10_oclock", kicker["screen_side"])
        self.assertEqual(kicker["placement"], "low")
        self.assertFalse(kicker["use_shadow"])
        self.assertAlmostEqual(calibration["measured_trunk_lift_percent"], 12.0, delta=0.15)
        self.assertGreater(calibration["measured_dark_foliage_lift_percent"], 0.0)

    def test_physical_self_shadow_remains(self) -> None:
        strict = json.loads((OUT / "diagnostic" / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(strict["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertEqual(strict["candidate_lift_percent"], 12.0)
        self.assertGreater(self.metrics["self_shadow"]["delta_ge_2_fraction"], 0.10)
        self.assertGreater(self.metrics["self_shadow"]["delta_max_8bit"], 20)

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((OUT / "sun_10_oclock_fill_12_review_sheet.png").is_file())
        self.assertTrue((OUT / "sun_10_oclock_fill_12_closeups.png").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
