"""Build final summer/winter review sheet and metrics for the batch proof."""

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
    image = Image.open(path).convert("RGBA")
    image = image.resize((512, 384), Image.Resampling.LANCZOS)
    label_height = 34
    canvas = Image.new("RGBA", (image.width, image.height + label_height), (18, 18, 17, 255))
    ImageDraw.Draw(canvas).text((10, 9), label, fill=(238, 228, 208, 255))
    canvas.alpha_composite(image, (0, label_height))
    return canvas


def main() -> None:
    args = parse_args()
    candidates = args.batch_root / "candidates"
    lab = args.batch_root / "lab"
    rows: list[tuple[Image.Image, Image.Image]] = []
    metrics: dict[str, dict] = {}
    for tree_index in range(2, 7):
        tree_id = f"tree_{tree_index:02d}"
        rows.append(
            (
                labelled_capture(lab / f"{tree_id}_summer.png", f"{tree_id} — SUMMER / PHYSICAL SHADOW"),
                labelled_capture(lab / f"{tree_id}_winter.png", f"{tree_id} — FULL FOLIAGE WINTER"),
            )
        )
        metrics[tree_id] = collect_metrics(candidates / tree_id)
    cell_width = 512
    cell_height = 418
    sheet = Image.new("RGBA", (cell_width * 2, cell_height * len(rows)), (18, 18, 17, 255))
    for row_index, row in enumerate(rows):
        for column_index, image in enumerate(row):
            sheet.alpha_composite(image, (column_index * cell_width, row_index * cell_height))
    sheet.save(args.batch_root / "batch_review_sheet.png")
    (args.batch_root / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Wrote batch review to {args.batch_root}")


if __name__ == "__main__":
    main()
