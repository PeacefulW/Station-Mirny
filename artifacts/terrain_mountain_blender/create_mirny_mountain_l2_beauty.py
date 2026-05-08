import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon


OUT_DIR = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful\artifacts\terrain_mountain_blender\l2_beauty_pass")
BLEND_PATH = OUT_DIR / "mirny_mountain_l2_rounded_cliff.blend"
RENDER_PATH = OUT_DIR / "mirny_mountain_l2_rounded_cliff.png"
METADATA_PATH = OUT_DIR / "mirny_mountain_l2_metadata.json"

SEED = 43821
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


def principled(mat):
    return next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)


def set_color_ramp(ramp, colors):
    while len(ramp.elements) > 2:
        ramp.elements.remove(ramp.elements[-1])
    for idx, (pos, color) in enumerate(colors):
        elem = ramp.elements[idx] if idx < len(ramp.elements) else ramp.elements.new(pos)
        elem.position = pos
        elem.color = color


def make_noise_mat(name, color_a, color_b, noise_scale, bump_scale, bump_strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color_b
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = principled(mat)
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 0.94
        bsdf.inputs["Metallic"].default_value = 0.0

    noise = nodes.new(type="ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 14
    noise.inputs["Roughness"].default_value = 0.58
    ramp = nodes.new(type="ShaderNodeValToRGB")
    set_color_ramp(ramp.color_ramp, [(0.08, color_a), (1.0, color_b)])

    bump_noise = nodes.new(type="ShaderNodeTexNoise")
    bump_noise.inputs["Scale"].default_value = bump_scale
    bump_noise.inputs["Detail"].default_value = 12
    bump_noise.inputs["Roughness"].default_value = 0.70
    bump = nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.075

    if bsdf:
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(bump_noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_flat_mat(name, color, roughness=0.92):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    bsdf = principled(mat)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = 0.0
    return mat


TOP_MAT = None
FACE_MAT = None
FACE_DARK_MAT = None
FACE_LIGHT_MAT = None
CRACK_MAT = None
GROUND_MAT = None
RUBBLE_MATS = []


def create_materials():
    global TOP_MAT, FACE_MAT, FACE_DARK_MAT, FACE_LIGHT_MAT, CRACK_MAT, GROUND_MAT, RUBBLE_MATS
    TOP_MAT = make_noise_mat(
        "l2_dusty_oxidized_gravel_top",
        (0.50, 0.15, 0.035, 1.0),
        (0.98, 0.36, 0.075, 1.0),
        noise_scale=62,
        bump_scale=190,
        bump_strength=0.045,
    )
    FACE_MAT = make_noise_mat(
        "l2_layered_rust_cliff_face",
        (0.28, 0.075, 0.022, 1.0),
        (0.76, 0.22, 0.050, 1.0),
        noise_scale=36,
        bump_scale=92,
        bump_strength=0.13,
    )
    FACE_DARK_MAT = make_flat_mat("l2_deep_crevice_shadow", (0.105, 0.040, 0.018, 1.0), 0.98)
    FACE_LIGHT_MAT = make_flat_mat("l2_worn_rim_highlight", (1.0, 0.50, 0.16, 1.0), 0.88)
    CRACK_MAT = make_flat_mat("l2_crack_dark_line", (0.055, 0.022, 0.010, 1.0), 0.99)
    GROUND_MAT = make_noise_mat(
        "l2_dusty_background_ground",
        (0.30, 0.13, 0.045, 1.0),
        (0.55, 0.27, 0.085, 1.0),
        noise_scale=26,
        bump_scale=56,
        bump_strength=0.018,
    )
    RUBBLE_MATS = [
        make_flat_mat("l2_rubble_light", (0.95, 0.35, 0.08, 1.0)),
        make_flat_mat("l2_rubble_mid", (0.58, 0.17, 0.045, 1.0)),
        make_flat_mat("l2_rubble_dark", (0.23, 0.065, 0.022, 1.0)),
    ]


def polygon_area(points):
    area = 0.0
    for i, p in enumerate(points):
        q = points[(i + 1) % len(points)]
        area += p[0] * q[1] - q[0] * p[1]
    return area * 0.5


def outward_for_edge(a, b, clockwise=True):
    edge = Vector((b[0] - a[0], b[1] - a[1], 0.0))
    if edge.length_squared == 0:
        return Vector((0, 0, 0))
    edge.normalize()
    return Vector((-edge.y, edge.x, 0.0)) if clockwise else Vector((edge.y, -edge.x, 0.0))


def point_in_polygon(x, y, points):
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


def sample_inside(points):
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    for _ in range(700):
        x = random.uniform(min_x, max_x)
        y = random.uniform(min_y, max_y)
        if point_in_polygon(x, y, points):
            return x, y
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def smooth_boundary(points, samples_per_edge=4, jitter=0.055):
    clockwise = polygon_area(points) < 0
    out = []
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        outward = outward_for_edge(a, b, clockwise)
        for step in range(samples_per_edge):
            t = step / samples_per_edge
            x = a[0] * (1 - t) + b[0] * t
            y = a[1] * (1 - t) + b[1] * t
            amount = random.uniform(-jitter * 0.25, jitter)
            out.append((x + outward.x * amount, y + outward.y * amount))
    return out


def plateau_polygon():
    # Clockwise, south/front edge first. Kept broad and readable for the game camera.
    base = [
        (-5.8, -1.95),
        (-5.0, -2.10),
        (-4.35, -1.82),
        (-3.45, -2.05),
        (-2.65, -1.78),
        (-1.82, -1.96),
        (-1.12, -1.65),
        (-0.35, -1.86),
        (0.52, -1.58),
        (1.24, -1.86),
        (2.05, -1.62),
        (2.82, -1.88),
        (3.64, -1.72),
        (4.34, -2.02),
        (5.18, -1.78),
        (5.72, -1.42),
        (5.55, -0.45),
        (5.85, 0.15),
        (5.40, 1.02),
        (5.55, 1.88),
        (4.54, 2.26),
        (3.46, 2.12),
        (2.42, 2.35),
        (1.22, 2.18),
        (0.05, 2.35),
        (-1.10, 2.16),
        (-2.34, 2.32),
        (-3.38, 2.06),
        (-4.46, 2.22),
        (-5.48, 1.72),
        (-5.66, 0.65),
        (-5.42, -0.12),
        (-5.84, -0.85),
    ]
    return smooth_boundary(base, samples_per_edge=2, jitter=0.075)


def create_plateau_mesh(points):
    clockwise = polygon_area(points) < 0
    top_z = 0.0
    bottom_z = -0.95
    verts = []
    faces = []
    mat_indices = []

    top_vectors = []
    for x, y in points:
        top_vectors.append(Vector((x, y, top_z + random.uniform(-0.014, 0.012))))
    verts.extend([tuple(v) for v in top_vectors])
    for tri in tessellate_polygon([top_vectors]):
        faces.append(tuple(tri))
        mat_indices.append(0)

    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        outward = outward_for_edge(a, b, clockwise)
        top_a = top_vectors[i]
        top_b = top_vectors[(i + 1) % len(points)]
        lip_a = random.uniform(0.025, 0.080)
        lip_b = random.uniform(0.025, 0.080)
        bot_b = (
            top_b.x + outward.x * lip_b,
            top_b.y + outward.y * lip_b,
            bottom_z + random.uniform(-0.050, 0.035),
        )
        bot_a = (
            top_a.x + outward.x * lip_a,
            top_a.y + outward.y * lip_a,
            bottom_z + random.uniform(-0.050, 0.035),
        )
        start = len(verts)
        verts.extend([tuple(top_a), tuple(top_b), bot_b, bot_a])
        faces.append((start, start + 1, start + 2, start + 3))
        mat_indices.append(1)

    mesh = bpy.data.meshes.new("l2_continuous_plateau_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("l2_continuous_rounded_plateau", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(TOP_MAT)
    obj.data.materials.append(FACE_MAT)
    for idx, poly in enumerate(obj.data.polygons):
        poly.material_index = mat_indices[idx]
    bevel = obj.modifiers.new("soft_eroded_outer_rim", "BEVEL")
    bevel.width = 0.060
    bevel.segments = 4
    bevel.affect = "EDGES"
    obj.modifiers.new("weighted_normals", "WEIGHTED_NORMAL")
    return obj


def add_rounded_box(name, loc, dimensions, mat, rot_z=0.0, bevel_width=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=(0.0, 0.0, rot_z))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel_width > 0.0:
        bevel = obj.modifiers.new("rounded_eroded_edges", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = 4
        bevel.affect = "EDGES"
    obj.modifiers.new("weighted_normals", "WEIGHTED_NORMAL")
    return obj


def create_polyline(name, points, mat, bevel_depth=0.01):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 1
    poly = curve.splines.new("POLY")
    poly.points.add(len(points) - 1)
    for p, co in zip(poly.points, points):
        p.co = (co[0], co[1], co[2], 1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def create_face_detail(points):
    clockwise = polygon_area(points) < 0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        outward = outward_for_edge(a, b, clockwise)
        edge = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = edge.length
        if length < 0.30:
            continue
        edge.normalize()
        angle = math.atan2(edge.y, edge.x)
        visible_weight = 1.0 if outward.y < -0.15 else 0.35
        if random.random() > visible_weight:
            continue

        # Fine horizontal sediment bands carry the cliff identity. They read as
        # rock strata without turning the face into separate rectangular panels.
        layer_count = 7 if outward.y < -0.10 else 2
        for layer in range(layer_count):
            z = -0.10 - layer * random.uniform(0.095, 0.135)
            off = random.uniform(0.080, 0.135)
            sag = random.uniform(-0.025, 0.025)
            create_polyline(
                f"l2_horizontal_sediment_line_{i}_{layer}",
                [
                    (a[0] + outward.x * off, a[1] + outward.y * off, z + random.uniform(-0.015, 0.012)),
                    (
                        (a[0] + b[0]) * 0.5 + outward.x * (off + random.uniform(-0.015, 0.018)),
                        (a[1] + b[1]) * 0.5 + outward.y * (off + random.uniform(-0.015, 0.018)),
                        z + sag,
                    ),
                    (b[0] + outward.x * off, b[1] + outward.y * off, z + random.uniform(-0.015, 0.012)),
                ],
                FACE_DARK_MAT if layer % 2 else FACE_LIGHT_MAT,
                bevel_depth=random.uniform(0.003, 0.007),
            )

        # Add occasional rounded natural bulges instead of slab panels.
        bulge_count = int(length * (1.4 if outward.y < -0.10 else 0.45))
        for bulge in range(bulge_count):
            if random.random() < 0.32:
                continue
            t = random.uniform(0.12, 0.88)
            x = a[0] * (1 - t) + b[0] * t + outward.x * random.uniform(0.10, 0.18)
            y = a[1] * (1 - t) + b[1] * t + outward.y * random.uniform(0.10, 0.18)
            radius = random.uniform(0.055, 0.16)
            add_rounded_rock(
                f"l2_face_eroded_bulge_{i}_{bulge}",
                (x, y, random.uniform(-0.32, -0.76)),
                (
                    radius * random.uniform(1.1, 2.2),
                    radius * random.uniform(0.28, 0.55),
                    radius * random.uniform(0.55, 1.25),
                ),
                FACE_MAT if random.random() > 0.20 else FACE_DARK_MAT,
            )

        if random.random() < (0.42 if outward.y < -0.15 else 0.14):
            t = random.uniform(0.20, 0.82)
            x = a[0] * (1 - t) + b[0] * t + outward.x * 0.145
            y = a[1] * (1 - t) + b[1] * t + outward.y * 0.145
            create_polyline(
                f"l2_vertical_crack_{i}",
                [
                    (x + random.uniform(-0.025, 0.025), y + random.uniform(-0.015, 0.015), -0.05),
                    (x + random.uniform(-0.045, 0.045), y + random.uniform(-0.015, 0.015), -0.38),
                    (x + random.uniform(-0.030, 0.030), y + random.uniform(-0.015, 0.015), -0.83),
                ],
                CRACK_MAT,
                bevel_depth=random.uniform(0.0035, 0.008),
            )


def create_rim_caps(points):
    clockwise = polygon_area(points) < 0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        outward = outward_for_edge(a, b, clockwise)
        edge = Vector((b[0] - a[0], b[1] - a[1], 0))
        length = edge.length
        if length < 0.22:
            continue
        edge.normalize()
        angle = math.atan2(edge.y, edge.x)
        pieces = max(1, int(length / 0.62))
        for p in range(pieces):
            if random.random() < 0.58:
                continue
            t = (p + 0.5) / pieces
            x = a[0] * (1 - t) + b[0] * t + outward.x * random.uniform(0.025, 0.075)
            y = a[1] * (1 - t) + b[1] * t + outward.y * random.uniform(0.025, 0.075)
            radius = random.uniform(0.040, 0.115)
            add_rounded_rock(
                f"l2_soft_rim_stone_{i}_{p}",
                (x, y, 0.045),
                (
                    radius * random.uniform(1.0, 2.4),
                    radius * random.uniform(0.55, 1.15),
                    radius * random.uniform(0.30, 0.70),
                ),
                random.choice([TOP_MAT, FACE_LIGHT_MAT, FACE_MAT]),
            )


def add_rounded_rock(name, loc, scale, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def scatter_rubble(points):
    clockwise = polygon_area(points) < 0
    for idx in range(230):
        x, y = sample_inside(points)
        radius = random.uniform(0.006, 0.032)
        add_rounded_rock(
            f"l2_top_rounded_gravel_{idx}",
            (x, y, random.uniform(0.025, 0.055)),
            (
                radius * random.uniform(0.85, 1.80),
                radius * random.uniform(0.75, 1.45),
                radius * random.uniform(0.45, 1.10),
            ),
            random.choice(RUBBLE_MATS),
        )

    rock_id = 0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        outward = outward_for_edge(a, b, clockwise)
        edge = Vector((b[0] - a[0], b[1] - a[1], 0))
        length = edge.length
        if length < 0.25:
            continue
        count = int(length * (5.5 if outward.y < -0.10 else 2.2))
        for _ in range(count):
            t = random.random()
            x = a[0] * (1 - t) + b[0] * t + outward.x * random.uniform(0.10, 0.42)
            y = a[1] * (1 - t) + b[1] * t + outward.y * random.uniform(0.10, 0.42)
            radius = random.uniform(0.025, 0.115)
            add_rounded_rock(
                f"l2_base_rubble_{rock_id}",
                (x, y, -0.92 + random.uniform(0.010, 0.085)),
                (
                    radius * random.uniform(0.8, 1.7),
                    radius * random.uniform(0.7, 1.45),
                    radius * random.uniform(0.35, 0.95),
                ),
                random.choice(RUBBLE_MATS),
            )
            rock_id += 1


def add_ground():
    bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, -0.05, -0.99))
    obj = bpy.context.object
    obj.name = "l2_warm_dust_ground_plane"
    obj.data.materials.append(GROUND_MAT)


def add_camera_and_lights():
    cam_data = bpy.data.cameras.new("l2_station_mirny_south_camera")
    cam = bpy.data.objects.new("l2_station_mirny_south_camera", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((0.0, -0.05, -0.22))
    cam.location = Vector((0.0, -6.9, 3.85))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 6.2
    bpy.context.scene.camera = cam

    sun_data = bpy.data.lights.new("l2_warm_evening_sun", "SUN")
    sun = bpy.data.objects.new("l2_warm_evening_sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(44), 0, math.radians(-18))
    sun_data.energy = 1.35
    sun_data.angle = math.radians(4.5)

    fill_data = bpy.data.lights.new("l2_soft_front_fill", "AREA")
    fill = bpy.data.objects.new("l2_soft_front_fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (0.0, -4.6, 3.0)
    fill.rotation_euler = (math.radians(64), 0, 0)
    fill_data.energy = 230
    fill_data.size = 6.0


def configure_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.preview_samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1100
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("l2_warm_dark_world") if not scene.world else scene.world
    scene.world.color = (0.30, 0.20, 0.13)
    scene.view_settings.exposure = 0.03
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


def write_metadata():
    data = {
        "prototype": "mirny_mountain_l2_rounded_cliff_beauty_pass",
        "seed": SEED,
        "camera_contract": "north-up gameplay view; south cliff face looks straight at the player",
        "intent": "style target for future atlas cases, not a final Godot runtime asset",
        "improvements_over_l1": [
            "continuous rounded plateau mesh instead of visible block tiles",
            "soft bevel/erosion on the rim and corners",
            "rounded rubble instead of triangular pyramid stones",
            "layered cliff face using slabs, sediment lines, and cracks",
            "base rubble accumulation at the cliff foot",
        ],
        "reference_used": "../references/generated_cliff_reference_sheet.png",
    }
    METADATA_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def build():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    create_materials()
    points = plateau_polygon()
    add_ground()
    create_plateau_mesh(points)
    create_face_detail(points)
    create_rim_caps(points)
    scatter_rubble(points)
    add_camera_and_lights()
    configure_render()
    write_metadata()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    build()
