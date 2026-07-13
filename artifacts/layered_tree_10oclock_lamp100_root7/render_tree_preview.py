"""Render one isolated tree_01 review with the selected lighting experiment."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools" / "tree_atlas"
sys.path.insert(0, str(TOOLS))

import blender_layered_tree_asset_bake as bake  # noqa: E402


SOURCE_PROFILE = TOOLS / "layered_tree_bake_profile_10_oclock_fill_20.json"
DEFAULT_OUT_DIR = Path(__file__).resolve().parent

ROOT_EMBED_FRACTION = 0.07
LAMP_ENERGY = 100.0
FRAME_SIZE = 1024
GROUND_Z = 0.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tree-index", type=int, default=1, choices=range(1, 7))
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    return parser.parse_args(argv)


def clip_shadow_casters_to_visible_ground(objects: list[bpy.types.Object]) -> dict:
    """Remove mesh geometry below ground so buried roots cannot cast shadows."""
    world_plane_point = Vector((0.0, 0.0, GROUND_Z))
    world_plane_normal = Vector((0.0, 0.0, 1.0))
    before_vertices = 0
    after_vertices = 0
    clipped_objects = 0
    empty_objects: list[bpy.types.Object] = []

    for obj in objects:
        mesh = obj.data
        object_vertices_before = len(mesh.vertices)
        before_vertices += len(mesh.vertices)
        matrix_world = obj.matrix_world.copy()
        plane_co_local = matrix_world.inverted() @ world_plane_point
        plane_no_local = (matrix_world.to_3x3().transposed() @ world_plane_normal).normalized()

        bm = bmesh.new()
        bm.from_mesh(mesh)
        geometry = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(
            bm,
            geom=geometry,
            dist=0.00001,
            plane_co=plane_co_local,
            plane_no=plane_no_local,
            clear_inner=True,
            clear_outer=False,
        )
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        after_vertices += len(mesh.vertices)
        if len(mesh.vertices) != object_vertices_before:
            clipped_objects += 1
        if len(mesh.vertices) == 0:
            empty_objects.append(obj)

    for obj in empty_objects:
        objects.remove(obj)
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.view_layer.update()
    remaining_corners = bake.all_world_corners(objects)
    remaining_min_z = min(c.z for c in remaining_corners)
    if remaining_min_z < GROUND_Z - 0.0001:
        raise RuntimeError(f"Buried shadow geometry remains below ground: {remaining_min_z}")
    return {
        "mode": "physical_mesh_bisect",
        "clip_plane_z": GROUND_Z,
        "before_vertices": before_vertices,
        "after_vertices": after_vertices,
        "clipped_objects": clipped_objects,
        "remaining_min_z": remaining_min_z,
    }


def add_ground() -> bpy.types.Object:
    bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    plane.name = "TreeReviewGround"

    material = bpy.data.materials.new("TreeReviewGroundMaterial")
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (0.085, 0.072, 0.052, 1.0)
    principled.inputs["Roughness"].default_value = 0.94
    plane.data.materials.append(material)
    return plane


def main() -> None:
    args = parse_args()
    tree_id = f"tree_{args.tree_index:02d}"
    source_glb = Path(f"C:/Users/progi/project-Mirniy/tree glb/{args.tree_index}.glb")
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    out_image = out_dir / f"{tree_id}_sun10_lamp100_root7_visible_root_shadow_cycles.png"
    out_manifest = out_dir / f"{tree_id}_manifest.json"
    yaw_degrees = 180.0 if args.tree_index == 6 else 90.0

    profile = bake.load_profile(SOURCE_PROFILE)
    profile["profile_id"] = f"station_mirny_{tree_id}_sun10_lamp100_root7_review"
    profile["orientation"]["default_yaw_degrees"] = yaw_degrees
    profile["planting"]["root_embed_fraction"] = ROOT_EMBED_FRACTION
    profile["lighting"]["low_opposite_kicker"]["energy"] = LAMP_ENERGY
    profile["render"]["albedo_engine"] = "BLENDER_EEVEE"
    profile["render"]["transparent_film"] = False
    profile["render"]["samples"] = 64
    profile["frame_size"] = FRAME_SIZE
    profile["camera"]["padding_scale"] = 1.28

    bake.clear_scene()
    objects = bake.import_tree(source_glb)
    bake.normalize_tree(
        objects,
        float(profile["orientation"]["default_yaw_degrees"]),
        ROOT_EMBED_FRACTION,
        float(profile["planting"]["max_root_embed_fraction"]),
    )

    pre_clip_corners = bake.all_world_corners(objects)
    buried_geometry_min_z = min(c.z for c in pre_clip_corners)
    caster_clip = clip_shadow_casters_to_visible_ground(objects)

    corners = bake.all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(profile["camera"]["target_z_fraction"])
    camera, sun = bake.setup_render(
        FRAME_SIZE,
        camera_target_z,
        float(profile["lighting"]["sun_azimuth_degrees"]),
        profile,
    )
    kicker = bake.add_profile_low_opposite_kicker(min_z, max_z, profile)
    anchor = bake.fit_camera_to_objects(camera, objects, profile)
    add_ground()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.film_transparent = False
    scene.world.color = (0.012, 0.014, 0.018)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(out_image)
    bpy.ops.render.render(write_still=True)

    out_manifest.write_text(
        json.dumps(
            {
                "source_glb": str(source_glb),
                "source_profile": str(SOURCE_PROFILE),
                "tree": tree_id,
                "yaw_degrees": yaw_degrees,
                "screen_sun_direction": "10:00",
                "sun_azimuth_degrees": profile["lighting"]["sun_azimuth_degrees"],
                "lamp_type": "SPOT",
                "lamp_energy": LAMP_ENERGY,
                "lamp_use_shadow": bool(kicker.data.use_shadow) if kicker else None,
                "root_embed_fraction": ROOT_EMBED_FRACTION,
                "buried_geometry_min_z_before_clip": buried_geometry_min_z,
                "geometry_min_z_after_clip": min_z,
                "geometry_max_z": max_z,
                "ground_z": GROUND_Z,
                "shadow_caster_clip": caster_clip,
                "sun_shadow": {
                    "renderer": "CYCLES",
                    "samples": scene.cycles.samples,
                    "use_denoising": scene.cycles.use_denoising,
                    "angular_diameter_degrees": profile["lighting"]["albedo_sun_angular_diameter_degrees"],
                    "caster_geometry": "visible_above_ground_only",
                },
                "anchor": list(anchor),
                "frame_size": FRAME_SIZE,
                "render_engine": scene.render.engine,
                "blender_version": bpy.app.version_string,
                "output": str(out_image),
                "production_assets_changed": False,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Wrote tree review to {out_image}")


if __name__ == "__main__":
    main()
