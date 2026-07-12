"""Build full tree+shadow and 9:00/9:30/10:00 physical direction sheets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

from build_layered_tree_proof_report import collect_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--nine-dir", required=True, type=Path)
    parser.add_argument("--ten-dir", required=True, type=Path)
    parser.add_argument("--ten-cast-dir", required=True, type=Path)
    return parser.parse_args()


def composite(shadow_path: Path, albedo_path: Path) -> Image.Image:
    shadow = Image.open(shadow_path).convert("RGBA")
    albedo = Image.open(albedo_path).convert("RGBA")
    ground = Image.new("RGBA", albedo.size, (46, 42, 35, 255))
    draw = ImageDraw.Draw(ground)
    for y in range(0, ground.height, 28):
        color = (51 + (y // 28) % 2 * 5, 46, 38, 255)
        draw.rectangle((0, y, ground.width, y + 14), fill=color)
    ground.alpha_composite(shadow)
    ground.alpha_composite(albedo)
    return ground


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)


def main() -> None:
    args = parse_args()
    proof_dir = args.proof_dir.resolve()
    diagnostic_dir = proof_dir / "diagnostic"
    base_asset = proof_dir / "base_asset_00"
    diagnostic = json.loads((diagnostic_dir / "manifest.json").read_text(encoding="utf-8"))
    new_cast = collect_metrics(base_asset)
    nine_cast = collect_metrics(args.nine_dir / "base_asset_00")
    ten_cast = collect_metrics(args.ten_cast_dir.resolve())
    self_shadow = json.loads((diagnostic_dir / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
    diagnostic["physical_cast_shadow"] = {
        "screen_angle_degrees": new_cast["shadow_screen_angle_degrees"],
        "centroid_delta": new_cast["shadow_centroid_delta"],
    }
    diagnostic["comparison_cast_angles_degrees"] = {
        "9_00": nine_cast["shadow_screen_angle_degrees"],
        "9_30": new_cast["shadow_screen_angle_degrees"],
        "10_00": ten_cast["shadow_screen_angle_degrees"],
    }
    diagnostic["self_shadow"] = self_shadow
    (proof_dir / "metrics.json").write_text(json.dumps(diagnostic, indent=2), encoding="utf-8")

    new_target_file = diagnostic_dir / diagnostic["files"]["fill_target"]
    new_composite = composite(base_asset / "shadow.png", new_target_file)
    large = Image.new("RGBA", (1500, 1000), (22, 23, 25, 255))
    large_draw = ImageDraw.Draw(large)
    font = ImageFont.load_default()
    large_draw.text((28, 22), "SUN 9:30 + LOW KICKER 12% | COMPLETE PHYSICAL SHADOW", font=font, fill=(238, 233, 223, 255))
    large_draw.text(
        (28, 46),
        "cast %.2f deg | trunk +%.2f%% | dark foliage +%.2f%%" % (
            new_cast["shadow_screen_angle_degrees"],
            diagnostic["calibration"]["measured_trunk_lift_percent"],
            diagnostic["calibration"]["measured_dark_foliage_lift_percent"],
        ),
        font=font,
        fill=(160, 168, 175, 255),
    )
    prepared = fit(new_composite, (1440, 900))
    large.alpha_composite(prepared, ((1500 - prepared.width) // 2, 78))
    large.save(proof_dir / "sun_9_30_fill_12_with_shadow.png")

    nine_composite = composite(
        args.nine_dir / "base_asset_00" / "shadow.png",
        args.nine_dir / "diagnostic" / "sun_9_fill_08.png",
    )
    ten_metrics = json.loads((args.ten_dir / "metrics.json").read_text(encoding="utf-8"))
    ten_composite = composite(
        args.ten_cast_dir / "shadow.png",
        args.ten_dir / "diagnostic" / ten_metrics["files"]["fill_target"],
    )
    items = [
        ("9:00 + 8%", nine_composite, nine_cast["shadow_screen_angle_degrees"]),
        ("9:30 + 12%", new_composite, new_cast["shadow_screen_angle_degrees"]),
        ("10:00 + 12%", ten_composite, ten_cast["shadow_screen_angle_degrees"]),
    ]
    panel_w, panel_h = 700, 600
    sheet = Image.new("RGBA", (panel_w * 3, panel_h), (22, 23, 25, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (label, source, angle) in enumerate(items):
        x0 = index * panel_w
        primary = index == 1
        outline = (100, 201, 150, 255) if primary else (73, 76, 81, 255)
        draw.rectangle((x0 + 6, 6, x0 + panel_w - 7, panel_h - 7), fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1)
        draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        draw.text((x0 + 18, 40), "physical cast angle %.2f deg" % angle, font=font, fill=(160, 168, 175, 255))
        prepared = fit(source, (panel_w - 28, panel_h - 76))
        sheet.alpha_composite(prepared, (x0 + (panel_w - prepared.width) // 2, 66))
    sheet.save(proof_dir / "sun_9_30_shadow_directions.png")
    print(json.dumps(diagnostic, indent=2))


if __name__ == "__main__":
    main()
