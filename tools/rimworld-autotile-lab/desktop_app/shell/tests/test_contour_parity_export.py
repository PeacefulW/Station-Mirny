import sys
import unittest
from pathlib import Path

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
        self.assertEqual(request["tile_size"], 128)
        self.assertEqual(request["seed"], contour_parity_export.PARITY_SEED)
        self.assertEqual(request["forced_variant"], 0)
        self.assertEqual(request["map"]["width"], 16)
        self.assertEqual(request["map"]["height"], 16)
        self.assertEqual(len(request["map"]["cells"]), 256)
        for y in (7, 8):
            for x in (7, 8):
                self.assertEqual(request["map"]["cells"][y * 16 + x], 0)


if __name__ == "__main__":
    unittest.main()
