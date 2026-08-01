"""Strictly process and pack one physically rendered player shadow clip.

The Blender pass writes transparent Cycles shadow-catcher frames at 304x192.
This tool applies the same alpha cleanup and [15, 11, 7] tint as the layered
tree pipeline, downsamples exactly 4x, proves the fixed south-east cast and loop
seam, then packs a separate 16x16 shadow atlas.  There is intentionally no fake
silhouette fallback: an invalid physical render fails the bake.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_PROFILE = TOOL_DIR / "player_bake_profile.json"
FIXED_SHADOW_DIRECTION = (0.887216, 0.461354)
ALPHA_STRONG_THRESHOLD = 8
MIN_OUTPUT_MARGIN_PX = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip_id")
    parser.add_argument("frames_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--preview-dir", type=Path, default=None)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def cleaned_shadow_alpha(
    raw_shadow: Image.Image,
    bake_profile: dict,
    minimum_source_margin_px: int,
) -> tuple[Image.Image, int]:
    """Return the strict real shadow-catcher alpha and selected threshold."""
    raw_alpha = raw_shadow.convert("RGBA").getchannel("A")
    cleaned = None
    selected_threshold = -1
    for threshold in bake_profile["postprocess"]["processed_shadow_thresholds"]:
        thresholded = raw_alpha.point(lambda value, t=threshold: 255 if value > t else 0, "L")
        bbox = thresholded.getbbox()
        if bbox is None:
            continue
        bbox_coverage = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / float(
            raw_alpha.width * raw_alpha.height
        )
        # A nearly full-frame rectangle is the catcher plane, not a usable cast.
        if bbox_coverage > 0.72:
            continue
        margins = (bbox[0], bbox[1], raw_alpha.width - bbox[2], raw_alpha.height - bbox[3])
        if min(margins) < minimum_source_margin_px:
            continue
        cleaned = raw_alpha.point(
            lambda value, t=threshold: 0 if value <= t else min(int((value - t) * 1.55), 205),
            "L",
        )
        selected_threshold = int(threshold)
        break
    if cleaned is None:
        raise ValueError("raw shadow-catcher alpha is empty or resolves to the whole catcher plane")
    alpha = cleaned.filter(ImageFilter.GaussianBlur(1.8))
    alpha = alpha.point(lambda value: 0 if value < 2 else min(int(value * 1.08), 215), "L")
    return alpha, selected_threshold


def colorized_shadow(alpha: Image.Image, bake_profile: dict) -> Image.Image:
    rgb = tuple(int(value) for value in bake_profile["postprocess"]["shadow_rgb"])
    return Image.merge(
        "RGBA",
        (
            Image.new("L", alpha.size, rgb[0]),
            Image.new("L", alpha.size, rgb[1]),
            Image.new("L", alpha.size, rgb[2]),
            alpha,
        ),
    )


def translated_rgba(
    image: Image.Image,
    offset: tuple[int, int],
    target_size: tuple[int, int],
) -> Image.Image:
    """Apply an integer crop-window correction without interpolation or wrap."""
    source = image.convert("RGBA")
    if offset == (0, 0) and source.size == target_size:
        return source
    shifted = Image.new("RGBA", target_size, (0, 0, 0, 0))
    shifted.paste(source, offset)
    return shifted


def strong_bbox(alpha: Image.Image) -> tuple[int, int, int, int] | None:
    return alpha.point(lambda value: 255 if value > ALPHA_STRONG_THRESHOLD else 0, "L").getbbox()


def border_max(alpha: Image.Image) -> int:
    width, height = alpha.size
    border = []
    border.extend(alpha.crop((0, 0, width, 1)).get_flattened_data())
    border.extend(alpha.crop((0, height - 1, width, height)).get_flattened_data())
    border.extend(alpha.crop((0, 0, 1, height)).get_flattened_data())
    border.extend(alpha.crop((width - 1, 0, width, height)).get_flattened_data())
    return max(border, default=0)


def alpha_metrics(alpha: Image.Image, anchor: tuple[float, float]) -> dict:
    bbox = strong_bbox(alpha)
    if bbox is None:
        raise ValueError("processed shadow has no alpha above the strong threshold")
    width, height = alpha.size
    margins = [bbox[0], bbox[1], width - bbox[2], height - bbox[3]]
    if min(margins) < MIN_OUTPUT_MARGIN_PX:
        raise ValueError(
            f"processed shadow strong-alpha bbox {bbox} has margins {margins}; "
            f"minimum is {MIN_OUTPUT_MARGIN_PX}px"
        )
    edge_alpha = border_max(alpha)
    if edge_alpha != 0:
        raise ValueError(f"processed shadow leaks alpha {edge_alpha} onto the tile border")

    pixels = list(alpha.get_flattened_data())
    total = float(sum(pixels))
    if total <= 0.0:
        raise ValueError("processed shadow has zero weighted alpha")
    centroid_x = sum((index % width) * value for index, value in enumerate(pixels)) / total
    centroid_y = sum((index // width) * value for index, value in enumerate(pixels)) / total
    delta_x = centroid_x - anchor[0]
    delta_y = centroid_y - anchor[1]
    if delta_x <= 0.0 or delta_y <= 0.0:
        raise ValueError(
            f"shadow centroid ({centroid_x:.2f}, {centroid_y:.2f}) is not south-east "
            f"of anchor ({anchor[0]:.2f}, {anchor[1]:.2f})"
        )
    length = math.hypot(delta_x, delta_y)
    dot = (delta_x * FIXED_SHADOW_DIRECTION[0] + delta_y * FIXED_SHADOW_DIRECTION[1]) / length
    angle_error = math.degrees(math.acos(max(-1.0, min(1.0, dot))))
    if angle_error > 30.0:
        raise ValueError(f"shadow centroid angle error {angle_error:.2f} degrees exceeds 30 degrees")

    return {
        "strong_alpha_bbox": list(bbox),
        "margins_px": margins,
        "border_alpha_max": edge_alpha,
        "alpha_max": max(pixels),
        "alpha_coverage": round(sum(1 for value in pixels if value > ALPHA_STRONG_THRESHOLD) / len(pixels), 6),
        "weighted_centroid_px": [round(centroid_x, 4), round(centroid_y, 4)],
        "anchor_to_centroid_px": [round(delta_x, 4), round(delta_y, 4)],
        "centroid_direction_error_degrees": round(angle_error, 4),
    }


def visual_rgba(image: Image.Image) -> Image.Image:
    red, green, blue, alpha = image.convert("RGBA").split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def frame_delta(first: Image.Image, second: Image.Image) -> float:
    difference = ImageChops.difference(first, second)
    means = ImageStat.Stat(difference).mean
    return sum(means) / (len(means) * 255.0)


def loop_seam_report(direction_frames: dict[int, list[Image.Image]]) -> dict:
    internal_steps = []
    seam_steps = []
    direction_ratios = []
    for direction in sorted(direction_frames):
        frames = [visual_rgba(frame) for frame in direction_frames[direction]]
        internal = [frame_delta(frames[index], frames[index + 1]) for index in range(len(frames) - 1)]
        seam = frame_delta(frames[-1], frames[0])
        internal_median = statistics.median(internal)
        ratio = seam / internal_median if internal_median > 0.0 else (0.0 if seam == 0.0 else math.inf)
        internal_steps.extend(internal)
        seam_steps.append(seam)
        direction_ratios.append(ratio)
    internal_median = statistics.median(internal_steps)
    seam_median = statistics.median(seam_steps)
    return {
        "internal_step_median": round(internal_median, 8),
        "internal_step_max": round(max(internal_steps), 8),
        "seam_median": round(seam_median, 8),
        "seam_max": round(max(seam_steps), 8),
        "median_seam_to_internal_median": round(
            seam_median / internal_median if internal_median > 0.0 else math.inf,
            5,
        ),
        "direction_seam_ratio_median": round(statistics.median(direction_ratios), 5),
        "direction_seam_ratio_max": round(max(direction_ratios), 5),
        "worst_direction": int(max(range(len(direction_ratios)), key=direction_ratios.__getitem__)),
    }


def write_cardinal_loop_preview(
    path: Path,
    direction_frames: dict[int, list[Image.Image]],
    frame_count: int,
) -> None:
    labels = ((0, "N / row 0"), (4, "E / row 4"), (8, "S / row 8"), (12, "W / row 12"))
    scale = 4
    tile_w, tile_h = next(iter(direction_frames.values()))[0].size
    header_h = 24
    frames = []
    for frame_index in range(frame_count):
        sheet = Image.new("RGB", (tile_w * scale * 4, tile_h * scale + header_h), (184, 166, 137))
        draw = ImageDraw.Draw(sheet)
        for column, (direction, label) in enumerate(labels):
            tile = direction_frames[direction][frame_index].resize(
                (tile_w * scale, tile_h * scale), Image.Resampling.BILINEAR
            )
            backdrop = Image.new("RGBA", tile.size, (184, 166, 137, 255))
            composed = Image.alpha_composite(backdrop, tile).convert("RGB")
            x = column * tile_w * scale
            sheet.paste(composed, (x, header_h))
            draw.text((x + 6, 5), label, fill=(35, 27, 19))
        frames.append(sheet)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=125, loop=0, disposal=2)


def write_composite_cardinal_loop(
    path: Path,
    direction_frames: dict[int, list[Image.Image]],
    albedo_atlas_path: Path,
    albedo_metadata: dict,
    shadow_anchor: tuple[float, float],
    frame_count: int,
) -> None:
    if not albedo_atlas_path.is_file():
        return
    labels = ((0, "N"), (4, "E"), (8, "S"), (12, "W"))
    albedo = Image.open(albedo_atlas_path).convert("RGBA")
    albedo_w = int(albedo_metadata["frame_width_px"])
    albedo_h = int(albedo_metadata["frame_height_px"])
    albedo_anchor_uv = albedo_metadata["foot_anchor_uv"]
    albedo_anchor = (float(albedo_anchor_uv[0]) * albedo_w, float(albedo_anchor_uv[1]) * albedo_h)
    panel_w, panel_h = 360, 320
    world_anchor = (96, 238)
    animation = []
    for frame_index in range(frame_count):
        sheet = Image.new("RGB", (panel_w * 4, panel_h), (184, 166, 137))
        draw = ImageDraw.Draw(sheet)
        for column, (direction, label) in enumerate(labels):
            panel = Image.new("RGBA", (panel_w, panel_h), (184, 166, 137, 255))
            shadow = direction_frames[direction][frame_index].resize(
                (direction_frames[direction][frame_index].width * 4, direction_frames[direction][frame_index].height * 4),
                Image.Resampling.BILINEAR,
            )
            shadow_xy = (
                int(round(world_anchor[0] - shadow_anchor[0] * 4.0)),
                int(round(world_anchor[1] - shadow_anchor[1] * 4.0)),
            )
            panel.alpha_composite(shadow, shadow_xy)
            albedo_tile = albedo.crop(
                (
                    frame_index * albedo_w,
                    direction * albedo_h,
                    (frame_index + 1) * albedo_w,
                    (direction + 1) * albedo_h,
                )
            )
            albedo_xy = (
                int(round(world_anchor[0] - albedo_anchor[0])),
                int(round(world_anchor[1] - albedo_anchor[1])),
            )
            panel.alpha_composite(albedo_tile, albedo_xy)
            x = column * panel_w
            sheet.paste(panel.convert("RGB"), (x, 0))
            draw.text((x + 8, 7), f"{label} / row {direction}", fill=(35, 27, 19))
            draw.ellipse(
                (
                    x + world_anchor[0] - 2,
                    world_anchor[1] - 2,
                    x + world_anchor[0] + 2,
                    world_anchor[1] + 2,
                ),
                fill=(211, 60, 36),
            )
        animation.append(sheet)
    animation[0].save(
        path,
        save_all=True,
        append_images=animation[1:],
        duration=125,
        loop=0,
        disposal=2,
    )


def main() -> None:
    args = parse_args()
    profile = load_json(args.profile.resolve())
    bake_profile = load_json((TOOL_DIR.parent.parent / profile["inherits_bake_profile"]).resolve())
    clip = next((item for item in profile["clips"] if item["clip_id"] == args.clip_id), None)
    if clip is None:
        raise SystemExit(f"Clip id '{args.clip_id}' is not declared in {args.profile}")

    frames_dir = args.frames_dir.resolve()
    summary_path = frames_dir / f"{args.clip_id}_shadow_render_summary.json"
    if not summary_path.is_file():
        raise SystemExit(f"Missing shadow bake summary: {summary_path}")
    summary = load_json(summary_path)
    shadow_profile = profile["shadow"]
    source_w = int(shadow_profile["source_width_px"])
    source_h = int(shadow_profile["source_height_px"])
    output_w = int(shadow_profile["output_width_px"])
    output_h = int(shadow_profile["output_height_px"])
    downsample = int(shadow_profile["downsample_factor"])
    if (source_w, source_h) != (output_w * downsample, output_h * downsample):
        raise SystemExit("Shadow source/output dimensions do not match the declared integer downsample")
    directions = int(summary["directions"])
    frame_count = int(summary["frames_per_direction"])
    if directions != int(profile["grid"]["directions"]) or frame_count != int(profile["grid"]["frames_per_direction"]):
        raise SystemExit("Shadow bake grid does not match the player profile")

    source_anchor = tuple(float(value) for value in shadow_profile["source_anchor_px"])
    output_anchor = (source_anchor[0] / downsample, source_anchor[1] / downsample)
    rendered_anchor_raw = summary.get("anchor", {}).get("projected_world_origin_px", source_anchor)
    rendered_anchor = tuple(float(value) for value in rendered_anchor_raw)
    rendered_source_size = (
        int(summary.get("source_frame_width_px", source_w)),
        int(summary.get("source_frame_height_px", source_h)),
    )
    reframe_offset_float = (
        source_anchor[0] - rendered_anchor[0],
        source_anchor[1] - rendered_anchor[1],
    )
    reframe_offset = (round(reframe_offset_float[0]), round(reframe_offset_float[1]))
    if abs(reframe_offset[0] - reframe_offset_float[0]) > 1e-4 \
            or abs(reframe_offset[1] - reframe_offset_float[1]) > 1e-4:
        raise SystemExit(
            f"Shadow source reframe must be integer pixels, got {reframe_offset_float}"
        )
    if abs(reframe_offset[0]) >= source_w or abs(reframe_offset[1]) >= source_h:
        raise SystemExit(f"Shadow source reframe {reframe_offset} would discard the whole frame")
    processed_dir = frames_dir / "processed"
    processed_dir.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (output_w * frame_count, output_h * directions), (0, 0, 0, 0))
    direction_frames: dict[int, list[Image.Image]] = {}
    frame_metrics = []
    selected_thresholds = []
    for direction in range(directions):
        tiles = []
        for frame_index in range(frame_count):
            name = f"{args.clip_id}_shadow_raw_dir{direction:02d}_frame{frame_index:02d}.png"
            path = frames_dir / name
            if not path.is_file():
                raise SystemExit(f"Missing physical shadow frame: {path}")
            with Image.open(path) as raw:
                if raw.size != rendered_source_size:
                    raise SystemExit(f"{name} is {raw.size}, expected rendered size {rendered_source_size}")
                reframed = translated_rgba(raw, reframe_offset, (source_w, source_h))
                try:
                    base_alpha, selected_threshold = cleaned_shadow_alpha(
                        reframed,
                        bake_profile,
                        MIN_OUTPUT_MARGIN_PX * downsample,
                    )
                except ValueError as error:
                    raise SystemExit(f"{name}: {error}") from error
            small_alpha = base_alpha.resize((output_w, output_h), Image.Resampling.LANCZOS)
            small_alpha = small_alpha.point(lambda value: 0 if value < 2 else min(value, 215), "L")
            try:
                metrics = alpha_metrics(small_alpha, output_anchor)
            except ValueError as error:
                raise SystemExit(f"{name}: {error}") from error
            tile = colorized_shadow(small_alpha, bake_profile)
            processed_name = f"{args.clip_id}_shadow_dir{direction:02d}_frame{frame_index:02d}.png"
            tile.save(processed_dir / processed_name)
            atlas.paste(tile, (frame_index * output_w, direction * output_h))
            tiles.append(tile)
            selected_thresholds.append(selected_threshold)
            frame_metrics.append({"direction": direction, "frame_index": frame_index, **metrics})
        direction_frames[direction] = tiles

    loop_report = None
    if bool(clip.get("loop", False)):
        loop_report = loop_seam_report(direction_frames)
        validation = profile["loop_validation"]
        direction_limit = float(validation["pixel_seam_to_direction_median_max"])
        median_limit = float(validation["pixel_median_seam_to_internal_median_max"])
        if loop_report["direction_seam_ratio_max"] > direction_limit:
            raise SystemExit(
                f"{args.clip_id} shadow loop seam ratio {loop_report['direction_seam_ratio_max']:.3f} "
                f"at row {loop_report['worst_direction']} exceeds {direction_limit:.3f}"
            )
        if loop_report["median_seam_to_internal_median"] > median_limit:
            raise SystemExit(
                f"{args.clip_id} shadow median loop seam ratio "
                f"{loop_report['median_seam_to_internal_median']:.3f} exceeds {median_limit:.3f}"
            )

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"player_{args.clip_id}_shadow_{directions}dir_{frame_count}frames"
    atlas_path = output_dir / f"{stem}.png"
    atlas.save(atlas_path)
    min_margins = [min(metrics["margins_px"][side] for metrics in frame_metrics) for side in range(4)]
    max_angle_error = max(metrics["centroid_direction_error_degrees"] for metrics in frame_metrics)
    median_angle_error = statistics.median(
        metrics["centroid_direction_error_degrees"] for metrics in frame_metrics
    )
    metadata = {
        "asset_kind": "baked_player_sun_shadow",
        "clip_id": args.clip_id,
        "spec": profile["spec"],
        "atlas": atlas_path.name,
        "albedo_atlas": f"player_{args.clip_id}_{directions}dir_{frame_count}frames.png",
        "directions": directions,
        "frames_per_direction": frame_count,
        "frame_width_px": output_w,
        "frame_height_px": output_h,
        "atlas_width_px": atlas.width,
        "atlas_height_px": atlas.height,
        "source_frame_width_px": source_w,
        "source_frame_height_px": source_h,
        "downsample_factor": downsample,
        "rendered_source_anchor_px": [round(rendered_anchor[0], 5), round(rendered_anchor[1], 5)],
        "rendered_source_frame_size_px": list(rendered_source_size),
        "source_reframe_offset_px": list(reframe_offset),
        "shadow_anchor_px": [round(output_anchor[0], 5), round(output_anchor[1], 5)],
        "shadow_anchor_uv": [round(output_anchor[0] / output_w, 6), round(output_anchor[1] / output_h, 6)],
        "albedo_anchor_uv": summary["albedo_anchor_uv"],
        "direction_zero": profile["grid"]["direction_zero"],
        "direction_order": profile["grid"]["direction_order"],
        "direction_yaw_degrees": summary["direction_yaw_degrees"],
        "sampled_source_frames": summary["sampled_source_frames"],
        "source_frame_start": summary["source_frame_start"],
        "source_frame_end": summary["source_frame_end"],
        "loop": bool(clip.get("loop", False)),
        "loop_pixel_seam": loop_report,
        "render_mode": "cycles_shadow_catcher",
        "inherits_bake_profile": profile["inherits_bake_profile"],
        "camera_elevation_degrees": summary["camera_elevation_degrees"],
        "sun_azimuth_degrees": summary["sun_azimuth_degrees"],
        "shadow_sun_elevation_degrees": summary["shadow_sun_elevation_degrees"],
        "shadow_sun_energy": summary["shadow_sun_energy"],
        "cycles_samples": summary["cycles_samples"],
        "denoising": summary["denoising"],
        "fixed_shadow_direction": bake_profile["lighting"]["fixed_shadow_direction"],
        "fixed_shadow_direction_vector": list(FIXED_SHADOW_DIRECTION),
        "shadow_rgb": bake_profile["postprocess"]["shadow_rgb"],
        "alpha_max": max(metrics["alpha_max"] for metrics in frame_metrics),
        "min_margins_px": min_margins,
        "border_alpha_max": max(metrics["border_alpha_max"] for metrics in frame_metrics),
        "centroid_direction_error_degrees_median": round(median_angle_error, 4),
        "centroid_direction_error_degrees_max": round(max_angle_error, 4),
        "selected_raw_alpha_thresholds": sorted(set(selected_thresholds)),
        "frames_rendered": len(frame_metrics),
    }
    (output_dir / f"{stem}.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    preview_dir = (args.preview_dir or frames_dir.parent).resolve()
    preview_dir.mkdir(parents=True, exist_ok=True)
    write_cardinal_loop_preview(
        preview_dir / f"{stem}_cardinal_loop.gif",
        direction_frames,
        frame_count,
    )
    albedo_metadata_path = output_dir / f"player_{args.clip_id}_{directions}dir_{frame_count}frames.json"
    if albedo_metadata_path.is_file():
        albedo_metadata = load_json(albedo_metadata_path)
        write_composite_cardinal_loop(
            preview_dir / f"{stem}_composite_cardinal_loop.gif",
            direction_frames,
            output_dir / metadata["albedo_atlas"],
            albedo_metadata,
            output_anchor,
            frame_count,
        )

    print("PLAYER_SHADOW_ATLAS_ASSEMBLED")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
