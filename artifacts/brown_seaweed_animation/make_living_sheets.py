import json
import re
import sys
from pathlib import Path

from PIL import Image


FRAME_PATTERN = re.compile(r"view_(\d+)deg_frame_(\d+)\.png$")


def checkerboard(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            shade = 216 if ((x // cell) + (y // cell)) % 2 == 0 else 178
            pixels[x, y] = (shade, shade, shade, 255)
    return image


def load_frames(view_dir: Path) -> list[Path]:
    frames = sorted(view_dir.glob("brown_seaweed_view_*_frame_*.png"))
    if not frames:
        raise RuntimeError(f"No frames found in {view_dir}")
    return frames


def save_view_sheet(frames: list[Path], output_png: Path) -> dict:
    first = Image.open(frames[0]).convert("RGBA")
    frame_size = first.size
    sheet = Image.new("RGBA", (frame_size[0] * len(frames), frame_size[1]), (0, 0, 0, 0))
    frame_rows = []
    for index, path in enumerate(frames):
        image = Image.open(path).convert("RGBA")
        if image.size != frame_size:
            raise RuntimeError(f"Frame size mismatch: {path} is {image.size}, expected {frame_size}")
        x = index * frame_size[0]
        sheet.paste(image, (x, 0), image)
        frame_rows.append({"index": index, "file": path.name, "x": x, "y": 0, "width": frame_size[0], "height": frame_size[1]})
    output_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_png)

    preview = checkerboard(sheet.size)
    preview.alpha_composite(sheet)
    preview.save(output_png.with_name(output_png.stem + "_checker_preview.png"))
    return {"sheet": output_png.name, "frame_size": frame_size, "frame_count": len(frames), "frames": frame_rows}


def save_animated_preview(frames: list[Path], output_webp: Path) -> None:
    composited = []
    for path in frames:
        image = Image.open(path).convert("RGBA")
        preview = checkerboard(image.size, 32)
        preview.alpha_composite(image)
        composited.append(preview.convert("RGB"))
    output_webp.parent.mkdir(parents=True, exist_ok=True)
    composited[0].save(
        output_webp,
        save_all=True,
        append_images=composited[1:],
        duration=100,
        loop=0,
        quality=90,
        method=6,
    )


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("Usage: python make_living_sheets.py <frames_root> <output_root> <metadata_json> <frames_per_view>")

    frames_root = Path(sys.argv[1])
    output_root = Path(sys.argv[2])
    metadata_json = Path(sys.argv[3])
    frames_per_view = int(sys.argv[4])

    view_dirs = sorted([path for path in frames_root.glob("view_*deg") if path.is_dir()])
    if not view_dirs:
        raise RuntimeError(f"No view directories found in {frames_root}")

    view_entries = []
    all_view_images = []
    frame_size = None
    for row, view_dir in enumerate(view_dirs):
        frames = load_frames(view_dir)
        if len(frames) != frames_per_view:
            raise RuntimeError(f"{view_dir} has {len(frames)} frames, expected {frames_per_view}")

        match = re.search(r"view_(\d+)deg$", view_dir.name)
        degrees = int(match.group(1)) if match else None
        view_sheet = output_root / f"brown_seaweed_living_view_{degrees:03d}deg_16x512.png"
        view_data = save_view_sheet(frames, view_sheet)
        save_animated_preview(frames, output_root / "previews" / f"brown_seaweed_living_view_{degrees:03d}deg.webp")

        if frame_size is None:
            frame_size = view_data["frame_size"]
        elif frame_size != view_data["frame_size"]:
            raise RuntimeError(f"View frame size mismatch: {view_dir}")

        row_images = [Image.open(path).convert("RGBA") for path in frames]
        all_view_images.append(row_images)
        view_entries.append(
            {
                "view_index": row,
                "angle_degrees": degrees,
                "sheet": view_sheet.name,
                "animated_preview": f"previews/brown_seaweed_living_view_{degrees:03d}deg.webp",
                "frames": view_data["frames"],
            }
        )

    assert frame_size is not None
    master = Image.new("RGBA", (frame_size[0] * frames_per_view, frame_size[1] * len(view_dirs)), (0, 0, 0, 0))
    for row, row_images in enumerate(all_view_images):
        for column, image in enumerate(row_images):
            master.paste(image, (column * frame_size[0], row * frame_size[1]), image)
    master_png = output_root / "brown_seaweed_living_master_4views_16frames_512.png"
    master.save(master_png)

    master_preview = checkerboard(master.size)
    master_preview.alpha_composite(master)
    master_preview_png = output_root / "brown_seaweed_living_master_4views_16frames_512_checker_preview.png"
    master_preview.save(master_preview_png)

    metadata = {
        "source": "M:/Downloads/brown seaweed 3d model.glb",
        "master_sheet": master_png.name,
        "master_preview": master_preview_png.name,
        "views": len(view_dirs),
        "frames_per_view": frames_per_view,
        "frame_width": frame_size[0],
        "frame_height": frame_size[1],
        "columns": frames_per_view,
        "rows": len(view_dirs),
        "camera": "orthographic top-front, 62 degree elevation, no side yaw",
        "view_angles_degrees": [entry["angle_degrees"] for entry in view_entries],
        "animation": "baked subtle self-motion; base mostly anchored, upper vertices sway/fluctuate smoothly",
        "shadows": "disabled",
        "view_entries": view_entries,
    }
    metadata_json.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print(f"master_sheet={master_png}")
    print(f"master_preview={master_preview_png}")
    print(f"metadata={metadata_json}")
    print(f"views={len(view_dirs)}")
    print(f"frames_per_view={frames_per_view}")
    print(f"master_size={master.size[0]}x{master.size[1]}")


if __name__ == "__main__":
    main()
