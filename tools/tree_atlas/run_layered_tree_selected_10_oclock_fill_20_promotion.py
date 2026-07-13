"""Bake, review, promote, and verify the selected lamp-100/root-7% tree rig."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("layered_tree_10_oclock_fill_20_batch_manifest.json")
BAKE = Path(__file__).with_name("blender_layered_tree_asset_bake.py")
POSTPROCESS = Path(__file__).with_name("postprocess_layered_tree_asset.py")
REVIEW = Path(__file__).with_name("build_layered_tree_selected_10_oclock_fill_20_batch_review.py")
FOCUSED_TEST = "tools.tree_atlas.test_layered_tree_selected_10_oclock_fill_20_batch"
LAB_PROBE = "res://tools/layered_tree_selected_batch_lab_render_probe.gd"
RUNTIME_SMOKE = "res://tools/layered_tree_runtime_smoke_test.gd"
RUNTIME_FILES = (
    "albedo.png", "trunk.png", "foliage.png", "shadow.png", "wind_mask.png",
    "snow_mask.png", "snow_overlay.png", "season_mask.png", "height.png",
    "normal.png", "meta.json", "preview_panel.png",
)
FORBIDDEN_PATHS = (
    "tools/tree_atlas/layered_asset_bake_profile.json",
    "core/systems/world/layered_tree_object_layer.gd",
    "core/systems/world/world_streamer.gd",
    "core/systems/world/world_visual_lighting_profile.gd",
    "core/systems/world/world_runtime_constants.gd",
    "data/world_objects/placement_groups/plains_trees.tres",
    "project.godot",
    "assets/sprites/decor/plains/layered_small_rocks",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument(
        "--reuse-candidates",
        action="store_true",
        help="Reuse a complete candidate batch after a review-stage interruption.",
    )
    return parser.parse_args()


def resolve_repo_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def path_hashes() -> dict[str, str]:
    hashes: dict[str, str] = {}
    for value in FORBIDDEN_PATHS:
        path = ROOT / value
        if path.is_file():
            hashes[value] = sha256(path)
        elif path.is_dir():
            for child in sorted(item for item in path.rglob("*") if item.is_file()):
                hashes[child.relative_to(ROOT).as_posix()] = sha256(child)
    return hashes


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    profile = resolve_repo_path(str(manifest["profile"]))
    output_root = resolve_repo_path(str(manifest["output_root"]))
    batch_root = output_root.parent
    production_root = resolve_repo_path(str(manifest["production_root"]))
    output_root.mkdir(parents=True, exist_ok=True)
    before = path_hashes()

    for item in manifest["trees"]:
        tree_id = str(item["tree_id"])
        source_glb = resolve_repo_path(str(item["source_glb"]))
        candidate = output_root / tree_id
        yaw = float(item["yaw_degrees"])
        if args.reuse_candidates and all((candidate / name).is_file() for name in RUNTIME_FILES):
            print(f"Reusing complete selected production candidate {tree_id}", flush=True)
            continue
        print(f"Baking selected production candidate {tree_id}: yaw={yaw:.1f}", flush=True)
        run([
            str(args.blender), "--background", "--factory-startup", "--python", str(BAKE), "--",
            "--glb", str(source_glb), "--out-dir", str(candidate),
            "--profile", str(profile), "--yaw-degrees", str(yaw),
        ])
        run([sys.executable, "-B", str(POSTPROCESS), str(candidate), "--profile", str(profile)])

    run([
        str(args.godot), "--path", str(ROOT), "--rendering-method", "gl_compatibility",
        "--audio-driver", "Dummy", "--script", LAB_PROBE,
    ])
    run([sys.executable, "-B", str(REVIEW), str(batch_root)])

    promoted: dict[str, dict[str, str]] = {}
    for item in manifest["trees"]:
        tree_id = str(item["tree_id"])
        candidate = output_root / tree_id
        destination = production_root / tree_id
        run([
            sys.executable, "-B", str(POSTPROCESS), str(candidate),
            "--profile", str(profile), "--copy-to", str(destination),
        ])
        promoted[tree_id] = {
            name: sha256(destination / name)
            for name in RUNTIME_FILES
        }

    after = path_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (batch_root / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    (batch_root / "promotion_manifest.json").write_text(
        json.dumps({"profile": str(profile), "promoted": promoted}, indent=2),
        encoding="utf-8",
    )
    if not guard["passed"]:
        raise RuntimeError("Selected tree promotion changed files outside the approved presentation scope")

    run([sys.executable, "-B", "-m", "unittest", FOCUSED_TEST])
    run([str(args.godot), "--headless", "--path", str(ROOT), "--script", RUNTIME_SMOKE])
    print(f"Promoted selected 10:00 / lamp 100 / root embed 7% profile to {production_root}")


if __name__ == "__main__":
    main()
