"""Run isolated screen 10 o'clock Sun plus calibrated 12% kicker proof."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from run_layered_tree_brightness_variants import production_hashes


ROOT = Path(__file__).resolve().parents[2]
SOURCE_GLB = Path("C:/Users/progi/project-Mirniy/tree glb/1.glb")
PROFILE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075" / "profile.json"
CAST_ASSET = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075"
TEN_EIGHT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "low_rear_fill_10_oclock"
NINE_EIGHT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_9_oclock_fill_08"
OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "sun_10_oclock_fill_12"
DIAGNOSTIC = Path(__file__).with_name("blender_layered_tree_9_oclock_fill_diagnostic.py")
SELF_REPORT = Path(__file__).with_name("build_layered_tree_self_shadow_report.py")
REVIEW = Path(__file__).with_name("build_layered_tree_10_oclock_fill_12_review.py")


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
    diagnostic_dir = OUT / "diagnostic"
    run([
        str(args.blender), "--background", "--factory-startup", "--python", str(DIAGNOSTIC), "--",
        "--glb", str(SOURCE_GLB), "--profile", str(PROFILE), "--out-dir", str(diagnostic_dir),
        "--target-lift", "12", "--spot-x", "2.25", "--spot-y", "-2.05",
        "--spot-screen-side", "east_south_east_opposite_10_oclock_sun", "--file-prefix", "sun_10_fill",
    ])
    if not (diagnostic_dir / "manifest.json").is_file():
        raise RuntimeError("10 o'clock / 12% diagnostic did not produce manifest")
    run([sys.executable, "-B", str(SELF_REPORT), str(diagnostic_dir / "self_shadow")])
    run([
        sys.executable, "-B", str(REVIEW), "--proof-dir", str(OUT), "--ten-eight-dir", str(TEN_EIGHT),
        "--nine-eight-dir", str(NINE_EIGHT), "--cast-asset-dir", str(CAST_ASSET),
    ])
    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (OUT / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Production changed during isolated 10 o'clock / 12% proof")
    print(f"Wrote isolated 10 o'clock / 12% proof to {OUT}")


if __name__ == "__main__":
    main()
