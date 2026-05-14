import sys
from unittest import mock
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import contour_parity_export  # noqa: E402


class ContourParityExportTests(unittest.TestCase):
    def test_task_11_case_matrix_is_complete(self):
        self.assertEqual(
            list(contour_parity_export.PARITY_CASES.keys()),
            [
                "single_tile",
                "two_by_two_blob",
                "large_blob",
                "large_cave_like_cut",
                "thin_diagonal_opening",
                "inner_dug_hole",
                "straight_south_face",
                "chunk_seam_edge",
                "mined_tile_notch",
            ],
        )

    def test_reference_request_uses_deterministic_runtime_sdf_export(self):
        request = contour_parity_export.build_reference_request("inner_dug_hole")

        self.assertEqual(request["asset_name"], "parity_inner_dug_hole")
        self.assertEqual(request["export_mode"], contour_parity_export.REFERENCE_EXPORT_MODE)
        self.assertEqual(request["preset"], "mountain")
        self.assertEqual(request["tile_size"], 64)
        self.assertEqual(request["seed"], contour_parity_export.PARITY_SEED)
        self.assertEqual(request["forced_variant"], 0)
        self.assertEqual(request["map"]["width"], 16)
        self.assertEqual(request["map"]["height"], 16)
        self.assertEqual(len(request["map"]["cells"]), 256)
        for y in (7, 8):
            for x in (7, 8):
                self.assertEqual(request["map"]["cells"][y * 16 + x], 0)

    def test_large_cave_like_cut_covers_visual_rescue_fail_case(self):
        request = contour_parity_export.build_reference_request("large_cave_like_cut")

        self.assertEqual(request["asset_name"], "parity_large_cave_like_cut")
        self.assertEqual(request["map"]["width"], 16)
        self.assertEqual(request["map"]["height"], 16)
        self.assertGreater(sum(request["map"]["cells"]), 120)
        for y, x in ((8, 7), (8, 8), (9, 7), (9, 8)):
            self.assertEqual(request["map"]["cells"][y * 16 + x], 0)

    def test_export_resolves_output_before_calling_core(self):
        with TemporaryDirectory() as tmp:
            output = Path(tmp) / "relative_like_output"
            seen_outputs = []

            def fake_run_core(_mode, _request, output_dir):
                seen_outputs.append(output_dir)
                return {"files": {}}

            with mock.patch.object(contour_parity_export, "run_core", side_effect=fake_run_core), \
                    mock.patch.object(contour_parity_export, "stop_core_server"):
                contour_parity_export.export_references(output, ["single_tile"])

            self.assertEqual(len(seen_outputs), 1)
            self.assertTrue(seen_outputs[0].is_absolute())
            self.assertEqual(seen_outputs[0].parent.parent, output.resolve())


if __name__ == "__main__":
    unittest.main()
