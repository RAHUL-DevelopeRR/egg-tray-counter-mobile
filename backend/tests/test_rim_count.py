import numpy as np
import pytest

from app.vision.rim_count import RimParams, rim_count


def _painted_stack(gaps, *, thickness=4, width=160, doubled_at=None, noise=0.0, seed=0):
    """Dark strip with one bright 'rim' band per layer; returns (image_bgr, column dict, centres)."""
    centres = []
    y = 40.0
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
    column = {
        "column": 1,
        "x_min": 20.0,
        "x_max": float(width - 20),
        "y_first": centres[0],
        "y_last": centres[-1],
        "pitch_px": float(np.median(np.diff(centres))),
        "span_count": len(centres),
        "model_boxes": len(centres),
    }
    return image, column, centres


def test_uniform_rims_are_counted_exactly():
    image, column, centres = _painted_stack([30.0] * 19, noise=4.0)
    result = rim_count(image, [column])[0]
    assert result["rim_count"] == 20
    assert result["agrees_with_span"] is True
    assert len(result["peaks_y"]) == 20 and result["inferred_rims"] == 0
    assert abs(result["perspective_gradient"] - 1.0) < 0.1
    assert result["top_y"] < centres[0] + column["pitch_px"] / 2
    assert result["base_y"] > centres[-1] - column["pitch_px"] / 2
    assert result["confidence"] > 0.6
    assert "verified" not in result


def test_perspective_rims_shrinking_from_28_to_16_px_count_twenty():
    gaps = np.linspace(28.0, 16.0, 19)
    image, column, _ = _painted_stack(gaps, noise=4.0)
    column["span_count"] = int(round((column["y_last"] - column["y_first"]) / column["pitch_px"])) + 1
    result = rim_count(image, [column])[0]
    assert result["rim_count"] == 20
    assert result["perspective_gradient"] > 1.3
    assert len(result["local_pitches"]) == 19
    assert result["local_pitches"][0] > result["local_pitches"][-1]
    assert result["agrees_with_span"] == (column["span_count"] == 20)


def test_doubled_edge_three_px_apart_is_counted_once():
    image, column, _ = _painted_stack([30.0] * 19, doubled_at=7)
    result = rim_count(image, [column])[0]
    assert result["rim_count"] == 20
    assert len(result["peaks_y"]) == 20


def test_missing_rim_is_inferred_from_a_double_gap_and_lowers_confidence():
    image, column, centres = _painted_stack([30.0] * 19)
    hole = int(round(centres[9] - 2))
    image[hole - 2 : hole + 6, :] = 30  # erase one rim entirely
    result = rim_count(image, [column])[0]
    assert len(result["peaks_y"]) == 19
    assert result["inferred_rims"] == 1 and result["rim_count"] == 20
    assert "inferred" in result["note"]
    without = rim_count(image, [column], RimParams(infer_missing=False))[0]
    assert without["rim_count"] == 19 and without["agrees_with_span"] is False
    assert result["confidence"] < rim_count(_painted_stack([30.0] * 19)[0], [column])[0]["confidence"]


@pytest.mark.parametrize(
    "image, columns",
    [
        (np.zeros((0, 0, 3), np.uint8), [{"x_min": 0, "x_max": 10, "y_first": 0, "y_last": 10,
                                          "pitch_px": 5}]),
        (None, [{"x_min": 0, "x_max": 10, "y_first": 0, "y_last": 10, "pitch_px": 5}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10, "x_max": 60, "y_first": 20, "y_last": 180,
                                                  "pitch_px": 20}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 150, "x_max": 180, "y_first": 20, "y_last": 180,
                                                  "pitch_px": 20}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10, "x_max": 60, "y_first": 20, "y_last": 180,
                                                  "pitch_px": float("nan")}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10, "x_max": 60, "y_first": 20, "y_last": 180,
                                                  "pitch_px": 0}]),
        (np.full((200, 100, 3), 90, np.uint8), [{"x_min": 10}]),
        (np.full((200, 100, 3), 90, np.uint8), ["not a dict"]),
        (np.full((200, 100), 90, np.uint8), [{"x_min": 10, "x_max": 60, "y_first": 300, "y_last": 400,
                                               "pitch_px": 20}]),
    ],
)
def test_degenerate_input_returns_none_without_raising(image, columns):
    results = rim_count(image, columns)
    assert len(results) == 1
    assert results[0]["rim_count"] is None
    assert results[0]["agrees_with_span"] is None
    assert results[0]["peaks_y"] == [] and results[0]["confidence"] == 0.0
    assert results[0]["note"]


def test_empty_column_list_and_missing_span_count():
    assert rim_count(np.zeros((50, 50, 3), np.uint8), []) == []
    image, column, _ = _painted_stack([30.0] * 19)
    del column["span_count"]
    result = rim_count(image, [column])[0]
    assert result["rim_count"] == 20 and result["agrees_with_span"] is None
