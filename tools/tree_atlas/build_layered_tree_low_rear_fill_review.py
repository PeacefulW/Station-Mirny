"""Build full-tree and crown/trunk close-up sheets for low rear fill variants."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BACKGROUND = (23, 24, 26, 255)
PANEL = (36, 37, 40, 255)
TEXT = (237, 233, 224, 255)
MUTED = (157, 165, 172, 255)
PRIMARY = (100, 200, 148, 255)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, type=Path)
    return parser.parse_args()


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    return image.convert("RGBA").getchannel("A").getbbox() or (0, 0, image.width, image.height)


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def crop_with_margin(image: Image.Image, box: tuple[int, int, int, int], margin: int = 16) -> Image.Image:
    return image.crop(
        (
            max(0, box[0] - margin),
            max(0, box[1] - margin),
            min(image.width, box[2] + margin),
            min(image.height, box[3] + margin),
        )
    )


def place(canvas: Image.Image, image: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    prepared = fit(image, (x1 - x0, y1 - y0))
    canvas.alpha_composite(
        prepared,
        (x0 + (x1 - x0 - prepared.width) // 2, y0 + (y1 - y0 - prepared.height) // 2),
    )


def main() -> None:
    args = parse_args()
    root = args.input_dir.resolve()
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    font = ImageFont.load_default()
    variants = manifest["variants"]
    images = {item["target_lift_percent"]: Image.open(root / item["file"]).convert("RGBA") for item in variants}

    panel_w, panel_h = 410, 720
    sheet = Image.new("RGBA", (panel_w * len(variants), panel_h), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    for index, item in enumerate(variants):
        x0 = index * panel_w
        primary = bool(item["primary"])
        outline = PRIMARY if primary else (70, 73, 78, 255)
        draw.rectangle((x0 + 5, 5, x0 + panel_w - 6, panel_h - 6), fill=PANEL, outline=outline, width=5 if primary else 1)
        label = f"TARGET {item['target_lift_percent']:.0f}%"
        if primary:
            label += "  PRIMARY"
        draw.text((x0 + 18, 17), label, font=font, fill=PRIMARY if primary else TEXT)
        draw.text(
            (x0 + 18, 41),
            "trunk measured +%.2f%% | dark foliage +%.2f%%" % (
                item["measured_trunk_lift_percent"],
                item["measured_dark_foliage_lift_percent"],
            ),
            font=font,
            fill=MUTED,
        )
        draw.text((x0 + 18, 61), "10:00 physical Sun | low shadowless Spot", font=font, fill=MUTED)
        source = images[item["target_lift_percent"]]
        bbox = visible_bbox(source)
        place(sheet, crop_with_margin(source, bbox, 22), (x0 + 16, 92, x0 + panel_w - 16, panel_h - 18))
    sheet.save(root / "low_rear_fill_review_sheet.png")

    closeups = Image.new("RGBA", (panel_w * len(variants), 850), BACKGROUND)
    close_draw = ImageDraw.Draw(closeups)
    close_draw.text((18, 12), "CROWN (top): preserve cavities | TRUNK (bottom): lift only a little", font=font, fill=TEXT)
    base_bbox = visible_bbox(images[0.0])
    left, top, right, bottom = base_bbox
    height = bottom - top
    crown_box = (left, top, right, top + round(height * 0.44))
    trunk_box = (left, top + round(height * 0.30), right, top + round(height * 0.87))
    for index, item in enumerate(variants):
        x0 = index * panel_w
        primary = bool(item["primary"])
        outline = PRIMARY if primary else (70, 73, 78, 255)
        close_draw.rectangle((x0 + 5, 40, x0 + panel_w - 6, 842), fill=PANEL, outline=outline, width=5 if primary else 1)
        close_draw.text((x0 + 18, 54), f"{item['target_lift_percent']:.0f}%", font=font, fill=PRIMARY if primary else TEXT)
        source = images[item["target_lift_percent"]]
        place(closeups, crop_with_margin(source, crown_box, 8), (x0 + 14, 82, x0 + panel_w - 14, 410))
        place(closeups, crop_with_margin(source, trunk_box, 8), (x0 + 14, 438, x0 + panel_w - 14, 824))
    closeups.save(root / "low_rear_fill_closeups.png")

    (root / "metrics.json").write_text(
        json.dumps(
            {
                "primary_target_percent": manifest["calibration"]["primary_target_percent"],
                "variants": variants,
                "kicker": manifest["kicker"],
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    print(f"Wrote low rear fill review sheets to {root}")


if __name__ == "__main__":
    main()
