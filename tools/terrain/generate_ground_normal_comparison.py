#!/usr/bin/env python3
"""Generate a procedural ground normal map and preview comparison sheets."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def _load_rgb(path: Path, size: tuple[int, int] | None = None) -> np.ndarray:
    image = Image.open(path).convert("RGB")
    if size is not None and image.size != size:
        image = image.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(image, dtype=np.float32) / 255.0


def _save_rgb(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(out, "RGB").save(path)


def _smoothstep(t: np.ndarray) -> np.ndarray:
    return t * t * (3.0 - 2.0 * t)


def _tileable_value_noise(width: int, height: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    grid = rng.random((cells, cells), dtype=np.float32)
    xs = np.arange(width, dtype=np.float32) * (cells / float(width))
    ys = np.arange(height, dtype=np.float32) * (cells / float(height))

    x0 = np.floor(xs).astype(np.int32) % cells
    y0 = np.floor(ys).astype(np.int32) % cells
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    tx = _smoothstep(xs - np.floor(xs))
    ty = _smoothstep(ys - np.floor(ys))

    n00 = grid[y0[:, None], x0[None, :]]
    n10 = grid[y0[:, None], x1[None, :]]
    n01 = grid[y1[:, None], x0[None, :]]
    n11 = grid[y1[:, None], x1[None, :]]
    nx0 = n00 * (1.0 - tx[None, :]) + n10 * tx[None, :]
    nx1 = n01 * (1.0 - tx[None, :]) + n11 * tx[None, :]
    return nx0 * (1.0 - ty[:, None]) + nx1 * ty[:, None]


def _fbm(width: int, height: int, rng: np.random.Generator) -> np.ndarray:
    result = np.zeros((height, width), dtype=np.float32)
    amp = 1.0
    amp_sum = 0.0
    for cells in (7, 13, 29, 61, 127):
        result += _tileable_value_noise(width, height, cells, rng) * amp
        amp_sum += amp
        amp *= 0.52
    return result / max(amp_sum, 0.001)


def _add_local_disc(height: np.ndarray, cx: int, cy: int, radius: int, stamp: np.ndarray) -> None:
    h, w = height.shape
    ys = (np.arange(cy - radius, cy + radius + 1) % h).astype(np.int32)
    xs = (np.arange(cx - radius, cx + radius + 1) % w).astype(np.int32)
    height[np.ix_(ys, xs)] += stamp


def _add_stones_and_pits(height: np.ndarray, rng: np.random.Generator) -> None:
    h, w = height.shape

    for _ in range(760):
        radius = int(rng.integers(3, 14))
        yy, xx = np.mgrid[-radius : radius + 1, -radius : radius + 1].astype(np.float32)
        d = np.sqrt(xx * xx + yy * yy) / float(radius)
        stamp = np.clip(1.0 - d, 0.0, 1.0)
        stamp = stamp * stamp * (3.0 - 2.0 * stamp)
        amp = float(rng.uniform(0.018, 0.095))
        if rng.random() < 0.18:
            amp *= 1.8
            radius = min(radius + int(rng.integers(2, 8)), 24)
            yy, xx = np.mgrid[-radius : radius + 1, -radius : radius + 1].astype(np.float32)
            d = np.sqrt(xx * xx + yy * yy) / float(radius)
            stamp = np.clip(1.0 - d, 0.0, 1.0)
            stamp = stamp * stamp * (3.0 - 2.0 * stamp)
        _add_local_disc(
            height,
            int(rng.integers(0, w)),
            int(rng.integers(0, h)),
            radius,
            stamp.astype(np.float32) * amp,
        )

    for _ in range(430):
        radius = int(rng.integers(5, 24))
        yy, xx = np.mgrid[-radius : radius + 1, -radius : radius + 1].astype(np.float32)
        d = np.sqrt(xx * xx + yy * yy) / float(radius)
        basin = -np.exp(-(d * 2.15) ** 2)
        rim = np.exp(-((d - 0.74) * 5.2) ** 2) * 0.38
        stamp = (basin + rim) * float(rng.uniform(0.018, 0.072))
        stamp[d > 1.0] = 0.0
        _add_local_disc(
            height,
            int(rng.integers(0, w)),
            int(rng.integers(0, h)),
            radius,
            stamp.astype(np.float32),
        )


def _height_to_normal(height: np.ndarray, strength: float) -> np.ndarray:
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.dstack((nx * inv_len, ny * inv_len, nz * inv_len))
    return normal * 0.5 + 0.5


def _renormalize_normal_map(normal_map: np.ndarray) -> np.ndarray:
    normal = normal_map * 2.0 - 1.0
    length = np.linalg.norm(normal, axis=2, keepdims=True)
    normal = normal / np.maximum(length, 0.0001)
    return normal * 0.5 + 0.5


def _make_tileable_normal(input_path: Path, output_path: Path, band: int) -> None:
    data = _load_rgb(input_path)
    height, width, _channels = data.shape
    band = min(band, width // 4, height // 4)
    shifted = np.roll(np.roll(data, width // 2, axis=1), height // 2, axis=0)

    x = np.minimum(np.arange(width), width - 1 - np.arange(width)).astype(np.float32)
    y = np.minimum(np.arange(height), height - 1 - np.arange(height)).astype(np.float32)
    wx = _smoothstep(np.clip(x / max(float(band), 1.0), 0.0, 1.0))
    wy = _smoothstep(np.clip(y / max(float(band), 1.0), 0.0, 1.0))
    weight = (wx[None, :] * wy[:, None])[:, :, None]
    blended = shifted * (1.0 - weight) + data * weight
    _save_rgb(output_path, _renormalize_normal_map(blended))


def _make_procedural_normal(albedo_path: Path, output_path: Path, seed: int, strength: float) -> None:
    albedo_image = Image.open(albedo_path).convert("RGB")
    width, height_px = albedo_image.size
    rng = np.random.default_rng(seed)

    lum = np.asarray(albedo_image.convert("L"), dtype=np.float32) / 255.0
    blur = np.asarray(albedo_image.convert("L").filter(ImageFilter.GaussianBlur(7.0)), dtype=np.float32) / 255.0
    highpass = lum - blur

    height = (_fbm(width, height_px, rng) - 0.5) * 0.42
    height += highpass * 0.18
    _add_stones_and_pits(height, rng)
    height += (_tileable_value_noise(width, height_px, 251, rng) - 0.5) * 0.055

    low = float(np.percentile(height, 1.0))
    high = float(np.percentile(height, 99.0))
    height = np.clip((height - low) / max(high - low, 0.001), 0.0, 1.0)
    normal = _height_to_normal(height, strength)
    _save_rgb(output_path, normal)


def _shade(albedo: np.ndarray, normal_map: np.ndarray) -> np.ndarray:
    normal = normal_map * 2.0 - 1.0
    light = np.array([-0.42, -0.32, 0.85], dtype=np.float32)
    light /= np.linalg.norm(light)
    diffuse = np.clip((normal * light).sum(axis=2), 0.0, 1.0)
    shade = 0.52 + diffuse * 0.72
    return np.clip(albedo * shade[:, :, None], 0.0, 1.0)


def _label(image: Image.Image, label: str) -> None:
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, image.width, 26), fill=(16, 16, 16))
    draw.text((8, 6), label, fill=(235, 235, 235))


def _preview_cell(label: str, data: np.ndarray, width: int = 360) -> Image.Image:
    image = Image.fromarray(np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    image = image.resize((width, width), Image.Resampling.LANCZOS)
    _label(image, label)
    return image


def _build_preview(args: argparse.Namespace) -> None:
    albedo = _load_rgb(args.albedo)
    size = (albedo.shape[1], albedo.shape[0])

    cells: list[Image.Image] = [_preview_cell("albedo", albedo)]
    normals: list[Image.Image] = []
    for label, path in (
        ("current shaded", args.current_normal),
        ("model bake shaded", args.model_normal),
        ("procedural shaded", args.procedural_normal),
    ):
        if path and path.exists():
            normal = _load_rgb(path, size)
            cells.append(_preview_cell(label, _shade(albedo, normal)))
            normals.append(_preview_cell(label.replace(" shaded", " normal"), normal))

    sheet = Image.new("RGB", (360 * len(cells), 360), (20, 20, 20))
    for index, cell in enumerate(cells):
        sheet.paste(cell, (index * 360, 0))
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.preview)

    if normals:
        normal_sheet = Image.new("RGB", (360 * len(normals), 360), (20, 20, 20))
        for index, cell in enumerate(normals):
            normal_sheet.paste(cell, (index * 360, 0))
        normal_sheet.save(args.normal_preview)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--albedo", type=Path, required=True)
    parser.add_argument("--current-normal", type=Path, required=True)
    parser.add_argument("--model-normal", type=Path, required=True)
    parser.add_argument("--procedural-normal", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    parser.add_argument("--normal-preview", type=Path, required=True)
    parser.add_argument("--model-tileable-normal", type=Path)
    parser.add_argument("--procedural-tileable-normal", type=Path)
    parser.add_argument("--tile-band", type=int, default=128)
    parser.add_argument("--seed", type=int, default=42024)
    parser.add_argument("--strength", type=float, default=42.0)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    _make_procedural_normal(args.albedo, args.procedural_normal, args.seed, args.strength)
    if args.model_tileable_normal:
        _make_tileable_normal(args.model_normal, args.model_tileable_normal, args.tile_band)
        args.model_normal = args.model_tileable_normal
    if args.procedural_tileable_normal:
        _make_tileable_normal(args.procedural_normal, args.procedural_tileable_normal, args.tile_band)
        args.procedural_normal = args.procedural_tileable_normal
    _build_preview(args)
    print(
        "GENERATED",
        {
            "procedural_normal": str(args.procedural_normal),
            "preview": str(args.preview),
            "normal_preview": str(args.normal_preview),
            "seed": args.seed,
            "strength": args.strength,
        },
    )


if __name__ == "__main__":
    main()
