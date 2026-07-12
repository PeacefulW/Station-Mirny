"""Run the isolated candidate-A fixed-light turntable proof."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from run_layered_tree_brightness_variants import production_hashes


ROOT = Path(__file__).resolve().parents[2]
BLENDER_SCRIPT = Path(__file__).with_name("blender_layered_tree_turntable_diagnostic.py")
REVIEW_SCRIPT = Path(__file__).with_name("build_layered_tree_turntable_review.py")
DEFAULT_GLb = Path("C:/Users/progi/project-Mirniy/tree glb/1.glb")
DEFAULT_PROFILE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "a_exposure_080" / "profile.json"
DEFAULT_OUT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "turntable"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--glb", type=Path, default=DEFAULT_GLb)
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
            "--yaw-degrees",
            "90",
            "--frame-size",
            "768",
        ]
    )
    if not (out_dir / "manifest.json").is_file():
        raise RuntimeError("Blender turntable diagnostic did not produce manifest.json")
    run([sys.executable, "-B", str(REVIEW_SCRIPT), "--input-dir", str(out_dir)])
    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (out_dir / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Production files changed during isolated turntable proof")
    print(f"Wrote isolated turntable proof to {out_dir}")


if __name__ == "__main__":
    main()
