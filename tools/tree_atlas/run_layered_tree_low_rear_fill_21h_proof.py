"""Run the isolated 8% candidate and exact 21:00 lab comparison."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from run_layered_tree_brightness_variants import production_hashes


ROOT = Path(__file__).resolve().parents[2]
LAYERS_SCRIPT = Path(__file__).with_name("blender_layered_tree_low_rear_fill_layers.py")
CANDIDATE_SCRIPT = Path(__file__).with_name("build_layered_tree_low_rear_fill_candidate.py")
REVIEW_SCRIPT = Path(__file__).with_name("build_layered_tree_low_rear_fill_21h_review.py")
SOURCE_GLB = Path("C:/Users/progi/project-Mirniy/tree glb/1.glb")
PROOF_ROOT = ROOT / "artifacts" / "layered_tree_brightness_variants" / "low_rear_fill_10_oclock"
PROFILE = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075" / "profile.json"
BASE_DIR = ROOT / "artifacts" / "layered_tree_brightness_variants" / "c_clock_10_exposure_075"
LAYERS_DIR = PROOF_ROOT / "runtime_08_layers"
CANDIDATE_DIR = PROOF_ROOT / "candidate_08"
LAB_DIR = PROOF_ROOT / "lab_21h"
PROOF_MANIFEST = PROOF_ROOT / "manifest.json"
GODOT_PROBE = "res://tools/layered_tree_low_rear_fill_21h_probe.gd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    before = production_hashes()
    run([
        str(args.blender), "--background", "--factory-startup", "--python", str(LAYERS_SCRIPT), "--",
        "--glb", str(SOURCE_GLB), "--profile", str(PROFILE), "--proof-manifest", str(PROOF_MANIFEST),
        "--out-dir", str(LAYERS_DIR), "--target-lift", "8",
    ])
    if not (LAYERS_DIR / "manifest.json").is_file():
        raise RuntimeError("Blender did not produce split 8% layers")
    run([
        sys.executable, "-B", str(CANDIDATE_SCRIPT), "--base-dir", str(BASE_DIR),
        "--layers-dir", str(LAYERS_DIR), "--proof-manifest", str(PROOF_MANIFEST), "--out-dir", str(CANDIDATE_DIR),
    ])
    run([
        str(args.godot), "--path", str(ROOT), "--rendering-method", "gl_compatibility",
        "--audio-driver", "Dummy", "--script", GODOT_PROBE,
    ])
    snapshots_path = LAB_DIR / "snapshots.json"
    if not snapshots_path.is_file() or len(json.loads(snapshots_path.read_text(encoding="utf-8"))) != 2:
        raise RuntimeError("Godot 21:00 probe did not produce exactly two captures")
    run([sys.executable, "-B", str(REVIEW_SCRIPT), "--lab-dir", str(LAB_DIR), "--candidate-dir", str(CANDIDATE_DIR)])
    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (LAB_DIR / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Production changed during isolated 21:00 proof")
    print(f"Wrote isolated 21:00 proof to {LAB_DIR}")


if __name__ == "__main__":
    main()
