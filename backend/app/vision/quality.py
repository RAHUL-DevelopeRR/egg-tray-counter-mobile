from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from app.config import Settings
from app.errors import InvalidImageError


@dataclass(frozen=True)
class ImageQuality:
    score: float
    accepted: bool
    blur_score: float
    exposure_mean: float
    dark_fraction: float
    bright_fraction: float
    width: int
    height: int
    reason: str | None


def decode_image(content: bytes) -> np.ndarray:
    encoded = np.frombuffer(content, dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
    if image is None or image.ndim != 3 or image.shape[2] != 3:
        raise InvalidImageError("The uploaded file is not a decodable JPEG or PNG image")
    return image


def evaluate_quality(image: np.ndarray, settings: Settings) -> ImageQuality:
    height, width = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    exposure_mean = float(gray.mean())
    dark_fraction = float(np.mean(gray <= 15))
    bright_fraction = float(np.mean(gray >= 245))

    resolution_score = min(1.0, width / settings.min_image_width, height / settings.min_image_height)
    blur_component = min(1.0, blur_score / max(settings.min_blur_score * 2.0, 1.0))
    centered_exposure = max(0.0, 1.0 - abs(exposure_mean - 127.5) / 127.5)
    clipping_component = max(0.0, 1.0 - max(dark_fraction, bright_fraction))
    score = float(
        np.clip(
            0.25 * resolution_score
            + 0.30 * blur_component
            + 0.20 * centered_exposure
            + 0.25 * clipping_component,
            0.0,
            1.0,
        )
    )

    reason: str | None = None
    if width < settings.min_image_width or height < settings.min_image_height:
        reason = f"Image resolution is too low ({width}x{height})"
    elif blur_score < settings.min_blur_score:
        reason = "Image is blurry"
    elif dark_fraction > settings.max_dark_fraction:
        reason = "Image is severely underexposed"
    elif bright_fraction > settings.max_bright_fraction:
        reason = "Image is severely overexposed"
    return ImageQuality(
        score=score,
        accepted=reason is None and score >= settings.min_view_quality,
        blur_score=blur_score,
        exposure_mean=exposure_mean,
        dark_fraction=dark_fraction,
        bright_fraction=bright_fraction,
        width=width,
        height=height,
        reason=reason,
    )
