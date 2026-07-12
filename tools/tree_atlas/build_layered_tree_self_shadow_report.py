"""Build a fixed-scale delta and compact metrics for a strict self-shadow pair."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("diagnostic_dir", type=Path)
    return parser.parse_args()


def labelled(image: Image.Image, label: str) -> Image.Image:
    label_height = 32
    canvas = Image.new("RGBA", (image.width, image.height + label_height), (16, 16, 15, 255))
    ImageDraw.Draw(canvas).text((10, 9), label, fill=(235, 226, 207, 255))
    canvas.alpha_composite(image, (0, label_height))
    return canvas


def main() -> None:
    args = parse_args()
    diagnostic_dir = args.diagnostic_dir.resolve()
    shadow_on = Image.open(diagnostic_dir / "self_shadow_on.png").convert("RGBA")
    shadow_off = Image.open(diagnostic_dir / "self_shadow_off.png").convert("RGBA")
    if shadow_on.size != shadow_off.size:
        raise ValueError("Self-shadow diagnostic images must have identical dimensions")

    common_alpha = Image.new("L", shadow_on.size, 0)
    on_alpha = shadow_on.getchannel("A")
    off_alpha = shadow_off.getchannel("A")
    alpha_out = common_alpha.load()
    for y in range(shadow_on.height):
        for x in range(shadow_on.width):
            alpha_out[x, y] = min(on_alpha.getpixel((x, y)), off_alpha.getpixel((x, y)))
    interior = common_alpha.point(lambda value: 255 if value >= 250 else 0, "L").filter(ImageFilter.MinFilter(5))

    on_luma = shadow_on.convert("L")
    off_luma = shadow_off.convert("L")
    delta_values: list[int] = []
    delta = Image.new("RGBA", shadow_on.size, (0, 0, 0, 255))
    delta_px = delta.load()
    for y in range(shadow_on.height):
        for x in range(shadow_on.width):
            if interior.getpixel((x, y)) == 0:
                continue
            value = max(0, off_luma.getpixel((x, y)) - on_luma.getpixel((x, y)))
            delta_values.append(value)
            shown = min(255, value * 8)
            delta_px[x, y] = (shown, int(shown * 0.58), int(shown * 0.10), 255)

    sampled = len(delta_values)
    metrics = {
        "sampled_interior_pixels": sampled,
        "delta_mean_8bit": statistics.fmean(delta_values) if delta_values else 0.0,
        "delta_max_8bit": max(delta_values) if delta_values else 0,
        "delta_ge_2_fraction": sum(value >= 2 for value in delta_values) / max(sampled, 1),
        "delta_ge_5_fraction": sum(value >= 5 for value in delta_values) / max(sampled, 1),
        "delta_ge_10_fraction": sum(value >= 10 for value in delta_values) / max(sampled, 1),
        "visualization_gain": 8,
    }
    (diagnostic_dir / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    delta.save(diagnostic_dir / "self_shadow_delta_x8.png")

    panels = [
        labelled(shadow_on, "SELF SHADOW ON"),
        labelled(shadow_off, "SELF SHADOW OFF"),
        labelled(delta, "OFF - ON DELTA x8"),
    ]
    panel = Image.new(
        "RGBA",
        (sum(item.width for item in panels), max(item.height for item in panels)),
        (16, 16, 15, 255),
    )
    x_offset = 0
    for item in panels:
        panel.alpha_composite(item, (x_offset, 0))
        x_offset += item.width
    panel.save(diagnostic_dir / "self_shadow_strict_ab.png")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
