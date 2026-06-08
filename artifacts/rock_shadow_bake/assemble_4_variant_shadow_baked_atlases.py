from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


FRAME_SIZE = 512
COLUMNS = 8
ROWS = 4
FRAME_COUNT = COLUMNS * ROWS
UNIQUE_VARIANTS = 4
GROUND_COLOR = (96, 83, 67, 255)
CHECKER_A = (78, 70, 59, 255)
CHECKER_B = (112, 98, 79, 255)
SHADOW_COLOR = (30, 24, 17, 0)


ASSETS = [
    {
        "name": "rock_1",
        "source": "C:/Users/peaceful/Station Peaceful/flora glb/rock 1.glb",
        "frames": Path("artifacts/rock_shadow_bake/rock_1/frames_512_4variant"),
        "atlas": Path("assets/sprites/resources/atlases/plains_rock_1_atlas.png"),
        "metadata": Path("assets/sprites/resources/atlases/plains_rock_1_atlas.json"),
    },
    {
        "name": "rock_2",
        "source": "C:/Users/peaceful/Station Peaceful/flora glb/rock 2.glb",
        "frames": Path("artifacts/rock_shadow_bake/rock_2/frames_512_4variant"),
        "atlas": Path("assets/sprites/resources/atlases/plains_rock_2_atlas.png"),
        "metadata": Path("assets/sprites/resources/atlases/plains_rock_2_atlas.json"),
    },
    {
        "name": "volcanic_rock",
        "source": "M:/Downloads/volcanic+rock+3d+model.glb",
        "frames": Path("artifacts/rock_shadow_bake/volcanic_rock/frames_512_4variant"),
        "atlas": Path("assets/sprites/resources/atlases/plains_volcanic_rock_atlas.png"),
        "metadata": Path("assets/sprites/resources/atlases/plains_volcanic_rock_atlas.json"),
    },
]


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return (0, 0, image.width, image.height)
    return bbox


def bottom_darken(image: Image.Image, strength: float = 0.13, start_y: float = 0.54) -> Image.Image:
    src = image.convert("RGBA")
    pixels = src.load()
    bbox = alpha_bbox(src)
    top = bbox[1]
    bottom = max(bbox[3] - 1, top + 1)
    start = top + (bottom - top) * start_y
    span = max(bottom - start, 1.0)
    for y in range(src.height):
        if y < start:
            continue
        t = min(max((y - start) / span, 0.0), 1.0)
        factor = 1.0 - strength * (t * t)
        for x in range(src.width):
            r, g, b, a = pixels[x, y]
            if a <= 12:
                continue
            pixels[x, y] = (int(r * factor), int(g * factor), int(b * factor), a)
    return src


def luminance(pixel: tuple[int, int, int, int]) -> float:
    return pixel[0] * 0.2126 + pixel[1] * 0.7152 + pixel[2] * 0.0722


def border_reference_luma(image: Image.Image) -> float:
    pixels = image.convert("RGBA").load()
    samples: list[float] = []
    width = image.width
    height = image.height
    band = max(8, min(width, height) // 32)
    for y in range(height):
        for x in range(width):
            if x >= band and x < width - band and y >= band and y < height - band:
                continue
            samples.append(luminance(pixels[x, y]))
    samples.sort()
    if not samples:
        return 1.0
    return samples[len(samples) // 2]


def shadow_layer_from_pass(shadow_pass: Image.Image) -> Image.Image:
    src = shadow_pass.convert("RGBA")
    reference = max(border_reference_luma(src), 1.0)
    alpha = Image.new("L", src.size, 0)
    src_pixels = src.load()
    alpha_pixels = alpha.load()
    for y in range(src.height):
        for x in range(src.width):
            darkening = max(0.0, (reference - luminance(src_pixels[x, y])) / reference)
            if darkening <= 0.010:
                continue
            value = min(170, int((darkening - 0.010) * 820.0))
            alpha_pixels[x, y] = value
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=0.8))
    shadow = Image.new("RGBA", src.size, SHADOW_COLOR)
    shadow.putalpha(alpha)
    return shadow


def cleanup_tiny_alpha(image: Image.Image) -> Image.Image:
    src = image.convert("RGBA")
    pixels = src.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = pixels[x, y]
            if a <= 2:
                pixels[x, y] = (0, 0, 0, 0)
    return src


def frame_paths(frames_dir: Path, asset_name: str, unique_index: int) -> tuple[Path, Path, Path]:
    degrees = unique_index * 90
    stem = f"{asset_name}_rot_{unique_index:02d}_{degrees:03d}deg"
    return (
        frames_dir / f"{stem}.png",
        frames_dir / f"{stem}_object.png",
        frames_dir / f"{stem}_shadow.png",
    )


def composite_two_pass(object_pass: Image.Image, shadow_pass: Image.Image) -> Image.Image:
    object_image = bottom_darken(object_pass)
    result = Image.new("RGBA", object_image.size, (0, 0, 0, 0))
    result.alpha_composite(shadow_layer_from_pass(shadow_pass))
    result.alpha_composite(object_image)
    return cleanup_tiny_alpha(result)


def make_checker(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, CHECKER_A)
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=CHECKER_B)
    return image


def load_unique_frames(asset: dict[str, object]) -> list[Image.Image]:
    asset_name = str(asset["name"])
    frames_dir = Path(asset["frames"])
    frames: list[Image.Image] = []
    for unique_index in range(UNIQUE_VARIANTS):
        final_path, object_path, shadow_path = frame_paths(frames_dir, asset_name, unique_index)
        if object_path.exists() and shadow_path.exists():
            frame = composite_two_pass(Image.open(object_path), Image.open(shadow_path))
            frame.save(final_path)
        else:
            if not final_path.exists():
                raise FileNotFoundError(final_path)
            frame = Image.open(final_path).convert("RGBA")
        if frame.size != (FRAME_SIZE, FRAME_SIZE):
            raise RuntimeError(f"Unexpected frame size for {asset_name} #{unique_index}: {frame.size}")
        frames.append(frame)
    return frames


def build_atlas(unique_frames: list[Image.Image]) -> tuple[Image.Image, list[dict[str, int | str]]]:
    atlas = Image.new("RGBA", (FRAME_SIZE * COLUMNS, FRAME_SIZE * ROWS), (0, 0, 0, 0))
    frame_records: list[dict[str, int | str]] = []
    for index in range(FRAME_COUNT):
        source_index = index % UNIQUE_VARIANTS
        x = (index % COLUMNS) * FRAME_SIZE
        y = (index // COLUMNS) * FRAME_SIZE
        atlas.alpha_composite(unique_frames[source_index], (x, y))
        frame_records.append({
            "index": index,
            "source_unique_index": source_index,
            "angle_degrees": source_index * 90,
            "x": x,
            "y": y,
            "width": FRAME_SIZE,
            "height": FRAME_SIZE,
        })
    return atlas, frame_records


def make_preview(atlas: Image.Image, asset_name: str, output_dir: Path) -> None:
    preview_size = (FRAME_SIZE * UNIQUE_VARIANTS, FRAME_SIZE)
    ground = Image.new("RGBA", preview_size, GROUND_COLOR)
    checker = make_checker(preview_size)
    for index in range(UNIQUE_VARIANTS):
        crop = atlas.crop((
            index * FRAME_SIZE,
            0,
            (index + 1) * FRAME_SIZE,
            FRAME_SIZE,
        ))
        ground.alpha_composite(crop, (index * FRAME_SIZE, 0))
        checker.alpha_composite(crop, (index * FRAME_SIZE, 0))
    ground.save(output_dir / f"{asset_name}_4variant_ground_preview.png")
    checker.save(output_dir / f"{asset_name}_4variant_checker_preview.png")


def write_metadata(asset: dict[str, object], frame_records: list[dict[str, int | str]]) -> None:
    metadata_path = Path(asset["metadata"])
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "source": str(asset["source"]),
        "sprite_sheet": Path(asset["atlas"]).name,
        "frame_count": FRAME_COUNT,
        "unique_variant_count": UNIQUE_VARIANTS,
        "columns": COLUMNS,
        "rows": ROWS,
        "frame_width": FRAME_SIZE,
        "frame_height": FRAME_SIZE,
        "camera": "orthographic top-front, 63 degree elevation, no side yaw",
        "shadows": "cycles two-pass render; real ground shadow pass composited under sprite",
        "postprocess": "two-pass object/shadow composite; slight bottom darken applied to object pixels",
        "native_packet_compatibility": "32 frame slots, four unique variants repeated by index % 4",
        "frames": frame_records,
    }
    metadata_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> None:
    output_dir = Path("artifacts/rock_shadow_bake/previews")
    output_dir.mkdir(parents=True, exist_ok=True)
    for asset in ASSETS:
        asset_name = str(asset["name"])
        unique_frames = load_unique_frames(asset)
        atlas, frame_records = build_atlas(unique_frames)
        atlas_path = Path(asset["atlas"])
        atlas_path.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(atlas_path)
        write_metadata(asset, frame_records)
        make_preview(atlas, asset_name, output_dir)
        print(f"assembled {asset_name} -> {atlas_path}")
    print(f"previews -> {output_dir}")


if __name__ == "__main__":
    main()
