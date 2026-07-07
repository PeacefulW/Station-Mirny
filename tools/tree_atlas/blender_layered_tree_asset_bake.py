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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--frame-size", type=int, default=FRAME_SIZE)
    parser.add_argument("--yaw-degrees", type=float, default=18.0)
    parser.add_argument("--sun-angle-degrees", type=float, default=FIXED_SUN_AZIMUTH_DEGREES)
    parser.add_argument("--root-embed-fraction", type=float, default=ROOT_EMBED_FRACTION)
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    return parser.parse_args(argv)


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


def normalize_tree(objects: list[bpy.types.Object], yaw_degrees: float, root_embed_fraction: float) -> None:
    corners = all_world_corners(objects)
    min_x = min(c.x for c in corners)
    max_x = max(c.x for c in corners)
    min_y = min(c.y for c in corners)
    max_y = max(c.y for c in corners)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    root_z = min_z + (max_z - min_z) * max(0.0, min(root_embed_fraction, 0.22))
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


def setup_render(frame_size: int, target_z: float, sun_angle_degrees: float) -> tuple[bpy.types.Object, bpy.types.Light]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 64
    scene.render.resolution_x = frame_size
    scene.render.resolution_y = frame_size
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Filmic"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    camera_data = bpy.data.cameras.new("LayeredTreeCamera")
    camera = bpy.data.objects.new("LayeredTreeCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.location = Vector((0.0, -3.0, target_z + 1.6))
    look_at(camera, Vector((0.0, 0.0, target_z)))

    sun_data = bpy.data.lights.new("LayeredTreeSun", "SUN")
    sun = bpy.data.objects.new("LayeredTreeSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.data.energy = 2.25
    sun.rotation_euler = (math.radians(ALBEDO_SUN_ELEVATION_DEGREES), 0.0, math.radians(sun_angle_degrees))

    fill_data = bpy.data.lights.new("LayeredTreeFill", "AREA")
    fill = bpy.data.objects.new("LayeredTreeFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = Vector((0.0, -2.0, 1.0))
    fill.data.energy = 65.0
    fill.data.size = 4.0
    return camera, sun


def fit_camera_to_objects(camera: bpy.types.Object, objects: list[bpy.types.Object]) -> tuple[int, int]:
    scene = bpy.context.scene
    camera.data.ortho_scale = 1.25
    corners = all_world_corners(objects)
    for _ in range(3):
        projected = [world_to_camera_view(scene, camera, corner) for corner in corners]
        min_x = min(p.x for p in projected)
        max_x = max(p.x for p in projected)
        min_y = min(p.y for p in projected)
        max_y = max(p.y for p in projected)
        width = max_x - min_x
        height = max_y - min_y
        scale_factor = max(width / 0.66, height / 0.70, 0.2)
        camera.data.ortho_scale *= scale_factor
        bpy.context.view_layer.update()
    camera.data.ortho_scale *= 1.10
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


def setup_shadow_scene(objects: list[bpy.types.Object], sun_angle_degrees: float) -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True

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

    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.name.startswith("LayeredTreeSun"):
            obj.rotation_euler = (math.radians(SHADOW_SUN_ELEVATION_DEGREES), 0.0, math.radians(sun_angle_degrees))
            obj.data.energy = 3.5
    return plane


def main() -> None:
    args = parse_args()
    clear_scene()
    objects = import_tree(args.glb)
    normalize_tree(objects, args.yaw_degrees, args.root_embed_fraction)
    classification = classify_objects(objects)
    corners = all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * 0.42
    camera, _sun = setup_render(args.frame_size, camera_target_z, args.sun_angle_degrees)
    anchor = fit_camera_to_objects(camera, objects)

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
    setup_shadow_scene(objects, args.sun_angle_degrees)
    render_png(out_dir / "shadow_raw.png")

    metadata = {
        "source_glb": str(args.glb),
        "frame_width": args.frame_size,
        "frame_height": args.frame_size,
        "anchor": list(anchor),
        "yaw_degrees": args.yaw_degrees,
        "sun_angle_degrees": args.sun_angle_degrees,
        "root_embed_fraction": args.root_embed_fraction,
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
