"""Run isolated screen 9:30 Sun, 12% kicker, and physical shadow proof."""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path

from run_layered_tree_brightness_variants import production_hashes


ROOT = Path(__file__).resolve().parents[2]
SOURCE_GLB = Path("C:/Users/progi/project-Mirniy/tree glb/1.glb")
BASE_PROFILE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075" / "profile.json"
NINE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_9_oclock_fill_08"
TEN = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_10_oclock_fill_12"
TEN_CAST = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075"
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_9_30_fill_12"
BAKE = Path(__file__).with_name("blender_layered_tree_asset_bake.py")
POST = Path(__file__).with_name("postprocess_layered_tree_asset.py")
DIAGNOSTIC = Path(__file__).with_name("blender_layered_tree_9_oclock_fill_diagnostic.py")
SELF_REPORT = Path(__file__).with_name("build_layered_tree_self_shadow_report.py")
REVIEW = Path(__file__).with_name("build_layered_tree_9_30_fill_12_review.py")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    before = production_hashes()
    profile = copy.deepcopy(json.loads(BASE_PROFILE.read_text(encoding="utf-8")))
    profile["profile_id"] = "station_mirny_tree_sun_9_30_fill_12_proof"
    profile["version"] = 4
    profile["lighting"].update({
        "sun_azimuth_degrees": 245.0,
        "screen_sun_direction": "west_north_west_9_30_oclock",
        "fixed_shadow_direction": "screen_east_south_east_3_30",
        "fixed_shadow_direction_vector_screen": [0.965926, 0.258819],
        "ambient_fill": {"enabled": False},
        "fill_energy": 0.0,
    })
    profile["runtime"]["sun_shadow_mode"] = "baked_fixed_east_south_east_3_30_stretch_only"
    profile_path = OUT / "profile.json"
    profile_path.write_text(json.dumps(profile, indent="\t"), encoding="utf-8")

    base_asset = OUT / "base_asset_00"
    run([str(args.blender), "--background", "--factory-startup", "--python", str(BAKE), "--", "--glb", str(SOURCE_GLB), "--out-dir", str(base_asset), "--profile", str(profile_path), "--yaw-degrees", "90"])
    run([sys.executable, "-B", str(POST), str(base_asset), "--profile", str(profile_path)])
    diagnostic_dir = OUT / "diagnostic"
    run([
        str(args.blender), "--background", "--factory-startup", "--python", str(DIAGNOSTIC), "--",
        "--glb", str(SOURCE_GLB), "--profile", str(profile_path), "--out-dir", str(diagnostic_dir),
        "--target-lift", "12", "--spot-x", "2.45", "--spot-y", "-1.025",
        "--spot-screen-side", "east_south_east_opposite_9_30_oclock_sun", "--file-prefix", "sun_9_30_fill",
    ])
    if not (diagnostic_dir / "manifest.json").is_file():
        raise RuntimeError("9:30 / 12% diagnostic did not produce manifest")
    run([sys.executable, "-B", str(SELF_REPORT), str(diagnostic_dir / "self_shadow")])
    run([
        sys.executable, "-B", str(REVIEW), "--proof-dir", str(OUT), "--nine-dir", str(NINE),
        "--ten-dir", str(TEN), "--ten-cast-dir", str(TEN_CAST),
    ])
    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (OUT / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Production changed during isolated 9:30 / 12% proof")
    print(f"Wrote isolated 9:30 / 12% proof to {OUT}")


if __name__ == "__main__":
    main()
