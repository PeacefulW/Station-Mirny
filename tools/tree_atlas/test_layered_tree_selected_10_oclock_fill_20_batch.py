"""Production checks for the selected lamp-100/root-7% six-tree batch."""

from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_layered_tree_proof_report import collect_metrics


ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "tools" / "tree_atlas" / "layered_tree_bake_profile_10_oclock_fill_20.json"
MANIFEST = ROOT / "tools" / "tree_atlas" / "layered_tree_10_oclock_fill_20_batch_manifest.json"
BATCH = ROOT / "artifacts" / "layered_tree_10_oclock_fill_20_batch"
PRODUCTION = ROOT / "assets" / "sprites" / "flora" / "layered_trees"
TREE_IDS = tuple(f"tree_{index:02d}" for index in range(1, 7))
RUNTIME_FILES = (
    "albedo.png", "trunk.png", "foliage.png", "shadow.png", "wind_mask.png",
    "snow_mask.png", "snow_overlay.png", "season_mask.png", "height.png",
    "normal.png", "meta.json", "preview_panel.png",
)


def content_sha256(path: Path) -> str:
    if path.suffix.lower() == ".png":
        image = Image.open(path).convert("RGBA")
        payload = image.width.to_bytes(4, "little") + image.height.to_bytes(4, "little") + image.tobytes()
        return hashlib.sha256(payload).hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()


class LayeredTreeSelected10OclockFill20BatchTest(unittest.TestCase):
    def test_profile_is_exact_selected_rig(self) -> None:
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        lighting = profile["lighting"]
        kicker = lighting["low_opposite_kicker"]
        self.assertEqual(profile["profile_id"], "station_mirny_layered_tree_10_oclock_lamp100_root7_v5")
        self.assertEqual(profile["version"], 5)
        self.assertEqual(profile["planting"]["root_embed_fraction"], 0.07)
        self.assertEqual(
            profile["planting"]["ground_clip"],
            {
                "enabled": True,
                "mode": "physical_mesh_bisect",
                "plane_z": 0.0,
                "bisect_distance": 0.00001,
                "max_remaining_below_plane": 0.00001,
            },
        )
        self.assertEqual(lighting["sun_azimuth_degrees"], 219.0)
        self.assertEqual(profile["render"]["exposure"], 0.75)
        self.assertEqual(lighting["fixed_shadow_direction_vector_screen"], [0.866025, 0.5])
        self.assertEqual(profile["runtime"]["shadow_contact_lock_source_px"], 48.0)
        self.assertEqual(kicker["position_x"], 2.25)
        self.assertEqual(kicker["position_y"], -2.05)
        self.assertEqual(kicker["height_fraction"], 0.08)
        self.assertEqual(kicker["target_height_fraction"], 0.43)
        self.assertEqual(kicker["energy"], 100.0)
        self.assertEqual(kicker["spot_size_degrees"], 52.0)
        self.assertEqual(kicker["spot_blend"], 0.88)
        self.assertFalse(kicker["use_shadow"])
        self.assertNotIn("shadow_casters", profile)

    def test_manifest_preserves_single_tree_06_yaw_exception(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        yaws = {item["tree_id"]: float(item["yaw_degrees"]) for item in manifest["trees"]}
        self.assertEqual(set(yaws), set(TREE_IDS))
        self.assertEqual([tree_id for tree_id, yaw in yaws.items() if yaw != 90.0], ["tree_06"])
        self.assertEqual(yaws["tree_06"], 180.0)

    def test_candidates_have_complete_physical_layers_and_metadata(self) -> None:
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        yaws = {item["tree_id"]: float(item["yaw_degrees"]) for item in manifest["trees"]}
        for tree_id in TREE_IDS:
            candidate = BATCH / "candidates" / tree_id
            classification = json.loads((candidate / "classification.json").read_text(encoding="utf-8"))
            meta = json.loads((candidate / "meta.json").read_text(encoding="utf-8"))
            self.assertEqual(classification.get("suppressed_shadow_casters", []), [], tree_id)
            ground_clip = classification["ground_clip"]
            self.assertEqual(ground_clip["mode"], "physical_mesh_bisect", tree_id)
            self.assertGreater(ground_clip["clipped_objects"], 0, tree_id)
            self.assertGreaterEqual(float(ground_clip["remaining_min_z"]), -0.00001, tree_id)
            self.assertEqual(float(classification["yaw_degrees"]), yaws[tree_id], tree_id)
            self.assertEqual(meta["bake_profile"]["profile_id"], "station_mirny_layered_tree_10_oclock_lamp100_root7_v5")
            self.assertEqual(meta["bake_profile"]["root_embed_fraction"], 0.07)
            self.assertEqual(meta["bake_profile"]["ground_clip"], profile["planting"]["ground_clip"])
            self.assertEqual(meta["bake_profile"]["low_opposite_kicker"]["energy"], 100.0)
            self.assertFalse(meta["bake_profile"]["low_opposite_kicker"]["use_shadow"])
            self.assertEqual(meta["bake_profile"]["shadow_contact_lock_source_px"], 48.0)
            self.assertEqual(meta["bake_profile"]["fixed_shadow_direction_vector_screen"], [0.866025, 0.5])
            self.assertEqual(Image.open(candidate / "season_mask.png").convert("RGBA").getchannel("G").getextrema(), (0, 0))
            metrics = collect_metrics(candidate)
            self.assertGreater(metrics["shadow_centroid_delta"][0], 0.0, tree_id)
            self.assertGreater(metrics["shadow_centroid_delta"][1], 0.0, tree_id)
            self.assertLessEqual(metrics["root_band_snow_alpha_mean"], 0.05, tree_id)

    def test_review_lab_and_production_copies_are_complete(self) -> None:
        self.assertTrue((BATCH / "selected_10_oclock_fill_20_batch_review.png").is_file())
        snapshots = json.loads((BATCH / "lab" / "snapshots.json").read_text(encoding="utf-8"))
        self.assertEqual(len(snapshots), 12)
        guard = json.loads((BATCH / "production_guard.json").read_text(encoding="utf-8"))
        self.assertTrue(guard["passed"])
        for tree_id in TREE_IDS:
            candidate = BATCH / "candidates" / tree_id
            production = PRODUCTION / tree_id
            for name in RUNTIME_FILES:
                self.assertEqual(
                    content_sha256(candidate / name),
                    content_sha256(production / name),
                    f"{tree_id}/{name}",
                )


if __name__ == "__main__":
    unittest.main()
