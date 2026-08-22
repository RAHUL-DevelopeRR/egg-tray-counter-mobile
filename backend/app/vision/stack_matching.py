from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from app.errors import StackAssociationError

VIEW_NAMES = ("left", "right", "straight")


@dataclass(frozen=True)
class StackObservation:
    view: str
    center_x_normalized: float
    height_normalized: float
    tray_count: int | None
    image_quality: float
    segmentation_quality: float
    periodicity_quality: float
    inferred_layers: int
    top_visible: bool = True
    bottom_visible: bool = True


@dataclass(frozen=True)
class MatchedStack:
    physical_stack_id: str
    observations: dict[str, StackObservation | None]
    association_confidence: float


def associate_by_spatial_order(
    observations: dict[str, list[StackObservation]],
    *,
    minimum_confidence: float,
) -> list[MatchedStack]:
    non_empty = {
        view: sorted(items, key=lambda item: item.center_x_normalized)
        for view, items in observations.items()
        if items
    }
    if len(non_empty) < 2:
        raise StackAssociationError("At least two views must contain visible stack faces")
    counts = {view: len(items) for view, items in non_empty.items()}
    if len(set(counts.values())) != 1:
        detail = ", ".join(f"{view}={count}" for view, count in sorted(counts.items()))
        raise StackAssociationError(f"Visible physical-stack counts disagree across views ({detail})")
    stack_count = next(iter(counts.values()))
    matched: list[MatchedStack] = []
    for index in range(stack_count):
        per_view = {
            view: non_empty.get(view, [None] * stack_count)[index] if view in non_empty else None
            for view in VIEW_NAMES
        }
        available = [observation for observation in per_view.values() if observation is not None]
        heights = np.asarray([observation.height_normalized for observation in available], dtype=np.float64)
        height_consistency = float(max(0.0, 1.0 - np.std(heights) / max(float(np.mean(heights)), 0.05)))
        rank_consistency = 1.0
        completeness = len(available) / 3
        confidence = float(
            np.clip(0.45 * height_consistency + 0.35 * rank_consistency + 0.20 * completeness, 0, 1)
        )
        if confidence < minimum_confidence:
            raise StackAssociationError(f"Stack {index + 1} could not be associated reliably across views")
        matched.append(
            MatchedStack(
                physical_stack_id=f"stack_{index + 1:02d}",
                observations=per_view,
                association_confidence=confidence,
            )
        )
    return matched
