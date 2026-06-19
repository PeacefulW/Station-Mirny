import json
import math
import re
import sys
from pathlib import Path

from PIL import Image


ANGLE_PATTERN = re.compile(r"rot_(\d+)_(\d+)deg\.png$")


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return (0, 0, image.width, image.height)
    return bbox


def cleanup_tiny_alpha(image: Image.Image) -> Image.Image:
    src = image.convert("RGBA")
    pixels = src.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = pixels[x, y]
            if a <= 2:
                pixels[x, y] = (0, 0, 0, 0)
    return src


def checkerboard(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            shade = 216 if ((x // cell) + (y // cell)) % 2 == 0 else 178
            pixels[x, y] = (shade, shade, shade, 255)
    return image


def make_ground(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (92, 84, 72, 255))


def main() -> None:
    if len(sys.argv) != 6:
        raise SystemExit(
            "Usage: python make_twisted_tree_spritesheet.py "
            "<render_dir> <asset_name> <rotations> <frame_size> <source_glb>"
        )

    render_dir = Path(sys.argv[1])
    asset_name = sys.argv[2]
    rotations = int(sys.argv[3])
    frame_size = int(sys.argv[4])
    source_glb = sys.argv[5]

    frames: list[Image.Image] = []
    frame_entries: list[dict[str, object]] = []
    for index in range(rotations):
        degrees = round(360.0 * index / rotations)
        path = render_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg.png"
        if not path.exists():
            raise FileNotFoundError(path)
        image = cleanup_tiny_alpha(Image.open(path))
        if image.size != (frame_size, frame_size):
            raise RuntimeError(f"Frame size mismatch: {path} is {image.size}, expected {(frame_size, frame_size)}")
        image.save(path)
        frames.append(image)

        match = ANGLE_PATTERN.search(path.name)
        angle_degrees = int(match.group(2)) if match else degrees
        bbox = alpha_bbox(image)
        frame_entries.append(
            {
                "index": index,
                "angle_degrees": angle_degrees,
                "file": path.name,
                "x": index * frame_size,
                "y": 0,
                "width": frame_size,
                "height": frame_size,
                "alpha_bbox": list(bbox),
                "visible_width": bbox[2] - bbox[0],
                "visible_height": bbox[3] - bbox[1],
            }
        )

    columns = rotations
    rows = math.ceil(rotations / columns)
    atlas = Image.new("RGBA", (columns * frame_size, rows * frame_size), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, (index * frame_size, 0))

    atlas_path = render_dir / f"{asset_name}_spritesheet_{rotations}x{frame_size}.png"
    atlas.save(atlas_path)

    checker_preview = checkerboard(atlas.size)
    checker_preview.alpha_composite(atlas)
    checker_path = render_dir / f"{asset_name}_spritesheet_{rotations}x{frame_size}_checker_preview.png"
    checker_preview.save(checker_path)

    ground_preview = make_ground(atlas.size)
    ground_preview.alpha_composite(atlas)
    ground_path = render_dir / f"{asset_name}_spritesheet_{rotations}x{frame_size}_ground_preview.png"
    ground_preview.save(ground_path)

    metadata = {
        "asset": asset_name,
        "source_glb": source_glb,
        "atlas": atlas_path.name,
        "checker_preview": checker_path.name,
        "ground_preview": ground_path.name,
        "columns": columns,
        "rows": rows,
        "frame_width": frame_size,
        "frame_height": frame_size,
        "frame_count": rotations,
        "rotations_degrees": [entry["angle_degrees"] for entry in frame_entries],
        "camera": "orthographic top-front, 63 degree elevation",
        "lighting": "neutral ambient plus soft top-front light; no dramatic baked time-of-day tint",
        "shadows": "ground shadow disabled; no receiver plane or shadow catcher; runtime should provide contact/sun shadow",
        "postprocess": "tiny alpha cleanup only",
        "frames": frame_entries,
    }
    metadata_path = render_dir / f"{asset_name}_spritesheet_{rotations}x{frame_size}.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("Twisted tree spritesheet complete")
    print(f"atlas={atlas_path}")
    print(f"metadata={metadata_path}")
    print(f"checker_preview={checker_path}")
    print(f"ground_preview={ground_path}")
    print(f"frames={rotations}")
    print(f"frame_size={frame_size}")


if __name__ == "__main__":
    main()
