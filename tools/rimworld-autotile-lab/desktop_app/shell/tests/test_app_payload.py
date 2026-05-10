import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app  # noqa: E402


class FakeVar:
    def __init__(self, value):
        self.value = value

    def get(self):
        return self.value

    def set(self, value):
        self.value = value


def make_request_builder_stub():
    instance = object.__new__(app.CliffForgeApp)
    instance._validated_asset_name = lambda show_error=False, raise_on_error=False: "test_asset"
    instance._selected_export_mode_key = lambda: "Full47"
    instance._selected_preset_key = lambda: "mountain"
    instance._selected_preview_mode_key = lambda: "composite"
    instance._build_materials_payload = lambda: {}
    instance._build_decal_payload = lambda: {}
    instance._build_silhouette_payload = lambda: {}
    instance.texture_paths = {"top": "", "face": "", "base": ""}
    instance.current_map = {"width": 1, "height": 1, "cells": [1]}

    for name, value in {
        "forced_variant_var": "Все",
        "tile_size_var": 64,
        "south_height_var": 24,
        "north_height_var": 12,
        "side_height_var": 14,
        "roughness_var": 0.25,
        "face_power_var": 1.0,
        "back_drop_var": 0.25,
        "crown_bevel_var": 4,
        "outer_corner_radius_var": 7,
        "inner_corner_radius_var": 11,
        "corner_round_px_var": 3,
        "diagonal_smooth_px_var": 5,
        "contour_relax_var": 0.4,
        "contour_warp_px_var": 2.5,
        "corner_variation_var": 0.2,
        "rim_width_var": 6,
        "edge_debris_var": 0.15,
        "geometry_variance_var": 0.1,
        "shape_supersampling_var": 2,
        "variants_var": 6,
        "seed_var": 42,
        "texture_scale_var": 1.0,
        "normal_strength_var": 2.0,
        "normal_detail_strength_var": 0.5,
        "bake_height_shading_var": True,
        "texture_color_overlay_var": False,
        "top_color_var": "#778899",
        "face_color_var": "#556677",
        "edge_color_var": "#cc5533",
        "edge_color_strength_var": 0.75,
        "back_color_var": "#334455",
        "base_color_var": "#223344",
    }.items():
        setattr(instance, name, FakeVar(value))

    return instance


class AppPayloadTests(unittest.TestCase):
    def test_build_request_preserves_separate_corner_radii(self):
        request = make_request_builder_stub().build_request()

        self.assertEqual(request["outer_corner_radius"], 7)
        self.assertEqual(request["inner_corner_radius"], 11)
        self.assertEqual(request["corner_round_px"], 3)
        self.assertEqual(request["colors"]["edge"], "#cc5533")
        self.assertEqual(request["edge_color_strength"], 0.75)

    def test_lit_preview_mode_does_not_show_normal_atlas_as_lit_atlas(self):
        instance = object.__new__(app.CliffForgeApp)
        instance._selected_preview_mode_key = lambda: "lit"
        atlas_calls = []
        preview_calls = []
        instance._set_atlas_image = lambda path: atlas_calls.append(Path(path))
        instance._set_preview_image = lambda path: preview_calls.append(Path(path))

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            preview = tmp_path / "preview.png"
            normal = tmp_path / "atlas_normal.png"
            albedo = tmp_path / "atlas_albedo.png"
            for path in (preview, normal, albedo):
                path.write_bytes(b"placeholder")

            instance._update_images(
                {
                    "mode": "full",
                    "export_mode": "Full47",
                    "files": {
                        "preview_png": str(preview),
                        "atlas_normal_png": str(normal),
                        "atlas_albedo_png": str(albedo),
                    },
                }
            )

        self.assertEqual(preview_calls, [preview])
        self.assertEqual(atlas_calls, [albedo])

    def test_full_manifest_without_preview_schedules_draft_refresh(self):
        instance = object.__new__(app.CliffForgeApp)
        requested_modes = []
        instance.pending_mode = None
        instance.last_warnings = []
        instance.stats_var = FakeVar("")
        instance._update_warnings_label = lambda: None
        instance._update_images = lambda _manifest: None
        instance._set_status = lambda _text: None
        instance._set_progress_active = lambda _active: None
        instance.request_render = lambda mode: requested_modes.append(mode)

        instance._handle_manifest(
            {
                "mode": "full",
                "build_ms": 1,
                "signature_count": 16,
                "total_tiles": 96,
                "files": {"preview_png": ""},
            }
        )

        self.assertEqual(requested_modes, ["draft"])

    def test_zooming_out_uses_smooth_resampling(self):
        self.assertEqual(
            app.resampling_for_zoom_scale(0.5),
            app.Image.Resampling.LANCZOS,
        )
        self.assertEqual(
            app.resampling_for_zoom_scale(1.0),
            app.Image.Resampling.NEAREST,
        )

    def test_preview_control_limits_match_core_sanitization(self):
        self.assertEqual(app.max_corner_radius_for_tile_size(32), 16)
        self.assertEqual(app.max_corner_radius_for_tile_size(64), 32)
        self.assertEqual(app.max_rim_width_for_tile_size(32), 8)
        self.assertEqual(app.max_rim_width_for_tile_size(64), 16)
        self.assertEqual(app.max_height_for_tile_size(32), 16)
        self.assertEqual(app.max_height_for_tile_size(64), 32)

    def test_panel_scale_release_defaults_to_draft_preview(self):
        instance = object.__new__(app.CliffForgeApp)
        calls = []
        instance.schedule_draft = lambda: calls.append("draft")
        instance.schedule_full = lambda: calls.append("full")

        instance._on_panel_scale_release()

        self.assertEqual(calls, ["draft"])

    def test_map_release_schedules_draft_preview(self):
        instance = object.__new__(app.CliffForgeApp)
        calls = []
        instance.schedule_draft = lambda: calls.append("draft")
        instance.schedule_full = lambda: calls.append("full")

        instance._on_map_release(None)

        self.assertEqual(calls, ["draft"])


if __name__ == "__main__":
    unittest.main()
