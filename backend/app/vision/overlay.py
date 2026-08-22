from __future__ import annotations

import cv2
import numpy as np

from app.providers.base import StackFacePrediction
from app.vision.layer_signal import LayerCountResult


def draw_source_predictions(image: np.ndarray, predictions: list[StackFacePrediction]) -> np.ndarray:
    canvas = image.copy()
    for index, prediction in enumerate(predictions, start=1):
        polygon = np.rint(np.asarray(prediction.polygon)).astype(np.int32)
        cv2.polylines(canvas, [polygon], isClosed=True, color=(0, 220, 120), thickness=3)
        origin = tuple(polygon[0])
        cv2.putText(
            canvas,
            f"stack_{index:02d} {prediction.confidence:.2f}",
            origin,
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
    return canvas


def draw_rectified_layers(rectified: np.ndarray, result: LayerCountResult) -> np.ndarray:
    canvas = rectified.copy()
    for position in result.peak_positions:
        cv2.line(canvas, (0, position), (canvas.shape[1] - 1, position), (0, 220, 120), 2)
    pitch = result.pitch_px and round(result.pitch_px, 1)
    label = f"count={result.tray_count} pitch={pitch} q={result.quality:.2f}"
    cv2.putText(canvas, label, (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    return canvas
