"""Build 10/12 versus 10/20 lighting review and complete-shadow composite."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_layered_tree_proof_report import collect_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--twelve-dir", required=True, type=Path)
    parser.add_argument("--cast-asset-dir", required=True, type=Path)
    return parser.parse_args()


def crop_visible(image: Image.Image, margin: int = 20) -> Image.Image:
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    return image.crop((
        max(0, bbox[0] - margin), max(0, bbox[1] - margin),
        min(image.width, bbox[2] + margin), min(image.height, bbox[3] + margin),
    ))


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    return image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )


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


def main() -> None:
    args = parse_args()
    proof_dir = args.proof_dir.resolve()
    diagnostic_dir = proof_dir / "diagnostic"
    diagnostic = json.loads((diagnostic_dir / "manifest.json").read_text(encoding="utf-8"))
    twelve = json.loads((args.twelve_dir / "metrics.json").read_text(encoding="utf-8"))
    cast = collect_metrics(args.cast_asset_dir.resolve())
    self_shadow = json.loads((diagnostic_dir / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
    diagnostic["physical_cast_shadow"] = {
        "screen_angle_degrees": cast["shadow_screen_angle_degrees"],
        "centroid_delta": cast["shadow_centroid_delta"],
    }
    diagnostic["comparison"] = {
        "baseline_target_lift_percent": twelve["calibration"]["target_trunk_lift_percent"],
        "baseline_measured_trunk_lift_percent": twelve["calibration"]["measured_trunk_lift_percent"],
    }
    diagnostic["self_shadow"] = self_shadow
    (proof_dir / "metrics.json").write_text(json.dumps(diagnostic, indent=2), encoding="utf-8")

    twelve_image = Image.open(
        args.twelve_dir / "diagnostic" / twelve["files"]["fill_target"]
    ).convert("RGBA")
    twenty_path = diagnostic_dir / diagnostic["files"]["fill_target"]
    twenty_image = Image.open(twenty_path).convert("RGBA")
    font = ImageFont.load_default()

    full = composite(args.cast_asset_dir / "shadow.png", twenty_path)
    large = Image.new("RGBA", (1500, 1000), (22, 23, 25, 255))
    large_draw = ImageDraw.Draw(large)
    large_draw.text(
        (28, 22), "SUN 10:00 + LOW KICKER 20% | COMPLETE PHYSICAL SHADOW",
        font=font, fill=(238, 233, 223, 255),
    )
    large_draw.text(
        (28, 46),
        "cast %.2f deg | trunk +%.2f%% | dark foliage +%.2f%%" % (
            cast["shadow_screen_angle_degrees"],
            diagnostic["calibration"]["measured_trunk_lift_percent"],
            diagnostic["calibration"]["measured_dark_foliage_lift_percent"],
        ),
        font=font, fill=(160, 168, 175, 255),
    )
    prepared = fit(full, (1440, 900))
    large.alpha_composite(prepared, ((1500 - prepared.width) // 2, 78))
    large.save(proof_dir / "sun_10_fill_20_with_shadow.png")

    items = [
        (
            "10:00 SUN + 12%",
            twelve_image,
            twelve["calibration"]["measured_trunk_lift_percent"],
            twelve["calibration"]["measured_dark_foliage_lift_percent"],
            False,
        ),
        (
            "10:00 SUN + 20%  PRIMARY",
            twenty_image,
            diagnostic["calibration"]["measured_trunk_lift_percent"],
            diagnostic["calibration"]["measured_dark_foliage_lift_percent"],
            True,
        ),
    ]
    panel_w, panel_h = 760, 820
    sheet = Image.new("RGBA", (panel_w * 2, panel_h), (22, 23, 25, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (label, source, trunk_lift, foliage_lift, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (100, 201, 150, 255) if primary else (73, 76, 81, 255)
        draw.rectangle(
            (x0 + 6, 6, x0 + panel_w - 7, panel_h - 7),
            fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1,
        )
        draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        draw.text(
            (x0 + 18, 42), "trunk +%.2f%% | dark foliage +%.2f%%" % (trunk_lift, foliage_lift),
            font=font, fill=(158, 166, 173, 255),
        )
        tree = fit(crop_visible(source), (panel_w - 42, panel_h - 110))
        sheet.alpha_composite(tree, (x0 + (panel_w - tree.width) // 2, 82 + (panel_h - 110 - tree.height) // 2))
    sheet.save(proof_dir / "sun_10_fill_12_vs_20_review.png")

    detail = (
        round(twelve_image.width * 0.18),
        round(twelve_image.height * 0.03),
        round(twelve_image.width * 0.82),
        round(twelve_image.height * 0.97),
    )
    close = Image.new("RGBA", (panel_w * 2, 900), (22, 23, 25, 255))
    close_draw = ImageDraw.Draw(close)
    for index, (label, source, _trunk_lift, _foliage_lift, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (100, 201, 150, 255) if primary else (73, 76, 81, 255)
        detail_image = fit(source.crop(detail), (panel_w - 40, 800))
        close.alpha_composite(
            detail_image,
            (x0 + (panel_w - detail_image.width) // 2, 70 + (800 - detail_image.height) // 2),
        )
        close_draw.rectangle(
            (x0 + 6, 6, x0 + panel_w - 7, 893),
            outline=outline, width=5 if primary else 1,
        )
        close_draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
    close.save(proof_dir / "sun_10_fill_12_vs_20_closeups.png")
    print(json.dumps(diagnostic, indent=2))


if __name__ == "__main__":
    main()
