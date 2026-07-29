"""Bake one procedurally generated alien bush into the canonical layered frames.

This script does not own bake settings. Camera, lighting, render engines, sun
angles, the layer cross-shadow rule and the Cycles shadow-catcher pass all come
from the canonical module `blender_layered_tree_asset_bake.py` and
`layered_asset_bake_profile.json` — the same contract the shipped trees are
baked against.

What it replaces is the *source* stage. A tree arrives as a GLB; a bush is grown
from a seed instead:

  caudex -> rosette blades -> ground blades -> pod arcs -> canonical bake

The silhouette is the alien part. A rosette of creased, serrated blades forms a
low cup, and thin arcs rise out of it carrying luminous capsules, so the plant
reads as "not a shrub from Earth" before its colour is even legible.

Layer split follows the tree contract: everything that should move on the wind
(blades, pods, beads) is `foliage`, everything planted (caudex, arcs) is
`trunk`. The postprocess derives the wind mask from exactly that split.
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
from mathutils import Vector

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
TREE_TOOL_DIR = REPO_ROOT / "tools" / "tree_atlas"
DEFAULT_BAKE_PROFILE = TREE_TOOL_DIR / "layered_asset_bake_profile.json"
DEFAULT_BUSH_PROFILE = TOOL_DIR / "alien_bush_profiles.json"


def load_canonical_bake_module():
    path = TREE_TOOL_DIR / "blender_layered_tree_asset_bake.py"
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
    parser.add_argument("--bush-profile", type=Path, default=DEFAULT_BUSH_PROFILE)
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    return parser.parse_args(argv)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def find_variant(bush_profile: dict, variant_id: str) -> dict:
    for variant in bush_profile["variants"]:
        if variant["id"] == variant_id:
            return variant
    known = ", ".join(v["id"] for v in bush_profile["variants"])
    raise SystemExit(f"Unknown variant id {variant_id!r}. Known ids: {known}")


# --- colour ----------------------------------------------------------------


def srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def linear_rgba(srgb: tuple[float, float, float], scale: float = 1.0) -> tuple[float, float, float, float]:
    return (
        srgb_to_linear(max(0.0, min(1.0, srgb[0] * scale))),
        srgb_to_linear(max(0.0, min(1.0, srgb[1] * scale))),
        srgb_to_linear(max(0.0, min(1.0, srgb[2] * scale))),
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


def ramp_rgb(ramp: dict, amount: float, tip_power: float = 1.0) -> tuple[float, float, float]:
    """Root -> mid -> tip, with the hot tip pushed onto the last stretch.

    A blade is widest around its middle, so a linear ramp paints most of the
    plant's *area* in the tip colour. Against an orange biofield that turns the
    whole bush orange and the silhouette stops reading.
    """
    shaped = max(0.0, min(1.0, amount)) ** max(tip_power, 1e-6)
    root = rgb_255(ramp["root"])
    mid = rgb_255(ramp["mid"])
    tip = rgb_255(ramp["tip"])
    if shaped <= 0.5:
        return lerp_rgb(root, mid, shaped / 0.5)
    return lerp_rgb(mid, tip, (shaped - 0.5) / 0.5)


_MATERIAL_CACHE: dict[tuple, bpy.types.Material] = {}


def make_material(
    name: str,
    srgb: tuple[float, float, float],
    roughness: float,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Base Color"].default_value = linear_rgba(srgb)
    principled.inputs["Roughness"].default_value = float(roughness)
    if "Specular IOR Level" in principled.inputs:
        principled.inputs["Specular IOR Level"].default_value = 0.32
    elif "Specular" in principled.inputs:
        principled.inputs["Specular"].default_value = 0.32
    if emission_strength > 0.0:
        emission_color = principled.inputs.get("Emission Color") or principled.inputs.get("Emission")
        emission_input = principled.inputs.get("Emission Strength")
        if emission_color is None or emission_input is None:
            raise RuntimeError("Principled BSDF has no emission inputs in this Blender build")
        emission_color.default_value = linear_rgba(srgb)
        emission_input.default_value = float(emission_strength)
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    mat.diffuse_color = (srgb[0], srgb[1], srgb[2], 1.0)
    return mat


def blade_step_material(
    profile: dict,
    ramp_key: str,
    ramp_index: int,
    tier_index: int,
    tone_index: int,
    step: int,
    steps: int,
) -> bpy.types.Material:
    key = (ramp_key, ramp_index, tier_index, tone_index, step)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    palette = profile["palette"]
    # Depth tier darkens by position in the bush; the tone jitter is per blade,
    # so two neighbours at the same depth still differ.
    scale = float(palette["shade_tiers"][tier_index]) * float(palette["blade_tone_jitter"][tone_index])
    amount = step / max(steps - 1, 1)
    base = ramp_rgb(palette[ramp_key][ramp_index], amount, float(palette["blade_tip_power"]))
    mat = make_material(
        f"bush_{ramp_key}_{ramp_index}_t{tier_index}_j{tone_index}_s{step}",
        (base[0] * scale, base[1] * scale, base[2] * scale),
        float(profile["material"]["blade_roughness"]),
    )
    _MATERIAL_CACHE[key] = mat
    return mat


def stem_step_material(profile: dict, tier_index: int, step: int, steps: int) -> bpy.types.Material:
    key = ("stem", tier_index, step)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    palette = profile["palette"]
    tier = float(palette["shade_tiers"][tier_index])
    amount = step / max(steps - 1, 1)
    base = ramp_rgb(palette["stem_ramp"], amount)
    mat = make_material(
        f"bush_stem_t{tier_index}_s{step}",
        (base[0] * tier, base[1] * tier, base[2] * tier),
        float(profile["material"]["stem_roughness"]),
    )
    _MATERIAL_CACHE[key] = mat
    return mat


def pod_material(profile: dict, index: int, tier_index: int) -> bpy.types.Material:
    key = ("pod", index, tier_index)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    palette = profile["palette"]
    tier = float(palette["shade_tiers"][tier_index])
    base = rgb_255(palette["pod_rgb"][index])
    mat = make_material(
        f"bush_pod_{index}_t{tier_index}",
        (base[0] * tier, base[1] * tier, base[2] * tier),
        float(profile["material"]["pod_roughness"]),
        float(profile["material"]["pod_emission_strength"]),
    )
    _MATERIAL_CACHE[key] = mat
    return mat


def bead_material(profile: dict, index: int) -> bpy.types.Material:
    key = ("bead", index)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    mat = make_material(
        f"bush_bead_{index}",
        rgb_255(profile["palette"]["bead_rgb"][index]),
        float(profile["material"]["pod_roughness"]),
        float(profile["material"]["bead_emission_strength"]),
    )
    _MATERIAL_CACHE[key] = mat
    return mat


# --- geometry --------------------------------------------------------------


def growth_arc(
    length: float,
    theta_start: float,
    theta_end: float,
    bend_power: float,
    segments: int,
) -> list[tuple[Vector, float]]:
    """Centre line of one organ, integrated from a turning growth angle.

    Theta is measured from vertical toward +X, so a blade that starts near 0 and
    ends past 90 stands up, arcs over and lets its tip fall back down — which is
    what makes the rosette read as a cup instead of a starburst.
    """
    points: list[tuple[Vector, float]] = []
    position = Vector((0.0, 0.0, 0.0))
    step = length / segments
    for index in range(segments + 1):
        t = index / segments
        theta = theta_start + (theta_end - theta_start) * (t ** bend_power)
        points.append((position.copy(), theta))
        position += Vector((math.sin(theta), 0.0, math.cos(theta))) * step
    return points


def blade_half_width(t: float, half_width: float, serration: float, cycles: float) -> float:
    shape = ((t + 0.12) ** 0.45) * (max(0.0, 1.0 - t ** 2.6) ** 0.55)
    ripple = 1.0 + serration * math.sin(t * cycles * math.tau)
    return half_width * shape * ripple * 1.35


def blade_mesh(
    name: str,
    length: float,
    half_width: float,
    theta_start: float,
    theta_end: float,
    bend_power: float,
    twist: float,
    crease: float,
    serration: float,
    serration_cycles: float,
    segments: int,
) -> bpy.types.Mesh:
    """One fleshy blade: a creased ribbon with a serrated outline.

    The crease is what gives a flat ribbon a lit side and a shaded side under
    the fixed bake sun; without it the rosette flattens into paper cut-outs.
    """
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    for index, (position, theta) in enumerate(growth_arc(length, theta_start, theta_end, bend_power, segments)):
        t = index / segments
        tangent_normal = Vector((math.cos(theta), 0.0, -math.sin(theta)))
        side_axis = Vector((0.0, 1.0, 0.0))
        angle = twist * t
        side = side_axis * math.cos(angle) + tangent_normal * math.sin(angle)
        lift = -side_axis * math.sin(angle) + tangent_normal * math.cos(angle)
        width = blade_half_width(t, half_width, serration, serration_cycles)
        vertices.append(tuple(position - side * width))
        vertices.append(tuple(position + lift * (crease * width)))
        vertices.append(tuple(position + side * width))
        if index > 0:
            base = index * 3
            faces.append((base - 3, base - 2, base + 1, base))
            faces.append((base - 2, base - 1, base + 2, base + 1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return mesh


def stem_mesh(
    name: str,
    length: float,
    half_width: float,
    theta_start: float,
    theta_end: float,
    bend_power: float,
    tip_fraction: float,
    segments: int,
    sides: int,
) -> tuple[bpy.types.Mesh, Vector, float]:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    arc = growth_arc(length, theta_start, theta_end, bend_power, segments)
    for index, (position, theta) in enumerate(arc):
        t = index / segments
        normal = Vector((math.cos(theta), 0.0, -math.sin(theta)))
        side = Vector((0.0, 1.0, 0.0))
        radius = half_width * (1.0 - (1.0 - tip_fraction) * t)
        for corner in range(sides):
            angle = corner / sides * math.tau
            offset = side * (math.cos(angle) * radius) + normal * (math.sin(angle) * radius)
            vertices.append(tuple(position + offset))
        if index > 0:
            ring = index * sides
            previous = ring - sides
            for corner in range(sides):
                next_corner = (corner + 1) % sides
                faces.append(
                    (
                        previous + corner,
                        previous + next_corner,
                        ring + next_corner,
                        ring + corner,
                    )
                )
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    tip_position, tip_theta = arc[-1]
    return mesh, tip_position, tip_theta


def new_object(name: str, mesh: bpy.types.Mesh, location: Vector, yaw: float) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, yaw)
    return obj


def add_sphere(
    name: str,
    location: Vector,
    radius: float,
    material: bpy.types.Material,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def depth_tier(azimuth: float, tiers: int, rng: random.Random) -> int:
    """Organs growing away from the camera sink into darker tiers.

    The bake camera sits at -Y and looks toward +Y, so sin(azimuth) is how far
    an organ leans into the depth of the bush.
    """
    depth = 0.5 + 0.5 * math.sin(azimuth)
    index = int(round(depth * (tiers - 1))) + rng.choice((-1, 0, 0))
    return max(0, min(tiers - 1, index))


def uniform_pair(rng: random.Random, values: list) -> float:
    return rng.uniform(float(values[0]), float(values[1]))


def randint_pair(rng: random.Random, values: list) -> int:
    return rng.randint(int(values[0]), int(values[1]))


def assign_step_materials(obj: bpy.types.Object, materials: list[bpy.types.Material], faces_per_step: int) -> None:
    for material in materials:
        obj.data.materials.append(material)
    steps = len(materials)
    for index, polygon in enumerate(obj.data.polygons):
        polygon.material_index = min(index // faces_per_step, steps - 1)


def create_bush(variant: dict, profile: dict) -> list[tuple[bpy.types.Object, str]]:
    """Grow one bush. Returns (object, layer) pairs for the canonical layer split."""
    rng = random.Random(int(variant["seed"]))
    geometry = profile["geometry"]
    palette = profile["palette"]
    world_scale = float(variant.get("world_scale", 1.0))
    tiers = len(palette["shade_tiers"])
    blade_segments = int(geometry["blade_segments"])
    color_steps = int(geometry["blade_color_steps"])
    stem_segments = int(geometry["stem_segments"])
    stem_sides = int(geometry["stem_sides"])
    faces_per_blade_step = max(1, (blade_segments * 2) // color_steps)
    faces_per_stem_step = max(1, (stem_segments * stem_sides) // color_steps)

    parts: list[tuple[bpy.types.Object, str]] = []

    caudex = add_sphere(
        "bush_caudex",
        Vector((0.0, 0.0, -float(geometry["caudex_sink"]) * world_scale)),
        float(geometry["caudex_radius"]) * world_scale,
        make_material("bush_caudex", rgb_255(palette["caudex_rgb"]), float(profile["material"]["stem_roughness"])),
        scale=(1.0, 1.0, float(geometry["caudex_flatten"])),
    )
    parts.append((caudex, "trunk"))

    def grow_blades(settings: dict, ramp_key: str, name_prefix: str, layer: str) -> None:
        count = randint_pair(rng, settings["count"])
        ramps = palette[ramp_key]
        for index in range(count):
            azimuth = index / count * math.tau + rng.gauss(0.0, 0.17)
            base_radius = uniform_pair(rng, settings["base_radius"]) * world_scale
            base = Vector(
                (
                    math.cos(azimuth) * base_radius,
                    math.sin(azimuth) * base_radius,
                    uniform_pair(rng, settings["base_z"]) * world_scale,
                )
            )
            # A minority of blades keep turning past horizontal and curl back
            # toward the ground. That broken-outline minority is what stops the
            # rosette from reading as an agave.
            theta_end = uniform_pair(rng, settings["theta_end_degrees"])
            if rng.random() < float(settings["curl_fraction"]):
                theta_end += uniform_pair(rng, settings["curl_extra_degrees"])
            mesh = blade_mesh(
                f"{name_prefix}_{index:02d}",
                uniform_pair(rng, settings["length"]) * world_scale,
                uniform_pair(rng, settings["half_width"]) * world_scale,
                math.radians(uniform_pair(rng, settings["theta_start_degrees"])),
                math.radians(theta_end),
                uniform_pair(rng, settings["bend_power"]),
                math.radians(uniform_pair(rng, settings["twist_degrees"])),
                uniform_pair(rng, settings["crease"]),
                float(settings["serration"]),
                uniform_pair(rng, settings["serration_cycles"]),
                blade_segments,
            )
            obj = new_object(f"{name_prefix}_{index:02d}", mesh, base, azimuth)
            tier_index = depth_tier(azimuth, tiers, rng)
            ramp_index = rng.randrange(len(ramps))
            tone_index = rng.randrange(len(palette["blade_tone_jitter"]))
            assign_step_materials(
                obj,
                [
                    blade_step_material(profile, ramp_key, ramp_index, tier_index, tone_index, step, color_steps)
                    for step in range(color_steps)
                ],
                faces_per_blade_step,
            )
            parts.append((obj, layer))

    grow_blades(geometry["rosette"], "blade_ramps", "bush_blade", "foliage")
    grow_blades(geometry["ground_blades"], "ground_blade_ramps", "bush_ground_blade", "foliage")

    arcs = geometry["arcs"]
    arc_count = randint_pair(rng, arcs["count"])
    for index in range(arc_count):
        azimuth = index / arc_count * math.tau + rng.gauss(0.0, 0.28)
        base_radius = uniform_pair(rng, arcs["base_radius"]) * world_scale
        base = Vector((math.cos(azimuth) * base_radius, math.sin(azimuth) * base_radius, 0.0))
        length = uniform_pair(rng, arcs["length"]) * world_scale
        theta_start = math.radians(uniform_pair(rng, arcs["theta_start_degrees"]))
        theta_end = math.radians(uniform_pair(rng, arcs["theta_end_degrees"]))
        bend_power = uniform_pair(rng, arcs["bend_power"])
        mesh, tip_local, tip_theta = stem_mesh(
            f"bush_arc_{index:02d}",
            length,
            uniform_pair(rng, arcs["radius"]) * world_scale,
            theta_start,
            theta_end,
            bend_power,
            float(arcs["radius_tip_fraction"]),
            stem_segments,
            stem_sides,
        )
        arc_object = new_object(f"bush_arc_{index:02d}", mesh, base, azimuth)
        tier_index = depth_tier(azimuth, tiers, rng)
        assign_step_materials(
            arc_object,
            [stem_step_material(profile, tier_index, step, color_steps) for step in range(color_steps)],
            faces_per_stem_step,
        )
        parts.append((arc_object, "trunk"))

        def to_world(local: Vector) -> Vector:
            return base + Vector(
                (
                    local.x * math.cos(azimuth) - local.y * math.sin(azimuth),
                    local.x * math.sin(azimuth) + local.y * math.cos(azimuth),
                    local.z,
                )
            )

        # A cluster of small capsules, not one big ball: a single sphere on a
        # bare stalk reads as a lollipop, and at this size a seed head is what
        # makes the plant look grown rather than assembled.
        spread = uniform_pair(rng, arcs["pod_cluster_spread"]) * world_scale
        for pod_index in range(randint_pair(rng, arcs["pod_cluster"])):
            offset = Vector(
                (
                    rng.gauss(0.0, spread),
                    rng.gauss(0.0, spread),
                    -uniform_pair(rng, arcs["pod_sink"]) * world_scale + rng.gauss(0.0, spread * 0.5),
                )
            )
            pod = add_sphere(
                f"bush_pod_{index:02d}_{pod_index:02d}",
                to_world(tip_local) + offset,
                uniform_pair(rng, arcs["pod_radius"]) * world_scale * rng.uniform(0.72, 1.12),
                pod_material(profile, rng.randrange(len(palette["pod_rgb"])), tier_index),
                scale=(1.0, 1.0, uniform_pair(rng, arcs["pod_stretch"])),
                rotation=(0.0, tip_theta + rng.gauss(0.0, 0.25), azimuth),
            )
            parts.append((pod, "foliage"))

        for bead_index in range(randint_pair(rng, arcs["bead_count"])):
            t = uniform_pair(rng, arcs["bead_position"])
            arc_points = growth_arc(length, theta_start, theta_end, bend_power, stem_segments)
            local = arc_points[min(len(arc_points) - 1, int(t * stem_segments))][0]
            bead = add_sphere(
                f"bush_bead_{index:02d}_{bead_index:02d}",
                to_world(local),
                uniform_pair(rng, arcs["bead_radius"]) * world_scale,
                bead_material(profile, rng.randrange(len(palette["bead_rgb"]))),
            )
            parts.append((bead, "foliage"))

    bpy.context.view_layer.update()
    return parts


# --- framing ---------------------------------------------------------------


def measure_framing(camera: bpy.types.Object, objects: list[bpy.types.Object], frame_size: int) -> dict:
    """Record world size, because the canonical camera refits every asset.

    Without this the proof sheet cannot show that the bush is small next to a
    tree: both fill the same fraction of their own frame.
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
    bush_profile = load_json(args.bush_profile)
    variant = find_variant(bush_profile, args.variant_id)

    frame_size = int(bake_profile["frame_size"])
    yaw_degrees = float(variant.get("yaw_degrees", bake_profile["orientation"]["default_yaw_degrees"]))
    sun_angle_degrees = float(bake_profile["lighting"]["sun_azimuth_degrees"])
    embed_fraction = float(variant.get("embed_fraction", bake_profile["planting"]["root_embed_fraction"]))

    BAKE.clear_scene()
    _MATERIAL_CACHE.clear()
    parts = create_bush(variant, bush_profile)
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
        "generator": "tools/bush_atlas/blender_alien_bush_bake.py",
        "bush_profile_id": bush_profile["profile_id"],
        "bush_profile_version": bush_profile["version"],
        "variant_id": variant["id"],
        "frame_width": frame_size,
        "frame_height": frame_size,
        "anchor": list(anchor),
        "yaw_degrees": yaw_degrees,
        "sun_angle_degrees": sun_angle_degrees,
        "root_embed_fraction": embed_fraction,
        "bake_profile": BAKE.bake_profile_summary(bake_profile, frame_size, sun_angle_degrees, embed_fraction),
        "runtime_plant_depth_px": 0,
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
        "profile_id": bush_profile["profile_id"],
        "version": bush_profile["version"],
        "variant": variant,
        "framing": framing,
        "part_counts": {
            "foliage": sum(1 for _obj, layer in parts if layer == "foliage"),
            "trunk": sum(1 for _obj, layer in parts if layer == "trunk"),
        },
    }
    with (out_dir / "variation.json").open("w", encoding="utf-8") as fh:
        json.dump(variation_record, fh, indent="\t", ensure_ascii=False)

    print(f"Wrote procedural alien bush render source for {variant['id']} to {out_dir}")


if __name__ == "__main__":
    main()
