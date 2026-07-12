"""Render two cheap albedo-only yaw candidates for one layered tree GLB."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import blender_layered_tree_asset_bake as bake


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--frame-size", type=int, default=384)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    bake.clear_scene()
    objects = bake.import_tree(args.glb)
    bake.normalize_tree(
        objects,
        90.0,
        float(profile["planting"]["root_embed_fraction"]),
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    root = bpy.data.objects.get("TreeRoot")
    if root is None:
        raise RuntimeError("TreeRoot was not created")
    corners = bake.all_world_corners(objects)
    min_z = min(corner.z for corner in corners)
    max_z = max(corner.z for corner in corners)
    target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, _sun = bake.setup_render(
        int(args.frame_size),
        target_z,
        float(profile["lighting"]["sun_azimuth_degrees"]),
        profile,
    )
    bake.set_layer_visibility(objects, bake.classify_objects(objects), "all")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    captures: list[dict] = []
    for yaw_degrees in (90.0, 180.0):
        root.rotation_euler[2] = math.radians(yaw_degrees)
        bpy.context.view_layer.update()
        anchor = bake.fit_camera_to_objects(camera, objects, profile)
        file_name = f"yaw_{int(yaw_degrees):03d}.png"
        bake.render_png(args.out_dir / file_name)
        captures.append(
            {
                "yaw_degrees": yaw_degrees,
                "file": file_name,
                "anchor": list(anchor),
            }
        )
    (args.out_dir / "manifest.json").write_text(
        json.dumps(
            {
                "source_glb": str(args.glb.resolve()),
                "profile": str(args.profile.resolve()),
                "captures": captures,
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    print(f"Wrote orientation probe to {args.out_dir}")


if __name__ == "__main__":
    main()
