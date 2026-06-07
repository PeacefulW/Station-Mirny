import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def argv_after_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


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


def configure_render(size: int) -> None:
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


def recenter(objects: list[bpy.types.Object], meshes: list[bpy.types.Object]) -> None:
    mins, maxs = mesh_bounds(meshes)
    offset = Vector((-((mins.x + maxs.x) * 0.5), -((mins.y + maxs.y) * 0.5), -mins.z))
    object_set = set(objects)
    roots = [obj for obj in objects if obj.parent not in object_set]
    for obj in roots:
        obj.location += offset
    bpy.context.view_layer.update()


def parent_roots_to_turntable(objects: list[bpy.types.Object]) -> bpy.types.Object:
    object_set = set(objects)
    roots = [obj for obj in objects if obj.parent not in object_set]
    root = bpy.data.objects.new("mixamo_run_turntable_root", None)
    bpy.context.collection.objects.link(root)
    for obj in roots:
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
        obj.matrix_world = world
    return root


def configure_camera_lights(meshes: list[bpy.types.Object]) -> None:
    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    radius = max(dims.x, dims.y, dims.z, 1.0)
    target = Vector((0.0, 0.0, max(dims.z * 0.47, 0.3)))

    for name, loc, power, size in [
        ("front_no_shadow", (0.0, -4.3 * radius, 5.5 * radius), 520.0, 5.0 * radius),
        ("fill_no_shadow", (-3.0 * radius, 2.5 * radius, 4.2 * radius), 160.0, 6.0 * radius),
        ("rim_no_shadow", (3.2 * radius, 3.0 * radius, 4.8 * radius), 95.0, 6.0 * radius),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = power
        data.size = size
        if hasattr(data, "use_shadow"):
            data.use_shadow = False
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = loc
        look_at(light, target)

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


def get_frame_range(armatures: list[bpy.types.Object]) -> tuple[int, int]:
    if armatures and armatures[0].animation_data and armatures[0].animation_data.action:
        start, end = armatures[0].animation_data.action.frame_range
        return int(math.floor(start)), int(math.ceil(end))
    return int(bpy.context.scene.frame_start), int(bpy.context.scene.frame_end)


def render_run(turntable: bpy.types.Object, output_dir: Path, directions: int, frames_per_direction: int, frame_start: int, frame_end: int) -> None:
    scene = bpy.context.scene
    for direction in range(directions):
        degrees = round(360.0 * direction / directions, 3)
        view_dir = output_dir / f"dir_{direction:02d}_{int(round(degrees)):03d}deg"
        view_dir.mkdir(parents=True, exist_ok=True)
        turntable.rotation_euler.z = math.tau * direction / directions
        for frame_index in range(frames_per_direction):
            source_frame = frame_start + round(frame_index * max(frame_end - frame_start, 1) / max(frames_per_direction - 1, 1))
            scene.frame_set(source_frame)
            bpy.context.view_layer.update()
            scene.render.filepath = str(view_dir / f"space_suit_run_dir_{direction:02d}_{int(round(degrees)):03d}deg_frame_{frame_index:02d}.png")
            bpy.ops.render.render(write_still=True)


def main() -> None:
    args = argv_after_separator()
    if len(args) != 5:
        raise SystemExit(
            "Usage: blender --background --python render_mixamo_source_run_16dir.py -- "
            "<running.fbx> <output_dir> <directions> <frames_per_direction> <frame_size>"
        )
    running_fbx = Path(args[0])
    output_dir = Path(args[1])
    directions = int(args[2])
    frames_per_direction = int(args[3])
    frame_size = int(args[4])
    output_dir.mkdir(parents=True, exist_ok=True)

    clear_scene()
    configure_render(frame_size)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(running_fbx))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if not meshes or not armatures:
        raise RuntimeError(f"Expected mesh and armature in {running_fbx}")
    for mesh in meshes:
        mesh.visible_shadow = False

    recenter(imported, meshes)
    turntable = parent_roots_to_turntable(imported)
    configure_camera_lights(meshes)
    frame_start, frame_end = get_frame_range(armatures)
    frames_dir = output_dir / "frames_source_16dir"
    render_run(turntable, frames_dir, directions, frames_per_direction, frame_start, frame_end)

    summary = {
        "source": str(running_fbx),
        "frames_dir": str(frames_dir),
        "directions": directions,
        "frames_per_direction": frames_per_direction,
        "source_frame_start": frame_start,
        "source_frame_end": frame_end,
        "frame_size": frame_size,
        "mesh_count": len(meshes),
        "armature_count": len(armatures),
        "camera": "orthographic top-front, 62 degree elevation, no side yaw",
        "shadows": "disabled",
    }
    (output_dir / "mixamo_source_run_render_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("MIXAMO_SOURCE_RUN_RENDER_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
