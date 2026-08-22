from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class LetterboxTransform:
    original_width: int
    original_height: int
    target_width: int
    target_height: int
    scale: float
    pad_x: float
    pad_y: float

    def to_model(self, point: tuple[float, float]) -> tuple[float, float]:
        x, y = point
        return x * self.scale + self.pad_x, y * self.scale + self.pad_y

    def to_original(self, point: tuple[float, float]) -> tuple[float, float]:
        x, y = point
        original_x = (x - self.pad_x) / self.scale
        original_y = (y - self.pad_y) / self.scale
        return (
            float(np.clip(original_x, 0, self.original_width - 1)),
            float(np.clip(original_y, 0, self.original_height - 1)),
        )

    def polygon_to_original(self, points: Iterable[tuple[float, float]]) -> tuple[tuple[float, float], ...]:
        return tuple(self.to_original(point) for point in points)


def letterbox(
    image: np.ndarray, target_size: tuple[int, int] = (640, 640)
) -> tuple[np.ndarray, LetterboxTransform]:
    target_width, target_height = target_size
    original_height, original_width = image.shape[:2]
    scale = min(target_width / original_width, target_height / original_height)
    resized_width = max(1, round(original_width * scale))
    resized_height = max(1, round(original_height * scale))
    resized = cv2.resize(image, (resized_width, resized_height), interpolation=cv2.INTER_AREA)
    pad_x = (target_width - resized_width) / 2
    pad_y = (target_height - resized_height) / 2
    left, top = int(np.floor(pad_x)), int(np.floor(pad_y))
    right, bottom = target_width - resized_width - left, target_height - resized_height - top
    boxed = cv2.copyMakeBorder(resized, top, bottom, left, right, cv2.BORDER_CONSTANT, value=(114, 114, 114))
    transform = LetterboxTransform(
        original_width=original_width,
        original_height=original_height,
        target_width=target_width,
        target_height=target_height,
        scale=scale,
        pad_x=float(left),
        pad_y=float(top),
    )
    return boxed, transform
