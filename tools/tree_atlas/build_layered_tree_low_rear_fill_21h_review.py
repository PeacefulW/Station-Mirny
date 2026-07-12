"""Build raw and gain-assisted 21:00 comparison for baseline versus 8% kicker."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lab-dir", required=True, type=Path)
    parser.add_argument("--candidate-dir", required=True, type=Path)
    return parser.parse_args()


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def tree_screen_mask(candidate_dir: Path) -> Image.Image:
    meta = json.loads((candidate_dir / "meta.json").read_text(encoding="utf-8"))
    albedo = Image.open(candidate_dir / "albedo.png").convert("RGBA")
    scale = 0.86
    root_x, root_y = 512.0, 620.0
    frame_width = float(meta["frame_width"])
    frame_height = float(meta["frame_height"])
    anchor_x, anchor_y = (float(value) for value in meta["anchor"])
    center_x, center_y = frame_width * 0.5, frame_height * 0.5
    sprite_x = root_x - (anchor_x - center_x) * scale
    sprite_y = root_y - (anchor_y - center_y) * scale
    scaled_size = (round(albedo.width * scale), round(albedo.height * scale))
    alpha = albedo.getchannel("A").resize(scaled_size, Image.Resampling.LANCZOS)
    mask = Image.new("L", (1024, 768), 0)
    mask.paste(alpha, (round(sprite_x - scaled_size[0] * 0.5), round(sprite_y - scaled_size[1] * 0.5)))
    return mask


def luma_metrics(image: Image.Image, mask: Image.Image) -> dict:
    values = [
        value
        for value, alpha in zip(image.convert("L").getdata(), mask.getdata())
        if alpha >= 128
    ]
    ordered = sorted(values)
    return {
        "mean": statistics.fmean(values) if values else 0.0,
        "p90": float(ordered[int(round((len(ordered) - 1) * 0.9))]) if ordered else 0.0,
        "max": max(values) if values else 0,
        "sample_count": len(values),
    }


def labelled_panel(image: Image.Image, label: str, detail: str, size: tuple[int, int]) -> Image.Image:
    panel = Image.new("RGBA", size, (25, 26, 28, 255))
    draw = ImageDraw.Draw(panel)
    font = ImageFont.load_default()
    draw.text((14, 12), label, fill=(238, 233, 222, 255), font=font)
    draw.text((14, 32), detail, fill=(156, 164, 172, 255), font=font)
    prepared = fit(image, (size[0] - 20, size[1] - 64))
    panel.alpha_composite(prepared, ((size[0] - prepared.width) // 2, 56))
    return panel


def main() -> None:
    args = parse_args()
    lab_dir = args.lab_dir.resolve()
    candidate_dir = args.candidate_dir.resolve()
    baseline = Image.open(lab_dir / "baseline_00_at_21h.png").convert("RGBA")
    candidate = Image.open(lab_dir / "candidate_08_at_21h.png").convert("RGBA")
    mask = tree_screen_mask(candidate_dir)
    baseline_metrics = luma_metrics(baseline, mask)
    candidate_metrics = luma_metrics(candidate, mask)
    metrics = {
        "hour": 21.0,
        "ambient_color": [0.03, 0.035, 0.05, 1.0],
        "direct_sun_energy": 0.0,
        "sun_cast_shadow_visibility": 0.0,
        "torch_enabled": False,
        "baseline_00": baseline_metrics,
        "candidate_08": candidate_metrics,
        "mean_luminance_delta_8bit": candidate_metrics["mean"] - baseline_metrics["mean"],
        "analysis_gain": 16.0,
    }
    (lab_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    gain = 16.0
    panel_size = (720, 560)
    panels = [
        labelled_panel(baseline, "RAW GAMEPLAY 21:00 - 0%", "night ambient, sun off, shadow off, torch off", panel_size),
        labelled_panel(candidate, "RAW GAMEPLAY 21:00 - 8%", "night ambient, sun off, shadow off, torch off", panel_size),
        labelled_panel(ImageEnhance.Brightness(baseline).enhance(gain), f"ANALYSIS x{gain:.0f} - 0%", "inspection only; not gameplay brightness", panel_size),
        labelled_panel(ImageEnhance.Brightness(candidate).enhance(gain), f"ANALYSIS x{gain:.0f} - 8%", "inspection only; not gameplay brightness", panel_size),
    ]
    sheet = Image.new("RGBA", (panel_size[0] * 2, panel_size[1] * 2), (14, 15, 17, 255))
    for index, panel in enumerate(panels):
        sheet.alpha_composite(panel, ((index % 2) * panel_size[0], (index // 2) * panel_size[1]))
    sheet.save(lab_dir / "night_21h_review_sheet.png")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
