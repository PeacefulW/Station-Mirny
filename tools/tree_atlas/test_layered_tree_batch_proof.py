"""Focused contract checks for the remaining-tree isolated batch proof."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image

from build_layered_tree_proof_report import collect_metrics


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "tools" / "tree_atlas" / "layered_tree_batch_proof_manifest.json"
BATCH_ROOT = ROOT / "artifacts" / "layered_tree_nw_winter_batch_proof"
CANDIDATE_ROOT = BATCH_ROOT / "candidates"
LAB_ROOT = BATCH_ROOT / "lab"
TREE_IDS = tuple(f"tree_{index:02d}" for index in range(2, 7))


class LayeredTreeBatchProofTest(unittest.TestCase):
    def test_manifest_records_one_explicit_yaw_exception(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        by_id = {str(item["tree_id"]): item for item in manifest["trees"]}
        self.assertEqual(set(by_id), set(TREE_IDS))
        exceptions = [item for item in by_id.values() if float(item["yaw_degrees"]) != 90.0]
        self.assertEqual(len(exceptions), 1)
        self.assertEqual(exceptions[0]["tree_id"], "tree_06")
        self.assertEqual(float(exceptions[0]["yaw_degrees"]), 180.0)

    def test_each_candidate_has_complete_physical_layered_passes(self) -> None:
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
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        yaws = {str(item["tree_id"]): float(item["yaw_degrees"]) for item in manifest["trees"]}
        for tree_id in TREE_IDS:
            candidate = CANDIDATE_ROOT / tree_id
            actual = {
                path.name
                for path in candidate.iterdir()
                if path.is_file() and not path.name.endswith(".import")
            }
            self.assertEqual(actual, required, tree_id)
            classification = json.loads((candidate / "classification.json").read_text(encoding="utf-8"))
            self.assertEqual(classification.get("suppressed_shadow_casters", []), [], tree_id)
            self.assertAlmostEqual(float(classification["yaw_degrees"]), yaws[tree_id], places=5)
            season = Image.open(candidate / "season_mask.png").convert("RGBA")
            self.assertEqual(season.getchannel("G").getextrema(), (0, 0), tree_id)

    def test_each_candidate_has_south_east_shadow_and_supported_snow(self) -> None:
        for tree_id in TREE_IDS:
            metrics = collect_metrics(CANDIDATE_ROOT / tree_id)
            delta_x, delta_y = metrics["shadow_centroid_delta"]
            self.assertGreater(delta_x, 0.0, tree_id)
            self.assertGreater(delta_y, 0.0, tree_id)
            self.assertLessEqual(metrics["visible_trunk_snow_alpha_mean"], 0.30, tree_id)
            self.assertLessEqual(metrics["root_band_snow_alpha_mean"], 0.05, tree_id)
            self.assertLessEqual(metrics["root_zone_64_snow_alpha_mean"], 0.05, tree_id)
            self.assertGreater(metrics["active_snow_pixel_count"], 500, tree_id)
            self.assertGreater(metrics["active_snow_luma_range"], 20.0, tree_id)

    def test_batch_lab_captures_summer_and_full_winter(self) -> None:
        snapshots = json.loads((LAB_ROOT / "snapshots.json").read_text(encoding="utf-8"))
        self.assertEqual(len(snapshots), 10)
        by_capture = {str(item["capture"]): item for item in snapshots}
        for tree_id in TREE_IDS:
            summer = by_capture[f"{tree_id}_summer"]
            winter = by_capture[f"{tree_id}_winter"]
            self.assertEqual(float(summer["season_amount"]), 0.0)
            self.assertEqual(float(winter["season_amount"]), 1.0)
            self.assertEqual(float(winter["effective_wind_strength_px"]), 0.0)
            self.assertTrue(Path(summer["path"]).is_file())
            self.assertTrue(Path(winter["path"]).is_file())


if __name__ == "__main__":
    unittest.main()
