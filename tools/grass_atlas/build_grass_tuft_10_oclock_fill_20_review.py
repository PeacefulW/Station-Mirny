"""Build a labelled self-shadow and physical-shadow review for selected grass frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance


SELECTED_FRAMES = (0, 2, 16, 20)
FRAME_SIZE = (160, 120)
AUTHORED_ROOT_ANCHOR = (FRAME_SIZE[0] * 0.42, FRAME_SIZE[1] * 0.75)
AUTHORED_SHADOW_DIRECTION = (0.866025, 0.5)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    return parser.parse_args()


def alpha_centroid(image: Image.Image) -> tuple[float, float]:
    alpha = image.convert("RGBA").getchannel("A")
    total = sum(alpha.tobytes())
    if total <= 0:
        return (0.0, 0.0)
    weighted_x = 0
    weighted_y = 0
    pixels = alpha.load()
    for y in range(alpha.height):
        for x in range(alpha.width):
            value = pixels[x, y]
            weighted_x += x * value
            weighted_y += y * value
    return (weighted_x / total, weighted_y / total)


def ground_shadow_metrics(image: Image.Image) -> dict[str, object]:
    alpha = image.convert("RGBA").getchannel("A")
    shadow_center = alpha_centroid(image)
    projections: list[float] = []
    below_anchor_alpha = 0
    total_alpha = 0
    pixels = alpha.load()
    for y in range(alpha.height):
        for x in range(alpha.width):
            value = pixels[x, y]
            if value <= 0:
                continue
            total_alpha += value
            if y > AUTHORED_ROOT_ANCHOR[1]:
                below_anchor_alpha += value
            projections.append(
                (x - AUTHORED_ROOT_ANCHOR[0]) * AUTHORED_SHADOW_DIRECTION[0]
                + (y - AUTHORED_ROOT_ANCHOR[1]) * AUTHORED_SHADOW_DIRECTION[1]
            )
    return {
        "authored_shadow_direction": list(AUTHORED_SHADOW_DIRECTION),
        "shadow_centroid_from_authored_root": [
            shadow_center[0] - AUTHORED_ROOT_ANCHOR[0],
            shadow_center[1] - AUTHORED_ROOT_ANCHOR[1],
        ],
        "max_forward_extent_from_authored_root": max(projections, default=0.0),
        "below_root_alpha_fraction": below_anchor_alpha / float(max(total_alpha, 1)),
    }


def self_shadow_metrics(full: Image.Image, reference: Image.Image) -> dict[str, float]:
    full_pixels = full.convert("RGBA").load()
    ref_pixels = reference.convert("RGBA").load()
    compared = 0
    shadowed = 0
    max_delta = 0
    for y in range(full.height):
        for x in range(full.width):
            fp = full_pixels[x, y]
            rp = ref_pixels[x, y]
            if fp[3] < 96 or rp[3] < 96:
                continue
            compared += 1
            full_luma = (fp[0] * 299 + fp[1] * 587 + fp[2] * 114) // 1000
            ref_luma = (rp[0] * 299 + rp[1] * 587 + rp[2] * 114) // 1000
            delta = ref_luma - full_luma
            max_delta = max(max_delta, delta)
            if delta >= 2:
                shadowed += 1
    return {
        "compared_pixels": compared,
        "shadowed_fraction_delta_ge_2": shadowed / float(max(compared, 1)),
        "max_luminance_delta": max_delta,
    }


def labelled(image: Image.Image, label: str) -> Image.Image:
    tile = Image.new("RGBA", (320, 270), (34, 31, 26, 255))
    preview = image.convert("RGBA").resize((320, 240), Image.Resampling.NEAREST)
    tile.alpha_composite(preview, (0, 30))
    ImageDraw.Draw(tile).text((7, 8), label, fill=(240, 228, 207, 255))
    return tile


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    frames = root / "frames"
    atlas = Image.open(root / "grass_tuft_shadow_atlas.png").convert("RGBA")
    frame_width, frame_height = FRAME_SIZE
    rows: list[Image.Image] = []
    report: dict[str, dict] = {}
    for index in SELECTED_FRAMES:
        full = Image.open(frames / f"frame_{index:02d}.png").convert("RGBA")
        reference = Image.open(frames / f"no_self_shadow_frame_{index:02d}.png").convert("RGBA")
        box = (
            (index % 4) * frame_width,
            (index // 4) * frame_height,
            (index % 4 + 1) * frame_width,
            (index // 4 + 1) * frame_height,
        )
        shadow = atlas.crop(box)
        delta_rgb = ImageChops.subtract(reference.convert("RGB"), full.convert("RGB"))
        delta = ImageEnhance.Brightness(delta_rgb).enhance(5.0).convert("RGBA")
        delta.putalpha(ImageChops.multiply(full.getchannel("A"), reference.getchannel("A")))
        metrics = self_shadow_metrics(full, reference)
        metrics.update(ground_shadow_metrics(shadow))
        report[f"frame_{index:02d}"] = metrics
        row = Image.new("RGBA", (1280, 270), (20, 18, 15, 255))
        for column, tile in enumerate((
            labelled(full, f"{index:02d} | SUN + SELF-SHADOW"),
            labelled(reference, "SUN SHADOW DISABLED"),
            labelled(delta, "SELF-SHADOW DELTA x5"),
            labelled(shadow, "SUN-ONLY GROUND SHADOW"),
        )):
            row.alpha_composite(tile, (column * 320, 0))
        rows.append(row)
    sheet = Image.new("RGBA", (1280, len(rows) * 270), (18, 16, 14, 255))
    for row_index, row in enumerate(rows):
        sheet.alpha_composite(row, (0, row_index * 270))
    sheet.save(root / "selected_10_oclock_fill_20_review.png")
    (root / "selected_10_oclock_fill_20_metrics.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(f"Wrote selected grass review to {root}")


if __name__ == "__main__":
    main()
