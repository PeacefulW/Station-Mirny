#!/usr/bin/env python3
"""Build the authored, bounded atlas pack consumed by RenderClassRegistry.

This is an offline asset task. Runtime code reads the generated JSON and small
metadata LUTs; it never scans source images or assembles family textures.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
STATIC_OUT = ROOT / "assets/sprites/world_render/static"
ACTOR_OUT = ROOT / "assets/sprites/world_render/actors"
SYNTHETIC_OUT = ROOT / "assets/sprites/world_render/synthetic"
DATA_OUT = ROOT / "data/world_render"

PASS_GROUND = 1
PASS_BODY = 2
PASS_SHADOW = 4
PASS_EMISSIVE = 8
PASS_OVERHEAD = 16

FLAG_LAYERED = 1
FLAG_SEASONAL_SIMPLE = 2
FLAG_ACTOR = 4
FLAG_WIND = 8
FLAG_CUTOUT = 16
FLAG_GROUND = 32

STATIC_SIZE = (7776, 960)
STATIC_RECTS = {
    "layered_tree": (0, 0, 6144, 768),
    "grass_tuft": (6144, 0, 640, 960),
    "layered_bush": (6784, 0, 512, 128),
    "small_rock": (7296, 0, 480, 480),
}

TREE_DIRS = [
    f"assets/sprites/flora/layered_trees/rust_crown_{index:02d}"
    for index in range(1, 9)
]
ROCK_DIRS = [
    f"assets/sprites/decor/plains/layered_small_rocks/small_rock_{index:02d}"
    for index in range(1, 23)
]
BUSH_DIRS = ["assets/sprites/flora/layered_bushes/alien_bush_01"]


def _rgba(path: str | Path) -> Image.Image:
    with Image.open(ROOT / path) as source:
        return source.convert("RGBA")


def _save_channel(name: str, sources: Iterable[tuple[str, str]]) -> None:
    output = Image.new("RGBA", STATIC_SIZE, (0, 0, 0, 0))
    for family_id, source_path in sources:
        source = _rgba(source_path)
        x, y, width, height = STATIC_RECTS[family_id]
        if source.size != (width, height):
            raise ValueError(
                f"{source_path}: expected {(width, height)}, got {source.size}"
            )
        output.alpha_composite(source, (x, y))
    output.save(STATIC_OUT / f"{name}.png", optimize=True)


def _build_static_atlases() -> None:
    STATIC_OUT.mkdir(parents=True, exist_ok=True)
    tree = "assets/sprites/flora/atlases/layered_trees"
    bush = "assets/sprites/flora/atlases/layered_bushes"
    rock = "assets/sprites/decor/atlases/layered_small_rocks"
    grass = "assets/textures/world/biomes/plains/flora"
    channel_sources = {
        "body_base": [
            ("layered_tree", f"{tree}/trunk.png"),
            ("grass_tuft", f"{grass}/grass_tuft_atlas.png"),
            ("layered_bush", f"{bush}/trunk.png"),
            ("small_rock", f"{rock}/albedo.png"),
        ],
        "foliage": [
            ("layered_tree", f"{tree}/foliage.png"),
            ("layered_bush", f"{bush}/foliage.png"),
        ],
        "snow_overlay": [
            ("layered_tree", f"{tree}/snow_overlay.png"),
            ("layered_bush", f"{bush}/snow_overlay.png"),
            ("small_rock", f"{rock}/snow_overlay.png"),
        ],
        "wind_mask": [
            ("layered_tree", f"{tree}/wind_mask.png"),
            ("layered_bush", f"{bush}/wind_mask.png"),
        ],
        "snow_mask": [
            ("layered_tree", f"{tree}/snow_mask.png"),
            ("layered_bush", f"{bush}/snow_mask.png"),
            ("small_rock", f"{rock}/snow_mask.png"),
        ],
        "season_mask": [
            ("layered_tree", f"{tree}/season_mask.png"),
            ("layered_bush", f"{bush}/season_mask.png"),
        ],
        "shadow": [
            ("layered_tree", f"{tree}/shadow.png"),
            ("grass_tuft", f"{grass}/grass_tuft_shadow_atlas.png"),
            ("layered_bush", f"{bush}/shadow.png"),
            ("small_rock", f"{rock}/shadow.png"),
        ],
        # Fixed optional passes always bind a valid authored texture. Production
        # descriptors do not opt into either pass yet, so these start transparent
        # and can gain content without changing renderer source or material count.
        "emissive": [],
        "overhead": [],
    }
    for name, sources in channel_sources.items():
        _save_channel(name, sources)


def _build_actor_atlases() -> list[dict[str, Any]]:
    ACTOR_OUT.mkdir(parents=True, exist_ok=True)
    clips = [
        ("player_idle", "player_idle_16dir_16frames.png"),
        ("player_run_forward", "player_run_forward_16dir_16frames.png"),
        ("player_run_backward", "player_run_backward_16dir_16frames.png"),
        ("player_strafe_left", "player_strafe_left_16dir_16frames.png"),
        ("player_strafe_right", "player_strafe_right_16dir_16frames.png"),
    ]
    body_size = (9984, 9216)
    shadow_size = (3648, 1536)
    body_positions = [(0, 0), (3328, 0), (6656, 0), (0, 4608), (3328, 4608)]
    shadow_positions = [(0, 0), (1216, 0), (2432, 0), (0, 768), (1216, 768)]
    body_output = Image.new("RGBA", body_size, (0, 0, 0, 0))
    shadow_output = Image.new("RGBA", shadow_size, (0, 0, 0, 0))
    descriptors: list[dict[str, Any]] = []
    for clip_index, ((clip_id, body_name), body_position, shadow_position) in enumerate(
        zip(clips, body_positions, shadow_positions)
    ):
        shadow_name = body_name.replace("_16dir_16frames.png", "_shadow_16dir_16frames.png")
        body = _rgba(Path("assets/sprites/player") / body_name)
        shadow = _rgba(Path("assets/sprites/player") / shadow_name)
        if body.size != (3328, 4608) or shadow.size != (1216, 768):
            raise ValueError(f"Unexpected player atlas dimensions for {clip_id}")
        body_output.alpha_composite(body, body_position)
        shadow_output.alpha_composite(shadow, shadow_position)
        descriptors.append(
            {
                "id": clip_id,
                "descriptor_id": 4 + clip_index,
                "flags": FLAG_ACTOR | FLAG_CUTOUT,
                "passes": PASS_BODY | PASS_SHADOW,
                "atlas_layout": [16, 16, 256],
                "body_rect_px": [*body_position, *body.size],
                "shadow_rect_px": [*shadow_position, *shadow.size],
                "frame_size_px": [208, 288],
                "shadow_frame_size_px": [76, 48],
                "wind_strength_px": 0.0,
                "render_crops": [[0.0, 0.0, 1.0, 1.0] for _ in range(256)],
                "anchors": [[0.5, 0.5] for _ in range(256)],
            }
        )
    body_output.save(ACTOR_OUT / "player_body.png", optimize=True)
    shadow_output.save(ACTOR_OUT / "player_shadow.png", optimize=True)
    return descriptors


def _read_metadata(source_dirs: list[str], fixed_scale: float, collision: bool) -> tuple[list[float], list[list[float]], list[list[float]]]:
    metrics: list[float] = []
    crops: list[list[float]] = []
    anchors: list[list[float]] = []
    padding = 12.0 if collision else (2.0 if "small_rock" in source_dirs[0] else 4.0)
    for source_dir in source_dirs:
        metadata = json.loads((ROOT / source_dir / "meta.json").read_text(encoding="utf-8"))
        width = float(metadata["frame_width"])
        height = float(metadata["frame_height"])
        anchor_x, anchor_y = (float(value) for value in metadata["anchor"][:2])
        alpha_x, alpha_y, alpha_width, alpha_height = (
            float(value) for value in metadata["alpha_bbox"][:4]
        )
        metrics.extend(
            [width, height, anchor_x, anchor_y, fixed_scale if fixed_scale > 0 else alpha_width]
        )
        if collision:
            footprint = metadata["collision_footprint"]
            metrics.extend(
                [
                    float(footprint.get("offset_x_px", 0.0)),
                    float(footprint["width_px"]),
                    float(footprint["depth_px"]),
                ]
            )
        minimum_x = max(0.0, alpha_x - padding)
        minimum_y = max(0.0, alpha_y - padding)
        maximum_x = min(width, alpha_x + alpha_width + padding)
        maximum_y = min(height, alpha_y + alpha_height + padding)
        crops.append(
            [
                minimum_x / width,
                minimum_y / height,
                max(1.0, maximum_x - minimum_x) / width,
                max(1.0, maximum_y - minimum_y) / height,
            ]
        )
        anchors.append([anchor_x / width, anchor_y / height])
    return metrics, crops, anchors


def _grass_crops() -> list[list[float]]:
    atlas = _rgba("assets/textures/world/biomes/plains/flora/grass_tuft_atlas.png")
    columns, rows, frame_count = 4, 8, 32
    frame_width = atlas.width // columns
    frame_height = atlas.height // rows
    alpha = atlas.getchannel("A")
    crops: list[list[float]] = []
    for frame_index in range(frame_count):
        cell_x = frame_index % columns
        cell_y = frame_index // columns
        frame_alpha = alpha.crop(
            (
                cell_x * frame_width,
                cell_y * frame_height,
                (cell_x + 1) * frame_width,
                (cell_y + 1) * frame_height,
            )
        )
        bbox = frame_alpha.point(lambda value: 255 if value > 0 else 0).getbbox()
        if bbox is None:
            minimum_y, maximum_y = 0, frame_height - 1
        else:
            minimum_y = max(0, bbox[1] - 2)
            maximum_y = min(frame_height - 1, bbox[3] - 1 + 2)
        crops.append(
            [0.0, minimum_y / frame_height, 1.0, (maximum_y - minimum_y + 1) / frame_height]
        )
    return crops


def _grass_shadow_crops() -> list[list[float]]:
    atlas = _rgba("assets/textures/world/biomes/plains/flora/grass_tuft_shadow_atlas.png")
    columns, rows, frame_count = 4, 8, 32
    frame_width = atlas.width // columns
    frame_height = atlas.height // rows
    alpha = atlas.getchannel("A")
    crops: list[list[float]] = []
    for frame_index in range(frame_count):
        cell_x = frame_index % columns
        cell_y = frame_index // columns
        frame_alpha = alpha.crop(
            (
                cell_x * frame_width,
                cell_y * frame_height,
                (cell_x + 1) * frame_width,
                (cell_y + 1) * frame_height,
            )
        )
        bbox = frame_alpha.point(lambda value: 255 if value > 0 else 0).getbbox()
        if bbox is None:
            crops.append([0.0, 0.0, 1.0, 1.0])
            continue
        minimum_x = max(0, bbox[0] - 2)
        minimum_y = max(0, bbox[1] - 2)
        maximum_x = min(frame_width, bbox[2] + 2)
        maximum_y = min(frame_height, bbox[3] + 2)
        crops.append(
            [
                minimum_x / frame_width,
                minimum_y / frame_height,
                (maximum_x - minimum_x) / frame_width,
                (maximum_y - minimum_y) / frame_height,
            ]
        )
    return crops


def _packed_variant_rects(
    family_id: str,
    layout: tuple[int, int, int],
    source_crops: list[list[float]],
) -> list[list[float]]:
    """Resolve a regular family grid to per-variant UV rectangles offline."""
    atlas_width, atlas_height = STATIC_SIZE
    family_x, family_y, family_width, family_height = STATIC_RECTS[family_id]
    columns, rows, frame_count = layout
    rects: list[list[float]] = []
    for frame_index in range(frame_count):
        cell_x = frame_index % columns
        cell_y = frame_index // columns
        crop_x, crop_y, crop_width, crop_height = source_crops[frame_index]
        rects.append(
            [
                (family_x + (cell_x + crop_x) * family_width / columns) / atlas_width,
                (family_y + (cell_y + crop_y) * family_height / rows) / atlas_height,
                crop_width * family_width / columns / atlas_width,
                crop_height * family_height / rows / atlas_height,
            ]
        )
    return rects


def _static_descriptor(
    descriptor_id: int,
    family_id: str,
    layout: tuple[int, int, int],
    frame_size: tuple[int, int],
    flags: int,
    wind_strength: float,
    metrics: list[float],
    crops: list[list[float]],
    anchors: list[list[float]],
    metric_stride: int,
    result_set: str,
    buffer_key: str,
    geometry: str,
    shadow_source_crop: list[float],
    shadow_source_crops: list[list[float]] | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    resolved_shadow_crops = shadow_source_crops or [
        list(shadow_source_crop) for _ in range(layout[2])
    ]
    descriptor = {
        "id": family_id,
        "descriptor_id": descriptor_id,
        "flags": flags,
        "passes": PASS_GROUND | PASS_SHADOW if geometry == "south_edge" else PASS_BODY | PASS_SHADOW,
        "atlas_layout": list(layout),
        "body_rect_px": list(STATIC_RECTS[family_id]),
        "shadow_rect_px": list(STATIC_RECTS[family_id]),
        "frame_size_px": list(frame_size),
        "shadow_frame_size_px": list(frame_size),
        "wind_strength_px": wind_strength,
        "render_crops": crops,
        "anchors": anchors,
    }
    binding = {
        "id": family_id,
        "descriptor_id": descriptor_id,
        "result_set": result_set,
        "buffer_key": buffer_key,
        "geometry": geometry,
        "semantic_layer": 0 if geometry == "south_edge" else 10,
        "metric_stride": metric_stride,
        "metrics": metrics,
        "render_crops": crops,
        "shadow_source_crop": shadow_source_crop,
        "shadow_source_crops": resolved_shadow_crops,
        "compact_ground_shadow_rects": _packed_variant_rects(
            family_id, layout, resolved_shadow_crops
        ) if geometry == "south_edge" else [],
        "lod_scaled": geometry == "south_edge",
        "shadow_lod_scaled": geometry == "south_edge",
        "shadow_lod_start_fraction": 0.40 if geometry == "south_edge" else 0.0,
    }
    return descriptor, binding


def _build_registry(actor_descriptors: list[dict[str, Any]]) -> None:
    tree_metrics, tree_crops, tree_anchors = _read_metadata(TREE_DIRS, 0.64, True)
    rock_metrics, rock_crops, rock_anchors = _read_metadata(ROCK_DIRS, -1.0, False)
    bush_metrics, bush_crops, bush_anchors = _read_metadata(BUSH_DIRS, -1.0, False)
    grass_crops = _grass_crops()
    grass_shadow_crops = _grass_shadow_crops()
    static_specs = [
        _static_descriptor(
            0, "grass_tuft", (4, 8, 32), (160, 120), FLAG_GROUND | FLAG_CUTOUT | FLAG_WIND,
            0.0, [], grass_crops, [[0.5, 0.5] for _ in range(32)], 5,
            "grass", "bucket_buffers", "south_edge", [0.175, 0.0, 0.825, 1.0],
            grass_shadow_crops,
        ),
        _static_descriptor(
            1, "layered_tree", (8, 1, 8), (768, 768), FLAG_LAYERED | FLAG_WIND | FLAG_CUTOUT,
            3.0, tree_metrics, tree_crops, tree_anchors, 8,
            "objects", "tree_atlas_bucket_buffers", "anchored", [0.278646, 0.566406, 0.714844, 0.388021],
        ),
        _static_descriptor(
            2, "small_rock", (5, 5, 22), (96, 96), FLAG_SEASONAL_SIMPLE | FLAG_CUTOUT,
            0.0, rock_metrics, rock_crops, rock_anchors, 5,
            "objects", "rock_atlas_bucket_buffers", "anchored", [0.15625, 0.354167, 0.822917, 0.541667],
        ),
        _static_descriptor(
            3, "layered_bush", (4, 1, 1), (128, 128), FLAG_LAYERED | FLAG_WIND | FLAG_CUTOUT,
            1.2, bush_metrics, bush_crops, bush_anchors, 5,
            "objects", "bush_atlas_bucket_buffers", "anchored", [0.351563, 0.5625, 0.609375, 0.335938],
        ),
    ]
    registry = {
        "version": 2,
        "descriptor_capacity": 64,
        "variant_capacity": 256,
        "pass_capacity": 5,
        "page_capacity": 17,
        "instance_capacity": 1_048_576,
        "atlases": {
            "static_size_px": list(STATIC_SIZE),
            "body_base": "res://assets/sprites/world_render/static/body_base.png",
            "foliage": "res://assets/sprites/world_render/static/foliage.png",
            "snow_overlay": "res://assets/sprites/world_render/static/snow_overlay.png",
            "wind_mask": "res://assets/sprites/world_render/static/wind_mask.png",
            "snow_mask": "res://assets/sprites/world_render/static/snow_mask.png",
            "season_mask": "res://assets/sprites/world_render/static/season_mask.png",
            "shadow": "res://assets/sprites/world_render/static/shadow.png",
            "emissive": "res://assets/sprites/world_render/static/emissive.png",
            "overhead": "res://assets/sprites/world_render/static/overhead.png",
            "actor_body": "res://assets/sprites/world_render/actors/player_body.png",
            "actor_body_size_px": [9984, 9216],
            "actor_shadow": "res://assets/sprites/world_render/actors/player_shadow.png",
            "actor_shadow_size_px": [3648, 1536],
        },
        "passes": [
            {"id": "ground", "bit": PASS_GROUND, "blend": "mix"},
            {"id": "body", "bit": PASS_BODY, "blend": "mix"},
            {"id": "shadow", "bit": PASS_SHADOW, "blend": "mix"},
            {"id": "emissive", "bit": PASS_EMISSIVE, "blend": "add"},
            {"id": "overhead", "bit": PASS_OVERHEAD, "blend": "mix"},
        ],
        "descriptors": [descriptor for descriptor, _ in static_specs] + actor_descriptors,
        "source_bindings": [binding for _, binding in static_specs],
        "hard_bounds": {
            "max_texture_dimension_px": 16384,
            "max_descriptors": 64,
            "max_variants_per_descriptor": 256,
            "max_visible_instances": 1_048_576,
            "max_visible_actors": 4_096,
            "max_spore_instances": 1_048_576,
            "max_render_page_slots": 17,
            "max_fixed_passes": 5,
            "max_gpu_instance_payload_bytes": 1_048_576 * 16 * 4 * 5,
            "max_cpu_render_atom_bytes": 1_048_576 * 160,
            "max_cpu_sort_index_bytes": 1_048_576 * 8,
            "max_cpu_snapshot_working_set_bytes": 1_073_741_824,
        },
    }
    DATA_OUT.mkdir(parents=True, exist_ok=True)
    (DATA_OUT / "render_class_registry.json").write_text(
        json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def _build_synthetic_pack() -> None:
    SYNTHETIC_OUT.mkdir(parents=True, exist_ok=True)
    cell = 64
    family_count = 10
    variant_count = 10
    size = (variant_count * cell, family_count * cell)
    channels = {
        "body_base": Image.new("RGBA", size, (0, 0, 0, 0)),
        "foliage": Image.new("RGBA", size, (0, 0, 0, 0)),
        "emissive": Image.new("RGBA", size, (0, 0, 0, 0)),
        "overhead": Image.new("RGBA", size, (0, 0, 0, 0)),
        "shadow": Image.new("RGBA", size, (0, 0, 0, 0)),
    }
    for family in range(family_count):
        for variant in range(variant_count):
            x = variant * cell
            y = family * cell
            hue = ((family * 37 + variant * 11) % 255)
            body_draw = ImageDraw.Draw(channels["body_base"])
            body_draw.rounded_rectangle(
                (x + 10, y + 12, x + 54, y + 59),
                radius=8,
                fill=(55 + hue // 3, 80 + (hue * 2) % 150, 110 + hue // 4, 255),
            )
            shadow_draw = ImageDraw.Draw(channels["shadow"])
            shadow_draw.ellipse((x + 8, y + 44, x + 58, y + 61), fill=(0, 0, 0, 150))
            if family % 3 == 0:
                foliage_draw = ImageDraw.Draw(channels["foliage"])
                foliage_draw.ellipse(
                    (x + 5, y + 3, x + 59, y + 42),
                    fill=(40, 120 + hue // 4, 65, 235),
                )
            if family % 3 == 1:
                emissive_draw = ImageDraw.Draw(channels["emissive"])
                emissive_draw.ellipse((x + 24, y + 21, x + 40, y + 37), fill=(255, 190, 60, 230))
            if family in (5, 8):
                overhead_draw = ImageDraw.Draw(channels["overhead"])
                overhead_draw.polygon(
                    [(x + 32, y + 2), (x + 61, y + 31), (x + 32, y + 45), (x + 3, y + 31)],
                    fill=(130, 170, 210, 180),
                )
    for name, image in channels.items():
        image.save(SYNTHETIC_OUT / f"{name}.png", optimize=True)

    descriptors: list[dict[str, Any]] = []
    bindings: list[dict[str, Any]] = []
    for family in range(family_count):
        flags = FLAG_CUTOUT
        passes = PASS_BODY | PASS_SHADOW
        semantic = "opaque_cutout"
        if family % 3 == 0:
            flags |= FLAG_LAYERED | FLAG_WIND
            semantic = "foliage_wind"
        elif family % 3 == 1:
            passes |= PASS_EMISSIVE
            semantic = "emissive"
        if family in (5, 8):
            passes |= PASS_OVERHEAD
            semantic = "overhead"
        descriptors.append(
            {
                "id": f"synthetic_family_{family + 1:02d}",
                "descriptor_id": family,
                "semantic": semantic,
                "flags": flags,
                "passes": passes,
                "atlas_layout": [10, 1, 10],
                "body_rect_px": [0, family * cell, size[0], cell],
                "shadow_rect_px": [0, family * cell, size[0], cell],
                "frame_size_px": [cell, cell],
                "shadow_frame_size_px": [cell, cell],
                "wind_strength_px": 1.5 if flags & FLAG_WIND else 0.0,
                "render_crops": [[0.0, 0.0, 1.0, 1.0] for _ in range(variant_count)],
                "anchors": [[0.5, 0.92] for _ in range(variant_count)],
            }
        )
        metrics = []
        for _variant in range(variant_count):
            metrics.extend([64.0, 64.0, 32.0, 59.0, 44.0])
        bindings.append(
            {
                "id": f"synthetic_family_{family + 1:02d}",
                "descriptor_id": family,
                "result_set": "objects",
                "buffer_key": f"synthetic_family_{family + 1:02d}_bucket_buffers",
                "geometry": "anchored",
                "semantic_layer": 10,
                "metric_stride": 5,
                "metrics": metrics,
                "render_crops": [[0.0, 0.0, 1.0, 1.0] for _ in range(variant_count)],
                "shadow_source_crop": [0.05, 0.05, 0.9, 0.9],
                "lod_scaled": False,
            }
        )
    atlas_paths = {
        name: f"res://assets/sprites/world_render/synthetic/{name}.png"
        for name in channels
    }
    for count, suffix in ((9, "09"), (10, "10")):
        payload = {
            "version": 1,
            "purpose": "iteration_2_scale_proof",
            "family_count": count,
            "variants_per_family": variant_count,
            "atlas_size_px": list(size),
            "atlases": atlas_paths,
            "descriptors": descriptors[:count],
            "source_bindings": bindings[:count],
        }
        (DATA_OUT / f"synthetic_render_class_pack_{suffix}.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )


def main() -> None:
    _build_static_atlases()
    actor_descriptors = _build_actor_atlases()
    _build_registry(actor_descriptors)
    _build_synthetic_pack()
    print("world render class pack generated")


if __name__ == "__main__":
    main()
