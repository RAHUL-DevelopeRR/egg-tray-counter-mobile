from __future__ import annotations

import cv2
import numpy as np
import pytest

from app.config import Settings


@pytest.fixture
def test_settings() -> Settings:
    return Settings(
        min_image_width=200,
        min_image_height=200,
        min_blur_score=5.0,
        min_view_quality=0.30,
        min_pitch_px=14,
        max_pitch_px=60,
        peak_prominence_factor=0.45,
        association_threshold=0.50,
        rectified_width=320,
        rectified_height=480,
    )


def synthetic_stack(layers: int = 18, variant: int = 0, width: int = 480, height: int = 720) -> np.ndarray:
    image = np.full((height, width, 3), (54, 142, 70), dtype=np.uint8)
    top, bottom = 38, height - 38
    rail_positions = np.linspace(top, bottom, layers, dtype=int)
    for position in rail_positions:
        cv2.line(image, (0, int(position)), (width - 1, int(position)), (225, 240, 225), 3)
    cv2.rectangle(image, (4 + variant * 3, 4), (14 + variant * 3, 18), (variant * 30, 30, 220), -1)
    return image


def encoded_stack(layers: int = 18, variant: int = 0) -> bytes:
    ok, encoded = cv2.imencode(
        ".jpg",
        synthetic_stack(layers=layers, variant=variant),
        [cv2.IMWRITE_JPEG_QUALITY, 95],
    )
    assert ok
    return encoded.tobytes()
