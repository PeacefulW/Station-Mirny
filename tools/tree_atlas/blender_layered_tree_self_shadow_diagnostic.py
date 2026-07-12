"""Render a controlled tree self-shadow ON/OFF pair from one Blender scene."""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("--yaw-degrees", required=True, type=float)
    parser.add_argument("--frame-size", type=int)
    parser.add_argument("--sun-elevation-degrees", type=float)
    parser.add_argument("--sun-angle-degrees", type=float)
    parser.add_argument("--fill-energy", type=float)
    parser.add_argument("--sun-angular-diameter-degrees", type=float)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    frame_size = int(args.frame_size or profile["frame_size"])
    sun_angle_degrees = float(
        args.sun_angle_degrees
        if args.sun_angle_degrees is not None
        else profile["lighting"]["sun_azimuth_degrees"]
    )
    if args.sun_elevation_degrees is not None:
        profile["lighting"]["albedo_sun_elevation_degrees"] = float(args.sun_elevation_degrees)
    if args.fill_energy is not None:
        profile["lighting"]["fill_energy"] = float(args.fill_energy)
    if args.sun_angular_diameter_degrees is not None:
        profile["lighting"]["albedo_sun_angular_diameter_degrees"] = float(
            args.sun_angular_diameter_degrees
        )
    root_embed_fraction = float(profile["planting"]["root_embed_fraction"])

    bake.clear_scene()
    objects = bake.import_tree(args.glb)
    bake.normalize_tree(
        objects,
        float(args.yaw_degrees),
        root_embed_fraction,
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    classification = bake.classify_objects(objects)
    corners = bake.all_world_corners(objects)
    min_z = min(corner.z for corner in corners)
    max_z = max(corner.z for corner in corners)
    target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, sun = bake.setup_render(frame_size, target_z, sun_angle_degrees, profile)
    anchor = bake.fit_camera_to_objects(camera, objects, profile)
    bake.set_layer_visibility(objects, classification, "all")

    fill = bpy.data.objects.get("LayeredTreeFill")
    if fill is None or fill.type != "LIGHT":
        raise RuntimeError("LayeredTreeFill was not created")
    fill.data.use_shadow = False

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    sun.data.use_shadow = True
    bpy.context.view_layer.update()
    bake.render_png(out_dir / "self_shadow_on.png")
    sun.data.use_shadow = False
    bpy.context.view_layer.update()
    bake.render_png(out_dir / "self_shadow_off.png")

    manifest = {
        "source_glb": str(args.glb.resolve()),
        "profile": str(args.profile.resolve()),
        "frame_size": frame_size,
        "yaw_degrees": float(args.yaw_degrees),
        "anchor": list(anchor),
        "sun_azimuth_degrees": sun_angle_degrees,
        "sun_elevation_degrees": float(profile["lighting"]["albedo_sun_elevation_degrees"]),
        "sun_energy": float(profile["lighting"]["albedo_sun_energy"]),
        "sun_angular_diameter_degrees": float(
            profile["lighting"].get("albedo_sun_angular_diameter_degrees", 0.526)
        ),
        "fill_energy": float(profile["lighting"]["fill_energy"]),
        "fill_use_shadow": False,
        "exposure": float(profile["render"]["exposure"]),
        "controlled_difference": "LayeredTreeSun.data.use_shadow",
        "on_value": True,
        "off_value": False,
        "classification_count": len(classification),
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Wrote strict self-shadow diagnostic to {out_dir}")


if __name__ == "__main__":
    main()
