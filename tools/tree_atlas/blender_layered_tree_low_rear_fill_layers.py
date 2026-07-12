"""Render split trunk/foliage layers for one calibrated low rear kicker variant."""

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--proof-manifest", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--target-lift", type=float, default=8.0)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    proof = json.loads(args.proof_manifest.read_text(encoding="utf-8"))
    variant = next(
        item for item in proof["variants"]
        if math.isclose(float(item["target_lift_percent"]), float(args.target_lift), abs_tol=0.001)
    )
    kicker = proof["kicker"]
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    bake.clear_scene()
    objects = bake.import_tree(args.glb)
    bake.normalize_tree(
        objects,
        float(proof["tree_yaw_degrees"]),
        float(profile["planting"]["root_embed_fraction"]),
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    classification = bake.classify_objects(objects)
    corners = bake.all_world_corners(objects)
    min_z = min(corner.z for corner in corners)
    max_z = max(corner.z for corner in corners)
    target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, sun = bake.setup_render(
        int(profile["frame_size"]),
        target_z,
        float(profile["lighting"]["sun_azimuth_degrees"]),
        profile,
    )
    anchor = bake.fit_camera_to_objects(camera, objects, profile)
    sun.data.use_shadow = True

    spot_data = bpy.data.lights.new("LayeredTreeLowRearKicker", "SPOT")
    spot = bpy.data.objects.new("LayeredTreeLowRearKicker", spot_data)
    bpy.context.collection.objects.link(spot)
    spot.location = Vector(kicker["location"])
    bake.look_at(spot, Vector(kicker["target"]))
    spot.data.energy = float(variant["spot_energy"])
    spot.data.color = tuple(float(value) for value in kicker["color"])
    spot.data.spot_size = math.radians(float(kicker["spot_size_degrees"]))
    spot.data.spot_blend = float(kicker["spot_blend"])
    spot.data.use_shadow = False

    for layer, file_name in (
        ("all", "albedo.png"),
        ("trunk", "trunk.png"),
        ("foliage", "foliage.png"),
    ):
        bake.set_layer_visibility(objects, classification, layer)
        bake.render_png(out_dir / file_name)

    metadata = {
        "target_lift_percent": float(args.target_lift),
        "spot_energy": float(variant["spot_energy"]),
        "sun_use_shadow": bool(sun.data.use_shadow),
        "kicker_use_shadow": bool(spot.data.use_shadow),
        "anchor": list(anchor),
        "profile_id": profile["profile_id"],
        "layers": {"albedo": "albedo.png", "trunk": "trunk.png", "foliage": "foliage.png"},
    }
    (out_dir / "manifest.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
