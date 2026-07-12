"""Focused contract checks for the fixed-light candidate-A turntable proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "turntable"
EXPECTED = ["south", "south_west", "west", "north_west", "north", "north_east", "east", "south_east"]


class LayeredTreeTurntableTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))

    def test_exact_compass_views_exist(self) -> None:
        self.assertEqual([view["id"] for view in self.manifest["views"]], EXPECTED)
        for view in self.manifest["views"]:
            image_path = OUT / view["file"]
            self.assertTrue(image_path.is_file())
            with Image.open(image_path) as image:
                self.assertGreater(image.convert("RGBA").getchannel("A").getbbox()[2], 0)

    def test_candidate_a_keeps_physical_fixed_light(self) -> None:
        self.assertEqual(self.manifest["candidate"], "A")
        self.assertTrue(self.manifest["tree_and_lights_fixed"])
        self.assertTrue(self.manifest["camera_only_orbit"])
        self.assertTrue(self.manifest["sun"]["use_shadow"])
        self.assertEqual(self.manifest["sun"]["screen_direction"], "north_west")
        self.assertFalse(self.manifest["render"]["ambient_fill_enabled"])
        self.assertEqual(self.manifest["render"]["fill_energy"], 0.0)

    def test_review_artifacts_and_guard_exist(self) -> None:
        self.assertTrue((OUT / "turntable_sheet.png").is_file())
        self.assertTrue((OUT / "west_closeup.png").is_file())
        self.assertTrue((OUT / "metrics.json").is_file())
        guard = json.loads((OUT / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])


if __name__ == "__main__":
    unittest.main()
