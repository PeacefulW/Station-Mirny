import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


OUT_DIR = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful\artifacts\terrain_mountain_blender")
BLEND_PATH = OUT_DIR / "mirny_mountain_plateau_reference.blend"
RENDER_PATH = OUT_DIR / "mirny_mountain_plateau_reference.png"

SEED = 74017
random.seed(SEED)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.textures,
        bpy.data.images,
        bpy.data.lights,
        bpy.data.cameras,
    ):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def set_color_ramp(ramp, colors):
    while len(ramp.elements) > 2:
        ramp.elements.remove(ramp.elements[-1])
    for idx, (pos, color) in enumerate(colors):
        elem = ramp.elements[idx] if idx < len(ramp.elements) else ramp.elements.new(pos)
        elem.position = pos
        elem.color = color


def make_noise_material(
    name: str,
    base_a,
    base_b,
    noise_scale: float,
    roughness: float = 0.9,
    bump_strength: float = 0.07,
    bump_scale: float = 65.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    mat.diffuse_color = base_b
    if bsdf:
        if bsdf.inputs.get("Roughness"):
            bsdf.inputs["Roughness"].default_value = roughness
        if bsdf.inputs.get("Metallic"):
            bsdf.inputs["Metallic"].default_value = 0.0

    noise = nodes.new(type="ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 12.0
    noise.inputs["Roughness"].default_value = 0.58

    ramp = nodes.new(type="ShaderNodeValToRGB")
    set_color_ramp(
        ramp.color_ramp,
        [
            (0.06, base_a),
            (1.0, base_b),
        ],
    )

    bump_noise = nodes.new(type="ShaderNodeTexNoise")
    bump_noise.inputs["Scale"].default_value = bump_scale
    bump_noise.inputs["Detail"].default_value = 9.0
    bump_noise.inputs["Roughness"].default_value = 0.72

    bump = nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.08

    if bsdf:
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(bump_noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_flat_material(name: str, color, roughness: float = 0.92) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        if bsdf.inputs.get("Roughness"):
            bsdf.inputs["Roughness"].default_value = roughness
        if bsdf.inputs.get("Metallic"):
            bsdf.inputs["Metallic"].default_value = 0.0
    return mat


TOP_MAT = None
SIDE_MAT = None
RIM_MAT = None
GROUND_MAT = None
STONE_MATS = []


def polygon_area(points):
    area = 0.0
    for i, p in enumerate(points):
        q = points[(i + 1) % len(points)]
        area += p[0] * q[1] - q[0] * p[1]
    return area * 0.5


def outward_normal(a, b, clockwise: bool) -> Vector:
    edge = Vector((b[0] - a[0], b[1] - a[1], 0.0))
    if edge.length_squared == 0:
        return Vector((0.0, 0.0, 0.0))
    edge.normalize()
    if clockwise:
        return Vector((-edge.y, edge.x, 0.0))
    return Vector((edge.y, -edge.x, 0.0))


def jagged_outline(points, steps_min=2, steps_max=4, jitter=0.08):
    clockwise = polygon_area(points) < 0
    result = []
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        normal = outward_normal(a, b, clockwise)
        steps = random.randint(steps_min, steps_max)
        for step in range(steps):
            t = step / steps
            x = a[0] * (1.0 - t) + b[0] * t
            y = a[1] * (1.0 - t) + b[1] * t
            amount = random.uniform(-jitter * 0.55, jitter)
            result.append((x + normal.x * amount, y + normal.y * amount))
    return result


def point_in_polygon(x, y, points) -> bool:
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]
        xj, yj = points[j]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 0.000001) + xi
        ):
            inside = not inside
        j = i
    return inside


def sample_inside_polygon(points):
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    for _ in range(1000):
        x = random.uniform(min_x, max_x)
        y = random.uniform(min_y, max_y)
        if point_in_polygon(x, y, points):
            return x, y
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def create_plateau(name: str, points, location=(0, 0, 0), scale=1.0, height=0.95, top_noise=0.035):
    points = [(x * scale + location[0], y * scale + location[1]) for x, y in points]
    points = jagged_outline(points, jitter=0.09 * scale)
    clockwise = polygon_area(points) < 0

    verts = []
    faces = []
    mat_indices = []

    center = Vector(
        (
            sum(p[0] for p in points) / len(points),
            sum(p[1] for p in points) / len(points),
            location[2] + random.uniform(-top_noise, top_noise),
        )
    )
    center_i = len(verts)
    verts.append(tuple(center))

    top_indices = []
    bottom_indices = []
    for i, p in enumerate(points):
        prev_p = points[i - 1]
        next_p = points[(i + 1) % len(points)]
        n0 = outward_normal(prev_p, p, clockwise)
        n1 = outward_normal(p, next_p, clockwise)
        n = n0 + n1
        if n.length_squared < 0.001:
            n = n1
        n.normalize()
        top_z = location[2] + random.uniform(-top_noise, top_noise)
        bottom_z = location[2] - height + random.uniform(-0.08 * scale, 0.08 * scale)
        ledge = random.uniform(0.03, 0.14) * scale
        top_indices.append(len(verts))
        verts.append((p[0], p[1], top_z))
        bottom_indices.append(len(verts))
        verts.append((p[0] + n.x * ledge, p[1] + n.y * ledge, bottom_z))

    for i in range(len(points)):
        j = (i + 1) % len(points)
        if clockwise:
            faces.append((center_i, top_indices[j], top_indices[i]))
        else:
            faces.append((center_i, top_indices[i], top_indices[j]))
        mat_indices.append(0)

    for i in range(len(points)):
        j = (i + 1) % len(points)
        if clockwise:
            faces.append((top_indices[i], top_indices[j], bottom_indices[j], bottom_indices[i]))
        else:
            faces.append((top_indices[j], top_indices[i], bottom_indices[i], bottom_indices[j]))
        mat_indices.append(1)

    bottom_face = tuple(reversed(bottom_indices)) if clockwise else tuple(bottom_indices)
    faces.append(bottom_face)
    mat_indices.append(1)

    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(TOP_MAT)
    obj.data.materials.append(SIDE_MAT)
    obj.data.materials.append(RIM_MAT)
    for idx, poly in enumerate(obj.data.polygons):
        poly.material_index = mat_indices[idx]

    bevel = obj.modifiers.new("small_chipped_bevel", "BEVEL")
    bevel.width = 0.035 * scale
    bevel.segments = 2
    bevel.affect = "EDGES"

    obj.modifiers.new("weighted_rock_normals", "WEIGHTED_NORMAL")

    return obj, points


def create_octa_rock_mesh(name: str, placements, mats):
    verts = []
    faces = []
    mat_indices = []
    base = [
        Vector((1, 0, 0)),
        Vector((-1, 0, 0)),
        Vector((0, 1, 0)),
        Vector((0, -1, 0)),
        Vector((0, 0, 1)),
        Vector((0, 0, -0.55)),
    ]
    base_faces = [
        (0, 2, 4),
        (2, 1, 4),
        (1, 3, 4),
        (3, 0, 4),
        (2, 0, 5),
        (1, 2, 5),
        (3, 1, 5),
        (0, 3, 5),
    ]
    for loc, scale, rot, mat_index in placements:
        start = len(verts)
        sx, sy, sz = scale
        cr = math.cos(rot)
        sr = math.sin(rot)
        for v in base:
            noisy = Vector(
                (
                    v.x * sx * random.uniform(0.72, 1.18),
                    v.y * sy * random.uniform(0.72, 1.18),
                    v.z * sz * random.uniform(0.75, 1.25),
                )
            )
            x = noisy.x * cr - noisy.y * sr
            y = noisy.x * sr + noisy.y * cr
            verts.append((loc[0] + x, loc[1] + y, loc[2] + noisy.z))
        for f in base_faces:
            faces.append(tuple(start + i for i in f))
            mat_indices.append(mat_index)

    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in mats:
        obj.data.materials.append(mat)
    for idx, poly in enumerate(obj.data.polygons):
        poly.material_index = mat_indices[idx] % len(mats)
    return obj


def scatter_top_pebbles(points, count, z, name):
    placements = []
    for _ in range(count):
        x, y = sample_inside_polygon(points)
        size = random.uniform(0.010, 0.044)
        flat = random.uniform(0.45, 0.85)
        placements.append(
            (
                (x, y, z + random.uniform(0.01, 0.045)),
                (size * random.uniform(0.8, 1.6), size * random.uniform(0.7, 1.35), size * flat),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )
    return create_octa_rock_mesh(name, placements, STONE_MATS)


def scatter_cliff_rubble(points, count, top_z, height, name):
    clockwise = polygon_area(points) < 0
    placements = []
    for _ in range(count):
        i = random.randrange(len(points))
        a = points[i]
        b = points[(i + 1) % len(points)]
        t = random.random()
        n = outward_normal(a, b, clockwise)
        x = a[0] * (1 - t) + b[0] * t + n.x * random.uniform(0.02, 0.18)
        y = a[1] * (1 - t) + b[1] * t + n.y * random.uniform(0.02, 0.18)
        z = top_z - random.uniform(0.08, height * 0.95)
        size = random.uniform(0.026, 0.105)
        placements.append(
            (
                (x, y, z),
                (size * random.uniform(0.7, 1.4), size * random.uniform(0.7, 1.4), size * random.uniform(0.8, 1.8)),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )
    return create_octa_rock_mesh(name, placements, STONE_MATS)


def add_ground_plane():
    bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.4, -0.8, -1.02))
    ground = bpy.context.object
    ground.name = "dusty_lowland_plane"
    ground.data.materials.append(GROUND_MAT)
    return ground


def add_camera_and_lights():
    cam_data = bpy.data.cameras.new("isometric_reference_camera")
    cam = bpy.data.objects.new("isometric_reference_camera", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = Vector((5.9, -7.4, 5.0))
    target = Vector((0.45, -0.6, -0.25))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 8.2
    bpy.context.scene.camera = cam

    sun_data = bpy.data.lights.new("warm_low_sun", "SUN")
    sun = bpy.data.objects.new("warm_low_sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(48), math.radians(0), math.radians(-32))
    sun_data.energy = 1.4
    sun_data.angle = math.radians(4.0)

    area_data = bpy.data.lights.new("large_soft_sky_fill", "AREA")
    area = bpy.data.objects.new("large_soft_sky_fill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (-3.2, -4.1, 5.2)
    area.rotation_euler = (math.radians(62), 0, math.radians(-28))
    area_data.energy = 360
    area_data.size = 5.5

    rim_data = bpy.data.lights.new("weak_cliff_rim", "POINT")
    rim = bpy.data.objects.new("weak_cliff_rim", rim_data)
    bpy.context.collection.objects.link(rim)
    rim.location = (4.5, 3.5, 2.2)
    rim_data.energy = 58
    rim_data.shadow_soft_size = 4.0


def configure_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.preview_samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1120
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("warm_dust_world") if not scene.world else scene.world
    scene.world.color = (0.50, 0.25, 0.075)
    scene.view_settings.exposure = 0.05
    scene.view_settings.gamma = 1.0
    for transform in ("AgX", "Filmic", "Standard"):
        try:
            scene.view_settings.view_transform = transform
            break
        except TypeError:
            continue
    for look in ("Medium High Contrast", "High Contrast", "None"):
        try:
            scene.view_settings.look = look
            break
        except TypeError:
            continue
    scene.render.filepath = str(RENDER_PATH)


def build_scene():
    global TOP_MAT, SIDE_MAT, RIM_MAT, GROUND_MAT, STONE_MATS
    clear_scene()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    TOP_MAT = make_noise_material(
        "oxidized_orange_gravel_top",
        (0.64, 0.22, 0.055, 1.0),
        (0.98, 0.40, 0.10, 1.0),
        noise_scale=48,
        bump_strength=0.045,
        bump_scale=135,
    )
    SIDE_MAT = make_noise_material(
        "fractured_rust_cliff_face",
        (0.31, 0.10, 0.035, 1.0),
        (0.78, 0.26, 0.065, 1.0),
        noise_scale=34,
        bump_strength=0.13,
        bump_scale=72,
    )
    RIM_MAT = make_flat_material("dark_under_rim", (0.25, 0.09, 0.035, 1.0))
    GROUND_MAT = make_noise_material(
        "distant_dust_ground",
        (0.36, 0.18, 0.055, 1.0),
        (0.58, 0.29, 0.09, 1.0),
        noise_scale=22,
        bump_strength=0.018,
        bump_scale=45,
    )
    STONE_MATS = [
        make_flat_material("stone_rust_light", (0.93, 0.34, 0.08, 1.0)),
        make_flat_material("stone_rust_mid", (0.58, 0.19, 0.05, 1.0)),
        make_flat_material("stone_rust_dark", (0.25, 0.08, 0.028, 1.0)),
    ]

    add_ground_plane()

    main_shape = [
        (-4.05, -0.95),
        (-3.65, -1.55),
        (-2.45, -1.95),
        (-1.30, -1.85),
        (-0.92, -2.30),
        (0.05, -2.30),
        (0.45, -1.82),
        (1.15, -1.82),
        (1.55, -2.46),
        (2.20, -2.36),
        (2.48, -1.92),
        (3.68, -1.80),
        (3.80, -1.10),
        (4.35, -0.92),
        (4.15, -0.10),
        (3.35, 0.08),
        (3.08, 0.82),
        (2.02, 0.90),
        (1.92, 1.62),
        (0.75, 1.92),
        (0.02, 1.72),
        (-0.72, 1.92),
        (-1.92, 1.62),
        (-2.10, 0.98),
        (-3.02, 0.82),
        (-3.18, 0.20),
        (-4.00, -0.02),
        (-4.22, -0.55),
    ]
    main, main_points = create_plateau(
        "main_procedural_mountain_plateau",
        main_shape,
        height=0.96,
        top_noise=0.012,
    )
    scatter_top_pebbles(main_points, 420, 0.02, "main_top_gravel_and_small_stones")
    scatter_cliff_rubble(main_points, 185, 0.0, 0.96, "main_cliff_rubble")

    island_shape_a = [
        (-0.45, -0.38),
        (0.20, -0.46),
        (0.55, -0.10),
        (0.48, 0.42),
        (-0.15, 0.56),
        (-0.56, 0.18),
    ]
    _, island_a_points = create_plateau(
        "detached_small_rock_island_a",
        island_shape_a,
        location=(3.10, -3.05, -0.05),
        scale=0.92,
        height=0.72,
        top_noise=0.025,
    )
    scatter_top_pebbles(island_a_points, 52, -0.03, "island_a_top_gravel")
    scatter_cliff_rubble(island_a_points, 38, -0.05, 0.72, "island_a_cliff_rubble")

    island_shape_b = [
        (-0.43, -0.28),
        (0.30, -0.35),
        (0.48, 0.02),
        (0.34, 0.35),
        (-0.24, 0.39),
        (-0.55, 0.05),
    ]
    _, island_b_points = create_plateau(
        "detached_small_rock_island_b",
        island_shape_b,
        location=(4.08, -3.86, -0.16),
        scale=0.70,
        height=0.50,
        top_noise=0.018,
    )
    scatter_top_pebbles(island_b_points, 34, -0.14, "island_b_top_gravel")
    scatter_cliff_rubble(island_b_points, 24, -0.16, 0.50, "island_b_cliff_rubble")

    add_camera_and_lights()
    configure_render()

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    build_scene()
