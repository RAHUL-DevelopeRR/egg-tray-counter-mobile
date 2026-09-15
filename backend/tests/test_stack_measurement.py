import json

import cv2
import numpy as np
import pytest

from app.vision.stack_measurement import (
    analyze_rims,
    calibrated_height_evidence,
    localize_stacks,
    rectify_native,
)


def test_bright_lip_pairs_are_one_band_and_alternating_strength_keeps_pitch():
    image = np.full((400, 120, 3), 40, dtype=np.uint8)
    for index, y in enumerate(range(20, 381, 24)):
        cv2.rectangle(image, (0, y - 3), (119, y + 3), (220 if index % 2 else 140,) * 3, -1)
    result = analyze_rims(image)
    json.dumps(result, allow_nan=False)
    assert result["best"]["count"] == len(range(20, 381, 24))
    assert abs(result["best"]["pitch_px"] - 24) <= 1
    assert result["best"]["feature"] == "bright"
    assert all(
        a < y < b for (a, b), y in zip(result["best"]["intervals"], result["best"]["centres"], strict=True)
    )
    assert {12, 24, 48}.issubset({c["pitch_px"] for c in result["hypotheses"]})
    assert result["physical_count"] is None and result["occupancy"] == "unknown"


def test_no_texture_cannot_produce_a_count():
    assert analyze_rims(np.zeros((100, 100, 3), np.uint8))["best"] is None


def test_stack_number_is_inferred_from_boxes_not_a_fixed_five():
    boxes = [
        {"bbox": [x, y, x + 70, y + 10], "confidence": 0.9}
        for x, levels in ((10, 7), (100, 4), (190, 6))
        for y in range(20, 20 + levels * 20, 20)
    ]
    stacks = localize_stacks(boxes, (200, 300, 3))
    assert [s["rf_count"] for s in stacks] == [7, 4, 6]
    assert all(s["top_visible"] is None for s in stacks)
    with pytest.raises(ValueError):
        localize_stacks([{"bbox": [-1, 2, 50, 40], "confidence": 0.9}], (100, 100))


def test_rectification_preserves_native_detail_and_rejects_outside_quad():
    image = np.zeros((800, 400, 3), np.uint8)
    face, info = rectify_native(image, [[10, 10], [310, 10], [310, 790], [10, 790]])
    assert face.image.shape[:2] == (780, 300)
    assert not info["completeness_verified"]
    with pytest.raises(ValueError):
        rectify_native(image, [[-2, 0], [10, 0], [10, 20], [0, 20]])


def test_calibration_is_measured_versioned_and_never_implies_filled():
    calibration = {
        "profile_id": "synthetic-only",
        "version": "1",
        "samples": [
            {"count": n, "height_cm": 3 + (n - 1) * 4, "uncertainty_cm": 0.1} for n in (1, 5, 10, 25)
        ],
    }
    measurement = {
        "calibration_id": "synthetic-only",
        "calibration_version": "1",
        "geometry_verified": True,
        "camera_calibration_id": "camera-test",
        "survey_reference_id": "survey-test",
        "height_cm": 47,
        "uncertainty_cm": 0.1,
    }
    evidence = calibrated_height_evidence(calibration, measurement)
    assert evidence["height_count"] == 12 and evidence["occupancy"] == "unknown"
    with pytest.raises(ValueError):
        calibrated_height_evidence(calibration, {**measurement, "geometry_verified": False})
