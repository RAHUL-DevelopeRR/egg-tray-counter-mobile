from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

import numpy as np

from app.config import Settings
from app.vision.stack_matching import MatchedStack, StackObservation


@dataclass(frozen=True)
class FusedStack:
    physical_stack_id: str
    counts: dict[str, int | None]
    final_count: int | None
    confidence: float
    accepted: bool
    reason: str
    association_confidence: float


def _usable(observation: StackObservation | None, settings: Settings) -> bool:
    return bool(
        observation
        and observation.tray_count is not None
        and observation.image_quality >= settings.min_view_quality
        and observation.periodicity_quality >= 0.30
        and observation.inferred_layers <= settings.max_inferred_layers
        and observation.top_visible
        and observation.bottom_visible
    )


def fuse_stack(stack: MatchedStack, settings: Settings) -> FusedStack:
    counts = {
        view: observation.tray_count if observation else None
        for view, observation in stack.observations.items()
    }
    usable = {
        view: observation
        for view, observation in stack.observations.items()
        if _usable(observation, settings)
    }
    if len(usable) < 2:
        return FusedStack(
            physical_stack_id=stack.physical_stack_id,
            counts=counts,
            final_count=None,
            confidence=0.0,
            accepted=False,
            reason="Fewer than two high-quality views contain a complete layer estimate",
            association_confidence=stack.association_confidence,
        )
    groups: dict[int, list[StackObservation]] = defaultdict(list)
    for observation in usable.values():
        assert observation is not None and observation.tray_count is not None
        groups[observation.tray_count].append(observation)
    agreeing = [(count, members) for count, members in groups.items() if len(members) >= 2]
    if len(agreeing) != 1:
        return FusedStack(
            physical_stack_id=stack.physical_stack_id,
            counts=counts,
            final_count=None,
            confidence=0.0,
            accepted=False,
            reason="Usable views do not agree exactly on one integer tray count",
            association_confidence=stack.association_confidence,
        )
    final_count, agreeing_observations = agreeing[0]
    evidence_scores = [
        min(item.image_quality, item.segmentation_quality, item.periodicity_quality)
        for item in agreeing_observations
    ]
    confidence = float(
        np.clip(
            0.55 * float(np.mean(evidence_scores))
            + 0.30 * stack.association_confidence
            + 0.15 * (len(agreeing_observations) / 3),
            0,
            1,
        )
    )
    return FusedStack(
        physical_stack_id=stack.physical_stack_id,
        counts=counts,
        final_count=final_count,
        confidence=confidence,
        accepted=True,
        reason=f"{len(agreeing_observations)}/3 usable views agree exactly",
        association_confidence=stack.association_confidence,
    )


def fuse_scene(stacks: list[MatchedStack], settings: Settings) -> list[FusedStack]:
    return [fuse_stack(stack, settings) for stack in stacks]
