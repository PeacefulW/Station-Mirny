import json
import math
import re
import sys
from pathlib import Path

from PIL import Image


ANGLE_PATTERN = re.compile(r"rot_(\d+)_(\d+)deg\.png$")


def checkerboard(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            shade = 216 if ((x // cell) + (y // cell)) % 2 == 0 else 178
            pixels[x, y] = (shade, shade, shade, 255)
    return image


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("Usage: python make_volcanic_rock_spritesheet.py <frames_dir> <sheet_png> <metadata_json> <columns>")

    frames_dir = Path(sys.argv[1])
    sheet_png = Path(sys.argv[2])
    metadata_json = Path(sys.argv[3])
    columns = int(sys.argv[4])

    frame_paths = sorted(frames_dir.glob("volcanic_rock_rot_*_*.png"))
    if not frame_paths:
        raise RuntimeError(f"No rendered frames found in {frames_dir}")

    first = Image.open(frame_paths[0]).convert("RGBA")
    frame_size = first.size
    rows = math.ceil(len(frame_paths) / columns)
    sheet = Image.new("RGBA", (columns * frame_size[0], rows * frame_size[1]), (0, 0, 0, 0))

    frames = []
    for frame_index, path in enumerate(frame_paths):
        image = Image.open(path).convert("RGBA")
        if image.size != frame_size:
            raise RuntimeError(f"Frame size mismatch: {path} is {image.size}, expected {frame_size}")
        x = (frame_index % columns) * frame_size[0]
        y = (frame_index // columns) * frame_size[1]
        sheet.paste(image, (x, y), image)

        match = ANGLE_PATTERN.search(path.name)
        frames.append(
            {
                "index": frame_index,
                "file": path.name,
                "angle_degrees": int(match.group(2)) if match else None,
                "x": x,
                "y": y,
                "width": frame_size[0],
                "height": frame_size[1],
            }
        )

    sheet_png.parent.mkdir(parents=True, exist_ok=True)
    metadata_json.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_png)

    preview = checkerboard(sheet.size)
    preview.alpha_composite(sheet)
    preview_path = sheet_png.with_name(sheet_png.stem + "_checker_preview.png")
    preview.save(preview_path)

    metadata = {
        "source": "M:/Downloads/volcanic+rock+3d+model.glb",
        "sprite_sheet": sheet_png.name,
        "preview": preview_path.name,
        "frame_count": len(frame_paths),
        "columns": columns,
        "rows": rows,
        "frame_width": frame_size[0],
        "frame_height": frame_size[1],
        "camera": "orthographic top-front, 62 degree elevation, no side yaw",
        "animation": "disabled",
        "shadows": "disabled",
        "frames": frames,
    }
    metadata_json.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print(f"sheet={sheet_png}")
    print(f"preview={preview_path}")
    print(f"metadata={metadata_json}")
    print(f"frames={len(frame_paths)}")
    print(f"size={sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
