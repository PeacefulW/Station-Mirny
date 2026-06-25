#!/usr/bin/env python3
"""Amplify an existing (clean, GLB-baked) normal map so its relief pops more.

Steepens the X/Y slopes and renormalizes — the sun/torch then catches the SAME
structured pebbles/cracks harder (more 'wow'), without inventing noise the way
albedo-derived normals do. Tileable-preserving (per-pixel op).

  python tools/terrain/amplify_normal.py --normal <in.png> --out <out.png> \
      [--albedo <albedo.png> --preview <sheet.png>] [--gain 1.9]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def _rgb(path: Path, size: tuple[int, int] | None = None) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    if size is not None and img.size != size:
        img = img.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def _save(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path)


def _amplify(normal_map: np.ndarray, gain: float) -> np.ndarray:
    n = normal_map * 2.0 - 1.0
    n[:, :, 0] *= gain
    n[:, :, 1] *= gain
    n[:, :, 2] = np.maximum(n[:, :, 2], 0.05)
    length = np.linalg.norm(n, axis=2, keepdims=True)
    return (n / np.maximum(length, 1e-4)) * 0.5 + 0.5


def _shade(albedo: np.ndarray, normal_map: np.ndarray, light: np.ndarray) -> np.ndarray:
    n = normal_map * 2.0 - 1.0
    light = light / np.linalg.norm(light)
    diffuse = np.clip((n * light).sum(axis=2), 0.0, 1.0)
    return np.clip(albedo * (0.40 + diffuse * 0.95)[:, :, None], 0.0, 1.0)


def _crop_cell(label: str, arr: np.ndarray, c: int = 320, s: int = 512) -> Image.Image:
    y0, x0 = arr.shape[0] // 2 - c // 2, arr.shape[1] // 2 - c // 2
    img = Image.fromarray(np.clip(arr[y0:y0 + c, x0:x0 + c] * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    img = img.resize((s, s), Image.Resampling.LANCZOS)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, s, 24), fill=(16, 16, 16))
    d.text((8, 6), label, fill=(235, 235, 235))
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--normal", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--gain", type=float, default=1.9)
    ap.add_argument("--albedo", type=Path)
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()

    normal = _rgb(args.normal)
    amplified = _amplify(normal, args.gain)
    _save(args.out, amplified)

    if args.albedo and args.preview:
        albedo = _rgb(args.albedo, (normal.shape[1], normal.shape[0]))
        light = np.array([-0.55, -0.42, 0.62], dtype=np.float32)
        cells = [
            _crop_cell("orig shaded", _shade(albedo, normal, light)),
            _crop_cell("amplified shaded x%.1f" % args.gain, _shade(albedo, amplified, light)),
            _crop_cell("orig normal", normal),
            _crop_cell("amplified normal", amplified),
        ]
        sheet = Image.new("RGB", (512 * len(cells), 512), (20, 20, 20))
        for i, cc in enumerate(cells):
            sheet.paste(cc, (i * 512, 0))
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(args.preview)

    print("OK out=%s gain=%.2f" % (args.out, args.gain))


if __name__ == "__main__":
    main()
