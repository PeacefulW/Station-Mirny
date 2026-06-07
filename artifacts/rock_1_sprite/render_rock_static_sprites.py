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


def imported_meshes() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


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


def recenter_imported_objects(imported: list[bpy.types.Object], meshes: list[bpy.types.Object]) -> None:
    mins, maxs = mesh_bounds(meshes)
    offset = Vector((-((mins.x + maxs.x) * 0.5), -((mins.y + maxs.y) * 0.5), -mins.z))
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    for obj in roots:
        obj.location += offset
    bpy.context.view_layer.update()


def parent_roots_to_turntable(imported: list[bpy.types.Object]) -> bpy.types.Object:
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    root = bpy.data.objects.new("rock_1_turntable_root", None)
    bpy.context.collection.objects.link(root)
    for obj in roots:
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
        obj.matrix_world = world
    return root


def configure_render(frame_size: int) -> None:
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue

    scene.render.resolution_x = frame_size
    scene.render.resolution_y = frame_size
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


def configure_shadowless_materials(meshes: list[bpy.types.Object]) -> None:
    for obj in meshes:
        obj.visible_shadow = False
        for slot in obj.material_slots:
            material = slot.material
            if material is None:
                continue
            if hasattr(material, "show_transparent_back"):
                material.show_transparent_back = True
            if hasattr(material, "use_screen_refraction"):
                material.use_screen_refraction = False


def add_shadowless_light(name: str, location: tuple[float, float, float], power: float, size: float) -> None:
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = power
    data.size = size
    if hasattr(data, "use_shadow"):
        data.use_shadow = False
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    look_at(obj, Vector((0.0, 0.0, 0.25)))


def configure_lighting(radius: float) -> None:
    scale = max(radius, 1.0)
    add_shadowless_light("rock_soft_front_no_shadow", (0.0, -4.0 * scale, 5.2 * scale), 430.0, 5.0 * scale)
    add_shadowless_light("rock_soft_fill_no_shadow", (-3.2 * scale, 2.4 * scale, 4.2 * scale), 145.0, 6.0 * scale)
    add_shadowless_light("rock_soft_rim_no_shadow", (3.2 * scale, 3.0 * scale, 4.4 * scale), 80.0, 6.0 * scale)


def configure_camera(meshes: list[bpy.types.Object], turntable_root: bpy.types.Object, rotations: int) -> bpy.types.Object:
    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    target = Vector((0.0, 0.0, max(dims.z * 0.42, 0.08)))
    radius = max(dims.x, dims.y, dims.z, 1.0)

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

    max_extent = 0.0
    original_rotation = turntable_root.rotation_euler.z
    for index in range(rotations):
        turntable_root.rotation_euler.z = math.tau * index / rotations
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        inverse_camera = camera.matrix_world.inverted()
        min_x = math.inf
        max_x = -math.inf
        min_y = math.inf
        max_y = -math.inf
        for obj in meshes:
            eval_obj = obj.evaluated_get(depsgraph)
            matrix = inverse_camera @ eval_obj.matrix_world
            for corner in eval_obj.bound_box:
                point = matrix @ Vector(corner)
                min_x = min(min_x, point.x)
                max_x = max(max_x, point.x)
                min_y = min(min_y, point.y)
                max_y = max(max_y, point.y)
        max_extent = max(max_extent, max_x - min_x, max_y - min_y)

    turntable_root.rotation_euler.z = original_rotation
    bpy.context.view_layer.update()
    camera_data.ortho_scale = max_extent * 0.92
    return camera


def render_rotations(turntable_root: bpy.types.Object, output_dir: Path, rotations: int) -> None:
    scene = bpy.context.scene
    output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(rotations):
        degrees = round(360.0 * index / rotations)
        turntable_root.rotation_euler.z = math.tau * index / rotations
        bpy.context.view_layer.update()
        scene.render.filepath = str(output_dir / f"rock_1_rot_{index:02d}_{degrees:03d}deg.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    args = argv_after_separator()
    if len(args) != 4:
        raise SystemExit("Usage: blender --background --python render_rock_static_sprites.py -- <input.glb> <output_dir> <rotations> <frame_size>")

    input_glb = Path(args[0])
    output_dir = Path(args[1])
    rotations = int(args[2])
    frame_size = int(args[3])
    if not input_glb.exists():
        raise FileNotFoundError(input_glb)

    clear_scene()
    configure_render(frame_size)

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(input_glb))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = imported_meshes()
    if not meshes:
        raise RuntimeError("No mesh objects were imported from the GLB.")

    recenter_imported_objects(imported, meshes)
    turntable_root = parent_roots_to_turntable(imported)
    configure_shadowless_materials(meshes)

    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    radius = max(dims.x, dims.y, dims.z, 1.0)
    configure_lighting(radius)
    configure_camera(meshes, turntable_root, rotations)
    render_rotations(turntable_root, output_dir, rotations)

    mins, maxs = mesh_bounds(meshes)
    print("Rock 1 static sprite render complete")
    print(f"input_glb={input_glb}")
    print(f"output_dir={output_dir}")
    print(f"rotations={rotations}")
    print(f"frame_size={frame_size}")
    print(f"bounds_min={tuple(round(v, 4) for v in mins)}")
    print(f"bounds_max={tuple(round(v, 4) for v in maxs)}")
    print(f"render_engine={bpy.context.scene.render.engine}")
    print(f"camera_ortho_scale={bpy.context.scene.camera.data.ortho_scale:.4f}")
    print("animation=disabled")
    print("shadows=disabled")


if __name__ == "__main__":
    main()
