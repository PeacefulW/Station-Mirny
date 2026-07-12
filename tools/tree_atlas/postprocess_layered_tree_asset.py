"""Postprocess one layered tree bake into game-ready helper textures."""

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
    summary = {
        "profile_id": profile["profile_id"],
        "version": profile["version"],
        "frame_size": frame_size,
        "sun_azimuth_degrees": float(
            classification.get("sun_angle_degrees", profile["lighting"]["sun_azimuth_degrees"])
        ),
        "albedo_sun_elevation_degrees": profile["lighting"]["albedo_sun_elevation_degrees"],
        "albedo_sun_angular_diameter_degrees": float(
            profile["lighting"].get("albedo_sun_angular_diameter_degrees", 0.526)
        ),
        "shadow_sun_elevation_degrees": profile["lighting"]["shadow_sun_elevation_degrees"],
        "root_embed_fraction": float(
            classification.get("root_embed_fraction", profile["planting"]["root_embed_fraction"])
        ),
    }
    lighting = profile["lighting"]
    if "screen_sun_direction" in lighting:
        summary["screen_sun_direction"] = lighting["screen_sun_direction"]
        summary["fixed_shadow_direction"] = lighting["fixed_shadow_direction"]
        summary["fixed_shadow_direction_vector_screen"] = lighting["fixed_shadow_direction_vector_screen"]
        summary["sun_shadow_mode"] = profile["runtime"]["sun_shadow_mode"]
        summary["shadow_contact_lock_source_px"] = float(
            profile["runtime"]["shadow_contact_lock_source_px"]
        )
    kicker = lighting.get("low_opposite_kicker")
    if kicker is not None and bool(kicker.get("enabled", False)):
        summary["low_opposite_kicker"] = kicker
    if "yaw_degrees" in classification:
        summary["yaw_degrees"] = float(classification["yaw_degrees"])
    shadow_casters = profile.get("shadow_casters")
    if shadow_casters is not None:
        summary["suppress_root_parts_max_z"] = float(shadow_casters["suppress_root_parts_max_z"])
    return summary


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


def union_alpha(*images: Image.Image) -> Image.Image:
    result = Image.new("L", images[0].size, 0)
    for image in images:
        result = ImageChops.lighter(result, alpha_of(image))
    return result


def fake_shadow_from_alpha(alpha: Image.Image, anchor: tuple[int, int], profile: dict | None = None) -> Image.Image:
    profile = profile_or_default(profile)
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
        if coverage > 0.72:
            continue
        cleaned = raw_alpha.point(
            lambda value, threshold=threshold: 0 if value <= threshold else min(int((value - threshold) * 1.55), 205),
            "L",
        )
        break
    if cleaned is None:
        return fake_shadow_from_alpha(albedo_alpha, anchor, profile)
    alpha = cleaned.filter(ImageFilter.GaussianBlur(1.8))
    alpha = alpha.point(lambda value: 0 if value < 2 else min(int(value * 1.08), 215), "L")
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


def suppress_shadow_under_root_footprint(
    shadow: Image.Image,
    trunk: Image.Image,
    anchor: tuple[int, int],
    profile: dict | None = None,
) -> Image.Image:
    profile = profile_or_default(profile)
    footprint_profile = profile["postprocess"].get("root_shadow_footprint")
    if footprint_profile is None or not bool(footprint_profile.get("enabled", False)):
        return shadow

    trunk_alpha = alpha_of(trunk)
    anchor_y = int(anchor[1])
    start_y = max(0, anchor_y + int(footprint_profile["band_start_offset_px"]))
    end_y = min(trunk_alpha.height, anchor_y + int(footprint_profile["band_end_offset_px"]) + 1)
    threshold = int(footprint_profile["alpha_threshold"])
    margin = int(footprint_profile["horizontal_margin_px"])
    footprint = Image.new("L", trunk_alpha.size, 0)
    footprint_draw = ImageDraw.Draw(footprint)
    source = trunk_alpha.load()
    for y in range(start_y, end_y):
        occupied = [x for x in range(trunk_alpha.width) if source[x, y] > threshold]
        if not occupied:
            continue
        left = max(0, occupied[0] - margin)
        right = min(trunk_alpha.width - 1, occupied[-1] + margin)
        footprint_draw.line((left, y, right, y), fill=255, width=1)
    footprint = footprint.filter(ImageFilter.GaussianBlur(float(footprint_profile["blur_radius"])))
    strength = float(footprint_profile["strength"])
    keep_mask = footprint.point(lambda value: max(0, 255 - int(value * strength)), "L")
    suppressed_alpha = ImageChops.multiply(alpha_of(shadow), keep_mask)
    red, green, blue, _old_alpha = shadow.split()
    return Image.merge("RGBA", (red, green, blue, suppressed_alpha))


def make_wind_mask(trunk: Image.Image, foliage: Image.Image) -> Image.Image:
    trunk_a = alpha_of(trunk)
    foliage_a = alpha_of(foliage)
    union = ImageChops.lighter(trunk_a, foliage_a)
    width, height = union.size
    trunk_bbox = trunk_a.getbbox() or (0, 0, width, height)
    trunk_top = trunk_bbox[1]
    trunk_height = max(trunk_bbox[3] - trunk_bbox[1], 1)
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
                    trunk_vertical = 1.0 - (y - trunk_top) / trunk_height
                    trunk_motion = max(0.0, min(1.0, (trunk_vertical - 0.12) / 0.68))
                    pixels[x, y] = min(255, int(t * trunk_motion * 0.72))
                continue
            # Leaf clusters move; pixels overlapping trunk are damped.
            damp = 0.58 if t > 20 else 1.0
            pixels[x, y] = min(255, int(f * vertical * damp))
    return Image.merge("RGBA", (gray, gray, gray, union))


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


def exposed_top_edges(
    source_alpha: Image.Image,
    *,
    weight: float = 1.0,
    occlusion_factor: float = 0.58,
) -> Image.Image:
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
            exposure = max(0.0, current - above * occlusion_factor) / 255.0
            if above <= 12:
                exposure = max(exposure, 0.72 * current / 255.0)
            if exposure <= 0.05:
                continue
            dst[x, y] = max(dst[x, y], min(255, int(255.0 * exposure * weight)))
    return edge.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.65))


def exposed_directional_edges(
    source_alpha: Image.Image,
    direction: tuple[float, float],
    *,
    weight: float,
    occlusion_factor: float,
) -> Image.Image:
    width, height = source_alpha.size
    direction_x, direction_y = direction
    direction_length = math.sqrt(direction_x * direction_x + direction_y * direction_y)
    if direction_length <= 0.000001 or weight <= 0.0:
        return Image.new("L", source_alpha.size, 0)
    direction_x /= direction_length
    direction_y /= direction_length
    perpendicular_x = -direction_y
    perpendicular_y = direction_x
    src = source_alpha.load()
    edge = Image.new("L", source_alpha.size, 0)
    dst = edge.load()
    for y in range(height):
        for x in range(width):
            current = src[x, y]
            if current <= 18:
                continue
            upstream = 0
            for distance in (2, 4, 7):
                for side in (-2, 0, 2):
                    sample_x = int(round(x + direction_x * distance + perpendicular_x * side))
                    sample_y = int(round(y + direction_y * distance + perpendicular_y * side))
                    if 0 <= sample_x < width and 0 <= sample_y < height:
                        upstream = max(upstream, src[sample_x, sample_y])
            exposure = max(0.0, current - upstream * occlusion_factor) / 255.0
            if upstream <= 12:
                exposure = max(exposure, 0.72 * current / 255.0)
            if exposure <= 0.05:
                continue
            dst[x, y] = min(255, int(255.0 * exposure * weight))
    return edge.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.65))


def spread_snow(edge: Image.Image, target_alpha: Image.Image, *, depth_px: int, strength: float) -> Image.Image:
    accumulation = Image.new("L", edge.size, 0)
    softened_edge = edge.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.35))
    for offset in range(0, depth_px, 2):
        progress = offset / max(depth_px - 1, 1)
        decay = (1.0 - progress) ** 1.45
        dx = int(round(math.sin(offset * 0.33) * 3.0 + math.sin(offset * 0.071) * 2.0))
        shifted = shifted_luma(softened_edge, dx, offset)
        blurred = shifted.filter(ImageFilter.GaussianBlur(1.20 + offset * 0.040))
        band = blurred.point(lambda value, decay=decay: min(255, int(value * decay * strength)), "L")
        accumulation = ImageChops.lighter(accumulation, band)
    alpha_gate = target_alpha.point(lambda value: 0 if value <= 12 else min(255, int(value * 1.16)), "L")
    return ImageChops.multiply(accumulation, alpha_gate)


def supported_cap_overhang(
    edge: Image.Image,
    *,
    up_px: int,
    side_px: int,
    strength: float,
    blur_radius: float,
) -> Image.Image:
    cap = Image.new("L", edge.size, 0)
    softened = edge.filter(ImageFilter.MaxFilter(3))
    for up in range(1, max(0, up_px) + 1):
        vertical_decay = 1.0 - (up - 1) / max(up_px, 1)
        for side in range(-max(0, side_px), max(0, side_px) + 1):
            lateral_decay = 1.0 - abs(side) / max(side_px + 1, 1)
            gain = strength * vertical_decay * lateral_decay
            shifted = shifted_luma(softened, side, -up)
            band = shifted.point(lambda value, gain=gain: min(255, int(value * gain)), "L")
            cap = ImageChops.lighter(cap, band)
    return cap.filter(ImageFilter.GaussianBlur(max(0.0, blur_radius)))


def legacy_snow_mask(albedo: Image.Image, foliage: Image.Image, trunk: Image.Image) -> Image.Image:
    alpha = union_alpha(albedo)
    foliage_alpha = alpha_of(foliage)
    trunk_alpha = alpha_of(trunk)
    foliage_edges = exposed_top_edges(foliage_alpha, weight=1.0)
    trunk_edges = exposed_top_edges(trunk_alpha, weight=0.64)
    foliage_snow = spread_snow(foliage_edges, foliage_alpha, depth_px=74, strength=1.22)
    trunk_snow = spread_snow(trunk_edges, trunk_alpha, depth_px=58, strength=1.05)
    gray = ImageChops.lighter(foliage_snow, trunk_snow)
    noise = procedural_noise(gray.size, low=138, high=255, phase=0.4)
    gray = ImageChops.multiply(gray, noise)
    gray = gray.point(lambda value: 0 if value < 10 else min(255, int(value * 1.46)), "L")
    gray = gray.filter(ImageFilter.GaussianBlur(1.35))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def apply_vertical_snow_fade(
    mask: Image.Image,
    *,
    anchor_y: int,
    full_until_offset_px: int,
    zero_from_offset_px: int,
) -> Image.Image:
    full_y = anchor_y + full_until_offset_px
    zero_y = anchor_y + zero_from_offset_px
    if zero_y <= full_y:
        raise ValueError("root snow zero boundary must be below its full-strength boundary")
    faded = Image.new("L", mask.size, 0)
    src = mask.load()
    dst = faded.load()
    for y in range(mask.height):
        if y <= full_y:
            factor = 1.0
        elif y >= zero_y:
            factor = 0.0
        else:
            factor = 1.0 - (y - full_y) / float(zero_y - full_y)
        if factor <= 0.0:
            continue
        for x in range(mask.width):
            dst[x, y] = int(src[x, y] * factor)
    return faded


def make_snow_mask(
    albedo: Image.Image,
    foliage: Image.Image,
    trunk: Image.Image,
    anchor: tuple[int, int] | None = None,
    profile: dict | None = None,
) -> Image.Image:
    profile = profile_or_default(profile)
    snow_profile = profile["postprocess"].get("snow")
    if snow_profile is None:
        return legacy_snow_mask(albedo, foliage, trunk)

    alpha = alpha_of(albedo)
    foliage_alpha = alpha_of(foliage)
    trunk_alpha = alpha_of(trunk)
    foliage_profile = snow_profile["foliage"]
    trunk_profile = snow_profile["trunk"]
    windward_direction = tuple(float(value) for value in snow_profile["windward_screen_direction"])

    foliage_top = exposed_top_edges(
        foliage_alpha,
        weight=float(foliage_profile["top_edge_weight"]),
        occlusion_factor=float(foliage_profile["top_occlusion_factor"]),
    )
    foliage_windward = exposed_directional_edges(
        foliage_alpha,
        windward_direction,
        weight=float(foliage_profile["windward_weight"]),
        occlusion_factor=float(foliage_profile["windward_occlusion_factor"]),
    )
    foliage_edges = ImageChops.lighter(foliage_top, foliage_windward)
    foliage_snow = spread_snow(
        foliage_edges,
        foliage_alpha,
        depth_px=int(foliage_profile["depth_px"]),
        strength=float(foliage_profile["strength"]),
    )
    foliage_cap = supported_cap_overhang(
        foliage_top,
        up_px=int(foliage_profile["cap_overhang_up_px"]),
        side_px=int(foliage_profile["cap_overhang_side_px"]),
        strength=float(foliage_profile["cap_strength"]),
        blur_radius=float(foliage_profile["cap_blur_radius"]),
    )

    trunk_top = exposed_top_edges(
        trunk_alpha,
        weight=float(trunk_profile["top_edge_weight"]),
        occlusion_factor=float(trunk_profile["top_occlusion_factor"]),
    )
    trunk_windward = exposed_directional_edges(
        trunk_alpha,
        windward_direction,
        weight=float(trunk_profile["windward_weight"]),
        occlusion_factor=float(trunk_profile["windward_occlusion_factor"]),
    )
    trunk_edges = ImageChops.lighter(trunk_top, trunk_windward)
    trunk_snow = spread_snow(
        trunk_edges,
        trunk_alpha,
        depth_px=int(trunk_profile["depth_px"]),
        strength=float(trunk_profile["strength"]),
    )
    trunk_cap = supported_cap_overhang(
        trunk_top,
        up_px=int(trunk_profile["cap_overhang_up_px"]),
        side_px=int(trunk_profile["cap_overhang_side_px"]),
        strength=float(trunk_profile["cap_strength"]),
        blur_radius=float(trunk_profile["cap_blur_radius"]),
    )
    anchor_y = int(anchor[1] if anchor is not None else albedo.height * 0.88)
    trunk_snow = apply_vertical_snow_fade(
        trunk_snow,
        anchor_y=anchor_y,
        full_until_offset_px=int(snow_profile["root_full_until_offset_px"]),
        zero_from_offset_px=int(snow_profile["root_zero_from_offset_px"]),
    )
    trunk_cap = apply_vertical_snow_fade(
        trunk_cap,
        anchor_y=anchor_y,
        full_until_offset_px=int(snow_profile["root_full_until_offset_px"]),
        zero_from_offset_px=int(snow_profile["root_zero_from_offset_px"]),
    )

    gray = ImageChops.lighter(foliage_snow, trunk_snow)
    gray = ImageChops.lighter(gray, ImageChops.lighter(foliage_cap, trunk_cap))
    noise = procedural_noise(
        gray.size,
        low=int(snow_profile["noise_low"]),
        high=int(snow_profile["noise_high"]),
        phase=0.4,
    )
    gray = ImageChops.multiply(gray, noise)
    mask_gain = float(snow_profile["mask_gain"])
    gray = gray.point(lambda value: 0 if value < 10 else min(255, int(value * mask_gain)), "L")
    gray = gray.filter(ImageFilter.GaussianBlur(float(snow_profile["mask_blur_radius"])))
    support_radius = max(
        int(foliage_profile["cap_overhang_up_px"]) + int(foliage_profile["cap_overhang_side_px"]),
        int(trunk_profile["cap_overhang_up_px"]) + int(trunk_profile["cap_overhang_side_px"]),
    )
    support_gate = alpha.filter(ImageFilter.MaxFilter(support_radius * 2 + 1))
    support_gate = support_gate.point(lambda value: 255 if value > 4 else 0, "L")
    gray = ImageChops.multiply(gray, support_gate)
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def make_season_mask(
    foliage: Image.Image,
    trunk: Image.Image,
    snow_mask: Image.Image,
    profile: dict | None = None,
) -> Image.Image:
    profile = profile_or_default(profile)
    leaf_drop_enabled = bool(
        profile["postprocess"].get("season", {}).get("leaf_drop_enabled", True)
    )
    foliage_alpha = alpha_of(foliage)
    trunk_alpha = alpha_of(trunk)
    snow = snow_mask.getchannel("R")
    width, height = foliage_alpha.size
    drop = Image.new("L", foliage_alpha.size, 0)
    cold = Image.new("L", foliage_alpha.size, 0)
    drop_px = drop.load()
    cold_px = cold.load()
    foliage_px = foliage_alpha.load()
    trunk_px = trunk_alpha.load()
    snow_px = snow.load()
    for y in range(height):
        vertical = 1.0 - y / max(height - 1, 1)
        for x in range(width):
            f = foliage_px[x, y]
            if f <= 18:
                continue
            if leaf_drop_enabled:
                noise = (
                    0.50
                    + 0.24 * math.sin(x * 0.071 + y * 0.109)
                    + 0.18 * math.sin(x * 0.173 - y * 0.037)
                    + 0.10 * math.sin(x * 0.023 + y * 0.251)
                )
                branch_damp = 0.18 if trunk_px[x, y] > 24 else 0.0
                order = max(0.0, min(1.0, noise * 0.82 + vertical * 0.12 + branch_damp))
                drop_px[x, y] = int(order * 255.0)
            cold_px[x, y] = max(snow_px[x, y], int(255.0 * max(0.0, vertical - 0.28) * 0.42))
    if leaf_drop_enabled:
        drop = drop.filter(ImageFilter.GaussianBlur(1.1))
    return Image.merge("RGBA", (snow, drop, cold, foliage_alpha))


def make_snow_overlay(
    snow_mask: Image.Image,
    profile: dict | None = None,
    *,
    height: Image.Image | None = None,
    normal: Image.Image | None = None,
) -> Image.Image:
    profile = profile_or_default(profile)
    snow = snow_mask.getchannel("R")
    snow_profile = profile["postprocess"].get("snow")
    if snow_profile is None or height is None or normal is None:
        alpha = snow.point(lambda value: 0 if value < 14 else min(int((value - 8) * 1.34), 242), "L")
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

    overlay_threshold = int(snow_profile["overlay_threshold"])
    overlay_alpha_gain = float(snow_profile["overlay_alpha_gain"])
    overlay_max_alpha = int(snow_profile["overlay_max_alpha"])
    alpha = snow.point(
        lambda value: 0
        if value < overlay_threshold
        else min(int((value - overlay_threshold) * overlay_alpha_gain), overlay_max_alpha),
        "L",
    )
    height_luma = height.convert("L")
    blurred_height = height_luma.filter(ImageFilter.GaussianBlur(float(snow_profile["cavity_blur_radius"])))
    normal_rgba = normal.convert("RGBA")
    snow_rgb = rgb_from_profile(profile, "snow_rgb")
    shadow_rgb = tuple(int(value) for value in snow_profile["shadow_rgb"])
    light = [float(value) for value in snow_profile["light_vector_screen"]]
    light_length = math.sqrt(sum(value * value for value in light))
    light = [value / max(light_length, 0.000001) for value in light]
    out = Image.new("RGBA", snow.size, (0, 0, 0, 0))
    out_px = out.load()
    alpha_px = alpha.load()
    height_px = height_luma.load()
    blur_px = blurred_height.load()
    normal_px = normal_rgba.load()
    shade_base = float(snow_profile["shade_base"])
    normal_weight = float(snow_profile["shade_normal_weight"])
    height_weight = float(snow_profile["shade_height_weight"])
    cavity_weight = float(snow_profile["shade_cavity_weight"])
    for y in range(snow.height):
        for x in range(snow.width):
            pixel_alpha = alpha_px[x, y]
            if pixel_alpha <= 0:
                continue
            red, green, blue, _normal_alpha = normal_px[x, y]
            nx = red / 127.5 - 1.0
            ny = green / 127.5 - 1.0
            nz = blue / 127.5 - 1.0
            ndotl = max(0.0, nx * light[0] + ny * light[1] + nz * light[2])
            height_value = height_px[x, y] / 255.0
            cavity = max(0.0, (blur_px[x, y] - height_px[x, y]) / 255.0)
            shade = max(
                0.0,
                min(
                    1.0,
                    shade_base + normal_weight * ndotl + height_weight * height_value - cavity_weight * cavity,
                ),
            )
            color = tuple(
                int(round(shadow_rgb[channel] + (snow_rgb[channel] - shadow_rgb[channel]) * shade))
                for channel in range(3)
            )
            out_px[x, y] = (color[0], color[1], color[2], pixel_alpha)
    return out


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


def asset_name_from_dir(asset_dir: Path) -> str:
    name = asset_dir.name
    if name.startswith("layered_"):
        name = name[len("layered_") :]
    return f"{name}_layered_glb"


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
    asset_dir: Path,
    albedo: Image.Image,
    trunk: Image.Image,
    foliage: Image.Image,
    shadow: Image.Image,
    wind_mask: Image.Image,
    snow_mask: Image.Image,
    snow_overlay: Image.Image,
    season_mask: Image.Image,
) -> Image.Image:
    tile_w, tile_h = albedo.size
    scale = 0.5
    panels = [
        ("albedo", composite_on_ground(albedo)),
        ("layered", composite_on_ground(shadow, trunk, foliage)),
        ("snow overlay", composite_on_ground(shadow, trunk, foliage, snow_overlay)),
        ("wind mask", wind_mask),
        ("snow mask", snow_mask),
        ("season mask", season_mask),
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
    trunk = load_rgba(asset_dir / "trunk.png")
    foliage = load_rgba(asset_dir / "foliage.png")
    raw_shadow = load_rgba(asset_dir / "shadow_raw.png")
    classification_path = asset_dir / "classification.json"
    with classification_path.open("r", encoding="utf-8") as fh:
        classification = json.load(fh)
    anchor_values = classification.get("anchor", [albedo.width // 2, int(albedo.height * 0.88)])
    anchor = (int(anchor_values[0]), int(anchor_values[1]))

    alpha = alpha_of(albedo)
    height = make_height(albedo)
    normal = make_normal_from_height(height, float(profile["postprocess"]["normal_strength"]))
    shadow = processed_shadow(raw_shadow, alpha, anchor, profile)
    shadow = suppress_shadow_under_root_footprint(shadow, trunk, anchor, profile)
    wind_mask = make_wind_mask(trunk, foliage)
    snow_mask = make_snow_mask(albedo, foliage, trunk, anchor, profile)
    snow_overlay = make_snow_overlay(snow_mask, profile, height=height, normal=normal)
    season_mask = make_season_mask(foliage, trunk, snow_mask, profile)

    outputs = {
        "shadow.png": shadow,
        "wind_mask.png": wind_mask,
        "snow_mask.png": snow_mask,
        "snow_overlay.png": snow_overlay,
        "season_mask.png": season_mask,
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
        "collision_radius": 18,
        "plant_depth_px": int(classification.get("runtime_plant_depth_px", 0)),
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
            "season_mask": "season_mask.png",
            "height": "height.png",
            "normal": "normal.png",
        },
        "alpha_bbox": alpha_bbox(albedo),
        "notes": "Prototype layered tree asset from one GLB. Static trunk/foliage layers; runtime wind should use wind_mask and keep trunk/root pinned.",
    }
    with (asset_dir / "meta.json").open("w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent="\t", ensure_ascii=False)

    preview = make_preview(asset_dir, albedo, trunk, foliage, shadow, wind_mask, snow_mask, snow_overlay, season_mask)
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
            "season_mask.png",
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
    save_outputs(args.asset_dir, args.copy_to, load_profile(args.profile))
    print(f"Wrote layered tree helper textures to {args.asset_dir}")


if __name__ == "__main__":
    main()
