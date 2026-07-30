"""Bake five more rust crown individuals through the canonical pipeline.

Same species, same approved geometry and palette - only the per-variant knobs the
profile already exposes are moved. Nothing about the crown, the fork or the bark
is touched here; those are still open questions.

`world_scale` is deliberately left at 1.0 on every new variant. The canonical
bake refits the camera to each asset and the runtime draws every tree at a fixed
frame scale, so a uniform scale is normalised away twice over and would not
produce a single different pixel in game. What survives the refit is proportion:
height_scale (slenderness), crown_scale (crown against trunk), blade_density
(how full the canopy is), yaw (which side of the braid faces the camera) and the
seed (the structure itself).

The canonical profile is not modified: a copy with the extra variants appended is
written to the scratchpad and handed to the shipped bake script via
--tree-profile.

Run from the repo root:
    python make_rust_crown_variations.py --out-dir <dir>
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful")
TOOL_DIR = REPO / "tools" / "tree_atlas"
SCRATCH = Path(__file__).resolve().parent
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe")
BAKE_SCRIPT = TOOL_DIR / "blender_rust_crown_tree_bake.py"
CANON_PROFILE = TOOL_DIR / "rust_crown_tree_profiles.json"

NEW_VARIANTS = [
    {
        "id": "var_04",
        "title": "tall_slim",
        "title_ru": "высокое узкое",
        "seed": 71044,
        "yaw_degrees": 82.0,
        "world_scale": 1.0,
        "height_scale": 1.24,
        "crown_scale": 0.80,
        "blade_density": 0.95,
    },
    {
        "id": "var_05",
        "title": "squat_dense",
        "title_ru": "приземистое плотное",
        "seed": 71055,
        "yaw_degrees": 116.0,
        "world_scale": 1.0,
        "height_scale": 0.82,
        "crown_scale": 1.12,
        "blade_density": 1.25,
    },
    {
        "id": "var_06",
        "title": "sparse_old",
        "title_ru": "редкое старое",
        "seed": 71066,
        "yaw_degrees": 68.0,
        "world_scale": 1.0,
        "height_scale": 1.02,
        "crown_scale": 1.04,
        "blade_density": 0.70,
    },
    {
        "id": "var_07",
        "title": "young_small",
        "title_ru": "молодое мелкое",
        "seed": 71077,
        "yaw_degrees": 96.0,
        "world_scale": 1.0,
        "height_scale": 0.94,
        "crown_scale": 0.84,
        "blade_density": 1.08,
    },
    {
        "id": "var_08",
        "title": "broad_spread",
        "title_ru": "раскидистое",
        "seed": 71088,
        "yaw_degrees": 110.0,
        "world_scale": 1.0,
        "height_scale": 1.00,
        "crown_scale": 1.28,
        "blade_density": 1.00,
        # A crown this wide runs its baked shadow off the right edge at the
        # shipped fit fractions, the same reason var_03 carries an override.
        "camera_fit": {"fit_width_fraction": 0.56, "fit_height_fraction": 0.62},
    },
]


def load_postprocess():
    path = TOOL_DIR / "postprocess_layered_tree_asset.py"
    spec = importlib.util.spec_from_file_location("postprocess_layered_tree_asset", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_profile(target: Path) -> Path:
    profile = json.loads(CANON_PROFILE.read_text(encoding="utf-8"))
    known = {variant["id"] for variant in profile["variants"]}
    for variant in NEW_VARIANTS:
        if variant["id"] in known:
            raise SystemExit(f"{variant['id']} already exists in the canonical profile")
        profile["variants"].append(copy.deepcopy(variant))
    target.write_text(json.dumps(profile, indent="\t", ensure_ascii=False), encoding="utf-8")
    return target


def bake(variant_id: str, out_dir: Path, profile_path: Path) -> None:
    command = [
        str(BLENDER), "-b", "--factory-startup",
        "--python", str(BAKE_SCRIPT), "--",
        "--out-dir", str(out_dir),
        "--variant-id", variant_id,
        "--tree-profile", str(profile_path),
    ]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-4000:])
        sys.stderr.write(result.stderr[-4000:])
        raise SystemExit(f"bake failed for {variant_id}")
    print(f"  bake {variant_id}: {time.time() - started:.0f}s", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--only", nargs="*", default=None)
    parser.add_argument("--skip-bake", action="store_true")
    args = parser.parse_args()

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    profile_path = build_profile(SCRATCH / "rust_crown_tree_profiles_extended.json")
    post = load_postprocess()

    wanted = [v for v in NEW_VARIANTS if args.only is None or v["id"] in args.only]
    for variant in wanted:
        variant_dir = out_dir / variant["id"]
        print(f"[{variant['id']}] {variant['title_ru']}", flush=True)
        if not args.skip_bake:
            bake(variant["id"], variant_dir, profile_path)
        started = time.time()
        post.save_outputs(
            variant_dir, None,
            post.load_profile(TOOL_DIR / "layered_asset_bake_profile.json"),
        )
        print(f"  postprocess: {time.time() - started:.0f}s", flush=True)

    print(f"done: {len(wanted)} variants in {out_dir}", flush=True)


if __name__ == "__main__":
    main()
