"""Build a labelled 90/180-degree orientation sheet for remaining trees."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("orientation_dir", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def cell(image_path: Path, label: str) -> Image.Image:
    image = Image.open(image_path).convert("RGBA")
    width, height = image.size
    label_height = 34
    canvas = Image.new("RGBA", (width, height + label_height), (18, 18, 17, 255))
    ground = Image.new("RGBA", image.size, (43, 39, 33, 255))
    draw = ImageDraw.Draw(ground)
    for y in range(0, height, 24):
        draw.rectangle((0, y, width, y + 12), fill=(49 + (y // 24) % 2 * 5, 44, 36, 255))
    ground.alpha_composite(image)
    canvas.alpha_composite(ground, (0, label_height))
    ImageDraw.Draw(canvas).text((10, 9), label, fill=(238, 228, 208, 255))
    return canvas


def main() -> None:
    args = parse_args()
    rows: list[tuple[Image.Image, Image.Image]] = []
    for tree_index in range(2, 7):
        tree_dir = args.orientation_dir / f"tree_{tree_index:02d}"
        rows.append(
            (
                cell(tree_dir / "yaw_090.png", f"tree_{tree_index:02d} — yaw 90"),
                cell(tree_dir / "yaw_180.png", f"tree_{tree_index:02d} — yaw 180"),
            )
        )
    cell_width = max(image.width for row in rows for image in row)
    cell_height = max(image.height for row in rows for image in row)
    sheet = Image.new("RGBA", (cell_width * 2, cell_height * len(rows)), (18, 18, 17, 255))
    for row_index, row in enumerate(rows):
        for column_index, image in enumerate(row):
            sheet.alpha_composite(image, (column_index * cell_width, row_index * cell_height))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    print(f"Wrote orientation sheet to {args.output}")


if __name__ == "__main__":
    main()
