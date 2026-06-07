import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


BONE_MAP = {
    "mixamorig:Hips": "Hip",
    "mixamorig:Spine": "Waist",
    "mixamorig:Spine1": "Spine01",
    "mixamorig:Spine2": "Spine02",
    "mixamorig:Neck": "NeckTwist01",
    "mixamorig:Head": "Head",
    "mixamorig:LeftShoulder": "L_Clavicle",
    "mixamorig:LeftArm": "L_Upperarm",
    "mixamorig:LeftForeArm": "L_Forearm",
    "mixamorig:LeftHand": "L_Hand",
    "mixamorig:RightShoulder": "R_Clavicle",
    "mixamorig:RightArm": "R_Upperarm",
    "mixamorig:RightForeArm": "R_Forearm",
    "mixamorig:RightHand": "R_Hand",
    "mixamorig:LeftUpLeg": "L_Thigh",
    "mixamorig:LeftLeg": "L_Calf",
    "mixamorig:LeftFoot": "L_Foot",
    "mixamorig:LeftToeBase": "L_ToeBase",
    "mixamorig:RightUpLeg": "R_Thigh",
    "mixamorig:RightLeg": "R_Calf",
    "mixamorig:RightFoot": "R_Foot",
    "mixamorig:RightToeBase": "R_ToeBase",
}


def argv_after_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def import_gltf(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def import_fbx(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def find_single_armature(objects: list[bpy.types.Object], label: str) -> bpy.types.Object:
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one {label} armature, found {len(armatures)}")
    return armatures[0]


def get_action_frame_range(armature: bpy.types.Object) -> tuple[int, int]:
    if armature.animation_data and armature.animation_data.action:
        action = armature.animation_data.action
        start, end = action.frame_range
        return int(math.floor(start)), int(math.ceil(end))
    if bpy.data.actions:
        action = bpy.data.actions[0]
        start, end = action.frame_range
        return int(math.floor(start)), int(math.ceil(end))
    return int(bpy.context.scene.frame_start), int(bpy.context.scene.frame_end)


def mesh_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    for obj in meshes:
        eval_obj = obj.evaluated_get(depsgraph)
        matrix = eval_obj.matrix_world
        for corner in eval_obj.bound_box:
            point = matrix @ Vector(corner)
            mins.x = min(mins.x, point.x)
            mins.y = min(mins.y, point.y)
            mins.z = min(mins.z, point.z)
            maxs.x = max(maxs.x, point.x)
            maxs.y = max(maxs.y, point.y)
            maxs.z = max(maxs.z, point.z)
    return mins, maxs


def recenter_target(target_objects: list[bpy.types.Object], target_meshes: list[bpy.types.Object]) -> None:
    mins, maxs = mesh_bounds(target_meshes)
    offset = Vector((-((mins.x + maxs.x) * 0.5), -((mins.y + maxs.y) * 0.5), -mins.z))
    target_set = set(target_objects)
    roots = [obj for obj in target_objects if obj.parent not in target_set]
    for obj in roots:
        obj.location += offset
    bpy.context.view_layer.update()


def configure_shadowless_render(size: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 15
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = 0.0
        scene.view_settings.gamma = 1.0
    except Exception:
        pass
    eevee = getattr(scene, "eevee", None)
    if eevee is not None:
        for prop in ("use_gtao", "use_raytracing", "use_shadows"):
            if hasattr(eevee, prop):
                setattr(eevee, prop, False)
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.80, 0.81, 0.82)


def add_light(name: str, location: tuple[float, float, float], power: float, size: float) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.size = size
    if hasattr(data, "use_shadow"):
        data.use_shadow = False
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    look_at(obj, Vector((0.0, 0.0, 0.8)))


def configure_camera_and_lights(target_meshes: list[bpy.types.Object]) -> None:
    mins, maxs = mesh_bounds(target_meshes)
    dims = maxs - mins
    radius = max(dims.x, dims.y, dims.z, 1.0)
    target = Vector((0.0, 0.0, max(dims.z * 0.47, 0.3)))

    add_light("player_soft_front_no_shadow", (0.0, -4.3 * radius, 5.5 * radius), 520.0, 5.0 * radius)
    add_light("player_soft_fill_no_shadow", (-3.0 * radius, 2.5 * radius, 4.2 * radius), 160.0, 6.0 * radius)
    add_light("player_soft_rim_no_shadow", (3.2 * radius, 3.0 * radius, 4.8 * radius), 95.0, 6.0 * radius)

    camera_data = bpy.data.cameras.new("orthographic_top_front_camera")
    camera = bpy.data.objects.new("orthographic_top_front_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    elevation = math.radians(62.0)
    distance = radius * 5.8
    camera.location = target + Vector((0.0, -math.cos(elevation) * distance, math.sin(elevation) * distance))
    look_at(camera, target)
    camera_data.type = "ORTHO"
    camera_data.clip_end = distance * 10.0
    camera_data.ortho_scale = max(dims.x, dims.y, dims.z) * 1.15


def hide_source_objects(source_objects: list[bpy.types.Object]) -> None:
    for obj in source_objects:
        obj.hide_render = True
        obj.hide_viewport = True


def retarget_action(source_armature: bpy.types.Object, target_armature: bpy.types.Object, frame_start: int, frame_end: int) -> dict:
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frame_end - frame_start + 1
    action = bpy.data.actions.new("station_mirny_run_retarget_test")
    target_armature.animation_data_create()
    target_armature.animation_data.action = action

    mapped = []
    missing_source = []
    missing_target = []
    for source_name, target_name in BONE_MAP.items():
        if source_name not in source_armature.pose.bones:
            missing_source.append(source_name)
            continue
        if target_name not in target_armature.pose.bones:
            missing_target.append(target_name)
            continue
        mapped.append((source_name, target_name))

    for target_bone in target_armature.pose.bones:
        target_bone.rotation_mode = "QUATERNION"

    target_root = target_armature.pose.bones.get("Root")
    target_hip = target_armature.pose.bones.get("Hip")
    rest_hip_z = target_hip.bone.matrix_local.translation.z if target_hip else 0.0

    for out_frame, source_frame in enumerate(range(frame_start, frame_end + 1), start=1):
        scene.frame_set(source_frame)
        bpy.context.view_layer.update()

        for source_name, target_name in mapped:
            src = source_armature.pose.bones[source_name]
            dst = target_armature.pose.bones[target_name]
            dst.rotation_mode = "QUATERNION"
            # Local rotation transfer is intentionally conservative. The
            # Mixamo and Tripo rest axes differ, so armature-space matrix
            # transfer can collapse the target mesh.
            dst.rotation_quaternion = src.matrix_basis.to_quaternion()
            dst.scale = (1.0, 1.0, 1.0)

        if target_root:
            target_root.location = (0.0, 0.0, 0.0)
            target_root.rotation_mode = "QUATERNION"
            target_root.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        if target_hip:
            target_hip.location.x = 0.0
            target_hip.location.y = 0.0
            target_hip.location.z = rest_hip_z + (target_hip.location.z - rest_hip_z) * 0.25

        for _source_name, target_name in mapped:
            dst = target_armature.pose.bones[target_name]
            dst.keyframe_insert("location", frame=out_frame)
            dst.keyframe_insert("rotation_quaternion", frame=out_frame)
            dst.keyframe_insert("scale", frame=out_frame)
        if target_root:
            target_root.keyframe_insert("location", frame=out_frame)
            target_root.keyframe_insert("rotation_quaternion", frame=out_frame)

    scene.frame_set(1)
    return {
        "mapped_count": len(mapped),
        "mapped": [{"source": source, "target": target} for source, target in mapped],
        "missing_source": missing_source,
        "missing_target": missing_target,
        "frame_start": frame_start,
        "frame_end": frame_end,
        "output_frames": scene.frame_end,
    }


def render_preview(output_dir: Path, frame_count: int) -> None:
    scene = bpy.context.scene
    output_dir.mkdir(parents=True, exist_ok=True)
    source_end = scene.frame_end
    sample_frames = []
    for index in range(frame_count):
        frame = 1 + round(index * max(source_end - 1, 1) / max(frame_count - 1, 1))
        sample_frames.append(frame)
    for index, frame in enumerate(sample_frames):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        scene.render.filepath = str(output_dir / f"space_suit_run_preview_frame_{index:02d}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    args = argv_after_separator()
    if len(args) != 5:
        raise SystemExit(
            "Usage: blender --background --python retarget_mixamo_run_preview.py -- "
            "<target.glb> <running.fbx> <output_dir> <frame_size> <preview_frames>"
        )
    target_glb = Path(args[0])
    running_fbx = Path(args[1])
    output_dir = Path(args[2])
    frame_size = int(args[3])
    preview_frames = int(args[4])
    output_dir.mkdir(parents=True, exist_ok=True)

    clear_scene()
    configure_shadowless_render(frame_size)

    target_objects = import_gltf(target_glb)
    target_armature = find_single_armature(target_objects, "target")
    target_meshes = [obj for obj in target_objects if obj.type == "MESH"]
    recenter_target(target_objects, target_meshes)

    source_objects = import_fbx(running_fbx)
    source_armature = find_single_armature(source_objects, "source")
    frame_start, frame_end = get_action_frame_range(source_armature)

    hide_source_objects(source_objects)
    summary = retarget_action(source_armature, target_armature, frame_start, frame_end)

    for mesh in target_meshes:
        mesh.visible_shadow = False
    configure_camera_and_lights(target_meshes)

    frames_dir = output_dir / "frames_preview"
    render_preview(frames_dir, preview_frames)

    blend_path = output_dir / "space_suit_running_retarget_test.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    summary.update(
        {
            "target_glb": str(target_glb),
            "running_fbx": str(running_fbx),
            "blend": str(blend_path),
            "preview_frames": preview_frames,
            "frame_size": frame_size,
            "target_armature": target_armature.name,
            "source_armature": source_armature.name,
            "target_meshes": len(target_meshes),
            "source_hidden": True,
            "camera": "orthographic top-front, 62 degree elevation, no side yaw",
            "shadows": "disabled",
        }
    )
    (output_dir / "retarget_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("RETARGET_RUN_PREVIEW_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
