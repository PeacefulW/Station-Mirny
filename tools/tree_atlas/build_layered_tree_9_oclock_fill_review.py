"""Build a 10 o'clock versus 9 o'clock, 0/8% comparison sheet."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_layered_tree_proof_report import collect_metrics, root_shadow_crop


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--prior-dir", required=True, type=Path)
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
    prior_dir = args.prior_dir.resolve()
    diagnostic = json.loads((proof_dir / "diagnostic" / "manifest.json").read_text(encoding="utf-8"))
    cast = collect_metrics(proof_dir / "base_asset_00")
    self_shadow = json.loads((proof_dir / "diagnostic" / "self_shadow" / "metrics.json").read_text(encoding="utf-8"))
    diagnostic["physical_cast_shadow"] = {
        "screen_angle_degrees": cast["shadow_screen_angle_degrees"],
        "centroid_delta": cast["shadow_centroid_delta"],
    }
    diagnostic["self_shadow"] = self_shadow
    (proof_dir / "metrics.json").write_text(json.dumps(diagnostic, indent=2), encoding="utf-8")

    items = [
        ("10:00 SUN + 8%", Image.open(prior_dir / "lift_08.png").convert("RGBA"), False),
        ("9:00 SUN + 0%", Image.open(proof_dir / "diagnostic" / "sun_9_fill_00.png").convert("RGBA"), False),
        ("9:00 SUN + 8%  PRIMARY", Image.open(proof_dir / "diagnostic" / "sun_9_fill_08.png").convert("RGBA"), True),
    ]
    panel_w, panel_h = 620, 760
    canvas = Image.new("RGBA", (panel_w * 3, panel_h), (22, 23, 25, 255))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for index, (label, source, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (98, 201, 148, 255) if primary else (73, 76, 81, 255)
        draw.rectangle((x0 + 6, 6, x0 + panel_w - 7, panel_h - 7), fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1)
        draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        if index == 2:
            detail = "trunk +%.2f%% | foliage +%.2f%% | cast %.2f deg" % (
                diagnostic["calibration"]["measured_trunk_lift_percent"],
                diagnostic["calibration"]["measured_dark_foliage_lift_percent"],
                cast["shadow_screen_angle_degrees"],
            )
        else:
            detail = "physical Sun self-shadow enabled"
        draw.text((x0 + 18, 42), detail, font=font, fill=(158, 166, 173, 255))
        prepared = fit(crop_visible(source), (panel_w - 38, panel_h - 92))
        canvas.alpha_composite(prepared, (x0 + (panel_w - prepared.width) // 2, 76 + (panel_h - 92 - prepared.height) // 2))
    canvas.save(proof_dir / "sun_9_oclock_review_sheet.png")

    base_bbox = items[1][1].getchannel("A").getbbox() or (0, 0, 768, 768)
    left, top, right, bottom = base_bbox
    height = bottom - top
    crown = (left - 10, top - 10, right + 10, top + round(height * 0.45))
    trunk = (left - 10, top + round(height * 0.30), right + 10, top + round(height * 0.88))
    close = Image.new("RGBA", (panel_w * 3, 850), (22, 23, 25, 255))
    close_draw = ImageDraw.Draw(close)
    for index, (label, source, primary) in enumerate(items):
        x0 = index * panel_w
        outline = (98, 201, 148, 255) if primary else (73, 76, 81, 255)
        close_draw.rectangle((x0 + 6, 6, x0 + panel_w - 7, 842), fill=(36, 37, 40, 255), outline=outline, width=5 if primary else 1)
        close_draw.text((x0 + 18, 18), label, font=font, fill=outline if primary else (238, 233, 223, 255))
        crown_img = fit(source.crop(crown), (panel_w - 32, 350))
        trunk_img = fit(source.crop(trunk), (panel_w - 32, 400))
        close.alpha_composite(crown_img, (x0 + (panel_w - crown_img.width) // 2, 58))
        close.alpha_composite(trunk_img, (x0 + (panel_w - trunk_img.width) // 2, 430))
    close.save(proof_dir / "sun_9_oclock_closeups.png")
    root_shadow_crop(
        proof_dir / "base_asset_00",
        "9:00 PHYSICAL SUN | CAST DUE EAST | %.2f DEG" % cast["shadow_screen_angle_degrees"],
    ).save(proof_dir / "sun_9_oclock_shadow_proof.png")
    print(json.dumps(diagnostic, indent=2))


if __name__ == "__main__":
    main()
