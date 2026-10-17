"""Synthetic-box tests for app.vision.stack_separation (arm C of the 2026-10-15 stack-face experiment)."""

import pytest

from app.vision.layer_span import count_layers_by_span
from app.vision.stack_separation import column_record, separate_stacks


def _stack(levels, x, pitch=40.0, width=200.0, height=38.0, y0=100.0, skip=(), width_end=None):
    """One column of boxes, top to bottom. ``width_end`` makes the width change linearly (perspective)."""
    boxes = []
    for k in range(levels):
        if k in skip:
            continue
        w = width if width_end is None else width + (width_end - width) * k / max(1, levels - 1)
        boxes.append({"x": x, "y": y0 + k * pitch, "width": w, "height": height})
    return boxes


def _all_boxes_accounted(result, n):
    seen = [i for s in result["stacks"] for i in s["box_indices"]] + [d["index"] for d in result["dropped"]]
    return sorted(seen) == list(range(n))


def test_column_record_matches_count_layers_by_span():
    column = _stack(20, 300, skip=(9,)) + [{"x": 302, "y": 100 + 4 * 40 + 3, "width": 198, "height": 38}]
    expected = count_layers_by_span(column)[0]
    assert column_record(column) == expected
    assert expected["walk_count"] == 20 and expected["walk_filled"] == 1


def test_clean_frontal_face_is_unchanged_from_layer_span():
    boxes = _stack(20, 150) + _stack(20, 400) + _stack(19, 650)
    result = separate_stacks(boxes)
    expected = [r["walk_count"] for r in count_layers_by_span(boxes)]
    assert [s["walk_count"] for s in result["stacks"]] == expected
    assert result["total"] == 59
    assert {s["depth"] for s in result["stacks"]} == {"front"}
    assert result["dropped"] == []
    assert _all_boxes_accounted(result, len(boxes))


def test_short_front_stack_is_split_from_the_set_back_stack_above_it():
    # Rear stack: only its top 6 layers show above the short front stack; narrower boxes (farther away),
    # then a gap of ~3 pitches where the short stack's top tray is seen from above.
    rear_top = _stack(6, 400, pitch=38, width=130, height=36, y0=500)
    front = _stack(12, 395, pitch=40, width=205, height=38, y0=500 + 5 * 38 + 3 * 40)
    boxes = rear_top + front
    merged = count_layers_by_span(boxes)
    assert len(merged) == 1  # layer_span sees one column
    result = separate_stacks(boxes)
    assert len(result["stacks"]) == 2
    upper = min(result["stacks"], key=lambda s: s["y_first"])
    lower = max(result["stacks"], key=lambda s: s["y_first"])
    assert upper["depth"] == "set_back_partial" and upper["partial"] and upper["walk_count"] == 6
    assert lower["depth"] == "front" and not lower["partial"] and lower["walk_count"] == 12
    assert "base hidden" in upper["flags"][0]
    assert result["total"] == 18


def test_missed_layers_with_the_same_box_width_do_not_split():
    boxes = _stack(20, 300, skip=(6, 7))  # a 3-pitch gap, same width above and below
    result = separate_stacks(boxes)
    assert len(result["stacks"]) == 1
    assert result["stacks"][0]["depth"] == "front"


def test_gradual_perspective_width_change_does_not_split():
    # Camera above the stack: widths shrink steadily from top to base, plus one missed layer.
    boxes = _stack(16, 300, width=140, width_end=100, skip=(8,))
    result = separate_stacks(boxes)
    assert len(result["stacks"]) == 1


def test_narrow_boxes_below_a_gap_do_not_split():
    # Only a narrower UPPER part is a set-back stack; a narrower lower part is not split.
    boxes = _stack(6, 300, width=210, y0=100) + _stack(8, 300, width=130, y0=100 + 5 * 40 + 3 * 40)
    assert len(separate_stacks(boxes)["stacks"]) == 1


def test_loose_trays_and_two_tray_stacks_are_kept_as_short_stacks():
    boxes = [{"x": 300, "y": 300, "width": 600, "height": 200}]
    result = separate_stacks(boxes)
    assert result["total"] == 1
    assert result["stacks"][0]["short"] and "short stack (1 box)" in result["stacks"][0]["flags"]
    two = _stack(2, 150, pitch=60, width=300, height=55) + _stack(20, 600, width=300)
    result = separate_stacks(two)
    assert [s["walk_count"] for s in result["stacks"]] == [2, 20]
    assert result["stacks"][0]["short"] and not result["stacks"][1]["short"]


def test_duplicate_box_on_a_single_tray_counts_once():
    boxes = [{"x": 300, "y": 300, "width": 500, "height": 400},
             {"x": 310, "y": 320, "width": 480, "height": 380}]
    result = separate_stacks(boxes)
    assert result["total"] == 1 and len(result["stacks"]) == 1


def test_small_far_short_group_is_dropped_as_background():
    far = {"x": 700, "y": 300, "width": 90, "height": 18}
    boxes = _stack(15, 200, width=170) + _stack(15, 420, width=170) + [far]
    result = separate_stacks(boxes)
    assert result["total"] == 30
    assert [d["index"] for d in result["dropped"]] == [30]
    assert "background" in result["dropped"][0]["reason"]
    assert _all_boxes_accounted(result, len(boxes))


def test_frame_edge_slivers_are_dropped_before_grouping():
    slivers = [{"x": 14, "y": y, "width": 28, "height": 300} for y in (170, 500, 760)]
    trays = [{"x": 280, "y": 190, "width": 460, "height": 380},
             {"x": 280, "y": 600, "width": 550, "height": 460}]
    boxes = slivers + trays
    assert count_layers_by_span(boxes)[0]["walk_count"] == 3  # layer_span counts the three slivers
    result = separate_stacks(boxes)
    assert result["total"] == 2
    assert [d["index"] for d in result["dropped"]] == [0, 1, 2]
    assert all("sliver" in d["reason"] for d in result["dropped"])


def test_set_back_column_is_labelled_and_still_counted():
    set_back = _stack(14, 1000, pitch=30, width=270, height=28)
    boxes = _stack(15, 200, width=370) + _stack(15, 650, width=370) + set_back
    result = separate_stacks(boxes)
    assert [s["depth"] for s in result["stacks"]] == ["front", "front", "set_back"]
    assert result["stacks"][2]["scale"] == pytest.approx(270 / 370, abs=1e-3)
    assert result["total"] == 44


def test_empty_and_invalid_input():
    assert separate_stacks([])["total"] == 0
    with pytest.raises(ValueError):
        separate_stacks([{"x": 1, "y": 2, "width": 0, "height": 5}])
    with pytest.raises(ValueError):
        separate_stacks([{"x": 1, "y": float("nan"), "width": 3, "height": 5}])
