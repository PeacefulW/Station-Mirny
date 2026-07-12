"""Bake one GLB tree into layered 2D source images.

Output is intentionally static and layered, not a 24-frame dancing atlas:
  albedo.png, trunk.png, foliage.png, shadow_raw.png, classification.json

The companion postprocess script derives wind/snow masks and preview panels.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view


FRAME_SIZE = 768
FIXED_SUN_AZIMUTH_DEGREES = 315.0
ALBEDO_SUN_ELEVATION_DEGREES = 52.0
SHADOW_SUN_ELEVATION_DEGREES = 42.0
ROOT_EMBED_FRACTION = 0.065
LEAF_VALUE_THRESHOLD = 0.34
LEAF_SAT_THRESHOLD = 0.88
LEAF_HUE_MIN = 15.0
LEAF_HUE_MAX = 45.0
DEFAULT_PROFILE_PATH = Path(__file__).with_name("layered_asset_bake_profile.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    parser.add_argument("--frame-size", type=int, default=None)
    parser.add_argument("--yaw-degrees", type=float, default=None)
    parser.add_argument("--sun-angle-degrees", type=float, default=None)
    parser.add_argument("--root-embed-fraction", type=float, default=None)
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    return parser.parse_args(argv)


def load_profile(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def bake_profile_summary(profile: dict, frame_size: int, sun_angle_degrees: float, root_embed_fraction: float) -> dict:
    summary = {
        "profile_id": profile["profile_id"],
        "version": profile["version"],
        "frame_size": frame_size,
        "sun_azimuth_degrees": sun_angle_degrees,
        "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
        "albedo_sun_angular_diameter_degrees": float(
            profile["lighting"].get("albedo_sun_angular_diameter_degrees", 0.526)
        ),
        "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
        "root_embed_fraction": root_embed_fraction,
    }
    lighting = profile["lighting"]
    if "screen_sun_direction" in lighting:
        summary["screen_sun_direction"] = lighting["screen_sun_direction"]
        summary["fixed_shadow_direction"] = lighting["fixed_shadow_direction"]
        summary["fixed_shadow_direction_vector_screen"] = lighting["fixed_shadow_direction_vector_screen"]
        summary["sun_shadow_mode"] = profile["runtime"]["sun_shadow_mode"]
        summary["shadow_contact_lock_source_px"] = float(
            profile["runtime"]["shadow_contact_lock_source_px"]
        )
    ambient_fill = lighting.get("ambient_fill")
    if ambient_fill is not None:
        summary["ambient_fill"] = ambient_fill
    kicker = lighting.get("low_opposite_kicker")
    if kicker is not None and bool(kicker.get("enabled", False)):
        summary["low_opposite_kicker"] = kicker
    shadow_casters = profile.get("shadow_casters")
    if shadow_casters is not None:
        summary["suppress_root_parts_max_z"] = float(shadow_casters["suppress_root_parts_max_z"])
    return summary


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


def import_tree(glb_path: Path) -> list[bpy.types.Object]:
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    objects: list[bpy.types.Object] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if obj.name.lower() == "cube":
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        objects.append(obj)
    if not objects:
        raise RuntimeError(f"No mesh objects imported from {glb_path}")
    return objects


def all_world_corners(objects: list[bpy.types.Object]) -> list[Vector]:
    corners: list[Vector] = []
    for obj in objects:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    return corners


def normalize_tree(
    objects: list[bpy.types.Object],
    yaw_degrees: float,
    root_embed_fraction: float,
    max_root_embed_fraction: float,
) -> None:
    corners = all_world_corners(objects)
    min_x = min(c.x for c in corners)
    max_x = max(c.x for c in corners)
    min_y = min(c.y for c in corners)
    max_y = max(c.y for c in corners)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    root_z = min_z + (max_z - min_z) * max(0.0, min(root_embed_fraction, max_root_embed_fraction))
    center = Vector(((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, root_z))
    root = bpy.data.objects.new("TreeRoot", None)
    bpy.context.collection.objects.link(root)
    root.rotation_euler[2] = math.radians(yaw_degrees)
    for obj in objects:
        obj.parent = root
        obj.location -= center
    bpy.context.view_layer.update()


def image_average_rgb(image: bpy.types.Image) -> tuple[float, float, float] | None:
    try:
        pixels = list(image.pixels[:])
    except Exception:
        return None
    count = len(pixels) // 4
    if count <= 0:
        return None
    step = max(1, count // 4096)
    r_sum = g_sum = b_sum = n = 0.0
    for index in range(0, count, step):
        alpha = pixels[index * 4 + 3]
        if alpha < 0.05:
            continue
        r_sum += pixels[index * 4]
        g_sum += pixels[index * 4 + 1]
        b_sum += pixels[index * 4 + 2]
        n += 1.0
    if n <= 0.0:
        return None
    return (r_sum / n, g_sum / n, b_sum / n)


def rgb_to_hsv(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    value = max(r, g, b)
    low = min(r, g, b)
    chroma = value - low
    if chroma <= 0.000001:
        return (0.0, 0.0, value)
    if value == r:
        hue = (60.0 * ((g - b) / chroma) + 360.0) % 360.0
    elif value == g:
        hue = 60.0 * ((b - r) / chroma) + 120.0
    else:
        hue = 60.0 * ((r - g) / chroma) + 240.0
    return (hue, chroma / max(value, 0.000001), value)


def basecolor_image(obj: bpy.types.Object) -> bpy.types.Image | None:
    for slot in obj.material_slots:
        mat = slot.material
        if not mat or not mat.node_tree:
            continue
        for node in mat.node_tree.nodes:
            if node.bl_idname != "ShaderNodeTexImage":
                continue
            image = getattr(node, "image", None)
            if image and "basecolor" in image.name.lower():
                return image
    return None


def classify_objects(objects: list[bpy.types.Object]) -> dict[str, dict]:
    classification: dict[str, dict] = {}
    for obj in objects:
        corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        min_z = min(c.z for c in corners)
        max_z = max(c.z for c in corners)
        center_z = (min_z + max_z) * 0.5
        image = basecolor_image(obj)
        rgb = image_average_rgb(image) if image else None
        hsv = rgb_to_hsv(rgb) if rgb else (0.0, 0.0, 0.0)
        hue, saturation, value = hsv
        is_leaf = (
            LEAF_HUE_MIN <= hue <= LEAF_HUE_MAX
            and saturation >= LEAF_SAT_THRESHOLD
            and value >= LEAF_VALUE_THRESHOLD
        )
        # Large dark vertical meshes are trunk/branches even when orange bark is present.
        layer = "foliage" if is_leaf else "trunk"
        classification[obj.name] = {
            "layer": layer,
            "center_z": center_z,
            "min_z": min_z,
            "max_z": max_z,
            "avg_rgb": list(rgb) if rgb else None,
            "hsv": list(hsv),
            "basecolor": image.name if image else "",
            "verts": len(obj.data.vertices),
        }
    return classification


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_symmetric_ambient_rig(target_z: float, lighting_profile: dict) -> None:
    ambient = lighting_profile.get("ambient_fill", {})
    if not bool(ambient.get("enabled", False)):
        return
    total_energy = max(float(ambient.get("total_energy", 0.0)), 0.0)
    light_count = max(int(ambient.get("light_count", 4)), 1)
    if total_energy <= 0.0:
        return
    radius = max(float(ambient.get("radius", 3.0)), 0.1)
    height = float(ambient.get("height", 2.4))
    size = max(float(ambient.get("size", 5.0)), 0.1)
    color_values = ambient.get("color", [1.0, 1.0, 1.0])
    color = (
        float(color_values[0]),
        float(color_values[1]),
        float(color_values[2]),
    )
    for index in range(light_count):
        angle = math.tau * float(index) / float(light_count)
        light_data = bpy.data.lights.new(f"LayeredTreeAmbient{index}", "AREA")
        light = bpy.data.objects.new(f"LayeredTreeAmbient{index}", light_data)
        bpy.context.collection.objects.link(light)
        light.location = Vector(
            (
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                target_z + height,
            )
        )
        light.data.energy = total_energy / float(light_count)
        light.data.size = size
        light.data.color = color
        light.data.use_shadow = False
        look_at(light, Vector((0.0, 0.0, target_z)))


def add_profile_low_opposite_kicker(
    min_z: float,
    max_z: float,
    profile: dict,
) -> bpy.types.Object | None:
    kicker_profile = profile["lighting"].get("low_opposite_kicker")
    if not kicker_profile or not bool(kicker_profile.get("enabled", False)):
        return None
    tree_height = max(max_z - min_z, 0.001)
    spot_data = bpy.data.lights.new("LayeredTreeLowOppositeKicker", "SPOT")
    spot = bpy.data.objects.new("LayeredTreeLowOppositeKicker", spot_data)
    bpy.context.collection.objects.link(spot)
    spot.location = Vector((
        float(kicker_profile["position_x"]),
        float(kicker_profile["position_y"]),
        min_z + tree_height * float(kicker_profile["height_fraction"]),
    ))
    target = Vector((
        0.0,
        0.0,
        min_z + tree_height * float(kicker_profile["target_height_fraction"]),
    ))
    look_at(spot, target)
    spot.data.energy = float(kicker_profile["energy"])
    color = kicker_profile["color"]
    spot.data.color = (float(color[0]), float(color[1]), float(color[2]))
    spot.data.spot_size = math.radians(float(kicker_profile["spot_size_degrees"]))
    spot.data.spot_blend = float(kicker_profile["spot_blend"])
    spot.data.use_shadow = bool(kicker_profile["use_shadow"])
    return spot


def setup_render(
    frame_size: int,
    target_z: float,
    sun_angle_degrees: float,
    profile: dict,
) -> tuple[bpy.types.Object, bpy.types.Light]:
    scene = bpy.context.scene
    render_profile = profile["render"]
    lighting_profile = profile["lighting"]
    camera_profile = profile["camera"]

    scene.render.engine = render_profile["albedo_engine"]
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = int(render_profile["samples"])
    scene.render.resolution_x = frame_size
    scene.render.resolution_y = frame_size
    scene.render.film_transparent = bool(render_profile["transparent_film"])
    scene.view_settings.view_transform = str(render_profile["view_transform"])
    scene.view_settings.look = str(render_profile["look"])
    scene.view_settings.exposure = float(render_profile["exposure"])
    scene.view_settings.gamma = float(render_profile["gamma"])
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = str(render_profile["color_mode"])

    camera_data = bpy.data.cameras.new("LayeredTreeCamera")
    camera = bpy.data.objects.new("LayeredTreeCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = str(camera_profile["type"])
    camera.location = Vector(
        (
            0.0,
            float(camera_profile["location_y"]),
            target_z + float(camera_profile["height_offset"]),
        )
    )
    look_at(camera, Vector((0.0, 0.0, target_z)))

    sun_data = bpy.data.lights.new("LayeredTreeSun", "SUN")
    sun = bpy.data.objects.new("LayeredTreeSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.data.energy = float(lighting_profile["albedo_sun_energy"])
    sun.data.angle = math.radians(float(lighting_profile.get("albedo_sun_angular_diameter_degrees", 0.526)))
    sun.rotation_euler = (
        math.radians(float(lighting_profile["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(sun_angle_degrees),
    )

    fill_data = bpy.data.lights.new("LayeredTreeFill", "AREA")
    fill = bpy.data.objects.new("LayeredTreeFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = Vector((0.0, -2.0, 1.0))
    fill.data.energy = float(lighting_profile["fill_energy"])
    fill.data.size = float(lighting_profile["fill_size"])
    add_symmetric_ambient_rig(target_z, lighting_profile)
    return camera, sun


def fit_camera_to_objects(camera: bpy.types.Object, objects: list[bpy.types.Object], profile: dict) -> tuple[int, int]:
    scene = bpy.context.scene
    camera_profile = profile["camera"]
    camera.data.ortho_scale = float(camera_profile["initial_ortho_scale"])
    corners = all_world_corners(objects)
    for _ in range(3):
        projected = [world_to_camera_view(scene, camera, corner) for corner in corners]
        min_x = min(p.x for p in projected)
        max_x = max(p.x for p in projected)
        min_y = min(p.y for p in projected)
        max_y = max(p.y for p in projected)
        width = max_x - min_x
        height = max_y - min_y
        scale_factor = max(
            width / float(camera_profile["fit_width_fraction"]),
            height / float(camera_profile["fit_height_fraction"]),
            0.2,
        )
        camera.data.ortho_scale *= scale_factor
        bpy.context.view_layer.update()
    camera.data.ortho_scale *= float(camera_profile["padding_scale"])
    bpy.context.view_layer.update()
    root_world = Vector((0.0, 0.0, 0.0))
    root_uv = world_to_camera_view(scene, camera, root_world)
    anchor = (
        int(round(root_uv.x * scene.render.resolution_x)),
        int(round((1.0 - root_uv.y) * scene.render.resolution_y)),
    )
    return anchor


def set_layer_visibility(objects: list[bpy.types.Object], classification: dict[str, dict], layer: str) -> None:
    for obj in objects:
        visible = layer == "all" or classification[obj.name]["layer"] == layer
        obj.hide_render = not visible
        obj.hide_viewport = not visible


def render_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def setup_shadow_scene(
    objects: list[bpy.types.Object],
    classification: dict[str, dict],
    sun_angle_degrees: float,
    profile: dict,
) -> tuple[bpy.types.Object, list[str]]:
    scene = bpy.context.scene
    render_profile = profile["render"]
    lighting_profile = profile["lighting"]
    scene.render.engine = str(render_profile["shadow_engine"])
    scene.cycles.samples = int(render_profile["samples"])
    scene.cycles.use_denoising = bool(render_profile["use_denoising"])
    scene.render.film_transparent = bool(render_profile["transparent_film"])

    suppressed_shadow_casters: list[str] = []
    caster_profile = profile.get("shadow_casters")
    root_part_max_z = (
        float(caster_profile["suppress_root_parts_max_z"])
        if caster_profile is not None
        else None
    )
    for obj in objects:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.visible_camera = False
        suppress_root_shadow = (
            root_part_max_z is not None
            and classification[obj.name]["layer"] == "trunk"
            and float(classification[obj.name]["max_z"]) <= root_part_max_z
        )
        obj.visible_shadow = not suppress_root_shadow
        if suppress_root_shadow:
            suppressed_shadow_casters.append(obj.name)

    plane_mesh = bpy.data.meshes.new("ShadowCatcherPlaneMesh")
    size = 2.8
    verts = [(-size, -size, -0.012), (size, -size, -0.012), (size, size, -0.012), (-size, size, -0.012)]
    plane_mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    plane_mesh.update()
    plane = bpy.data.objects.new("ShadowCatcherPlane", plane_mesh)
    bpy.context.collection.objects.link(plane)
    plane.is_shadow_catcher = True

    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.name.startswith("LayeredTreeSun"):
            obj.rotation_euler = (
                math.radians(float(lighting_profile["shadow_sun_elevation_degrees"])),
                0.0,
                math.radians(sun_angle_degrees),
            )
            obj.data.energy = float(lighting_profile["shadow_sun_energy"])
        elif obj.type == "LIGHT" and obj.name.startswith("LayeredTreeLowOppositeKicker"):
            # The selected kicker affects albedo only. Ground projection stays
            # a physical Sun-only Cycles shadow.
            obj.hide_render = True
    return plane, suppressed_shadow_casters


def main() -> None:
    args = parse_args()
    profile = load_profile(args.profile)
    frame_size = int(args.frame_size if args.frame_size is not None else profile["frame_size"])
    yaw_degrees = float(
        args.yaw_degrees if args.yaw_degrees is not None else profile["orientation"]["default_yaw_degrees"]
    )
    sun_angle_degrees = float(
        args.sun_angle_degrees
        if args.sun_angle_degrees is not None
        else profile["lighting"]["sun_azimuth_degrees"]
    )
    root_embed_fraction = float(
        args.root_embed_fraction
        if args.root_embed_fraction is not None
        else profile["planting"]["root_embed_fraction"]
    )
    clear_scene()
    objects = import_tree(args.glb)
    normalize_tree(
        objects,
        yaw_degrees,
        root_embed_fraction,
        float(profile["planting"]["max_root_embed_fraction"]),
    )
    classification = classify_objects(objects)
    corners = all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, _sun = setup_render(frame_size, camera_target_z, sun_angle_degrees, profile)
    add_profile_low_opposite_kicker(min_z, max_z, profile)
    anchor = fit_camera_to_objects(camera, objects, profile)

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for layer, file_name in (
        ("all", "albedo.png"),
        ("trunk", "trunk.png"),
        ("foliage", "foliage.png"),
    ):
        set_layer_visibility(objects, classification, layer)
        render_png(out_dir / file_name)

    set_layer_visibility(objects, classification, "all")
    _shadow_plane, suppressed_shadow_casters = setup_shadow_scene(
        objects,
        classification,
        sun_angle_degrees,
        profile,
    )
    render_png(out_dir / "shadow_raw.png")

    metadata = {
        "source_glb": str(args.glb),
        "frame_width": frame_size,
        "frame_height": frame_size,
        "anchor": list(anchor),
        "yaw_degrees": yaw_degrees,
        "sun_angle_degrees": sun_angle_degrees,
        "root_embed_fraction": root_embed_fraction,
        "bake_profile": bake_profile_summary(profile, frame_size, sun_angle_degrees, root_embed_fraction),
        "runtime_plant_depth_px": 0,
        "classification": classification,
        "suppressed_shadow_casters": suppressed_shadow_casters,
        "layers": {
            "albedo": "albedo.png",
            "trunk": "trunk.png",
            "foliage": "foliage.png",
            "shadow_raw": "shadow_raw.png",
        },
    }
    with (out_dir / "classification.json").open("w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent="\t", ensure_ascii=False)
    print(f"Wrote layered tree render source to {out_dir}")


if __name__ == "__main__":
    main()
