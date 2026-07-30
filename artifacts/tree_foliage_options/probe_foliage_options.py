"""Exploration probe: bake the same rust crown tree with alternative foliage.

Nothing here is canon and nothing is written into the repo. The point is to see
how the tree reads with different leaf biology before deciding whether any of it
is worth a spec.

Two things are deliberately locked so the comparison is honest:

  * the burst RNG is isolated, so trunk, branches, roots and stubs come out
    bit-identical across every option - only the foliage differs;
  * the camera framing and the normalisation centre are taken from the baseline
    and reused, so a bigger crown looks bigger instead of being refitted back to
    the same apparent size the way the shipped per-asset bake would.

Run:
  blender --background --python probe_foliage_options.py -- --out-dir <dir>
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
import random
import sys
import zlib
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful")
TOOL_DIR = REPO / "tools" / "tree_atlas"
UP = Vector((0.0, 0.0, 1.0))
GRAVITY_ROLL_JITTER = math.radians(22.0)


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MOD = load_module(TOOL_DIR / "blender_rust_crown_tree_bake.py", "rust_crown_probe")
BAKE = MOD.BAKE
ORIGINAL_BLADE_MESH = MOD.blade_mesh
ORIGINAL_ADD_BURST = MOD.add_burst
ORIGINAL_AIM_MATRIX = MOD.aim_matrix


def gravity_aim_matrix(position: Vector, direction: Vector, roll: float) -> Matrix:
    """Aim a local-+Y blade along `direction`, local +Z as close to world up as possible.

    blade_mesh() bends the blade along its local -Z, but the canonical
    aim_matrix() then rolls it by a *random* angle about its own axis - so the
    bend points somewhere arbitrary and never reads as gravity. That is fine for
    a spiky burst, where the bend is just shape noise. It is fatal for any option
    whose identity IS the hang: a cascade, a frond, a sky-facing pad. Those need
    the one remaining degree of freedom resolved against world up instead of
    thrown away.
    """
    forward = Vector(direction).normalized()
    up_perp = UP - forward * UP.dot(forward)
    if up_perp.length < 1e-5:
        # Blade points straight up or down: every roll is equivalent.
        return ORIGINAL_AIM_MATRIX(position, direction, roll)
    z_axis = up_perp.normalized()
    x_axis = forward.cross(z_axis).normalized()
    basis = Matrix((
        (x_axis.x, forward.x, z_axis.x),
        (x_axis.y, forward.y, z_axis.y),
        (x_axis.z, forward.z, z_axis.z),
    )).to_4x4()
    # Keep a little residual roll so the crown is not combed flat. The incoming
    # random roll is reused as the jitter source, so the RNG stream is untouched.
    jitter = (roll / math.tau - 0.5) * 2.0 * GRAVITY_ROLL_JITTER
    return Matrix.Translation(position) @ (Quaternion(forward, jitter).to_matrix().to_4x4() @ basis)


# --- burst RNG isolation ---------------------------------------------------


def isolated_add_burst(parts, leaves, profile, rng, sun_to_light, center, axis, scale, blade_density, name):
    """Give every burst its own RNG so the crown never disturbs the trunk stream.

    grow_branch() interleaves branching with burst placement out of one RNG. A
    crown that draws a different number of samples therefore shifts every branch
    decision after it, and the "foliage comparison" would silently be comparing
    different trees.
    """
    seed = 990001 + (zlib.crc32(name.encode("utf-8")) & 0x7FFFFFFF)
    return ORIGINAL_ADD_BURST(
        parts, leaves, profile, random.Random(seed), sun_to_light,
        center, axis, scale, blade_density, name,
    )


# --- alternative blade geometry --------------------------------------------


def _append_strip(verts, faces, vertex_t, root, direction, blade_len, blade_hw,
                  t_root, t_tip, crease, droop, segments, width_profile):
    """Append one leaf strip growing from `root` along `direction`."""
    d = Vector(direction).normalized()
    perp = Vector((-d.y, d.x, 0.0))
    if perp.length < 1e-6:
        perp = Vector((1.0, 0.0, 0.0))
    perp.normalize()
    base = len(verts)
    for index in range(segments + 1):
        u = index / segments
        width = blade_hw * width_profile(u)
        point = root + d * (blade_len * u) + Vector((0.0, 0.0, -droop * blade_len * u * u))
        lift = crease * width
        t = t_root + (t_tip - t_root) * u
        verts.append(tuple(point - perp * width))
        verts.append(tuple(point + Vector((0.0, 0.0, lift))))
        verts.append(tuple(point + perp * width))
        vertex_t.extend((t, t, t))
    for index in range(segments):
        low = base + index * 3
        high = base + (index + 1) * 3
        faces.append((low, low + 1, high + 1, high))
        faces.append((low + 1, low + 2, high + 2, high + 1))


def _finish(name, verts, faces, vertex_t):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return mesh, vertex_t


def frond_mesh(name, length, half_width, droop, crease, segments):
    """A pinnate frond: a thin rachis carrying paired leaflets.

    Reads as fern/cycad rather than a broadleaf tree - the most alien of the
    options, and the one that cannot be reached by tuning the existing blade.
    """
    verts, faces, vertex_t = [], [], []
    rings = max(6, int(segments))
    rachis_hw = max(half_width * 0.14, 1e-5)
    _append_strip(
        verts, faces, vertex_t, Vector((0.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)),
        length, rachis_hw, 0.0, 1.0, crease, droop, rings,
        lambda u: max(0.35, 1.0 - 0.55 * u),
    )
    pairs = max(4, rings - 1)
    sweep = math.radians(38.0)
    for index in range(pairs):
        t = (index + 0.9) / (pairs + 0.5)
        base_y = length * t
        base_z = -droop * length * t * t
        leaflet_len = half_width * 2.4 * (1.0 - 0.5 * t)
        for side in (-1.0, 1.0):
            direction = Vector((side * math.cos(sweep), math.sin(sweep), 0.0))
            root = Vector((side * rachis_hw * 0.9, base_y, base_z))
            _append_strip(
                verts, faces, vertex_t, root, direction,
                leaflet_len, leaflet_len * 0.30,
                # The leaflet inherits the rachis colour where it attaches and
                # runs to the tip stop, so the hot ember stays on the edges.
                t * 0.75, min(1.0, t * 0.75 + 0.42),
                crease * 0.7, droop * 0.5, 2,
                lambda u: max(0.08, (1.0 - u) ** 0.6 * (0.45 + 0.55 * min(1.0, u * 3.0))),
            )
    return _finish(name, verts, faces, vertex_t)


def pad_mesh(name, length, half_width, droop, crease, segments):
    """A rounded pad on a short petiole - blunt tip instead of a spike."""
    verts, faces, vertex_t = [], [], []

    def profile(u):
        stalk = min(1.0, u * 5.0)
        body = max(0.0, 1.0 - (2.0 * u - 1.0) ** 4) ** 0.5
        return max(0.04, stalk * body)

    _append_strip(
        verts, faces, vertex_t, Vector((0.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)),
        length, half_width, 0.0, 1.0, crease, droop, max(6, int(segments)), profile,
    )
    return _finish(name, verts, faces, vertex_t)


# --- the options -----------------------------------------------------------

OPTIONS = [
    {
        "id": "a_current",
        "title": "A - текущий (колючие пучки)",
        "note": "как в репозитории сейчас",
        "crown": {},
    },
    {
        "id": "b_broadleaf",
        "title": "B - широкий лист",
        "note": "меньше листьев, каждый крупнее; крона плотнее и мягче",
        "crown": {
            "blades": [9, 14],
            "blade_length": [0.030, 0.052],
            "blade_half_width": [0.026, 0.042],
            "blade_droop": [0.15, 0.55],
            "blade_crease": [0.22, 0.50],
            "blade_segments": 5,
            "spread_degrees": [95, 150],
            "length_jitter": [0.85, 1.15],
        },
    },
    {
        "id": "c_weeping",
        "title": "C - плакучая (каскад)",
        "note": "длинные узкие листья, провис по гравитации — крона течёт вниз",
        "gravity": True,
        "crown": {
            "blades": [24, 36],
            "blade_length": [0.060, 0.115],
            "blade_half_width": [0.006, 0.012],
            "blade_droop": [0.95, 1.80],
            "blade_crease": [0.50, 0.95],
            "blade_segments": 6,
            "spread_degrees": [105, 165],
            "outward_bias": [0.50, 0.85],
        },
    },
    {
        "id": "d_needle",
        "title": "D - хвойная щётка",
        "note": "много тонких коротких игл, узкий конус — плотные кисти",
        "crown": {
            "blades": [55, 82],
            "blade_length": [0.022, 0.042],
            "blade_half_width": [0.0032, 0.0062],
            "blade_droop": [0.0, 0.25],
            "blade_crease": [0.60, 1.05],
            "blade_segments": 3,
            "spread_degrees": [45, 88],
            "outward_bias": [0.12, 0.40],
        },
    },
    {
        "id": "e_frond",
        "title": "E - перистая вайя",
        "note": "новая геометрия: рахис с парными листочками (папоротник/цикас)",
        "gravity": True,
        "crown": {
            "blades": [5, 8],
            "blade_length": [0.055, 0.098],
            "blade_half_width": [0.013, 0.023],
            "blade_droop": [0.35, 0.85],
            "blade_crease": [0.30, 0.60],
            "blade_segments": 7,
            "spread_degrees": [70, 132],
            "outward_bias": [0.35, 0.70],
        },
        "mesh": frond_mesh,
    },
    {
        "id": "f_ribbon",
        "title": "F - ленты",
        "note": "немного очень длинных широких лент, сильная складка — водоросль",
        "gravity": True,
        "crown": {
            "blades": [7, 11],
            "blade_length": [0.075, 0.140],
            "blade_half_width": [0.016, 0.030],
            "blade_droop": [0.55, 1.15],
            "blade_crease": [0.70, 1.25],
            "blade_segments": 7,
            "spread_degrees": [85, 145],
        },
    },
    {
        "id": "g_pad",
        "title": "G - округлые пластины",
        "note": "новая геометрия: тупой округлый лист, развёрнут к небу",
        "gravity": True,
        "crown": {
            "blades": [6, 10],
            "blade_length": [0.032, 0.058],
            "blade_half_width": [0.024, 0.042],
            "blade_droop": [0.10, 0.45],
            "blade_crease": [0.12, 0.38],
            "blade_segments": 6,
            "spread_degrees": [88, 150],
        },
        "mesh": pad_mesh,
    },
]


# --- framing helpers -------------------------------------------------------


def compute_center(objects, embed_fraction, max_embed) -> Vector:
    corners = BAKE.all_world_corners(objects)
    min_x = min(c.x for c in corners)
    max_x = max(c.x for c in corners)
    min_y = min(c.y for c in corners)
    max_y = max(c.y for c in corners)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    root_z = min_z + (max_z - min_z) * max(0.0, min(embed_fraction, max_embed))
    return Vector(((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, root_z))


def normalize_with_center(objects, yaw_degrees: float, center: Vector) -> None:
    root = bpy.data.objects.new("TreeRoot", None)
    bpy.context.collection.objects.link(root)
    root.rotation_euler[2] = math.radians(yaw_degrees)
    for obj in objects:
        obj.parent = root
        obj.location -= center
    bpy.context.view_layer.update()


def main() -> None:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--variant-id", default="var_01")
    parser.add_argument("--headroom", type=float, default=1.18)
    args = parser.parse_args(argv)

    bake_profile = MOD.load_json(TOOL_DIR / "layered_asset_bake_profile.json")
    tree_profile = MOD.load_json(TOOL_DIR / "rust_crown_tree_profiles.json")
    variant = MOD.find_variant(tree_profile, args.variant_id)

    camera_fit = dict(tree_profile.get("camera_fit", {}))
    camera_fit.update(variant.get("camera_fit", {}))
    if camera_fit:
        bake_profile = {**bake_profile, "camera": {**bake_profile["camera"], **camera_fit}}
    lighting_override = dict(tree_profile.get("lighting", {}))
    bounce_override = dict(lighting_override.pop("bounce", {}))
    if lighting_override or bounce_override:
        lighting = {**bake_profile["lighting"], **lighting_override}
        if bounce_override:
            lighting["bounce"] = {**bake_profile["lighting"]["bounce"], **bounce_override}
        bake_profile = {**bake_profile, "lighting": lighting}

    frame_size = int(bake_profile["frame_size"])
    yaw = float(variant.get("yaw_degrees", bake_profile["orientation"]["default_yaw_degrees"]))
    sun_angle = float(bake_profile["lighting"]["sun_azimuth_degrees"])
    embed = float(variant.get("embed_fraction", bake_profile["planting"]["root_embed_fraction"]))
    max_embed = float(bake_profile["planting"]["max_root_embed_fraction"])

    sun_ray = Vector((0.0, 0.0, -1.0))
    sun_ray.rotate(MOD.Euler((
        math.radians(float(bake_profile["lighting"]["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(sun_angle),
    )))
    sun_to_light = -sun_ray

    MOD.add_burst = isolated_add_burst

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    locked = {}
    records = []

    for option in OPTIONS:
        profile = copy.deepcopy(tree_profile)
        profile["geometry"]["crown"].update(option["crown"])
        MOD.blade_mesh = option.get("mesh") or ORIGINAL_BLADE_MESH
        MOD.aim_matrix = gravity_aim_matrix if option.get("gravity") else ORIGINAL_AIM_MATRIX

        BAKE.clear_scene()
        MOD._MATERIAL_CACHE.clear()
        parts = MOD.create_tree(variant, profile, sun_to_light)
        objects = [obj for obj, _layer in parts]

        if "center" not in locked:
            locked["center"] = compute_center(objects, embed, max_embed)
        normalize_with_center(objects, yaw, locked["center"])

        classification = {obj.name: {"layer": layer} for obj, layer in parts}

        if "target_z" not in locked:
            corners = BAKE.all_world_corners(objects)
            min_z = min(c.z for c in corners)
            max_z = max(c.z for c in corners)
            locked["target_z"] = min_z + (max_z - min_z) * float(bake_profile["camera"]["target_z_fraction"])

        camera, _sun = BAKE.setup_render(frame_size, locked["target_z"], sun_angle, bake_profile)
        if "ortho" not in locked:
            BAKE.fit_camera_to_objects(camera, objects, bake_profile)
            locked["ortho"] = camera.data.ortho_scale * float(args.headroom)
        camera.data.ortho_scale = locked["ortho"]
        bpy.context.view_layer.update()

        BAKE.set_layer_visibility(objects, classification, "all")
        BAKE.render_png(out_dir / f"{option['id']}.png")

        corners = BAKE.all_world_corners(objects)
        records.append({
            "id": option["id"],
            "title": option["title"],
            "note": option["note"],
            "crown_patch": option["crown"],
            "custom_mesh": bool(option.get("mesh")),
            "gravity_aligned": bool(option.get("gravity")),
            "foliage_parts": sum(1 for _o, layer in parts if layer == "foliage"),
            "trunk_parts": sum(1 for _o, layer in parts if layer == "trunk"),
            "world_width": max(c.x for c in corners) - min(c.x for c in corners),
            "world_height": max(c.z for c in corners) - min(c.z for c in corners),
        })
        print(f"[probe] {option['id']}: {records[-1]['foliage_parts']} foliage parts")

    with (out_dir / "options.json").open("w", encoding="utf-8") as fh:
        json.dump({
            "variant": variant["id"],
            "seed": variant["seed"],
            "locked_ortho_scale": locked["ortho"],
            "frame_size": frame_size,
            "options": records,
        }, fh, indent="\t", ensure_ascii=False)
    print(f"[probe] wrote {len(records)} options to {out_dir}")


if __name__ == "__main__":
    main()
