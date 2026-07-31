"""Grow one "rust crown" tree from a seed and bake it into the canonical layered frames.

This script does not own bake settings. Camera, lighting, render engines, sun
angles, the layer cross-shadow rule and the Cycles shadow-catcher pass all come
from the canonical module `blender_layered_tree_asset_bake.py` and
`layered_asset_bake_profile.json` - the same contract the shipped trees are
baked against. What it replaces is the *source* stage: instead of importing a
GLB, the tree is grown.

  root flare -> twisted trunk -> recursive candelabra branching -> leaf bursts

The silhouette is the point. The art-direction reference shows a near-black,
low-forking trunk carrying rust-orange foliage as **discrete radiating bursts**
at the twig tips, not one dense canopy blob - you can see sky and branch
through the crown. A solid ellipsoid canopy is what makes a small tree read as
generic; the open burst crown is what keeps the reference silhouette.

Layer split follows the tree contract: everything that should move on the wind
(leaf blades) is `foliage`, everything planted (roots, trunk, branches, twigs,
burst nubs) is `trunk`. The canonical postprocess derives the wind mask from
exactly that split.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
DEFAULT_BAKE_PROFILE = TOOL_DIR / "layered_asset_bake_profile.json"
DEFAULT_TREE_PROFILE = TOOL_DIR / "rust_crown_tree_profiles.json"

UP = Vector((0.0, 0.0, 1.0))


def load_canonical_bake_module():
    path = TOOL_DIR / "blender_layered_tree_asset_bake.py"
    spec = importlib.util.spec_from_file_location("layered_tree_asset_bake", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load canonical bake module at {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BAKE = load_canonical_bake_module()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--variant-id", required=True)
    parser.add_argument("--profile", type=Path, default=DEFAULT_BAKE_PROFILE)
    parser.add_argument("--tree-profile", type=Path, default=DEFAULT_TREE_PROFILE)
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    return parser.parse_args(argv)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def find_variant(tree_profile: dict, variant_id: str) -> dict:
    for variant in tree_profile["variants"]:
        if variant["id"] == variant_id:
            return variant
    known = ", ".join(v["id"] for v in tree_profile["variants"])
    raise SystemExit(f"Unknown variant id {variant_id!r}. Known ids: {known}")


# --- colour ----------------------------------------------------------------


def srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def linear_rgba(srgb: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (
        srgb_to_linear(max(0.0, min(1.0, srgb[0]))),
        srgb_to_linear(max(0.0, min(1.0, srgb[1]))),
        srgb_to_linear(max(0.0, min(1.0, srgb[2]))),
        1.0,
    )


def rgb_255(values: list[int]) -> tuple[float, float, float]:
    return (float(values[0]) / 255.0, float(values[1]) / 255.0, float(values[2]) / 255.0)


def lerp_rgb(
    left: tuple[float, float, float],
    right: tuple[float, float, float],
    amount: float,
) -> tuple[float, float, float]:
    t = max(0.0, min(1.0, amount))
    return tuple(left[index] * (1.0 - t) + right[index] * t for index in range(3))


def lerp_float(left: float, right: float, amount: float) -> float:
    t = max(0.0, min(1.0, amount))
    return left * (1.0 - t) + right * t


def smoothstep01(amount: float) -> float:
    t = max(0.0, min(1.0, amount))
    return t * t * (3.0 - 2.0 * t)


def ramp_stops(ramp: dict) -> dict:
    return {key: rgb_255(ramp[key]) for key in ("root", "mid", "tip")}


def blend_stops(left: dict, right: dict, amount: float) -> dict:
    return {key: lerp_rgb(left[key], right[key], amount) for key in ("root", "mid", "tip")}


def ramp_rgb(stops: dict, amount: float, tip_power: float = 1.0) -> tuple[float, float, float]:
    """Root -> mid -> tip, with the hot tip pushed onto the last stretch.

    A leaf blade is widest near its base, so a linear ramp paints most of the
    crown's *area* in the tip colour and the burst flattens into one flat orange
    patch. Shaping the ramp keeps the bright ember on the spikes only.
    """
    shaped = max(0.0, min(1.0, amount)) ** max(tip_power, 1e-6)
    if shaped <= 0.5:
        return lerp_rgb(stops["root"], stops["mid"], shaped / 0.5)
    return lerp_rgb(stops["mid"], stops["tip"], (shaped - 0.5) / 0.5)


COLOR_ATTRIBUTE: str = "rust_crown_color"

_MATERIAL_CACHE: dict[str, bpy.types.Material] = {}


def vertex_color_material(name: str, roughness: float) -> bpy.types.Material:
    """One material per family, reading colour from the mesh's vertex colours.

    Colouring by handing a mesh N stepped materials paints it in visible bands:
    every face lands wholly in one rung of the ramp, so a trunk ends up ringed
    like a barber pole - which is exactly what shows up on approach in game.
    A per-vertex colour interpolates across each face instead, so the gradient
    is continuous, and the whole tree needs two materials rather than hundreds.
    """
    cached = _MATERIAL_CACHE.get(name)
    if cached is not None:
        return cached
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = COLOR_ATTRIBUTE
    links.new(attribute.outputs["Color"], principled.inputs["Base Color"])
    principled.inputs["Roughness"].default_value = float(roughness)
    if "Specular IOR Level" in principled.inputs:
        principled.inputs["Specular IOR Level"].default_value = 0.28
    elif "Specular" in principled.inputs:
        principled.inputs["Specular"].default_value = 0.28
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    _MATERIAL_CACHE[name] = mat
    return mat


def paint_vertices(obj: bpy.types.Object, colors: list[tuple[float, float, float]]) -> None:
    """Write one linear colour per vertex; float colour attributes are linear."""
    mesh = obj.data
    attribute = mesh.color_attributes.new(name=COLOR_ATTRIBUTE, type="FLOAT_COLOR", domain="POINT")
    for index, srgb in enumerate(colors):
        attribute.data[index].color = linear_rgba(srgb)


def bark_material(profile: dict) -> bpy.types.Material:
    return vertex_color_material("rust_crown_bark", float(profile["material"]["bark_roughness"]))


def leaf_material(profile: dict) -> bpy.types.Material:
    return vertex_color_material("rust_crown_leaf", float(profile["material"]["leaf_roughness"]))


def paint_bark(
    obj: bpy.types.Object,
    profile: dict,
    vertex_t: list[float],
    tier_index: int,
    *,
    ramp_start: float = 0.0,
    ramp_end: float = 1.0,
    end_tier_index: int | None = None,
    tier_blend_start: float = 0.0,
    tier_blend_end: float = 1.0,
) -> None:
    palette = profile["palette"]
    tier_start = float(palette["shade_tiers"][tier_index])
    tier_end = float(palette["shade_tiers"][tier_index if end_tier_index is None else end_tier_index])
    stops = ramp_stops(palette["bark_ramp"])
    obj.data.materials.append(bark_material(profile))
    colors: list[tuple[float, float, float]] = []
    for t in vertex_t:
        base = ramp_rgb(stops, lerp_float(ramp_start, ramp_end, t))
        tier_amount = smoothstep01(
            (t - tier_blend_start) / max(tier_blend_end - tier_blend_start, 1e-6)
        )
        tier = lerp_float(tier_start, tier_end, tier_amount)
        colors.append((base[0] * tier, base[1] * tier, base[2] * tier))
    paint_vertices(obj, colors)


def bark_progress_range(profile: dict, level: int) -> tuple[float, float]:
    """Allocate one continuous root-to-twig colour ramp across the tree."""
    transition = profile["geometry"]["trunk_transition"]
    trunk_end = float(transition["bark_trunk_end"])
    if level <= 0:
        return 0.0, trunk_end
    branch_levels = max(int(profile["geometry"]["branching"]["levels"]) - 1, 1)
    start = trunk_end + (1.0 - trunk_end) * min(level - 1, branch_levels) / branch_levels
    end = trunk_end + (1.0 - trunk_end) * min(level, branch_levels) / branch_levels
    return start, end


def paint_leaves(leaves: list[dict], profile: dict, rng: random.Random) -> None:
    """Colour the crown after it is grown, when its extent is finally known.

    Picking a ramp per burst while growing can only ever be noise: nothing knows
    yet where the top of the crown is. Painting in a second pass lets the hue
    ride a real gradient - gold where the sun reaches, red where the crown falls
    into its own shade - which is what makes the canopy read as one canopy
    instead of a pile of independently tinted pom-poms.
    """
    if not leaves:
        return
    palette = profile["palette"]
    bias = palette["leaf_hue_bias"]
    red_stops = ramp_stops(palette["leaf_ramp_red"])
    gold_stops = ramp_stops(palette["leaf_ramp_gold"])
    tip_power = float(palette["leaf_tip_power"])
    material = leaf_material(profile)
    height_weight = float(bias["height_weight"])
    light_weight = float(bias["light_weight"])
    jitter = float(bias["jitter"])

    heights = [entry["height"] for entry in leaves]
    low = min(heights)
    span = max(max(heights) - low, 1e-5)
    # Both terms are recentred on this crown's own spread. The raw sun dot is
    # not a contrast signal: the sun sits high, most blades point up and out, so
    # nearly every leaf scores positive and the whole canopy goes gold. What
    # should drive the hue is which side of *this* crown a leaf is on.
    lights = [entry["light"] for entry in leaves]
    light_mid = sum(lights) / len(lights)
    light_half_span = max((max(lights) - min(lights)) * 0.5, 1e-5)
    for entry in leaves:
        # Both terms live in [-1, 1] so the weights read as plain proportions.
        height_term = (entry["height"] - low) / span * 2.0 - 1.0
        light_term = max(-1.0, min(1.0, (entry["light"] - light_mid) / light_half_span))
        amount = (
            float(bias["center"])
            + height_weight * height_term
            + light_weight * light_term
            + rng.gauss(0.0, jitter)
        )
        hue = max(0.0, min(1.0, 0.5 + 0.5 * amount))
        # Depth tier darkens by how far the burst leans away from the camera; the
        # tone jitter is per blade, so two neighbours at the same depth differ.
        scale = float(palette["shade_tiers"][entry["tier"]]) * float(palette["leaf_tone_jitter"][entry["tone"]])
        stops = blend_stops(red_stops, gold_stops, hue)
        blade: bpy.types.Object = entry["object"]
        blade.data.materials.append(material)
        colors: list[tuple[float, float, float]] = []
        for t in entry["vertex_t"]:
            base = ramp_rgb(stops, t, tip_power)
            colors.append((base[0] * scale, base[1] * scale, base[2] * scale))
        paint_vertices(blade, colors)


# --- sampling helpers ------------------------------------------------------


def uniform_pair(rng: random.Random, values: list) -> float:
    return rng.uniform(float(values[0]), float(values[1]))


def randint_pair(rng: random.Random, values: list) -> int:
    return rng.randint(int(values[0]), int(values[1]))


def perpendicular(direction: Vector) -> Vector:
    axis = direction.cross(UP)
    if axis.length < 1e-5:
        axis = direction.cross(Vector((1.0, 0.0, 0.0)))
    return axis.normalized()


def depth_tier(direction: Vector, tiers: int, rng: random.Random) -> int:
    """Organs growing away from the camera sink into darker tiers.

    The bake camera sits at -Y and looks toward +Y, so the +Y component is how
    far an organ leans into the depth of the crown.
    """
    depth = 0.5 + 0.5 * max(-1.0, min(1.0, direction.normalized().y))
    index = int(round(depth * (tiers - 1))) + rng.choice((-1, 0, 0))
    return max(0, min(tiers - 1, index))


# --- geometry --------------------------------------------------------------


def polyline_frames(points: list[Vector]) -> tuple[list[Vector], list[Vector]]:
    """Tangents plus a parallel-transported normal, so the tube never pinches."""
    count = len(points)
    tangents: list[Vector] = []
    for index in range(count):
        if index == 0:
            delta = points[1] - points[0]
        elif index == count - 1:
            delta = points[-1] - points[-2]
        else:
            delta = points[index + 1] - points[index - 1]
        if delta.length < 1e-9:
            delta = UP.copy()
        tangents.append(delta.normalized())

    normals = [perpendicular(tangents[0])]
    for index in range(1, count):
        rotated = normals[-1].copy()
        rotated.rotate(tangents[index - 1].rotation_difference(tangents[index]))
        rotated -= tangents[index] * rotated.dot(tangents[index])
        if rotated.length < 1e-6:
            rotated = perpendicular(tangents[index])
        normals.append(rotated.normalized())
    return tangents, normals


def relief_settings(rng: random.Random, settings: dict | None, scale: float = 1.0) -> dict | None:
    if not settings:
        return None
    return {
        "amount": uniform_pair(rng, settings["amount"]) * scale,
        "lobes": float(randint_pair(rng, settings["lobes"])),
        "twist": uniform_pair(rng, settings["twist"]),
        "bulge": uniform_pair(rng, settings["bulge"]) * scale,
        "bulge_cycles": uniform_pair(rng, settings["bulge_cycles"]),
        "phase": rng.uniform(0.0, math.tau),
    }


def relief_scale(relief: dict | None, angle: float, t: float) -> float:
    """Fluting that spirals up the tube, plus a slow swell along it.

    One clean cosine gives a machined gear. Two beating frequencies plus the
    swell give bark: ridges that wander, split and fatten, which is what a
    silhouette this dark has instead of a texture.
    """
    if relief is None:
        return 1.0
    lobes = relief["lobes"]
    twist = relief["twist"] * t * math.tau
    phase = relief["phase"]
    ridges = 0.62 * math.cos(lobes * angle + twist + phase) + 0.38 * math.cos(
        2.6 * lobes * angle - 1.7 * twist + phase * 1.9
    )
    swell = math.sin((t * relief["bulge_cycles"] + phase * 0.3) * math.tau)
    return 1.0 + relief["amount"] * ridges + relief["bulge"] * swell


def tube_mesh(
    name: str,
    points: list[Vector],
    radii: list[float],
    sides: int,
    relief: dict | None = None,
    *,
    cap_start: bool = True,
    cap_end: bool = True,
    path_t: list[float] | None = None,
    relief_path_t: list[float] | None = None,
    relief_t_start: float = 0.0,
    relief_t_end: float = 1.0,
) -> tuple[bpy.types.Mesh, list[float]]:
    """A tapered tube through world-space points with independently optional caps."""
    if len(points) != len(radii):
        raise ValueError(f"{name}: points/radii length mismatch")
    if path_t is not None and len(path_t) != len(points):
        raise ValueError(f"{name}: path_t length mismatch")
    if relief_path_t is not None and len(relief_path_t) != len(points):
        raise ValueError(f"{name}: relief_path_t length mismatch")
    tangents, normals = polyline_frames(points)
    verts: list[tuple[float, float, float]] = []
    vertex_t: list[float] = []
    spans = max(len(points) - 1, 1)
    for index, point in enumerate(points):
        tangent = tangents[index]
        normal = normals[index]
        binormal = tangent.cross(normal).normalized()
        radius = radii[index]
        t = path_t[index] if path_t is not None else index / spans
        relief_t = (
            relief_path_t[index]
            if relief_path_t is not None
            else lerp_float(relief_t_start, relief_t_end, t)
        )
        for side in range(sides):
            angle = math.tau * side / sides
            offset = normal * math.cos(angle) + binormal * math.sin(angle)
            verts.append(tuple(point + offset * radius * relief_scale(relief, angle, relief_t)))
            vertex_t.append(t)

    faces: list[tuple[int, ...]] = []
    rings = len(points)
    if cap_start:
        base_index = len(verts)
        verts.append(tuple(points[0] - tangents[0] * radii[0] * 0.4))
        vertex_t.append(path_t[0] if path_t is not None else 0.0)
        for side in range(sides):
            side_next = (side + 1) % sides
            faces.append((side_next, side, base_index))
    for ring in range(rings - 1):
        base = ring * sides
        nxt = (ring + 1) * sides
        for side in range(sides):
            side_next = (side + 1) % sides
            faces.append((base + side, base + side_next, nxt + side_next, nxt + side))
    if cap_end:
        tip_index = len(verts)
        verts.append(tuple(points[-1] + tangents[-1] * radii[-1] * 1.4))
        vertex_t.append(path_t[-1] if path_t is not None else 1.0)
        last = (rings - 1) * sides
        for side in range(sides):
            side_next = (side + 1) % sides
            faces.append((last + side, last + side_next, tip_index))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return mesh, vertex_t


def blade_mesh(
    name: str,
    length: float,
    half_width: float,
    droop: float,
    crease: float,
    segments: int,
) -> tuple[bpy.types.Mesh, list[float]]:
    """One pointed leaf blade in local space, growing along +Y.

    Narrow at the attachment, widest just past it, tapering to a point: that is
    what makes a burst read as a spiky star instead of a fan of ribbons. The
    crease keeps the blade from vanishing when it turns edge-on to the camera.
    """
    verts: list[tuple[float, float, float]] = []
    vertex_t: list[float] = []
    for index in range(segments + 1):
        t = index / segments
        width = half_width * max(0.05, (1.0 - t) ** 0.7 * (0.4 + 0.6 * min(1.0, t * 4.0)))
        z = -droop * length * t * t
        lift = crease * width
        verts.append((-width, length * t, z))
        verts.append((0.0, length * t, z + lift))
        verts.append((width, length * t, z))
        vertex_t.extend((t, t, t))

    faces: list[tuple[int, ...]] = []
    for index in range(segments):
        base = index * 3
        nxt = (index + 1) * 3
        faces.append((base, base + 1, nxt + 1, nxt))
        faces.append((base + 1, base + 2, nxt + 2, nxt + 1))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return mesh, vertex_t


def link_object(name: str, mesh: bpy.types.Mesh, matrix: Matrix | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if matrix is not None:
        obj.matrix_world = matrix
    return obj


def aim_matrix(position: Vector, direction: Vector, roll: float) -> Matrix:
    """Place a local-+Y mesh so +Y points along `direction`, rolled about it."""
    forward = direction.normalized()
    quat = Vector((0.0, 1.0, 0.0)).rotation_difference(forward)
    return Matrix.Translation(position) @ (Quaternion(forward, roll) @ quat).to_matrix().to_4x4()


def branch_points(
    origin: Vector,
    direction: Vector,
    length: float,
    curl: float,
    wobble: float,
    upright_pull: float,
    segments: int,
    rng: random.Random,
) -> list[Vector]:
    """Grow a curving axis: a steady bend, a per-segment wobble, a pull upward.

    The steady bend is what gives the reference its twisted, wind-worked look;
    the wobble alone reads as noise, and a straight axis reads as a diagram.
    """
    points = [origin.copy()]
    heading = direction.normalized()
    bend_axis = perpendicular(heading)
    step = length / segments
    for _ in range(segments):
        heading.rotate(Quaternion(bend_axis, curl / segments))
        jitter = Vector((rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0), rng.gauss(0.0, 1.0)))
        if jitter.length > 1e-6:
            heading.rotate(Quaternion(jitter.normalized(), rng.gauss(0.0, wobble)))
        heading = heading.lerp(UP, upright_pull / segments).normalized()
        points.append(points[-1] + heading * step)
    return points


def hermite_fork_points(
    origin: Vector,
    incoming_direction: Vector,
    target_direction: Vector,
    length: float,
    curl: float,
    wobble: float,
    upright_pull: float,
    segments: int,
    rng: random.Random,
    transition: dict,
) -> list[Vector]:
    """Continue the trunk tangent through a short Hermite sleeve before branching."""
    transition_length = length * float(transition["length_fraction"])
    rings = max(4, int(transition["rings"]))
    handle = transition_length * float(transition["tangent_handle_fraction"])
    incoming = incoming_direction.normalized()
    target = target_direction.normalized()
    chord_direction = incoming.lerp(target, 0.5)
    if chord_direction.length < 1e-6:
        chord_direction = target.copy()
    endpoint = origin + chord_direction.normalized() * transition_length
    tangent_start = incoming * handle
    tangent_end = target * handle

    sleeve: list[Vector] = []
    for ring in range(rings):
        t = ring / max(rings - 1, 1)
        t2 = t * t
        t3 = t2 * t
        h00 = 2.0 * t3 - 3.0 * t2 + 1.0
        h10 = t3 - 2.0 * t2 + t
        h01 = -2.0 * t3 + 3.0 * t2
        h11 = t3 - t2
        sleeve.append(origin * h00 + tangent_start * h10 + endpoint * h01 + tangent_end * h11)

    tail_length = max(length - transition_length, length * 0.1)
    tail = branch_points(endpoint, target, tail_length, curl, wobble, upright_pull, segments, rng)
    return sleeve[:-1] + tail


def polyline_length_fractions(points: list[Vector]) -> list[float]:
    distances = [0.0]
    for index in range(1, len(points)):
        distances.append(distances[-1] + (points[index] - points[index - 1]).length)
    total = max(distances[-1], 1e-9)
    return [distance / total for distance in distances]


def sample_polyline(points: list[Vector], fraction: float) -> Vector:
    fractions = polyline_length_fractions(points)
    target = max(0.0, min(1.0, fraction))
    for index in range(1, len(points)):
        if target <= fractions[index]:
            span = max(fractions[index] - fractions[index - 1], 1e-9)
            amount = (target - fractions[index - 1]) / span
            return points[index - 1].lerp(points[index], amount)
    return points[-1].copy()


def add_fork_continuations(
    parts: list[tuple[bpy.types.Object, str]],
    profile: dict,
    entry_cords: list[dict],
    branch_axis: list[Vector],
    root_radius: float,
    tip_radius: float,
    bark_start: float,
    bark_end: float,
    start_tier: int,
    end_tier: int,
) -> None:
    """Extend each trunk cord into the branch inside one continuous tube mesh."""
    transition = profile["geometry"]["trunk_transition"]
    rib_fraction = float(transition["cord_continuation_fraction"])
    rib_segments = max(3, int(transition["cord_segments"]))
    core_start = float(transition["core_start_fraction"])
    bundle_radius_fraction = float(transition["cord_bundle_radius_fraction"])
    cord_turns = float(transition["cord_turns"])
    cord_end_radius_fraction = float(transition["cord_end_radius_fraction"])
    cord_core_inset = float(transition["cord_core_inset"])

    axis_points = [
        sample_polyline(branch_axis, rib_fraction * index / rib_segments)
        for index in range(rib_segments + 1)
    ]
    tangents, normals = polyline_frames(axis_points)
    binormals = [tangents[index].cross(normals[index]).normalized() for index in range(len(axis_points))]
    branch_origin = branch_axis[0]
    rib_bark_end = lerp_float(bark_start, bark_end, rib_fraction)
    tip_radius_scale = tip_radius / max(root_radius, 1e-6)

    for cord in entry_cords:
        initial_offset = cord["position"] - branch_origin
        if initial_offset.length < 1e-6:
            initial_offset = normals[0] * max(float(cord["radius"]), 1e-4)
        angle = math.atan2(initial_offset.dot(binormals[0]), initial_offset.dot(normals[0]))
        initial_offset_radius = initial_offset.length
        cord_radius = float(cord["radius"])
        rib_points: list[Vector] = []
        rib_radii: list[float] = []
        for index, axis_point in enumerate(axis_points):
            u = index / rib_segments
            eased = smoothstep01(u)
            axis_fraction = rib_fraction * u
            merge = smoothstep01(
                (axis_fraction - core_start) / max(rib_fraction - core_start, 1e-6)
            )
            base_rib_radius = cord_radius * lerp_float(1.0, tip_radius_scale, eased)
            rib_radius = base_rib_radius * lerp_float(
                1.0,
                cord_end_radius_fraction,
                merge,
            )
            core_radius = lerp_float(
                root_radius,
                tip_radius,
                axis_fraction,
            )
            free_offset = lerp_float(
                initial_offset_radius,
                base_rib_radius * bundle_radius_fraction,
                eased,
            )
            embedded_offset = max(core_radius - rib_radius * cord_core_inset, 0.0)
            offset_radius = lerp_float(free_offset, embedded_offset, merge)
            cord_angle = angle + cord_turns * math.tau * u
            offset = normals[index] * math.cos(cord_angle) + binormals[index] * math.sin(cord_angle)
            rib_points.append(axis_point + offset * offset_radius)
            rib_radii.append(rib_radius)

        cord_path_t = polyline_length_fractions(cord["points"])
        combined_points = cord["points"] + rib_points[1:]
        combined_radii = cord["radii"] + rib_radii[1:]
        bark_path_t = [
            lerp_float(0.0, bark_start, amount)
            for amount in cord_path_t
        ] + [
            lerp_float(bark_start, rib_bark_end, index / rib_segments)
            for index in range(1, rib_segments + 1)
        ]
        relief_path_t = cord_path_t + [
            1.0 + rib_fraction * index / rib_segments
            for index in range(1, rib_segments + 1)
        ]
        cord_mesh, cord_vertex_t = tube_mesh(
            cord["name"],
            combined_points,
            combined_radii,
            int(transition["first_order_sides"]),
            cord["relief"],
            cap_end=True,
            path_t=bark_path_t,
            relief_path_t=relief_path_t,
        )
        cord_object = link_object(cord["name"], cord_mesh)
        paint_bark(
            cord_object,
            profile,
            cord_vertex_t,
            start_tier,
            ramp_start=0.0,
            ramp_end=1.0,
            end_tier_index=end_tier,
            tier_blend_start=bark_start,
            tier_blend_end=bark_end,
        )
        parts.append((cord_object, "trunk"))


def add_burst(
    parts: list[tuple[bpy.types.Object, str]],
    leaves: list[dict],
    profile: dict,
    rng: random.Random,
    sun_to_light: Vector,
    center: Vector,
    axis: Vector,
    scale: float,
    blade_density: float,
    name: str,
) -> None:
    """One radiating clump of leaves at a twig tip."""
    crown = profile["geometry"]["crown"]
    palette = profile["palette"]
    tiers = len(palette["shade_tiers"])
    blade_segments = int(crown["blade_segments"])

    nub_radius = uniform_pair(rng, crown["nub_radius"]) * scale
    nub_points = [center - axis.normalized() * nub_radius * 1.2, center + axis.normalized() * nub_radius * 1.2]
    nub_mesh, nub_vertex_t = tube_mesh(f"{name}_nub", nub_points, [nub_radius * 0.7, nub_radius], 6)
    nub = link_object(f"{name}_nub", nub_mesh)
    paint_bark(nub, profile, nub_vertex_t, depth_tier(axis, tiers, rng))
    parts.append((nub, "trunk"))

    count = max(4, int(round(randint_pair(rng, crown["blades"]) * blade_density)))
    spread = math.radians(uniform_pair(rng, crown["spread_degrees"]))
    outward_bias = uniform_pair(rng, crown["outward_bias"])
    heading = axis.normalized()
    side = perpendicular(heading)
    for index in range(count):
        azimuth = math.tau * index / count + rng.gauss(0.0, 0.3)
        # sqrt keeps the blades spread over the cone's area instead of piling
        # them on the axis, which is what turns a burst into a lollipop.
        polar = spread * math.sqrt(rng.random())
        bend_axis = side.copy()
        bend_axis.rotate(Quaternion(heading, azimuth))
        blade_dir = heading.copy()
        blade_dir.rotate(Quaternion(bend_axis, polar))
        radial = Vector((blade_dir.x, blade_dir.y, 0.0))
        if radial.length > 1e-5:
            blade_dir = blade_dir.lerp(radial.normalized(), outward_bias).normalized()

        length = uniform_pair(rng, crown["blade_length"]) * scale * uniform_pair(rng, crown["length_jitter"])
        mesh, vertex_t = blade_mesh(
            f"{name}_blade_{index:02d}",
            length,
            uniform_pair(rng, crown["blade_half_width"]) * scale,
            uniform_pair(rng, crown["blade_droop"]),
            uniform_pair(rng, crown["blade_crease"]),
            blade_segments,
        )
        # Blades start off the nub surface at slightly different depths, so the
        # burst has volume instead of collapsing onto one origin point.
        jitter = float(crown["burst_jitter"]) * nub_radius
        base = center + blade_dir * nub_radius * 0.6 + Vector(
            (rng.gauss(0.0, jitter), rng.gauss(0.0, jitter), rng.gauss(0.0, jitter))
        )
        blade = link_object(
            f"{name}_blade_{index:02d}",
            mesh,
            aim_matrix(base, blade_dir, rng.uniform(0.0, math.tau)),
        )
        parts.append((blade, "foliage"))
        leaves.append(
            {
                "object": blade,
                "vertex_t": vertex_t,
                "tier": depth_tier(blade_dir, tiers, rng),
                "tone": rng.randrange(len(palette["leaf_tone_jitter"])),
                "height": base.z,
                "light": max(-1.0, min(1.0, blade_dir.dot(sun_to_light))),
            }
        )


def grow_branch(
    parts: list[tuple[bpy.types.Object, str]],
    leaves: list[dict],
    profile: dict,
    variant: dict,
    rng: random.Random,
    sun_to_light: Vector,
    origin: Vector,
    direction: Vector,
    length: float,
    radius: float,
    level: int,
    path: str,
    inherited_tier: int | None = None,
    entry_direction: Vector | None = None,
    entry_cords: list[dict] | None = None,
) -> None:
    geometry = profile["geometry"]
    palette = profile["palette"]
    branching = geometry["branching"]
    levels = int(branching["levels"])
    tiers = len(palette["shade_tiers"])

    segments = int(branching["segments"])
    transition = geometry["trunk_transition"]
    first_order_transition = entry_direction is not None and bool(entry_cords)
    sides = int(transition["first_order_sides"]) if first_order_transition else int(branching["sides"])
    curl = math.radians(uniform_pair(rng, branching["curl_degrees"]))
    wobble = math.radians(uniform_pair(rng, branching["wobble_degrees"]))
    upright_pull = uniform_pair(rng, branching["upright_pull"])
    taper = uniform_pair(rng, branching["radius_fraction"])

    visible_root_radius = radius
    shaft_root_radius = radius
    if first_order_transition:
        points = hermite_fork_points(
            origin,
            entry_direction,
            direction,
            length,
            curl,
            wobble,
            upright_pull,
            segments,
            rng,
            transition,
        )
        area_radius = math.sqrt(sum(float(cord["radius"]) ** 2 for cord in entry_cords))
        visible_root_radius = max(
            area_radius * float(transition["area_radius_scale"]),
            radius * float(transition["radius_floor_fraction"]),
        )
    else:
        points = branch_points(origin, direction, length, curl, wobble, upright_pull, segments, rng)
    path_t = polyline_length_fractions(points)
    # The braided cords may flare at the fork to form a natural branch collar.
    # Keep that larger root section, but taper back toward the authored shaft
    # radius instead of making the whole first-order branch uniformly thicker.
    tip_radius = shaft_root_radius * taper
    radii = [lerp_float(visible_root_radius, tip_radius, amount) for amount in path_t]
    mesh_points = points
    mesh_path_t = path_t
    mesh_radii = radii
    if first_order_transition:
        core_start = float(transition["core_start_fraction"])
        cord_end = float(transition["cord_continuation_fraction"])
        core_entry_radius_fraction = float(transition["core_entry_radius_fraction"])
        mesh_points = [sample_polyline(points, core_start)]
        mesh_path_t = [core_start]
        for point, amount in zip(points, path_t):
            if amount > core_start + 1e-6:
                mesh_points.append(point)
                mesh_path_t.append(amount)
        mesh_radii = []
        for amount in mesh_path_t:
            merge = smoothstep01(
                (amount - core_start) / max(cord_end - core_start, 1e-6)
            )
            core_scale = lerp_float(core_entry_radius_fraction, 1.0, merge)
            base_core_radius = lerp_float(visible_root_radius, tip_radius, amount)
            mesh_radii.append(base_core_radius * core_scale)
    # Relief fades out with branch order: a gnarled twig is noise at sprite size.
    relief_scale_amount = (
        float(transition["first_order_relief_scale"])
        if first_order_transition
        else 1.0 / (1.0 + level)
    )
    mesh, vertex_t = tube_mesh(
        f"rust_crown_{path}",
        mesh_points,
        mesh_radii,
        sides,
        relief_settings(rng, branching.get("relief"), relief_scale_amount),
        cap_start=not first_order_transition,
        path_t=mesh_path_t,
    )
    branch = link_object(f"rust_crown_{path}", mesh)
    tip_direction = (points[-1] - points[-2]).normalized()
    target_tier = depth_tier(tip_direction, tiers, rng)
    start_tier = target_tier if inherited_tier is None else inherited_tier
    bark_start, bark_end = bark_progress_range(profile, level)
    paint_bark(
        branch,
        profile,
        vertex_t,
        start_tier,
        ramp_start=bark_start,
        ramp_end=bark_end,
        end_tier_index=target_tier,
    )
    parts.append((branch, "trunk"))
    if first_order_transition:
        add_fork_continuations(
            parts,
            profile,
            entry_cords,
            points,
            visible_root_radius,
            tip_radius,
            bark_start,
            bark_end,
            start_tier,
            target_tier,
        )

    crown = geometry["crown"]
    crown_scale = float(variant.get("crown_scale", 1.0)) * float(variant.get("world_scale", 1.0))
    blade_density = float(variant.get("blade_density", 1.0))
    burst_from_level = randint_pair(rng, crown["burst_levels"])

    terminal = level + 1 >= levels or tip_radius < float(branching["min_radius"])
    if terminal:
        for burst_index in range(randint_pair(rng, crown["bursts_per_twig"])):
            offset = uniform_pair(rng, crown["burst_offset"])
            position = points[-1].lerp(points[max(0, len(points) - 3)], 1.0 - offset)
            add_burst(
                parts,
                leaves,
                profile,
                rng,
                sun_to_light,
                position,
                tip_direction,
                crown_scale,
                blade_density,
                f"rust_crown_{path}_b{burst_index}",
            )
        return

    child_count = randint_pair(rng, branching["children"])
    if rng.random() < float(branching["extra_child_chance"]):
        child_count += 1
    divergence_scale = float(branching["divergence_falloff"]) ** level
    azimuth_seed = rng.uniform(0.0, math.tau)
    side = perpendicular(tip_direction)
    for child_index in range(child_count):
        azimuth = azimuth_seed + math.tau * child_index / child_count + rng.gauss(0.0, 0.22)
        divergence = math.radians(uniform_pair(rng, branching["divergence_degrees"])) * divergence_scale
        bend_axis = side.copy()
        bend_axis.rotate(Quaternion(tip_direction, azimuth))
        child_direction = tip_direction.copy()
        child_direction.rotate(Quaternion(bend_axis, divergence))
        child_length = length * uniform_pair(rng, branching["length_fraction"])
        child_radius = tip_radius * uniform_pair(rng, branching["radius_fraction"])

        # A short dead stub: the reference trees are not tidy, and a bare
        # snapped branch is what sells them as weathered rather than modelled.
        if level >= 1 and rng.random() < float(branching["stub_chance"]):
            stub_points = branch_points(
                points[-1], child_direction, child_length * 0.45, divergence * 0.5, wobble, 0.0, 3, rng
            )
            stub_radii = [child_radius * (1.0 - 0.7 * index / 3) for index in range(4)]
            stub_mesh, stub_vertex_t = tube_mesh(f"rust_crown_{path}_{child_index}_stub", stub_points, stub_radii, 5)
            stub = link_object(f"rust_crown_{path}_{child_index}_stub", stub_mesh)
            stub_end_tier = depth_tier(child_direction, tiers, rng)
            stub_bark_start, stub_bark_end = bark_progress_range(profile, level + 1)
            paint_bark(
                stub,
                profile,
                stub_vertex_t,
                target_tier,
                ramp_start=stub_bark_start,
                ramp_end=stub_bark_end,
                end_tier_index=stub_end_tier,
            )
            parts.append((stub, "trunk"))
            continue

        grow_branch(
            parts,
            leaves,
            profile,
            variant,
            rng,
            sun_to_light,
            points[-1],
            child_direction,
            child_length,
            child_radius,
            level + 1,
            f"{path}_{child_index}",
            target_tier,
        )

    # Bursts hanging off inner forks, not only the outermost twigs: the
    # reference crown has foliage at several depths, which is what gives it
    # volume without closing the silhouette.
    if level + 1 >= burst_from_level and rng.random() < 0.75:
        add_burst(
            parts,
            leaves,
            profile,
            rng,
            sun_to_light,
            points[-1],
            tip_direction,
            crown_scale * 0.78,
            blade_density * 0.7,
            f"rust_crown_{path}_inner",
        )


def add_root_fibers(
    parts: list[tuple[bpy.types.Object, str]],
    profile: dict,
    rng: random.Random,
    strand_paths: list[tuple[list[Vector], list[float], float]],
    world_scale: float,
) -> None:
    """The trunk splitting into a fan of fibres, not roots bolted onto a pole.

    Separate limbs attached to the outside of the trunk - round tubes or flat
    ribs alike - always read as added afterwards, because nothing about them
    continues the wood above. On the shipped trees the flare is the trunk
    *itself* fraying: many thin cords peel off high up, run down alongside it,
    and only splay outward as they reach the soil. Fibres here do the same, and
    they peel off the braid's strands, which already run in exactly that
    direction.

    Each fibre is built directly in cylindrical coordinates around its strand -
    descending in z, gaining radius as a power curve - so the splay happens at
    the ground and nowhere else.
    """
    geometry = profile["geometry"]
    palette = profile["palette"]
    roots = geometry["roots"]
    tiers = len(palette["shade_tiers"])
    segments = int(roots["segments"])
    fiber_index = 0
    for points, radii, strand_azimuth in strand_paths:
        fiber_count = randint_pair(rng, roots["fibers_per_strand"])
        for slot in range(fiber_count):
            start_t = uniform_pair(rng, roots["start_height_fraction"])
            anchor_index = min(len(points) - 1, max(0, int(round(start_t * (len(points) - 1)))))
            origin = points[anchor_index]
            strand_radius = radii[anchor_index]

            # Spaced around the strand rather than clustered on one side, and
            # started out at its surface: the fibres have to sheathe the wood,
            # the way a rope is its own strands, not sprout from a point on it.
            angle = strand_azimuth + math.tau * slot / fiber_count + rng.gauss(0.0, 0.22)
            radial = strand_radius * rng.uniform(0.45, 0.95)
            bury = uniform_pair(rng, roots["bury_depth"]) * world_scale
            drop = origin.z + bury
            if drop <= 1e-4:
                continue
            spread = uniform_pair(rng, roots["spread"]) * world_scale
            spread_power = uniform_pair(rng, roots["spread_power"])
            twist = math.radians(uniform_pair(rng, roots["twist_degrees"]))
            wobble = float(roots["wobble"]) * world_scale

            fiber_points: list[Vector] = []
            drift_x = drift_y = 0.0
            for step_index in range(segments + 1):
                t = step_index / segments
                drift_x += rng.gauss(0.0, wobble)
                drift_y += rng.gauss(0.0, wobble)
                sweep = radial + spread * (t ** spread_power)
                heading = angle + twist * t
                fiber_points.append(
                    Vector(
                        (
                            origin.x + math.cos(heading) * sweep + drift_x,
                            origin.y + math.sin(heading) * sweep + drift_y,
                            origin.z - drop * t,
                        )
                    )
                )

            radius = strand_radius * uniform_pair(rng, roots["radius_fraction"])
            fiber_radii = [radius * (1.0 - 0.82 * (step_index / segments) ** 1.1) for step_index in range(segments + 1)]
            name = f"rust_crown_root_fiber_{fiber_index:02d}"
            fiber_index += 1
            mesh, vertex_t = tube_mesh(
                name,
                fiber_points,
                fiber_radii,
                int(roots["sides"]),
                relief_settings(rng, roots.get("relief")),
            )
            fiber = link_object(name, mesh)
            direction = (fiber_points[-1] - fiber_points[0]).normalized()
            paint_bark(fiber, profile, vertex_t, depth_tier(direction, tiers, rng))
            parts.append((fiber, "trunk"))


def strand_polyline(
    axis_points: list[Vector],
    azimuth: float,
    turns: float,
    bundle_closed: float,
    bundle_open: float,
    open_power: float,
    fork_open_fraction: float,
    fork_open_start_fraction: float,
) -> list[Vector]:
    """One strand winding around the trunk axis, opening into the crown fork.

    The bundle still collapses at the foot, but the crown end retains a
    data-driven share of its opening. Closing both ends creates an hourglass
    pinch immediately before the branches even when the tube meshes themselves
    are continuous.
    """
    tangents, normals = polyline_frames(axis_points)
    spans = max(len(axis_points) - 1, 1)
    start_sine = max(math.sin(math.pi * fork_open_start_fraction), 1e-6)
    bulge_start = start_sine**open_power
    slope_start = (
        open_power
        * math.pi
        * math.cos(math.pi * fork_open_start_fraction)
        * start_sine ** (open_power - 1.0)
    )
    tail_tangent = slope_start * (1.0 - fork_open_start_fraction)
    points: list[Vector] = []
    for index, point in enumerate(axis_points):
        t = index / spans
        bulge = math.sin(math.pi * t) ** open_power
        if fork_open_fraction <= 0.0 or t <= fork_open_start_fraction:
            envelope = bulge
        else:
            u = (t - fork_open_start_fraction) / max(1.0 - fork_open_start_fraction, 1e-6)
            u2 = u * u
            u3 = u2 * u
            h00 = 2.0 * u3 - 3.0 * u2 + 1.0
            h10 = u3 - 2.0 * u2 + u
            h01 = -2.0 * u3 + 3.0 * u2
            envelope = h00 * bulge_start + h10 * tail_tangent + h01 * fork_open_fraction
            envelope = max(0.0, min(1.0, envelope))
        radius = bundle_closed + (bundle_open - bundle_closed) * envelope
        angle = azimuth + turns * math.tau * t
        binormal = tangents[index].cross(normals[index]).normalized()
        points.append(point + (normals[index] * math.cos(angle) + binormal * math.sin(angle)) * radius)
    return points


def grow_trunk(
    parts: list[tuple[bpy.types.Object, str]],
    profile: dict,
    rng: random.Random,
    origin: Vector,
    direction: Vector,
    length: float,
    base_radius: float,
) -> tuple[list[dict], list[tuple[list[Vector], list[float], float]]]:
    """Braid several strands into one trunk. Returns each strand's top and path.

    A single tapered tube reads as a pole no matter how much relief it carries.
    Several stems spiralling into one fused trunk is what makes this species
    look grown rather than extruded - and it hands the crown a ready-made set
    of divergent launch directions at the fork.
    """
    geometry = profile["geometry"]
    palette = profile["palette"]
    trunk_settings = geometry["trunk"]
    braid = trunk_settings["braid"]
    transition = geometry["trunk_transition"]
    tiers = len(palette["shade_tiers"])

    segments = int(trunk_settings["segments"])
    curl = math.radians(uniform_pair(rng, trunk_settings["curl_degrees"]))
    wobble = math.radians(uniform_pair(rng, trunk_settings["wobble_degrees"]))
    axis = branch_points(origin, direction, length, curl, wobble, 0.0, segments, rng)

    strands = randint_pair(rng, braid["strands"])
    strand_radius = base_radius * uniform_pair(rng, braid["strand_radius_fraction"])
    # Closed tighter than a strand is thick, so neighbours overlap and weld.
    bundle_closed = strand_radius * uniform_pair(rng, braid["bundle_closed_fraction"])
    bundle_open = base_radius * uniform_pair(rng, braid["bundle_open_fraction"])
    open_power = float(braid["bundle_open_power"])
    fork_open_fraction = float(braid["fork_open_fraction"])
    fork_open_start_fraction = float(braid["fork_open_start_fraction"])
    turns = uniform_pair(rng, braid["turns"]) * rng.choice((-1.0, 1.0))
    taper = uniform_pair(rng, trunk_settings["taper"])

    launches: list[dict] = []
    paths: list[tuple[list[Vector], list[float], float]] = []
    for index in range(strands):
        azimuth = math.tau * index / strands + rng.gauss(0.0, 0.12)
        points = strand_polyline(
            axis,
            azimuth,
            turns,
            bundle_closed,
            bundle_open,
            open_power,
            fork_open_fraction,
            fork_open_start_fraction,
        )
        branch_axis_points = strand_polyline(
            axis,
            azimuth,
            turns,
            bundle_closed,
            bundle_open,
            open_power,
            0.0,
            fork_open_start_fraction,
        )
        radius = strand_radius * rng.uniform(0.88, 1.12)
        tip_radius = radius * taper
        radii = [radius + (tip_radius - radius) * (step_index / segments) for step_index in range(segments + 1)]
        # The collar: the strand itself swells where it enters the ground. Half
        # of a root flare is the trunk widening, not separate roots bolted on -
        # without it the ribs have nothing to grow out of.
        collar = trunk_settings["collar"]
        collar_flare = uniform_pair(rng, collar["flare"])
        collar_height = max(uniform_pair(rng, collar["height_fraction"]), 1e-3)
        collar_power = float(collar["power"])
        radii = [
            value * (1.0 + collar_flare * max(0.0, 1.0 - (step_index / segments) / collar_height) ** collar_power)
            for step_index, value in enumerate(radii)
        ]
        # Let the braided cords thicken before they peel into first-order
        # branches. This creates a procedural branch collar and avoids the
        # hourglass silhouette produced by a wide braid feeding thin shafts.
        tip_flare_start = float(transition["cord_tip_flare_start_fraction"])
        tip_flare_scale = float(transition["cord_tip_flare_scale"])
        radii = [
            value
            * lerp_float(
                1.0,
                tip_flare_scale,
                smoothstep01(
                    ((step_index / segments) - tip_flare_start)
                    / max(1.0 - tip_flare_start, 1e-6)
                ),
            )
            for step_index, value in enumerate(radii)
        ]
        visual_tip_direction = (points[-1] - points[-2]).normalized()
        branch_tip_direction = (branch_axis_points[-1] - branch_axis_points[-2]).normalized()
        tier_index = depth_tier(branch_tip_direction, tiers, rng)

        # Second level of braiding: the strand is itself a bundle of cords with
        # their own twist. One spiral reads as a smoothly bent pole no matter how
        # much surface relief it carries; a spiral of spirals is what puts real
        # depth into the silhouette, because the cords occlude each other.
        sub = braid.get("sub")
        if sub is None:
            cord_specs = [(points, radii, f"rust_crown_strand_{index:02d}")]
        else:
            cord_specs = []
            cord_count = randint_pair(rng, sub["count"])
            cord_radius = radius * uniform_pair(rng, sub["radius_fraction"])
            cord_closed = cord_radius * uniform_pair(rng, sub["bundle_closed_fraction"])
            cord_open = radius * uniform_pair(rng, sub["bundle_open_fraction"])
            cord_power = float(sub["bundle_open_power"])
            cord_fork_open_fraction = float(sub["fork_open_fraction"])
            cord_fork_open_start_fraction = float(sub["fork_open_start_fraction"])
            cord_turns = uniform_pair(rng, sub["turns"]) * rng.choice((-1.0, 1.0))
            for cord in range(cord_count):
                cord_azimuth = math.tau * cord / cord_count + rng.gauss(0.0, 0.15)
                cord_points = strand_polyline(
                    points,
                    cord_azimuth,
                    cord_turns,
                    cord_closed,
                    cord_open,
                    cord_power,
                    cord_fork_open_fraction,
                    cord_fork_open_start_fraction,
                )
                # Cord thickness rides the strand profile, so the collar swell
                # and the taper carry through to every cord.
                scale = cord_radius / max(radius, 1e-6) * rng.uniform(0.85, 1.15)
                cord_radii = [value * scale for value in radii]
                cord_specs.append((cord_points, cord_radii, f"rust_crown_strand_{index:02d}_cord_{cord:02d}"))

        cord_tips: list[dict] = []
        for cord_points, cord_radii, cord_name in cord_specs:
            cord_relief = relief_settings(rng, trunk_settings.get("relief"))
            cord_tips.append(
                {
                    "name": cord_name,
                    "points": cord_points,
                    "radii": cord_radii,
                    "position": cord_points[-1],
                    "direction": (cord_points[-1] - cord_points[-2]).normalized(),
                    "radius": cord_radii[-1],
                    "relief": cord_relief,
                }
            )

        launches.append(
            {
                "position": points[-1],
                "entry_direction": visual_tip_direction,
                "branch_direction": branch_tip_direction,
                "radius": tip_radius,
                "azimuth": azimuth + turns * math.tau,
                "tier_index": tier_index,
                "cords": cord_tips,
            }
        )
        paths.append((points, radii, azimuth))
    return launches, paths


def create_tree(variant: dict, profile: dict, sun_to_light: Vector) -> list[tuple[bpy.types.Object, str]]:
    """Grow one tree. Returns (object, layer) pairs for the canonical layer split."""
    rng = random.Random(int(variant["seed"]))
    geometry = profile["geometry"]
    trunk_settings = geometry["trunk"]
    world_scale = float(variant.get("world_scale", 1.0))
    height_scale = float(variant.get("height_scale", 1.0))

    parts: list[tuple[bpy.types.Object, str]] = []
    leaves: list[dict] = []
    base_radius = uniform_pair(rng, trunk_settings["base_radius"]) * world_scale

    lean = math.radians(uniform_pair(rng, trunk_settings["lean_degrees"]))
    lean_azimuth = rng.uniform(0.0, math.tau)
    direction = Vector((math.cos(lean_azimuth) * math.sin(lean), math.sin(lean_azimuth) * math.sin(lean), math.cos(lean)))
    trunk_length = uniform_pair(rng, trunk_settings["height"]) * world_scale * height_scale

    # The braid has to exist before the roots: fibres peel off the strands.
    launches, strand_paths = grow_trunk(
        parts,
        profile,
        rng,
        Vector((0.0, 0.0, -base_radius * 0.6)),
        direction,
        trunk_length,
        base_radius,
    )
    add_root_fibers(parts, profile, rng, strand_paths, world_scale)

    branching = geometry["branching"]
    spread = math.radians(uniform_pair(rng, trunk_settings["braid"]["strand_spread_degrees"]))
    for index, launch in enumerate(launches):
        position: Vector = launch["position"]
        entry_direction: Vector = launch["entry_direction"]
        branch_direction: Vector = launch["branch_direction"]
        tip_radius = float(launch["radius"])
        azimuth = float(launch["azimuth"])
        # Each strand leaves the fork leaning away from the bundle axis, so the
        # braid opens into a candelabra instead of a bouquet of parallel poles.
        bend_axis = perpendicular(branch_direction)
        bend_axis.rotate(Quaternion(branch_direction, azimuth))
        launch_direction = branch_direction.copy()
        launch_direction.rotate(Quaternion(bend_axis, spread))
        grow_branch(
            parts,
            leaves,
            profile,
            variant,
            rng,
            sun_to_light,
            position,
            launch_direction,
            trunk_length * uniform_pair(rng, branching["length_fraction"]),
            tip_radius,
            1,
            f"branch{index}",
            int(launch["tier_index"]),
            entry_direction,
            launch["cords"],
        )

    paint_leaves(leaves, profile, rng)
    bpy.context.view_layer.update()
    return parts


# --- framing ---------------------------------------------------------------


def measure_framing(camera: bpy.types.Object, objects: list[bpy.types.Object], frame_size: int) -> dict:
    """Record world size, because the canonical camera refits every asset.

    Without this the proof sheet cannot show how this tree sizes up against the
    shipped ones: every asset fills the same fraction of its own frame.
    """
    corners = BAKE.all_world_corners(objects)
    min_x = min(c.x for c in corners)
    max_x = max(c.x for c in corners)
    min_y = min(c.y for c in corners)
    max_y = max(c.y for c in corners)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    ortho_scale = float(camera.data.ortho_scale)
    return {
        "ortho_scale": ortho_scale,
        "pixels_per_world_unit": float(frame_size) / ortho_scale if ortho_scale > 0.0 else 0.0,
        "world_bbox": [min_x, min_y, min_z, max_x, max_y, max_z],
        "world_width": max_x - min_x,
        "world_depth": max_y - min_y,
        "world_height": max_z - min_z,
    }


def main() -> None:
    args = parse_args()
    bake_profile = load_json(args.profile)
    tree_profile = load_json(args.tree_profile)
    variant = find_variant(tree_profile, args.variant_id)

    # The canonical camera fits the *tree*, not its shadow, and the shipped
    # trees are narrow enough that the time-stretched shadow still lands inside
    # the frame. A rust crown is nearly as wide as it is tall, so at the shipped
    # fit fractions the shadow runs off the right edge and the asset ships with
    # a straight cut through it. Widening the fit is authored per asset family
    # here; the canonical profile stays owned by the shipped trees.
    camera_fit = dict(tree_profile.get("camera_fit", {}))
    camera_fit.update(variant.get("camera_fit", {}))
    if camera_fit:
        bake_profile = {**bake_profile, "camera": {**bake_profile["camera"], **camera_fit}}

    # The canonical ground bounce is tuned for the shipped bark. This bark is
    # far darker, and at full bounce energy the shaded side lifts to match the
    # sun-lit side, so the trunk loses its form and the tree stops reading as
    # lit from the north-west at all. Sun angles stay canonical; only the fill
    # is authored down here.
    lighting_override = dict(tree_profile.get("lighting", {}))
    bounce_override = dict(lighting_override.pop("bounce", {}))
    if lighting_override or bounce_override:
        lighting = {**bake_profile["lighting"], **lighting_override}
        if bounce_override:
            lighting["bounce"] = {**bake_profile["lighting"]["bounce"], **bounce_override}
        bake_profile = {**bake_profile, "lighting": lighting}

    frame_size = int(bake_profile["frame_size"])
    yaw_degrees = float(variant.get("yaw_degrees", bake_profile["orientation"]["default_yaw_degrees"]))
    sun_angle_degrees = float(bake_profile["lighting"]["sun_azimuth_degrees"])
    embed_fraction = float(variant.get("embed_fraction", bake_profile["planting"]["root_embed_fraction"]))

    # Direction *toward* the sun, built the same way the canonical sun lamp is
    # oriented, so the crown's gold side and the render's lit side agree.
    sun_ray = Vector((0.0, 0.0, -1.0))
    sun_ray.rotate(
        Euler(
            (
                math.radians(float(bake_profile["lighting"]["albedo_sun_elevation_degrees"])),
                0.0,
                math.radians(sun_angle_degrees),
            )
        )
    )
    sun_to_light = -sun_ray

    BAKE.clear_scene()
    _MATERIAL_CACHE.clear()
    parts = create_tree(variant, tree_profile, sun_to_light)
    objects = [obj for obj, _layer in parts]

    BAKE.normalize_tree(
        objects,
        yaw_degrees,
        embed_fraction,
        float(bake_profile["planting"]["max_root_embed_fraction"]),
    )

    classification = {obj.name: {"layer": layer} for obj, layer in parts}

    corners = BAKE.all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(bake_profile["camera"]["target_z_fraction"])
    camera, _sun = BAKE.setup_render(frame_size, camera_target_z, sun_angle_degrees, bake_profile)
    anchor = BAKE.fit_camera_to_objects(camera, objects, bake_profile)
    framing = measure_framing(camera, objects, frame_size)

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for layer, file_name in (
        ("all", "albedo.png"),
        ("trunk", "trunk.png"),
        ("foliage", "foliage.png"),
    ):
        BAKE.set_layer_visibility(objects, classification, layer)
        BAKE.render_png(out_dir / file_name)

    BAKE.set_layer_visibility(objects, classification, "all")
    BAKE.setup_shadow_scene(objects, sun_angle_degrees, bake_profile)
    BAKE.render_png(out_dir / "shadow_raw.png")

    metadata = {
        "source_glb": "",
        "source": "procedural",
        "generator": "tools/tree_atlas/blender_rust_crown_tree_bake.py",
        "tree_profile_id": tree_profile["profile_id"],
        "tree_profile_version": tree_profile["version"],
        "variant_id": variant["id"],
        "frame_width": frame_size,
        "frame_height": frame_size,
        "anchor": list(anchor),
        "yaw_degrees": yaw_degrees,
        "sun_angle_degrees": sun_angle_degrees,
        "root_embed_fraction": embed_fraction,
        "bake_profile": BAKE.bake_profile_summary(bake_profile, frame_size, sun_angle_degrees, embed_fraction),
        "runtime_plant_depth_px": 0,
        "collision_footprint": dict(variant["collision_footprint"]),
        "classification": classification,
        "layers": {
            "albedo": "albedo.png",
            "trunk": "trunk.png",
            "foliage": "foliage.png",
            "shadow_raw": "shadow_raw.png",
        },
    }
    with (out_dir / "classification.json").open("w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent="\t", ensure_ascii=False)

    variation_record = {
        "profile_id": tree_profile["profile_id"],
        "version": tree_profile["version"],
        "variant": variant,
        "framing": framing,
        "part_counts": {
            "foliage": sum(1 for _obj, layer in parts if layer == "foliage"),
            "trunk": sum(1 for _obj, layer in parts if layer == "trunk"),
        },
    }
    with (out_dir / "variation.json").open("w", encoding="utf-8") as fh:
        json.dump(variation_record, fh, indent="\t", ensure_ascii=False)

    print(f"Wrote procedural rust crown tree render source for {variant['id']} to {out_dir}")


if __name__ == "__main__":
    main()
