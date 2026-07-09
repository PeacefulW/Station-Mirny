"""Postprocess one layered small-rock bake into game-ready helper textures."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

DEFAULT_PROFILE_PATH = Path(__file__).with_name("layered_asset_bake_profile.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("asset_dir", type=Path)
    parser.add_argument("--copy-to", type=Path, default=None)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    return parser.parse_args()


def load_profile(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def bake_profile_summary(profile: dict, classification: dict, frame_size: int) -> dict:
    return {
        "profile_id": profile["profile_id"],
        "version": profile["version"],
        "frame_size": frame_size,
        "sun_azimuth_degrees": float(
            classification.get("sun_angle_degrees", profile["lighting"]["sun_azimuth_degrees"])
        ),
        "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
        "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
        "root_embed_fraction": float(
            classification.get("root_embed_fraction", profile["planting"]["root_embed_fraction"])
        ),
    }


def profile_or_default(profile: dict | None) -> dict:
    return profile if profile is not None else load_profile(DEFAULT_PROFILE_PATH)


def rgb_from_profile(profile: dict, key: str) -> tuple[int, int, int]:
    values = profile["postprocess"][key]
    return int(values[0]), int(values[1]), int(values[2])


def load_rgba(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Missing image: {path}")
    return Image.open(path).convert("RGBA")


def alpha_of(image: Image.Image) -> Image.Image:
    return image.getchannel("A")


def fake_shadow_from_alpha(alpha: Image.Image, anchor: tuple[int, int], profile: dict | None = None) -> Image.Image:
    profile = profile_or_default(profile)
    bbox = alpha.getbbox()
    if bbox is None:
        return Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    cropped = alpha.crop(bbox)
    shadow_h = max(1, int(round(cropped.height * 0.26)))
    shadow = cropped.resize((cropped.width, shadow_h), Image.Resampling.BICUBIC)
    shadow = shadow.filter(ImageFilter.GaussianBlur(5.5))
    canvas = Image.new("L", alpha.size, 0)
    paste_x = int(round(anchor[0] - cropped.width * 0.18))
    paste_y = int(round(anchor[1] - shadow_h * 0.42))
    canvas.paste(shadow, (paste_x, paste_y), shadow)
    canvas = canvas.point(lambda value: min(int(value * 0.56), 150), "L")
    shadow_rgb = rgb_from_profile(profile, "fake_shadow_rgb")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", alpha.size, shadow_rgb[0]),
            Image.new("L", alpha.size, shadow_rgb[1]),
            Image.new("L", alpha.size, shadow_rgb[2]),
            canvas,
        ),
    )


def processed_shadow(
    raw_shadow: Image.Image,
    albedo_alpha: Image.Image,
    anchor: tuple[int, int],
    profile: dict | None = None,
) -> Image.Image:
    profile = profile_or_default(profile)
    raw_alpha = alpha_of(raw_shadow)
    cleaned: Image.Image | None = None
    for threshold in profile["postprocess"]["processed_shadow_thresholds"]:
        thresholded = raw_alpha.point(lambda value, threshold=threshold: 255 if value > threshold else 0, "L")
        bbox = thresholded.getbbox()
        if bbox is None:
            continue
        coverage_bbox = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
        coverage = coverage_bbox / float(raw_alpha.width * raw_alpha.height)
        if coverage > 0.68:
            continue
        cleaned = raw_alpha.point(
            lambda value, threshold=threshold: 0 if value <= threshold else min(int((value - threshold) * 1.7), 205),
            "L",
        )
        break
    if cleaned is None:
        return fake_shadow_from_alpha(albedo_alpha, anchor, profile)
    alpha = cleaned.filter(ImageFilter.GaussianBlur(1.4))
    alpha = alpha.point(lambda value: 0 if value < 2 else min(int(value * 1.06), 205), "L")
    shadow_rgb = rgb_from_profile(profile, "shadow_rgb")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", raw_shadow.size, shadow_rgb[0]),
            Image.new("L", raw_shadow.size, shadow_rgb[1]),
            Image.new("L", raw_shadow.size, shadow_rgb[2]),
            alpha,
        ),
    )


def shifted_luma(image: Image.Image, dx: int, dy: int) -> Image.Image:
    width, height = image.size
    out = Image.new("L", image.size, 0)
    src_x0 = max(0, -dx)
    src_y0 = max(0, -dy)
    src_x1 = min(width, width - dx)
    src_y1 = min(height, height - dy)
    if src_x1 <= src_x0 or src_y1 <= src_y0:
        return out
    crop = image.crop((src_x0, src_y0, src_x1, src_y1))
    out.paste(crop, (src_x0 + dx, src_y0 + dy))
    return out


def procedural_noise(size: tuple[int, int], *, low: int, high: int, phase: float = 0.0) -> Image.Image:
    width, height = size
    out = Image.new("L", size, 0)
    pixels = out.load()
    span = high - low
    for y in range(height):
        for x in range(width):
            value = (
                0.50
                + 0.22 * math.sin(x * 0.083 + y * 0.041 + phase)
                + 0.18 * math.sin(x * 0.019 - y * 0.127 + phase * 1.7)
                + 0.10 * math.sin(x * 0.211 + y * 0.173 + phase * 0.37)
            )
            pixels[x, y] = max(0, min(255, int(low + span * value)))
    return out.filter(ImageFilter.GaussianBlur(0.9))


def exposed_top_edges(source_alpha: Image.Image, *, weight: float = 1.0) -> Image.Image:
    width, height = source_alpha.size
    src = source_alpha.load()
    edge = Image.new("L", source_alpha.size, 0)
    dst = edge.load()
    for y in range(height):
        for x in range(width):
            current = src[x, y]
            if current <= 18:
                continue
            above = 0
            for sample_y in (y - 2, y - 4, y - 7):
                if sample_y < 0:
                    continue
                for sample_x in range(max(0, x - 3), min(width, x + 4)):
                    above = max(above, src[sample_x, sample_y])
            exposure = max(0.0, current - above * 0.62) / 255.0
            if above <= 12:
                exposure = max(exposure, 0.58 * current / 255.0)
            if exposure <= 0.05:
                continue
            dst[x, y] = max(dst[x, y], min(255, int(255.0 * exposure * weight)))
    return edge.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.6))


def spread_snow(edge: Image.Image, target_alpha: Image.Image, *, depth_px: int, strength: float) -> Image.Image:
    accumulation = Image.new("L", edge.size, 0)
    softened_edge = edge.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    for offset in range(0, depth_px, 2):
        progress = offset / max(depth_px - 1, 1)
        decay = (1.0 - progress) ** 1.55
        dx = int(round(math.sin(offset * 0.37) * 2.0 + math.sin(offset * 0.081) * 1.5))
        shifted = shifted_luma(softened_edge, dx, offset)
        blurred = shifted.filter(ImageFilter.GaussianBlur(1.0 + offset * 0.035))
        band = blurred.point(lambda value, decay=decay: min(255, int(value * decay * strength)), "L")
        accumulation = ImageChops.lighter(accumulation, band)
    alpha_gate = target_alpha.point(lambda value: 0 if value <= 12 else min(255, int(value * 1.18)), "L")
    return ImageChops.multiply(accumulation, alpha_gate)


def make_snow_mask(albedo: Image.Image, snow_surface: Image.Image | None) -> Image.Image:
    alpha = alpha_of(albedo)
    edge_snow = spread_snow(exposed_top_edges(alpha, weight=0.82), alpha, depth_px=38, strength=1.08)
    if snow_surface is not None:
        topness = ImageChops.multiply(snow_surface.convert("L"), alpha)
        topness = topness.filter(ImageFilter.GaussianBlur(1.0))
        gray = ImageChops.lighter(edge_snow, topness)
    else:
        gray = edge_snow
    noise = procedural_noise(gray.size, low=148, high=255, phase=0.7)
    gray = ImageChops.multiply(gray, noise)
    gray = gray.point(lambda value: 0 if value < 10 else min(255, int(value * 1.32)), "L")
    gray = gray.filter(ImageFilter.GaussianBlur(1.05))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def make_snow_overlay(snow_mask: Image.Image, profile: dict | None = None) -> Image.Image:
    profile = profile_or_default(profile)
    snow = snow_mask.getchannel("R")
    alpha = snow.point(lambda value: 0 if value < 14 else min(int((value - 8) * 1.30), 235), "L")
    snow_rgb = rgb_from_profile(profile, "snow_rgb")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", snow.size, snow_rgb[0]),
            Image.new("L", snow.size, snow_rgb[1]),
            Image.new("L", snow.size, snow_rgb[2]),
            alpha,
        ),
    )


def make_height(albedo: Image.Image) -> Image.Image:
    alpha = alpha_of(albedo)
    luminance = albedo.convert("L")
    height = ImageChops.multiply(alpha, luminance)
    height = height.filter(ImageFilter.GaussianBlur(1.1))
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


def asset_name_from_dir(asset_dir: Path) -> str:
    return f"{asset_dir.name}_layered_glb"


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


def make_preview(
    albedo: Image.Image,
    shadow: Image.Image,
    snow_mask: Image.Image,
    snow_overlay: Image.Image,
    normal: Image.Image,
) -> Image.Image:
    tile_w, tile_h = albedo.size
    scale = 0.5
    panels = [
        ("albedo", composite_on_ground(albedo)),
        ("shadow", composite_on_ground(shadow, albedo)),
        ("snow overlay", composite_on_ground(shadow, albedo, snow_overlay)),
        ("snow mask", snow_mask),
        ("normal", normal),
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


def save_outputs(asset_dir: Path, copy_to: Path | None = None, profile: dict | None = None) -> None:
    profile = profile_or_default(profile)
    albedo = load_rgba(asset_dir / "albedo.png")
    raw_shadow = load_rgba(asset_dir / "shadow_raw.png")
    snow_surface_path = asset_dir / "snow_surface_raw.png"
    snow_surface = load_rgba(snow_surface_path) if snow_surface_path.exists() else None
    classification_path = asset_dir / "classification.json"
    with classification_path.open("r", encoding="utf-8") as fh:
        classification = json.load(fh)
    anchor_values = classification.get("anchor", [albedo.width // 2, int(albedo.height * 0.72)])
    anchor = (int(anchor_values[0]), int(anchor_values[1]))

    alpha = alpha_of(albedo)
    shadow = processed_shadow(raw_shadow, alpha, anchor, profile)
    snow_mask = make_snow_mask(albedo, snow_surface)
    snow_overlay = make_snow_overlay(snow_mask, profile)
    height = make_height(albedo)
    normal = make_normal_from_height(height, float(profile["postprocess"]["normal_strength"]))

    outputs = {
        "shadow.png": shadow,
        "snow_mask.png": snow_mask,
        "snow_overlay.png": snow_overlay,
        "height.png": height.convert("RGBA"),
        "normal.png": normal,
    }
    for name, image in outputs.items():
        image.save(asset_dir / name)

    meta = {
        "asset": asset_name_from_dir(asset_dir),
        "source_glb": classification.get("source_glb", ""),
        "frame_width": albedo.width,
        "frame_height": albedo.height,
        "anchor": list(anchor),
        "bake_profile": bake_profile_summary(profile, classification, albedo.width),
        "sort_offset": anchor[1],
        "blocks_movement": False,
        "collision_radius": 0,
        "plant_depth_px": int(classification.get("runtime_plant_depth_px", 0)),
        "wind_strength": 0.0,
        "snow_capacity": 0.9,
        "layers": {
            "albedo": "albedo.png",
            "shadow": "shadow.png",
            "snow_mask": "snow_mask.png",
            "snow_overlay": "snow_overlay.png",
            "height": "height.png",
            "normal": "normal.png",
        },
        "alpha_bbox": alpha_bbox(albedo),
        "notes": "Small visual-only rock from one GLB. No collision and no wind mask.",
    }
    with (asset_dir / "meta.json").open("w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent="\t", ensure_ascii=False)

    preview = make_preview(albedo, shadow, snow_mask, snow_overlay, normal)
    preview.save(asset_dir / "preview_panel.png")

    if copy_to is not None:
        copy_to.mkdir(parents=True, exist_ok=True)
        for name in [
            "albedo.png",
            "shadow.png",
            "snow_mask.png",
            "snow_overlay.png",
            "height.png",
            "normal.png",
            "meta.json",
            "preview_panel.png",
        ]:
            source = asset_dir / name
            target = copy_to / name
            if name.endswith(".png"):
                Image.open(source).save(target)
            else:
                target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")


def main() -> None:
    args = parse_args()
    if not args.asset_dir.is_dir():
        raise SystemExit(f"Asset directory does not exist: {args.asset_dir}")
    save_outputs(args.asset_dir, args.copy_to, load_profile(args.profile))
    print(f"Wrote layered rock helper textures to {args.asset_dir}")


if __name__ == "__main__":
    main()
