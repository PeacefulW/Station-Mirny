"""Pack Blender grass tuft frames and derive cheap runtime helper atlases."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter


DEFAULT_PROFILE_PATH = Path(__file__).with_name("grass_tuft_bake_profile.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    return parser.parse_args()


def load_profile(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 1.0 if value >= edge1 else 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def expected_frame_paths(frames_dir: Path, frame_count: int) -> list[Path]:
    return [frames_dir / f"frame_{index:02d}.png" for index in range(frame_count)]


def expected_shadow_frame_paths(frames_dir: Path, frame_count: int) -> list[Path]:
    return [frames_dir / ("shadow_frame_%02d.png" % index) for index in range(frame_count)]


def load_frames(frames_dir: Path, frame_count: int) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for path in expected_frame_paths(frames_dir, frame_count):
        if not path.is_file():
            raise SystemExit(f"Missing grass frame: {path}")
        frames.append(Image.open(path).convert("RGBA"))
    return frames


def load_shadow_frames(frames_dir: Path, frame_count: int) -> list[Image.Image]:
    paths = expected_shadow_frame_paths(frames_dir, frame_count)
    if not all(path.is_file() for path in paths):
        return []
    return [Image.open(path).convert("RGBA") for path in paths]


def atlas_cell_box(index: int, columns: int, frame_width: int, frame_height: int) -> tuple[int, int, int, int]:
    x = (index % columns) * frame_width
    y = (index // columns) * frame_height
    return (x, y, x + frame_width, y + frame_height)


def pack_atlas(frames: list[Image.Image], columns: int, rows: int) -> Image.Image:
    if not frames:
        raise ValueError("No frames to pack.")
    frame_width, frame_height = frames[0].size
    atlas = Image.new("RGBA", (frame_width * columns, frame_height * rows), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        if frame.size != (frame_width, frame_height):
            raise ValueError(f"Frame {index} has size {frame.size}, expected {(frame_width, frame_height)}.")
        atlas.alpha_composite(frame, (atlas_cell_box(index, columns, frame_width, frame_height)[0:2]))
    return atlas


def grade_albedo_to_reference(albedo: Image.Image, profile: dict) -> Image.Image:
    multipliers = profile["postprocess"].get("albedo_grade_rgb_multiply")
    if multipliers is None:
        return albedo
    r_mul, g_mul, b_mul = (float(value) for value in multipliers)
    red, green, blue, alpha = albedo.convert("RGBA").split()
    return Image.merge(
        "RGBA",
        (
            red.point(lambda value: max(0, min(255, int(value * r_mul))), "L"),
            green.point(lambda value: max(0, min(255, int(value * g_mul))), "L"),
            blue.point(lambda value: max(0, min(255, int(value * b_mul))), "L"),
            alpha,
        ),
    )


def make_wind_mask_from_alpha(alpha: Image.Image) -> Image.Image:
    alpha = alpha.convert("L")
    width, height = alpha.size
    out = Image.new("L", alpha.size, 0)
    src = alpha.load()
    dst = out.load()
    for y in range(height):
        topness = 1.0 - y / max(height - 1, 1)
        bottomness = y / max(height - 1, 1)
        root_pin = smoothstep(0.10, 0.30, 1.0 - bottomness)
        blade_weight = (topness ** 0.72) * root_pin
        for x in range(width):
            a = src[x, y]
            if a <= 2:
                continue
            dst[x, y] = min(255, int(a * blade_weight))
    return out.filter(ImageFilter.GaussianBlur(0.35))


def make_fake_shadow_from_alpha(
    alpha: Image.Image,
    *,
    shadow_rgb: tuple[int, int, int],
) -> Image.Image:
    alpha = alpha.convert("L")
    bbox = alpha.getbbox()
    if bbox is None:
        return Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = bbox
    cropped = alpha.crop(bbox)
    shadow_width = max(1, int(round(cropped.width * 0.96)))
    shadow_height = max(1, int(round(cropped.height * 0.34)))
    shadow = cropped.resize((shadow_width, shadow_height), Image.Resampling.BICUBIC)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2.2))
    canvas = Image.new("L", alpha.size, 0)

    # Match the authored layered-tree shadow axis in PNG space: right and up.
    # Runtime rotates this bake-space north-east vector around the root onto
    # the canonical south-east cast direction.
    center_x = (x0 + x1) * 0.5 + cropped.height * 0.34
    center_y = y1 - cropped.height * 0.72
    paste_x = int(round(center_x - shadow_width * 0.5))
    paste_y = int(round(center_y - shadow_height * 0.5))

    margin = 2
    paste_x = max(margin, paste_x)
    paste_y = max(margin, paste_y)
    max_width = max(1, alpha.width - margin - paste_x)
    max_height = max(1, alpha.height - margin - paste_y)
    if shadow.width > max_width or shadow.height > max_height:
        fit = min(max_width / shadow.width, max_height / shadow.height)
        new_size = (
            max(1, int(math.floor(shadow.width * fit))),
            max(1, int(math.floor(shadow.height * fit))),
        )
        shadow = shadow.resize(new_size, Image.Resampling.BICUBIC)
    paste_x = min(paste_x, alpha.width - margin - shadow.width)
    paste_y = min(paste_y, alpha.height - margin - shadow.height)

    canvas.paste(shadow, (paste_x, paste_y), shadow)
    canvas = canvas.point(lambda value: 0 if value < 3 else min(int(value * 0.62), 160), "L")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", alpha.size, shadow_rgb[0]),
            Image.new("L", alpha.size, shadow_rgb[1]),
            Image.new("L", alpha.size, shadow_rgb[2]),
            canvas,
        ),
    )


def edge_fade_mask(size: tuple[int, int], fade_px: int) -> Image.Image:
    """Soft ramp to zero within fade_px of every frame edge so a shadow that
    reaches the frame border dissolves instead of cutting off in a line."""
    width, height = size
    mask = Image.new("L", size, 255)
    px = mask.load()
    for y in range(height):
        edge_y = min(y, height - 1 - y)
        for x in range(width):
            edge = min(x, width - 1 - x, edge_y)
            if edge < fade_px:
                px[x, y] = int(255 * (edge + 1) / (fade_px + 1))
    return mask


def processed_shadow_from_raw(
    raw_shadow: Image.Image,
    albedo_alpha: Image.Image,
    *,
    profile: dict,
) -> Image.Image:
    raw_alpha = raw_shadow.convert("RGBA").getchannel("A")
    cleaned: Image.Image | None = None
    thresholds = profile["postprocess"].get("processed_shadow_thresholds", [3, 5, 7, 9])
    for threshold in thresholds:
        thresholded = raw_alpha.point(lambda value, threshold=threshold: 255 if value > threshold else 0, "L")
        bbox = thresholded.getbbox()
        if bbox is None:
            continue
        coverage = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / float(raw_alpha.width * raw_alpha.height)
        if coverage > 0.74:
            continue
        cleaned = raw_alpha.point(
            lambda value, threshold=threshold: 0 if value <= threshold else min(int((value - threshold) * 1.72), 215),
            "L",
        )
        break
    if cleaned is None:
        fake_rgb = tuple(int(v) for v in profile["postprocess"].get("fake_shadow_rgb", profile["postprocess"]["shadow_rgb"]))
        return make_fake_shadow_from_alpha(albedo_alpha, shadow_rgb=fake_rgb)
    alpha = cleaned.filter(ImageFilter.GaussianBlur(1.2))
    alpha = alpha.point(lambda value: 0 if value < 2 else min(int(value * 1.16), 220), "L")
    fade_px = int(profile["postprocess"].get("shadow_edge_fade_px", 0))
    if fade_px > 0:
        alpha = ImageChops.multiply(alpha, edge_fade_mask(alpha.size, fade_px))
    shadow_rgb = tuple(int(v) for v in profile["postprocess"]["shadow_rgb"])
    return Image.merge(
        "RGBA",
        (
            Image.new("L", raw_shadow.size, shadow_rgb[0]),
            Image.new("L", raw_shadow.size, shadow_rgb[1]),
            Image.new("L", raw_shadow.size, shadow_rgb[2]),
            alpha,
        ),
    )


def make_snow_mask_from_alpha(alpha: Image.Image) -> Image.Image:
    alpha = alpha.convert("L")
    width, height = alpha.size
    out = Image.new("L", alpha.size, 0)
    src = alpha.load()
    dst = out.load()
    for y in range(height):
        topness = 1.0 - y / max(height - 1, 1)
        for x in range(width):
            current = src[x, y]
            if current <= 8:
                continue
            above = 0
            for sy in (y - 2, y - 5, y - 8):
                if sy < 0:
                    continue
                for sx in range(max(0, x - 2), min(width, x + 3)):
                    above = max(above, src[sx, sy])
            exposed = max(0.0, (current - above * 0.54) / 255.0)
            if above <= 8:
                exposed = max(exposed, current / 255.0 * 0.72)
            vertical_gain = smoothstep(0.18, 0.88, topness)
            value = exposed * vertical_gain * 255.0
            if value > 4.0:
                dst[x, y] = min(255, int(value))
    return out.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.85))


def make_snow_overlay(snow_mask: Image.Image, snow_rgb: tuple[int, int, int]) -> Image.Image:
    snow = snow_mask.convert("L")
    alpha = snow.point(lambda value: 0 if value < 10 else min(238, int(value * 1.36)), "L")
    return Image.merge(
        "RGBA",
        (
            Image.new("L", snow.size, snow_rgb[0]),
            Image.new("L", snow.size, snow_rgb[1]),
            Image.new("L", snow.size, snow_rgb[2]),
            alpha,
        ),
    )


def make_season_mask(alpha: Image.Image, snow_mask: Image.Image) -> Image.Image:
    alpha = alpha.convert("L")
    snow = snow_mask.convert("L")
    width, height = alpha.size
    desaturate = Image.new("L", alpha.size, 0)
    bury = Image.new("L", alpha.size, 0)
    a_px = alpha.load()
    d_px = desaturate.load()
    b_px = bury.load()
    s_px = snow.load()
    for y in range(height):
        topness = 1.0 - y / max(height - 1, 1)
        for x in range(width):
            a = a_px[x, y]
            if a <= 4:
                continue
            wave = 0.5 + 0.25 * math.sin(x * 0.27 + y * 0.11) + 0.15 * math.sin(x * 0.07 - y * 0.31)
            d_px[x, y] = min(255, int(max(s_px[x, y], a * (0.36 + wave * 0.28))))
            b_px[x, y] = min(255, int(a * smoothstep(0.25, 0.95, topness) * 0.56))
    return Image.merge("RGBA", (snow, desaturate, bury, alpha))


def winterize_albedo(albedo: Image.Image, snow_overlay: Image.Image, winter_leaf_rgb: tuple[int, int, int]) -> Image.Image:
    base = albedo.convert("RGBA")
    alpha = base.getchannel("A")
    gray = ImageEnhance.Color(base).enhance(0.22)
    tint = Image.new("RGBA", base.size, (*winter_leaf_rgb, 0))
    tint.putalpha(alpha.point(lambda value: int(value * 0.48), "L"))
    gray.alpha_composite(tint)
    gray.alpha_composite(snow_overlay)
    return gray


def make_atlas_from_alpha(
    albedo_atlas: Image.Image,
    columns: int,
    frame_count: int,
    maker,
    *args,
    **kwargs,
) -> Image.Image:
    frame_width = albedo_atlas.width // columns
    frame_height = albedo_atlas.height // max(1, math.ceil(frame_count / columns))
    frames: list[Image.Image] = []
    for index in range(frame_count):
        box = atlas_cell_box(index, columns, frame_width, frame_height)
        alpha = albedo_atlas.crop(box).getchannel("A")
        frames.append(maker(alpha, *args, **kwargs).convert("RGBA"))
    return pack_atlas(frames, columns, math.ceil(frame_count / columns))


def compose_preview_panel(images: dict[str, Image.Image]) -> Image.Image:
    labels = [
        ("albedo", images["albedo"]),
        ("shadow", images["shadow"]),
        ("wind mask", images["wind"]),
        ("snow mask", images["snow"]),
        ("winter", images["winter"]),
    ]
    thumb_w = 256
    label_h = 30
    thumbs: list[tuple[str, Image.Image]] = []
    for label, image in labels:
        ratio = thumb_w / image.width
        thumb = image.resize((thumb_w, int(image.height * ratio)), Image.Resampling.LANCZOS)
        thumbs.append((label, thumb))
    panel_w = thumb_w * len(thumbs)
    panel_h = max(thumb.height for _label, thumb in thumbs) + label_h
    panel = Image.new("RGBA", (panel_w, panel_h), (31, 30, 26, 255))
    draw = ImageDraw.Draw(panel)
    for index, (label, thumb) in enumerate(thumbs):
        x = index * thumb_w
        panel.alpha_composite(thumb, (x, label_h))
        draw.text((x + 8, 8), label, fill=(232, 222, 202, 255))
    return panel


def save_outputs(frames_dir: Path, out_dir: Path, profile: dict) -> None:
    atlas_profile = profile["atlas"]
    columns = int(atlas_profile["columns"])
    rows = int(atlas_profile["rows"])
    frame_count = int(atlas_profile["frame_count"])
    out_dir.mkdir(parents=True, exist_ok=True)

    frames = load_frames(frames_dir, frame_count)
    shadow_frames = load_shadow_frames(frames_dir, frame_count)
    albedo = grade_albedo_to_reference(pack_atlas(frames, columns, rows), profile)
    shadow_rgb = tuple(int(v) for v in profile["postprocess"]["shadow_rgb"])
    snow_rgb = tuple(int(v) for v in profile["postprocess"]["snow_rgb"])
    winter_leaf_rgb = tuple(int(v) for v in profile["postprocess"]["winter_leaf_rgb"])

    if shadow_frames:
        shadow_frames_processed: list[Image.Image] = []
        frame_width, frame_height = frames[0].size
        for index, raw_shadow in enumerate(shadow_frames):
            box = atlas_cell_box(index, columns, frame_width, frame_height)
            shadow_frames_processed.append(
                processed_shadow_from_raw(raw_shadow, albedo.crop(box).getchannel("A"), profile=profile)
            )
        shadow = pack_atlas(shadow_frames_processed, columns, rows)
        shadow_source = "blender_shadow_catcher"
    else:
        shadow = make_atlas_from_alpha(albedo, columns, frame_count, make_fake_shadow_from_alpha, shadow_rgb=shadow_rgb)
        shadow_source = "alpha_fake_fallback"
    wind = make_atlas_from_alpha(albedo, columns, frame_count, make_wind_mask_from_alpha)
    snow = make_atlas_from_alpha(albedo, columns, frame_count, make_snow_mask_from_alpha)
    snow_overlay = Image.new("RGBA", albedo.size, (0, 0, 0, 0))
    season = Image.new("RGBA", albedo.size, (0, 0, 0, 0))
    winter = Image.new("RGBA", albedo.size, (0, 0, 0, 0))
    frame_width, frame_height = frames[0].size
    for index in range(frame_count):
        box = atlas_cell_box(index, columns, frame_width, frame_height)
        frame = albedo.crop(box)
        snow_frame = snow.crop(box).getchannel("R")
        overlay_frame = make_snow_overlay(snow_frame, snow_rgb)
        season_frame = make_season_mask(frame.getchannel("A"), snow_frame)
        winter_frame = winterize_albedo(frame, overlay_frame, winter_leaf_rgb)
        snow_overlay.alpha_composite(overlay_frame, box[0:2])
        season.alpha_composite(season_frame, box[0:2])
        winter.alpha_composite(winter_frame, box[0:2])

    outputs = {
        "grass_tuft_albedo_atlas.png": albedo,
        "grass_tuft_shadow_atlas.png": shadow,
        "grass_tuft_wind_mask_atlas.png": wind,
        "grass_tuft_snow_mask_atlas.png": snow,
        "grass_tuft_snow_overlay_atlas.png": snow_overlay,
        "grass_tuft_season_mask_atlas.png": season,
    }
    for file_name, image in outputs.items():
        image.save(out_dir / file_name)

    preview = compose_preview_panel(
        {
            "albedo": albedo,
            "shadow": shadow,
            "wind": wind,
            "snow": snow,
            "winter": winter,
        }
    )
    preview.save(out_dir / "preview_panel.png")

    meta = {
        "asset": "blender_grass_tuft_prototype",
        "profile_id": profile["profile_id"],
        "inherits_profile_id": profile["inherits_profile_id"],
        "atlas": atlas_profile,
        "source_frames": str(frames_dir),
        "shadow_source": shadow_source,
        "outputs": list(outputs.keys()) + ["preview_panel.png"],
        "runtime_note": "Prototype only; live grass_tuft_atlas.png is not replaced.",
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent="\t", ensure_ascii=False), encoding="utf-8")


def main() -> None:
    args = parse_args()
    save_outputs(args.frames_dir, args.out_dir, load_profile(args.profile))
    print(f"Wrote grass tuft prototype atlases to {args.out_dir}")


if __name__ == "__main__":
    main()
