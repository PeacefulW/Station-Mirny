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
    make_wind_mask,
    make_snow_mask,
    make_snow_overlay,
    processed_shadow,
    validated_collision_footprint,
)


ROOT = Path(__file__).resolve().parents[2]
# Fixture must be an asset baked with the *current* profile: the shadow
# direction assertions below only mean something against the live sun.
ASSET_DIR = ROOT / "artifacts" / "layered_tree_v1_variations" / "var_01"


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
    def test_collision_footprint_validation_preserves_authored_geometry(self) -> None:
        footprint = {"offset_x_px": -79, "width_px": 81, "depth_px": 36}

        self.assertEqual(
            validated_collision_footprint(
                {"collision_footprint": footprint},
                (384, 519),
                (768, 768),
            ),
            footprint,
        )

    def test_collision_footprint_validation_rejects_invalid_geometry(self) -> None:
        invalid_footprints = (
            {"offset_x_px": 0.0, "width_px": 0, "depth_px": 36},
            {"offset_x_px": 0.0, "width_px": 36},
            {"offset_x_px": 760.0, "width_px": 36, "depth_px": 36},
            {"offset_x_px": 0.0, "width_px": 36, "depth_px": 600},
        )

        for footprint in invalid_footprints:
            with self.subTest(footprint=footprint):
                with self.assertRaises(SystemExit):
                    validated_collision_footprint(
                        {"collision_footprint": footprint},
                        (384, 519),
                        (768, 768),
                    )

    def test_collision_footprint_validation_keeps_legacy_centered_default(self) -> None:
        self.assertEqual(
            validated_collision_footprint({}, (384, 676), (768, 768)),
            {"offset_x_px": 0.0, "width_px": 36.0, "depth_px": 36.0},
        )

    def test_processed_shadow_preserves_clean_blender_shadow_extent(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        raw_shadow = load_rgba(ASSET_DIR / "shadow_raw.png")

        shadow = processed_shadow(raw_shadow, alpha_of(albedo), _asset_anchor())
        alpha = alpha_of(shadow)
        bbox = alpha.getbbox()
        anchor = _asset_anchor()

        silhouette = alpha_of(albedo).getbbox()
        self.assertIsNotNone(bbox)
        self.assertIsNotNone(silhouette)
        assert bbox is not None and silhouette is not None

        # The fallback fake shadow is a squashed copy of the silhouette pasted at
        # the root, so it is never much wider than the tree. A real cast shadow at
        # 42 degrees of elevation stretches far past it. Comparing against the
        # silhouette keeps this meaningful for any variant, wide or slender,
        # instead of pinning pixel columns of one particular tree.
        silhouette_width = silhouette[2] - silhouette[0]
        self.assertGreater(bbox[2] - bbox[0], silhouette_width * 2)
        self.assertGreaterEqual(bbox[2], anchor[0] + 250)
        self.assertGreater(sum(alpha.histogram()[1:]), 12_000)

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
        # Sun azimuth 225 puts the shadow screen south-east: right of the root
        # and below it. This assertion is the guard against the bake and the
        # runtime stretch direction drifting apart.
        self.assertGreater(weighted_x / total_alpha, anchor[0] + 30)
        self.assertGreater(weighted_y / total_alpha, anchor[1] + 8)

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

    def test_snow_overlay_reaches_visible_upper_trunk(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        foliage = load_rgba(ASSET_DIR / "foliage.png")
        trunk = load_rgba(ASSET_DIR / "trunk.png")
        trunk_alpha = alpha_of(trunk)
        foliage_alpha = alpha_of(foliage)

        snow_overlay = make_snow_overlay(make_snow_mask(albedo, foliage, trunk))
        snow_alpha = alpha_of(snow_overlay)
        bbox = trunk_alpha.getbbox()

        self.assertIsNotNone(bbox)
        assert bbox is not None
        visible_hits = 0
        visible_candidates = 0
        for x in range(bbox[0], bbox[2]):
            for y in range(bbox[1], min(bbox[3], bbox[1] + 280)):
                if trunk_alpha.getpixel((x, y)) > 48 and foliage_alpha.getpixel((x, y)) < 20:
                    visible_candidates += 1
                    if snow_alpha.getpixel((x, y)) > 18:
                        visible_hits += 1

        self.assertGreater(visible_candidates, 1000)
        self.assertGreater(visible_hits / visible_candidates, 0.24)

    def test_wind_mask_reaches_visible_upper_trunk(self) -> None:
        foliage = load_rgba(ASSET_DIR / "foliage.png")
        trunk = load_rgba(ASSET_DIR / "trunk.png")
        trunk_alpha = alpha_of(trunk)
        foliage_alpha = alpha_of(foliage)
        wind = make_wind_mask(trunk, foliage).getchannel("R")
        bbox = trunk_alpha.getbbox()

        self.assertIsNotNone(bbox)
        assert bbox is not None
        moving_upper_trunk = 0
        visible_upper_trunk = 0
        for x in range(bbox[0], bbox[2]):
            for y in range(bbox[1], min(bbox[3], bbox[1] + 300)):
                if trunk_alpha.getpixel((x, y)) > 48 and foliage_alpha.getpixel((x, y)) < 20:
                    visible_upper_trunk += 1
                    if wind.getpixel((x, y)) > 24:
                        moving_upper_trunk += 1

        self.assertGreater(visible_upper_trunk, 1000)
        self.assertGreater(moving_upper_trunk / visible_upper_trunk, 0.18)

    def test_baked_root_sinks_some_roots_below_anchor(self) -> None:
        albedo = load_rgba(ASSET_DIR / "albedo.png")
        alpha = alpha_of(albedo)
        bbox = alpha.getbbox()
        anchor_y = _asset_anchor()[1]

        self.assertIsNotNone(bbox)
        assert bbox is not None
        self.assertGreater(bbox[3] - anchor_y, 42)

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
