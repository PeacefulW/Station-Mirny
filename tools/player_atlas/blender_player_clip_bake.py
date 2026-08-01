"""Bake one player clip into 16 directions x N frames under the tree bake canon.

This script does not own camera or lighting values. They come verbatim from
`tools/tree_atlas/layered_asset_bake_profile.json`, the same contract the shipped
trees, bushes and grass use, so the player sits in the same world instead of
being filmed with a private camera.

Each Mixamo clip ships the rigged character itself, so the clip *is* the source:
mesh, skeleton and animation arrive together and are rendered directly. An
earlier version retargeted mixamorig onto a separately rigged AccuRig model and
distorted the body; there is no retarget step here any more.

Three things are deliberate and easy to get wrong:

* The orthographic scale is derived once from a reference clip's standing height
  and reused for every direction and every clip. Fitting the camera per frame or
  per clip would make the character breathe in size between animations.
* The turntable rotates the *model*, never the sun. The sun stays at the canon
  azimuth, so turning the character changes which side of him is lit - the same
  thing that happens to every other object in the world.
* Mixamo clips travel across their scene. The game moves the body itself, so
  horizontal travel is cancelled per frame while the vertical bob is kept.

Usage:
    blender --background --factory-startup --python blender_player_clip_bake.py -- \
        <clip_id> <output_dir> [--profile <path>]
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parent.parent
DEFAULT_PROFILE = TOOL_DIR / "player_bake_profile.json"


def argv_after_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip_id")
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    return parser.parse_args(argv_after_separator())


def load_json(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def eevee_engine_name() -> str:
    items = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    for candidate in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        if candidate in items:
            return candidate
    raise RuntimeError("No EEVEE render engine available in this Blender build")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_fbx(path: Path) -> list[bpy.types.Object]:
    if not path.exists():
        raise RuntimeError(f"Source FBX not found: {path}")
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def single_armature(objects: list[bpy.types.Object], label: str) -> bpy.types.Object:
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected exactly one {label} armature, found {len(armatures)}")
    return armatures[0]


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def mesh_world_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        matrix = evaluated.matrix_world
        for corner in evaluated.bound_box:
            point = matrix @ Vector(corner)
            for axis in range(3):
                mins[axis] = min(mins[axis], point[axis])
                maxs[axis] = max(maxs[axis], point[axis])
    return mins, maxs


def apply_basecolor_override(meshes: list[bpy.types.Object], texture_path: Path) -> bool:
    """Swap Mixamo's re-encoded 512px diffuse for the model's own 1024px basecolor.

    Mixamo decimates the mesh and re-encodes the texture on upload. The UV layout
    survives that trip, so the higher-resolution source map still lines up.
    """
    if not texture_path.exists():
        raise RuntimeError(f"basecolor_override not found: {texture_path}")
    image = bpy.data.images.load(str(texture_path))
    replaced = False
    for mesh in meshes:
        for slot in mesh.material_slots:
            material = slot.material
            if material is None or not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE":
                    node.image = image
                    replaced = True
    if not replaced:
        raise RuntimeError("basecolor_override requested but no image texture node was found")
    return replaced


def clip_frame_range(armature: bpy.types.Object) -> tuple[int, int]:
    if armature.animation_data is None or armature.animation_data.action is None:
        raise RuntimeError("Mixamo clip carries no action on its armature")
    start, end = armature.animation_data.action.frame_range
    return int(math.floor(start)), int(math.ceil(end))


def root_translation_in(reference: bpy.types.Object, armature: bpy.types.Object, root_bone: str) -> Vector:
    """Root bone position expressed in `reference`'s space.

    Travel must be cancelled in the turntable's space, not in world space: the
    turntable spins between directions, so a world-space correction would be
    applied along the wrong axes. Under this 28 degree camera a depth error also
    reads as a vertical one, which is what made the figure appear to take off.
    """
    pose_bone = armature.pose.bones.get(root_bone)
    if pose_bone is None:
        raise RuntimeError(f"Root bone '{root_bone}' not present in clip armature")
    world = (armature.matrix_world @ pose_bone.matrix).translation
    return reference.matrix_world.inverted() @ world


def set_source_frame(scene: bpy.types.Scene, source_frame: float) -> None:
    """Evaluate animation at an exact (possibly fractional) source phase."""
    whole_frame = int(math.floor(source_frame))
    scene.frame_set(whole_frame, subframe=source_frame - whole_frame)


def loop_endpoint_pose_report(
    scene: bpy.types.Scene,
    armature: bpy.types.Object,
    root_bone: str,
    frame_start: float,
    frame_end: float,
) -> dict:
    """Compare authored loop endpoints without treating root XY travel as pose.

    Mixamo locomotion moves the hips through the scene. That translation is
    cancelled by the bake, so it must not make a valid cyclic pose fail. Local
    bone rotation, vertical translation and scale remain part of the check.
    """

    def signature(source_frame: float) -> dict:
        set_source_frame(scene, source_frame)
        bpy.context.view_layer.update()
        result = {}
        for bone in armature.pose.bones:
            location, rotation, scale = bone.matrix_basis.decompose()
            if bone.name == root_bone:
                location.x = 0.0
                location.y = 0.0
            result[bone.name] = (location.copy(), rotation.copy(), scale.copy())
        return result

    first = signature(frame_start)
    last = signature(frame_end)
    squared_components = []
    max_location = 0.0
    max_angle = 0.0
    max_scale = 0.0
    for bone_name, (first_location, first_rotation, first_scale) in first.items():
        last_location, last_rotation, last_scale = last[bone_name]
        location_delta = (first_location - last_location).length
        angle_delta = first_rotation.rotation_difference(last_rotation).angle
        scale_delta = (first_scale - last_scale).length
        squared_components.extend((location_delta ** 2, angle_delta ** 2, scale_delta ** 2))
        max_location = max(max_location, location_delta)
        max_angle = max(max_angle, angle_delta)
        max_scale = max(max_scale, scale_delta)
    rms = math.sqrt(sum(squared_components) / max(len(squared_components), 1))
    return {
        "rms": float(rms),
        "max_bone_location_delta": float(max_location),
        "max_bone_angle_delta_radians": float(max_angle),
        "max_bone_scale_delta": float(max_scale),
    }


def setup_render(frame_w: int, frame_h: int, bake_profile: dict, reference_height_m: float) -> tuple[bpy.types.Object, bpy.types.Object]:
    scene = bpy.context.scene
    render_profile = bake_profile["render"]
    lighting_profile = bake_profile["lighting"]
    camera_profile = bake_profile["camera"]

    scene.render.engine = eevee_engine_name()
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = int(render_profile["samples"])
    scene.render.resolution_x = frame_w
    scene.render.resolution_y = frame_h
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = bool(render_profile["transparent_film"])
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = str(render_profile["color_mode"])
    scene.view_settings.view_transform = str(render_profile["view_transform"])
    scene.view_settings.look = str(render_profile["look"])
    scene.view_settings.exposure = float(render_profile["exposure"])
    scene.view_settings.gamma = float(render_profile["gamma"])

    # Camera geometry is copied from the tree canon so the elevation matches
    # exactly: location_y=-3.0 with height_offset=1.6 is 28.07 degrees. Only the
    # aim height differs, because a tree and a man are framed differently.
    target_z = float(camera_profile["target_z_fraction"]) * reference_height_m
    camera_data = bpy.data.cameras.new("PlayerCanonCamera")
    camera = bpy.data.objects.new("PlayerCanonCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = str(camera_profile["type"])
    # A portrait frame must resolve ortho_scale against its height, not against
    # whichever dimension Blender's AUTO fit happens to pick.
    camera_data.sensor_fit = "VERTICAL"
    camera.location = Vector((0.0, float(camera_profile["location_y"]), target_z + float(camera_profile["height_offset"])))
    look_at(camera, Vector((0.0, 0.0, target_z)))
    camera_data.clip_start = 0.01
    camera_data.clip_end = 100.0

    sun_data = bpy.data.lights.new("PlayerCanonSun", "SUN")
    sun_data.energy = float(lighting_profile["albedo_sun_energy"])
    sun = bpy.data.objects.new("PlayerCanonSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (
        math.radians(float(lighting_profile["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(float(lighting_profile["sun_azimuth_degrees"])),
    )

    bounce_profile = lighting_profile["bounce"]
    bounce_data = bpy.data.lights.new("PlayerCanonBounce", "AREA")
    bounce_data.energy = float(bounce_profile["energy"])
    bounce_data.size = float(bounce_profile["size"])
    bounce_data.color = tuple(float(v) for v in bounce_profile["color"])
    bounce_data.use_shadow = bool(bounce_profile["casts_shadow"])
    bounce = bpy.data.objects.new("PlayerCanonBounce", bounce_data)
    bpy.context.collection.objects.link(bounce)
    bounce.location = Vector(tuple(float(v) for v in bounce_profile["location"]))
    bounce.rotation_euler = (math.radians(float(bounce_profile["pitch_degrees"])), 0.0, 0.0)
    return camera, sun


def calibrate_framing(
    camera: bpy.types.Object,
    reference_height_m: float,
    height_fraction: float,
    ground_anchor_fraction: float,
) -> dict:
    """Lock scale and vertical offset once, for every clip and every direction.

    Scale is measured against one reference standing height, not against a posed
    bounding box: fitting per clip would make the character change size between
    animations. The offset then pins the world origin - the point between the
    feet - to a fixed line in the frame, so every clip shares one ground line.
    """
    scene = bpy.context.scene
    foot_world = Vector((0.0, 0.0, 0.0))
    head_world = Vector((0.0, 0.0, reference_height_m))

    for _ in range(4):
        bpy.context.view_layer.update()
        foot = world_to_camera_view(scene, camera, foot_world)
        head = world_to_camera_view(scene, camera, head_world)
        span = abs(head.y - foot.y)
        if span <= 1e-6:
            raise RuntimeError("Camera calibration failed: reference height projects to zero")
        camera.data.ortho_scale *= span / height_fraction

    # world_to_camera_view puts 0 at the frame bottom; the profile states the
    # anchor as a fraction from the top, matching how sprite frames are read.
    wanted_from_bottom = 1.0 - ground_anchor_fraction
    up_axis = camera.matrix_world.to_3x3() @ Vector((0.0, 1.0, 0.0))
    for _ in range(6):
        bpy.context.view_layer.update()
        foot = world_to_camera_view(scene, camera, foot_world)
        delta = foot.y - wanted_from_bottom
        if abs(delta) < 1e-5:
            break
        camera.location += up_axis * (delta * camera.data.ortho_scale)

    bpy.context.view_layer.update()
    foot = world_to_camera_view(scene, camera, foot_world)
    head = world_to_camera_view(scene, camera, head_world)
    return {
        "ortho_scale": float(camera.data.ortho_scale),
        "foot_anchor_uv": [round(float(foot.x), 5), round(float(1.0 - foot.y), 5)],
        "reference_height_frame_fraction": round(float(abs(head.y - foot.y)), 5),
    }


def measure_reference_height(profile: dict) -> tuple[float, float]:
    """Standing height and floor level, measured once on the reference clip.

    Every clip is then rendered at that one scale. Measuring per clip would let
    a crouched running pose zoom the camera in and make the character change
    size when the player starts moving.
    """
    source = profile["source"]
    reference_path = Path(source["clip_dir"]) / str(source["reference_clip"])
    clear_scene()
    objects = import_fbx(reference_path)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"Reference clip carries no mesh: {reference_path}")
    bpy.context.scene.frame_set(int(source["reference_frame"]))
    bpy.context.view_layer.update()
    mins, maxs = mesh_world_bounds(meshes)
    return float(maxs.z - mins.z), float(mins.z)


def frame_alpha_report(path: Path) -> dict:
    """Which borders the silhouette touches, and where its lowest pixel sits.

    The lowest pixel is what the shadow must stand on. The projection of world
    origin is *not* that line: under a 28 degree camera the feet sit forward of
    the body centre and land lower on screen, so pinning the shadow to the
    origin line leaves the character hovering above its own shadow.
    """
    image = bpy.data.images.load(str(path))
    try:
        width, height = image.size
        alpha = list(image.pixels)[3::4]
        threshold = 8.0 / 255.0
        sides = []

        def row_hit(y: int) -> bool:
            base = y * width
            return any(alpha[base + x] > threshold for x in range(width))

        def column_hit(x: int) -> bool:
            return any(alpha[y * width + x] > threshold for y in range(height))

        # Blender image rows start at the bottom.
        if row_hit(0):
            sides.append("bottom")
        if row_hit(height - 1):
            sides.append("top")
        if column_hit(0):
            sides.append("left")
        if column_hit(width - 1):
            sides.append("right")

        lowest_from_top = None
        for y in range(height):
            if row_hit(y):
                lowest_from_top = (height - 1 - y) / float(height - 1)
                break
        return {"clipped": sides, "foot_uv": lowest_from_top}
    finally:
        bpy.data.images.remove(image)


def main() -> None:
    args = parse_args()
    profile = load_json(args.profile)
    bake_profile = load_json(REPO_ROOT / profile["inherits_bake_profile"])

    clip = next((c for c in profile["clips"] if c["clip_id"] == args.clip_id), None)
    if clip is None:
        raise RuntimeError(f"Clip id '{args.clip_id}' is not declared in {args.profile}")

    frame_profile = profile["frame"]
    grid = profile["grid"]
    source = profile["source"]
    motion = profile["motion"]

    frame_w = int(frame_profile["albedo_width_px"])
    frame_h = int(frame_profile["albedo_height_px"])
    directions = int(grid["directions"])
    frames_per_direction = int(grid["frames_per_direction"])

    # Blender resolves a relative render.filepath against the blend file, not the
    # working directory, so a relative argument silently writes nothing here.
    output_dir = Path(args.output_dir).resolve()
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    reference_height_m, reference_floor_z = measure_reference_height(profile)

    clear_scene()
    clip_objects = import_fbx(Path(source["clip_dir"]) / clip["mixamo_file"])
    meshes = [obj for obj in clip_objects if obj.type == "MESH"]
    armature = single_armature(clip_objects, "mixamo clip")
    if not meshes:
        raise RuntimeError(f"Clip {clip['mixamo_file']} carries no mesh")

    basecolor_override = source.get("basecolor_override", "")
    if basecolor_override:
        apply_basecolor_override(meshes, Path(basecolor_override))

    # Rotation and per-frame recentring are separate parents so they cannot
    # fight: the turntable spins, the carrier slides.
    carrier = bpy.data.objects.new(f"{args.clip_id}_carrier", None)
    bpy.context.collection.objects.link(carrier)
    turntable = bpy.data.objects.new(f"{args.clip_id}_turntable", None)
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

    camera, _sun = setup_render(frame_w, frame_h, bake_profile, reference_height_m)
    framing = calibrate_framing(
        camera,
        reference_height_m,
        float(frame_profile["figure_height_fraction"]),
        float(frame_profile["ground_anchor_y_fraction"]),
    )

    frame_start, frame_end = clip_frame_range(armature)
    loops = bool(clip.get("loop", False))
    root_bone = str(motion["root_bone"])
    cancel_horizontal = bool(motion["cancel_horizontal_travel"])
    loop_pose = None
    if loops:
        loop_pose = loop_endpoint_pose_report(
            bpy.context.scene,
            armature,
            root_bone,
            float(frame_start),
            float(frame_end),
        )
        pose_rms_limit = float(profile["loop_validation"]["source_endpoint_pose_rms_max"])
        if loop_pose["rms"] > pose_rms_limit:
            raise RuntimeError(
                f"Clip '{args.clip_id}' does not close at its authored endpoint: "
                f"pose RMS {loop_pose['rms']:.6f} exceeds {pose_rms_limit:.6f}. "
                "Do not crop or declare it looped without a seamless endpoint."
            )

    source_span = max(float(frame_end - frame_start), 0.0)
    if loops:
        # The authored endpoint is a copy (or near-copy) of the first pose.
        # Uniform phases on [start, end) omit that duplicate and make the wrap
        # step exactly the same duration as every internal step.
        sampled_source_frames = [
            float(frame_start) + frame_index * source_span / frames_per_direction
            for frame_index in range(frames_per_direction)
        ]
    elif frames_per_direction > 1:
        sampled_source_frames = [
            float(frame_start) + frame_index * source_span / (frames_per_direction - 1)
            for frame_index in range(frames_per_direction)
        ]
    else:
        sampled_source_frames = [float(frame_start)]

    set_source_frame(bpy.context.scene, float(frame_start))
    carrier.location = Vector((0.0, 0.0, 0.0))
    bpy.context.view_layer.update()
    root_reference = root_translation_in(turntable, armature, root_bone)

    scene = bpy.context.scene
    rendered = []
    foot_samples: list[float] = []
    direction_yaw_degrees = []
    for direction in range(directions):
        # Project-wide turntable contract: row 0 faces screen north and rows
        # advance clockwise. Cardinal probes on this FBX under the canon camera
        # measured yaw 0=S, 90=E, 180=N, 270=W, hence 180-row*step.
        yaw_degrees = (180.0 - direction * (360.0 / directions)) % 360.0
        direction_yaw_degrees.append(round(yaw_degrees, 5))
        turntable.rotation_euler.z = math.radians(yaw_degrees)
        for frame_index, source_frame in enumerate(sampled_source_frames):
            set_source_frame(scene, source_frame)

            carrier.location = Vector((0.0, 0.0, 0.0))
            bpy.context.view_layer.update()
            correction = Vector((0.0, 0.0, -reference_floor_z))
            if cancel_horizontal:
                travelled = root_translation_in(turntable, armature, root_bone) - root_reference
                correction.x -= travelled.x
                correction.y -= travelled.y
            carrier.location = correction
            bpy.context.view_layer.update()

            path = output_dir / f"{args.clip_id}_dir{direction:02d}_frame{frame_index:02d}.png"
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            rendered.append(
                {
                    "direction": direction,
                    "frame_index": frame_index,
                    "source_frame": round(source_frame, 5),
                }
            )
            report = frame_alpha_report(path)
            if report["clipped"]:
                # A silently cropped limb ships as a mutilated sprite. The frame
                # profile is wrong, so say which frame and stop.
                raise RuntimeError(
                    f"Frame {path.name} touches the frame border on {report['clipped']}; "
                    f"lower figure_height_fraction or move ground_anchor_y_fraction"
                )
            if report["foot_uv"] is not None:
                foot_samples.append(report["foot_uv"])

    summary = {
        "clip_id": args.clip_id,
        "source_clip": clip["mixamo_file"],
        "source_clip_dir": source["clip_dir"],
        "basecolor_override": basecolor_override,
        "directions": directions,
        "frames_per_direction": frames_per_direction,
        "direction_zero": grid["direction_zero"],
        "direction_order": grid["direction_order"],
        "direction_yaw_degrees": direction_yaw_degrees,
        "frame_width_px": frame_w,
        "frame_height_px": frame_h,
        "reference_clip": source["reference_clip"],
        "reference_height_m": round(reference_height_m, 5),
        "ortho_scale": framing["ortho_scale"],
        "foot_anchor_uv": framing["foot_anchor_uv"],
        "reference_height_frame_fraction": framing["reference_height_frame_fraction"],
        "camera_elevation_degrees": math.degrees(
            math.atan2(float(bake_profile["camera"]["height_offset"]), abs(float(bake_profile["camera"]["location_y"])))
        ),
        "sun_azimuth_degrees": bake_profile["lighting"]["sun_azimuth_degrees"],
        "source_frame_start": frame_start,
        "source_frame_end": frame_end,
        "sampled_source_frames": [round(value, 5) for value in sampled_source_frames],
        "source_fps": round(float(scene.render.fps) / float(scene.render.fps_base), 5),
        "source_cycle_duration_seconds": (
            round(source_span / (float(scene.render.fps) / float(scene.render.fps_base)), 5)
            if loops else None
        ),
        "loop": loops,
        "loop_endpoint_pose": loop_pose,
        "frames_rendered": len(rendered),
        "horizontal_travel_cancelled": cancel_horizontal,
        # Where the feet actually land, measured from the rendered alpha. The
        # shadow stands on this line, not on the projection of world origin.
        "foot_contact_uv_median": round(sorted(foot_samples)[len(foot_samples) // 2], 5) if foot_samples else None,
        "foot_contact_uv_max": round(max(foot_samples), 5) if foot_samples else None,
    }
    (output_dir / f"{args.clip_id}_render_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("PLAYER_CLIP_BAKE_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
