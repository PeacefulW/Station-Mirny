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
    return {
        "profile_id": profile["profile_id"],
        "version": profile["version"],
        "frame_size": frame_size,
        "sun_azimuth_degrees": sun_angle_degrees,
        "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
        "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
        "root_embed_fraction": root_embed_fraction,
    }


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
    sun.rotation_euler = (
        math.radians(float(lighting_profile["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(sun_angle_degrees),
    )

    # The sun sits north-west, so the face the camera sees is the shaded one. It
    # is lifted by a ground bounce: low, on the camera side, aimed upward. Coming
    # from below, it reaches undersides and the trunk without touching the
    # sun-lit tops, so it can never blow out a highlight the way a frontal fill
    # or raised exposure does. It casts nothing; the sun owns every shadow.
    bounce_profile = lighting_profile["bounce"]
    bounce_data = bpy.data.lights.new("LayeredTreeBounce", "AREA")
    bounce = bpy.data.objects.new("LayeredTreeBounce", bounce_data)
    bpy.context.collection.objects.link(bounce)
    bounce.location = Vector(tuple(float(value) for value in bounce_profile["location"]))
    bounce.rotation_euler = (math.radians(float(bounce_profile["pitch_degrees"])), 0.0, 0.0)
    bounce.data.energy = float(bounce_profile["energy"])
    bounce.data.size = float(bounce_profile["size"])
    bounce.data.color = tuple(float(value) for value in bounce_profile["color"])
    bounce.data.use_shadow = bool(bounce_profile["casts_shadow"])
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


def set_layer_visibility(
    objects: list[bpy.types.Object],
    classification: dict[str, dict],
    layer: str,
    cross_layer_shadows: bool = True,
) -> None:
    """Render one layer, but keep the other layers casting sun shadows onto it.

    The runtime composites `trunk.png` under `foliage.png`, so any shadow the
    canopy casts on the trunk has to exist inside the trunk pass. Hiding the
    other layer outright removes it from the shadow map too, and the assembled
    tree ends up with no self-shadowing at all.
    """
    for obj in objects:
        visible = layer == "all" or classification[obj.name]["layer"] == layer
        if visible or not cross_layer_shadows:
            obj.hide_render = not visible
            obj.hide_viewport = not visible
            obj.visible_camera = True
            continue
        obj.hide_render = False
        obj.hide_viewport = False
        obj.visible_camera = False
        obj.visible_shadow = True


def render_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def setup_shadow_scene(objects: list[bpy.types.Object], sun_angle_degrees: float, profile: dict) -> bpy.types.Object:
    scene = bpy.context.scene
    render_profile = profile["render"]
    lighting_profile = profile["lighting"]
    scene.render.engine = str(render_profile["shadow_engine"])
    scene.cycles.samples = int(render_profile["samples"])
    scene.cycles.use_denoising = bool(render_profile["use_denoising"])
    scene.render.film_transparent = bool(render_profile["transparent_film"])

    for obj in objects:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.visible_camera = False
        obj.visible_shadow = True

    plane_mesh = bpy.data.meshes.new("ShadowCatcherPlaneMesh")
    size = 2.8
    verts = [(-size, -size, -0.012), (size, -size, -0.012), (size, size, -0.012), (-size, size, -0.012)]
    plane_mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    plane_mesh.update()
    plane = bpy.data.objects.new("ShadowCatcherPlane", plane_mesh)
    bpy.context.collection.objects.link(plane)
    plane.is_shadow_catcher = True

    keep_bounce = bool(lighting_profile["bounce"]["in_shadow_pass"])
    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.name.startswith("LayeredTreeBounce") and not keep_bounce:
            # The shadow catcher must read the sun alone; unshadowed bounce light
            # landing on the plane would wash the cast shadow out.
            obj.hide_render = True
            continue
        if obj.type == "LIGHT" and obj.name.startswith("LayeredTreeSun"):
            obj.rotation_euler = (
                math.radians(float(lighting_profile["shadow_sun_elevation_degrees"])),
                0.0,
                math.radians(sun_angle_degrees),
            )
            obj.data.energy = float(lighting_profile["shadow_sun_energy"])
    return plane


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
    setup_shadow_scene(objects, sun_angle_degrees, profile)
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
