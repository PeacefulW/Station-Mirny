"""Run the isolated 10 o'clock low rear fill proof and production guard."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from run_layered_tree_brightness_variants import production_hashes


ROOT = Path(__file__).resolve().parents[2]
BLENDER_SCRIPT = Path(__file__).with_name("blender_layered_tree_low_rear_fill_diagnostic.py")
REVIEW_SCRIPT = Path(__file__).with_name("build_layered_tree_low_rear_fill_review.py")
SELF_SHADOW_REPORT = Path(__file__).with_name("build_layered_tree_self_shadow_report.py")
DEFAULT_GLB = Path("C:/Users/progi/project-Mirniy/tree glb/1.glb")
DEFAULT_PROFILE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075" / "profile.json"
DEFAULT_OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "low_rear_fill_10_oclock"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--glb", type=Path, default=DEFAULT_GLB)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    before = production_hashes()
    run(
        [
            str(args.blender),
            "--background",
            "--factory-startup",
            "--python",
            str(BLENDER_SCRIPT),
            "--",
            "--glb",
            str(args.glb.resolve()),
            "--profile",
            str(args.profile.resolve()),
            "--out-dir",
            str(out_dir),
        ]
    )
    if not (out_dir / "manifest.json").is_file():
        raise RuntimeError("Blender low rear fill diagnostic did not produce manifest.json")
    run([sys.executable, "-B", str(REVIEW_SCRIPT), "--input-dir", str(out_dir)])
    run([sys.executable, "-B", str(SELF_SHADOW_REPORT), str(out_dir / "self_shadow")])
    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (out_dir / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Production files changed during isolated low rear fill proof")
    print(f"Wrote isolated low rear fill proof to {out_dir}")


if __name__ == "__main__":
    main()
