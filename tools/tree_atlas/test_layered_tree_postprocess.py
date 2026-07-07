"""Regression checks for layered tree helper texture postprocessing."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image

import postprocess_layered_tree_asset as post
from postprocess_layered_tree_asset import (
    alpha_of,
    load_rgba,
    make_snow_mask,
    make_snow_overlay,
    processed_shadow,
)


ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "artifacts" / "layered_tree_01"


def _asset_anchor() -> tuple[int, int]:
    with (ASSET_DIR / "classification.json").open("r", encoding="utf-8") as fh:
        classification = json.load(fh)
    anchor = classification.get("anchor", [384, 676])
    return int(anchor[0]), int(anchor[1])


def _alpha_runs(alpha: Image.Image, x: int, threshold: int = 18) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    y = 0
    height = alpha.height
    while y < height:
        while y < height and alpha.getpixel((x, y)) <= threshold:
            y += 1
        start = y
        while y < height and alpha.getpixel((x, y)) > threshold:
            y += 1
        end = y
        if end - start > 8:
            runs.append((start, end))
    return runs


def _dark_vertical_gap_count(image: Image.Image, alpha: Image.Image, bbox: tuple[int, int, int, int]) -> int:
    stripe_count = 0
    for x in range(bbox[0] + 2, bbox[2] - 2):
        run = 0
        for y in range(bbox[1], bbox[3]):
            value = image.getpixel((x, y))
            left = max(image.getpixel((x - 1, y)), image.getpixel((x - 2, y)))
            right = max(image.getpixel((x + 1, y)), image.getpixel((x + 2, y)))
            is_gap = value < 35 and left > 80 and right > 80 and alpha.getpixel((x, y)) > 18
            if is_gap:
                run += 1
                continue
            if run >= 8:
                stripe_count += 1
            run = 0
        if run >= 8:
            stripe_count += 1
    return stripe_count


class LayeredTreePostprocessTest(unittest.TestCase):
    def test_processed_shadow_preserves_clean_blender_shadow_extent(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        raw_shadow = load_rgba(ASSET_DIR / "shadow_raw.png")

        shadow = processed_shadow(raw_shadow, alpha_of(albedo), _asset_anchor())
        alpha = alpha_of(shadow)
        bbox = alpha.getbbox()
        anchor = _asset_anchor()

        self.assertIsNotNone(bbox)
        assert bbox is not None
        self.assertLessEqual(bbox[0], 190)
        self.assertGreaterEqual(bbox[2], 700)
        self.assertGreater(bbox[2] - bbox[0], 400)
        self.assertGreater(sum(alpha.histogram()[1:]), 40_000)

        total_alpha = 0
        weighted_x = 0
        weighted_y = 0
        for y in range(alpha.height):
            for x in range(alpha.width):
                value = alpha.getpixel((x, y))
                if value <= 8:
                    continue
                total_alpha += value
                weighted_x += x * value
                weighted_y += y * value
        self.assertGreater(total_alpha, 0)
        self.assertGreater(weighted_x / total_alpha, anchor[0] + 30)
        self.assertLess(weighted_y / total_alpha, anchor[1] + 5)

    def test_snow_overlay_reaches_lower_foliage_clusters(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        foliage = load_rgba(ASSET_DIR / "foliage.png")
        trunk = load_rgba(ASSET_DIR / "trunk.png")
        foliage_alpha = alpha_of(foliage)

        snow_overlay = make_snow_overlay(make_snow_mask(albedo, foliage, trunk))
        snow_alpha = alpha_of(snow_overlay)

        lower_cluster_hits = 0
        for x in range(foliage_alpha.width):
            for start, end in _alpha_runs(foliage_alpha, x)[1:]:
                if start < 300:
                    continue
                for y in range(start, min(end, start + 28)):
                    if snow_alpha.getpixel((x, y)) > 45:
                        lower_cluster_hits += 1

        self.assertGreater(lower_cluster_hits, 250)

    def test_snow_mask_has_no_dark_vertical_gaps_inside_caps(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        foliage = load_rgba(ASSET_DIR / "foliage.png")
        trunk = load_rgba(ASSET_DIR / "trunk.png")

        snow_mask = make_snow_mask(albedo, foliage, trunk).getchannel("R")
        foliage_alpha = alpha_of(foliage)
        bbox = foliage_alpha.getbbox()

        self.assertIsNotNone(bbox)
        assert bbox is not None
        self.assertLessEqual(_dark_vertical_gap_count(snow_mask, foliage_alpha, bbox), 2)

    def test_season_mask_encodes_leaf_drop_variation(self) -> None:
        self.assertTrue(hasattr(post, "make_season_mask"), "Postprocess must emit a reusable season mask.")
        if not hasattr(post, "make_season_mask"):
            return
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        foliage = load_rgba(ASSET_DIR / "foliage.png")
        trunk = load_rgba(ASSET_DIR / "trunk.png")

        snow_mask = make_snow_mask(albedo, foliage, trunk)
        season_mask = post.make_season_mask(foliage, trunk, snow_mask)
        drop_order = season_mask.getchannel("G")
        foliage_alpha = alpha_of(foliage)
        values = [
            drop_order.getpixel((x, y))
            for y in range(foliage_alpha.height)
            for x in range(foliage_alpha.width)
            if foliage_alpha.getpixel((x, y)) > 32
        ]

        self.assertGreater(max(values) - min(values), 150)
        self.assertGreater(len({value // 16 for value in values}), 10)


if __name__ == "__main__":
    unittest.main()
