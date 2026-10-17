"""Localization bookkeeping of scripts/experiment_stack_faces.py on synthetic boxes and polygons (no repo data).

Run from the repository root:
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_experiment_stack_faces.py
"""

from __future__ import annotations

import inspect
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import experiment_stack_faces as ex  # noqa: E402


def _rect(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


def _column(x, ys, width=100, height=20):
    return [{"x": x, "y": y, "width": width, "height": height} for y in ys]


IMAGE = {"id": "synthetic", "polygons": [
    {"id": "front", "role": "target", "polygon": _rect(0, 300, 200, 700), "depth_row": 0},
    {"id": "rear", "role": "target", "polygon": _rect(0, 0, 200, 300), "depth_row": 1},
    {"id": "right", "role": "target", "polygon": _rect(300, 0, 500, 700), "depth_row": 0},
    {"id": "loose", "role": "target", "polygon": _rect(600, 0, 900, 700), "depth_row": 0},
    {"id": "bg", "role": "neighbour", "polygon": _rect(1000, 0, 1200, 700), "depth_row": 2},
]}


def test_inside_and_assign():
    assert ex.inside((50, 50), _rect(0, 0, 100, 100))
    assert not ex.inside((150, 50), _rect(0, 0, 100, 100))
    owner, multi = ex.assign([{"x": 100, "y": 400}, {"x": 400, "y": 100}, {"x": 950, "y": 100}], IMAGE["polygons"])
    assert owner == ["front", "right", None] and multi == 0


def test_localization_statuses():
    boxes = (_column(100, [320, 360, 400, 440]) + _column(100, [100, 140, 180])  # front + rear in one column
             + _column(400, [100, 140, 180, 220]) + [{"x": 750, "y": 300, "width": 300, "height": 200}]
             + _column(1100, [100, 140, 180]))
    owner, _ = ex.assign(boxes, IMAGE["polygons"])
    stacks = [{"column": 1, "walk_count": 7, "box_indices": list(range(0, 7))},
              {"column": 2, "walk_count": 4, "box_indices": list(range(7, 11))},
              {"column": 3, "walk_count": 3, "box_indices": list(range(12, 15))}]  # box 11 (loose) not placed
    loc = ex.localization(stacks, owner, IMAGE, boxes)
    status = {t["polygon"]: t["status"] for t in loc["per_target"]}
    assert status == {"front": "merged_with_target", "rear": "merged_with_target", "right": "correct",
                      "loose": "missed"}
    assert loc["found_with_neighbour_boxes"] == 1 and loc["found_neighbour_only"] == 1
    mixed = next(f for f in loc["found"] if f["index"] == 1)
    assert mixed["merge_parts_walk"] == {"front": 4, "rear": 3} and mixed["merge_effect"] == 0


def test_predictions_never_take_a_label():
    for fn in (ex.arm_a, ex.arm_b, ex.arm_c, ex.localization, ex.equal_extent_pairs, ex.association,
               ex.predict_labelled_set, ex.per_stack_recall):
        assert not any("label" in name for name in inspect.signature(fn).parameters)
