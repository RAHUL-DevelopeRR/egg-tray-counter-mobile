from __future__ import annotations

import pytest

from app.errors import StackAssociationError
from app.vision.fusion import fuse_stack
from app.vision.stack_matching import MatchedStack, StackObservation, associate_by_spatial_order


def observation(view: str, count: int | None, quality: float = 0.9) -> StackObservation:
    return StackObservation(
        view=view,
        center_x_normalized=0.5,
        height_normalized=0.8,
        tray_count=count,
        image_quality=quality,
        segmentation_quality=0.95,
        periodicity_quality=0.9,
        inferred_layers=0,
    )


@pytest.mark.parametrize(
    ("counts", "accepted", "final_count"),
    [
        ((18, 18, 17), True, 18),
        ((18, 17, 19), False, None),
        ((18, None, 18), True, 18),
        ((18, 18, None), True, 18),
        ((18, None, None), False, None),
    ],
)
def test_conservative_exact_agreement(test_settings, counts, accepted, final_count) -> None:
    stack = MatchedStack(
        physical_stack_id="stack_01",
        observations={
            "left": observation("left", counts[0]) if counts[0] is not None else None,
            "right": observation("right", counts[1]) if counts[1] is not None else None,
            "straight": observation("straight", counts[2]) if counts[2] is not None else None,
        },
        association_confidence=0.95,
    )
    result = fuse_stack(stack, test_settings)
    assert result.accepted is accepted
    assert result.final_count == final_count


def test_association_uses_order_and_rejects_count_mismatch(test_settings) -> None:
    with pytest.raises(StackAssociationError):
        associate_by_spatial_order(
            {
                "left": [observation("left", 18)],
                "right": [observation("right", 18), observation("right", 20)],
                "straight": [observation("straight", 18), observation("straight", 20)],
            },
            minimum_confidence=test_settings.association_threshold,
        )
