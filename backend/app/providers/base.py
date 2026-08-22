from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

import numpy as np


@dataclass(frozen=True)
class StackFacePrediction:
    polygon: tuple[tuple[float, float], ...]
    bbox: tuple[float, float, float, float]
    confidence: float
    class_name: str
    metadata: dict[str, object] = field(default_factory=dict)

    @property
    def center_x(self) -> float:
        x1, _, x2, _ = self.bbox
        return (x1 + x2) / 2


@dataclass(frozen=True)
class InferenceResult:
    predictions: tuple[StackFacePrediction, ...]
    provider: str
    model_version: str
    latency_ms: int
    detection_count: int | None = None
    output_class: str | None = None
    average_detection_confidence: float | None = None


class InferenceProvider(ABC):
    @abstractmethod
    async def infer(
        self,
        image_bytes: bytes,
        image: np.ndarray,
        metadata: dict[str, object],
    ) -> InferenceResult:
        """Return stack-face predictions in original-image coordinates."""
