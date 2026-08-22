from __future__ import annotations

import cv2
import numpy as np
import pytest

from app.config import Settings
from app.vision.preprocessing import letterbox
from app.vision.quality import evaluate_quality
from app.vision.rectification import rectify_face
from tests.conftest import synthetic_stack


def test_coordinate_round_trip() -> None:
    image = np.zeros((300, 500, 3), dtype=np.uint8)
    _, transform = letterbox(image, (640, 640))
    original = (423.5, 244.25)
    restored = transform.to_original(transform.to_model(original))
    assert restored == pytest.approx(original)


def test_quality_rejects_blur() -> None:
    image = cv2.GaussianBlur(synthetic_stack(), (81, 81), 30)
    settings = Settings(min_image_width=200, min_image_height=200, min_blur_score=250.0)
    quality = evaluate_quality(image, settings)
    assert not quality.accepted
    assert quality.reason == "Image is blurry"


def test_rectification_has_configured_shape() -> None:
    image = synthetic_stack(width=500, height=700)
    polygon = ((40.0, 30.0), (460.0, 60.0), (440.0, 670.0), (60.0, 650.0))
    result = rectify_face(image, polygon, (320, 480))
    assert result.image.shape == (480, 320, 3)
    assert abs(cv2.contourArea(result.source_quad)) > 100_000
