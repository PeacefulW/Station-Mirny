"""Build 9/8 versus 10/8 versus 10/12 clock-face lighting comparison."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_layered_tree_proof_report import collect_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--ten-eight-dir", required=True, type=Path)
    parser.add_argument("--nine-eight-dir", required=True, type=Path)
    parser.add_argument("--cast-asset-dir", required=True, type=Path)
    return parser.parse_args()


def crop_visible(image: Image.Image, margin: int = 20) -> Image.Image:
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    return image.crop((max(0, bbox[0] - margin), max(0, bbox[1] - margin), min(image.width, bbox[2] + margin), min(image.height, bbox[3] + margin)))


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)


def main() -> None:
    args = parse_args()
    proof_dir = args.proof_dir.resolve()
    diagnostic_dir = proof_dir / "diagnostic"
    diagnostic = json.loads((diagnostic_dir / "manifest.json").read_text(encoding="utf-8"))
    cast = collect_metrics(args.cast_asset_dir.resolve())
    self_shadow = json.loads((diagnostic_dir / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
    diagnostic["physical_cast_shadow"] = {
        "screen_angle_degrees": cast["shadow_screen_angle_degrees"],
        "centroid_delta": cast["shadow_centroid_delta"],
    }
    diagnostic["self_shadow"] = self_shadow
    (proof_dir / "metrics.json").write_text(json.dumps(diagnostic, indent=2), encoding="utf-8")

    items = [
        ("9:00 SUN + 8%", Image.open(args.nine_eight_dir / "diagnostic" / "sun_9_fill_08.png").convert("RGBA"), False),
        ("10:00 SUN + 8%", Image.open(args.ten_eight_dir / "lift_08.png").convert("RGBA"), False),
        ("10:00 SUN + 12%  PRIMARY", Image.open(diagnostic_dir / diagnostic["files"]["fill_target"]).convert("RGBA"), True),
    ]
    panel_w, panel_h = 620, 760
    canvas = Image.new("RGBA", (panel_w * 3, panel_h), (22, 23, 25, 255))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for index, (label, source, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (100, 201, 150, 255) if primary else (73, 76, 81, 255)
        draw.rectangle((x0 + 6, 6, x0 + panel_w - 7, panel_h - 7), fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1)
        draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        detail = "physical Sun self-shadow enabled"
        if primary:
            detail = "trunk +%.2f%% | foliage +%.2f%% | cast %.2f deg" % (
                diagnostic["calibration"]["measured_trunk_lift_percent"],
                diagnostic["calibration"]["measured_dark_foliage_lift_percent"],
                cast["shadow_screen_angle_degrees"],
            )
        draw.text((x0 + 18, 42), detail, font=font, fill=(158, 166, 173, 255))
        prepared = fit(crop_visible(source), (panel_w - 38, panel_h - 92))
        canvas.alpha_composite(prepared, (x0 + (panel_w - prepared.width) // 2, 76 + (panel_h - 92 - prepared.height) // 2))
    canvas.save(proof_dir / "sun_10_oclock_fill_12_review_sheet.png")

    bbox = items[1][1].getchannel("A").getbbox() or (0, 0, 768, 768)
    left, top, right, bottom = bbox
    height = bottom - top
    crown = (left - 10, top - 10, right + 10, top + round(height * 0.45))
    trunk = (left - 10, top + round(height * 0.30), right + 10, top + round(height * 0.88))
    close = Image.new("RGBA", (panel_w * 3, 850), (22, 23, 25, 255))
    close_draw = ImageDraw.Draw(close)
    for index, (label, source, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (100, 201, 150, 255) if primary else (73, 76, 81, 255)
        close_draw.rectangle((x0 + 6, 6, x0 + panel_w - 7, 842), fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1)
        close_draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        crown_img = fit(source.crop(crown), (panel_w - 32, 350))
        trunk_img = fit(source.crop(trunk), (panel_w - 32, 400))
        close.alpha_composite(crown_img, (x0 + (panel_w - crown_img.width) // 2, 58))
        close.alpha_composite(trunk_img, (x0 + (panel_w - trunk_img.width) // 2, 430))
    close.save(proof_dir / "sun_10_oclock_fill_12_closeups.png")
    print(json.dumps(diagnostic, indent=2))


if __name__ == "__main__":
    main()
