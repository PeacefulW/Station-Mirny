import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROTATION_DEGREES = [0, 45, 90, 135]


def argv_after_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


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
    offset = Vector(
        (
            -((mins.x + maxs.x) * 0.5),
            -((mins.y + maxs.y) * 0.5),
            -mins.z,
        )
    )
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    for obj in roots:
        obj.location += offset
    bpy.context.view_layer.update()


def parent_roots_to_turntable(imported: list[bpy.types.Object]) -> bpy.types.Object:
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]
    root = bpy.data.objects.new("brown_seaweed_turntable_root", None)
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
    world.color = (0.80, 0.81, 0.80)


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
    look_at(obj, Vector((0.0, 0.0, 0.35)))


def configure_lighting(radius: float) -> None:
    scale = max(radius, 1.0)
    add_shadowless_light("living_soft_front_no_shadow", (0.0, -4.0 * scale, 5.4 * scale), 460.0, 5.4 * scale)
    add_shadowless_light("living_soft_fill_no_shadow", (-3.2 * scale, 2.5 * scale, 4.4 * scale), 155.0, 6.0 * scale)
    add_shadowless_light("living_soft_rim_no_shadow", (3.3 * scale, 3.0 * scale, 4.7 * scale), 90.0, 6.0 * scale)


def configure_camera(meshes: list[bpy.types.Object], turntable_root: bpy.types.Object) -> bpy.types.Object:
    mins, maxs = mesh_bounds(meshes)
    dims = maxs - mins
    target = Vector((0.0, 0.0, max(dims.z * 0.45, 0.1)))
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
    for degrees in ROTATION_DEGREES:
        turntable_root.rotation_euler.z = math.radians(degrees)
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


class LivingMeshDeformer:
    def __init__(self, meshes: list[bpy.types.Object], amplitude: float) -> None:
        self.meshes = meshes
        self.amplitude = amplitude
        self.records: dict[bpy.types.Object, list[tuple[int, Vector, float, float, float]]] = {}

        bpy.context.view_layer.update()
        all_world_z = []
        for obj in meshes:
            for vertex in obj.data.vertices:
                world = obj.matrix_world @ vertex.co
                all_world_z.append(world.z)

        min_z = min(all_world_z)
        max_z = max(all_world_z)
        z_span = max(max_z - min_z, 0.0001)

        for obj in meshes:
            rows = []
            for vertex in obj.data.vertices:
                original = vertex.co.copy()
                world = obj.matrix_world @ original
                height = (world.z - min_z) / z_span
                seed = math.sin(world.x * 12.9898 + world.y * 78.233 + world.z * 37.719) * 43758.5453
                phase = (seed - math.floor(seed)) * math.tau
                radial = math.atan2(world.y, world.x)
                rows.append((vertex.index, original, height, phase, radial))
            self.records[obj] = rows

    def apply(self, frame_index: int, frame_count: int) -> None:
        phase = math.tau * frame_index / frame_count
        for obj, rows in self.records.items():
            inv_basis = obj.matrix_world.inverted().to_3x3()
            for index, original, height, local_phase, radial in rows:
                influence = smoothstep(0.10, 1.0, height)
                influence = influence * influence
                tip_flutter = smoothstep(0.55, 1.0, height)

                slow = math.sin(phase + local_phase * 0.35 + height * 1.1)
                counter = math.sin(-phase * 1.35 + local_phase * 0.55 + radial * 0.6)
                pulse = math.sin(phase * 2.0 + local_phase + height * 3.0)

                lateral = self.amplitude * influence * (0.70 * slow + 0.30 * counter)
                cross = self.amplitude * influence * (0.32 * math.cos(phase * 0.9 + local_phase + radial))
                vertical = self.amplitude * 0.18 * tip_flutter * pulse

                world_delta = Vector((lateral, cross, vertical))
                local_delta = inv_basis @ world_delta
                obj.data.vertices[index].co = original + local_delta
            obj.data.update()
        bpy.context.view_layer.update()

    def reset(self) -> None:
        for obj, rows in self.records.items():
            for index, original, _height, _phase, _radial in rows:
                obj.data.vertices[index].co = original
            obj.data.update()
        bpy.context.view_layer.update()


def render_sequence(
    turntable_root: bpy.types.Object,
    deformer: LivingMeshDeformer,
    output_dir: Path,
    frame_count: int,
) -> None:
    scene = bpy.context.scene
    for degrees in ROTATION_DEGREES:
        view_dir = output_dir / f"view_{degrees:03d}deg"
        view_dir.mkdir(parents=True, exist_ok=True)
        turntable_root.rotation_euler.z = math.radians(degrees)
        for frame_index in range(frame_count):
            deformer.apply(frame_index, frame_count)
            scene.render.filepath = str(view_dir / f"brown_seaweed_view_{degrees:03d}deg_frame_{frame_index:02d}.png")
            bpy.ops.render.render(write_still=True)
        deformer.reset()


def main() -> None:
    args = argv_after_separator()
    if len(args) != 4:
        raise SystemExit(
            "Usage: blender --background --python render_brown_seaweed_living_sprites.py -- "
            "<input.glb> <output_dir> <frame_count> <frame_size>"
        )

    input_glb = Path(args[0])
    output_dir = Path(args[1])
    frame_count = int(args[2])
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
    configure_camera(meshes, turntable_root)

    # Small baked living motion: enough to read as organic, not as wind blast.
    deformer = LivingMeshDeformer(meshes, amplitude=radius * 0.025)
    render_sequence(turntable_root, deformer, output_dir, frame_count)

    mins, maxs = mesh_bounds(meshes)
    print("Brown seaweed living sprite render complete")
    print(f"input_glb={input_glb}")
    print(f"output_dir={output_dir}")
    print(f"view_degrees={ROTATION_DEGREES}")
    print(f"frames_per_view={frame_count}")
    print(f"frame_size={frame_size}")
    print(f"bounds_min={tuple(round(v, 4) for v in mins)}")
    print(f"bounds_max={tuple(round(v, 4) for v in maxs)}")
    print(f"render_engine={bpy.context.scene.render.engine}")
    print(f"camera_ortho_scale={bpy.context.scene.camera.data.ortho_scale:.4f}")
    print(f"self_motion=enabled amplitude={radius * 0.025:.4f}")
    print("shadows=disabled")


if __name__ == "__main__":
    main()
