import numpy as np
import pytest

from app.vision.rim_count import RimParams, rim_count


def _painted_stack(gaps, *, thickness=4, width=160, doubled_at=None, noise=0.0, seed=0, top_margin=40.0):
    """Dark strip with one bright 'rim' band per layer and a lighter floor; returns (image_bgr, column dict, centres)."""
    centres = []
    y = top_margin
    for gap in list(gaps) + [None]:
        centres.append(y + thickness / 2)
        if gap is None:
            break
        y += gap
    height = int(centres[-1] + 60)
    image = np.full((height, width, 3), 30, np.uint8)
    pitch = float(np.median(np.diff(centres))) if len(centres) > 1 else 30.0
    image[int(centres[-1] + 0.5 * pitch) :, :] = 120  # floor under the stack, as in a real photo
    for c in centres:
        top = int(round(c - thickness / 2))
        image[top : top + thickness, 20 : width - 20] = 230
    if doubled_at is not None:
        top = int(round(centres[doubled_at] - thickness / 2))
        image[top : top + thickness + 1, 20 : width - 20] = 30
        image[top : top + 2, 20 : width - 20] = 230  # two 2 px lines whose tops are 3 px apart
        image[top + 3 : top + 5, 20 : width - 20] = 230
    if noise:
        rng = np.random.default_rng(seed)
        image = np.clip(image.astype(float) + rng.normal(0, noise, image.shape), 0, 255).astype(np.uint8)
    # Only the x-range: the reader never needs the detector's vertical positions or pitch to count.
    column = {"column": 1, "x_min": 20.0, "x_max": float(width - 20)}
    return image, column, centres


def test_uniform_rims_are_counted_from_the_x_range_alone():
    image, column, centres = _painted_stack([30.0] * 19, noise=4.0)
    result = rim_count(image, [column])[0]
    assert result["readable"] is True and result["rim_count"] == 20
    assert len(result["peaks_y"]) == 20
    assert abs(result["perspective_gradient"] - 1.0) < 0.1
    assert abs(result["top_y"] - centres[0]) < 15 and abs(result["base_y"] - centres[-1]) < 15
    assert result["confidence"] >= 0.5
    assert result["agrees_with_walk"] is None  # no detector count was sent
    assert "verified" not in result


def test_detector_vertical_positions_only_feed_the_comparison_fields():
    image, column, centres = _painted_stack([30.0] * 19, noise=4.0)
    # The detector boxed only the middle 16 layers: the count is unchanged and the comparison shows the extra layers.
    boxed = {**column, "y_first": centres[2], "y_last": centres[-3], "walk_count": 16, "span_count": 16}
    plain, compared = rim_count(image, [column])[0], rim_count(image, [boxed])[0]
    assert plain["rim_count"] == compared["rim_count"] == 20
    assert compared["run_extra_layers"] == 4 and compared["run_extends"] == "both"
    assert compared["agrees_with_walk"] is False


def test_perspective_rims_shrinking_from_28_to_16_px_count_twenty():
    image, column, _ = _painted_stack(np.linspace(28.0, 16.0, 19), noise=4.0)
    result = rim_count(image, [column])[0]
    assert result["rim_count_raw"] == 20
    assert result["perspective_gradient"] > 1.3
    assert result["local_pitches"][0] > result["local_pitches"][-1]


def test_doubled_edge_three_px_apart_is_counted_once():
    image, column, _ = _painted_stack([30.0] * 19, doubled_at=7)
    assert rim_count(image, [column])[0]["rim_count_raw"] == 20


def test_a_run_reaching_the_frame_edge_is_unreadable_not_guessed():
    image, column, _ = _painted_stack([30.0] * 19, top_margin=0.0)
    result = rim_count(image, [column])[0]
    assert result["readable"] is False and result["rim_count"] is None
    assert result["rim_count_raw"] is not None
    assert "frame edge" in result["unreadable_reason"]


def test_pitch_alternatives_are_reported():
    image, column, _ = _painted_stack([30.0] * 19, noise=4.0)
    alternatives = rim_count(image, [column])[0]["pitch_alternatives"]
    assert set(alternatives) == {"half", "layer", "pair"}


@pytest.mark.parametrize(
    "image, columns",
    [
        (np.zeros((0, 0, 3), np.uint8), [{"x_min": 0, "x_max": 10}]),
        (None, [{"x_min": 0, "x_max": 10}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10, "x_max": 60}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 150, "x_max": 180}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10, "x_max": float("nan")}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 60, "x_max": 10}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10}]),
        (np.full((200, 100, 3), 90, np.uint8), ["not a dict"]),
    ],
)
def test_degenerate_input_returns_none_without_raising(image, columns):
    results = rim_count(image, columns)
    assert len(results) == 1
    assert results[0]["rim_count"] is None and results[0]["readable"] is False
    assert results[0]["peaks_y"] == [] and results[0]["confidence"] == 0.0
    assert results[0]["note"]


def test_empty_column_list():
    assert rim_count(np.zeros((50, 50, 3), np.uint8), []) == []


def test_params_are_frozen_dataclass():
    with pytest.raises(Exception):
        RimParams().min_confidence = 0.1  # type: ignore[misc]
