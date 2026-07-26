"""Bake one procedural silhouette variation of a source GLB tree.

This script does not own bake settings. Camera, lighting, render engine, yaw
default, root embed and layer splitting all come from the canonical module
`blender_layered_tree_asset_bake.py` and `layered_asset_bake_profile.json`.

What this script adds is a deterministic geometry variation step inserted
between GLB import and the canonical bake:

  import GLB -> classify trunk/foliage -> deform -> normalize -> render

The source GLB is a photogrammetry-style mesh split into many parts that share
one continuous surface. Rotating a single part would tear the mesh, so the
variation is a continuous deformation field evaluated around the reconstructed
trunk axis and applied to every vertex of every part with the same function.
Foliage clusters get an additional local transform, which is safe because a
canopy blob is much larger than the twig it hides.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import random
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector, kdtree

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_BAKE_PROFILE = TOOL_DIR / "layered_asset_bake_profile.json"
DEFAULT_VARIATION_PROFILE = TOOL_DIR / "tree_variation_profiles.json"


def load_canonical_bake_module():
    path = TOOL_DIR / "blender_layered_tree_asset_bake.py"
    spec = importlib.util.spec_from_file_location("layered_tree_asset_bake", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load canonical bake module at {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BAKE = load_canonical_bake_module()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True, type=Path)
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
    raise SystemExit(f"Unknown variant id {variant_id!r}. Known: {known}")


# --- mesh access -------------------------------------------------------------


def mesh_world_coords(obj: bpy.types.Object) -> np.ndarray:
    mesh = obj.data
    count = len(mesh.vertices)
    flat = np.empty(count * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", flat)
    local = flat.reshape(count, 3)
    matrix = np.array(obj.matrix_world, dtype=np.float64)
    return local @ matrix[:3, :3].T + matrix[:3, 3]


def write_mesh_world_coords(obj: bpy.types.Object, world: np.ndarray) -> None:
    matrix = np.array(obj.matrix_world, dtype=np.float64)
    inverse_basis = np.linalg.inv(matrix[:3, :3])
    local = (world - matrix[:3, 3]) @ inverse_basis.T
    mesh = obj.data
    mesh.vertices.foreach_set("co", local.astype(np.float32).ravel())
    mesh.update()


def drop_custom_split_normals(obj: bpy.types.Object) -> bool:
    """Vertex-level deformation invalidates imported split normals."""
    mesh = obj.data
    removed = False
    if "custom_normal" in mesh.attributes:
        mesh.attributes.remove(mesh.attributes["custom_normal"])
        removed = True
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    return removed


# --- trunk axis --------------------------------------------------------------


def build_trunk_axis(
    trunk_coords: np.ndarray,
    base_z: float,
    top_z: float,
    bins: int,
    smooth_passes: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Median XY of trunk geometry per height band, smoothed into a centerline."""
    edges = np.linspace(base_z, top_z, bins + 1)
    centers = 0.5 * (edges[:-1] + edges[1:])
    axis = np.full((bins, 2), np.nan, dtype=np.float64)
    index = np.clip(np.digitize(trunk_coords[:, 2], edges) - 1, 0, bins - 1)
    for band in range(bins):
        selected = trunk_coords[index == band]
        if selected.shape[0] < 32:
            continue
        axis[band, 0] = float(np.median(selected[:, 0]))
        axis[band, 1] = float(np.median(selected[:, 1]))

    valid = ~np.isnan(axis[:, 0])
    if not valid.any():
        raise RuntimeError("Could not reconstruct a trunk axis from trunk geometry.")
    for column in range(2):
        axis[:, column] = np.interp(centers, centers[valid], axis[valid, column])
    for _ in range(max(0, smooth_passes)):
        padded = np.vstack([axis[:1], axis, axis[-1:]])
        axis = (padded[:-2] + padded[1:-1] * 2.0 + padded[2:]) * 0.25
    return centers, axis


def sample_axis(centers: np.ndarray, axis: np.ndarray, z: np.ndarray) -> np.ndarray:
    return np.stack(
        (np.interp(z, centers, axis[:, 0]), np.interp(z, centers, axis[:, 1])),
        axis=1,
    )


# --- deformation field -------------------------------------------------------


def deform_world_coords(
    world: np.ndarray,
    variant: dict,
    base_z: float,
    height: float,
    centers: np.ndarray,
    axis: np.ndarray,
) -> np.ndarray:
    z = world[:, 2]
    h = np.clip((z - base_z) / height, 0.0, 1.0)

    anchor = sample_axis(centers, axis, z)
    offset = world[:, :2] - anchor
    radius = np.hypot(offset[:, 0], offset[:, 1])

    angle = math.radians(float(variant["twist_degrees"])) * np.power(h, float(variant["twist_power"]))
    cos_a = np.cos(angle)
    sin_a = np.sin(angle)
    rotated = np.stack(
        (
            offset[:, 0] * cos_a - offset[:, 1] * sin_a,
            offset[:, 0] * sin_a + offset[:, 1] * cos_a,
        ),
        axis=1,
    )
    rotated *= (1.0 + float(variant["spread"]) * np.square(h))[:, None]

    lean = np.array(variant["lean"], dtype=np.float64) * height
    sway = np.array(variant["sway"], dtype=np.float64) * height
    displacement = lean[None, :] * np.power(h, float(variant["lean_power"]))[:, None]
    displacement += sway[None, :] * np.sin(np.pi * h)[:, None]

    planar = anchor + rotated + displacement
    new_z = base_z + (z - base_z) * float(variant["height_scale"])
    new_z = new_z - float(variant["droop"]) * height * np.square(radius / max(height, 1e-6))

    base_anchor = sample_axis(centers, axis, np.full(1, base_z))[0]
    planar = base_anchor + (planar - base_anchor) * float(variant["width_scale"])

    return np.column_stack((planar, new_z))


def build_trunk_kdtree(trunk_coords: np.ndarray, sample_limit: int) -> tuple[kdtree.KDTree, np.ndarray]:
    step = max(1, len(trunk_coords) // max(1, sample_limit))
    sampled = trunk_coords[::step]
    tree = kdtree.KDTree(len(sampled))
    for index, point in enumerate(sampled):
        tree.insert((float(point[0]), float(point[1]), float(point[2])), index)
    tree.balance()
    return tree, sampled


def nearest_trunk(tree: kdtree.KDTree, points: np.ndarray) -> tuple[float, np.ndarray, np.ndarray]:
    best_gap = float("inf")
    best_point = points[0]
    best_trunk = points[0]
    for point in points:
        trunk_point, _index, gap = tree.find((float(point[0]), float(point[1]), float(point[2])))
        if gap < best_gap:
            best_gap = float(gap)
            best_point = point
            best_trunk = np.array(trunk_point, dtype=np.float64)
            if best_gap <= 0.0:
                break
    return best_gap, best_point, best_trunk


def cluster_contact(tree: kdtree.KDTree, cluster: np.ndarray) -> tuple[float, np.ndarray, np.ndarray]:
    """Cluster vertex closest to trunk geometry, plus the trunk point it meets.

    Coarse sweep first, then an exhaustive sweep of the neighbourhood it found.
    A canopy blob carries tens of thousands of vertices and only the few around
    the branch join matter, so scanning all of them against the tree is wasted
    work without being any more accurate.
    """
    coarse_step = max(1, len(cluster) // 4000)
    coarse_gap, coarse_point, coarse_trunk = nearest_trunk(tree, cluster[::coarse_step])
    if coarse_gap <= 0.0:
        return coarse_gap, coarse_point, coarse_trunk

    mean_radius = float(np.linalg.norm(cluster - cluster.mean(axis=0), axis=1).mean())
    neighbourhood = max(mean_radius * 0.25, 1e-6)
    local = cluster[np.linalg.norm(cluster - coarse_point, axis=1) <= neighbourhood]
    if len(local) == 0:
        return coarse_gap, coarse_point, coarse_trunk
    fine_gap, fine_point, fine_trunk = nearest_trunk(tree, local)
    if fine_gap < coarse_gap:
        return fine_gap, fine_point, fine_trunk
    return coarse_gap, coarse_point, coarse_trunk


def transform_cluster(
    world: np.ndarray,
    *,
    pivot: np.ndarray,
    yaw_degrees: float,
    scale: float,
    sink: float,
) -> np.ndarray:
    """Rotate and scale a canopy blob around its attachment point, never its centroid.

    Pivoting on the contact vertex is what keeps foliage welded to its branch:
    the pivot is a fixed point of both the rotation and the scaling, so a cluster
    that touched the trunk before still touches it after. `sink` then pulls the
    blob further onto the branch, which can only increase the overlap.
    """
    local = world - pivot
    angle = math.radians(yaw_degrees)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    rotated = np.column_stack(
        (
            local[:, 0] * cos_a - local[:, 1] * sin_a,
            local[:, 0] * sin_a + local[:, 1] * cos_a,
            local[:, 2],
        )
    )
    rotated *= np.array([scale, scale, scale * 0.94], dtype=np.float64)
    placed = rotated + pivot

    centroid = placed.mean(axis=0)
    outward = centroid - pivot
    length = float(np.linalg.norm(outward))
    if length > 1e-9:
        radius = float(np.linalg.norm(placed - centroid, axis=1).mean())
        placed = placed - (outward / length) * (sink * radius)
    return placed


# --- pipeline ----------------------------------------------------------------


def apply_variation(
    objects: list[bpy.types.Object],
    classification: dict,
    variant: dict,
    axis_settings: dict,
    attachment_settings: dict,
) -> dict:
    rng = random.Random(int(variant["seed"]))

    foliage_names = [name for name, info in classification.items() if info["layer"] == "foliage"]
    foliage_names.sort(key=lambda name: classification[name]["verts"])
    cull_count = int(variant["cull_foliage"])
    culled = foliage_names[:cull_count] if cull_count > 0 else []
    if culled:
        doomed = [obj for obj in objects if obj.name in culled]
        objects[:] = [obj for obj in objects if obj.name not in culled]
        for obj in doomed:
            bpy.data.objects.remove(obj, do_unlink=True)

    coords = {obj.name: mesh_world_coords(obj) for obj in objects}
    trunk_coords = np.vstack(
        [coords[obj.name] for obj in objects if classification[obj.name]["layer"] == "trunk"]
    )
    all_z = np.concatenate([coords[obj.name][:, 2] for obj in objects])
    base_z = float(all_z.min())
    top_z = float(all_z.max())
    height = max(top_z - base_z, 1e-6)

    centers, axis = build_trunk_axis(
        trunk_coords,
        base_z,
        top_z,
        int(axis_settings["height_bins"]),
        int(axis_settings["smooth_passes"]),
    )

    cluster_yaw_range = float(variant["cluster_yaw_degrees"])
    cluster_scale = float(variant["cluster_scale"])
    cluster_jitter = float(variant["cluster_scale_jitter"])
    cluster_sink = float(variant["cluster_sink"])

    # Pass 1: the continuous field moves trunk and foliage together, so nothing
    # can come apart here. Keep the results in memory; the canopy pass needs the
    # already-deformed trunk to find attachment points.
    deformed: dict[str, np.ndarray] = {}
    for obj in objects:
        deformed[obj.name] = deform_world_coords(coords[obj.name], variant, base_z, height, centers, axis)

    trunk_deformed = np.vstack(
        [deformed[obj.name] for obj in objects if classification[obj.name]["layer"] == "trunk"]
    )
    tree, trunk_samples = build_trunk_kdtree(trunk_deformed, int(attachment_settings["trunk_sample_limit"]))
    tolerance = float(attachment_settings["gap_tolerance_fraction"]) * height
    overlap = float(attachment_settings["snap_overlap_fraction"])

    # Pass 2: every canopy blob is rotated and scaled around the vertex where it
    # meets a branch, so it stays welded. A cluster that already floated in the
    # source GLB is snapped down onto its nearest branch instead of inheriting
    # the defect.
    cluster_log: list[dict] = []
    for obj in objects:
        if classification[obj.name]["layer"] != "foliage":
            continue
        cluster = deformed[obj.name]
        gap_before, pivot, trunk_point = cluster_contact(tree, cluster)
        yaw = rng.uniform(-cluster_yaw_range, cluster_yaw_range)
        scale = cluster_scale * (1.0 + rng.uniform(-cluster_jitter, cluster_jitter))
        placed = transform_cluster(cluster, pivot=pivot, yaw_degrees=yaw, scale=scale, sink=cluster_sink)

        snapped = 0.0
        if gap_before > tolerance:
            radius = float(np.linalg.norm(placed - placed.mean(axis=0), axis=1).mean())
            bridge = trunk_point - pivot
            bridge_length = float(np.linalg.norm(bridge))
            if bridge_length > 1e-9:
                placed = placed + bridge * (1.0 + overlap * radius / bridge_length)
                snapped = bridge_length

        gap_after, _pivot_after, _trunk_after = cluster_contact(tree, placed)
        deformed[obj.name] = placed
        cluster_log.append(
            {
                "object": obj.name,
                "yaw_degrees": round(yaw, 3),
                "scale": round(scale, 4),
                "gap_before": round(gap_before, 6),
                "gap_after": round(gap_after, 6),
                "snapped_distance": round(snapped, 6),
            }
        )

    detached = [entry for entry in cluster_log if entry["gap_after"] > tolerance]
    if detached:
        names = ", ".join(f"{entry['object']} ({entry['gap_after']:.5f})" for entry in detached)
        raise RuntimeError(
            f"Foliage clusters left detached from branch geometry, tolerance {tolerance:.5f}: {names}"
        )

    normals_dropped = 0
    for obj in objects:
        write_mesh_world_coords(obj, deformed[obj.name])
        if drop_custom_split_normals(obj):
            normals_dropped += 1

    bpy.context.view_layer.update()
    return {
        "culled_foliage": culled,
        "clusters": cluster_log,
        "custom_normals_cleared": normals_dropped,
        "source_height": round(height, 6),
        "trunk_axis_bins": int(axis_settings["height_bins"]),
        "attachment": {
            "gap_tolerance": round(tolerance, 6),
            "trunk_samples": int(len(trunk_samples)),
            "max_gap_before": round(max((e["gap_before"] for e in cluster_log), default=0.0), 6),
            "max_gap_after": round(max((e["gap_after"] for e in cluster_log), default=0.0), 6),
            "snapped_clusters": [e["object"] for e in cluster_log if e["snapped_distance"] > 0.0],
        },
    }


def main() -> None:
    args = parse_args()
    bake_profile = load_json(args.profile)
    variation_profile = load_json(args.variation_profile)
    variant = find_variant(variation_profile, args.variant_id)

    frame_size = int(bake_profile["frame_size"])
    yaw_degrees = float(variant["yaw_degrees"])
    sun_angle_degrees = float(bake_profile["lighting"]["sun_azimuth_degrees"])
    root_embed_fraction = float(bake_profile["planting"]["root_embed_fraction"])

    BAKE.clear_scene()
    objects = BAKE.import_tree(args.glb)
    source_classification = BAKE.classify_objects(objects)
    variation_log = apply_variation(
        objects,
        source_classification,
        variant,
        variation_profile["axis"],
        variation_profile["attachment"],
    )

    BAKE.normalize_tree(
        objects,
        yaw_degrees,
        root_embed_fraction,
        float(bake_profile["planting"]["max_root_embed_fraction"]),
    )
    classification = BAKE.classify_objects(objects)
    corners = BAKE.all_world_corners(objects)
    min_z = min(c.z for c in corners)
    max_z = max(c.z for c in corners)
    camera_target_z = min_z + (max_z - min_z) * float(bake_profile["camera"]["target_z_fraction"])
    camera, _sun = BAKE.setup_render(frame_size, camera_target_z, sun_angle_degrees, bake_profile)
    anchor = BAKE.fit_camera_to_objects(camera, objects, bake_profile)

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for layer, file_name in (("all", "albedo.png"), ("trunk", "trunk.png"), ("foliage", "foliage.png")):
        BAKE.set_layer_visibility(objects, classification, layer)
        BAKE.render_png(out_dir / file_name)

    BAKE.set_layer_visibility(objects, classification, "all")
    BAKE.setup_shadow_scene(objects, sun_angle_degrees, bake_profile)
    BAKE.render_png(out_dir / "shadow_raw.png")

    metadata = {
        "source_glb": str(args.glb),
        "frame_width": frame_size,
        "frame_height": frame_size,
        "anchor": list(anchor),
        "yaw_degrees": yaw_degrees,
        "sun_angle_degrees": sun_angle_degrees,
        "root_embed_fraction": root_embed_fraction,
        "bake_profile": BAKE.bake_profile_summary(bake_profile, frame_size, sun_angle_degrees, root_embed_fraction),
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

    # The canonical camera fits every asset to the same frame fraction, so the
    # baked sprite alone cannot say how tall this variation actually is. Record
    # the world framing so consumers and proof sheets can restore true scale.
    baked_corners = BAKE.all_world_corners(objects)
    world_bbox = {
        "min": [min(c[i] for c in baked_corners) for i in range(3)],
        "max": [max(c[i] for c in baked_corners) for i in range(3)],
    }
    ortho_scale = float(camera.data.ortho_scale)
    variation_metadata = {
        "variation_profile_id": variation_profile["profile_id"],
        "variation_profile_version": variation_profile["version"],
        "variant": variant,
        "applied": variation_log,
        "framing": {
            "ortho_scale": ortho_scale,
            "pixels_per_world_unit": frame_size / ortho_scale,
            "world_bbox": world_bbox,
            "world_height": world_bbox["max"][2] - world_bbox["min"][2],
        },
    }
    with (out_dir / "variation.json").open("w", encoding="utf-8") as fh:
        json.dump(variation_metadata, fh, indent="\t", ensure_ascii=False)

    print(f"Wrote variation {variant['id']} render source to {out_dir}")


if __name__ == "__main__":
    main()
