#!/usr/bin/env python3
"""Albedo-driven procedural ground normal map.

Unlike the fbm/random-stone path, this derives relief from the ALBEDO itself, at
multiple scales, so every visible pebble/crack/grain becomes real relief that the
in-game sun/torch can catch — including small bumps. Tileable if the albedo is.

Usage:
  python tools/terrain/procedural_ground_normal.py --albedo <albedo.png> \
      --out <normal.png> [--compare-against <their_normal.png>] \
      [--preview <sheet.png>] [--strength 70] [--detail 1.0] [--grain 0.03]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def _lum(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0


def _rgb(path: Path, size: tuple[int, int] | None = None) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    if size is not None and img.size != size:
        img = img.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def _gauss(arr01: np.ndarray, sigma: float) -> np.ndarray:
    img = Image.fromarray(np.clip(arr01 * 255.0, 0, 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32) / 255.0


def _albedo_height(lum: np.ndarray, detail: float, grain: float, seed: int) -> np.ndarray:
    """Multi-scale band-pass of the albedo luminance -> relief at every scale.

    Bright = high (pebble tops), dark = low (cracks/pits). Mid scales carry the
    pebble relief; fine scales give the 'sun on small bumps' sparkle; one low band
    keeps broad lumps."""
    rng = np.random.default_rng(seed)
    height = np.zeros_like(lum)
    # (sigma_px, weight): mid-dominant for pebbles, plus fine for micro relief.
    for sigma, weight in ((1.5, 0.55), (3.0, 0.85), (6.0, 1.0), (12.0, 0.6), (24.0, 0.35)):
        height += (lum - _gauss(lum, sigma)) * (weight * detail)
    # broad lumps so the surface is not globally flat
    height += (_gauss(lum, 48.0) - 0.5) * 0.5
    # tiny incoherent grain for sub-pebble sparkle (negligible seam)
    if grain > 0.0:
        height += (rng.random(lum.shape, dtype=np.float32) - 0.5) * grain
    return height


def _height_to_normal(height: np.ndarray, strength: float) -> np.ndarray:
    # wrap-around differences keep the normal tileable when the albedo tiles
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack((nx * inv, ny * inv, nz * inv)) * 0.5 + 0.5


def _save_rgb(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path)


def _shade(albedo: np.ndarray, normal_map: np.ndarray, light: np.ndarray) -> np.ndarray:
    normal = normal_map * 2.0 - 1.0
    light = light / np.linalg.norm(light)
    diffuse = np.clip((normal * light).sum(axis=2), 0.0, 1.0)
    shade = 0.40 + diffuse * 0.95  # raking, high-contrast -> shows relief drama
    return np.clip(albedo * shade[:, :, None], 0.0, 1.0)


def _cell(label: str, data: np.ndarray, size: int = 360) -> Image.Image:
    img = Image.fromarray(np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, size, 24), fill=(16, 16, 16))
    draw.text((8, 6), label, fill=(235, 235, 235))
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--albedo", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--compare-against", type=Path)
    ap.add_argument("--preview", type=Path)
    ap.add_argument("--strength", type=float, default=70.0)
    ap.add_argument("--detail", type=float, default=1.0)
    ap.add_argument("--grain", type=float, default=0.03)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    lum = _lum(args.albedo)
    height = _albedo_height(lum, args.detail, args.grain, args.seed)
    normal = _height_to_normal(height, args.strength)
    _save_rgb(args.out, normal)

    if args.preview:
        albedo = _rgb(args.albedo)
        size = (albedo.shape[1], albedo.shape[0])
        # raking light to make relief obvious
        light = np.array([-0.55, -0.42, 0.62], dtype=np.float32)
        cells = [_cell("albedo", albedo), _cell("MINE shaded", _shade(albedo, normal, light)), _cell("MINE normal", normal)]
        if args.compare_against and args.compare_against.exists():
            their = _rgb(args.compare_against, size)
            cells += [_cell("yours shaded", _shade(albedo, their, light)), _cell("yours normal", their)]
        sheet = Image.new("RGB", (360 * len(cells), 360), (20, 20, 20))
        for i, c in enumerate(cells):
            sheet.paste(c, (i * 360, 0))
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(args.preview)

        # Detail crop (320px region upscaled) so fine relief is actually judgeable.
        def _crop(arr: np.ndarray, lbl: str, c: int = 320, s: int = 512) -> Image.Image:
            y0, x0 = arr.shape[0] // 2 - c // 2, arr.shape[1] // 2 - c // 2
            return _cell(lbl, arr[y0:y0 + c, x0:x0 + c], s)
        dcells = [_crop(_shade(albedo, normal, light), "MINE shaded x")]
        if args.compare_against and args.compare_against.exists():
            dcells.append(_crop(_shade(albedo, _rgb(args.compare_against, size), light), "yours shaded x"))
        dcells.append(_crop(normal, "MINE normal x"))
        if args.compare_against and args.compare_against.exists():
            dcells.append(_crop(_rgb(args.compare_against, size), "yours normal x"))
        detail = Image.new("RGB", (512 * len(dcells), 512), (20, 20, 20))
        for i, c in enumerate(dcells):
            detail.paste(c, (i * 512, 0))
        detail.save(args.preview.with_name(args.preview.stem + "_detail.png"))

    print("OK out=%s strength=%.1f detail=%.2f grain=%.3f" % (args.out, args.strength, args.detail, args.grain))


if __name__ == "__main__":
    main()
