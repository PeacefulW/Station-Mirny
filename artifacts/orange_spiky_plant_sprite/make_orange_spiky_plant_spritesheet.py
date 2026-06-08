import json
import sys
from pathlib import Path

from PIL import Image, ImageFilter


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return (0, 0, image.width, image.height)
    return bbox


def bottom_darken(image: Image.Image, strength: float = 0.18, start_y: float = 0.47) -> Image.Image:
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
            if darkening <= 0.018:
                continue
            value = min(125, int((darkening - 0.018) * 520.0))
            alpha_pixels[x, y] = value
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=0.7))
    shadow = Image.new("RGBA", src.size, (34, 25, 16, 0))
    shadow.putalpha(alpha)
    return shadow


def composite_two_pass(object_pass: Image.Image, shadow_pass: Image.Image) -> Image.Image:
    object_image = bottom_darken(object_pass)
    result = Image.new("RGBA", object_image.size, (0, 0, 0, 0))
    result.alpha_composite(shadow_layer_from_pass(shadow_pass))
    result.alpha_composite(object_image)
    return cleanup_tiny_alpha(result)


def cleanup_tiny_alpha(image: Image.Image) -> Image.Image:
    src = image.convert("RGBA")
    pixels = src.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = pixels[x, y]
            if a <= 2:
                pixels[x, y] = (0, 0, 0, 0)
    return src


def main() -> None:
    if len(sys.argv) != 6:
        raise SystemExit(
            "Usage: python make_orange_spiky_plant_spritesheet.py "
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
        raw_path = render_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg_raw.png"
        object_path = render_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg_object.png"
        shadow_path = render_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg_shadow.png"
        if object_path.exists() and shadow_path.exists():
            image = composite_two_pass(Image.open(object_path), Image.open(shadow_path))
        else:
            if not raw_path.exists():
                raise FileNotFoundError(raw_path)
            image = bottom_darken(Image.open(raw_path))
        frame_path = render_dir / f"{asset_name}_rot_{index:02d}_{degrees:03d}deg.png"
        image.save(frame_path)
        frames.append(image)
        bbox = alpha_bbox(image)
        frame_entries.append(
            {
                "index": index,
                "degrees": degrees,
                "file": frame_path.name,
                "raw_file": raw_path.name,
                "object_file": object_path.name if object_path.exists() else None,
                "shadow_file": shadow_path.name if shadow_path.exists() else None,
                "alpha_bbox": list(bbox),
                "visible_width": bbox[2] - bbox[0],
                "visible_height": bbox[3] - bbox[1],
            }
        )

    atlas = Image.new("RGBA", (frame_size * rotations, frame_size), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, (index * frame_size, 0))
    atlas_path = render_dir / f"{asset_name}_spritesheet_4x{frame_size}.png"
    atlas.save(atlas_path)

    metadata = {
        "asset": asset_name,
        "source_glb": source_glb,
        "atlas": atlas_path.name,
        "columns": rotations,
        "rows": 1,
        "frame_width": frame_size,
        "frame_height": frame_size,
        "frame_count": rotations,
        "rotations_degrees": [entry["degrees"] for entry in frame_entries],
        "camera": "orthographic top-front, 63 degree elevation",
        "lighting": "Cycles two-pass render; top sun with slight front tilt; real ground shadows composited under sprite",
        "postprocess": "two-pass object/shadow composite when pass files exist; slight bottom darken applied to object pixels",
        "frames": frame_entries,
    }
    metadata_path = render_dir / f"{asset_name}_spritesheet_4x{frame_size}.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("Orange spiky plant spritesheet complete")
    print(f"atlas={atlas_path}")
    print(f"metadata={metadata_path}")
    print(f"frames={rotations}")
    print(f"frame_size={frame_size}")


if __name__ == "__main__":
    main()
