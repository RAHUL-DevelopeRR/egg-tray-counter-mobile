from __future__ import annotations

import numpy as np


def transparent_confidence(
    *,
    image_quality: float,
    segmentation_confidence: float,
    periodicity_quality: float,
    inferred_layers: int,
    maximum_inferred_layers: int,
) -> float:
    inference_support = max(0.0, 1.0 - inferred_layers / max(maximum_inferred_layers + 1, 1))
    return float(
        np.clip(
            0.25 * image_quality
            + 0.25 * segmentation_confidence
            + 0.40 * periodicity_quality
            + 0.10 * inference_support,
            0,
            1,
        )
    )
