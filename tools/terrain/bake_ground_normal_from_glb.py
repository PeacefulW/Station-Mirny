#!/usr/bin/env python3
"""Bake a tangent-space normal map from a GLB mesh using Blender."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def _parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--size", type=int, default=1254)
    parser.add_argument("--margin", type=int, default=24)
    parser.add_argument("--mode", choices=("uv", "plane"), default="uv")
    return parser.parse_args(argv)


def _active_mesh() -> bpy.types.Object:
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("GLB contains no mesh objects")
    return max(meshes, key=lambda obj: len(obj.data.polygons))


def _attach_bake_image(obj: bpy.types.Object, image: bpy.types.Image) -> None:
    if not obj.data.materials:
        obj.data.materials.append(bpy.data.materials.new("normal_bake_target"))

    for material in obj.data.materials:
        if material is None:
            continue
        material.use_nodes = True
        tex = material.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        material.node_tree.nodes.active = tex


def _make_projection_plane(source: bpy.types.Object) -> bpy.types.Object:
    coords = [source.matrix_world @ source.data.vertices[index].co for index in range(len(source.data.vertices))]
    min_x = min(coord.x for coord in coords)
    max_x = max(coord.x for coord in coords)
    min_y = min(coord.y for coord in coords)
    max_y = max(coord.y for coord in coords)
    min_z = min(coord.z for coord in coords)
    max_z = max(coord.z for coord in coords)

    center_x = (min_x + max_x) * 0.5
    center_z = (min_z + max_z) * 0.5
    half = max(max_x - min_x, max_z - min_z) * 0.5
    y = max_y + max(0.01, (max_y - min_y) * 0.02)

    verts = [
        (center_x - half, y, center_z - half),
        (center_x + half, y, center_z - half),
        (center_x + half, y, center_z + half),
        (center_x - half, y, center_z + half),
    ]
    mesh = bpy.data.meshes.new("normal_bake_plane_mesh")
    mesh.from_pydata(verts, [], [(0, 3, 2, 1)])
    mesh.update(calc_edges=True)

    uv = mesh.uv_layers.new(name="UVMap")
    face = mesh.polygons[0]
    for loop_index, value in zip(face.loop_indices, ((0, 0), (0, 1), (1, 1), (1, 0))):
        uv.data[loop_index].uv = value

    plane = bpy.data.objects.new("normal_bake_plane", mesh)
    bpy.context.collection.objects.link(plane)
    return plane


def main() -> None:
    args = _parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    bpy.ops.import_scene.gltf(filepath=str(input_path))

    source = _active_mesh()
    if args.mode == "uv" and not source.data.uv_layers:
        raise RuntimeError(f"Mesh {source.name!r} has no UV map for texture bake")

    target = source if args.mode == "uv" else _make_projection_plane(source)

    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.mode_set(mode="OBJECT")

    image = bpy.data.images.new(
        "dry_ground_top_normal_model_bake",
        width=args.size,
        height=args.size,
        alpha=False,
        float_buffer=False,
    )
    image.generated_color = (0.5, 0.5, 1.0, 1.0)
    _attach_bake_image(target, image)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = args.margin
    scene.render.bake.use_clear = True
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.use_selected_to_active = args.mode == "plane"
    scene.render.bake.max_ray_distance = 1.5 if args.mode == "plane" else 0.0

    bpy.ops.object.bake(type="NORMAL")

    image.filepath_raw = str(output_path)
    image.file_format = "PNG"
    image.save_render(str(output_path))

    print(
        "BAKED",
        {
            "mesh": source.name,
            "mode": args.mode,
            "vertices": len(source.data.vertices),
            "polygons": len(source.data.polygons),
            "uv_layers": [uv.name for uv in source.data.uv_layers],
            "output": str(output_path),
            "size": args.size,
        },
    )


if __name__ == "__main__":
    main()
