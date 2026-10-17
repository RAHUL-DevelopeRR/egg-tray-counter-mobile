"""Label perturbation: no prediction of the 2026-10-15 evaluation, stack-face experiment or walk-fill
experiment may depend on a label.

Every label value is changed: the eval manifest photos and not-usable labels, the labels.csv totals and region
labels, every per-stack truth value (filled and empty trays), and the walk reference file
(reports/field-labelled-20261007/per_stack_counts.csv: label_total and every assistant_count; which rows are
resolved stays the same). The three scripts are then re-run on the repo's saved detections and annotations
(read only; output goes to pytest's tmp_path). Every prediction must stay byte-identical, the walk-fill
experiment's stage-1 (label-free) output and chosen variant must not move, and the scores must change (so the
perturbation reached the scoring code).

Run from the repository root (PYTHONPATH must provide numpy):
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_label_perturbation.py
"""

from __future__ import annotations

import copy
import csv
import json
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import evaluate_labelled as ev  # noqa: E402
import experiment_stack_faces as ex  # noqa: E402
import experiment_walk_fill as wf  # noqa: E402

# Outputs left out of the prediction comparison: scores (label-derived) and the input file paths (the
# perturbed manifest lives in tmp_path).
EV_SKIP_SECTIONS = {"summary_labels", "summary_clusters", "summary_blocks", "raw_v2_box_count_clusters",
                    "clusters", "blocks", "per_stack_summary", "inputs"}
EV_SCORE_KEYS = {"label", "size", "result", "error", "abs_error", "would_be_exact", "raw_box_error",
                 "raw_box_exact", "user_filled", "user_empty", "walk_minus_filled", "walk_minus_all_trays",
                 "label_written", "region_labels", "shown_minus_written", "accepted_equal_to_written"}
EX_SCORE_KEYS = {"label", "err_A", "err_B", "err_B_short_as_walk", "err_C", "A_accepted_exact",
                 "labels_csv_value", "user_filled", "missing_layers", "walk_error", "span_error", "summary"}


def _strip(obj, keys):
    if isinstance(obj, dict):
        return {k: _strip(v, keys) for k, v in obj.items() if k not in keys}
    if isinstance(obj, list):
        return [_strip(v, keys) for v in obj]
    return obj


def _dump(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False)


def _write_csv(rows, path):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _perturb(tmp: Path):
    rnd = random.Random(20261015)
    original = ev._load(ev.MANIFEST)
    man = copy.deepcopy(original)
    for p in man["photos"] + man["not_usable"]:
        p["label_value"] = p["label_value"] * 3 + rnd.randint(1, 50)
        if "label_as_written" in p:
            p["label_as_written"] = str(p["label_value"])
        if p.get("region_labels"):
            p["region_labels"] = "|".join(str(int(v) + 9) for v in p["region_labels"].split("|"))
    for case in man["per_stack"]:
        for st in case["stacks"]:
            st["filled"] += rnd.randint(5, 40)
            st["empty"] = (st["empty"] or 0) + 3
    for old, new in zip(original["photos"] + original["not_usable"], man["photos"] + man["not_usable"],
                        strict=True):
        assert old["label_value"] != new["label_value"]
    manifest = tmp / "eval_manifest_perturbed.json"
    manifest.write_text(json.dumps(man, ensure_ascii=False), encoding="utf-8")

    with open(ex.LABELS_CSV, encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        r["label_total"] = str(int(r["label_total"]) * 7 + 11)
        if r["region_labels"]:
            r["region_labels"] = "|".join(str(int(v) * 2 + 1) for v in r["region_labels"].split("|"))
    labels_csv = tmp / "labels_perturbed.csv"
    _write_csv(rows, labels_csv)

    # Walk reference file: the photo label copy and every reference value change; the resolved rows (those
    # with a value) stay the same rows, because stage 1 reads their (image, column) positions.
    with open(wf.REFERENCE_CSV, encoding="utf-8") as fh:
        refs = list(csv.DictReader(fh))
    changed = 0
    for r in refs:
        r["label_total"] = str(int(r["label_total"]) * 5 + 3)
        if r["assistant_count"].strip():
            r["assistant_count"] = str(int(r["assistant_count"]) + rnd.randint(3, 9))
            changed += 1
    assert changed == 53
    reference_csv = tmp / "per_stack_counts_perturbed.csv"
    _write_csv(refs, reference_csv)
    return manifest, labels_csv, reference_csv


class _Inputs:
    """Point all three scripts at one set of label files for the duration of a run."""

    def __init__(self, manifest: Path, labels_csv: Path, reference_csv: Path):
        self.paths = manifest, labels_csv, reference_csv

    def __enter__(self):
        self.saved = ev.MANIFEST, ex.LABELS_CSV, wf.REFERENCE_CSV
        ev.MANIFEST, ex.LABELS_CSV, wf.REFERENCE_CSV = self.paths

    def __exit__(self, *exc):
        ev.MANIFEST, ex.LABELS_CSV, wf.REFERENCE_CSV = self.saved


@pytest.fixture(scope="module")
def inputs(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("perturb")
    return tmp, (ev.MANIFEST, ex.LABELS_CSV, wf.REFERENCE_CSV), _perturb(tmp)


@pytest.fixture(scope="module")
def runs(inputs):
    tmp, original_paths, perturbed_paths = inputs
    out = []
    for name, paths in (("original", original_paths), ("perturbed", perturbed_paths)):
        with _Inputs(*paths):
            out.append((ev.main(["--out", str(tmp / name)]), ex.run()))
    return tuple(out)


@pytest.fixture(scope="module")
def walk_fill_runs(inputs):
    _, original_paths, perturbed_paths = inputs
    out = []
    for paths in (original_paths, perturbed_paths):
        with _Inputs(*paths):
            out.append(wf.run())
    return tuple(out)


def _ev_predictions(results):
    return _dump(_strip({k: v for k, v in results.items() if k not in EV_SKIP_SECTIONS}, EV_SCORE_KEYS))


def _ex_predictions(results):
    return _dump(_strip(results, EX_SCORE_KEYS))


def test_evaluate_labelled_predictions_ignore_labels(runs):
    (a, _), (b, _) = runs
    assert _ev_predictions(a) == _ev_predictions(b)
    kept = json.loads(_ev_predictions(a))
    assert kept["photos"][0]["predicted_total"] == a["photos"][0]["predicted_total"]
    assert {"photos", "per_stack", "multi_view", "not_usable_secondary"} <= set(kept)
    assert a["summary_clusters"] != b["summary_clusters"]  # the perturbation reached the scores
    assert [p["label"] for p in a["photos"]] != [p["label"] for p in b["photos"]]


def test_experiment_predictions_ignore_labels(runs):
    (_, a), (_, b) = runs
    assert _ex_predictions(a) == _ex_predictions(b)
    kept = json.loads(_ex_predictions(a))
    assert {"per_image", "cross_view_association", "localization_A", "labelled_set_A_vs_C"} <= set(kept)
    assert a["labelled_set_A_vs_C"]["summary"] != b["labelled_set_A_vs_C"]["summary"]
    assert a["scored_polygon_images"] != b["scored_polygon_images"]
    assert a["not_usable_polygon_images"] != b["not_usable_polygon_images"]


def test_walk_fill_stage_1_and_choice_ignore_labels(walk_fill_runs):
    a, b = walk_fill_runs
    # Stage 1 serialised exactly as results.json writes it: byte-identical, key order included.
    stage_1 = [json.dumps(r["stage_1_label_free"], indent=1, ensure_ascii=False) for r in (a, b)]
    assert stage_1[0] == stage_1[1]
    assert a["stage_1_label_free"]["choice"] == b["stage_1_label_free"]["choice"]
    assert a["stage_1_label_free"]["choice"]["chosen"] in wf.VARIANTS
    assert {"criteria", "equal_extent_pairs", "polygon_counts", "outcomes", "block_results"} <= set(
        a["stage_1_label_free"])
    # The perturbation reached every label input of stage 2: manifest labels, per-stack values, reference
    # values and labels.csv.
    lb_a, lb_b = a["stage_2_label_based"], b["stage_2_label_based"]
    for key in ("clusters_22", "polygon_photos_9", "per_stack_user_reported", "reference_columns_53",
                "not_usable_outcome_changes"):
        assert lb_a[key] != lb_b[key], key
