"""Calibrate and render a subtle shadowless low rear kicker at 10 o'clock Sun."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path

import bpy
from mathutils import Vector


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import blender_layered_tree_asset_bake as bake


TARGET_LIFTS = (0.0, 2.0, 4.0, 6.0, 8.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--yaw-degrees", type=float, default=90.0)
    parser.add_argument("--frame-size", type=int, default=768)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def srgb_encode(value: float) -> float:
    value = max(0.0, min(1.0, value))
    if value <= 0.0031308:
        return 12.92 * value
    return 1.055 * pow(value, 1.0 / 2.4) - 0.055


def load_rgba(path: Path) -> tuple[int, int, list[float]]:
    image = bpy.data.images.load(str(path), check_existing=False)
    width, height = int(image.size[0]), int(image.size[1])
    pixels = list(image.pixels[:])
    bpy.data.images.remove(image)
    return width, height, pixels


def screen_luminance(pixels: list[float], pixel_index: int) -> float:
    offset = pixel_index * 4
    red = srgb_encode(pixels[offset])
    green = srgb_encode(pixels[offset + 1])
    blue = srgb_encode(pixels[offset + 2])
    return red * 0.2126 + green * 0.7152 + blue * 0.0722


def alpha(pixels: list[float], pixel_index: int) -> float:
    return pixels[pixel_index * 4 + 3]


def build_sample_masks(
    width: int,
    height: int,
    anchor_y: int,
    base_pixels: list[float],
    trunk_pixels: list[float],
    foliage_pixels: list[float],
) -> tuple[list[int], list[int]]:
    trunk_candidates: list[tuple[int, float]] = []
    foliage_candidates: list[tuple[int, float]] = []
    for pixel_index in range(width * height):
        row_from_bottom = pixel_index // width
        top_y = height - 1 - row_from_bottom
        if alpha(base_pixels, pixel_index) < 0.5:
            continue
        value = screen_luminance(base_pixels, pixel_index)
        if alpha(trunk_pixels, pixel_index) >= 0.5 and top_y < anchor_y - 56:
            trunk_candidates.append((pixel_index, value))
        if alpha(foliage_pixels, pixel_index) >= 0.5:
            foliage_candidates.append((pixel_index, value))
    if not trunk_candidates or not foliage_candidates:
        raise RuntimeError("Could not build dark trunk/foliage calibration masks")
    trunk_median = statistics.median(value for _, value in trunk_candidates)
    foliage_median = statistics.median(value for _, value in foliage_candidates)
    return (
        [pixel_index for pixel_index, value in trunk_candidates if value <= trunk_median],
        [pixel_index for pixel_index, value in foliage_candidates if value <= foliage_median],
    )


def mean_luminance(pixels: list[float], sample: list[int]) -> float:
    return statistics.fmean(screen_luminance(pixels, pixel_index) for pixel_index in sample)


def rounded_matrix(obj: bpy.types.Object) -> list[float]:
    return [round(float(value), 7) for row in obj.matrix_world for value in row]


def main() -> None:
    args = parse_args()
    profile = bake.load_profile(args.profile)
    if float(profile["lighting"]["sun_azimuth_degrees"]) != 219.0:
        raise RuntimeError("Low rear fill proof requires candidate C 10 o'clock Sun")
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
    tree_height = max_z - min_z
    target_z = min_z + tree_height * float(profile["camera"]["target_z_fraction"])
    camera, sun = bake.setup_render(
        int(args.frame_size),
        target_z,
        float(profile["lighting"]["sun_azimuth_degrees"]),
        profile,
    )
    anchor = bake.fit_camera_to_objects(camera, objects, profile)
    sun.data.use_shadow = True

    spot_data = bpy.data.lights.new("LayeredTreeLowRearKicker", "SPOT")
    spot = bpy.data.objects.new("LayeredTreeLowRearKicker", spot_data)
    bpy.context.collection.objects.link(spot)
    spot.location = Vector((2.25, -2.05, min_z + tree_height * 0.08))
    spot_target = Vector((0.0, 0.0, min_z + tree_height * 0.43))
    bake.look_at(spot, spot_target)
    spot.data.energy = 0.0
    spot.data.color = (1.0, 0.97, 0.92)
    spot.data.spot_size = math.radians(52.0)
    spot.data.spot_blend = 0.88
    spot.data.use_shadow = False

    bake.set_layer_visibility(objects, classification, "all")
    bake.render_png(out_dir / "lift_00.png")
    bake.set_layer_visibility(objects, classification, "trunk")
    bake.render_png(out_dir / "trunk_reference.png")
    bake.set_layer_visibility(objects, classification, "foliage")
    bake.render_png(out_dir / "foliage_reference.png")
    bake.set_layer_visibility(objects, classification, "all")

    fixed_tree = {obj.name: rounded_matrix(obj) for obj in objects}
    fixed_camera = rounded_matrix(camera)
    fixed_sun = rounded_matrix(sun)
    fixed_spot = rounded_matrix(spot)

    width, height, base_pixels = load_rgba(out_dir / "lift_00.png")
    _, _, trunk_pixels = load_rgba(out_dir / "trunk_reference.png")
    _, _, foliage_pixels = load_rgba(out_dir / "foliage_reference.png")
    trunk_sample, foliage_sample = build_sample_masks(
        width, height, int(anchor[1]), base_pixels, trunk_pixels, foliage_pixels
    )
    base_trunk = mean_luminance(base_pixels, trunk_sample)
    base_foliage = mean_luminance(base_pixels, foliage_sample)
    calibration_counter = 0
    calibration_paths: list[Path] = []

    def render_metrics(energy: float, path: Path | None = None) -> tuple[float, float]:
        nonlocal calibration_counter
        if path is None:
            path = out_dir / f"_calibration_{calibration_counter:03d}.png"
            calibration_counter += 1
            calibration_paths.append(path)
        spot.data.energy = energy
        bake.render_png(path)
        _, _, pixels = load_rgba(path)
        trunk_lift = (mean_luminance(pixels, trunk_sample) / base_trunk - 1.0) * 100.0
        foliage_lift = (mean_luminance(pixels, foliage_sample) / base_foliage - 1.0) * 100.0
        return trunk_lift, foliage_lift

    variants = [
        {
            "target_lift_percent": 0.0,
            "measured_trunk_lift_percent": 0.0,
            "measured_dark_foliage_lift_percent": 0.0,
            "spot_energy": 0.0,
            "file": "lift_00.png",
            "primary": False,
        }
    ]
    previous_energy = 0.0
    for target in TARGET_LIFTS[1:]:
        low = previous_energy
        high = max(1.0, previous_energy * 1.5)
        measured, _ = render_metrics(high)
        while measured < target and high < 65536.0:
            low = high
            high *= 2.0
            measured, _ = render_metrics(high)
        if measured < target:
            raise RuntimeError(f"Could not calibrate {target}% trunk lift")
        for _ in range(9):
            mid = (low + high) * 0.5
            measured, _ = render_metrics(mid)
            if measured < target:
                low = mid
            else:
                high = mid
        energy = (low + high) * 0.5
        file_name = f"lift_{int(target):02d}.png"
        trunk_lift, foliage_lift = render_metrics(energy, out_dir / file_name)
        previous_energy = energy
        variants.append(
            {
                "target_lift_percent": target,
                "measured_trunk_lift_percent": trunk_lift,
                "measured_dark_foliage_lift_percent": foliage_lift,
                "spot_energy": energy,
                "file": file_name,
                "primary": target == 2.0,
            }
        )
    for calibration_path in calibration_paths:
        calibration_path.unlink(missing_ok=True)

    selected = next(item for item in variants if item["primary"])
    spot.data.energy = float(selected["spot_energy"])
    diagnostic_dir = out_dir / "self_shadow"
    diagnostic_dir.mkdir(parents=True, exist_ok=True)
    sun.data.use_shadow = True
    bake.render_png(diagnostic_dir / "self_shadow_on.png")
    sun.data.use_shadow = False
    bake.render_png(diagnostic_dir / "self_shadow_off.png")
    sun.data.use_shadow = True
    (diagnostic_dir / "manifest.json").write_text(
        json.dumps(
            {
                "controlled_difference": "LayeredTreeSun.data.use_shadow",
                "candidate_lift_percent": 2.0,
                "kicker_fixed": True,
                "camera_fixed": True,
                "materials_fixed": True,
                "exposure_fixed": True,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    if (
        {obj.name: rounded_matrix(obj) for obj in objects} != fixed_tree
        or rounded_matrix(camera) != fixed_camera
        or rounded_matrix(sun) != fixed_sun
        or rounded_matrix(spot) != fixed_spot
    ):
        raise RuntimeError("Tree, camera, Sun, or kicker transform changed during calibration")

    manifest = {
        "source_glb": str(args.glb.resolve()),
        "profile": str(args.profile.resolve()),
        "profile_id": profile["profile_id"],
        "tree_yaw_degrees": float(args.yaw_degrees),
        "anchor": list(anchor),
        "sun": {
            "screen_direction": profile["lighting"]["screen_sun_direction"],
            "azimuth_degrees": float(profile["lighting"]["sun_azimuth_degrees"]),
            "elevation_degrees": float(profile["lighting"]["albedo_sun_elevation_degrees"]),
            "energy": float(sun.data.energy),
            "use_shadow": True,
        },
        "kicker": {
            "name": spot.name,
            "type": spot.data.type,
            "screen_side": "east_south_east_opposite_10_oclock_sun",
            "placement": "low",
            "aim": "upward_to_middle_lower_trunk",
            "location": [round(float(value), 6) for value in spot.location],
            "target": [round(float(value), 6) for value in spot_target],
            "spot_size_degrees": 52.0,
            "spot_blend": float(spot.data.spot_blend),
            "color": [float(value) for value in spot.data.color],
            "use_shadow": bool(spot.data.use_shadow),
        },
        "calibration": {
            "metric": "screen_srgb_luminance_lift_on_dark_visible_trunk_pixels",
            "trunk_sample_pixels": len(trunk_sample),
            "dark_foliage_sample_pixels": len(foliage_sample),
            "targets_percent": list(TARGET_LIFTS),
            "primary_target_percent": 2.0,
        },
        "fixed_scene": {
            "tree": True,
            "camera": True,
            "sun": True,
            "kicker_transform": True,
            "only_kicker_energy_varies": True,
        },
        "variants": variants,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
