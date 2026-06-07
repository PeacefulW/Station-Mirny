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


def parent_roots_to_turntable(imported: list[bpy.types.Object], asset_name: str) -> bpy.types.Object:
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    root = bpy.data.objects.new(f"{asset_name}_turntable_root", None)
    bpy.context.collection.objects.link(root)
    for obj in roots:
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
        obj.matrix_world = world
    return root


def configure_render(frame_size: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 1
    scene.cycles.transparent_max_bounces = 4

    scene.render.resolution_x = frame_size
    scene.render.resolution_y = frame_size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 15
    if hasattr(bpy.context.view_layer, "cycles") \
            and hasattr(bpy.context.view_layer.cycles, "use_pass_shadow_catcher"):
        bpy.context.view_layer.cycles.use_pass_shadow_catcher = True

    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = 0.0
        scene.view_settings.gamma = 1.0
    except Exception:
        pass

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.42, 0.43, 0.42)


def make_materials_matte(meshes: list[bpy.types.Object]) -> None:
    for obj in meshes:
        obj.visible_shadow = True
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
                    ("Roughness", 0.92),
                    ("Specular IOR Level", 0.22),
                    ("Specular", 0.18),
                    ("Coat Weight", 0.0),
                    ("Clearcoat", 0.0),
                ):
                    if input_name in node.inputs:
                        node.inputs[input_name].default_value = value


def add_overhead_sun(radius: float) -> None:
    scale = max(radius, 1.0)
    sun_data = bpy.data.lights.new("strict_overhead_sun", type="SUN")
    sun_data.energy = 2.9
    sun_data.angle = math.radians(9.0)
    sun = bpy.data.objects.new("strict_overhead_sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.location = (0.0, -0.65 * scale, 4.0 * scale)
    look_at(sun, Vector((0.0, 0.0, 0.0)))


def add_shadowless_fill(name: str, location: tuple[float, float, float], power: float, size: float) -> None:
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
    add_overhead_sun(radius)
    add_shadowless_fill("matte_front_fill_no_shadow", (0.0, -4.0 * scale, 5.0 * scale), 120.0, 6.0 * scale)
    add_shadowless_fill("matte_side_fill_no_shadow", (-3.5 * scale, 2.0 * scale, 4.5 * scale), 60.0, 7.0 * scale)


def add_shadow_catcher(radius: float) -> bpy.types.Object:
    plane_size = max(radius * 7.0, 6.0)
    bpy.ops.mesh.primitive_plane_add(size=plane_size, location=(0.0, 0.0, -0.002))
    plane = bpy.context.object
    plane.name = "overhead_shadow_catcher_ground"
    try:
        plane.is_shadow_catcher = True
    except Exception:
        pass
    cycles_settings = getattr(plane, "cycles", None)
    if cycles_settings is not None and hasattr(cycles_settings, "is_shadow_catcher"):
        cycles_settings.is_shadow_catcher = True
    material = bpy.data.materials.new("shadow_catcher_ground_material")
    material.diffuse_color = (0.38, 0.32, 0.24, 1.0)
    plane.data.materials.append(material)
    return plane


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
    camera_data.ortho_scale = max_extent * 1.08
    return camera


def render_rotations(turntable_root: bpy.types.Object, output_dir: Path, rotations: int, asset_name: str) -> None:
    scene = bpy.context.scene
    output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(rotations):
        degrees = round(360.0 * index / rotations)
        turntable_root.rotation_euler.z = math.tau * index / rotations
        bpy.context.view_layer.update()
        scene.render.filepath = str(output_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    args = argv_after_separator()
    if len(args) != 5:
        raise SystemExit(
            "Usage: blender --background --python render_rocks_with_overhead_shadow.py -- "
            "<input.glb> <output_dir> <asset_name> <rotations> <frame_size>"
        )

    input_glb = Path(args[0])
    output_dir = Path(args[1])
    asset_name = args[2]
    rotations = int(args[3])
    frame_size = int(args[4])
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
    turntable_root = parent_roots_to_turntable(imported, asset_name)
    make_materials_matte(meshes)

    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    radius = max(dims.x, dims.y, dims.z, 1.0)
    add_shadow_catcher(radius)
    configure_lighting(radius)
    configure_camera(meshes, turntable_root, rotations)
    render_rotations(turntable_root, output_dir, rotations, asset_name)

    print("Rock overhead shadow sprite render complete")
    print(f"input_glb={input_glb}")
    print(f"output_dir={output_dir}")
    print(f"asset_name={asset_name}")
    print(f"rotations={rotations}")
    print(f"frame_size={frame_size}")
    print(f"bounds_min={tuple(round(v, 4) for v in mins)}")
    print(f"bounds_max={tuple(round(v, 4) for v in maxs)}")
    print(f"render_engine={bpy.context.scene.render.engine}")
    print(f"camera_ortho_scale={bpy.context.scene.camera.data.ortho_scale:.4f}")
    print("shadow=cycles shadow catcher, overhead sun")


if __name__ == "__main__":
    main()
