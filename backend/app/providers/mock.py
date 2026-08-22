from __future__ import annotations

import time

import numpy as np

from app.providers.base import InferenceProvider, InferenceResult, StackFacePrediction


class MockInferenceProvider(InferenceProvider):
    """Deterministic full-height faces for offline development and tests."""

    def __init__(self, stack_count: int = 1) -> None:
        self.stack_count = max(1, stack_count)

    async def infer(
        self,
        image_bytes: bytes,
        image: np.ndarray,
        metadata: dict[str, object],
    ) -> InferenceResult:
        started = time.perf_counter()
        height, width = image.shape[:2]
        outer_margin_x = width * 0.05
        top, bottom = height * 0.03, height * 0.97
        usable_width = width - 2 * outer_margin_x
        face_width = usable_width / self.stack_count
        predictions: list[StackFacePrediction] = []
        for index in range(self.stack_count):
            x1 = outer_margin_x + index * face_width + face_width * 0.04
            x2 = outer_margin_x + (index + 1) * face_width - face_width * 0.04
            polygon = ((x1, top), (x2, top), (x2, bottom), (x1, bottom))
            predictions.append(
                StackFacePrediction(
                    polygon=polygon,
                    bbox=(x1, top, x2, bottom),
                    confidence=0.99,
                    class_name="stack_face",
                    metadata={"mock": True, "index": index},
                )
            )
        return InferenceResult(
            predictions=tuple(predictions),
            provider="mock",
            model_version="mock/full-face-v1",
            latency_ms=round((time.perf_counter() - started) * 1000),
        )
