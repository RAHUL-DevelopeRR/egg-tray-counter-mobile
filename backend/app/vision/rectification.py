from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class RectifiedFace:
    image: np.ndarray
    source_quad: np.ndarray
    homography: np.ndarray


def _order_quad(points: np.ndarray) -> np.ndarray:
    ordered = np.zeros((4, 2), dtype=np.float32)
    sums = points.sum(axis=1)
    differences = np.diff(points, axis=1).reshape(-1)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(differences)]
    ordered[3] = points[np.argmax(differences)]
    return ordered


def polygon_to_quad(polygon: Iterable[tuple[float, float]]) -> np.ndarray:
    points = np.asarray(tuple(polygon), dtype=np.float32)
    if points.ndim != 2 or points.shape[0] < 3 or points.shape[1] != 2:
        raise ValueError("A stack face requires at least three polygon points")
    if points.shape[0] == 4:
        quad = points
    else:
        rectangle = cv2.minAreaRect(points)
        quad = cv2.boxPoints(rectangle)
    ordered = _order_quad(quad)
    if abs(cv2.contourArea(ordered)) < 16:
        raise ValueError("Stack-face polygon area is too small")
    return ordered


def rectify_face(
    image: np.ndarray,
    polygon: Iterable[tuple[float, float]],
    target_size: tuple[int, int],
) -> RectifiedFace:
    width, height = target_size
    source = polygon_to_quad(polygon)
    destination = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype=np.float32,
    )
    homography = cv2.getPerspectiveTransform(source, destination)
    warped = cv2.warpPerspective(image, homography, (width, height), flags=cv2.INTER_LINEAR)
    return RectifiedFace(image=warped, source_quad=source, homography=homography)
