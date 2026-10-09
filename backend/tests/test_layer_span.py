import json
from pathlib import Path

import pytest

from app.vision.layer_span import count_layers_by_span, walk_layers

RAW = Path(__file__).resolve().parents[2] / "reports" / "field-labelled-20261007" / "raw"


def _boxes(levels, x, pitch=40, duplicate_at=None, y0=100):
    boxes = [{"x": x, "y": y0 + k * pitch, "width": 80, "height": 36} for k in range(levels)]
    if duplicate_at is not None:
        boxes.append({"x": x + 2, "y": y0 + duplicate_at * pitch + 3, "width": 78, "height": 36})
    return boxes


def test_duplicate_box_does_not_inflate_span_count():
    result = count_layers_by_span(_boxes(20, 100, duplicate_at=7))
    assert len(result) == 1
    assert result[0]["model_boxes"] == 21
    assert result[0]["span_count"] == 20
    assert result[0]["duplicate_boxes"] == 1
    assert result[0]["verified"] is False


def test_missed_middle_layer_is_recovered_but_missed_base_is_not():
    middle_gap = [b for b in _boxes(20, 100) if b["y"] != 100 + 9 * 40]
    assert count_layers_by_span(middle_gap)[0]["span_count"] == 20
    no_base = _boxes(19, 100)
    assert count_layers_by_span(no_base)[0]["span_count"] == 19


def test_columns_are_split_by_x_and_short_groups_dropped():
    boxes = _boxes(20, 100) + _boxes(18, 300) + _boxes(2, 500)
    result = count_layers_by_span(boxes)
    assert [r["span_count"] for r in result] == [20, 18]


def test_invalid_box_rejected():
    with pytest.raises(ValueError):
        count_layers_by_span([{"x": 1, "y": 2, "width": 0, "height": 5}])


def _archived(image_id):
    for path in sorted(RAW.glob("batch-*.json")):
        rec = json.loads(path.read_text())
        for view, i in rec["ids"].items():
            if i == image_id:
                return rec["response"]["views"][view]["detections"]
    raise FileNotFoundError(image_id)


@pytest.mark.skipif(not RAW.exists(), reason="archived field responses not present")
def test_archived_frontal_scene_img19_gives_five_columns_of_twenty():
    result = count_layers_by_span(_archived(19))
    assert [r["span_count"] for r in result] == [20, 20, 20, 20, 20]


@pytest.mark.skipif(not RAW.exists(), reason="archived field responses not present")
def test_archived_img21_duplicates_removed():
    result = count_layers_by_span(_archived(21))
    assert [r["model_boxes"] for r in result] == [20, 20, 20, 20, 21]
    assert [r["span_count"] for r in result] == [20, 20, 20, 20, 20]


def test_walk_counts_perspective_shrinking_pitch_exactly():
    ys, y, gap = [100.0], 100.0, 28.0
    for _ in range(19):  # 20 layers, spacing shrinking 28 -> 16 px
        y += gap
        ys.append(y)
        gap -= 12 / 19
    walk = walk_layers(ys, 24.0)
    assert walk["count"] == 20
    assert walk["perspective_gradient"] > 1.4


def test_walk_merges_duplicates_and_fills_single_gaps():
    ys = [100 + 40 * k for k in range(20)]
    ys += [100 + 40 * 7 + 3]       # duplicate box on layer 8
    del ys[12]                     # layer 13 missed by the detector
    walk = walk_layers(ys, 36.0)
    assert walk["count"] == 20 and walk["duplicates"] == 1 and walk["filled"] == 1


def test_walk_handles_degenerate_input():
    assert walk_layers([], 36.0)["count"] == 0
    assert walk_layers([5.0], 36.0)["count"] == 1
    assert walk_layers([5.0, 6.0], 36.0)["count"] == 1   # two boxes on one layer


@pytest.mark.skipif(not RAW.exists(), reason="archived field responses not present")
def test_archived_img01_walk_corrects_the_span_rounding():
    cols = count_layers_by_span(_archived(1))
    assert [c["span_count"] for c in cols] == [21, 20, 20, 20, 19]
    assert [c["walk_count"] for c in cols] == [20, 20, 20, 20, 19]
