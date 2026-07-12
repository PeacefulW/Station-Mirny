"""Render eight fixed-light camera views around one normalized layered tree."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import blender_layered_tree_asset_bake as bake


VIEWS = (
    ("south", "South", -90.0),
    ("south_west", "South-West", -135.0),
    ("west", "West", 180.0),
    ("north_west", "North-West", 135.0),
    ("north", "North", 90.0),
    ("north_east", "North-East", 45.0),
    ("east", "East", 0.0),
    ("south_east", "South-East", -45.0),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--yaw-degrees", type=float, default=90.0)
    parser.add_argument("--frame-size", type=int, default=768)
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    return parser.parse_args(argv)


def rounded_matrix(obj: bpy.types.Object) -> list[float]:
    return [round(value, 8) for row in obj.matrix_world for value in row]


def scene_signature(objects: list[bpy.types.Object], lights: list[bpy.types.Object]) -> dict:
    return {
        "tree": {obj.name: rounded_matrix(obj) for obj in sorted(objects, key=lambda item: item.name)},
        "lights": {
            light.name: {
                "matrix_world": rounded_matrix(light),
                "type": light.data.type,
                "energy": round(float(light.data.energy), 8),
                "use_shadow": bool(getattr(light.data, "use_shadow", True)),
            }
            for light in sorted(lights, key=lambda item: item.name)
        },
    }


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    bake.clear_scene()
    objects = bake.import_tree(args.glb)
    bake.normalize_tree(
        objects,
        float(args.yaw_degrees),
        float(profile["planting"]["root_embed_fraction"]),
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    classification = bake.classify_objects(objects)
    corners = bake.all_world_corners(objects)
    min_z = min(corner.z for corner in corners)
    max_z = max(corner.z for corner in corners)
    target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    sun_azimuth = float(profile["lighting"]["sun_azimuth_degrees"])
    camera, sun = bake.setup_render(int(args.frame_size), target_z, sun_azimuth, profile)
    bake.set_layer_visibility(objects, classification, "all")
    sun.data.use_shadow = True

    radius = abs(float(profile["camera"]["location_y"]))
    camera_height = target_z + float(profile["camera"]["height_offset"])
    lights = [obj for obj in bpy.context.scene.objects if obj.type == "LIGHT"]
    fixed_signature: dict | None = None
    views: list[dict] = []
    for view_id, label, angle_degrees in VIEWS:
        angle = math.radians(angle_degrees)
        camera.location = Vector((math.cos(angle) * radius, math.sin(angle) * radius, camera_height))
        bake.look_at(camera, Vector((0.0, 0.0, target_z)))
        anchor = bake.fit_camera_to_objects(camera, objects, profile)
        current_signature = scene_signature(objects, lights)
        if fixed_signature is None:
            fixed_signature = current_signature
        elif current_signature != fixed_signature:
            raise RuntimeError(f"Tree or light state changed while rendering {view_id}")
        output_path = out_dir / f"{view_id}.png"
        bake.render_png(output_path)
        views.append(
            {
                "id": view_id,
                "label": label,
                "camera_compass_degrees": angle_degrees,
                "camera_location": [round(float(value), 6) for value in camera.location],
                "camera_ortho_scale": round(float(camera.data.ortho_scale), 8),
                "anchor": list(anchor),
                "file": output_path.name,
            }
        )

    manifest = {
        "source_glb": str(args.glb.resolve()),
        "profile": str(args.profile.resolve()),
        "profile_id": profile["profile_id"],
        "candidate": "A",
        "tree_yaw_degrees": float(args.yaw_degrees),
        "tree_and_lights_fixed": True,
        "camera_only_orbit": True,
        "sun": {
            "name": sun.name,
            "azimuth_degrees": sun_azimuth,
            "elevation_degrees": float(profile["lighting"]["albedo_sun_elevation_degrees"]),
            "energy": float(sun.data.energy),
            "use_shadow": bool(sun.data.use_shadow),
            "screen_direction": profile["lighting"]["screen_sun_direction"],
        },
        "render": {
            "exposure": float(profile["render"]["exposure"]),
            "ambient_fill_enabled": bool(profile["lighting"].get("ambient_fill", {}).get("enabled", False)),
            "fill_energy": float(profile["lighting"]["fill_energy"]),
            "frame_size": int(args.frame_size),
        },
        "views": views,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"Wrote {len(views)} fixed-light camera views to {out_dir}")


if __name__ == "__main__":
    main()
