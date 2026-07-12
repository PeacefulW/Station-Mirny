"""Build one labelled A/B/C tree brightness sheet and compact metrics."""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

from build_layered_tree_proof_report import collect_metrics
from postprocess_layered_tree_asset import composite_on_ground


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = Path(__file__).with_name("layered_tree_brightness_variants_manifest.json")
PANEL_WIDTH = 600
PANEL_HEIGHT = 720
HEADER_HEIGHT = 92


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    return parser.parse_args()


def resolve_repo_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def percentile(values: list[int], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * fraction))
    return float(ordered[index])


def luminance_metrics(asset_dir: Path) -> dict:
    albedo = Image.open(asset_dir / "albedo.png").convert("RGBA")
    values = [
        value
        for value, alpha in zip(albedo.convert("L").getdata(), albedo.getchannel("A").getdata())
        if alpha >= 128
    ]
    return {
        "mean": statistics.fmean(values) if values else 0.0,
        "p10": percentile(values, 0.10),
        "median": percentile(values, 0.50),
        "p90": percentile(values, 0.90),
        "dark_fraction_lt_32": sum(value < 32 for value in values) / max(len(values), 1),
        "sample_count": len(values),
    }


def layered_preview(asset_dir: Path) -> Image.Image:
    shadow = Image.open(asset_dir / "shadow.png").convert("RGBA")
    trunk = Image.open(asset_dir / "trunk.png").convert("RGBA")
    foliage = Image.open(asset_dir / "foliage.png").convert("RGBA")
    preview = composite_on_ground(shadow, trunk, foliage)
    union = ImageChops.lighter(shadow.getchannel("A"), trunk.getchannel("A"))
    union = ImageChops.lighter(union, foliage.getchannel("A"))
    bbox = union.getbbox() or (0, 0, preview.width, preview.height)
    margin = 26
    crop = (
        max(0, bbox[0] - margin),
        max(0, bbox[1] - margin),
        min(preview.width, bbox[2] + margin),
        min(preview.height, bbox[3] + margin),
    )
    return preview.crop(crop)


def fit_image(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def main() -> None:
    args = parse_args()
    manifest = json.loads(args.manifest.resolve().read_text(encoding="utf-8"))
    output_root = resolve_repo_path(str(manifest["output_root"]))
    baseline_dir = ROOT / "assets" / "sprites" / "flora" / "layered_trees" / "tree_01"
    metrics: dict = {"baseline_production": {"luminance": luminance_metrics(baseline_dir)}, "variants": {}}
    sheet = Image.new(
        "RGBA",
        (PANEL_WIDTH * len(manifest["variants"]), PANEL_HEIGHT),
        (19, 18, 17, 255),
    )
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, item in enumerate(manifest["variants"]):
        variant_id = str(item["id"])
        asset_dir = output_root / variant_id
        cast = collect_metrics(asset_dir)
        self_shadow = json.loads((asset_dir / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
        luma = luminance_metrics(asset_dir)
        metrics["variants"][variant_id] = {
            "label": item["label"],
            "luminance": luma,
            "shadow_screen_angle_degrees": cast["shadow_screen_angle_degrees"],
            "shadow_centroid_delta": cast["shadow_centroid_delta"],
            "self_shadow": self_shadow,
        }
        x0 = index * PANEL_WIDTH
        draw.rectangle((x0, 0, x0 + PANEL_WIDTH - 1, PANEL_HEIGHT - 1), outline=(70, 64, 56, 255))
        draw.text((x0 + 16, 14), str(item["label"]), fill=(244, 236, 218, 255), font=font)
        draw.text(
            (x0 + 16, 38),
            "luma mean %.1f | p10 %.0f | self-shadow %.1f%% | cast %.1f deg"
            % (
                luma["mean"],
                luma["p10"],
                self_shadow["delta_ge_2_fraction"] * 100.0,
                cast["shadow_screen_angle_degrees"],
            ),
            fill=(194, 208, 218, 255),
            font=font,
        )
        draw.text(
            (x0 + 16, 60),
            "physical Sun shadow ON | complete roots | no production write",
            fill=(156, 151, 139, 255),
            font=font,
        )
        preview = fit_image(layered_preview(asset_dir), (PANEL_WIDTH - 32, PANEL_HEIGHT - HEADER_HEIGHT - 24))
        px = x0 + (PANEL_WIDTH - preview.width) // 2
        py = HEADER_HEIGHT + (PANEL_HEIGHT - HEADER_HEIGHT - preview.height) // 2
        sheet.alpha_composite(preview, (px, py))
    (output_root / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    sheet.save(output_root / "brightness_review_sheet.png")
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
