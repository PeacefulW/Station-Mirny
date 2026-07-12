"""Focused checks for the isolated 8% candidate at gameplay hour 21:00."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
PROOF_ROOT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "low_rear_fill_10_oclock"
CANDIDATE = PROOF_ROOT / "candidate_08"
LAB = PROOF_ROOT / "lab_21h"
BASE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075"


class LayeredTreeLowRearFill21hTest(unittest.TestCase):
    def test_candidate_is_complete_and_preserves_geometry_contract(self) -> None:
        required = {
            "albedo.png", "trunk.png", "foliage.png", "shadow.png", "wind_mask.png",
            "snow_mask.png", "snow_overlay.png", "season_mask.png", "height.png", "normal.png", "meta.json",
        }
        self.assertTrue(required.issubset({path.name for path in CANDIDATE.iterdir() if path.is_file()}))
        base_meta = json.loads((BASE / "meta.json").read_text(encoding="utf-8"))
        candidate_meta = json.loads((CANDIDATE / "meta.json").read_text(encoding="utf-8"))
        self.assertEqual(candidate_meta["anchor"], base_meta["anchor"])
        self.assertEqual(candidate_meta["frame_width"], base_meta["frame_width"])
        self.assertEqual(candidate_meta["frame_height"], base_meta["frame_height"])
        self.assertEqual(
            Image.open(CANDIDATE / "albedo.png").getchannel("A").getbbox(),
            Image.open(BASE / "albedo.png").getchannel("A").getbbox(),
        )
        self.assertIsNone(ImageChops.difference(
            Image.open(CANDIDATE / "shadow.png").convert("RGBA"),
            Image.open(BASE / "shadow.png").convert("RGBA"),
        ).getbbox())

    def test_probe_uses_exact_21h_darkness_contract(self) -> None:
        snapshots = json.loads((LAB / "snapshots.json").read_text(encoding="utf-8"))
        self.assertEqual(len(snapshots), 2)
        self.assertEqual({float(item["lift_percent"]) for item in snapshots}, {0.0, 8.0})
        for item in snapshots:
            self.assertEqual(float(item["world_hour"]), 21.0)
            self.assertEqual([round(float(value), 3) for value in item["ambient_color"][:3]], [0.03, 0.035, 0.05])
            self.assertEqual(float(item["direct_sun_energy"]), 0.0)
            self.assertFalse(bool(item["direct_sun_enabled"]))
            self.assertEqual(float(item["sun_cast_shadow_visibility"]), 0.0)
            self.assertFalse(bool(item["torch_enabled"]))
            self.assertEqual(int(item["local_light_count"]), 0)

    def test_raw_candidate_stays_night_dark_and_non_emissive(self) -> None:
        metrics = json.loads((LAB / "metrics.json").read_text(encoding="utf-8"))
        baseline = metrics["baseline_00"]
        candidate = metrics["candidate_08"]
        self.assertLess(candidate["mean"], 16.0)
        self.assertLess(candidate["p90"], 24.0)
        self.assertLess(candidate["mean"] - baseline["mean"], 3.0)
        self.assertGreaterEqual(candidate["mean"], baseline["mean"])

    def test_review_and_production_guard(self) -> None:
        self.assertTrue((LAB / "night_21h_review_sheet.png").is_file())
        guard = json.loads((LAB / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        self.assertEqual(guard["before"], guard["after"])


if __name__ == "__main__":
    unittest.main()
