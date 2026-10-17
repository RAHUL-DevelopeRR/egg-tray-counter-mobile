"""Walk variants of scripts/experiment_walk_fill.py on synthetic boxes (no repo data, no labels).

Run from the repository root:
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_experiment_walk_fill.py
"""

from __future__ import annotations

import inspect
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import experiment_walk_fill as wf  # noqa: E402
from app.vision import layer_span, stack_separation  # noqa: E402
from app.vision.layer_span import count_layers_by_span  # noqa: E402


def _ys(gaps, start=100.0, pitch=50.0):
    ys = [start]
    for g in gaps:
        ys.append(ys[-1] + g * pitch)
    return ys


def _counts(ys, height=45.0):
    return {v: wf.WALKS[v](ys, height)["count"] for v in wf.VARIANTS}


def test_generic_walk_with_defaults_is_the_deployed_walk():
    rng = random.Random(20261015)
    for _ in range(500):
        y, ys = 0.0, []
        for _ in range(rng.randint(1, 30)):
            y += rng.choice(
                [rng.uniform(5, 60), rng.uniform(40, 60), rng.uniform(80, 130), rng.uniform(140, 200)]
            )
            ys.append(y)
        rng.shuffle(ys)
        height = rng.uniform(20, 60)
        mine = wf.walk(ys, height)
        assert mine.pop("declined_fills") == 0
        assert mine == layer_span.walk_layers(ys, height)


def test_span_matches_the_column_record():
    rng = random.Random(7)
    for _ in range(200):
        ys = sorted(rng.uniform(0, 1500) for _ in range(rng.randint(3, 25)))
        boxes = [{"x": 100.0, "y": y, "width": 120.0, "height": 40.0} for y in ys]
        assert wf.span_from_ys(ys, 40.0) == stack_separation.column_record(boxes)["span_count"]


def test_clean_stack_reads_the_same_under_every_variant():
    ys = _ys([1.0] * 19)
    assert set(_counts(ys).values()) == {20}
    assert all(wf.WALKS[v](ys, 45.0)["filled"] == 0 for v in wf.VARIANTS)


def test_one_missed_layer_is_filled_by_every_variant():
    gaps = [1.0] * 19
    gaps[9:11] = [2.0]  # box of layer 11 missing
    ys = _ys(gaps)
    assert set(_counts(ys).values()) == {20}
    assert {wf.WALKS[v](ys, 45.0)["filled"] for v in wf.VARIANTS} == {1}


def test_pitch_ratchet_overfill_and_the_fixes():
    # A 1.5-pitch gap is split in two; the deployed walk then feeds 0.75 back into its local pitch, so the
    # following ordinary 1.2-pitch gaps are split in two as well (the pitch ends at its 0.6 floor).
    ys = _ys([1.0] * 5 + [1.5, 1.2, 1.2, 1.2])
    span = wf.span_from_ys(ys, 45.0)
    c = _counts(ys)
    assert span == 11
    assert c["V0"] == 14 and c["V0"] > span + 1
    assert c["V1"] == span + 1  # capped
    assert c["V2"] == span  # fallback
    assert c["V3"] == 10  # 1.5 has residual 0.5 > 0.25: not filled, counted as one step
    assert c["V4"] == 11  # the fill stays, but the pitch keeps following observed one-layer gaps


def test_upward_pitch_drift_drops_layers_and_only_the_span_variants_restore_them():
    # After three 1.3-pitch gaps the local pitch is high, so 0.8-pitch layers fall under 0.65 x pitch and are
    # dropped as duplicates. V4 does not address this (its pitch also follows observed one-layer gaps).
    ys = _ys([1.0] * 3 + [1.3] * 3 + [0.8] * 6)
    span = wf.span_from_ys(ys, 45.0)
    c = _counts(ys)
    assert span == 14 and c["V0"] == 10
    assert c["V1"] == span - 1 and c["V2"] == span
    assert c["V3"] == 10 and c["V4"] == 10
    capped = wf.WALKS["V1"](ys, 45.0)
    assert (
        capped["deployed_count"] == 10 and capped["filled"] == 3
    )  # 10 kept boxes, 3 layers added by the floor


def test_strict_fill_declines_when_the_local_pitch_has_drifted():
    # Local pitch drifts to about 0.8 of the global pitch, then a gap of exactly 2 local pitches follows.
    ys = _ys([1.0] * 6 + [0.8, 0.8, 0.8, 1.6, 0.8])
    v0, v3 = wf.WALKS["V0"](ys, 45.0), wf.WALKS["V3"](ys, 45.0)
    assert v0["filled"] == 1
    assert v3["filled"] == 0 and v3["declined_fills"] == 1 and v3["count"] == v0["count"] - 1


def test_strict_fill_keeps_a_clean_double_gap_at_the_global_pitch():
    ys = _ys([1.0] * 6 + [2.05] + [1.0] * 4)
    v3 = wf.WALKS["V3"](ys, 45.0)
    assert v3["filled"] == 1 and v3["declined_fills"] == 0


def test_unresolved_gaps_are_unchanged_by_every_variant():
    ys = _ys([1.0] * 5 + [6.0] + [1.0] * 5)  # five missing layers: never bridged
    for v in wf.VARIANTS:
        assert wf.WALKS[v](ys, 45.0)["unresolved_gaps"] == 1


def test_use_walk_swaps_and_restores_even_on_error():
    boxes = [
        {"x": 100.0, "y": y, "width": 120.0, "height": 45.0} for y in _ys([1.0] * 5 + [1.5, 1.2, 1.2, 1.2])
    ]
    deployed = count_layers_by_span(boxes)[0]["walk_count"]
    with wf.use_walk("V4"):
        assert layer_span.walk_layers is wf.walk_observed_pitch
        assert stack_separation.walk_layers is wf.walk_observed_pitch
        assert count_layers_by_span(boxes)[0]["walk_count"] == 11
        assert stack_separation.column_record(boxes)["walk_count"] == 11
    assert deployed == 14 and layer_span.walk_layers is wf.DEPLOYED_WALK
    with pytest.raises(RuntimeError), wf.use_walk("V1"):
        raise RuntimeError("boom")
    assert layer_span.walk_layers is wf.DEPLOYED_WALK and stack_separation.walk_layers is wf.DEPLOYED_WALK


def _crit(pairs_gt1, pairs_sum, cross_gt1=0, ref_gt1=0, changed=0):
    return {
        "equal_extent": {"diff_gt1": pairs_gt1, "abs_diff_sum": pairs_sum},
        "cross_view": {"spread_gt1": cross_gt1},
        "reference": {"equal_extent_diff_gt1": ref_gt1, "changed_vs_V0": changed},
    }


def test_choice_rule_excludes_span_variants_and_harmful_ones():
    crit = {
        "V0": _crit(15, 97),
        "V1": _crit(1, 2),
        "V2": _crit(0, 0),
        "V3": _crit(2, 18, ref_gt1=3, changed=4),
        "V4": _crit(11, 47),
    }
    choice = wf.choose_variant(crit)
    assert choice["eligible"] == ["V0", "V4"]
    assert choice["chosen"] == "V4" and choice["walk_change_for_trial"] is True
    assert any("span" in r for r in choice["ineligible_reasons"]["V2"])
    assert any("reference" in r for r in choice["ineligible_reasons"]["V3"])
    crit["V4"] = _crit(11, 47, cross_gt1=1)
    assert wf.choose_variant(crit)["chosen"] == "V0"


def test_stage_one_functions_take_no_label():
    for fn in (
        wf.walk,
        wf.walk_cap,
        wf.walk_fallback,
        wf.walk_strict,
        wf.walk_observed_pitch,
        wf.polygon_counts,
        wf.equal_extent_summary,
        wf.walk_span_summary,
        wf.cross_view,
        wf.reference_consistency,
        wf.outcomes,
        wf.outcome_changes,
        wf.block_results,
        wf.choose_variant,
        wf.label_free,
    ):
        assert not any("label" in name or "manifest" in name for name in inspect.signature(fn).parameters)
