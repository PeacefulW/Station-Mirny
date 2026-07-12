"""Build metrics and a before/after panel for the fixed-sun winter tree proof."""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

from PIL import Image, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline_dir", type=Path)
    parser.add_argument("candidate_dir", type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    return parser.parse_args()


def load_rgba(asset_dir: Path, name: str) -> Image.Image:
    return Image.open(asset_dir / name).convert("RGBA")


def mean_or_zero(values: list[float]) -> float:
    return statistics.fmean(values) if values else 0.0


def collect_metrics(asset_dir: Path) -> dict:
    classification = json.loads((asset_dir / "classification.json").read_text(encoding="utf-8"))
    anchor_x, anchor_y = (int(value) for value in classification["anchor"])
    trunk = load_rgba(asset_dir, "trunk.png")
    foliage = load_rgba(asset_dir, "foliage.png")
    overlay = load_rgba(asset_dir, "snow_overlay.png")
    shadow = load_rgba(asset_dir, "shadow.png")
    normal = load_rgba(asset_dir, "normal.png")
    trunk_alpha = trunk.getchannel("A")
    foliage_alpha = foliage.getchannel("A")
    overlay_alpha = overlay.getchannel("A")
    shadow_alpha = shadow.getchannel("A")
    overlay_luma = overlay.convert("L")

    visible_trunk_alpha: list[float] = []
    root_alpha: list[float] = []
    root_zone_64_alpha: list[float] = []
    foliage_snow_alpha: list[float] = []
    active_luma: list[float] = []
    north_west_luma: list[float] = []
    south_east_luma: list[float] = []
    normal_px = normal.load()
    for y in range(overlay.height):
        for x in range(overlay.width):
            snow_alpha = overlay_alpha.getpixel((x, y))
            trunk_value = trunk_alpha.getpixel((x, y))
            foliage_value = foliage_alpha.getpixel((x, y))
            if trunk_value > 48 and foliage_value < 20:
                normalized_alpha = snow_alpha / 255.0
                visible_trunk_alpha.append(normalized_alpha)
                if y >= anchor_y - 8:
                    root_alpha.append(normalized_alpha)
                if y >= anchor_y - 64:
                    root_zone_64_alpha.append(normalized_alpha)
            if foliage_value > 32:
                foliage_snow_alpha.append(snow_alpha / 255.0)
            if snow_alpha <= 32:
                continue
            luma = float(overlay_luma.getpixel((x, y)))
            active_luma.append(luma)
            red, green, _blue, _alpha = normal_px[x, y]
            nx = red / 127.5 - 1.0
            ny = green / 127.5 - 1.0
            facing = -(nx + ny) / math.sqrt(2.0)
            if facing >= 0.18:
                north_west_luma.append(luma)
            elif facing <= -0.18:
                south_east_luma.append(luma)

    total_shadow_alpha = 0
    weighted_x = 0
    weighted_y = 0
    for y in range(shadow.height):
        for x in range(shadow.width):
            value = shadow_alpha.getpixel((x, y))
            if value <= 8:
                continue
            total_shadow_alpha += value
            weighted_x += x * value
            weighted_y += y * value
    if total_shadow_alpha > 0:
        shadow_dx = weighted_x / total_shadow_alpha - anchor_x
        shadow_dy = weighted_y / total_shadow_alpha - anchor_y
        shadow_angle = math.degrees(math.atan2(shadow_dy, shadow_dx))
    else:
        shadow_dx = shadow_dy = shadow_angle = 0.0

    dark_foliage = sum(value <= 0.08 for value in foliage_snow_alpha)
    covered_foliage = sum(value >= 0.25 for value in foliage_snow_alpha)
    luma_range = max(active_luma) - min(active_luma) if active_luma else 0.0
    luma_stddev = statistics.pstdev(active_luma) if len(active_luma) > 1 else 0.0
    north_west_mean = mean_or_zero(north_west_luma)
    south_east_mean = mean_or_zero(south_east_luma)
    return {
        "asset_dir": str(asset_dir.resolve()),
        "source_glb": classification.get("source_glb", ""),
        "sun_angle_degrees": float(classification.get("sun_angle_degrees", 0.0)),
        "anchor": [anchor_x, anchor_y],
        "shadow_centroid_delta": [shadow_dx, shadow_dy],
        "shadow_screen_angle_degrees": shadow_angle,
        "visible_trunk_snow_alpha_mean": mean_or_zero(visible_trunk_alpha),
        "root_band_snow_alpha_mean": mean_or_zero(root_alpha),
        "root_zone_64_snow_alpha_mean": mean_or_zero(root_zone_64_alpha),
        "foliage_snow_alpha_mean": mean_or_zero(foliage_snow_alpha),
        "foliage_dark_gap_fraction": dark_foliage / max(len(foliage_snow_alpha), 1),
        "foliage_covered_fraction": covered_foliage / max(len(foliage_snow_alpha), 1),
        "active_snow_pixel_count": len(active_luma),
        "active_snow_luma_stddev": luma_stddev,
        "active_snow_luma_range": luma_range,
        "north_west_sample_count": len(north_west_luma),
        "south_east_sample_count": len(south_east_luma),
        "north_west_luma_mean": north_west_mean,
        "south_east_luma_mean": south_east_mean,
        "north_west_minus_south_east_luma": north_west_mean - south_east_mean,
    }


def labelled_preview(asset_dir: Path, label: str) -> Image.Image:
    preview = Image.open(asset_dir / "preview_panel.png").convert("RGBA")
    label_height = 34
    canvas = Image.new("RGBA", (preview.width, preview.height + label_height), (18, 18, 17, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 9), label, fill=(238, 228, 208, 255))
    canvas.alpha_composite(preview, (0, label_height))
    return canvas


def composite_tree(asset_dir: Path) -> Image.Image:
    albedo = load_rgba(asset_dir, "albedo.png")
    shadow = load_rgba(asset_dir, "shadow.png")
    trunk = load_rgba(asset_dir, "trunk.png")
    foliage = load_rgba(asset_dir, "foliage.png")
    ground = Image.new("RGBA", albedo.size, (43, 39, 33, 255))
    draw = ImageDraw.Draw(ground)
    for y in range(0, ground.height, 28):
        color = (48 + (y // 28) % 2 * 5, 43, 35, 255)
        draw.rectangle((0, y, ground.width, y + 14), fill=color)
    for layer in (shadow, trunk, foliage):
        ground.alpha_composite(layer)
    return ground


def root_shadow_crop(asset_dir: Path, label: str) -> Image.Image:
    classification = json.loads((asset_dir / "classification.json").read_text(encoding="utf-8"))
    anchor_x, anchor_y = (int(value) for value in classification["anchor"])
    composite = composite_tree(asset_dir)
    crop_box = (
        max(0, anchor_x - 180),
        max(0, anchor_y - 120),
        min(composite.width, anchor_x + 384),
        min(composite.height, anchor_y + 229),
    )
    crop = composite.crop(crop_box)
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.LANCZOS)
    label_height = 34
    canvas = Image.new("RGBA", (crop.width, crop.height + label_height), (18, 18, 17, 255))
    ImageDraw.Draw(canvas).text((12, 9), label, fill=(238, 228, 208, 255))
    canvas.alpha_composite(crop, (0, label_height))
    return canvas


def build_comparison_panel(baseline_dir: Path, candidate_dir: Path) -> Image.Image:
    baseline = labelled_preview(baseline_dir, "BASELINE v1 - NE shadow / flat snow")
    candidate = labelled_preview(candidate_dir, "PROOF v2 - NW sun / SE shadow / shaded snow")
    width = max(baseline.width, candidate.width)
    canvas = Image.new("RGBA", (width, baseline.height + candidate.height), (18, 18, 17, 255))
    canvas.alpha_composite(baseline, (0, 0))
    canvas.alpha_composite(candidate, (0, baseline.height))
    return canvas


def build_root_shadow_comparison(baseline_dir: Path, candidate_dir: Path) -> Image.Image:
    baseline = root_shadow_crop(baseline_dir, "BASELINE root cast shadow")
    candidate = root_shadow_crop(candidate_dir, "PROOF root cast shadow")
    canvas = Image.new("RGBA", (baseline.width + candidate.width, max(baseline.height, candidate.height)), (18, 18, 17, 255))
    canvas.alpha_composite(baseline, (0, 0))
    canvas.alpha_composite(candidate, (baseline.width, 0))
    return canvas


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    metrics = {
        "baseline": collect_metrics(args.baseline_dir),
        "candidate": collect_metrics(args.candidate_dir),
    }
    (args.out_dir / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    build_comparison_panel(args.baseline_dir, args.candidate_dir).save(args.out_dir / "comparison_panel.png")
    build_root_shadow_comparison(args.baseline_dir, args.candidate_dir).save(
        args.out_dir / "root_shadow_comparison.png"
    )
    print(f"Wrote proof metrics and comparison panel to {args.out_dir}")


if __name__ == "__main__":
    main()
