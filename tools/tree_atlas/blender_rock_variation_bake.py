"""Bake one procedurally generated stone into the canonical layered rock frames.

This script does not own bake settings. Camera, lighting, render engine, sun
angles and the shadow-catcher pass all come from the canonical module
`blender_layered_rock_asset_bake.py` and `layered_asset_bake_profile.json`.

What it replaces is the *source* stage. The shipped rocks are one-to-one bakes
of downloaded GLBs, so their variety is bounded by whichever models were found.
Here the mesh is generated from a seed instead:

  icosphere -> anisotropic shape -> facet cuts -> corner chips -> erosion -> bake

The four shaping stages are ordered deliberately. Facet cuts run before chips so
a chip can bite into an already-flat face, and erosion runs last so its grain
survives on every surface instead of being flattened away by a later cut.

A slab is not a separate code path: it is the same generator with `flatten` low
and `embed_fraction` high, so the stone reads as sunk into the ground rather
than resting on it.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector, noise

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_BAKE_PROFILE = TOOL_DIR / "layered_asset_bake_profile.json"
DEFAULT_VARIATION_PROFILE = TOOL_DIR / "rock_variation_profiles.json"


def load_canonical_bake_module():
    path = TOOL_DIR / "blender_layered_rock_asset_bake.py"
    spec = importlib.util.spec_from_file_location("layered_rock_asset_bake", path)
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
    parser.add_argument("--variation-profile", type=Path, default=DEFAULT_VARIATION_PROFILE)
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    return parser.parse_args(argv)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def find_variant(variation_profile: dict, variant_id: str) -> dict:
    for variant in variation_profile["variants"]:
        if variant["id"] == variant_id:
            return variant
    known = ", ".join(v["id"] for v in variation_profile["variants"])
    raise SystemExit(f"Unknown variant id {variant_id!r}. Known ids: {known}")


def srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


# --- geometry stages -------------------------------------------------------


def random_unit_vector(rng: random.Random) -> Vector:
    """Uniform on the sphere; the naive per-axis uniform clusters at corners."""
    while True:
        vector = Vector(
            (
                rng.uniform(-1.0, 1.0),
                rng.uniform(-1.0, 1.0),
                rng.uniform(-1.0, 1.0),
            )
        )
        length = vector.length
        if 1e-4 < length <= 1.0:
            return vector / length


def apply_anisotropic_shape(bm: bmesh.types.BMesh, variant: dict) -> None:
    """Squash, stretch and taper the sphere into the family's rough proportions."""
    flatten = float(variant["flatten"])
    elongation = float(variant["elongation"])
    taper = float(variant["taper"])
    for vert in bm.verts:
        co = vert.co
        # Taper is measured on the original sphere height, so it stays a shape
        # parameter rather than a second flatten.
        height_fraction = (co.z + 1.0) * 0.5
        taper_scale = 1.0 - taper * max(0.0, height_fraction) ** 1.4
        co.x *= elongation * taper_scale
        co.y *= taper_scale
        co.z *= flatten


def apply_facet_cuts(bm: bmesh.types.BMesh, variant: dict, geometry: dict, rng: random.Random) -> None:
    """Project everything past a random plane onto that plane, making a flat face.

    Near-vertical plane normals are rejected: on an already-flattened slab a cut
    from directly above would shave the whole top surface off instead of
    producing an edge, which is the difference between a stone and a wafer.
    """
    count = int(variant["facet_count"])
    sharpness = float(variant["facet_sharpness"])
    min_offset = float(geometry["facet_min_offset"])
    max_offset = float(geometry["facet_max_offset"])
    max_vertical = float(geometry["facet_max_vertical"])
    if count <= 0 or sharpness <= 0.0:
        return

    radius = max((vert.co.length for vert in bm.verts), default=1.0)
    for _ in range(count):
        normal = random_unit_vector(rng)
        attempts = 0
        while abs(normal.z) > max_vertical and attempts < 16:
            normal = random_unit_vector(rng)
            attempts += 1
        offset = rng.uniform(min_offset, max_offset) * radius
        for vert in bm.verts:
            distance = vert.co.dot(normal) - offset
            if distance > 0.0:
                vert.co -= normal * (distance * sharpness)


def apply_chips(bm: bmesh.types.BMesh, variant: dict, geometry: dict, rng: random.Random) -> None:
    """Bite chunks out of the surface so the silhouette is not a convex blob."""
    count = int(variant["chip_count"])
    depth = float(variant["chip_depth"])
    if count <= 0 or depth <= 0.0:
        return

    min_radius = float(geometry["chip_min_radius"])
    max_radius = float(geometry["chip_max_radius"])
    verts = list(bm.verts)
    extent = max((vert.co.length for vert in verts), default=1.0)
    for _ in range(count):
        origin = verts[rng.randrange(len(verts))].co.copy()
        chip_radius = rng.uniform(min_radius, max_radius) * extent
        chip_depth = depth * extent
        for vert in verts:
            distance = (vert.co - origin).length
            if distance >= chip_radius:
                continue
            falloff = (1.0 - distance / chip_radius) ** 1.2
            direction = vert.co.normalized() if vert.co.length > 1e-5 else Vector((0.0, 0.0, 1.0))
            vert.co -= direction * (chip_depth * falloff)


def apply_erosion(bm: bmesh.types.BMesh, variant: dict, geometry: dict, seed: int) -> None:
    """Displace along the radius by summed Perlin octaves.

    The sample point is offset by a seed-derived vector rather than through
    `noise.seed_set`, so two variants with different seeds read different parts
    of the same continuous field and the result stays reproducible.
    """
    scale = float(variant["erosion_scale"])
    strength = float(variant["erosion_strength"])
    if strength <= 0.0 or scale <= 0.0:
        return

    octaves = geometry["erosion_octaves"]
    offset = Vector(
        (
            (seed % 977) * 0.37,
            (seed % 613) * 0.53,
            (seed % 419) * 0.71,
        )
    )
    extent = max((vert.co.length for vert in bm.verts), default=1.0)
    for vert in bm.verts:
        if vert.co.length <= 1e-5:
            continue
        total = 0.0
        for octave in octaves:
            point = vert.co * (2.0 / scale) * float(octave["frequency"]) + offset
            total += noise.noise(point) * float(octave["weight"])
        vert.co += vert.co.normalized() * (total * strength * extent)


def mark_sharp_edges(bm: bmesh.types.BMesh, angle_degrees: float) -> None:
    """Split edges whose faces meet at a steep angle, then shade everything smooth.

    Flat shading over ~1300 eroded faces reads as noise, and pure smooth shading
    rounds the facet cuts away. Splitting only the steep edges keeps a cut
    looking cut while erosion stays a soft grain.
    """
    threshold = math.radians(angle_degrees)
    sharp = []
    for edge in bm.edges:
        if len(edge.link_faces) != 2:
            continue
        if edge.calc_face_angle(0.0) >= threshold:
            sharp.append(edge)
    if sharp:
        bmesh.ops.split_edges(bm, edges=sharp)
    for face in bm.faces:
        face.smooth = True


def build_rock_object(variant: dict, geometry: dict) -> bpy.types.Object:
    seed = int(variant["seed"])
    rng = random.Random(seed)

    bm = bmesh.new()
    bmesh.ops.create_icosphere(
        bm,
        subdivisions=int(geometry["base_subdivisions"]),
        radius=1.0,
    )

    apply_anisotropic_shape(bm, variant)
    apply_facet_cuts(bm, variant, geometry, rng)
    apply_chips(bm, variant, geometry, rng)
    apply_erosion(bm, variant, geometry, seed)
    mark_sharp_edges(bm, float(geometry["sharp_edge_angle_degrees"]))

    world_scale = float(variant.get("world_scale", 1.0))
    if world_scale != 1.0:
        for vert in bm.verts:
            vert.co *= world_scale

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(f"ProcRock_{variant['id']}")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new(f"ProcRock_{variant['id']}", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# --- material --------------------------------------------------------------


def make_rock_material(variant: dict, material_profile: dict) -> bpy.types.Material:
    """Stone surface: a tinted base, a crack network, and a fine grain.

    Both detail layers are bump only. Displacing them into geometry would fight
    the silhouette work above, and the runtime does not consume normal maps yet
    (see the bake contract), so surface relief has to live in the albedo shading.
    """
    tint_shift = float(variant.get("tint_shift", 0.0))
    base_srgb = [float(channel) / 255.0 for channel in material_profile["base_color_srgb"]]
    brightness = 1.0 + tint_shift
    # A warm stone shifts red up and blue down; a cool one does the reverse.
    base_linear = (
        srgb_to_linear(min(1.0, base_srgb[0] * (brightness + tint_shift * 0.35))),
        srgb_to_linear(min(1.0, base_srgb[1] * brightness)),
        srgb_to_linear(min(1.0, base_srgb[2] * (brightness - tint_shift * 0.45))),
        1.0,
    )

    mat = bpy.data.materials.new(f"ProcRock_{variant['id']}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Base Color"].default_value = base_linear
    principled.inputs["Roughness"].default_value = float(material_profile["roughness"])
    if "Specular IOR Level" in principled.inputs:
        principled.inputs["Specular IOR Level"].default_value = 0.28
    elif "Specular" in principled.inputs:
        principled.inputs["Specular"].default_value = 0.28

    texture_coord = nodes.new("ShaderNodeTexCoord")

    # Crack network: Voronoi distance-to-edge is near zero on the cell borders,
    # so a narrow ramp running white->black turns those borders into a mask that
    # is 1 exactly on the seam. Running the ramp the other way lights the seams
    # and darkens the cells instead, which reads as reptile skin, not stone.
    crack = nodes.new("ShaderNodeTexVoronoi")
    crack.feature = "DISTANCE_TO_EDGE"
    crack.inputs["Scale"].default_value = float(material_profile["crack_scale"])
    crack_ramp = nodes.new("ShaderNodeValToRGB")
    crack_ramp.color_ramp.elements[0].position = 0.0
    crack_ramp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
    crack_ramp.color_ramp.elements[1].position = float(material_profile["crack_width"])
    crack_ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
    links.new(texture_coord.outputs["Object"], crack.inputs["Vector"])
    links.new(crack.outputs["Distance"], crack_ramp.inputs["Fac"])

    # A Voronoi covers the whole surface evenly, and an evenly cracked stone
    # looks manufactured. Gate the seams behind a low-frequency mask so parts of
    # the stone stay intact.
    unevenness = nodes.new("ShaderNodeTexNoise")
    unevenness.inputs["Scale"].default_value = float(material_profile["crack_unevenness_scale"])
    unevenness.inputs["Detail"].default_value = 2.0
    links.new(texture_coord.outputs["Object"], unevenness.inputs["Vector"])
    uneven_ramp = nodes.new("ShaderNodeValToRGB")
    uneven_ramp.color_ramp.elements[0].position = 0.36
    uneven_ramp.color_ramp.elements[1].position = 0.66
    links.new(unevenness.outputs["Fac"], uneven_ramp.inputs["Fac"])

    crack_active = nodes.new("ShaderNodeMath")
    crack_active.operation = "MULTIPLY"
    links.new(crack_ramp.outputs["Color"], crack_active.inputs[0])
    links.new(uneven_ramp.outputs["Color"], crack_active.inputs[1])

    darken_amount = nodes.new("ShaderNodeMath")
    darken_amount.operation = "MULTIPLY"
    darken_amount.inputs[1].default_value = float(material_profile["crack_darkening"])
    links.new(crack_active.outputs["Value"], darken_amount.inputs[0])

    darken = nodes.new("ShaderNodeMix")
    darken.data_type = "RGBA"
    darken.blend_type = "MULTIPLY"
    darken.inputs[6].default_value = base_linear
    darken.inputs[7].default_value = (0.24, 0.20, 0.17, 1.0)
    links.new(darken_amount.outputs["Value"], darken.inputs["Factor"])

    # Broad tonal blotches: real stone is not one flat colour under its cracks.
    blotch = nodes.new("ShaderNodeTexNoise")
    blotch.inputs["Scale"].default_value = float(material_profile["blotch_scale"])
    blotch.inputs["Detail"].default_value = 3.0
    links.new(texture_coord.outputs["Object"], blotch.inputs["Vector"])
    blotch_amount = nodes.new("ShaderNodeMath")
    blotch_amount.operation = "MULTIPLY"
    blotch_amount.inputs[1].default_value = float(material_profile["blotch_strength"])
    links.new(blotch.outputs["Fac"], blotch_amount.inputs[0])

    mottle = nodes.new("ShaderNodeMix")
    mottle.data_type = "RGBA"
    mottle.blend_type = "MIX"
    mottle.inputs[7].default_value = (
        min(1.0, base_linear[0] * 1.28),
        min(1.0, base_linear[1] * 1.2),
        min(1.0, base_linear[2] * 1.12),
        1.0,
    )
    links.new(darken.outputs[2], mottle.inputs[6])
    links.new(blotch_amount.outputs["Value"], mottle.inputs["Factor"])
    links.new(mottle.outputs[2], principled.inputs["Base Color"])

    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = float(material_profile["grain_scale"])
    grain.inputs["Detail"].default_value = 6.0
    grain.inputs["Roughness"].default_value = 0.55
    links.new(texture_coord.outputs["Object"], grain.inputs["Vector"])

    # A crack is a groove, so the seam must sit below the surface: feed the
    # inverted mask as height.
    crack_height = nodes.new("ShaderNodeMath")
    crack_height.operation = "SUBTRACT"
    crack_height.inputs[0].default_value = 1.0
    links.new(crack_active.outputs["Value"], crack_height.inputs[1])

    crack_bump = nodes.new("ShaderNodeBump")
    crack_bump.inputs["Strength"].default_value = float(material_profile["crack_bump"])
    crack_bump.inputs["Distance"].default_value = 0.02
    links.new(crack_height.outputs["Value"], crack_bump.inputs["Height"])

    grain_bump = nodes.new("ShaderNodeBump")
    grain_bump.inputs["Strength"].default_value = float(material_profile["grain_bump"])
    grain_bump.inputs["Distance"].default_value = 0.01
    links.new(grain.outputs["Fac"], grain_bump.inputs["Height"])
    links.new(crack_bump.outputs["Normal"], grain_bump.inputs["Normal"])
    links.new(grain_bump.outputs["Normal"], principled.inputs["Normal"])

    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return mat


# --- framing ---------------------------------------------------------------


def measure_framing(camera: bpy.types.Object, objects: list[bpy.types.Object], frame_size: int) -> dict:
    """Record world size, because the canonical camera refits every asset.

    Without this the proof sheet cannot show that a gravel lump is smaller than
    a broad slab: both fill the same fraction of their own frame.
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
    variation_profile = load_json(args.variation_profile)
    variant = find_variant(variation_profile, args.variant_id)
    geometry = variation_profile["geometry"]

    frame_size = int(bake_profile["frame_size"])
    yaw_degrees = float(variant["yaw_degrees"])
    sun_angle_degrees = float(bake_profile["lighting"]["sun_azimuth_degrees"])
    embed_fraction = float(variant["embed_fraction"])

    BAKE.clear_scene()
    rock = build_rock_object(variant, geometry)
    rock.data.materials.append(make_rock_material(variant, variation_profile["material"]))
    objects = [rock]

    # Slabs deliberately sink deeper than the shared tree limit allows, so the
    # generator carries its own ceiling instead of silently clamping to 0.22.
    BAKE.normalize_rock(
        objects,
        yaw_degrees,
        embed_fraction,
        float(geometry["max_embed_fraction"]),
    )

    corners = BAKE.all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(bake_profile["camera"]["target_z_fraction"])
    camera, _sun = BAKE.setup_render(frame_size, camera_target_z, sun_angle_degrees, bake_profile)
    anchor = BAKE.fit_camera_to_objects(camera, objects, bake_profile)
    framing = measure_framing(camera, objects, frame_size)

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    BAKE.render_png(out_dir / "albedo.png")

    snow_material = BAKE.make_snow_surface_material()
    previous_materials = BAKE.replace_materials(objects, snow_material)
    BAKE.render_png(out_dir / "snow_surface_raw.png")
    BAKE.restore_materials(objects, previous_materials)

    BAKE.setup_shadow_scene(objects, sun_angle_degrees, bake_profile)
    BAKE.render_png(out_dir / "shadow_raw.png")

    classification = {
        "source_glb": "",
        "source": "procedural",
        "meta_notes": "Procedural visual-only rock generated from a seed. No collision and no wind mask.",
        "variation_profile_id": variation_profile["profile_id"],
        "variation_profile_version": variation_profile["version"],
        "variant_id": variant["id"],
        "frame_width": frame_size,
        "frame_height": frame_size,
        "anchor": list(anchor),
        "yaw_degrees": yaw_degrees,
        "sun_angle_degrees": sun_angle_degrees,
        "root_embed_fraction": embed_fraction,
        "bake_profile": BAKE.bake_profile_summary(bake_profile, frame_size, sun_angle_degrees, embed_fraction),
        "runtime_plant_depth_px": 0,
        "layers": {
            "albedo": "albedo.png",
            "snow_surface_raw": "snow_surface_raw.png",
            "shadow_raw": "shadow_raw.png",
        },
        "notes": "Procedural small rock. Generated from seed, no source GLB. No wind mask is produced.",
    }
    with (out_dir / "classification.json").open("w", encoding="utf-8") as fh:
        json.dump(classification, fh, indent="\t", ensure_ascii=False)

    variation_record = {
        "profile_id": variation_profile["profile_id"],
        "version": variation_profile["version"],
        "variant": variant,
        "framing": framing,
    }
    with (out_dir / "variation.json").open("w", encoding="utf-8") as fh:
        json.dump(variation_record, fh, indent="\t", ensure_ascii=False)

    print(f"Wrote procedural rock render source for {variant['id']} to {out_dir}")


if __name__ == "__main__":
    main()
