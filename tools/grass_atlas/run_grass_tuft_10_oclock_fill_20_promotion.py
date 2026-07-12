"""Bake, review, promote, and verify the selected fixed-length grass lighting."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PROFILE = Path(__file__).with_name("grass_tuft_bake_profile.json")
BAKE = Path(__file__).with_name("blender_grass_tuft_bake.py")
POSTPROCESS = Path(__file__).with_name("postprocess_grass_tuft_atlas.py")
REVIEW = Path(__file__).with_name("build_grass_tuft_10_oclock_fill_20_review.py")
OUTPUT_ROOT = ROOT / "artifacts" / "blender_grass_tufts_10_oclock_fill_20"
FRAMES = OUTPUT_ROOT / "frames"
RUNTIME_DIR = ROOT / "assets" / "textures" / "world" / "biomes" / "plains" / "flora"
FORBIDDEN_PATHS = (
    "gdextension/src/grass_scatter.cpp",
    "gdextension/src/grass_scatter.h",
    "core/autoloads/time_manager.gd",
    "core/autoloads/wind_runtime.gd",
    "core/autoloads/weather_runtime.gd",
    "core/systems/world/world_runtime_constants.gd",
    "assets/sprites/flora/layered_trees",
    "assets/sprites/decor/plains/layered_small_rocks",
    "project.godot",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalized_png_sha256(path: Path) -> str:
    image = Image.open(path).convert("RGBA")
    payload = image.width.to_bytes(4, "little") + image.height.to_bytes(4, "little") + image.tobytes()
    return hashlib.sha256(payload).hexdigest()


def path_hashes() -> dict[str, str]:
    hashes: dict[str, str] = {}
    for relative in FORBIDDEN_PATHS:
        path = ROOT / relative
        if path.is_file():
            hashes[relative] = sha256(path)
        elif path.is_dir():
            for child in sorted(item for item in path.rglob("*") if item.is_file()):
                hashes[child.relative_to(ROOT).as_posix()] = sha256(child)
    return hashes


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    before = path_hashes()
    run([
        str(args.blender), "--background", "--factory-startup", "--python", str(BAKE), "--",
        "--out-dir", str(FRAMES), "--profile", str(PROFILE), "--write-self-shadow-reference",
    ])
    run([
        sys.executable, "-B", str(POSTPROCESS), "--frames-dir", str(FRAMES),
        "--out-dir", str(OUTPUT_ROOT), "--profile", str(PROFILE),
    ])
    run([sys.executable, "-B", str(REVIEW), str(OUTPUT_ROOT)])
    run([
        sys.executable, "-B", str(POSTPROCESS), "--frames-dir", str(FRAMES),
        "--out-dir", str(OUTPUT_ROOT), "--profile", str(PROFILE), "--copy-to", str(RUNTIME_DIR),
    ])
    after = path_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (OUTPUT_ROOT / "production_guard.json").write_text(json.dumps(guard, indent=2), encoding="utf-8")
    if not guard["passed"]:
        raise RuntimeError("Grass promotion changed a forbidden world/runtime asset")
    promoted = {
        "grass_tuft_atlas.png": normalized_png_sha256(RUNTIME_DIR / "grass_tuft_atlas.png"),
        "grass_tuft_shadow_atlas.png": normalized_png_sha256(RUNTIME_DIR / "grass_tuft_shadow_atlas.png"),
    }
    (OUTPUT_ROOT / "promotion_manifest.json").write_text(
        json.dumps({"profile_id": json.loads(PROFILE.read_text(encoding="utf-8"))["profile_id"], "promoted": promoted}, indent=2),
        encoding="utf-8",
    )
    run([sys.executable, "-B", "-m", "unittest", "tools.grass_atlas.test_grass_tuft_bake_contract"])
    print(f"Promoted selected grass atlases to {RUNTIME_DIR}")


if __name__ == "__main__":
    main()
