"""Run without vision dependencies: python -m unittest tests.test_hybrid_core."""

import unittest
from dataclasses import replace

from app.vision.hybrid import ColumnEvidence, HeightCalibration, HeightSample, fuse_hybrid


def evidence(column="A/1", count=20, filled=20):
    return tuple(
        ColumnEvidence(
            column_id=column, view=view, image_sha256=digit * 64,
            camera_azimuth_deg=angle, calibration_id="measured-v1",
            height_candidates=(count,), detected_trays=count, filled_trays=filled,
            occupancy_complete=True, geometry_valid=True, identity_resolved=True,
            full_column_visible=True, layer_count=count,
        )
        for view, digit, angle in (("left", "a", -30), ("straight", "b", 0), ("right", "c", 30))
    )


def fuse(items, columns=frozenset({"A/1"})):
    return fuse_hybrid(columns, items, calibration_id="measured-v1")


class HeightTests(unittest.TestCase):
    def setUp(self):
        self.calibration = HeightCalibration(
            "filled-tray-v1", tuple(HeightSample(n, 5 + (n - 1) * 3, 0.05) for n in (1, 5, 10, 40))
        )

    def test_known_count(self):
        self.assertEqual(self.calibration.candidates(62, 0.1), (20,))

    def test_uncertainty_is_not_rounded(self):
        self.assertGreater(len(self.calibration.candidates(63.5, 2)), 1)

    def test_boundary_cannot_manufacture_unique_count(self):
        self.assertEqual(self.calibration.candidates(123.5, 2), ())

    def test_no_extrapolation(self):
        self.assertEqual(self.calibration.candidates(200, 0.1), ())

    def test_inconsistent_calibration(self):
        samples = (*self.calibration.samples[:3], HeightSample(40, 15, 0.1))
        with self.assertRaises(ValueError):
            HeightCalibration("wrong", samples)

    def test_nonfinite_or_zero_measurement(self):
        for height, error in ((float("nan"), 1), (1, float("inf")), (0, 1), (1, 0)):
            with self.subTest(height=height, error=error), self.assertRaises(ValueError):
                self.calibration.candidates(height, error)


class FusionTests(unittest.TestCase):
    def test_each_column_summed_once(self):
        result = fuse(evidence() + evidence("A/2", 40, 38), frozenset({"A/1", "A/2"}))
        self.assertTrue(result.accepted)
        self.assertEqual(result.total_filled_trays, 58)

    def test_known_empty_trays_excluded(self):
        self.assertEqual(fuse(evidence(filled=0)).total_filled_trays, 0)

    def test_generic_tray_class_cannot_prove_occupancy(self):
        self.assertFalse(fuse(tuple(replace(o, filled_trays=None) for o in evidence())).accepted)

    def test_missing_scope_column_hides_all_totals(self):
        result = fuse(evidence(), frozenset({"A/1", "B/1"}))
        self.assertFalse(result.accepted)
        self.assertIsNone(result.total_filled_trays)
        self.assertEqual(result.columns, ())

    def test_fail_closed_evidence(self):
        for mutation in (
            {"height_candidates": (19, 20)}, {"detected_trays": 19},
            {"layer_count": 21}, {"filled_trays": 21}, {"occupancy_complete": False},
            {"calibration_id": "stale"}, {"filled_trays": 19},
        ):
            with self.subTest(mutation=mutation):
                observations = evidence()
                self.assertFalse(fuse((replace(observations[0], **mutation), *observations[1:])).accepted)

    def test_occlusion_is_not_zero(self):
        self.assertFalse(fuse(tuple(replace(o, full_column_visible=False) for o in evidence())).accepted)

    def test_two_complete_views_can_use_third_occluded_view(self):
        a, b, c = evidence()
        self.assertTrue(fuse((a, b, replace(c, full_column_visible=False))).accepted)

    def test_duplicate_photos(self):
        self.assertFalse(fuse(tuple(replace(o, image_sha256="a" * 64) for o in evidence())).accepted)

    def test_duplicate_column_in_view(self):
        self.assertFalse(fuse((*evidence(), evidence()[0])).accepted)

    def test_missing_guided_view(self):
        self.assertFalse(fuse(evidence()[:2]).accepted)

    def test_same_pose_with_different_files(self):
        self.assertFalse(fuse(tuple(replace(o, camera_azimuth_deg=0) for o in evidence())).accepted)

    def test_angle_wraparound(self):
        items = tuple(replace(o, camera_azimuth_deg=a) for o, a in zip(evidence(), (359, 0, 1), strict=True))
        self.assertFalse(fuse(items).accepted)

    def test_nonfinite_pose_and_invalid_counts(self):
        for mutation in ({"camera_azimuth_deg": float("nan")}, {"filled_trays": True},
                         {"detected_trays": -1}, {"height_candidates": (0,)},
                         {"occupancy_complete": "false"}):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                replace(evidence()[0], **mutation)

    def test_pose_and_image_consistent_across_columns(self):
        other = tuple(replace(o, camera_azimuth_deg=o.camera_azimuth_deg + 20) for o in evidence("B/1"))
        self.assertFalse(fuse(evidence() + other, frozenset({"A/1", "B/1"})).accepted)


if __name__ == "__main__":
    unittest.main()
