"""Postprocess one layered tree bake into game-ready helper textures."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("asset_dir", type=Path)
    parser.add_argument("--copy-to", type=Path, default=None)
    return parser.parse_args()


def load_rgba(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Missing image: {path}")
    return Image.open(path).convert("RGBA")


def alpha_of(image: Image.Image) -> Image.Image:
    return image.getchannel("A")


def union_alpha(*images: Image.Image) -> Image.Image:
    result = Image.new("L", images[0].size, 0)
    for image in images:
        result = ImageChops.lighter(result, alpha_of(image))
    return result


def fake_shadow_from_alpha(alpha: Image.Image, anchor: tuple[int, int]) -> Image.Image:
    width, height = alpha.size
    anchor_x, anchor_y = anchor
    bbox = alpha.getbbox()
    if bbox is None:
        return Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    cropped = alpha.crop(bbox)
    shadow_h = max(1, int(round(cropped.height * 0.34)))
    shadow = cropped.resize((cropped.width, shadow_h), Image.Resampling.BICUBIC)
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    canvas = Image.new("L", alpha.size, 0)
    # Screen-space north-east from the root: right and up, but root remains attached.
    paste_x = int(round(anchor_x - cropped.width * 0.24))
    paste_y = int(round(anchor_y - shadow_h * 0.56))
    canvas.paste(shadow, (paste_x, paste_y), shadow)
    canvas = canvas.point(lambda value: min(int(value * 0.62), 170), "L")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", alpha.size, 18),
            Image.new("L", alpha.size, 13),
            Image.new("L", alpha.size, 8),
            canvas,
        ),
    )


def processed_shadow(raw_shadow: Image.Image, albedo_alpha: Image.Image, anchor: tuple[int, int]) -> Image.Image:
    raw_alpha = alpha_of(raw_shadow)
    cleaned: Image.Image | None = None
    for threshold in (6, 8, 10, 12):
        thresholded = raw_alpha.point(lambda value, threshold=threshold: 255 if value > threshold else 0, "L")
        bbox = thresholded.getbbox()
        if bbox is None:
            continue
        coverage_bbox = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
        coverage = coverage_bbox / float(raw_alpha.width * raw_alpha.height)
        if coverage > 0.72:
            continue
        cleaned = raw_alpha.point(
            lambda value, threshold=threshold: 0 if value <= threshold else min(int((value - threshold) * 1.55), 205),
            "L",
        )
        break
    if cleaned is None:
        return fake_shadow_from_alpha(albedo_alpha, anchor)
    alpha = cleaned.filter(ImageFilter.GaussianBlur(1.8))
    alpha = alpha.point(lambda value: 0 if value < 2 else min(int(value * 1.08), 215), "L")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", raw_shadow.size, 15),
            Image.new("L", raw_shadow.size, 11),
            Image.new("L", raw_shadow.size, 7),
            alpha,
        ),
    )


def make_wind_mask(trunk: Image.Image, foliage: Image.Image) -> Image.Image:
    trunk_a = alpha_of(trunk)
    foliage_a = alpha_of(foliage)
    union = ImageChops.lighter(trunk_a, foliage_a)
    width, height = union.size
    gray = Image.new("L", union.size, 0)
    pixels = gray.load()
    fa = foliage_a.load()
    ta = trunk_a.load()
    for y in range(height):
        vertical = 0.35 + 0.65 * max(0.0, 1.0 - y / max(height - 1, 1))
        for x in range(width):
            f = fa[x, y]
            t = ta[x, y]
            if f <= 4:
                if t > 4:
                    pixels[x, y] = 0
                continue
            # Leaf clusters move; pixels overlapping trunk are damped.
            damp = 0.35 if t > 20 else 1.0
            pixels[x, y] = min(255, int(f * vertical * damp))
    return Image.merge("RGBA", (gray, gray, gray, union))


def make_snow_mask(albedo: Image.Image, foliage: Image.Image, trunk: Image.Image) -> Image.Image:
    alpha = union_alpha(albedo)
    foliage_alpha = alpha_of(foliage)
    trunk_alpha = alpha_of(trunk)
    width, height = alpha.size
    foliage_px = foliage_alpha.load()
    trunk_px = trunk_alpha.load()
    gray = Image.new("L", alpha.size, 0)
    gray_px = gray.load()

    def paint_runs(source_px, *, depth_px: int, weight: float, trunk_damping: float) -> None:
        for x in range(width):
            y = 0
            while y < height:
                while y < height and source_px[x, y] <= 18:
                    y += 1
                run_start = y
                while y < height and source_px[x, y] > 18:
                    y += 1
                run_end = y
                run_height = run_end - run_start
                if run_height < 5:
                    continue
                local_depth = max(8, min(depth_px, int(run_height * 0.58)))
                local_depth = int(local_depth * (0.88 + 0.16 * math.sin(x * 0.067)))
                for yy in range(run_start, min(run_end, run_start + local_depth)):
                    source_alpha = source_px[x, yy]
                    if source_alpha <= 18:
                        continue
                    depth = (yy - run_start) / max(local_depth - 1, 1)
                    contour = (1.0 - depth) ** 1.35
                    noise = (
                        0.82
                        + 0.16 * math.sin(x * 0.17 + yy * 0.09)
                        + 0.10 * math.sin(x * 0.041 - yy * 0.13)
                        + 0.06 * math.sin(x * 0.31 + yy * 0.27)
                    )
                    overlap_damp = trunk_damping if trunk_px[x, yy] > 20 else 1.0
                    coverage = 0.42 + 0.58 * (source_alpha / 255.0)
                    value = int(255.0 * contour * noise * coverage * weight * overlap_damp)
                    if value > gray_px[x, yy]:
                        gray_px[x, yy] = max(0, min(255, value))

    paint_runs(foliage_px, depth_px=66, weight=1.0, trunk_damping=0.42)
    paint_runs(trunk_px, depth_px=24, weight=0.22, trunk_damping=1.0)
    gray = gray.filter(ImageFilter.GaussianBlur(0.45))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def make_snow_overlay(snow_mask: Image.Image) -> Image.Image:
    snow = snow_mask.getchannel("R")
    alpha = snow.point(lambda value: 0 if value < 16 else min(int((value - 10) * 1.18), 232), "L")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", snow.size, 242),
            Image.new("L", snow.size, 237),
            Image.new("L", snow.size, 224),
            alpha,
        ),
    )


def make_height(albedo: Image.Image) -> Image.Image:
    alpha = alpha_of(albedo)
    luminance = albedo.convert("L")
    height = ImageChops.multiply(alpha, luminance)
    height = height.filter(ImageFilter.GaussianBlur(1.2))
    return height


def make_normal_from_height(height: Image.Image, strength: float = 3.2) -> Image.Image:
    width, h = height.size
    src = height.load()
    out = Image.new("RGBA", height.size, (128, 128, 255, 255))
    pix = out.load()
    for y in range(h):
        for x in range(width):
            left = src[max(0, x - 1), y] / 255.0
            right = src[min(width - 1, x + 1), y] / 255.0
            up = src[x, max(0, y - 1)] / 255.0
            down = src[x, min(h - 1, y + 1)] / 255.0
            dx = (left - right) * strength
            dy = (up - down) * strength
            dz = 1.0
            length = math.sqrt(dx * dx + dy * dy + dz * dz)
            nx = dx / length
            ny = dy / length
            nz = dz / length
            pix[x, y] = (
                int((nx * 0.5 + 0.5) * 255),
                int((ny * 0.5 + 0.5) * 255),
                int((nz * 0.5 + 0.5) * 255),
                255,
            )
    out.putalpha(height.point(lambda value: 255 if value > 2 else 0, "L"))
    return out


def alpha_bbox(image: Image.Image) -> list[int]:
    bbox = alpha_of(image).getbbox()
    if bbox is None:
        return [0, 0, 0, 0]
    x0, y0, x1, y1 = bbox
    return [x0, y0, x1 - x0, y1 - y0]


def composite_on_ground(*layers: Image.Image) -> Image.Image:
    width, height = layers[0].size
    bg = Image.new("RGBA", (width, height), (43, 39, 33, 255))
    draw = ImageDraw.Draw(bg)
    for y in range(0, height, 28):
        color = (48 + (y // 28) % 2 * 5, 43, 35, 255)
        draw.rectangle((0, y, width, y + 14), fill=color)
    for layer in layers:
        bg.alpha_composite(layer)
    return bg


def make_preview(asset_dir: Path, albedo: Image.Image, trunk: Image.Image, foliage: Image.Image, shadow: Image.Image, wind_mask: Image.Image, snow_mask: Image.Image, snow_overlay: Image.Image) -> Image.Image:
    tile_w, tile_h = albedo.size
    scale = 0.5
    panels = [
        ("albedo", composite_on_ground(albedo)),
        ("layered", composite_on_ground(shadow, trunk, foliage)),
        ("snow overlay", composite_on_ground(shadow, trunk, foliage, snow_overlay)),
        ("wind mask", wind_mask),
        ("snow mask", snow_mask),
    ]
    thumb_w = int(tile_w * scale)
    thumb_h = int(tile_h * scale)
    label_h = 28
    canvas = Image.new("RGBA", (thumb_w * len(panels), thumb_h + label_h), (22, 22, 20, 255))
    draw = ImageDraw.Draw(canvas)
    for index, (label, image) in enumerate(panels):
        thumb = image.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = index * thumb_w
        canvas.alpha_composite(thumb, (x, label_h))
        draw.text((x + 8, 7), label, fill=(230, 220, 200, 255))
    return canvas


def save_outputs(asset_dir: Path, copy_to: Path | None = None) -> None:
    albedo = load_rgba(asset_dir / "albedo.png")
    trunk = load_rgba(asset_dir / "trunk.png")
    foliage = load_rgba(asset_dir / "foliage.png")
    raw_shadow = load_rgba(asset_dir / "shadow_raw.png")
    classification_path = asset_dir / "classification.json"
    with classification_path.open("r", encoding="utf-8") as fh:
        classification = json.load(fh)
    anchor_values = classification.get("anchor", [albedo.width // 2, int(albedo.height * 0.88)])
    anchor = (int(anchor_values[0]), int(anchor_values[1]))

    alpha = alpha_of(albedo)
    shadow = processed_shadow(raw_shadow, alpha, anchor)
    wind_mask = make_wind_mask(trunk, foliage)
    snow_mask = make_snow_mask(albedo, foliage, trunk)
    snow_overlay = make_snow_overlay(snow_mask)
    height = make_height(albedo)
    normal = make_normal_from_height(height)

    outputs = {
        "shadow.png": shadow,
        "wind_mask.png": wind_mask,
        "snow_mask.png": snow_mask,
        "snow_overlay.png": snow_overlay,
        "height.png": height.convert("RGBA"),
        "normal.png": normal,
    }
    for name, image in outputs.items():
        image.save(asset_dir / name)

    meta = {
        "asset": "tree_01_layered_glb",
        "source_glb": classification.get("source_glb", ""),
        "frame_width": albedo.width,
        "frame_height": albedo.height,
        "anchor": list(anchor),
        "sort_offset": anchor[1],
        "collision_radius": 18,
        "wind_strength": 0.45,
        "snow_capacity": 0.8,
        "layers": {
            "albedo": "albedo.png",
            "trunk": "trunk.png",
            "foliage": "foliage.png",
            "shadow": "shadow.png",
            "wind_mask": "wind_mask.png",
            "snow_mask": "snow_mask.png",
            "snow_overlay": "snow_overlay.png",
            "height": "height.png",
            "normal": "normal.png",
        },
        "alpha_bbox": alpha_bbox(albedo),
        "notes": "Prototype layered tree asset from one GLB. Static trunk/foliage layers; runtime wind should use wind_mask and keep trunk/root pinned.",
    }
    with (asset_dir / "meta.json").open("w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent="\t", ensure_ascii=False)

    preview = make_preview(asset_dir, albedo, trunk, foliage, shadow, wind_mask, snow_mask, snow_overlay)
    preview.save(asset_dir / "preview_panel.png")

    if copy_to is not None:
        copy_to.mkdir(parents=True, exist_ok=True)
        for name in [
            "albedo.png",
            "trunk.png",
            "foliage.png",
            "shadow.png",
            "wind_mask.png",
            "snow_mask.png",
            "snow_overlay.png",
            "height.png",
            "normal.png",
            "meta.json",
            "preview_panel.png",
        ]:
            Image.open(asset_dir / name).save(copy_to / name) if name.endswith(".png") else (copy_to / name).write_text((asset_dir / name).read_text(encoding="utf-8"), encoding="utf-8")


def main() -> None:
    args = parse_args()
    if not args.asset_dir.is_dir():
        raise SystemExit(f"Asset directory does not exist: {args.asset_dir}")
    save_outputs(args.asset_dir, args.copy_to)
    print(f"Wrote layered tree helper textures to {args.asset_dir}")


if __name__ == "__main__":
    main()
