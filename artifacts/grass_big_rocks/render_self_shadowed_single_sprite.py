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


def configure_render(frame_size: int) -> None:
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
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
        scene.view_settings.look = "Medium High Contrast"
        scene.view_settings.exposure = -0.08
        scene.view_settings.gamma = 1.0
    except Exception:
        pass
    eevee = getattr(scene, "eevee", None)
    if eevee is not None:
        for prop, value in (
            ("use_gtao", True),
            ("use_shadows", True),
            ("use_raytracing", False),
        ):
            if hasattr(eevee, prop):
                setattr(eevee, prop, value)
        for prop, value in (
            ("gtao_distance", 2.4),
            ("gtao_factor", 1.35),
            ("shadow_cube_size", "2048"),
            ("shadow_cascade_size", "2048"),
        ):
            if hasattr(eevee, prop):
                try:
                    setattr(eevee, prop, value)
                except TypeError:
                    pass
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.40, 0.40, 0.38)


def tune_self_shadow_materials(meshes: list[bpy.types.Object]) -> None:
    for obj in meshes:
        obj.visible_shadow = True
        obj.visible_camera = True
        for slot in obj.material_slots:
            material = slot.material
            if material is None:
                continue
            material.use_nodes = True
            for node in material.node_tree.nodes:
                if node.type != "BSDF_PRINCIPLED":
                    continue
                for input_name, value in (
                    ("Metallic", 0.0),
                    ("Roughness", 0.80),
                    ("Specular IOR Level", 0.16),
                    ("Specular", 0.16),
                    ("Coat Weight", 0.0),
                    ("Clearcoat", 0.0),
                ):
                    if input_name in node.inputs:
                        node.inputs[input_name].default_value = value


def add_area_light(name: str, location: tuple[float, float, float], power: float, size: float, target_z: float) -> None:
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = power
    data.size = size
    if hasattr(data, "use_shadow"):
        data.use_shadow = True
    if hasattr(data, "use_contact_shadow"):
        data.use_contact_shadow = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    look_at(obj, Vector((0.0, 0.0, target_z)))


def configure_lighting(radius: float, target_z: float) -> None:
    scale = max(radius, 1.0)
    add_area_light(
        "top_left_front_key_self_shadow",
        (-2.8 * scale, -3.6 * scale, 6.4 * scale),
        760.0,
        2.7 * scale,
        target_z,
    )
    add_area_light(
        "soft_front_fill_self_shadow",
        (2.8 * scale, -1.5 * scale, 4.6 * scale),
        135.0,
        6.0 * scale,
        target_z,
    )


def configure_camera(meshes: list[bpy.types.Object], frame_padding: float) -> bpy.types.Object:
    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    target = Vector((0.0, 0.0, max(dims.z * 0.42, 0.08)))
    radius = max(dims.x, dims.y, dims.z, 1.0)
    camera_data = bpy.data.cameras.new("orthographic_top_front_camera")
    camera = bpy.data.objects.new("orthographic_top_front_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    elevation = math.radians(61.0)
    distance = radius * 5.8
    camera.location = target + Vector((0.0, -math.cos(elevation) * distance, math.sin(elevation) * distance))
    look_at(camera, target)
    camera_data.type = "ORTHO"
    camera_data.clip_end = distance * 10.0

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
    camera_data.ortho_scale = max(max_x - min_x, max_y - min_y) * frame_padding
    return camera


def main() -> None:
    args = argv_after_separator()
    if len(args) != 3 and len(args) != 4:
        raise SystemExit(
            "Usage: blender --background --python render_self_shadowed_single_sprite.py -- "
            "<input.glb> <output.png> <frame_size> [frame_padding]"
        )
    input_glb = Path(args[0])
    output_png = Path(args[1])
    frame_size = int(args[2])
    frame_padding = float(args[3]) if len(args) >= 4 else 1.12
    if not input_glb.exists():
        raise FileNotFoundError(input_glb)
    output_png.parent.mkdir(parents=True, exist_ok=True)

    clear_scene()
    configure_render(frame_size)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(input_glb))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = imported_meshes()
    if not meshes:
        raise RuntimeError("No mesh objects were imported from the GLB.")

    recenter_imported_objects(imported, meshes)
    tune_self_shadow_materials(meshes)
    mins, maxs = mesh_bounds(meshes)
    radius = max(*(maxs - mins), 1.0)
    target_z = max((maxs.z - mins.z) * 0.36, 0.08)
    configure_lighting(radius, target_z)
    configure_camera(meshes, frame_padding)
    bpy.context.scene.render.filepath = str(output_png)
    bpy.ops.render.render(write_still=True)

    mins, maxs = mesh_bounds(meshes)
    print("Self-shadowed single sprite render complete")
    print(f"input_glb={input_glb}")
    print(f"output_png={output_png}")
    print(f"frame_size={frame_size}")
    print(f"bounds_min={tuple(round(v, 4) for v in mins)}")
    print(f"bounds_max={tuple(round(v, 4) for v in maxs)}")
    print(f"render_engine={bpy.context.scene.render.engine}")
    print(f"camera_ortho_scale={bpy.context.scene.camera.data.ortho_scale:.4f}")
    print("ground_shadow=disabled")
    print("self_shadow=enabled")
    print("ambient_occlusion=enabled")


if __name__ == "__main__":
    main()
