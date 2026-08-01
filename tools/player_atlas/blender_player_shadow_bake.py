"""Render one player's baked animation clip as strict Cycles shadow-catcher frames.

The albedo bake summary is authoritative for animation sampling and turntable
orientation. This pass never derives phases or yaws again: it reuses the exact
``sampled_source_frames`` and ``direction_yaw_degrees`` written by
``blender_player_clip_bake.py``.

Usage:
    blender --background --factory-startup --python blender_player_shadow_bake.py -- \
        <clip_id> <albedo_frames_dir> <output_dir> [--profile <path>]
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


TOOL_DIR = Path(__file__).resolve().parent
SOURCE_FRAME_WIDTH_PX = 304
SOURCE_FRAME_HEIGHT_PX = 192
SHADOW_CATCHER_HALF_EXTENT_M = 2.8
SHADOW_CATCHER_Z_M = -0.012
RAW_ALPHA_THRESHOLDS_U8 = (6, 8, 10, 12)
RAW_ALPHA_MIN_BORDER_MARGIN_PX = 8
RAW_ALPHA_MAX_BBOX_COVERAGE = 0.72
EXPECTED_SHADOW_ENGINE = "CYCLES"
EXPECTED_CYCLES_SAMPLES = 64
EXPECTED_SUN_AZIMUTH_DEGREES = 225.0
EXPECTED_SUN_ELEVATION_DEGREES = 42.0
EXPECTED_SUN_ENERGY = 3.5


def load_player_bake_module():
    path = TOOL_DIR / "blender_player_clip_bake.py"
    spec = importlib.util.spec_from_file_location("station_player_clip_bake", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import player bake helpers from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PLAYER_BAKE = load_player_bake_module()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip_id")
    parser.add_argument("albedo_frames_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--profile", type=Path, default=PLAYER_BAKE.DEFAULT_PROFILE)
    parser.add_argument("--only-direction", type=int, default=None)
    parser.add_argument("--only-frame", type=int, default=None)
    return parser.parse_args(PLAYER_BAKE.argv_after_separator())


def require_close(label: str, actual: float, expected: float, tolerance: float = 1e-6) -> None:
    if abs(actual - expected) > tolerance:
        raise RuntimeError(f"{label}={actual} does not match the canonical value {expected}")


def validate_shadow_contract(profile: dict, bake_profile: dict) -> tuple[int, int]:
    render = bake_profile["render"]
    lighting = bake_profile["lighting"]
    if str(render["shadow_engine"]) != EXPECTED_SHADOW_ENGINE:
        raise RuntimeError(
            f"Shadow engine {render['shadow_engine']!r} is not {EXPECTED_SHADOW_ENGINE!r}"
        )
    if int(render["samples"]) != EXPECTED_CYCLES_SAMPLES:
        raise RuntimeError(
            f"Cycles samples {render['samples']} do not match {EXPECTED_CYCLES_SAMPLES}"
        )
    if not bool(render["use_denoising"]):
        raise RuntimeError("Player shadow bake requires Cycles denoising")
    if not bool(render["transparent_film"]):
        raise RuntimeError("Player shadow bake requires transparent film")
    require_close(
        "sun_azimuth_degrees",
        float(lighting["sun_azimuth_degrees"]),
        EXPECTED_SUN_AZIMUTH_DEGREES,
    )
    require_close(
        "shadow_sun_elevation_degrees",
        float(lighting["shadow_sun_elevation_degrees"]),
        EXPECTED_SUN_ELEVATION_DEGREES,
    )
    require_close(
        "shadow_sun_energy",
        float(lighting["shadow_sun_energy"]),
        EXPECTED_SUN_ENERGY,
    )
    if bool(lighting["bounce"]["in_shadow_pass"]):
        raise RuntimeError("Ground bounce must be excluded from the player shadow pass")

    shadow_profile = profile.get("shadow")
    if not isinstance(shadow_profile, dict):
        raise RuntimeError("Player bake profile must declare shadow.source_anchor_px")
    source_anchor = shadow_profile.get("source_anchor_px")
    if not isinstance(source_anchor, list) or len(source_anchor) != 2:
        raise RuntimeError("shadow.source_anchor_px must contain [x, y]")
    anchor_x = int(source_anchor[0])
    anchor_y = int(source_anchor[1])
    if [anchor_x, anchor_y] != [104, 56]:
        raise RuntimeError(
            f"shadow.source_anchor_px={[anchor_x, anchor_y]} does not match the measured [104, 56]"
        )
    return anchor_x, anchor_y


def load_albedo_summary(clip_id: str, frames_dir: Path, profile: dict) -> tuple[dict, Path]:
    path = frames_dir / f"{clip_id}_render_summary.json"
    if not path.is_file():
        raise RuntimeError(f"Missing authoritative albedo render summary: {path}")
    summary = PLAYER_BAKE.load_json(path)
    if str(summary.get("clip_id", "")) != clip_id:
        raise RuntimeError(f"Albedo summary clip_id={summary.get('clip_id')!r}, expected {clip_id!r}")

    clip = next((item for item in profile["clips"] if item["clip_id"] == clip_id), None)
    if clip is None:
        raise RuntimeError(f"Clip id {clip_id!r} is not declared in the player bake profile")
    if str(summary.get("source_clip", "")) != str(clip["mixamo_file"]):
        raise RuntimeError(
            f"Albedo summary source {summary.get('source_clip')!r} does not match {clip['mixamo_file']!r}"
        )

    directions = int(summary.get("directions", 0))
    frames_per_direction = int(summary.get("frames_per_direction", 0))
    direction_yaws = summary.get("direction_yaw_degrees")
    source_frames = summary.get("sampled_source_frames")
    if directions <= 0 or not isinstance(direction_yaws, list) or len(direction_yaws) != directions:
        raise RuntimeError("Albedo summary has no complete direction_yaw_degrees table")
    if (
        frames_per_direction <= 0
        or not isinstance(source_frames, list)
        or len(source_frames) != frames_per_direction
    ):
        raise RuntimeError("Albedo summary has no complete sampled_source_frames table")
    if directions != int(profile["grid"]["directions"]):
        raise RuntimeError("Albedo summary direction count does not match the player bake profile")
    if frames_per_direction != int(profile["grid"]["frames_per_direction"]):
        raise RuntimeError("Albedo summary frame count does not match the player bake profile")
    for key in ("direction_zero", "direction_order"):
        if summary.get(key) != profile["grid"][key]:
            raise RuntimeError(
                f"Albedo summary {key}={summary.get(key)!r}, profile requires {profile['grid'][key]!r}"
            )
    return summary, path


def attach_clip_to_turntable(
    clip_id: str,
    clip_objects: list[bpy.types.Object],
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Build the same carrier -> turntable hierarchy used by the albedo pass."""
    carrier = bpy.data.objects.new(f"{clip_id}_shadow_carrier", None)
    bpy.context.collection.objects.link(carrier)
    turntable = bpy.data.objects.new(f"{clip_id}_shadow_turntable", None)
    bpy.context.collection.objects.link(turntable)
    carrier.parent = turntable
    owned = set(clip_objects)
    for obj in clip_objects:
        if obj.parent in owned:
            continue
        world = obj.matrix_world.copy()
        obj.parent = carrier
        obj.matrix_parent_inverse = carrier.matrix_world.inverted()
        obj.matrix_world = world
    return carrier, turntable


def position_world_origin_at_source_anchor(
    camera: bpy.types.Object,
    anchor_px: tuple[int, int],
) -> dict:
    """Translate one fixed ORTHO camera so world origin lands at the authored crop anchor."""
    scene = bpy.context.scene
    target_u = anchor_px[0] / float(SOURCE_FRAME_WIDTH_PX)
    target_v = 1.0 - anchor_px[1] / float(SOURCE_FRAME_HEIGHT_PX)
    height_units = float(camera.data.ortho_scale)
    width_units = height_units * SOURCE_FRAME_WIDTH_PX / float(SOURCE_FRAME_HEIGHT_PX)
    right = Vector(camera.matrix_world.col[0][:3]).normalized()
    up = Vector(camera.matrix_world.col[1][:3]).normalized()
    for _ in range(4):
        bpy.context.view_layer.update()
        origin_uv = world_to_camera_view(scene, camera, Vector((0.0, 0.0, 0.0)))
        camera.location += right * ((origin_uv.x - target_u) * width_units)
        camera.location += up * ((origin_uv.y - target_v) * height_units)

    bpy.context.view_layer.update()
    origin_uv = world_to_camera_view(scene, camera, Vector((0.0, 0.0, 0.0)))
    actual_px = [
        float(origin_uv.x) * SOURCE_FRAME_WIDTH_PX,
        (1.0 - float(origin_uv.y)) * SOURCE_FRAME_HEIGHT_PX,
    ]
    if abs(actual_px[0] - anchor_px[0]) > 0.05 or abs(actual_px[1] - anchor_px[1]) > 0.05:
        raise RuntimeError(
            f"Fixed shadow camera anchor calibration failed: projected origin {actual_px}, "
            f"wanted {list(anchor_px)}"
        )
    return {
        "source_anchor_px": list(anchor_px),
        "source_anchor_uv": [target_u, 1.0 - target_v],
        "projected_world_origin_px": [round(actual_px[0], 6), round(actual_px[1], 6)],
        "projected_world_origin_uv": [round(float(origin_uv.x), 8), round(1.0 - float(origin_uv.y), 8)],
    }


def configure_cycles_shadow_scene(
    meshes: list[bpy.types.Object],
    sun: bpy.types.Object,
    bake_profile: dict,
) -> tuple[bpy.types.Object, dict]:
    scene = bpy.context.scene
    render = bake_profile["render"]
    lighting = bake_profile["lighting"]
    scene.render.engine = EXPECTED_SHADOW_ENGINE
    scene.cycles.samples = EXPECTED_CYCLES_SAMPLES
    scene.cycles.use_denoising = True

    # Prefer the local CUDA device when available. The inherited contract fixes
    # engine/samples/denoising, not the execution device; GPU rendering preserves
    # the same physical pass while making 1,280 frames practical to regenerate.
    cycles_device = {"requested": "CPU", "active_devices": []}
    try:
        preferences = bpy.context.preferences.addons["cycles"].preferences
        preferences.compute_device_type = "CUDA"
        preferences.get_devices()
        active_devices = []
        for device in preferences.devices:
            use_device = str(device.type) == "CUDA"
            device.use = use_device
            if use_device:
                active_devices.append(str(device.name))
        if active_devices:
            scene.cycles.device = "GPU"
            cycles_device = {"requested": "CUDA", "active_devices": active_devices}
    except Exception as error:
        cycles_device = {"requested": "CPU", "active_devices": [], "fallback_reason": str(error)}
    scene.render.resolution_x = SOURCE_FRAME_WIDTH_PX
    scene.render.resolution_y = SOURCE_FRAME_HEIGHT_PX
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    for mesh in meshes:
        mesh.hide_render = False
        mesh.hide_viewport = False
        mesh.visible_camera = False
        mesh.visible_shadow = True

    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.name.startswith("PlayerCanonBounce"):
            obj.hide_render = True
    sun.hide_render = False
    sun.data.use_shadow = True
    sun.rotation_euler = (
        math.radians(float(lighting["shadow_sun_elevation_degrees"])),
        0.0,
        math.radians(float(lighting["sun_azimuth_degrees"])),
    )
    sun.data.energy = float(lighting["shadow_sun_energy"])

    size = SHADOW_CATCHER_HALF_EXTENT_M
    plane_mesh = bpy.data.meshes.new("PlayerShadowCatcherPlaneMesh")
    plane_mesh.from_pydata(
        [
            (-size, -size, SHADOW_CATCHER_Z_M),
            (size, -size, SHADOW_CATCHER_Z_M),
            (size, size, SHADOW_CATCHER_Z_M),
            (-size, size, SHADOW_CATCHER_Z_M),
        ],
        [],
        [(0, 1, 2, 3)],
    )
    plane_mesh.update()
    plane = bpy.data.objects.new("PlayerShadowCatcherPlane", plane_mesh)
    bpy.context.collection.objects.link(plane)
    plane.is_shadow_catcher = True

    if str(render["shadow_engine"]) != scene.render.engine:
        raise RuntimeError("Cycles shadow engine failed to activate")
    return plane, cycles_device


def raw_shadow_alpha_report(path: Path, expected_anchor_px: tuple[int, int]) -> dict:
    image = bpy.data.images.load(str(path))
    try:
        width, height = int(image.size[0]), int(image.size[1])
        if (width, height) != (SOURCE_FRAME_WIDTH_PX, SOURCE_FRAME_HEIGHT_PX):
            raise RuntimeError(
                f"Raw shadow {path.name} is {(width, height)}, "
                f"expected {SOURCE_FRAME_WIDTH_PX}x{SOURCE_FRAME_HEIGHT_PX}"
            )
        alpha = list(image.pixels)[3::4]
        # Cycles/denoising can leave isolated 7..9 alpha specks on the catcher
        # border. Select the first canonical tree threshold whose *bbox* is not
        # the whole plane, then validate the real cast at that threshold.
        selected_threshold = None
        for threshold in RAW_ALPHA_THRESHOLDS_U8:
            threshold_points = []
            for bottom_y in range(height):
                top_y = height - 1 - bottom_y
                row = bottom_y * width
                for x in range(width):
                    value = max(0, min(255, int(round(alpha[row + x] * 255.0))))
                    if value > threshold:
                        threshold_points.append((x, top_y))
            if not threshold_points:
                continue
            test_x0 = min(point[0] for point in threshold_points)
            test_y0 = min(point[1] for point in threshold_points)
            test_x1 = max(point[0] for point in threshold_points) + 1
            test_y1 = max(point[1] for point in threshold_points) + 1
            test_coverage = (test_x1 - test_x0) * (test_y1 - test_y0) / float(width * height)
            test_margins = (
                test_x0,
                test_y0,
                width - test_x1,
                height - test_y1,
            )
            if test_coverage <= RAW_ALPHA_MAX_BBOX_COVERAGE \
                    and min(test_margins) >= RAW_ALPHA_MIN_BORDER_MARGIN_PX:
                selected_threshold = threshold
                break
        if selected_threshold is None:
            raise RuntimeError(
                f"Raw shadow {path.name} is empty or resolves to the whole catcher plane "
                f"at thresholds {list(RAW_ALPHA_THRESHOLDS_U8)}"
            )

        active: list[tuple[int, int, int]] = []
        border_alpha_max = 0
        max_alpha = 0
        alpha_sum = 0
        weighted_x = 0
        weighted_y = 0
        border_sides: set[str] = set()

        for bottom_y in range(height):
            top_y = height - 1 - bottom_y
            row = bottom_y * width
            for x in range(width):
                value = max(0, min(255, int(round(alpha[row + x] * 255.0))))
                max_alpha = max(max_alpha, value)
                if x == 0 or x == width - 1 or top_y == 0 or top_y == height - 1:
                    border_alpha_max = max(border_alpha_max, value)
                if value <= selected_threshold:
                    continue
                active.append((x, top_y, value))
                alpha_sum += value
                weighted_x += x * value
                weighted_y += top_y * value
                if x == 0:
                    border_sides.add("left")
                if x == width - 1:
                    border_sides.add("right")
                if top_y == 0:
                    border_sides.add("top")
                if top_y == height - 1:
                    border_sides.add("bottom")

        if not active:
            raise RuntimeError(
                f"Raw shadow {path.name} is empty at alpha>{selected_threshold}; max alpha={max_alpha}"
            )
        x0 = min(point[0] for point in active)
        y0 = min(point[1] for point in active)
        x1 = max(point[0] for point in active) + 1
        y1 = max(point[1] for point in active) + 1
        bbox_coverage = (x1 - x0) * (y1 - y0) / float(width * height)
        margins = {
            "left": x0,
            "top": y0,
            "right": width - x1,
            "bottom": height - y1,
        }
        if bbox_coverage > RAW_ALPHA_MAX_BBOX_COVERAGE:
            raise RuntimeError(
                f"Raw shadow {path.name} covers {bbox_coverage:.3f} of the whole plane; "
                f"maximum is {RAW_ALPHA_MAX_BBOX_COVERAGE:.3f}"
            )
        if border_sides:
            raise RuntimeError(f"Raw shadow {path.name} touches frame border on {sorted(border_sides)}")
        tight_sides = [side for side, margin in margins.items() if margin < RAW_ALPHA_MIN_BORDER_MARGIN_PX]
        if tight_sides:
            raise RuntimeError(
                f"Raw shadow {path.name} has less than {RAW_ALPHA_MIN_BORDER_MARGIN_PX}px clearance on {tight_sides}"
            )

        centroid = [weighted_x / float(alpha_sum), weighted_y / float(alpha_sum)]
        return {
            "alpha_threshold_u8": selected_threshold,
            "alpha_max_u8": max_alpha,
            "alpha_sum_u8": alpha_sum,
            "active_pixel_count": len(active),
            "active_pixel_fraction": round(len(active) / float(width * height), 8),
            "bbox_xywh": [x0, y0, x1 - x0, y1 - y0],
            "bbox_coverage": round(bbox_coverage, 8),
            "border_alpha_max_u8": border_alpha_max,
            "border_sides_alpha_gt_threshold": sorted(border_sides),
            "border_margin_px": margins,
            "weighted_centroid_px": [round(centroid[0], 5), round(centroid[1], 5)],
            "centroid_from_source_anchor_px": [
                round(centroid[0] - expected_anchor_px[0], 5),
                round(centroid[1] - expected_anchor_px[1], 5),
            ],
        }
    finally:
        bpy.data.images.remove(image)


def render_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = parse_args()
    profile = PLAYER_BAKE.load_json(args.profile)
    inherited_path = Path(profile["inherits_bake_profile"])
    if not inherited_path.is_absolute():
        inherited_path = PLAYER_BAKE.REPO_ROOT / inherited_path
    bake_profile = PLAYER_BAKE.load_json(inherited_path)
    source_anchor_px = validate_shadow_contract(profile, bake_profile)

    albedo_frames_dir = args.albedo_frames_dir.resolve()
    albedo_summary, albedo_summary_path = load_albedo_summary(
        args.clip_id,
        albedo_frames_dir,
        profile,
    )
    clip = next(item for item in profile["clips"] if item["clip_id"] == args.clip_id)
    source = profile["source"]
    motion = profile["motion"]
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    reference_height_m, reference_floor_z = PLAYER_BAKE.measure_reference_height(profile)
    require_close(
        "reference_height_m",
        reference_height_m,
        float(albedo_summary["reference_height_m"]),
        tolerance=1e-4,
    )

    PLAYER_BAKE.clear_scene()
    clip_objects = PLAYER_BAKE.import_fbx(Path(source["clip_dir"]) / str(clip["mixamo_file"]))
    meshes = [obj for obj in clip_objects if obj.type == "MESH"]
    armature = PLAYER_BAKE.single_armature(clip_objects, "mixamo clip")
    if not meshes:
        raise RuntimeError(f"Clip {clip['mixamo_file']} carries no mesh")
    carrier, turntable = attach_clip_to_turntable(args.clip_id, clip_objects)

    camera, sun = PLAYER_BAKE.setup_render(
        SOURCE_FRAME_WIDTH_PX,
        SOURCE_FRAME_HEIGHT_PX,
        bake_profile,
        reference_height_m,
    )
    albedo_ortho_scale = float(albedo_summary["ortho_scale"])
    shadow_ortho_scale = albedo_ortho_scale * SOURCE_FRAME_HEIGHT_PX / 288.0
    camera.data.ortho_scale = shadow_ortho_scale
    bpy.context.view_layer.update()
    anchor_evidence = position_world_origin_at_source_anchor(camera, source_anchor_px)
    _shadow_catcher, cycles_device = configure_cycles_shadow_scene(meshes, sun, bake_profile)

    albedo_pixels_per_world_unit = 288.0 / albedo_ortho_scale
    shadow_pixels_per_world_unit = SOURCE_FRAME_HEIGHT_PX / shadow_ortho_scale
    require_close(
        "shadow pixels_per_world_unit",
        shadow_pixels_per_world_unit,
        albedo_pixels_per_world_unit,
        tolerance=1e-6,
    )

    scene = bpy.context.scene
    direction_yaws = albedo_summary["direction_yaw_degrees"]
    sampled_source_frames = albedo_summary["sampled_source_frames"]
    root_bone = str(motion["root_bone"])
    cancel_horizontal = bool(motion["cancel_horizontal_travel"])
    if cancel_horizontal != bool(albedo_summary.get("horizontal_travel_cancelled", False)):
        raise RuntimeError("Player motion profile disagrees with the authoritative albedo correction mode")

    turntable.rotation_euler.z = 0.0
    PLAYER_BAKE.set_source_frame(scene, float(albedo_summary["source_frame_start"]))
    carrier.location = Vector((0.0, 0.0, 0.0))
    bpy.context.view_layer.update()
    root_reference = PLAYER_BAKE.root_translation_in(turntable, armature, root_bone)

    raw_frames = []
    for direction, yaw_value in enumerate(direction_yaws):
        if args.only_direction is not None and direction != args.only_direction:
            continue
        yaw_degrees = float(yaw_value)
        turntable.rotation_euler.z = math.radians(yaw_degrees)
        for frame_index, source_frame_value in enumerate(sampled_source_frames):
            if args.only_frame is not None and frame_index != args.only_frame:
                continue
            source_frame = float(source_frame_value)
            PLAYER_BAKE.set_source_frame(scene, source_frame)
            carrier.location = Vector((0.0, 0.0, 0.0))
            bpy.context.view_layer.update()
            correction = Vector((0.0, 0.0, -reference_floor_z))
            if cancel_horizontal:
                travelled = PLAYER_BAKE.root_translation_in(turntable, armature, root_bone) - root_reference
                correction.x -= travelled.x
                correction.y -= travelled.y
            carrier.location = correction
            bpy.context.view_layer.update()

            name = (
                f"{args.clip_id}_shadow_raw_dir{direction:02d}_frame{frame_index:02d}.png"
            )
            path = output_dir / name
            render_png(path)
            evidence = raw_shadow_alpha_report(path, source_anchor_px)
            raw_frames.append(
                {
                    "file": name,
                    "direction": direction,
                    "frame_index": frame_index,
                    "direction_yaw_degrees": yaw_value,
                    "source_frame": source_frame_value,
                    "raw_alpha": evidence,
                }
            )

    summary_bytes = albedo_summary_path.read_bytes()
    summary = {
        "clip_id": args.clip_id,
        "source_clip": clip["mixamo_file"],
        "albedo_render_summary": str(albedo_summary_path),
        "albedo_render_summary_sha256": hashlib.sha256(summary_bytes).hexdigest(),
        "bake_profile": {
            "profile_id": bake_profile["profile_id"],
            "version": bake_profile["version"],
        },
        "directions": len(direction_yaws),
        "frames_per_direction": len(sampled_source_frames),
        "direction_zero": albedo_summary["direction_zero"],
        "direction_order": albedo_summary["direction_order"],
        "direction_yaw_degrees": direction_yaws,
        "sampled_source_frames": sampled_source_frames,
        "source_frame_start": albedo_summary["source_frame_start"],
        "source_frame_end": albedo_summary["source_frame_end"],
        "loop": albedo_summary["loop"],
        "horizontal_travel_cancelled": cancel_horizontal,
        "albedo_anchor_uv": albedo_summary["foot_anchor_uv"],
        "camera_elevation_degrees": albedo_summary["camera_elevation_degrees"],
        "sun_azimuth_degrees": EXPECTED_SUN_AZIMUTH_DEGREES,
        "shadow_sun_elevation_degrees": EXPECTED_SUN_ELEVATION_DEGREES,
        "shadow_sun_energy": EXPECTED_SUN_ENERGY,
        "cycles_samples": EXPECTED_CYCLES_SAMPLES,
        "denoising": True,
        "source_frame_width_px": SOURCE_FRAME_WIDTH_PX,
        "source_frame_height_px": SOURCE_FRAME_HEIGHT_PX,
        "anchor": anchor_evidence,
        "camera": {
            "type": str(camera.data.type),
            "sensor_fit": str(camera.data.sensor_fit),
            "camera_elevation_degrees": albedo_summary["camera_elevation_degrees"],
            "albedo_ortho_scale": albedo_ortho_scale,
            "shadow_ortho_scale": shadow_ortho_scale,
            "ortho_scale_formula": "albedo_ortho_scale * 192 / 288",
            "pixels_per_world_unit": shadow_pixels_per_world_unit,
            "location": [float(value) for value in camera.location],
            "rotation_euler_radians": [float(value) for value in camera.rotation_euler],
        },
        "sun": {
            "fixed_shadow_direction": bake_profile["lighting"]["fixed_shadow_direction"],
            "azimuth_degrees": EXPECTED_SUN_AZIMUTH_DEGREES,
            "elevation_degrees": EXPECTED_SUN_ELEVATION_DEGREES,
            "energy": EXPECTED_SUN_ENERGY,
        },
        "render": {
            "engine": EXPECTED_SHADOW_ENGINE,
            "samples": EXPECTED_CYCLES_SAMPLES,
            "use_denoising": True,
            "transparent_film": True,
            "color_mode": "RGBA",
            "resolution_px": [SOURCE_FRAME_WIDTH_PX, SOURCE_FRAME_HEIGHT_PX],
            "device": cycles_device,
        },
        "shadow_catcher": {
            "z_m": SHADOW_CATCHER_Z_M,
            "half_extent_m": SHADOW_CATCHER_HALF_EXTENT_M,
            "bounce_in_shadow_pass": False,
        },
        "raw_alpha_contract": {
            "thresholds_u8": list(RAW_ALPHA_THRESHOLDS_U8),
            "minimum_border_margin_px": RAW_ALPHA_MIN_BORDER_MARGIN_PX,
            "maximum_bbox_coverage": RAW_ALPHA_MAX_BBOX_COVERAGE,
            "fallback": "forbidden",
        },
        "frames_rendered": len(raw_frames),
        "raw_frames": raw_frames,
    }
    summary_path = output_dir / f"{args.clip_id}_shadow_render_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("PLAYER_SHADOW_BAKE_COMPLETE")
    print(
        json.dumps(
            {
                "clip_id": args.clip_id,
                "frames_rendered": len(raw_frames),
                "summary": str(summary_path),
                "source_anchor_px": list(source_anchor_px),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
