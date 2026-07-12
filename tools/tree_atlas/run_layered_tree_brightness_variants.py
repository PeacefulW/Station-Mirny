"""Bake three isolated tree_01 brightness candidates and strict self-shadow pairs."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BAKE_SCRIPT = Path(__file__).with_name("blender_layered_tree_asset_bake.py")
POSTPROCESS_SCRIPT = Path(__file__).with_name("postprocess_layered_tree_asset.py")
SELF_SHADOW_SCRIPT = Path(__file__).with_name("blender_layered_tree_self_shadow_diagnostic.py")
SELF_SHADOW_REPORT = Path(__file__).with_name("build_layered_tree_self_shadow_report.py")
REVIEW_SCRIPT = Path(__file__).with_name("build_layered_tree_brightness_review.py")
DEFAULT_MANIFEST = Path(__file__).with_name("layered_tree_brightness_variants_manifest.json")
PRODUCTION_GUARD_PATHS = (
    ROOT / "tools" / "tree_atlas" / "layered_tree_bake_profile.json",
    ROOT / "assets" / "sprites" / "flora" / "layered_trees",
    ROOT / "assets" / "shaders" / "layered_tree_foliage_wind.gdshader",
    ROOT / "assets" / "shaders" / "layered_tree_snow_accumulation.gdshader",
    ROOT / "core" / "systems" / "world" / "layered_tree_object_layer.gd",
    ROOT / "core" / "systems" / "world" / "world_streamer.gd",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--variant", action="append", default=[])
    return parser.parse_args()


def resolve_repo_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def deep_merge(target: dict, overrides: dict) -> dict:
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = copy.deepcopy(value)
    return target


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def production_hashes() -> dict[str, str]:
    result: dict[str, str] = {}
    for root_path in PRODUCTION_GUARD_PATHS:
        paths = sorted(root_path.rglob("*")) if root_path.is_dir() else [root_path]
        for path in paths:
            if not path.is_file() or path.name.endswith(".import"):
                continue
            result[path.relative_to(ROOT).as_posix()] = sha256(path)
    return result


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    base_profile = json.loads(
        resolve_repo_path(str(manifest["base_profile"])).read_text(encoding="utf-8")
    )
    source_glb = resolve_repo_path(str(manifest["source_glb"]))
    output_root = resolve_repo_path(str(manifest["output_root"]))
    output_root.mkdir(parents=True, exist_ok=True)
    before = production_hashes()
    (output_root / "production_guard_before.json").write_text(
        json.dumps(before, indent=2), encoding="utf-8"
    )

    selected = set(args.variant)
    for item in manifest["variants"]:
        variant_id = str(item["id"])
        if selected and variant_id not in selected:
            continue
        output_dir = output_root / variant_id
        output_dir.mkdir(parents=True, exist_ok=True)
        profile = deep_merge(copy.deepcopy(base_profile), item.get("overrides", {}))
        profile["profile_id"] = f"station_mirny_tree_brightness_proof_{variant_id}"
        profile["version"] = 3
        profile_path = output_dir / "profile.json"
        profile_path.write_text(json.dumps(profile, indent="\t"), encoding="utf-8")
        print(f"Baking brightness candidate {variant_id}", flush=True)
        run(
            [
                str(args.blender),
                "--background",
                "--factory-startup",
                "--python",
                str(BAKE_SCRIPT),
                "--",
                "--glb",
                str(source_glb),
                "--out-dir",
                str(output_dir),
                "--profile",
                str(profile_path),
                "--yaw-degrees",
                str(float(manifest["yaw_degrees"])),
            ]
        )
        run([sys.executable, "-B", str(POSTPROCESS_SCRIPT), str(output_dir), "--profile", str(profile_path)])
        diagnostic_dir = output_dir / "self_shadow"
        run(
            [
                str(args.blender),
                "--background",
                "--factory-startup",
                "--python",
                str(SELF_SHADOW_SCRIPT),
                "--",
                "--glb",
                str(source_glb),
                "--out-dir",
                str(diagnostic_dir),
                "--profile",
                str(profile_path),
                "--yaw-degrees",
                str(float(manifest["yaw_degrees"])),
            ]
        )
        run([sys.executable, "-B", str(SELF_SHADOW_REPORT), str(diagnostic_dir)])

    after = production_hashes()
    guard = {"passed": before == after, "before": before, "after": after}
    (output_root / "production_guard.json").write_text(
        json.dumps(guard, indent=2), encoding="utf-8"
    )
    if not guard["passed"]:
        raise RuntimeError("Production tree/runtime guard changed during isolated brightness proof")
    run([sys.executable, "-B", str(REVIEW_SCRIPT), "--manifest", str(manifest_path)])
    print(f"Wrote brightness proof to {output_root}")


if __name__ == "__main__":
    main()
