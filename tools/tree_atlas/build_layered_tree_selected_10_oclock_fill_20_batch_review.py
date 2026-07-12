"""Build six-tree selected-lighting summer/winter review and metrics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from build_layered_tree_proof_report import collect_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("batch_root", type=Path)
    return parser.parse_args()


def labelled_capture(path: Path, label: str) -> Image.Image:
    image = Image.open(path).convert("RGBA").resize((512, 384), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 418), (18, 18, 17, 255))
    ImageDraw.Draw(canvas).text((10, 9), label, fill=(238, 228, 208, 255))
    canvas.alpha_composite(image, (0, 34))
    return canvas


def main() -> None:
    args = parse_args()
    batch_root = args.batch_root.resolve()
    candidates = batch_root / "candidates"
    lab = batch_root / "lab"
    rows: list[tuple[Image.Image, Image.Image]] = []
    metrics: dict[str, dict] = {}
    for tree_index in range(1, 7):
        tree_id = f"tree_{tree_index:02d}"
        rows.append((
            labelled_capture(lab / f"{tree_id}_summer.png", f"{tree_id} | 10:00 + 20% | PHYSICAL SHADOW"),
            labelled_capture(lab / f"{tree_id}_winter.png", f"{tree_id} | FULL-FOLIAGE WINTER"),
        ))
        metrics[tree_id] = collect_metrics(candidates / tree_id)
    sheet = Image.new("RGBA", (1024, 418 * len(rows)), (18, 18, 17, 255))
    for row_index, row in enumerate(rows):
        for column_index, image in enumerate(row):
            sheet.alpha_composite(image, (column_index * 512, row_index * 418))
    sheet.save(batch_root / "selected_10_oclock_fill_20_batch_review.png")
    (batch_root / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"Wrote selected batch review to {batch_root}")


if __name__ == "__main__":
    main()
