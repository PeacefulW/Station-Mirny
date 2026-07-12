"""Focused checks for screen 10 o'clock Sun plus 20% kicker proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_10_oclock_fill_20"
TWELVE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_10_oclock_fill_12"


class LayeredTree10OclockFill20Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.metrics = json.loads((OUT / "metrics.json").read_text(encoding="utf-8"))
        cls.twelve = json.loads((TWELVE / "metrics.json").read_text(encoding="utf-8"))

    def test_reuses_exact_ten_oclock_physical_sun_and_shadow(self) -> None:
        self.assertEqual(self.metrics["sun"], self.twelve["sun"])
        self.assertEqual(self.metrics["profile"], self.twelve["profile"])
        self.assertAlmostEqual(
            self.metrics["physical_cast_shadow"]["screen_angle_degrees"],
            self.twelve["physical_cast_shadow"]["screen_angle_degrees"],
            delta=0.001,
        )

    def test_kicker_geometry_is_fixed_and_measured_twenty_percent(self) -> None:
        kicker = self.metrics["kicker"]
        baseline = self.twelve["kicker"]
        calibration = self.metrics["calibration"]
        for key in ("screen_side", "placement", "aim", "location", "target", "spot_size_degrees", "spot_blend", "use_shadow"):
            self.assertEqual(kicker[key], baseline[key])
        self.assertGreater(kicker["spot_energy"], baseline["spot_energy"])
        self.assertAlmostEqual(calibration["measured_trunk_lift_percent"], 20.0, delta=0.15)
        self.assertGreater(calibration["measured_dark_foliage_lift_percent"], 0.0)

    def test_physical_self_shadow_remains(self) -> None:
        strict = json.loads((OUT / "diagnostic" / "self_shadow" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(strict["controlled_difference"], "LayeredTreeSun.data.use_shadow")
        self.assertEqual(strict["candidate_lift_percent"], 20.0)
        self.assertGreater(self.metrics["self_shadow"]["delta_ge_2_fraction"], 0.10)
        self.assertGreater(self.metrics["self_shadow"]["delta_max_8bit"], 20)

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((OUT / "sun_10_fill_20_with_shadow.png").is_file())
        self.assertTrue((OUT / "sun_10_fill_12_vs_20_review.png").is_file())
        self.assertTrue((OUT / "sun_10_fill_12_vs_20_closeups.png").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
