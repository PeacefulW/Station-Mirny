"""Render a calibrated low opposite kicker under a clock-face Sun profile."""

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
import blender_layered_tree_low_rear_fill_diagnostic as calibration


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--target-lift", type=float, default=8.0)
    parser.add_argument("--spot-x", type=float, default=2.65)
    parser.add_argument("--spot-y", type=float, default=0.0)
    parser.add_argument("--spot-screen-side", default="east_opposite_9_oclock_sun")
    parser.add_argument("--file-prefix", default="sun_9_fill")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    bake.clear_scene()
    objects = bake.import_tree(args.glb)
    bake.normalize_tree(
        objects,
        float(profile["orientation"]["default_yaw_degrees"]),
        float(profile["planting"]["root_embed_fraction"]),
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    classification = bake.classify_objects(objects)
    corners = bake.all_world_corners(objects)
    min_z = min(corner.z for corner in corners)
    max_z = max(corner.z for corner in corners)
    tree_height = max_z - min_z
    target_z = min_z + tree_height * float(profile["camera"]["target_z_fraction"])
    sun_azimuth = float(profile["lighting"]["sun_azimuth_degrees"])
    camera, sun = bake.setup_render(int(profile["frame_size"]), target_z, sun_azimuth, profile)
    anchor = bake.fit_camera_to_objects(camera, objects, profile)
    sun.data.use_shadow = True

    spot_data = bpy.data.lights.new("LayeredTreeLowEastKicker", "SPOT")
    spot = bpy.data.objects.new("LayeredTreeLowEastKicker", spot_data)
    bpy.context.collection.objects.link(spot)
    spot.location = Vector((float(args.spot_x), float(args.spot_y), min_z + tree_height * 0.08))
    spot_target = Vector((0.0, 0.0, min_z + tree_height * 0.43))
    bake.look_at(spot, spot_target)
    spot.data.energy = 0.0
    spot.data.color = (1.0, 0.97, 0.92)
    spot.data.spot_size = math.radians(52.0)
    spot.data.spot_blend = 0.88
    spot.data.use_shadow = False

    bake.set_layer_visibility(objects, classification, "all")
    base_file = f"{args.file_prefix}_00.png"
    target_file = f"{args.file_prefix}_{int(round(args.target_lift)):02d}.png"
    bake.render_png(out_dir / base_file)
    bake.set_layer_visibility(objects, classification, "trunk")
    bake.render_png(out_dir / "trunk_reference.png")
    bake.set_layer_visibility(objects, classification, "foliage")
    bake.render_png(out_dir / "foliage_reference.png")
    bake.set_layer_visibility(objects, classification, "all")

    width, height, base_pixels = calibration.load_rgba(out_dir / base_file)
    _, _, trunk_pixels = calibration.load_rgba(out_dir / "trunk_reference.png")
    _, _, foliage_pixels = calibration.load_rgba(out_dir / "foliage_reference.png")
    trunk_sample, foliage_sample = calibration.build_sample_masks(
        width, height, int(anchor[1]), base_pixels, trunk_pixels, foliage_pixels
    )
    base_trunk = calibration.mean_luminance(base_pixels, trunk_sample)
    base_foliage = calibration.mean_luminance(base_pixels, foliage_sample)
    temp_paths: list[Path] = []
    counter = 0

    def render_metrics(energy: float, path: Path | None = None) -> tuple[float, float]:
        nonlocal counter
        if path is None:
            path = out_dir / f"_calibration_{counter:03d}.png"
            counter += 1
            temp_paths.append(path)
        spot.data.energy = energy
        bake.render_png(path)
        _, _, pixels = calibration.load_rgba(path)
        trunk_lift = (calibration.mean_luminance(pixels, trunk_sample) / base_trunk - 1.0) * 100.0
        foliage_lift = (calibration.mean_luminance(pixels, foliage_sample) / base_foliage - 1.0) * 100.0
        return trunk_lift, foliage_lift

    target = float(args.target_lift)
    low, high = 0.0, 1.0
    measured, _ = render_metrics(high)
    while measured < target and high < 65536.0:
        low = high
        high *= 2.0
        measured, _ = render_metrics(high)
    if measured < target:
        raise RuntimeError(f"Could not calibrate {target}% opposite kicker")
    for _ in range(10):
        mid = (low + high) * 0.5
        measured, _ = render_metrics(mid)
        if measured < target:
            low = mid
        else:
            high = mid
    energy = (low + high) * 0.5
    trunk_lift, foliage_lift = render_metrics(energy, out_dir / target_file)
    for path in temp_paths:
        path.unlink(missing_ok=True)

    diagnostic_dir = out_dir / "self_shadow"
    diagnostic_dir.mkdir(parents=True, exist_ok=True)
    spot.data.energy = energy
    sun.data.use_shadow = True
    bake.render_png(diagnostic_dir / "self_shadow_on.png")
    sun.data.use_shadow = False
    bake.render_png(diagnostic_dir / "self_shadow_off.png")
    sun.data.use_shadow = True
    (diagnostic_dir / "manifest.json").write_text(
        json.dumps({
            "controlled_difference": "LayeredTreeSun.data.use_shadow",
            "candidate_lift_percent": target,
            "kicker_fixed": True,
            "camera_fixed": True,
            "materials_fixed": True,
            "exposure_fixed": True,
        }, indent=2),
        encoding="utf-8",
    )

    manifest = {
        "source_glb": str(args.glb.resolve()),
        "profile": str(args.profile.resolve()),
        "sun": {
            "screen_direction": profile["lighting"]["screen_sun_direction"],
            "azimuth_degrees": sun_azimuth,
            "elevation_degrees": float(profile["lighting"]["albedo_sun_elevation_degrees"]),
            "use_shadow": True,
        },
        "cast_shadow_target": {
            "screen_direction": profile["lighting"]["fixed_shadow_direction"],
            "vector_screen": profile["lighting"]["fixed_shadow_direction_vector_screen"],
        },
        "kicker": {
            "screen_side": str(args.spot_screen_side),
            "placement": "low",
            "aim": "upward_to_middle_lower_trunk",
            "location": [round(float(value), 6) for value in spot.location],
            "target": [round(float(value), 6) for value in spot_target],
            "spot_energy": energy,
            "spot_size_degrees": 52.0,
            "spot_blend": float(spot.data.spot_blend),
            "use_shadow": bool(spot.data.use_shadow),
        },
        "calibration": {
            "target_trunk_lift_percent": target,
            "measured_trunk_lift_percent": trunk_lift,
            "measured_dark_foliage_lift_percent": foliage_lift,
            "trunk_sample_pixels": len(trunk_sample),
            "dark_foliage_sample_pixels": len(foliage_sample),
        },
        "files": {"fill_00": base_file, "fill_target": target_file},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
