"""Bake and postprocess the isolated remaining-tree proof batch."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BAKE_SCRIPT = Path(__file__).with_name("blender_layered_tree_asset_bake.py")
POSTPROCESS_SCRIPT = Path(__file__).with_name("postprocess_layered_tree_asset.py")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(__file__).with_name("layered_tree_batch_proof_manifest.json"),
    )
    return parser.parse_args()


def resolve_repo_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def main() -> None:
    args = parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    profile = resolve_repo_path(str(manifest["profile"]))
    output_root = resolve_repo_path(str(manifest["output_root"]))
    output_root.mkdir(parents=True, exist_ok=True)

    for item in manifest["trees"]:
        tree_id = str(item["tree_id"])
        source_glb = resolve_repo_path(str(item["source_glb"]))
        output_dir = output_root / tree_id
        yaw_degrees = float(item["yaw_degrees"])
        print(f"Baking {tree_id}: yaw={yaw_degrees:.1f}", flush=True)
        subprocess.run(
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
                str(profile),
                "--yaw-degrees",
                str(yaw_degrees),
            ],
            cwd=ROOT,
            check=True,
        )
        subprocess.run(
            [
                sys.executable,
                "-B",
                str(POSTPROCESS_SCRIPT),
                str(output_dir),
                "--profile",
                str(profile),
            ],
            cwd=ROOT,
            check=True,
        )
    print(f"Wrote batch proof to {output_root}")


if __name__ == "__main__":
    main()
