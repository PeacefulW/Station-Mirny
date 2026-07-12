"""Render procedural Blender grass tuft frames for the atlas prototype.

Follows the layered tree bake recipe: an ORTHO camera looking down at the
tuft from the tree-family elevation, roots scattered in depth on uneven
soil (no ruler-flat baseline), a Cycles shadow-catcher pass with the selected
10:00 Sun so ground shadows land screen east-south-east like the trees.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


DEFAULT_PROFILE_PATH = Path(__file__).with_name("grass_tuft_bake_profile.json")
DEFAULT_SEED = 981237


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument(
        "--frame-list",
        type=str,
        default="",
        help="Comma-separated frame indices for a partial smoke bake.",
    )
    parser.add_argument(
        "--override-json",
        type=str,
        default="",
        help="JSON object deep-merged over the profile (variant exploration).",
    )
    parser.add_argument(
        "--write-self-shadow-reference",
        action="store_true",
        help="Also render each albedo frame with Sun shadowing disabled for strict self-shadow comparison.",
    )
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    return parser.parse_args(argv)


def deep_merge(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_profile(path: Path, override_json: str) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        profile = json.load(fh)
    if override_json:
        profile = deep_merge(profile, json.loads(override_json))
    return profile


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.lights,
        bpy.data.cameras,
    ):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def set_render_engine(scene: bpy.types.Scene, requested_engine: str) -> None:
    for engine in (requested_engine, "BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            return
        except TypeError:
            continue
    raise RuntimeError("No supported Blender render engine found.")


def set_view_setting(settings: bpy.types.ColorManagedViewSettings, attr: str, values: tuple[str, ...]) -> None:
    for value in values:
        try:
            setattr(settings, attr, value)
            return
        except TypeError:
            continue
    raise RuntimeError(f"No supported Blender color-management value found for {attr}: {values}")


def configure_albedo_render(scene: bpy.types.Scene, profile: dict) -> None:
    atlas = profile["atlas"]
    render_profile = profile["render"]

    set_render_engine(scene, str(render_profile.get("engine", render_profile.get("albedo_engine", "BLENDER_EEVEE_NEXT"))))
    scene.render.resolution_x = int(atlas["frame_width"])
    scene.render.resolution_y = int(atlas["frame_height"])
    scene.render.film_transparent = bool(render_profile["transparent_film"])
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = str(render_profile["color_mode"])
    set_view_setting(scene.view_settings, "view_transform", (str(render_profile["view_transform"]), "Standard", "Filmic"))
    set_view_setting(scene.view_settings, "look", (str(render_profile["look"]), "None", "Medium High Contrast"))
    scene.view_settings.exposure = float(render_profile["exposure"])
    scene.view_settings.gamma = float(render_profile["gamma"])
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = int(render_profile["samples"])


def configure_albedo_lighting(scene: bpy.types.Scene, profile: dict) -> None:
    lighting = profile["lighting"]
    for obj in scene.objects:
        if obj.type != "LIGHT":
            continue
        obj.hide_render = False
        obj.hide_viewport = False
        if obj.name.startswith("GrassTuftSun"):
            obj.rotation_euler = (
                math.radians(float(lighting["albedo_sun_elevation_degrees"])),
                0.0,
                math.radians(float(lighting["sun_azimuth_degrees"])),
            )
            obj.data.energy = float(lighting["albedo_sun_energy"])
            if hasattr(obj.data, "angle"):
                obj.data.angle = math.radians(float(lighting.get("albedo_sun_angular_diameter_degrees", 4.0)))
        elif obj.name.startswith("GrassTuftFill"):
            obj.data.energy = float(lighting["fill_energy"])
        elif obj.name.startswith("GrassTuftLowOppositeKicker"):
            obj.hide_render = False
            obj.data.energy = float(lighting["low_opposite_kicker"]["energy"])


def place_camera_anchor(camera: bpy.types.Object, profile: dict) -> None:
    """Slide the camera in its view plane so the tuft root center (world
    origin) lands on the profile anchor fractions. Analytic for ORTHO, but
    iterate twice to absorb any update ordering quirks."""
    scene = bpy.context.scene
    camera_profile = profile["camera"]
    atlas = profile["atlas"]
    width_units = float(camera_profile["ortho_scale"])
    height_units = width_units * int(atlas["frame_height"]) / int(atlas["frame_width"])
    target_u = float(camera_profile["anchor_x_fraction"])
    # anchor_y_fraction is measured from the frame top; camera view v runs bottom-up.
    target_v = 1.0 - float(camera_profile["anchor_y_fraction"])
    for _ in range(2):
        bpy.context.view_layer.update()
        uv = world_to_camera_view(scene, camera, Vector((0.0, 0.0, 0.0)))
        right = Vector(camera.matrix_world.col[0][:3]).normalized()
        up = Vector(camera.matrix_world.col[1][:3]).normalized()
        camera.location += right * ((uv.x - target_u) * width_units)
        camera.location += up * ((uv.y - target_v) * height_units)
    bpy.context.view_layer.update()


def setup_scene(profile: dict) -> bpy.types.Object:
    scene = bpy.context.scene
    camera_profile = profile["camera"]
    lighting = profile["lighting"]

    configure_albedo_render(scene, profile)

    camera_data = bpy.data.cameras.new("GrassTuftCamera")
    camera = bpy.data.objects.new("GrassTuftCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = str(camera_profile["type"])
    camera.data.ortho_scale = float(camera_profile["ortho_scale"])
    elevation = math.radians(float(camera_profile["elevation_degrees"]))
    distance = float(camera_profile["distance"])
    camera.location = Vector((0.0, -distance * math.cos(elevation), distance * math.sin(elevation)))
    look_at(camera, Vector((0.0, 0.0, 0.0)))
    place_camera_anchor(camera, profile)

    sun_data = bpy.data.lights.new("GrassTuftSun", "SUN")
    sun_data.use_shadow = True
    sun = bpy.data.objects.new("GrassTuftSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.data.energy = float(lighting["albedo_sun_energy"])
    sun.rotation_euler = (
        math.radians(float(lighting["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(float(lighting["sun_azimuth_degrees"])),
    )

    kicker_profile = lighting.get("low_opposite_kicker", {})
    if bool(kicker_profile.get("enabled", False)):
        tuft_profile = profile["tuft"]
        height = max(
            float(tuft_profile["height_max"]) + float(tuft_profile.get("biofield_extra_height", 0.0)),
            0.001,
        )
        spot_data = bpy.data.lights.new("GrassTuftLowOppositeKicker", "SPOT")
        spot = bpy.data.objects.new("GrassTuftLowOppositeKicker", spot_data)
        bpy.context.collection.objects.link(spot)
        spot.location = Vector((
            float(kicker_profile["position_x"]),
            float(kicker_profile["position_y"]),
            height * float(kicker_profile["height_fraction"]),
        ))
        look_at(spot, Vector((0.0, 0.0, height * float(kicker_profile["target_height_fraction"]))))
        spot.data.energy = float(kicker_profile["energy"])
        color = kicker_profile["color"]
        spot.data.color = (float(color[0]), float(color[1]), float(color[2]))
        spot.data.spot_size = math.radians(float(kicker_profile["spot_size_degrees"]))
        spot.data.spot_blend = float(kicker_profile["spot_blend"])
        spot.data.use_shadow = bool(kicker_profile["use_shadow"])
    configure_albedo_lighting(scene, profile)
    return camera


_MATERIAL_CACHE: dict[tuple, bpy.types.Material] = {}


def make_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = None
    for node in mat.node_tree.nodes:
        if node.bl_idname == "ShaderNodeBsdfPrincipled":
            bsdf = node
            break
    if bsdf:
        base_color = bsdf.inputs.get("Base Color")
        if base_color is None:
            base_color = next((socket for socket in bsdf.inputs if socket.type == "RGBA"), None)
        roughness = bsdf.inputs.get("Roughness")
        if roughness is None:
            roughness = next(
                (
                    socket
                    for socket in bsdf.inputs
                    if "roughness" in socket.name.lower() or "roughness" in socket.identifier.lower()
                ),
                None,
            )
        if base_color:
            base_color.default_value = color
        if roughness:
            roughness.default_value = 0.78
    return mat


def color_from_rgb(rgb: list[int]) -> tuple[float, float, float, float]:
    return (
        max(0.0, min(1.0, float(rgb[0]) / 255.0)),
        max(0.0, min(1.0, float(rgb[1]) / 255.0)),
        max(0.0, min(1.0, float(rgb[2]) / 255.0)),
        1.0,
    )


def lerp_color(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
    amount: float,
) -> tuple[float, float, float, float]:
    t = max(0.0, min(1.0, amount))
    return tuple(left[index] * (1.0 - t) + right[index] * t for index in range(4))


def ramp_color(
    ramp: dict[str, list[int]],
    amount: float,
) -> tuple[float, float, float, float]:
    root = color_from_rgb(ramp["root"])
    mid = color_from_rgb(ramp["mid"])
    tip = color_from_rgb(ramp["tip"])
    if amount <= 0.5:
        return lerp_color(root, mid, amount / 0.5)
    return lerp_color(mid, tip, (amount - 0.5) / 0.5)


def shaded_segment_material(
    profile: dict,
    palette_key: str,
    ramp_index: int,
    tier_index: int,
    segment: int,
    segments: int,
) -> bpy.types.Material:
    key = (palette_key, ramp_index, tier_index, segment)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    tier = float(profile["tuft"]["shade_tiers"][tier_index])
    amount = segment / max(segments - 1, 1)
    base = ramp_color(profile["palette"][palette_key][ramp_index], amount)
    color = (base[0] * tier, base[1] * tier, base[2] * tier, 1.0)
    mat = make_material(f"grass_{palette_key}_{ramp_index}_t{tier_index}_s{segment}", color)
    _MATERIAL_CACHE[key] = mat
    return mat


def bloom_material(profile: dict, index: int) -> bpy.types.Material:
    key = ("bloom", index)
    cached = _MATERIAL_CACHE.get(key)
    if cached is not None:
        return cached
    mat = make_material(f"grass_bloom_{index}", color_from_rgb(profile["palette"]["bloom_rgb"][index]))
    _MATERIAL_CACHE[key] = mat
    return mat


def blade_mesh(
    name: str,
    root: Vector,
    height: float,
    lean_x: float,
    lean_y: float,
    width: float,
    bow: float,
    droop: float,
    yaw: float,
    segments: int,
) -> bpy.types.Mesh:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    axis_x = math.cos(yaw)
    axis_y = math.sin(yaw) * 0.55
    reach_sign = 1.0 if lean_x >= 0.0 else -1.0
    for i in range(segments + 1):
        t = i / segments
        x = root.x + lean_x * t + bow * math.sin(t * math.pi) + reach_sign * droop * 0.25 * height * t * t
        y = root.y + lean_y * t
        z = root.z + height * (t ** 0.94) * (1.0 - droop * t * t)
        # Monotonic taper to a needle tip: real steppe blades, not aloe leaves.
        half_width = width * max(0.06, (1.0 - t * 0.92) ** 0.85)
        vertices.append((x - axis_x * half_width, y - axis_y * half_width, z))
        vertices.append((x + axis_x * half_width, y + axis_y * half_width, z))
        if i > 0:
            base = i * 2
            faces.append((base - 2, base - 1, base + 1, base))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    return mesh


def make_uv_sphere(name: str, location: Vector, radius: float, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def frame_type_params(frame_type: int, rng: random.Random, tuft: dict) -> dict:
    """Four silhouette families, mirroring the reference atlas columns:
    0 standard clump with seed heads, 1 sparse runt, 2 dense wide carpet,
    3 tall wind-combed lean."""
    ranges = tuft["blade_count_ranges"]
    params = {
        "family": "standard",
        "blade_count": rng.randint(*ranges["standard"]),
        "height_scale": 1.0,
        "spread_scale": 1.0,
        "width_scale": 1.0,
        "lean_bias": 0.0,
        "bloom_count": rng.randint(2, 5),
        "allow_broadleaf": True,
    }
    if frame_type == 1:
        params.update(
            family="sparse",
            blade_count=rng.randint(*ranges["sparse"]),
            height_scale=0.80,
            spread_scale=0.86,
            bloom_count=1 if rng.random() < 0.15 else 0,
            allow_broadleaf=False,
        )
    elif frame_type == 2:
        params.update(
            family="dense",
            blade_count=rng.randint(*ranges["dense"]),
            spread_scale=1.12,
            width_scale=1.08,
            bloom_count=rng.randint(0, 2),
        )
    elif frame_type == 3:
        params.update(
            family="tall",
            blade_count=rng.randint(*ranges["tall"]),
            height_scale=1.08,
            lean_bias=rng.uniform(0.025, 0.055),
            bloom_count=rng.randint(0, 1),
            allow_broadleaf=False,
        )
    return params


def create_tuft(frame_index: int, profile: dict, seed: int) -> list[bpy.types.Object]:
    rng = random.Random(seed + frame_index * 7919)
    atlas = profile["atlas"]
    tuft = profile["tuft"]
    is_biofield = frame_index >= int(atlas["biofield_frame_base"])
    frame_type = frame_index % 4
    params = frame_type_params(frame_type, rng, tuft)

    blade_count = int(params["blade_count"])
    height_min = float(tuft["height_min"]) * params["height_scale"]
    height_max = float(tuft["height_max"]) * params["height_scale"]
    spread_x = float(tuft["spread_x"]) * params["spread_scale"]
    depth_y = float(tuft["depth_y"]) * params["spread_scale"]
    if is_biofield:
        blade_count += int(tuft["biofield_extra_blades"])
        height_max += float(tuft["biofield_extra_height"])

    segments = 5
    palette_key = "biofield_blade_ramps" if is_biofield else "dry_blade_ramps"
    ramp_count = len(profile["palette"][palette_key])
    tier_count = len(tuft["shade_tiers"])
    objects: list[bpy.types.Object] = []

    clump_count = rng.randint(int(tuft["clump_count_min"]), int(tuft["clump_count_max"]))
    clumps = [
        Vector((rng.uniform(-spread_x * 0.7, spread_x * 0.7), rng.uniform(-depth_y * 0.7, depth_y * 0.7), 0.0))
        for _ in range(clump_count)
    ]
    sigma = float(tuft["clump_sigma"]) * params["spread_scale"]
    frame_y_bias = rng.uniform(-depth_y * 0.20, depth_y * 0.20)
    frame_z_bias = rng.uniform(float(tuft["root_z_min"]) * 0.45, float(tuft["root_z_max"]) * 0.45)

    blade_tips: list[tuple[float, Vector]] = []
    for i in range(blade_count):
        clump = rng.choice(clumps)
        root = Vector(
            (
                max(-spread_x, min(spread_x, clump.x + rng.gauss(0.0, sigma))),
                max(-depth_y, min(depth_y, clump.y + frame_y_bias + rng.gauss(0.0, sigma * 0.95))),
                rng.uniform(float(tuft["root_z_min"]), float(tuft["root_z_max"])) + frame_z_bias,
            )
        )
        height = rng.uniform(height_min, height_max)
        width = rng.uniform(float(tuft["blade_width_min"]), float(tuft["blade_width_max"])) * params["width_scale"]
        droop = rng.uniform(float(tuft["droop_min"]), float(tuft["droop_max"]))
        is_broadleaf = params["allow_broadleaf"] and rng.random() < float(tuft["broadleaf_chance"])
        if is_broadleaf:
            width *= float(tuft["broadleaf_width_scale"])
            height *= float(tuft["broadleaf_height_scale"])
            droop = min(1.0, droop * 1.5)
        lean_x = params["lean_bias"] + rng.uniform(-0.075, 0.075) + math.sin(i * 1.73 + frame_index) * 0.022
        lean_y = rng.uniform(-0.10, 0.12)
        bow = rng.uniform(-0.030, 0.030)
        yaw = math.radians(rng.uniform(-35.0, 35.0))

        # Depth shading: far blades sink into darker tiers -> the dark
        # understory the reference atlas painted by hand.
        depth_norm = (root.y + depth_y) / max(2.0 * depth_y, 0.0001)
        tier_index = min(
            tier_count - 1,
            max(0, int(round(depth_norm * (tier_count - 1))) + rng.choice((-1, 0, 0, 1))),
        )
        ramp_index = rng.randrange(ramp_count)

        mesh = blade_mesh(
            f"tuft_{frame_index:02d}_blade_{i:02d}",
            root,
            height,
            lean_x,
            lean_y,
            width,
            bow,
            droop,
            yaw,
            segments,
        )
        obj = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.collection.objects.link(obj)
        for segment in range(segments):
            obj.data.materials.append(
                shaded_segment_material(profile, palette_key, ramp_index, tier_index, segment, segments)
            )
        for polygon_index, polygon in enumerate(obj.data.polygons):
            polygon.material_index = min(polygon_index, segments - 1)
        objects.append(obj)
        if not is_broadleaf:
            tip = Vector(
                (
                    root.x + lean_x + reach_of(droop, height, lean_x),
                    root.y + lean_y,
                    root.z + height * (1.0 - droop),
                )
            )
            blade_tips.append((height, tip))

    ground_ranges = tuft.get("ground_straw_count_ranges", {})
    straw_range = ground_ranges.get(str(params["family"]), ground_ranges.get("standard", [2, 4]))
    straw_count = rng.randint(int(straw_range[0]), int(straw_range[1]))
    for straw_index in range(straw_count):
        root = Vector(
            (
                rng.uniform(-spread_x * 0.92, spread_x * 0.92),
                rng.uniform(-depth_y * 1.10, depth_y * 1.10) + frame_y_bias * 0.65,
                rng.uniform(float(tuft["root_z_min"]) * 1.15, float(tuft["root_z_max"]) * 0.35) + frame_z_bias,
            )
        )
        height = rng.uniform(height_min * 0.35, height_max * 0.58)
        lean_x = rng.uniform(-0.11, 0.11)
        lean_y = rng.uniform(-0.13, 0.16)
        width = rng.uniform(float(tuft["blade_width_min"]) * 1.1, float(tuft["blade_width_max"]) * 1.45)
        droop = rng.uniform(0.58, 0.88)
        bow = rng.uniform(-0.04, 0.04)
        yaw = math.radians(rng.uniform(-55.0, 55.0))
        mesh = blade_mesh(
            f"tuft_{frame_index:02d}_ground_straw_{straw_index:02d}",
            root,
            height,
            lean_x,
            lean_y,
            width,
            bow,
            droop,
            yaw,
            segments,
        )
        obj = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.collection.objects.link(obj)
        ramp_index = rng.randrange(ramp_count)
        tier_index = rng.randrange(max(1, tier_count - 2), tier_count)
        for segment in range(segments):
            obj.data.materials.append(
                shaded_segment_material(profile, palette_key, ramp_index, tier_index, segment, segments)
            )
        for polygon_index, polygon in enumerate(obj.data.polygons):
            polygon.material_index = min(polygon_index, segments - 1)
        objects.append(obj)

    blade_tips.sort(key=lambda item: -item[0])
    bloom_count = min(int(params["bloom_count"]), len(blade_tips))
    for bloom_index in range(bloom_count):
        _, tip = blade_tips[bloom_index]
        radius = rng.uniform(float(tuft["bloom_radius_min"]), float(tuft["bloom_radius_max"]))
        objects.append(
            make_uv_sphere(
                f"tuft_{frame_index:02d}_bloom_{bloom_index:02d}",
                tip,
                radius,
                bloom_material(profile, rng.randrange(len(profile["palette"]["bloom_rgb"]))),
            )
        )
    return objects


def reach_of(droop: float, height: float, lean_x: float) -> float:
    reach_sign = 1.0 if lean_x >= 0.0 else -1.0
    return reach_sign * droop * 0.25 * height


def remove_objects(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def render_frame(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def setup_shadow_scene(objects: list[bpy.types.Object], profile: dict) -> bpy.types.Object:
    scene = bpy.context.scene
    render_profile = profile["render"]
    lighting = profile["lighting"]
    set_render_engine(scene, str(render_profile.get("shadow_engine", "CYCLES")))
    if hasattr(scene, "cycles"):
        scene.cycles.samples = int(render_profile["samples"])
        scene.cycles.use_denoising = bool(render_profile.get("use_denoising", True))
    scene.render.film_transparent = bool(render_profile["transparent_film"])

    for obj in objects:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.visible_camera = False
        obj.visible_shadow = True

    for obj in scene.objects:
        if obj.type != "LIGHT":
            continue
        if obj.name.startswith("GrassTuftSun"):
            obj.hide_render = False
            obj.rotation_euler = (
                math.radians(float(lighting["shadow_sun_elevation_degrees"])),
                0.0,
                math.radians(float(lighting["sun_azimuth_degrees"])),
            )
            obj.data.energy = float(lighting["shadow_sun_energy"])
        elif obj.name.startswith("GrassTuftFill"):
            obj.data.energy = 0.0
        elif obj.name.startswith("GrassTuftLowOppositeKicker"):
            obj.hide_render = True

    plane_mesh = bpy.data.meshes.new("GrassShadowCatcherPlaneMesh")
    size = 1.6
    verts = [(-size, -size, -0.010), (size, -size, -0.010), (size, size, -0.010), (-size, size, -0.010)]
    plane_mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    plane_mesh.update()
    plane = bpy.data.objects.new("GrassShadowCatcherPlane", plane_mesh)
    bpy.context.collection.objects.link(plane)
    plane.is_shadow_catcher = True
    return plane


def render_shadow_frame(path: Path, objects: list[bpy.types.Object], profile: dict) -> None:
    plane = setup_shadow_scene(objects, profile)
    render_frame(path)
    bpy.data.objects.remove(plane, do_unlink=True)
    configure_albedo_render(bpy.context.scene, profile)
    configure_albedo_lighting(bpy.context.scene, profile)
    for obj in objects:
        obj.visible_camera = True
        obj.visible_shadow = True


def main() -> None:
    args = parse_args()
    profile = load_profile(args.profile, args.override_json)
    clear_scene()
    _MATERIAL_CACHE.clear()
    setup_scene(profile)
    frame_count = int(profile["atlas"]["frame_count"])
    frame_indices = list(range(frame_count))
    if args.frame_list:
        frame_indices = [int(token) for token in args.frame_list.split(",") if token.strip() != ""]
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for step, frame_index in enumerate(frame_indices):
        objects = create_tuft(frame_index, profile, args.seed)
        configure_albedo_render(bpy.context.scene, profile)
        configure_albedo_lighting(bpy.context.scene, profile)
        render_frame(out_dir / f"frame_{frame_index:02d}.png")
        if args.write_self_shadow_reference:
            sun = bpy.data.objects.get("GrassTuftSun")
            if sun is None:
                raise RuntimeError("GrassTuftSun is required for the self-shadow reference.")
            sun.data.use_shadow = False
            render_frame(out_dir / f"no_self_shadow_frame_{frame_index:02d}.png")
            sun.data.use_shadow = True
        render_shadow_frame(out_dir / ("shadow_frame_%02d.png" % frame_index), objects, profile)
        remove_objects(objects)
        print(f"Rendered grass frame {step + 1}/{len(frame_indices)} (index {frame_index})")


if __name__ == "__main__":
    main()
