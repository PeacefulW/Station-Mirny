import json
import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils.geometry import tessellate_polygon


ROOT_DIR = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful\artifacts\terrain_mountain_blender")
OUT_DIR = ROOT_DIR / "l1_atlas_prototype"
CASE_DIR = OUT_DIR / "cases"

BLEND_PATH = OUT_DIR / "mirny_mountain_l1_atlas_prototype.blend"
ATLAS_PATH = OUT_DIR / "mirny_mountain_l1_atlas.png"
PREVIEW_PATH = OUT_DIR / "mirny_mountain_l1_preview.png"
METADATA_PATH = OUT_DIR / "mirny_mountain_l1_metadata.json"

SEED = 91273
TILE_SIZE_PX = 256
ATLAS_GRID = 4

BIT_N = 1
BIT_E = 2
BIT_S = 4
BIT_W = 8


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


def find_principled(mat: bpy.types.Material):
    return next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)


def set_color_ramp(ramp, colors):
    while len(ramp.elements) > 2:
        ramp.elements.remove(ramp.elements[-1])
    for idx, (pos, color) in enumerate(colors):
        elem = ramp.elements[idx] if idx < len(ramp.elements) else ramp.elements.new(pos)
        elem.position = pos
        elem.color = color


def make_noise_material(name: str, color_a, color_b, noise_scale, bump_strength, bump_scale):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color_b
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = find_principled(mat)
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 0.92
        bsdf.inputs["Metallic"].default_value = 0.0

    # Object-space coordinates for noise — keeps the texture stable across
    # horizontal and vertical faces (default UV stretches on cliff quads,
    # producing visible vertical "wood grain" stripes on the cliff face).
    tex_coord = nodes.new(type="ShaderNodeTexCoord")

    noise = nodes.new(type="ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 12.0
    noise.inputs["Roughness"].default_value = 0.62

    ramp = nodes.new(type="ShaderNodeValToRGB")
    set_color_ramp(ramp.color_ramp, [(0.08, color_a), (1.0, color_b)])

    bump_noise = nodes.new(type="ShaderNodeTexNoise")
    bump_noise.inputs["Scale"].default_value = bump_scale
    bump_noise.inputs["Detail"].default_value = 8.0
    bump_noise.inputs["Roughness"].default_value = 0.75

    bump = nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.07

    if bsdf:
        links.new(tex_coord.outputs["Object"], noise.inputs["Vector"])
        links.new(tex_coord.outputs["Object"], bump_noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(bump_noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_flat_material(name: str, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    bsdf = find_principled(mat)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.93
        bsdf.inputs["Metallic"].default_value = 0.0
    return mat


TOP_MAT = None
FACE_MAT = None
STONE_MATS = []
GROUND_MAT = None


def create_materials():
    global TOP_MAT, FACE_MAT, STONE_MATS, GROUND_MAT
    TOP_MAT = make_noise_material(
        "l1_oxidized_top_material",
        (0.60, 0.19, 0.045, 1.0),
        (0.96, 0.38, 0.085, 1.0),
        noise_scale=54,
        bump_strength=0.035,
        bump_scale=150,
    )
    FACE_MAT = make_noise_material(
        "l1_fractured_cliff_face_material",
        (0.25, 0.075, 0.025, 1.0),
        (0.73, 0.23, 0.055, 1.0),
        noise_scale=32,
        bump_strength=0.12,
        bump_scale=76,
    )
    GROUND_MAT = make_noise_material(
        "l1_dust_ground_material",
        (0.34, 0.15, 0.045, 1.0),
        (0.55, 0.27, 0.08, 1.0),
        noise_scale=24,
        bump_strength=0.012,
        bump_scale=38,
    )
    STONE_MATS = [
        make_flat_material("l1_stone_light", (0.94, 0.34, 0.08, 1.0)),
        make_flat_material("l1_stone_mid", (0.58, 0.18, 0.045, 1.0)),
        make_flat_material("l1_stone_dark", (0.22, 0.065, 0.022, 1.0)),
    ]


def side_key_to_edge(side: str):
    if side == "N":
        return [(-0.5, 0.5), (0.5, 0.5)], Vector((0, 1, 0))
    if side == "E":
        return [(0.5, 0.5), (0.5, -0.5)], Vector((1, 0, 0))
    if side == "S":
        return [(0.5, -0.5), (-0.5, -0.5)], Vector((0, -1, 0))
    if side == "W":
        return [(-0.5, -0.5), (-0.5, 0.5)], Vector((-1, 0, 0))
    raise ValueError(side)


def polygon_area(points):
    area = 0.0
    for i, p in enumerate(points):
        q = points[(i + 1) % len(points)]
        area += p[0] * q[1] - q[0] * p[1]
    return area * 0.5


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


def outward_for_edge(a, b, clockwise=True):
    edge = Vector((b[0] - a[0], b[1] - a[1], 0.0))
    if edge.length_squared == 0:
        return Vector((0, 0, 0))
    edge.normalize()
    if clockwise:
        return Vector((-edge.y, edge.x, 0.0))
    return Vector((edge.y, -edge.x, 0.0))


def subdivide_edge(a, b, segments, jitter, outward):
    points = []
    for i in range(segments + 1):
        t = i / segments
        x = a[0] * (1 - t) + b[0] * t
        y = a[1] * (1 - t) + b[1] * t
        if 0 < i < segments:
            x += outward.x * random.uniform(-jitter * 0.35, jitter)
            y += outward.y * random.uniform(-jitter * 0.35, jitter)
        points.append((x, y))
    return points


def case_name(mask: int) -> str:
    letters = []
    if mask & BIT_N:
        letters.append("N")
    if mask & BIT_E:
        letters.append("E")
    if mask & BIT_S:
        letters.append("S")
    if mask & BIT_W:
        letters.append("W")
    return "".join(letters) if letters else "isolated"


def exposed_sides(mask: int):
    result = []
    if not (mask & BIT_N):
        result.append("N")
    if not (mask & BIT_E):
        result.append("E")
    if not (mask & BIT_S):
        result.append("S")
    if not (mask & BIT_W):
        result.append("W")
    return result


def create_case_tile(
    mask: int,
    name: str,
    loc=(0, 0, 0),
    variant_seed=0,
    add_rubble=True,
    top_variation=True,
    bevel_width=0.032,
    solid_sides=False,
):
    rng_state = random.getstate()
    random.seed(SEED + mask * 137 + variant_seed)

    z_top = loc[2]
    height = 0.68
    bottom_z = z_top - height

    exposed = set(exposed_sides(mask))
    # Clockwise loop so the same [top_i, top_j, bot_j, bot_i] face order used
    # by the preview mesh keeps cliff normals pointing outward.
    edge_specs = [
        ("W", (-0.5, -0.5), (-0.5, 0.5)),
        ("N", (-0.5, 0.5), (0.5, 0.5)),
        ("E", (0.5, 0.5), (0.5, -0.5)),
        ("S", (0.5, -0.5), (-0.5, -0.5)),
    ]
    loop = []
    edge_is_exposed = []
    for side, a, b in edge_specs:
        outward = outward_for_edge(a, b, clockwise=True)
        is_exposed = side in exposed
        segments = 8 if is_exposed else 6
        jitter = 0.090 if is_exposed else 0.045
        for step in range(segments):
            t = step / segments
            x = a[0] * (1 - t) + b[0] * t
            y = a[1] * (1 - t) + b[1] * t
            if 0 < step < segments:
                amount = random.uniform(-jitter * 0.22, jitter)
                x += outward.x * amount
                y += outward.y * amount
            loop.append((x, y))
            edge_is_exposed.append(is_exposed)

    n = len(loop)
    clockwise = polygon_area(loop) < 0
    edge_outwards = [
        outward_for_edge(loop[i], loop[(i + 1) % n], clockwise=clockwise)
        for i in range(n)
    ]

    vertex_outwards = []
    vertex_is_exposed = []
    for i in range(n):
        prev_o = edge_outwards[(i - 1) % n]
        next_o = edge_outwards[i]
        avg = Vector(((prev_o.x + next_o.x) * 0.5, (prev_o.y + next_o.y) * 0.5, 0.0))
        if avg.length > 1e-5:
            avg.normalize()
        else:
            avg = next_o
        vertex_outwards.append(avg)
        vertex_is_exposed.append(edge_is_exposed[(i - 1) % n] or edge_is_exposed[i])

    vertex_lips = [
        random.uniform(0.045, 0.105) if vertex_is_exposed[i] else random.uniform(0.020, 0.052)
        for i in range(n)
    ]
    vertex_bot_z = [bottom_z + random.uniform(-0.052, 0.035) for _ in range(n)]

    top_pts = [
        Vector((
            loc[0] + loop[i][0],
            loc[1] + loop[i][1],
            z_top + (random.uniform(-0.012, 0.014) if top_variation else 0.0),
        ))
        for i in range(n)
    ]
    bot_pts = [
        Vector((
            loc[0] + loop[i][0] + vertex_outwards[i].x * vertex_lips[i],
            loc[1] + loop[i][1] + vertex_outwards[i].y * vertex_lips[i],
            vertex_bot_z[i],
        ))
        for i in range(n)
    ]

    rows = 4
    cliff_rows = [top_pts]
    for r in range(1, rows):
        t = r / rows
        bell = 4.0 * t * (1.0 - t)
        row = []
        for i in range(n):
            top = top_pts[i]
            bot = bot_pts[i]
            out = vertex_outwards[i]
            face_scale = 0.040 if vertex_is_exposed[i] else 0.024
            x = top.x * (1 - t) + bot.x * t
            y = top.y * (1 - t) + bot.y * t
            z = top.z * (1 - t) + bot.z * t
            x += out.x * random.uniform(-face_scale, face_scale) * bell
            y += out.y * random.uniform(-face_scale, face_scale) * bell
            z += random.uniform(-0.026, 0.026) * bell
            row.append(Vector((x, y, z)))
        cliff_rows.append(row)
    cliff_rows.append(bot_pts)

    bm = bmesh.new()
    bm_rows = [[bm.verts.new(p) for p in row] for row in cliff_rows]
    top_face = bm.faces.new(bm_rows[0])

    for r in range(rows):
        upper = bm_rows[r]
        lower = bm_rows[r + 1]
        for i in range(n):
            if not solid_sides and not edge_is_exposed[i]:
                continue
            a = upper[i]
            b = upper[(i + 1) % n]
            c = lower[(i + 1) % n]
            d = lower[i]
            try:
                bm.faces.new([a, b, c, d])
            except ValueError:
                pass

    bmesh.ops.triangulate(
        bm,
        faces=[top_face],
        quad_method="BEAUTY",
        ngon_method="BEAUTY",
    )
    bm.normal_update()

    boundary_top_v_ids = {id(v) for v in bm_rows[0]}
    top_face_id_set = {id(f) for f in bm.faces if f.normal.z > 0.7}
    interior_top_edges = [
        e for e in bm.edges
        if len(e.link_faces) == 2
        and all(id(lf) in top_face_id_set for lf in e.link_faces)
    ]
    if interior_top_edges:
        bmesh.ops.subdivide_edges(
            bm,
            edges=interior_top_edges,
            cuts=2,
            use_grid_fill=False,
        )
        bm.normal_update()

    for v in bm.verts:
        if id(v) in boundary_top_v_ids:
            continue
        if v.co.z < z_top - 0.05:
            continue
        if any(abs(f.normal.z) > 0.7 for f in v.link_faces):
            v.co.z += random.uniform(-0.020, 0.028)

    bm.normal_update()

    mesh = bpy.data.meshes.new(f"{name}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(TOP_MAT)
    obj.data.materials.append(FACE_MAT)
    for poly in obj.data.polygons:
        poly.material_index = 0 if abs(poly.normal.z) > 0.5 else 1

    if bevel_width > 0.0:
        bevel = obj.modifiers.new("case_soft_chipped_rim", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = 4
        bevel.profile = 0.62
        bevel.limit_method = "ANGLE"
        bevel.angle_limit = math.radians(45)
        bevel.affect = "EDGES"
    obj.modifiers.new("case_weighted_normals", "WEIGHTED_NORMAL")

    if add_rubble:
        create_tile_rubble(mask, loc=loc, name=f"{name}_rubble", variant_seed=variant_seed, solid_sides=solid_sides)

    random.setstate(rng_state)
    return obj


def create_octa_rocks(name: str, placements):
    verts = []
    faces = []
    mat_indices = []
    base = [
        Vector((1, 0, 0)),
        Vector((-1, 0, 0)),
        Vector((0, 1, 0)),
        Vector((0, -1, 0)),
        Vector((0, 0, 1)),
        Vector((0, 0, -0.42)),
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
                    v.x * sx * random.uniform(0.72, 1.14),
                    v.y * sy * random.uniform(0.72, 1.14),
                    v.z * sz * random.uniform(0.7, 1.18),
                )
            )
            x = noisy.x * cr - noisy.y * sr
            y = noisy.x * sr + noisy.y * cr
            verts.append((loc[0] + x, loc[1] + y, loc[2] + noisy.z))
        for face in base_faces:
            faces.append(tuple(start + i for i in face))
            mat_indices.append(mat_index)

    if not verts:
        return None
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in STONE_MATS:
        obj.data.materials.append(mat)
    for idx, poly in enumerate(obj.data.polygons):
        poly.material_index = mat_indices[idx] % len(STONE_MATS)
    return obj


def create_tile_rubble(mask: int, loc=(0, 0, 0), name="tile_rubble", variant_seed=0, solid_sides=False):
    random.seed(SEED * 3 + mask * 271 + variant_seed)
    placements = []
    top_count = 16 if mask != 15 else 10
    for _ in range(top_count):
        size = random.uniform(0.006, 0.026)
        placements.append(
            (
                (
                    loc[0] + random.uniform(-0.34, 0.34),
                    loc[1] + random.uniform(-0.34, 0.34),
                    loc[2] + random.uniform(0.012, 0.035),
                ),
                (size * random.uniform(0.8, 1.55), size * random.uniform(0.7, 1.3), size * random.uniform(0.55, 1.2)),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )

    exposed = set(exposed_sides(mask))
    sides = ["N", "E", "S", "W"] if solid_sides else list(exposed)
    for side in sides:
        edge, outward = side_key_to_edge(side)
        is_exposed = side in exposed

        mid_count = 3 if is_exposed else 1
        for _ in range(mid_count):
            t = random.random()
            x = edge[0][0] * (1 - t) + edge[1][0] * t + outward.x * random.uniform(0.03, 0.11)
            y = edge[0][1] * (1 - t) + edge[1][1] * t + outward.y * random.uniform(0.03, 0.11)
            size = random.uniform(0.014, 0.050)
            placements.append(
                (
                    (
                        loc[0] + x,
                        loc[1] + y,
                        loc[2] - random.uniform(0.08, 0.55),
                    ),
                    (size * random.uniform(0.75, 1.45), size * random.uniform(0.75, 1.45), size * random.uniform(0.8, 1.8)),
                    random.uniform(0, math.tau),
                    random.randrange(len(STONE_MATS)),
                )
            )

        base_count = 5 if is_exposed else 2
        for _ in range(base_count):
            t = random.random()
            x = edge[0][0] * (1 - t) + edge[1][0] * t + outward.x * random.uniform(0.06, 0.20)
            y = edge[0][1] * (1 - t) + edge[1][1] * t + outward.y * random.uniform(0.06, 0.20)
            size = random.uniform(0.018, 0.058) if is_exposed else random.uniform(0.012, 0.035)
            placements.append(
                (
                    (
                        loc[0] + x + random.uniform(-0.025, 0.025),
                        loc[1] + y + random.uniform(-0.025, 0.025),
                        loc[2] - random.uniform(0.62, 0.72),
                    ),
                    (size * random.uniform(0.85, 1.55), size * random.uniform(0.85, 1.55), size * random.uniform(0.55, 1.05)),
                    random.uniform(0, math.tau),
                    random.randrange(len(STONE_MATS)),
                )
            )
    return create_octa_rocks(name, placements)


def create_preview_rim_overhang(grid, ox, oy, z_top=0.012, bottom_z=-0.72):
    placements = []
    verts = []
    faces = []
    mat_indices = []
    random.seed(SEED + 8080)

    for y, row in enumerate(grid):
        for x, val in enumerate(row):
            if val != "1":
                continue
            mask = neighbor_mask(grid, x, y)
            loc_x = ox + x
            loc_y = oy - y
            for side in exposed_sides(mask):
                edge, outward = side_key_to_edge(side)
                segments = 3
                pts = subdivide_edge(edge[0], edge[1], segments, jitter=0.065, outward=outward)
                for i in range(segments):
                    p0 = pts[i]
                    p1 = pts[i + 1]
                    over0 = random.uniform(0.08, 0.18)
                    over1 = random.uniform(0.08, 0.18)
                    inner0 = (loc_x + p0[0], loc_y + p0[1], z_top + random.uniform(-0.004, 0.004))
                    inner1 = (loc_x + p1[0], loc_y + p1[1], z_top + random.uniform(-0.004, 0.004))
                    outer1 = (
                        loc_x + p1[0] + outward.x * over1,
                        loc_y + p1[1] + outward.y * over1,
                        z_top + random.uniform(-0.012, 0.008),
                    )
                    outer0 = (
                        loc_x + p0[0] + outward.x * over0,
                        loc_y + p0[1] + outward.y * over0,
                        z_top + random.uniform(-0.012, 0.008),
                    )

                    start = len(verts)
                    verts.extend([inner0, inner1, outer1, outer0])
                    faces.append((start, start + 1, start + 2, start + 3))
                    mat_indices.append(0)

                    b1 = (outer1[0] + outward.x * random.uniform(0.02, 0.05), outer1[1] + outward.y * random.uniform(0.02, 0.05), bottom_z + random.uniform(-0.04, 0.035))
                    b0 = (outer0[0] + outward.x * random.uniform(0.02, 0.05), outer0[1] + outward.y * random.uniform(0.02, 0.05), bottom_z + random.uniform(-0.04, 0.035))
                    start = len(verts)
                    verts.extend([outer0, outer1, b1, b0])
                    faces.append((start, start + 1, start + 2, start + 3))
                    mat_indices.append(1)

                    if random.random() < 0.28:
                        mid_x = (outer0[0] + outer1[0]) * 0.5
                        mid_y = (outer0[1] + outer1[1]) * 0.5
                        size = random.uniform(0.018, 0.055)
                        placements.append(
                            (
                                (mid_x + outward.x * random.uniform(0.03, 0.10), mid_y + outward.y * random.uniform(0.03, 0.10), random.uniform(-0.15, -0.55)),
                                (size * random.uniform(0.8, 1.4), size * random.uniform(0.8, 1.4), size * random.uniform(0.9, 1.9)),
                                random.uniform(0, math.tau),
                                random.randrange(len(STONE_MATS)),
                            )
                        )

    mesh = bpy.data.meshes.new("preview_continuous_rim_overhang_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("preview_continuous_rim_overhang", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(TOP_MAT)
    obj.data.materials.append(FACE_MAT)
    for idx, poly in enumerate(obj.data.polygons):
        poly.material_index = mat_indices[idx]
    obj.modifiers.new("preview_rim_weighted_normals", "WEIGHTED_NORMAL")
    create_octa_rocks("preview_extra_edge_rubble", placements)
    return obj


def boundary_edges_for_grid(grid, ox, oy):
    edges = {}
    for y, row in enumerate(grid):
        for x, val in enumerate(row):
            if val != "1":
                continue
            cx = ox + x
            cy = oy - y
            sides = exposed_sides(neighbor_mask(grid, x, y))
            if "N" in sides:
                a = (cx - 0.5, cy + 0.5)
                b = (cx + 0.5, cy + 0.5)
                edges[a] = b
            if "E" in sides:
                a = (cx + 0.5, cy + 0.5)
                b = (cx + 0.5, cy - 0.5)
                edges[a] = b
            if "S" in sides:
                a = (cx + 0.5, cy - 0.5)
                b = (cx - 0.5, cy - 0.5)
                edges[a] = b
            if "W" in sides:
                a = (cx - 0.5, cy - 0.5)
                b = (cx - 0.5, cy + 0.5)
                edges[a] = b
    return edges


def trace_boundary_loop(edges):
    if not edges:
        return []
    start = min(edges.keys(), key=lambda p: (p[1], p[0]))
    loop = [start]
    current = start
    guard = 0
    while guard < len(edges) + 8:
        guard += 1
        nxt = edges.get(current)
        if nxt is None:
            break
        if nxt == start:
            break
        loop.append(nxt)
        current = nxt
    return loop


def jagged_boundary(loop, jitter=0.12):
    if len(loop) < 3:
        return loop
    clockwise = polygon_area(loop) < 0
    result = []
    for i, a in enumerate(loop):
        b = loop[(i + 1) % len(loop)]
        outward = outward_for_edge(a, b, clockwise=clockwise)
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        length = max(0.001, math.sqrt(dx * dx + dy * dy))
        # 4 sub-segments per grid edge (was 2) — smoother irregular silhouette.
        segments = max(4, int(round(length * 4)))
        for step in range(segments):
            t = step / segments
            base_x = a[0] * (1 - t) + b[0] * t
            base_y = a[1] * (1 - t) + b[1] * t
            amount = random.uniform(-jitter * 0.22, jitter)
            result.append((base_x + outward.x * amount, base_y + outward.y * amount))
    return result


def sample_inside(points):
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    for _ in range(500):
        x = random.uniform(min_x, max_x)
        y = random.uniform(min_y, max_y)
        if point_in_polygon(x, y, points):
            return x, y
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def create_continuous_preview_mountain(grid, ox, oy):
    """Build the preview mountain as a single seam-free mesh.

    Key differences vs. the v1 implementation:
      - Outward direction is computed per VERTEX (averaged from the two
        adjacent edges), not per edge. This is what kills the visible
        seam between adjacent cliff quads.
      - Each boundary vertex carries ONE lip and ONE bottom_z value used
        by both adjacent quads, so the bottom rim no longer "stair-steps".
      - The cliff face is subdivided into 4 vertical rows with bell-shaped
        outward + z noise, so it stops reading as a single flat strip.
      - The top n-gon is triangulated with bmesh BEAUTY, eliminating the
        long needle triangles that the previous tessellate_polygon fan
        produced (those needles caused visible shading bands).
    """
    random.seed(SEED + 9900)
    raw_loop = trace_boundary_loop(boundary_edges_for_grid(grid, ox, oy))
    loop = jagged_boundary(raw_loop, jitter=0.18)
    clockwise = polygon_area(loop) < 0
    n = len(loop)
    if n < 3:
        return None

    z_top = 0.0
    bottom_z = -0.72

    # Per-edge outward (used as building block for vertex outwards).
    edge_outwards = [
        outward_for_edge(loop[i], loop[(i + 1) % n], clockwise=clockwise)
        for i in range(n)
    ]

    # Per-VERTEX outward: bisector of the two adjacent edge outwards.
    # This is the geometric reason the seams disappear.
    vertex_outwards = []
    for i in range(n):
        prev_o = edge_outwards[(i - 1) % n]
        next_o = edge_outwards[i]
        avg = Vector(((prev_o.x + next_o.x) * 0.5, (prev_o.y + next_o.y) * 0.5, 0.0))
        if avg.length > 1e-5:
            avg.normalize()
        else:
            avg = next_o
        vertex_outwards.append(avg)

    # ONE lip and ONE bottom_z per vertex (was: two independent randoms
    # per quad, which made the seam visible).
    vertex_lips = [random.uniform(0.045, 0.105) for _ in range(n)]
    vertex_bot_z = [bottom_z + random.uniform(-0.05, 0.03) for _ in range(n)]

    top_pts = [
        Vector((loop[i][0], loop[i][1], z_top + random.uniform(-0.005, 0.005)))
        for i in range(n)
    ]
    bot_pts = [
        Vector((
            loop[i][0] + vertex_outwards[i].x * vertex_lips[i],
            loop[i][1] + vertex_outwards[i].y * vertex_lips[i],
            vertex_bot_z[i],
        ))
        for i in range(n)
    ]

    # Vertical subdivision rows. Bell-shaped weight: zero at top/bottom
    # (so top and bottom rims stay aligned), max at the middle of the cliff.
    rows = 4
    cliff_rows = [top_pts]
    for r in range(1, rows):
        t = r / rows
        bell = 4.0 * t * (1.0 - t)
        row = []
        for i in range(n):
            top = top_pts[i]
            bot = bot_pts[i]
            out = vertex_outwards[i]
            x = top.x * (1 - t) + bot.x * t
            y = top.y * (1 - t) + bot.y * t
            z = top.z * (1 - t) + bot.z * t
            # Bigger outward + z noise so the cliff face reads as eroded
            # rock instead of a smooth slab.
            face_amt = random.uniform(-0.045, 0.045) * bell
            x += out.x * face_amt
            y += out.y * face_amt
            z += random.uniform(-0.030, 0.030) * bell
            row.append(Vector((x, y, z)))
        cliff_rows.append(row)
    cliff_rows.append(bot_pts)

    # Build with bmesh so we can BEAUTY-triangulate the top n-gon and
    # emit the cliff strip as proper quads.
    bm = bmesh.new()
    bm_rows = [[bm.verts.new(p) for p in row] for row in cliff_rows]

    top_face = bm.faces.new(bm_rows[0])

    for r in range(rows):
        upper = bm_rows[r]
        lower = bm_rows[r + 1]
        for i in range(n):
            a = upper[i]
            b = upper[(i + 1) % n]
            c = lower[(i + 1) % n]
            d = lower[i]
            try:
                bm.faces.new([a, b, c, d])
            except ValueError:
                # Already exists (degenerate boundary segment).
                pass

    bmesh.ops.triangulate(
        bm,
        faces=[top_face],
        quad_method='BEAUTY',
        ngon_method='BEAUTY',
    )
    bm.normal_update()

    # Add interior detail to the top so it stops reading as a flat sheet.
    # Strategy: subdivide ONLY the edges that are interior to the top
    # surface (both sides are top tris). Boundary edges are shared with
    # cliff quads — subdividing those would re-open the seam we just fixed.
    boundary_top_v_ids = {id(v) for v in bm_rows[0]}
    top_face_id_set = {id(f) for f in bm.faces if f.normal.z > 0.7}
    interior_top_edges = [
        e for e in bm.edges
        if len(e.link_faces) == 2
        and all(id(lf) in top_face_id_set for lf in e.link_faces)
    ]
    if interior_top_edges:
        bmesh.ops.subdivide_edges(
            bm,
            edges=interior_top_edges,
            cuts=2,
            use_grid_fill=False,
        )
        bm.normal_update()

    # Push interior top vertices around in z to create plateau bumps.
    # Skip the original boundary verts — they must keep their cliff alignment.
    for v in bm.verts:
        if id(v) in boundary_top_v_ids:
            continue
        if v.co.z < z_top - 0.05:
            continue
        if any(abs(f.normal.z) > 0.7 for f in v.link_faces):
            v.co.z += random.uniform(-0.024, 0.032)

    bm.normal_update()

    mesh = bpy.data.meshes.new("preview_continuous_mountain_mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("preview_continuous_mountain", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(TOP_MAT)
    obj.data.materials.append(FACE_MAT)

    # Per-polygon material by orientation: roughly horizontal -> top, else cliff.
    for poly in obj.data.polygons:
        poly.material_index = 0 if abs(poly.normal.z) > 0.5 else 1

    # Aggressive bevel limited by ANGLE — rounds the sharp top rim
    # (cliff/top junction is ~90°) but leaves the cliff strip's internal
    # row seams (~0° between adjacent quads) untouched.
    bevel = obj.modifiers.new("preview_soft_chipped_rim", "BEVEL")
    bevel.width = 0.038
    bevel.segments = 4
    bevel.profile = 0.62
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(45)
    bevel.affect = "EDGES"
    obj.modifiers.new("preview_weighted_normals", "WEIGHTED_NORMAL")

    # Rubble — three layers: top scatter (gravel), sparse mid-cliff
    # stones (face breakup), and a dense talus slope at the base of the
    # cliff so the cliff-to-ground transition reads as eroded rock pile,
    # not a knife-edge.
    placements = []

    # Top gravel
    for _ in range(260):
        x, y = sample_inside(loop)
        size = random.uniform(0.006, 0.028)
        placements.append(
            (
                (x, y, random.uniform(0.010, 0.038)),
                (size * random.uniform(0.7, 1.6), size * random.uniform(0.7, 1.35), size * random.uniform(0.45, 1.15)),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )

    # Mid-cliff sparse stones
    step_mid = max(1, n // 70)
    for i in range(0, n, step_mid):
        if random.random() > 0.55:
            continue
        a = loop[i]
        out = vertex_outwards[i]
        size = random.uniform(0.014, 0.042)
        placements.append(
            (
                (
                    a[0] + out.x * random.uniform(0.02, 0.10),
                    a[1] + out.y * random.uniform(0.02, 0.10),
                    random.uniform(-0.28, -0.55),
                ),
                (size * random.uniform(0.75, 1.45), size * random.uniform(0.75, 1.45), size * random.uniform(0.85, 1.7)),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )

    # Dense talus slope at the base — closely-spaced flatter stones
    # piled outward from the cliff foot, with a second smaller-stone
    # row further out.
    step_base = max(1, n // 280)
    for i in range(0, n, step_base):
        a = loop[i]
        out = vertex_outwards[i]
        side_jx = random.uniform(-0.04, 0.04)
        side_jy = random.uniform(-0.04, 0.04)

        size = random.uniform(0.026, 0.072)
        placements.append(
            (
                (
                    a[0] + out.x * random.uniform(0.05, 0.20) + side_jx,
                    a[1] + out.y * random.uniform(0.05, 0.20) + side_jy,
                    random.uniform(-0.66, -0.74),
                ),
                (size * random.uniform(0.85, 1.55), size * random.uniform(0.85, 1.55), size * random.uniform(0.55, 1.05)),
                random.uniform(0, math.tau),
                random.randrange(len(STONE_MATS)),
            )
        )

        if random.random() < 0.55:
            small = random.uniform(0.012, 0.030)
            placements.append(
                (
                    (
                        a[0] + out.x * random.uniform(0.13, 0.30) + side_jx,
                        a[1] + out.y * random.uniform(0.13, 0.30) + side_jy,
                        random.uniform(-0.70, -0.74),
                    ),
                    (small * random.uniform(0.85, 1.4), small * random.uniform(0.85, 1.4), small * random.uniform(0.55, 1.05)),
                    random.uniform(0, math.tau),
                    random.randrange(len(STONE_MATS)),
                )
            )

    create_octa_rocks("preview_continuous_gravel_and_edge_stones", placements)
    return obj


def setup_camera(name: str, ortho_scale: float, target=(0, 0, -0.12)):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam)
    # Station Mirny reads terrain north-up. The camera faces the south cliff
    # straight on instead of rotating the asset into a corner-isometric view.
    cam.location = Vector((target[0], target[1] - 3.65, target[2] + 2.55))
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    bpy.context.scene.camera = cam
    return cam


def setup_lighting():
    sun_data = bpy.data.lights.new("l1_warm_sun", "SUN")
    sun = bpy.data.objects.new("l1_warm_sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(46), 0, math.radians(-34))
    sun_data.energy = 1.25
    sun_data.angle = math.radians(4.5)

    fill_data = bpy.data.lights.new("l1_soft_fill", "AREA")
    fill = bpy.data.objects.new("l1_soft_fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-3.0, -4.0, 4.8)
    fill.rotation_euler = (math.radians(64), 0, math.radians(-25))
    fill_data.energy = 210
    fill_data.size = 4.0


def configure_render(res_x: int, res_y: int, transparent: bool, filepath: Path):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.preview_samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.film_transparent = transparent
    scene.world = bpy.data.worlds.new("l1_warm_world") if not scene.world else scene.world
    scene.world.color = (0.48, 0.23, 0.07)
    scene.view_settings.exposure = 0.02
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
    scene.render.filepath = str(filepath)


def hide_renderable_objects(hidden: bool):
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE", "FONT"}:
            obj.hide_render = hidden
            obj.hide_viewport = hidden


def render_case_tiles():
    case_paths = []
    for mask in range(16):
        hide_renderable_objects(True)
        objects_before = set(bpy.data.objects)
        create_case_tile(
            mask,
            f"render_case_{mask:02d}_{case_name(mask)}",
            variant_seed=mask,
            add_rubble=True,
            solid_sides=True,
        )
        for obj in bpy.data.objects:
            if obj not in objects_before and obj.type == "MESH":
                obj.hide_render = False
                obj.hide_viewport = False
        case_path = CASE_DIR / f"case_{mask:02d}_{case_name(mask)}.png"
        configure_render(TILE_SIZE_PX, TILE_SIZE_PX, False, case_path)
        setup_camera("case_camera", 1.82)
        bpy.ops.render.render(write_still=True)
        case_paths.append(case_path)

        for obj in list(bpy.data.objects):
            if obj not in objects_before and obj.type != "CAMERA":
                bpy.data.objects.remove(obj, do_unlink=True)
        for obj in list(bpy.data.objects):
            if obj.name.startswith("case_camera"):
                bpy.data.objects.remove(obj, do_unlink=True)
    return case_paths


def compose_atlas(case_paths):
    atlas_w = TILE_SIZE_PX * ATLAS_GRID
    atlas_h = TILE_SIZE_PX * ATLAS_GRID
    atlas = bpy.data.images.new("mirny_mountain_l1_atlas", width=atlas_w, height=atlas_h, alpha=True, float_buffer=False)
    pixels = [0.0] * (atlas_w * atlas_h * 4)

    for mask, path in enumerate(case_paths):
        img = bpy.data.images.load(str(path))
        src = list(img.pixels)
        col = mask % ATLAS_GRID
        row = mask // ATLAS_GRID
        dest_x0 = col * TILE_SIZE_PX
        dest_y0 = (ATLAS_GRID - 1 - row) * TILE_SIZE_PX
        for y in range(TILE_SIZE_PX):
            for x in range(TILE_SIZE_PX):
                src_i = (y * TILE_SIZE_PX + x) * 4
                dst_i = ((dest_y0 + y) * atlas_w + (dest_x0 + x)) * 4
                pixels[dst_i : dst_i + 4] = src[src_i : src_i + 4]
        bpy.data.images.remove(img)

    atlas.pixels = pixels
    atlas.filepath_raw = str(ATLAS_PATH)
    atlas.file_format = "PNG"
    atlas.save()


def mask_grid():
    return [
        "000000000000",
        "001111100000",
        "011111111000",
        "111111111100",
        "111111111110",
        "011111101110",
        "001111000110",
        "000010000000",
    ]


def mask_at(grid, x, y):
    if y < 0 or y >= len(grid):
        return False
    if x < 0 or x >= len(grid[y]):
        return False
    return grid[y][x] == "1"


def neighbor_mask(grid, x, y):
    mask = 0
    if mask_at(grid, x, y - 1):
        mask |= BIT_N
    if mask_at(grid, x + 1, y):
        mask |= BIT_E
    if mask_at(grid, x, y + 1):
        mask |= BIT_S
    if mask_at(grid, x - 1, y):
        mask |= BIT_W
    return mask


def create_preview_scene():
    clear_scene()
    create_materials()
    setup_lighting()

    grid = mask_grid()
    width = len(grid[0])
    height = len(grid)
    ox = -width * 0.5
    oy = height * 0.5

    create_continuous_preview_mountain(grid, ox, oy)

    bpy.ops.mesh.primitive_plane_add(size=15.5, location=(0.2, -0.6, -0.71))
    ground = bpy.context.object
    ground.name = "preview_dust_ground"
    ground.data.materials.append(GROUND_MAT)

    setup_camera("preview_iso_camera", 11.2, target=(0.0, 0.25, -0.25))
    configure_render(1600, 1050, False, PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)


def write_metadata():
    data = {
        "prototype": "mirny_mountain_l1_atlas",
        "tile_size_px": TILE_SIZE_PX,
        "case_count": 16,
        "bit_order": {
            "N": BIT_N,
            "E": BIT_E,
            "S": BIT_S,
            "W": BIT_W,
        },
        "cases": [
            {
                "case_index": mask,
                "case_name": case_name(mask),
                "neighbors": {
                    "N": bool(mask & BIT_N),
                    "E": bool(mask & BIT_E),
                    "S": bool(mask & BIT_S),
                    "W": bool(mask & BIT_W),
                },
                "exposed_sides": exposed_sides(mask),
                "atlas_cell": {
                    "x": mask % ATLAS_GRID,
                    "y": mask // ATLAS_GRID,
                },
                "file": str((CASE_DIR / f"case_{mask:02d}_{case_name(mask)}.png").relative_to(OUT_DIR)),
            }
            for mask in range(16)
        ],
        "notes": [
            "L1 uses 4-cardinal neighbor masks only.",
            "Atlas renders closed art-review modules to avoid misleading transparent holes in the case sheet.",
            "Preview renders one continuous front-oblique mountain mesh, not separate tile blocks.",
            "Camera faces the south cliff straight on to match Station Mirny's north-up gameplay view.",
            "This is an art-pipeline proof, not the final 47-case terrain topology.",
            "Final production should add diagonal-aware cases, variants, mask/AO/normal passes, facade breakup, and Godot TerrainShapeSet validation.",
        ],
    }
    METADATA_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")


def build():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    CASE_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    create_materials()
    setup_lighting()
    case_paths = render_case_tiles()
    compose_atlas(case_paths)
    create_preview_scene()
    write_metadata()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


if __name__ == "__main__":
    build()
