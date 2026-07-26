"""Postprocess one layered tree bake into game-ready helper textures."""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
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
    # Screen-space south-east from the root: right and down, root stays attached.
    paste_x = int(round(anchor_x - cropped.width * 0.24))
    paste_y = int(round(anchor_y - shadow_h * 0.12))
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


def to_array(image: Image.Image) -> np.ndarray:
    return np.asarray(image, dtype=np.float32) / 255.0


def to_image(array: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(array * 255.0, 0.0, 255.0).astype(np.uint8), "L")


def snow_settings(profile: dict) -> dict:
    return profile["postprocess"]["snow"]


def surface_normal_field(alpha: Image.Image, settings: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Screen-space outward normal of the silhouette, averaged over two scales.

    The wide blur reports the shape of a whole canopy blob; the tight blur
    reports the individual lumps on it. Snow needs both: the blob decides where
    a cap sits, the lumps decide where its edge breaks up.
    """
    normal_x = np.zeros(alpha.size[::-1], dtype=np.float32)
    normal_y = np.zeros_like(normal_x)
    weights = settings["surface_blur_weights"]
    for radius, weight in zip(settings["surface_blur_px"], weights):
        field = to_array(alpha.filter(ImageFilter.GaussianBlur(float(radius))))
        gradient_y, gradient_x = np.gradient(field)
        # Alpha falls off outward, so the outward normal is the negated gradient.
        normal_x -= gradient_x * float(weight)
        normal_y -= gradient_y * float(weight)
    magnitude = np.hypot(normal_x, normal_y)
    safe = np.maximum(magnitude, 1e-6)
    return normal_x / safe, normal_y / safe, magnitude


def up_facing_weight(alpha: Image.Image, settings: dict) -> np.ndarray:
    """How much sky this pixel's surface sees.

    This is what replaced "nothing above me within 7 pixels". That older test
    fired along the entire outline of a thin trunk, including its underside and
    its shaded flank, which is why snow used to coat whole silhouettes.
    """
    normal_x, normal_y, magnitude = surface_normal_field(alpha, settings)
    # Image y grows downward, so "up" is -y.
    facing = np.clip(-normal_y, 0.0, 1.0) ** float(settings["up_facing_power"])
    # Interior pixels carry no silhouette gradient and must not collect snow
    # directly; they are reached by settling from the surfaces above them.
    return facing * np.clip(magnitude * float(settings["surface_gradient_scale"]), 0.0, 1.0)


def shade_snow(amount: np.ndarray, settings: dict) -> np.ndarray:
    """Light the snow by the shape of the drift itself, not by the layer under it.

    Shading against the tree silhouette makes every cap the same flat white,
    because a drape inherits the tone of the rim it fell from. The drift has its
    own relief — lumps, a rounded top, a shaded far side — and that is what the
    fixed bake sun should be modelling.
    """
    light = np.array(settings["light_direction"], dtype=np.float32)
    light /= max(float(np.linalg.norm(light)), 1e-6)
    ambient = float(settings["shade_ambient"])

    field = to_array(to_image(amount).filter(ImageFilter.GaussianBlur(float(settings["shade_blur_px"]))))
    gradient_y, gradient_x = np.gradient(field)
    normal_x, normal_y = -gradient_x, -gradient_y
    magnitude = np.hypot(normal_x, normal_y)
    safe = np.maximum(magnitude, 1e-6)
    sloped = np.clip((normal_x / safe) * light[0] + (normal_y / safe) * light[1], 0.0, 1.0)

    # Inside a thick drift the surface is flat and level, so it takes the same
    # light as a horizontal top rather than an undefined normal.
    flat = float(np.clip(-light[1], 0.0, 1.0))
    flatness = np.clip(1.0 - magnitude * float(settings["shade_relief_scale"]), 0.0, 1.0)
    lit = sloped * (1.0 - flatness) + flat * flatness
    return np.clip(ambient + (1.0 - ambient) * lit, 0.0, 1.0)


def settle(landed: np.ndarray, gate: np.ndarray, settings: dict) -> np.ndarray:
    """Drape snow downward from where it landed, thinning as it goes.

    The first few pixels hold full depth — a drift has a body, not just a rim —
    and only past that does it thin out. `gate` must be the alpha of the layer
    the snow landed on, never a shared one, otherwise a canopy blob smears its
    snow down the trunk behind it and the result reads as fog.
    """
    depth = int(settings["settle_depth_px"])
    plateau = int(settings["settle_plateau_px"])
    decay_power = float(settings["settle_decay"])
    wobble = float(settings["settle_wobble_px"])
    accumulated = landed.copy()
    for offset in range(1, depth):
        progress = max(0.0, offset - plateau) / max(depth - plateau, 1)
        decay = (1.0 - progress) ** decay_power
        shift_x = int(round(math.sin(offset * 0.31) * wobble))
        shifted = np.roll(landed, offset, axis=0)
        shifted[:offset, :] = 0.0
        if shift_x:
            shifted = np.roll(shifted, shift_x, axis=1)
            if shift_x > 0:
                shifted[:, :shift_x] = 0.0
            else:
                shifted[:, shift_x:] = 0.0
        accumulated = np.maximum(accumulated, shifted * decay)
    return accumulated * gate


def value_noise(size: tuple[int, int], settings: dict) -> np.ndarray:
    """Bicubic-interpolated random grids. No sine lattice, so no visible grid."""
    rng = random.Random(int(settings["noise_seed"]))
    total = np.zeros(size[::-1], dtype=np.float32)
    weight_sum = 0.0
    for octave in settings["noise_octaves"]:
        cells = int(octave["cells"])
        weight = float(octave["weight"])
        grid = Image.new("L", (cells, cells))
        grid.putdata([rng.randrange(256) for _ in range(cells * cells)])
        total += to_array(grid.resize(size, Image.Resampling.BICUBIC)) * weight
        weight_sum += weight
    return np.clip(total / max(weight_sum, 1e-6), 0.0, 1.0)


def snow_cap(landed: np.ndarray, alpha_field: np.ndarray, settings: dict) -> np.ndarray:
    """Ridge of snow standing above the branch it sits on.

    Without this the sprite can only recolour pixels that already belong to the
    tree, and accumulation reads as bleaching rather than as depth.
    """
    height = int(settings["cap_height_px"])
    if height <= 0:
        return np.zeros_like(landed)
    source = landed * (alpha_field > 0.5)
    cap = np.zeros_like(landed)
    for offset in range(1, height + 1):
        falloff = (1.0 - offset / (height + 1.0)) ** 1.25
        shifted = np.roll(source, -offset, axis=0)
        shifted[-offset:, :] = 0.0
        cap = np.maximum(cap, shifted * falloff)
    return cap * float(settings["cap_strength"])


def make_snow_mask(
    albedo: Image.Image,
    foliage: Image.Image,
    trunk: Image.Image,
    profile: dict | None = None,
) -> Image.Image:
    """Channels: R accumulation order, G snow lighting, B cap depth, A coverage.

    R keeps the meaning the runtime shaders rely on — the higher the value, the
    earlier that pixel turns white as `season_amount` rises — so the sky-facing
    tops of the canopy snow over first and sheltered undersides snow over last.
    """
    settings = snow_settings(profile_or_default(profile))
    foliage_alpha = alpha_of(foliage)
    trunk_alpha = alpha_of(trunk)

    foliage_facing = up_facing_weight(foliage_alpha, settings)
    trunk_facing = up_facing_weight(trunk_alpha, settings) * float(settings["trunk_gain"])

    # Each layer settles inside its own silhouette, so canopy snow cannot run
    # down the trunk behind it.
    foliage_amount = settle(foliage_facing, to_array(foliage_alpha), settings)
    trunk_amount = settle(trunk_facing, to_array(trunk_alpha), settings)
    amount = np.maximum(foliage_amount, trunk_amount)

    noise = value_noise(foliage_alpha.size, settings)
    bite = float(settings["noise_bite"])
    amount = amount * (1.0 - bite + bite * noise)

    alpha_field = to_array(union_alpha(albedo))
    cap = snow_cap(amount, alpha_field, settings)
    amount = np.maximum(amount, cap)

    ceiling = float(np.percentile(amount[amount > 0.0], 98.0)) if np.any(amount > 0.0) else 1.0
    amount = np.clip(amount / max(ceiling, 1e-6), 0.0, 1.0)
    amount = to_array(to_image(amount).filter(ImageFilter.GaussianBlur(0.8)))
    # Thin snow lets bark and leaf show through, so it reads darker than a drift.
    lit = shade_snow(amount, settings) * (0.62 + 0.38 * amount)

    coverage = np.maximum(alpha_field, np.clip(cap * 3.0, 0.0, 1.0))
    return Image.merge(
        "RGBA",
        (to_image(amount), to_image(lit), to_image(cap), to_image(coverage)),
    )


def make_season_mask(foliage: Image.Image, trunk: Image.Image, snow_mask: Image.Image) -> Image.Image:
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
    drop = drop.filter(ImageFilter.GaussianBlur(1.1))
    return Image.merge("RGBA", (snow, drop, cold, foliage_alpha))


def make_snow_overlay(snow_mask: Image.Image, profile: dict | None = None) -> Image.Image:
    """Shade the snow instead of flooding a flat white over the silhouette."""
    profile = profile_or_default(profile)
    settings = snow_settings(profile)
    amount = to_array(snow_mask.getchannel("R"))
    lit = to_array(snow_mask.getchannel("G"))

    # The mask keeps a smooth ramp because the runtime sweeps a threshold across
    # it to grow snow over the season. The overlay is the full-winter result, and
    # there snow has a short, irregular boundary rather than an airbrushed one.
    cut = float(settings["overlay_cut"])
    softness = max(float(settings["overlay_softness"]), 1e-4)
    normalized = np.clip((amount - (cut - softness)) / (2.0 * softness), 0.0, 1.0)
    alpha = normalized * normalized * (3.0 - 2.0 * normalized) * float(settings["overlay_peak"])

    shaded = np.array(settings["shaded_rgb"], dtype=np.float32) / 255.0
    bright = np.array(settings["lit_rgb"], dtype=np.float32) / 255.0
    channels = [to_image(shaded[index] + (bright[index] - shaded[index]) * lit) for index in range(3)]
    channels.append(to_image(alpha))
    return Image.merge("RGBA", channels)


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
    shadow = processed_shadow(raw_shadow, alpha, anchor, profile)
    wind_mask = make_wind_mask(trunk, foliage)
    snow_mask = make_snow_mask(albedo, foliage, trunk, profile)
    snow_overlay = make_snow_overlay(snow_mask, profile)
    season_mask = make_season_mask(foliage, trunk, snow_mask)
    height = make_height(albedo)
    normal = make_normal_from_height(height, float(profile["postprocess"]["normal_strength"]))

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
