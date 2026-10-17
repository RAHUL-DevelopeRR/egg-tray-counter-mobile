"""Scoring arithmetic of scripts/evaluate_labelled.py on synthetic inputs (no repo data, no network).

Run from the repository root:
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_evaluate_labelled.py
"""

from __future__ import annotations

import inspect
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import evaluate_labelled as ev  # noqa: E402


def _row(pred, label, outcome):
    return ev.score_photo(pred, label, outcome)


def test_score_photo_outcomes():
    assert _row(100, 100, "accepted") == {"result": "accepted_correct", "accepted": True, "error": 0,
                                          "abs_error": 0, "would_be_exact": True}
    wrong = _row(78, 80, "accepted")
    assert (wrong["result"], wrong["error"], wrong["abs_error"]) == ("accepted_wrong", -2, 2)
    held = _row(19, 19, "withheld_flagged")
    assert (held["result"], held["accepted"], held["would_be_exact"]) == ("withheld_flagged", False, True)
    assert _row(0, 358, "withheld_gate")["abs_error"] == 358


def test_summarize_counts_and_rates():
    rows = [_row(100, 100, "accepted"), _row(78, 80, "accepted"), _row(0, 358, "withheld_gate"),
            _row(19, 20, "withheld_flagged"), _row(7, 7, "accepted")]
    s = ev.summarize(rows)
    assert (s["n"], s["accepted"], s["accepted_correct"], s["accepted_wrong"]) == (5, 3, 2, 1)
    assert (s["withheld"], s["withheld_gate"], s["withheld_flagged"], s["withheld_would_be_exact"]) == (2, 1, 1, 0)
    assert s["completion_rate"] == 0.6 and s["withheld_rate"] == 0.4
    assert s["exact_rate_on_accepted"] == 0.6667 and s["correct_and_shown_rate"] == 0.4
    assert s["mae_all"] == pytest.approx(72.2) and s["mean_signed_all"] == pytest.approx(-72.2)
    assert (s["median_abs_all"], s["max_abs_all"]) == (1, 358)
    assert s["mae_accepted"] == pytest.approx(0.667) and s["median_abs_accepted"] == 0 and s["max_abs_accepted"] == 2


def test_summarize_with_nothing_accepted_and_empty():
    s = ev.summarize([_row(0, 1, "withheld_gate"), _row(3, 2, "withheld_gate")])
    assert s["accepted"] == 0 and s["exact_rate_on_accepted"] is None and s["mae_accepted"] is None
    assert s["withheld_rate"] == 1.0 and s["mae_all"] == 1.0
    empty = ev.summarize([])
    assert empty["n"] == 0 and empty["completion_rate"] is None and empty["mae_all"] is None


@pytest.mark.parametrize("label,band", [(1, "<=10"), (10, "<=10"), (11, "11-60"), (60, "11-60"), (61, ">60")])
def test_size_band(label, band):
    assert ev.size_band(label) == band


def test_cluster_level_keeps_lowest_id_and_checks_agreement():
    base = {"group": "G", "predicted_total": 100}
    rows = [dict(base, label_id=24, cluster="C1", label=100, result="accepted_correct", error=0),
            dict(base, label_id=21, cluster="C1", label=100, result="accepted_correct", error=0),
            dict(base, label_id=5, cluster="C2", label=90, result="accepted_wrong", error=10),
            dict(base, label_id=6, cluster="C2", label=100, result="accepted_correct", error=0)]
    reps, table = ev.cluster_level(rows)
    assert [r["label_id"] for r in reps] == [5, 21]
    assert {t["cluster"]: t["members_agree"] for t in table} == {"C1": True, "C2": False}


def _stack(x, layers, y0=100.0, pitch=22.0, width=150.0, height=20.0):
    return [{"class": "egg_tray", "confidence": 0.8, "x": x, "y": y0 + k * pitch, "width": width, "height": height}
            for k in range(layers)]


def test_predict_face_counts_columns_and_applies_gate():
    face = _stack(200, 20) + _stack(400, 20) + _stack(600, 20)
    pred = ev.predict_face(face, 800, 600)
    assert pred["outcome"] == "accepted" and pred["gate_reasons"] == []
    assert [c["walk_count"] for c in pred["columns"]] == [20, 20, 20] and pred["predicted_total"] == 60
    lone = ev.predict_face([face[0]], 800, 600)  # fewer than 3 boxes is not a stack
    assert lone["outcome"] == "withheld_gate" and lone["gate_reasons"] == [ev.NO_STACKS]
    assert lone["predicted_total"] == 0 and lone["raw_boxes"] == 1
    far = ev.predict_face(face, 800, 2000)  # the same face small in a tall frame
    assert far["outcome"] == "withheld_gate" and ev.HEIGHT_REASON in far["gate_reasons"]


def test_duplicate_box_is_merged_and_long_gap_flags_the_column():
    face = _stack(200, 20) + _stack(400, 20) + _stack(600, 20)
    dup = dict(face[5], y=face[5]["y"] + 3)  # a second box on the same layer
    assert ev.predict_face(face + [dup], 800, 600)["predicted_total"] == 60
    gappy = [d for i, d in enumerate(face) if not 5 <= i <= 9]  # five missed layers in column 1
    pred = ev.predict_face(gappy, 800, 600)
    assert pred["outcome"] == "withheld_flagged" and pred["flagged_columns"] == 1


def test_prediction_never_takes_a_label():
    assert list(inspect.signature(ev.predict_face).parameters) == ["detections", "image_width", "image_height"]
    assert list(inspect.signature(ev.predict_block).parameters) == ["views"]
