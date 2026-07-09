"""Bake one GLB small rock into layered 2D source images.

The bake intentionally mirrors the tree layered asset profile: same frame,
camera, yaw, sun azimuth/elevation, and Cycles shadow-catcher pass. Rock assets
do not produce wind masks.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


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


def import_rock(glb_path: Path) -> list[bpy.types.Object]:
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


def normalize_rock(
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
    root = bpy.data.objects.new("RockRoot", None)
    bpy.context.collection.objects.link(root)
    root.rotation_euler[2] = math.radians(yaw_degrees)
    for obj in objects:
        obj.parent = root
        obj.location -= center
    bpy.context.view_layer.update()


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

    scene.render.engine = str(render_profile["albedo_engine"])
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

    camera_data = bpy.data.cameras.new("LayeredRockCamera")
    camera = bpy.data.objects.new("LayeredRockCamera", camera_data)
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

    sun_data = bpy.data.lights.new("LayeredRockSun", "SUN")
    sun = bpy.data.objects.new("LayeredRockSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.data.energy = float(lighting_profile["albedo_sun_energy"])
    sun.rotation_euler = (
        math.radians(float(lighting_profile["albedo_sun_elevation_degrees"])),
        0.0,
        math.radians(sun_angle_degrees),
    )

    fill_data = bpy.data.lights.new("LayeredRockFill", "AREA")
    fill = bpy.data.objects.new("LayeredRockFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = Vector((0.0, -2.0, 1.0))
    fill.data.energy = float(lighting_profile["fill_energy"])
    fill.data.size = float(lighting_profile["fill_size"])
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


def render_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def make_snow_surface_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("RockSnowSurfaceMask")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new(type="ShaderNodeOutputMaterial")
    emission = nodes.new(type="ShaderNodeEmission")
    try:
        geometry = nodes.new(type="ShaderNodeNewGeometry")
        separate = nodes.new(type="ShaderNodeSeparateXYZ")
        ramp = nodes.new(type="ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.34
        ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
        ramp.color_ramp.elements[1].position = 0.82
        ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
        links.new(geometry.outputs["Normal"], separate.inputs[0])
        links.new(separate.outputs["Z"], ramp.inputs[0])
        links.new(ramp.outputs["Color"], emission.inputs["Color"])
    except Exception:
        emission.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    emission.inputs["Strength"].default_value = 1.0
    links.new(emission.outputs[0], output.inputs["Surface"])
    return mat


def replace_materials(objects: list[bpy.types.Object], material: bpy.types.Material) -> list[list[bpy.types.Material | None]]:
    previous: list[list[bpy.types.Material | None]] = []
    for obj in objects:
        slots = [slot.material for slot in obj.material_slots]
        previous.append(slots)
        if len(obj.material_slots) == 0:
            obj.data.materials.append(material)
        else:
            for slot in obj.material_slots:
                slot.material = material
    return previous


def restore_materials(objects: list[bpy.types.Object], previous: list[list[bpy.types.Material | None]]) -> None:
    for obj, slots in zip(objects, previous):
        obj.data.materials.clear()
        for mat in slots:
            obj.data.materials.append(mat)


def setup_shadow_scene(objects: list[bpy.types.Object], sun_angle_degrees: float, profile: dict) -> None:
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

    for obj in scene.objects:
        if obj.type == "LIGHT" and obj.name.startswith("LayeredRockSun"):
            obj.rotation_euler = (
                math.radians(float(lighting_profile["shadow_sun_elevation_degrees"])),
                0.0,
                math.radians(sun_angle_degrees),
            )
            obj.data.energy = float(lighting_profile["shadow_sun_energy"])


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
    objects = import_rock(args.glb)
    normalize_rock(objects, yaw_degrees, root_embed_fraction, float(profile["planting"]["max_root_embed_fraction"]))
    corners = all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, _sun = setup_render(frame_size, camera_target_z, sun_angle_degrees, profile)
    anchor = fit_camera_to_objects(camera, objects, profile)

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    render_png(out_dir / "albedo.png")

    snow_material = make_snow_surface_material()
    previous_materials = replace_materials(objects, snow_material)
    render_png(out_dir / "snow_surface_raw.png")
    restore_materials(objects, previous_materials)

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
        "layers": {
            "albedo": "albedo.png",
            "snow_surface_raw": "snow_surface_raw.png",
            "shadow_raw": "shadow_raw.png",
        },
        "notes": "Small rock layered GLB bake. No wind mask is produced.",
    }
    with (out_dir / "classification.json").open("w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent="\t", ensure_ascii=False)
    print(f"Wrote layered rock render source to {out_dir}")


if __name__ == "__main__":
    main()
