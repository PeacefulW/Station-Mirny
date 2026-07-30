"""Exploration probe: carry foliage on the trunk, not only in the crown fork.

The reference frame the user supplied has a dominant curving trunk with several
discrete leaf clumps stepping *down* it on short lateral branches, plus a few
bare snapped twigs. The shipped generator puts every leaf above the fork, so the
tree always reads as one candelabra with a hat.

This probe adds a lateral pass: short branches launched off the trunk strands at
chosen heights, each ending in its own clump. Nothing here is canon.

Run:
  blender --background --python probe_branch_structure.py -- --out-dir <dir>
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
from mathutils import Quaternion, Vector

REPO = Path(r"C:\Users\peaceful\Station Peaceful\Station Peaceful")
TOOL_DIR = REPO / "tools" / "tree_atlas"
UP = Vector((0.0, 0.0, 1.0))


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MOD = load_module(TOOL_DIR / "blender_rust_crown_tree_bake.py", "rust_crown_branch_probe")
BAKE = MOD.BAKE
ORIGINAL_ADD_BURST = MOD.add_burst


def isolated_add_burst(parts, leaves, profile, rng, sun_to_light, center, axis, scale, blade_density, name):
    """Bursts draw from their own RNG so the trunk is identical in every option."""
    seed = 990001 + (zlib.crc32(name.encode("utf-8")) & 0x7FFFFFFF)
    return ORIGINAL_ADD_BURST(
        parts, leaves, profile, random.Random(seed), sun_to_light,
        center, axis, scale, blade_density, name,
    )


# --- the lateral pass ------------------------------------------------------


def trunk_centres(strand_paths) -> list[Vector]:
    """The braid's own axis, recovered by averaging the strands ring by ring."""
    rings = len(strand_paths[0][0])
    centres: list[Vector] = []
    for ring in range(rings):
        total = Vector((0.0, 0.0, 0.0))
        for points, _radii, _azimuth in strand_paths:
            total += points[ring]
        centres.append(total / len(strand_paths))
    return centres


def pick_launch(strand_paths, centres, ring: int, want_sign: float, screen_bias: float):
    """Choose the strand whose outward normal best faces the camera plane.

    The bake camera looks down +Y and the asset is yawed 90 degrees at
    normalisation, so a lateral pointing along local +/-Y is what ends up
    horizontal on screen. A lateral that happens to point at the camera
    foreshortens to nothing, and the option would look broken for a reason that
    has nothing to do with the option. Biasing the azimuth toward the screen
    plane is a probe-side readability rule, not a claim about the species.
    """
    best = None
    for points, radii, _azimuth in strand_paths:
        radial = points[ring] - centres[ring]
        radial.z = 0.0
        if radial.length < 1e-6:
            continue
        radial.normalize()
        score = radial.y * want_sign
        if best is None or score > best[0]:
            best = (score, points[ring], radii[ring], radial)
    if best is None:
        return None
    _score, origin, radius, radial = best
    target = Vector((0.0, want_sign, 0.0))
    biased = radial.lerp(target, screen_bias)
    if biased.length < 1e-6:
        biased = target
    return origin, radius, biased.normalized()


def add_bare_stub(parts, profile, rng, origin: Vector, direction: Vector, length: float, radius: float, name: str):
    """A snapped, leafless branch - the reference is full of them."""
    points = MOD.branch_points(origin, direction, length, math.radians(rng.uniform(8.0, 30.0)),
                               math.radians(6.0), rng.uniform(0.0, 0.15), 4, rng)
    radii = [radius * (1.0 - 0.78 * index / 4) for index in range(5)]
    mesh, vertex_t = MOD.tube_mesh(name, points, radii, 6,
                                   MOD.relief_settings(rng, profile["geometry"]["branching"].get("relief"), 0.5))
    stub = MOD.link_object(name, mesh)
    start, end = MOD.bark_progress_range(profile, 2)
    MOD.paint_bark(stub, profile, vertex_t, rng.randrange(len(profile["palette"]["shade_tiers"])),
                   ramp_start=start, ramp_end=end)
    parts.append((stub, "trunk"))


def add_trunk_laterals(parts, leaves, profile, variant, sun_to_light, strand_paths, trunk_length, settings):
    """Launch short foliage-bearing branches off the trunk at chosen heights."""
    rng = random.Random(int(settings.get("seed", 4242)))
    centres = trunk_centres(strand_paths)
    rings = len(centres)
    screen_bias = float(settings.get("screen_bias", 0.55))
    levels = int(profile["geometry"]["branching"]["levels"])

    for index, spec in enumerate(settings["laterals"]):
        height = float(spec["height"])
        ring = max(1, min(rings - 2, int(round(height * (rings - 1)))))
        want_sign = 1.0 if index % 2 == 0 else -1.0
        picked = pick_launch(strand_paths, centres, ring, want_sign, screen_bias)
        if picked is None:
            continue
        origin, strand_radius, radial = picked

        uplift = float(spec.get("uplift", 0.45))
        direction = radial.lerp(UP, uplift)
        if direction.length < 1e-6:
            direction = UP.copy()
        direction.normalize()
        # A little roll off the pure radial so the laterals are not all coplanar.
        jitter_axis = radial.cross(UP)
        if jitter_axis.length > 1e-6:
            direction.rotate(Quaternion(jitter_axis.normalized(), math.radians(rng.gauss(0.0, 7.0))))

        length = trunk_length * float(spec["length_fraction"])
        radius = strand_radius * float(spec.get("radius_fraction", 0.42))
        MOD.grow_branch(
            parts, leaves, profile, variant, rng, sun_to_light,
            origin, direction, length, radius,
            max(1, levels - int(spec.get("depth", 2))),
            f"lateral{index}",
        )

    for index, spec in enumerate(settings.get("stubs", [])):
        height = float(spec["height"])
        ring = max(1, min(rings - 2, int(round(height * (rings - 1)))))
        # Stubs alternate opposite to the laterals, and lean harder into the
        # screen plane: a bare twig is thin, so one pointing at the camera is
        # simply invisible and the option cannot be judged.
        want_sign = 1.0 if index % 2 else -1.0
        picked = pick_launch(strand_paths, centres, ring, want_sign, min(1.0, screen_bias + 0.3))
        if picked is None:
            continue
        origin, strand_radius, radial = picked
        direction = radial.lerp(UP, float(spec.get("uplift", 0.25))).normalized()
        add_bare_stub(
            parts, profile, rng, origin, direction,
            trunk_length * float(spec["length_fraction"]),
            strand_radius * float(spec.get("radius_fraction", 0.34)),
            f"rust_crown_stub{index}",
        )


def create_tree_with_laterals(variant, profile, sun_to_light, settings):
    """create_tree() with a lateral pass inserted; the trunk path is untouched."""
    rng = random.Random(int(variant["seed"]))
    geometry = profile["geometry"]
    trunk_settings = geometry["trunk"]
    world_scale = float(variant.get("world_scale", 1.0))
    height_scale = float(variant.get("height_scale", 1.0))

    parts: list = []
    leaves: list = []
    base_radius = MOD.uniform_pair(rng, trunk_settings["base_radius"]) * world_scale
    lean = math.radians(MOD.uniform_pair(rng, trunk_settings["lean_degrees"]))
    lean_azimuth = rng.uniform(0.0, math.tau)
    direction = Vector((
        math.cos(lean_azimuth) * math.sin(lean),
        math.sin(lean_azimuth) * math.sin(lean),
        math.cos(lean),
    ))
    trunk_length = MOD.uniform_pair(rng, trunk_settings["height"]) * world_scale * height_scale

    launches, strand_paths = MOD.grow_trunk(
        parts, profile, rng, Vector((0.0, 0.0, -base_radius * 0.6)),
        direction, trunk_length, base_radius,
    )
    MOD.add_root_fibers(parts, profile, rng, strand_paths, world_scale)

    if settings.get("laterals"):
        add_trunk_laterals(
            parts, leaves, profile, variant, sun_to_light,
            strand_paths, trunk_length, settings,
        )

    branching = geometry["branching"]
    spread = math.radians(MOD.uniform_pair(rng, trunk_settings["braid"]["strand_spread_degrees"]))
    for index, launch in enumerate(launches):
        position = launch["position"]
        entry_direction = launch["entry_direction"]
        branch_direction = launch["branch_direction"]
        tip_radius = float(launch["radius"])
        azimuth = float(launch["azimuth"])
        bend_axis = MOD.perpendicular(branch_direction)
        bend_axis.rotate(Quaternion(branch_direction, azimuth))
        launch_direction = branch_direction.copy()
        launch_direction.rotate(Quaternion(bend_axis, spread))
        MOD.grow_branch(
            parts, leaves, profile, variant, rng, sun_to_light,
            position, launch_direction,
            trunk_length * MOD.uniform_pair(rng, branching["length_fraction"]),
            tip_radius, 1, f"branch{index}",
            int(launch["tier_index"]), entry_direction, launch["cords"],
        )

    MOD.paint_leaves(leaves, profile, rng)
    bpy.context.view_layer.update()
    return parts


# --- options ---------------------------------------------------------------

def steps(heights, length_fractions, uplifts, depth=2):
    return [
        {"height": h, "length_fraction": l, "uplift": u, "depth": depth}
        for h, l, u in zip(heights, length_fractions, uplifts)
    ]


## The root flare eats the bottom of the strand path and the braid starts
## opening into the fork at 0.58, so a lateral below ~0.4 grows straight out of
## the root mass and one above ~0.85 is already crown. 0.42-0.82 is the band
## where a lateral reads as coming off a trunk.
BAND = [0.42, 0.55, 0.68, 0.80]
BAND_LENGTHS = [0.44, 0.38, 0.32, 0.27]
BAND_UPLIFTS = [0.30, 0.38, 0.46, 0.54]
STUBS = [
    {"height": 0.36, "length_fraction": 0.22, "uplift": 0.18},
    {"height": 0.61, "length_fraction": 0.19, "uplift": 0.30},
    {"height": 0.74, "length_fraction": 0.17, "uplift": 0.14},
]

## The reference tree is roughly 60% trunk / 40% crown. The shipped profile is
## the other way round, which is why laterals alone cannot reach that read: there
## is barely any bare trunk to hang them on. These options lengthen the trunk,
## and are the only ones whose trunk is NOT identical to the baseline.
TALL_TRUNK = {"geometry.trunk.height": [0.40, 0.52]}

OPTIONS = [
    {
        "id": "s0_baseline",
        "title": "S0 - как сейчас",
        "note": "вся листва только над развилкой",
        "settings": {},
        "profile": {},
    },
    {
        "id": "s1_two_low",
        "title": "S1 - две низкие ветки",
        "note": "две длинные боковые по разные стороны, ниже развилки",
        "settings": {
            "laterals": steps([0.44, 0.64], [0.48, 0.40], [0.32, 0.44]),
        },
        "profile": {},
    },
    {
        "id": "s2_stepped",
        "title": "S2 - ступенями",
        "note": "четыре боковые 0.42→0.80, чередуются стороны, короче к верху",
        "settings": {"laterals": steps(BAND, BAND_LENGTHS, BAND_UPLIFTS)},
        "profile": {},
    },
    {
        "id": "s3_many_short",
        "title": "S3 - много коротких",
        "note": "семь коротких боковых с мелкими клумпами по всему стволу",
        "settings": {
            "laterals": steps(
                [0.38, 0.46, 0.54, 0.62, 0.70, 0.77, 0.84],
                [0.30, 0.26, 0.28, 0.24, 0.26, 0.22, 0.19],
                [0.30, 0.38, 0.34, 0.46, 0.42, 0.52, 0.56],
                depth=1,
            ),
        },
        "profile": {},
    },
    {
        "id": "s4_stepped_stubs",
        "title": "S4 - ступени + голые сучья",
        "note": "S2 плюс три обломанных сучка без листвы, как на референсе",
        "settings": {"laterals": steps(BAND, BAND_LENGTHS, BAND_UPLIFTS), "stubs": STUBS},
        "profile": {},
    },
    {
        "id": "s5_tall_trunk",
        "title": "S5 - высокий ствол + ступени",
        "note": "ствол в 1.7 раза длиннее — пропорция ближе к референсу",
        "settings": {"laterals": steps(BAND, BAND_LENGTHS, BAND_UPLIFTS), "stubs": STUBS},
        "profile": dict(TALL_TRUNK),
    },
    {
        "id": "s6_tall_small_top",
        "title": "S6 - высокий ствол + сжатая верхушка",
        "note": "S5, но верхние ветки короче — ствол доминирует, крона стала одной из клумп",
        "settings": {"laterals": steps(BAND, BAND_LENGTHS, BAND_UPLIFTS), "stubs": STUBS},
        "profile": {**TALL_TRUNK, "geometry.branching.length_fraction": [0.44, 0.58]},
    },
]


def patch_profile(profile: dict, patches: dict) -> dict:
    for dotted, value in patches.items():
        node = profile
        keys = dotted.split(".")
        for key in keys[:-1]:
            node = node[key]
        node[keys[-1]] = value
    return profile


def compute_center(objects, embed_fraction, max_embed) -> Vector:
    corners = BAKE.all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    return Vector((
        (min(c.x for c in corners) + max(c.x for c in corners)) * 0.5,
        (min(c.y for c in corners) + max(c.y for c in corners)) * 0.5,
        min_z + (max_z - min_z) * max(0.0, min(embed_fraction, max_embed)),
    ))


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
    parser.add_argument("--headroom", type=float, default=1.12)
    # One shared frame for every panel, sized on the option that needs the most
    # room. Fitting on the baseline crops the tall-trunk options at the top, and
    # refitting per option would hide the very proportion change they exist to
    # show. The centre still comes from the baseline, so all seven stand on the
    # same ground line.
    parser.add_argument("--fit-from", default="s5_tall_trunk")
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
        0.0, math.radians(sun_angle),
    )))
    sun_to_light = -sun_ray

    MOD.add_burst = isolated_add_burst

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    locked: dict = {}
    records = []

    # Framing pass: baseline fixes the ground line, --fit-from fixes the zoom.
    for source_id in (OPTIONS[0]["id"], args.fit_from):
        source = next(o for o in OPTIONS if o["id"] == source_id)
        BAKE.clear_scene()
        MOD._MATERIAL_CACHE.clear()
        parts = create_tree_with_laterals(
            variant, patch_profile(copy.deepcopy(tree_profile), source["profile"]),
            sun_to_light, source["settings"],
        )
        objects = [obj for obj, _layer in parts]
        if "center" not in locked:
            locked["center"] = compute_center(objects, embed, max_embed)
        normalize_with_center(objects, yaw, locked["center"])
        if source_id != args.fit_from:
            continue
        corners = BAKE.all_world_corners(objects)
        min_z = min(c.z for c in corners)
        max_z = max(c.z for c in corners)
        locked["target_z"] = min_z + (max_z - min_z) * float(bake_profile["camera"]["target_z_fraction"])
        camera, _sun = BAKE.setup_render(frame_size, locked["target_z"], sun_angle, bake_profile)
        BAKE.fit_camera_to_objects(camera, objects, bake_profile)
        locked["ortho"] = camera.data.ortho_scale * float(args.headroom)
        print(f"[probe] framing locked on {args.fit_from}: ortho {locked['ortho']:.4f}")

    for option in OPTIONS:
        profile = patch_profile(copy.deepcopy(tree_profile), option["profile"])

        BAKE.clear_scene()
        MOD._MATERIAL_CACHE.clear()
        parts = create_tree_with_laterals(variant, profile, sun_to_light, option["settings"])
        objects = [obj for obj, _layer in parts]

        normalize_with_center(objects, yaw, locked["center"])
        classification = {obj.name: {"layer": layer} for obj, layer in parts}

        camera, _sun = BAKE.setup_render(frame_size, locked["target_z"], sun_angle, bake_profile)
        camera.data.ortho_scale = locked["ortho"]
        bpy.context.view_layer.update()

        BAKE.set_layer_visibility(objects, classification, "all")
        BAKE.render_png(out_dir / f"{option['id']}.png")

        records.append({
            "id": option["id"],
            "title": option["title"],
            "note": option["note"],
            "laterals": len(option["settings"].get("laterals", [])),
            "stubs": len(option["settings"].get("stubs", [])),
            "profile_patch": option["profile"],
            "trunk_matches_baseline": not option["profile"],
            "foliage_parts": sum(1 for _o, layer in parts if layer == "foliage"),
            "trunk_parts": sum(1 for _o, layer in parts if layer == "trunk"),
        })
        print(f"[probe] {option['id']}: {records[-1]['trunk_parts']} trunk / {records[-1]['foliage_parts']} foliage")

    with (out_dir / "options.json").open("w", encoding="utf-8") as fh:
        json.dump({
            "variant": variant["id"],
            "seed": variant["seed"],
            "locked_ortho_scale": locked["ortho"],
            "options": records,
        }, fh, indent="\t", ensure_ascii=False)
    print(f"[probe] wrote {len(records)} options to {out_dir}")


if __name__ == "__main__":
    main()
