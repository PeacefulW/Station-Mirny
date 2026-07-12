"""Build a labelled eight-view orbit sheet and a large west review image."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BACKGROUND = (27, 28, 30, 255)
PANEL = (39, 40, 43, 255)
TEXT = (236, 232, 222, 255)
MUTED = (166, 174, 181, 255)
WEST = (224, 170, 72, 255)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, type=Path)
    return parser.parse_args()


def crop_visible(image: Image.Image, margin: int = 18) -> Image.Image:
    image = image.convert("RGBA")
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    return image.crop(
        (
            max(0, bbox[0] - margin),
            max(0, bbox[1] - margin),
            min(image.width, bbox[2] + margin),
            min(image.height, bbox[3] + margin),
        )
    )


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def alpha_luminance(image: Image.Image) -> dict:
    rgba = image.convert("RGBA")
    values = [
        value
        for value, alpha in zip(rgba.convert("L").getdata(), rgba.getchannel("A").getdata())
        if alpha >= 128
    ]
    ordered = sorted(values)
    p10 = ordered[int(round((len(ordered) - 1) * 0.1))] if ordered else 0
    return {
        "mean": statistics.fmean(values) if values else 0.0,
        "p10": float(p10),
        "sample_count": len(values),
    }


def draw_tree_panel(canvas: Image.Image, image: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    fitted = fit(crop_visible(image), (x1 - x0 - 24, y1 - y0 - 24))
    canvas.alpha_composite(
        fitted,
        (x0 + (x1 - x0 - fitted.width) // 2, y0 + (y1 - y0 - fitted.height) // 2),
    )


def main() -> None:
    args = parse_args()
    root = args.input_dir.resolve()
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    font = ImageFont.load_default()
    metrics = {"candidate": manifest["candidate"], "views": {}}

    sheet = Image.new("RGBA", (1600, 1040), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    draw.text((28, 18), "TREE 01 - FIXED NW SUN / CAMERA ORBIT / CANDIDATE A", font=font, fill=TEXT)
    draw.text((28, 42), "Tree and physical Sun stay fixed. Only camera viewpoint changes.", font=font, fill=MUTED)
    panel_w, panel_h = 388, 470
    for index, view in enumerate(manifest["views"]):
        col, row = index % 4, index // 4
        x0, y0 = 16 + col * 396, 82 + row * 478
        x1, y1 = x0 + panel_w, y0 + panel_h
        highlight = view["id"] == "west"
        outline = WEST if highlight else (74, 77, 82, 255)
        width = 5 if highlight else 1
        draw.rectangle((x0, y0, x1, y1), fill=PANEL, outline=outline, width=width)
        label = f"{view['label']} VIEW"
        if highlight:
            label += "  <- WEST"
        draw.text((x0 + 14, y0 + 12), label, font=font, fill=WEST if highlight else TEXT)
        draw.text((x0 + 14, y0 + 32), "camera %s of tree" % view["label"].lower(), font=font, fill=MUTED)
        source = Image.open(root / view["file"]).convert("RGBA")
        metrics["views"][view["id"]] = alpha_luminance(source)
        draw_tree_panel(sheet, source, (x0 + 4, y0 + 52, x1 - 4, y1 - 6))

    sheet.save(root / "turntable_sheet.png")

    west_view = next(view for view in manifest["views"] if view["id"] == "west")
    west_source = Image.open(root / west_view["file"]).convert("RGBA")
    west = Image.new("RGBA", (1400, 1000), BACKGROUND)
    west_draw = ImageDraw.Draw(west)
    west_draw.rectangle((18, 18, 1382, 982), fill=PANEL, outline=WEST, width=6)
    west_draw.text((46, 42), "WEST SIDE - CAMERA WEST OF TREE, LOOKING EAST", font=font, fill=WEST)
    west_draw.text((46, 66), "Candidate A | fixed NW physical Sun | no fill / no ambient rig", font=font, fill=TEXT)
    west_draw.text((46, 88), "Self-shadow remains enabled. Production assets unchanged.", font=font, fill=MUTED)
    draw_tree_panel(west, west_source, (40, 118, 1360, 956))
    west.save(root / "west_closeup.png")

    (root / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
