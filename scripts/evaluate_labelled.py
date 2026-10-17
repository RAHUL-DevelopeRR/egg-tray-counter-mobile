"""Offline evaluation of the deployed counting logic on the count-labelled field photos.

What is evaluated: the counting logic of Worker commit 318eb04 (staging version 47cb2378, app 0.4.11):
span columns + walk counter (backend/app/vision/layer_span.py), the block model's per-column retake
reasons (backend/app/vision/block_model.py `_face`) and the capture gate (`captureQuality` in
cloudflare-worker/src/index.ts, ported below line by line). The Python ports are the repo's own;
`--js-parity` checks them against a build of the Worker.

Inputs are saved detections only (no network, no inference, deterministic):
- reports/field-labelled-20261007/raw/batch-*.json  (Roboflow projec-mutta/2 via the production Worker, 7 Oct)
- reports/eval-20261015/eval_manifest.json           (labels, tiers, clusters, leak status; scoring only)
- saved Worker responses for the per-stack and multi-view sections (paths in the manifest)

Labels are evaluation targets only. `predict_face` and `predict_block` never receive a label; scores
are joined afterwards in `score_photo` / `score_not_usable`. scripts/tests/test_label_perturbation.py
changes every label and per-stack truth value and checks that every prediction stays byte-identical.

Units: near-duplicate clusters (primary), labels, and physical blocks (lowest label id per block_id). The
28 labels the audit marks not usable at image level are predicted and shown in a secondary table only.

Run from the repository root:
  python scripts/evaluate_labelled.py --out <dir>
  python scripts/evaluate_labelled.py --js-parity <scratch>/index-318eb04.mjs   # optional, needs node
Writes results.csv and results.json to --out (default reports/eval-20261015).
"""

from __future__ import annotations

import argparse
import csv
import glob
import itertools
import json
import math
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))

from app.vision.block_model import _face, build_block  # noqa: E402
from app.vision.layer_span import count_layers_by_span  # noqa: E402

OUT_DIR = REPO / "reports" / "eval-20261015"
MANIFEST = OUT_DIR / "eval_manifest.json"
RAW_LABELLED = REPO / "reports" / "field-labelled-20261007" / "raw"
RAW_MUTAA = REPO / "reports" / "mutaa-20260916" / "raw"
VIEWS = ("left", "right", "straight")

# ---- Capture gate: port of cloudflare-worker/src/index.ts @ 318eb04 (GATE, captureQuality, medianBoxAspect,
# worstView). RECESS_SCALE is the block model's 0.85.
GATE = {
    "max_pitch_gradient": 1.2,
    "min_coverage_x": 0.45,
    "min_coverage_single": 0.25,
    "min_height_frac": 0.4,
    "recess_floor": 0.6,
    "full_height_waiver": 0.8,
    "min_box_aspect": 2.75,
}
RECESS_SCALE = 0.85
NO_STACKS = "no stacks detected"
SIDEWAYS = "the trays look sideways or unclear in this photo; hold the phone level and retake"
WIDTH_REASON = "stacks cover too little of the frame width"
HEIGHT_REASON = "stacks are too small in the frame (too far away)"
GRADIENT_REASON = "layer pitch changes across the face (angled or corner view)"


def _median(values):
    s = sorted(values)
    n = len(s)
    return s[(n - 1) // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


def _js_round3(value):
    return None if value is None else math.floor(value * 1000 + 0.5) / 1000  # Math.round(v * 1000) / 1000


def median_box_aspect(detections):
    aspects = [d["width"] / d["height"] for d in detections
               if (d.get("width") or 0) > 0 and (d.get("height") or 0) > 0]
    return _median(aspects) if aspects else None


def capture_quality(columns, image_width, image_height, box_aspect=None):
    finite = lambda v: v is not None and math.isfinite(v) and v > 0  # noqa: E731
    w = image_width if finite(image_width) else None
    h = image_height if finite(image_height) else None
    image = {"width": w, "height": h} if w and h else None
    aspect = box_aspect if box_aspect is not None and math.isfinite(box_aspect) else None
    sideways = aspect is not None and aspect < GATE["min_box_aspect"]
    if not columns:
        return {"accepted": False, "reasons": [SIDEWAYS, NO_STACKS] if sideways else [NO_STACKS],
                "metrics": {"columns": 0, "model_boxes": 0, "pitch_px": None, "pitch_frac": None,
                            "height_frac": None, "coverage_x": None, "pitch_gradient": None,
                            "recessed_columns": 0, "min_pitch_scale": None, "box_aspect": _js_round3(aspect),
                            "image": image}}
    ordered = sorted(columns, key=lambda c: c["x_min"])
    pitches = [c["pitch_px"] for c in ordered]
    face_median = _median(pitches)
    reference = _median([p for p in pitches if p >= face_median])
    scales = [p / reference if reference else 1 for p in pitches]
    recessed = [i for i, s in enumerate(scales) if s < RECESS_SCALE]
    gradient_columns = ([c for i, c in enumerate(ordered) if i != recessed[0]]
                        if len(recessed) == 1 and scales[recessed[0]] >= GATE["recess_floor"] else ordered)
    k = max(1, math.ceil(len(gradient_columns) / 3))
    head = _median([c["pitch_px"] for c in gradient_columns[:k]])
    tail = _median([c["pitch_px"] for c in gradient_columns[-k:]])
    gradient = max(head / tail, tail / head) if len(gradient_columns) >= 2 and head > 0 and tail > 0 else 1
    covered, span = 0.0, None
    for c in ordered:
        if span and c["x_min"] <= span[1]:
            span[1] = max(span[1], c["x_max"])
        else:
            if span:
                covered += span[1] - span[0]
            span = [c["x_min"], c["x_max"]]
    if span:
        covered += span[1] - span[0]
    coverage = covered / w if w else None
    height_frac = max(c["y_last"] - c["y_first"] + c["pitch_px"] for c in ordered) / h if h else None
    pitch_frac = face_median / h if h else None
    reasons = []
    if sideways:
        reasons.append(SIDEWAYS)
    if gradient > GATE["max_pitch_gradient"]:
        reasons.append(GRADIENT_REASON)
    min_coverage = GATE["min_coverage_single"] if len(ordered) == 1 else GATE["min_coverage_x"]
    fills_height = height_frac is not None and height_frac >= GATE["full_height_waiver"]
    if coverage is not None and coverage < min_coverage and not fills_height:
        reasons.append(WIDTH_REASON)
    if height_frac is not None and height_frac < GATE["min_height_frac"]:
        reasons.append(HEIGHT_REASON)
    return {"accepted": not reasons, "reasons": reasons, "metrics": {
        "columns": len(ordered), "model_boxes": sum(c["model_boxes"] for c in ordered),
        "pitch_px": math.floor(face_median * 100 + 0.5) / 100, "pitch_frac": _js_round3(pitch_frac),
        "height_frac": _js_round3(height_frac), "coverage_x": _js_round3(coverage),
        "pitch_gradient": _js_round3(gradient), "recessed_columns": len(recessed),
        "min_pitch_scale": _js_round3(min(scales)), "box_aspect": _js_round3(aspect), "image": image}}


def worst_view(capture, views=VIEWS):
    def rank(q):
        hf = q["metrics"]["height_frac"]
        return (100 if NO_STACKS in q["reasons"] else 0) + len(q["reasons"]) * 10 + (1 - (1 if hf is None else hf))
    rejected = [v for v in views if not capture[v]["accepted"]]
    rejected.sort(key=lambda v: (-rank(capture[v]), views.index(v)))
    return rejected[0] if rejected else None


# ---- Prediction (no labels anywhere below until score_photo).

def _boxes(detections):
    return [d for d in detections if all(isinstance(d.get(k), (int, float)) and math.isfinite(d[k])
                                         for k in ("x", "y", "width", "height")) and d["width"] > 0 and d["height"] > 0]


def predict_face(detections, image_width, image_height):
    """One photo as one face: span/walk columns, block-model column reasons, capture gate, totals.

    predicted_total = sum of walk_count over every span column (3+ boxes) on the photo, INCLUDING
    columns the block model would mark recessed (it counts them as an observed stack behind a missing
    front one) and INCLUDING flagged columns (only reported; a flag withholds the photo). Boxes in
    groups of fewer than 3 (loose trays, strays) are never counted, as in the Worker.
    """
    boxes = _boxes(detections)
    columns = count_layers_by_span(boxes)
    gate = capture_quality(columns, image_width, image_height, median_box_aspect(boxes))
    face = _face(columns, "straight") if columns else []
    by_x = sorted(columns, key=lambda c: c["x_min"])  # _face orders by x_min too
    cols = []
    for col, f in zip(by_x, face):
        cols.append({
            "column": col["column"], "x_min": col["x_min"], "x_max": col["x_max"],
            "model_boxes": col["model_boxes"], "span_count": col["span_count"], "walk_count": col["walk_count"],
            "walk_filled": col["walk_filled"], "walk_unresolved_gaps": col["walk_unresolved_gaps"],
            "perspective_gradient": col["perspective_gradient"], "pitch_px": col["pitch_px"],
            "box_height_px": col["box_height_px"],
            "box_pitch_ratio": round(col["box_height_px"] / col["pitch_px"], 3) if col["pitch_px"] else None,
            "scale": f["scale"], "recessed": f["recessed"], "reason": f["reason"]})
    flagged = [c for c in cols if c["reason"]]
    if not gate["accepted"]:
        outcome = "withheld_gate"
    elif flagged:
        outcome = "withheld_flagged"
    else:
        outcome = "accepted"
    return {
        "outcome": outcome,
        "gate_accepted": gate["accepted"], "gate_reasons": gate["reasons"], "gate_metrics": gate["metrics"],
        "flagged_columns": len(flagged), "flag_reasons": [c["reason"] for c in flagged],
        "recessed_columns": sum(c["recessed"] for c in cols),
        "columns": cols,
        "predicted_total": sum(c["walk_count"] for c in cols),
        "predicted_total_without_recessed": sum(c["walk_count"] for c in cols if not c["recessed"]),
        "span_total": sum(c["span_count"] for c in cols),
        "boxes_in_columns": sum(c["model_boxes"] for c in cols),
        "raw_boxes": len(detections),
    }


def predict_block(views):
    """Three faces -> the Worker's model_spatial_v1 block result (modelDiagnostics semantics, rim verify off).

    views: {left|right|straight: {"detections": [...], "image": {"width", "height"} | None}}.
    """
    columns, capture = {}, {}
    for v in VIEWS:
        boxes = _boxes(views[v]["detections"])
        columns[v] = count_layers_by_span(boxes)
        img = views[v].get("image") or {}
        capture[v] = capture_quality(columns[v], img.get("width"), img.get("height"), median_box_aspect(boxes))
    rejected = worst_view(capture)
    assembled = build_block(columns["straight"], columns["left"] or None, columns["right"] or None)
    block = dict(assembled)
    if rejected:
        block.update(status="needs_view", total_trays=None, faces_consistent=False, fully_observed=False)
    named = None
    for c in assembled["conflicts"]:
        reason = str(c.get("reason", ""))
        for v in ("LEFT", "RIGHT", "STRAIGHT"):
            if reason.startswith(v + ":"):
                named = v.lower()
                break
        if named:
            break
    block["capture"] = capture
    block["recommended_view"] = rejected or named or "straight"
    block["walk_by_view"] = {v: [c["walk_count"] for c in sorted(columns[v], key=lambda c: c["x_min"])]
                             for v in VIEWS}
    return block


# ---- Scoring (labels enter here, after prediction).

def score_photo(predicted_total, label, outcome):
    accepted = outcome == "accepted"
    error = predicted_total - label
    if accepted:
        result = "accepted_correct" if error == 0 else "accepted_wrong"
    else:
        result = outcome
    return {"result": result, "accepted": accepted, "error": error, "abs_error": abs(error),
            "would_be_exact": error == 0}


def _rate(k, n):
    return None if not n else round(k / n, 4)


def summarize(rows):
    """rows: dicts with result, accepted, error, abs_error, would_be_exact."""
    n = len(rows)
    acc = [r for r in rows if r["accepted"]]
    correct = sum(r["result"] == "accepted_correct" for r in rows)
    wrong = sum(r["result"] == "accepted_wrong" for r in rows)
    gate = sum(r["result"] == "withheld_gate" for r in rows)
    flagged = sum(r["result"] == "withheld_flagged" for r in rows)
    abs_all = [r["abs_error"] for r in rows]
    abs_acc = [r["abs_error"] for r in acc]
    return {
        "n": n,
        "accepted": len(acc), "accepted_correct": correct, "accepted_wrong": wrong,
        "withheld": gate + flagged, "withheld_gate": gate, "withheld_flagged": flagged,
        "withheld_would_be_exact": sum(r["would_be_exact"] and not r["accepted"] for r in rows),
        "completion_rate": _rate(len(acc), n),
        "withheld_rate": _rate(gate + flagged, n),
        "exact_rate_on_accepted": _rate(correct, len(acc)),
        "correct_and_shown_rate": _rate(correct, n),
        "mae_all": round(statistics.fmean(abs_all), 3) if abs_all else None,
        "median_abs_all": statistics.median(abs_all) if abs_all else None,
        "max_abs_all": max(abs_all) if abs_all else None,
        "mean_signed_all": round(statistics.fmean(r["error"] for r in rows), 3) if rows else None,
        "mae_accepted": round(statistics.fmean(abs_acc), 3) if abs_acc else None,
        "median_abs_accepted": statistics.median(abs_acc) if abs_acc else None,
        "max_abs_accepted": max(abs_acc) if abs_acc else None,
    }


def size_band(label):
    return "<=10" if label <= 10 else ("11-60" if label <= 60 else ">60")


def used_in_logic_tuning(r):
    """Gate tuning set, walk reference photos, walk development (9 Oct) or capture-gate orientation
    development (0.4.8; img-46). Manifest tags only, never a label."""
    return bool(r["in_gate_tuning_set"] or r["in_walk_reference_photos"] or r["in_walk_development_photos"]
                or r["in_orientation_development_photos"])


STRATA = (
    ("all", lambda r: "all"),
    ("tier", lambda r: r["tier"]),
    ("leak", lambda r: r["detector_leak"]),
    ("size", lambda r: size_band(r["label"])),
    ("logic_dev", lambda r: "used_in_tuning" if used_in_logic_tuning(r) else "not_used_in_logic_tuning"),
    ("detector_and_logic", lambda r: "untouched" if (r["detector_leak"] == "leak_free"
                                                     and not used_in_logic_tuning(r)) else "touched"),
)


def stratify(rows):
    out = {}
    for name, key in STRATA:
        groups = {}
        for r in rows:
            groups.setdefault(key(r), []).append(r)
        out[name] = {k: summarize(v) for k, v in sorted(groups.items())}
    return out


# ---- Inputs.

def _load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def load_labelled_detections(raw_dir=RAW_LABELLED):
    """id -> detections from the 7 Oct batches. Ids seen twice must have identical boxes; the first copy is used."""
    first, duplicates = {}, []
    for f in sorted(glob.glob(str(Path(raw_dir) / "batch-*.json"))):
        rec = _load(f)
        resp = rec["response"]
        for view, i in rec["ids"].items():
            dets = resp["views"][view].get("detections") or []
            src = {"file": Path(f).relative_to(REPO).as_posix(), "view": view,
                   "model_id": resp.get("model", {}).get("model_id"), "mode": resp.get("processing", {}).get("mode")}
            if i in first:
                same = json.dumps(first[i][0], sort_keys=True) == json.dumps(dets, sort_keys=True)
                duplicates.append({"label_id": i, "used": first[i][1], "other": src, "identical_boxes": same})
                if not same:
                    raise ValueError(f"id {i} has different detections in {first[i][1]} and {src}")
                continue
            first[i] = (dets, src)
    return first, duplicates


def _iou(a, b):
    ax0, ax1, ay0, ay1 = a["x"] - a["width"] / 2, a["x"] + a["width"] / 2, a["y"] - a["height"] / 2, a["y"] + a["height"] / 2
    bx0, bx1, by0, by1 = b["x"] - b["width"] / 2, b["x"] + b["width"] / 2, b["y"] - b["height"] / 2, b["y"] + b["height"] / 2
    inter = max(0.0, min(ax1, bx1) - max(ax0, bx0)) * max(0.0, min(ay1, by1) - max(ay0, by0))
    union = a["width"] * a["height"] + b["width"] * b["height"] - inter
    return inter / union if union else 0.0


def box_settings_evidence(detection_lists):
    confs = [d["confidence"] for dets in detection_lists for d in dets]
    ious = [_iou(a, b) for dets in detection_lists for a, b in itertools.combinations(dets, 2)]
    return {"photos": len(detection_lists), "boxes": len(confs),
            "classes": sorted({d.get("class") for dets in detection_lists for d in dets}),
            "min_confidence": round(min(confs), 4) if confs else None,
            "boxes_below_0.35": sum(c < 0.35 for c in confs),
            "max_pairwise_iou": round(max(ious), 3) if ious else None,
            "pairs_iou_above_0.5": sum(i > 0.5 for i in ious),
            "photos_with_pair_iou_above_0.5": sum(
                any(_iou(a, b) > 0.5 for a, b in itertools.combinations(dets, 2)) for dets in detection_lists)}


def settings_check(labelled):
    lab = box_settings_evidence([d for d, _ in labelled.values()])
    lab["model_ids"] = sorted({s["model_id"] for _, s in labelled.values()})
    lab["modes"] = sorted({s["mode"] for _, s in labelled.values()})
    lists, requests, models = [], set(), set()
    for f in sorted(glob.glob(str(RAW_MUTAA / "*.json"))):
        d = _load(f)
        if f.endswith("-request.json"):
            requests.add((d.get("model"), d.get("confidence"), d.get("overlap"), d.get("classes"),
                          d.get("settings_source")))
        elif "views" in d:
            models.add(d.get("model", {}).get("model_id"))
            lists += [vd.get("detections") or [] for vd in d["views"].values()]
    mut = box_settings_evidence(lists)
    mut["model_ids"] = sorted(models)
    mut["request_metadata"] = [dict(zip(("model", "confidence", "overlap", "classes", "settings_source"), r))
                               for r in sorted(requests, key=str)]
    mut["note"] = "views include transport repeats (companion images re-sent with single images 13-15)"
    return {"field_labelled_20261007": lab, "mutaa_20260916": mut}


def detection_reproducibility(labelled):
    """Same photo, later staging runs: are the boxes identical to the 7 Oct production run?"""
    pairs = [
        (1, "reports/staging-block-20261008/scan-99block-walk2.json", "straight"),
        (32, "reports/staging-block-20261008/scan-99block-walk2.json", "right"),
        (19, "reports/staging-block-20261008/scan-mech-walk.json", "straight"),
        (30, "reports/staging-block-20261008/scan-mech-walk.json", "left"),
        (2, "reports/staging-block-20261008/scan-mech-walk.json", "right"),
        (50, "reports/field-scans-20261013/replay/f81c04d7-5fec-4d64-aa8c-54098abf2415.json", "left"),
    ]
    notes = {50: "not the same file: f81c04d7 LEFT is the app's 1600 px re-encode of img-50 (different JPEG bytes)"}
    out = []
    key = lambda d: (round(d["x"], 1), round(d["y"], 1), round(d["width"], 1), round(d["height"], 1))  # noqa: E731
    for i, path, view in pairs:
        a = labelled[i][0]
        b = _load(REPO / path)["views"][view].get("detections") or []
        out.append({"label_id": i, "later_response": path, "view": view, "boxes_7oct": len(a), "boxes_later": len(b),
                    "identical_boxes": sorted(map(key, a)) == sorted(map(key, b)), "note": notes.get(i)})
    return out


def warehouse4_detections():
    """warehouse image-4: 23 Sep production (upstream-2 right) vs 9 Oct staging (scan-99block-walk2 left)."""
    up = _load(REPO / "reports/warehouse-20260923/upstream-2.json")["views"]["right"]["detections"]
    st = _load(REPO / "reports/staging-block-20261008/scan-99block-walk2.json")["views"]["left"]
    key = lambda d: (round(d["x"], 1), round(d["y"], 1), round(d["width"], 1), round(d["height"], 1))  # noqa: E731
    return st["detections"], st["image"], {"boxes_23sep": len(up), "boxes_9oct": len(st["detections"]),
                                           "identical_boxes": sorted(map(key, up)) == sorted(map(key, st["detections"]))}


# ---- Sections.

def evaluate_photos(manifest, labelled):
    rows = []
    for p in manifest["photos"]:
        dets, src = labelled[p["label_id"]]
        pred = predict_face(dets, p["width"], p["height"])  # no label passed
        s = score_photo(pred["predicted_total"], p["label_value"], pred["outcome"])
        raw_err = pred["raw_boxes"] - p["label_value"]
        rows.append({
            "label_id": p["label_id"], "label": p["label_value"], "tier": p["tier"],
            "cluster": p["near_duplicate_cluster"], "group": p["group_id"], "detector_leak": p["detector_leak"],
            "v2_tag_split_today": p["v2_tag_split_today"], "in_gate_tuning_set": p["in_gate_tuning_set"],
            "in_walk_reference_photos": p["in_walk_reference_photos"],
            "in_walk_development_photos": p["in_walk_development_photos"],
            "in_orientation_development_photos": p["in_orientation_development_photos"],
            "size": size_band(p["label_value"]),
            "detections": src, **{k: v for k, v in pred.items() if k != "columns"},
            "walk_by_column": [c["walk_count"] for c in pred["columns"]],
            "span_by_column": [c["span_count"] for c in pred["columns"]],
            "recessed_by_column": [c["recessed"] for c in pred["columns"]],
            "columns": pred["columns"], **s,
            "raw_box_error": raw_err, "raw_box_exact": raw_err == 0,
        })
    return rows


def cluster_level(rows):
    """One row per near-duplicate cluster: representative = lowest label id; members must agree."""
    clusters = {}
    for r in rows:
        clusters.setdefault(r["cluster"], []).append(r)
    reps, table = [], []
    for cid, members in sorted(clusters.items(), key=lambda kv: min(m["label_id"] for m in kv[1])):
        members = sorted(members, key=lambda m: m["label_id"])
        agree = len({(m["result"], m["error"]) for m in members}) == 1
        reps.append(members[0])
        table.append({"cluster": cid, "group": members[0]["group"], "label_ids": [m["label_id"] for m in members],
                      "labels": [m["label"] for m in members], "predicted": [m["predicted_total"] for m in members],
                      "results": [m["result"] for m in members], "members_agree": agree,
                      "representative": members[0]["label_id"]})
    return reps, table


def block_level(rows):
    """One row per physical block (group): representative = lowest label id. Members may disagree (G03)."""
    blocks = {}
    for r in rows:
        blocks.setdefault(r["group"], []).append(r)
    reps, table = [], []
    for gid, members in sorted(blocks.items(), key=lambda kv: min(m["label_id"] for m in kv[1])):
        members = sorted(members, key=lambda m: m["label_id"])
        reps.append(members[0])
        table.append({"group": gid, "label_ids": [m["label_id"] for m in members],
                      "clusters": sorted({m["cluster"] for m in members}),
                      "results": [m["result"] for m in members],
                      "members_agree": len({(m["result"], m["error"]) for m in members}) == 1,
                      "representative": members[0]["label_id"]})
    return reps, table


def predict_not_usable(manifest, labelled):
    """Predictions for the labels the audit marks not usable at image level (no label passed)."""
    rows = []
    for p in manifest["not_usable"]:
        dets, src = labelled[p["label_id"]]
        pred = predict_face(dets, p["width"], p["height"])
        rows.append({"label_id": p["label_id"], "group": p["group_id"], "cluster": p["near_duplicate_cluster"],
                     "detections": src, "outcome": pred["outcome"], "predicted_total": pred["predicted_total"],
                     "walk_by_column": [c["walk_count"] for c in pred["columns"]],
                     "gate_reasons": pred["gate_reasons"], "flag_reasons": pred["flag_reasons"],
                     "raw_boxes": pred["raw_boxes"]})
    return rows


def score_not_usable(rows, manifest):
    """Secondary only: the written number is not a usable target here (scope unclear), so no exact rate."""
    by_id = {p["label_id"]: p for p in manifest["not_usable"]}
    for r in rows:
        p = by_id[r["label_id"]]
        r.update(label_written=p["label_value"], region_labels=p["region_labels"],
                 audit_reason_not_usable=p["audit_reason_not_usable"],
                 shown_minus_written=r["predicted_total"] - p["label_value"])
    accepted = [r for r in rows if r["outcome"] == "accepted"]
    return {"n": len(rows), "accepted": len(accepted),
            "accepted_ids": [r["label_id"] for r in accepted],
            "accepted_equal_to_written": sum(r["shown_minus_written"] == 0 for r in accepted),
            "withheld_gate": sum(r["outcome"] == "withheld_gate" for r in rows),
            "withheld_flagged": sum(r["outcome"] == "withheld_flagged" for r in rows),
            "rows": rows}


def evaluate_per_stack(manifest, labelled):
    out = []
    wh_dets, wh_image, wh_check = warehouse4_detections()
    for case in manifest["per_stack"]:
        det_src = case["detections"]
        if "batch" in det_src:
            rec = _load(REPO / det_src["batch"])
            dets = rec["response"]["views"][det_src["view"]]["detections"]
            width, height = case["image"]
            extra = {}
        else:
            dets, width, height = wh_dets, wh_image["width"], wh_image["height"]
            extra = {"detections_23sep_vs_9oct": wh_check}
        pred = predict_face(dets, width, height)
        cols = pred["columns"]
        if case.get("x_range"):
            lo, hi = case["x_range"]
            cols = [c for c in cols if lo <= (c["x_min"] + c["x_max"]) / 2 <= hi]
        stacks = case["stacks"]
        entry = {"case": case["case"], "physical_stack": case["physical_stack"], "truth_source": case["truth_source"],
                 "truth_kind": "user-reported, not physically recounted",
                 "walk_development_photo": case["walk_development_photo"], "detections": det_src,
                 "photo_outcome": pred["outcome"], "gate_reasons": pred["gate_reasons"],
                 "columns_in_scope": len(cols), "stacks": [], **extra}
        if len(cols) != len(stacks):
            entry["assignment"] = (f"{len(cols)} columns in scope for {len(stacks)} stacks: not assigned "
                                   "(no label-based choice)")
            entry["columns"] = [{k: c[k] for k in ("x_min", "x_max", "model_boxes", "span_count", "walk_count",
                                                   "reason")} for c in cols]
        else:
            for st, c in zip(stacks, cols):
                trays = st["filled"] + (st["empty"] or 0)
                entry["stacks"].append({
                    "position": st["position"], "user_filled": st["filled"], "user_empty": st["empty"],
                    "walk": c["walk_count"], "span": c["span_count"], "boxes": c["model_boxes"],
                    "walk_minus_filled": c["walk_count"] - st["filled"],
                    "walk_minus_all_trays": c["walk_count"] - trays,
                    "column_reason": c["reason"], "recessed": c["recessed"]})
        out.append(entry)
    return out


def per_stack_summary(entries):
    obs = [(e, s) for e in entries for s in e["stacks"]]
    shown = [(e, s) for e, s in obs if e["photo_outcome"] == "accepted" and not s["column_reason"]]
    return {"photos": len(entries), "stack_observations": len(obs),
            "physical_stacks": len({(e["physical_stack"], s["position"]) for e, s in obs}),
            "walk_equals_user_filled": sum(s["walk_minus_filled"] == 0 for _, s in obs),
            "within_1_of_user_filled": sum(abs(s["walk_minus_filled"]) <= 1 for _, s in obs),
            "accepted_observations": len(shown),
            "accepted_and_equal": sum(s["walk_minus_filled"] == 0 for _, s in shown),
            "accepted_physical_stacks": len({(e["physical_stack"], s["position"]) for e, s in shown}),
            "accepted_from_walk_development_photos": sum(e["walk_development_photo"] for e, _ in shown),
            "withheld_observations": len(obs) - len(shown),
            "unassigned_cases": sum("assignment" in e for e in entries)}


def _summ_block(block):
    if not block:
        return None
    return {"status": block.get("status"), "total_trays": block.get("total_trays"),
            "observed_trays": block.get("observed_trays"), "computed_trays": block.get("computed_trays"),
            "width": block.get("width"), "depth": block.get("depth"),
            "conflicts": len(block.get("conflicts") or []), "ambiguities": len(block.get("ambiguities") or []),
            "capture_refused": sorted(v for v, q in (block.get("capture") or {}).items() if not q["accepted"])}


def _cells(block):
    return sorted((c["x"], c["y"], c["status"], c["layers"]) for c in block.get("cells") or [])


def evaluate_multi_view(manifest):
    out = []
    for trio in manifest["multi_view"]:
        entries = []
        for rep in trio["replays"]:
            resp = _load(REPO / rep["path"])
            views = {v: {"detections": resp["views"][v].get("detections") or [], "image": resp["views"][v].get("image")}
                     for v in VIEWS}
            current = predict_block(views)
            saved = resp.get("block")
            cur = _summ_block(current)
            entry = {"path": rep["path"], "recorded": rep["recorded"], "saved": _summ_block(saved),
                     "saved_walk_by_view": {v: [c.get("walk_count") for c in resp["views"][v].get("stack_columns") or []]
                                            for v in VIEWS},
                     "current_318eb04": cur, "current_walk_by_view": current["walk_by_view"],
                     "current_conflict_reasons": [c.get("reason") for c in current["conflicts"]],
                     "current_ambiguities": current["ambiguities"],
                     "current_recommended_view": current["recommended_view"],
                     "exact_result_produced": cur["status"] == "exact",
                     "total_shown": cur["total_trays"] is not None}
            if "47cb2378" in rep["recorded"] and saved:
                entry["matches_live_47cb2378"] = (_summ_block(saved) == cur and _cells(saved) == _cells(current))
            entries.append(entry)
        out.append({k: trio[k] for k in ("trio", "r2_scans", "faces", "genuine", "expected")} | {"replays": entries})
    return out


# ---- Optional parity check against a Worker build (node). The module must be the transpiled index.ts.

JS_HARNESS = r"""
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [modPath, casesPath] = process.argv.slice(2);
const worker = (await import(pathToFileURL(modPath).href)).default;
const cases = JSON.parse(readFileSync(casesPath, "utf8"));
const env = { MODEL_ID: "projec-mutta/2", CONFIDENCE: "35", OVERLAP: "50", MAX_VIEW_COUNT_RATIO: "1.25",
  EGGS_PER_TRAY: "30", ROBOFLOW_API_KEY: "offline" };
console.log = () => {}; console.error = () => {};
const out = [];
for (const c of cases) {
  const queue = ["left", "right", "straight"].map(v => c.views[v]);
  globalThis.fetch = async () => { const v = queue.shift();
    return new Response(JSON.stringify({ predictions: v.detections, ...(v.image ? { image: v.image } : {}) }),
      { status: 200, headers: { "content-type": "application/json" } }); };
  const form = new FormData();
  form.set("scan_id", "00000000-0000-4000-8000-000000000000");
  form.set("scan_contract", "model_spatial_v1");
  ["left", "right", "straight"].forEach((v, i) =>
    form.set(v, new File([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, i])], v + ".jpg", { type: "image/jpeg" })));
  const res = await worker.fetch(new Request("https://offline.invalid/v1/scans/count", { method: "POST", body: form }), env);
  out.push({ name: c.name, http: res.status, body: await res.json() });
}
process.stdout.write(JSON.stringify(out));
"""


def _run_js(module_path, cases):
    with tempfile.TemporaryDirectory() as tmp:
        harness, case_file = Path(tmp) / "harness.mjs", Path(tmp) / "cases.json"
        harness.write_text(JS_HARNESS, encoding="utf-8")
        case_file.write_text(json.dumps(cases), encoding="utf-8")
        proc = subprocess.run(["node", str(harness), str(Path(module_path).resolve()), str(case_file)],
                              capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(proc.stdout)


def _replay_views(path):
    resp = _load(REPO / path)
    return {v: {"detections": resp["views"][v].get("detections") or [], "image": resp["views"][v].get("image")}
            for v in VIEWS}


def js_old_worker(module_path, manifest):
    """Multi-view replays through an older Worker build (e.g. 1e8591e, the pre-0.4.11 code on staging f5776f0d)."""
    cases = [{"name": rep["path"], "views": _replay_views(rep["path"])}
             for trio in manifest["multi_view"] for rep in trio["replays"]]
    out = {}
    for r in _run_js(module_path, cases):
        block = r["body"]["block"]
        saved = _load(REPO / r["name"]).get("block")
        out[r["name"]] = {"block": _summ_block(block), "fully_observed": block.get("fully_observed"),
                          "reproduces_saved": (_summ_block(block) == _summ_block(saved) and _cells(block) == _cells(saved))
                          if saved else None}
    return {"module": Path(module_path).name, "replays": out}


def js_parity(module_path, manifest, labelled):
    """Run the Worker's own request path with Roboflow mocked by the saved detections; compare with Python."""
    cases, expect = [], {}
    for p in manifest["photos"]:
        dets = labelled[p["label_id"]][0]
        img = {"width": p["width"], "height": p["height"]}
        cases.append({"name": f"photo-{p['label_id']}", "views": {v: {"detections": dets, "image": img} for v in VIEWS}})
        expect[f"photo-{p['label_id']}"] = ("face", dets, img)
    for trio in manifest["multi_view"]:
        for rep in trio["replays"]:
            views = _replay_views(rep["path"])
            cases.append({"name": rep["path"], "views": views})
            expect[rep["path"]] = ("block", views, None)
    results = _run_js(module_path, cases)
    mismatches, checked = [], 0
    for r in results:
        kind, a, b = expect[r["name"]]
        body = r["body"]
        if kind == "face":
            pred = predict_face(a, b["width"], b["height"])
            js_cols = body["views"]["straight"]["stack_columns"]
            py_cols = count_layers_by_span(_boxes(a))
            js_cap = body["block"]["capture"]["straight"]
            # The same photo in all three slots: the block's conflicts carry every column's retake reason.
            py_block = predict_block({v: {"detections": a, "image": b} for v in VIEWS})
            same = (js_cap["accepted"] == pred["gate_accepted"] and js_cap["reasons"] == pred["gate_reasons"]
                    and js_cap["metrics"] == pred["gate_metrics"]
                    and [(c["walk_count"], c["span_count"], c["pitch_px"], c["x_min"], c["x_max"]) for c in js_cols]
                    == [(c["walk_count"], c["span_count"], c["pitch_px"], c["x_min"], c["x_max"]) for c in py_cols]
                    and [c.get("reason") for c in body["block"]["conflicts"]]
                    == [c.get("reason") for c in py_block["conflicts"]]
                    and _cells(body["block"]) == _cells(py_block))
        else:
            cur = predict_block(a)
            js_block = body["block"]
            same = (_summ_block(js_block) == _summ_block(cur) and _cells(js_block) == _cells(cur)
                    and [c.get("reason") for c in js_block["conflicts"]] == [c.get("reason") for c in cur["conflicts"]])
        checked += 1
        if not same or r["http"] != 200:
            mismatches.append(r["name"])
    return {"module": Path(module_path).name, "cases": checked, "mismatches": mismatches}


# ---- Output.

CSV_FIELDS = ["label_id", "label", "tier", "cluster", "group", "detector_leak", "v2_tag_split_today",
              "in_gate_tuning_set", "in_walk_reference_photos", "in_walk_development_photos",
              "in_orientation_development_photos", "size", "raw_boxes",
              "boxes_in_columns",
              "walk_by_column", "span_by_column", "recessed_by_column", "predicted_total",
              "predicted_total_without_recessed", "span_total", "gate_accepted", "gate_reasons", "flagged_columns",
              "flag_reasons", "recessed_columns", "outcome", "result", "error", "abs_error", "raw_box_error"]


def write_csv(rows, path):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: (json.dumps(r[k], ensure_ascii=False) if isinstance(r[k], (list, dict)) else r[k])
                        for k in CSV_FIELDS})


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(OUT_DIR))
    ap.add_argument("--js-parity", help="transpiled Worker index.ts (e.g. git show 318eb04:...) to compare with")
    ap.add_argument("--js-old-worker", help="transpiled older Worker index.ts (e.g. 1e8591e) for the multi-view "
                                            "before/after comparison")
    args = ap.parse_args(argv)
    manifest = _load(MANIFEST)
    labelled, duplicates = load_labelled_detections()
    rows = evaluate_photos(manifest, labelled)
    reps, cluster_table = cluster_level(rows)
    block_reps, block_table = block_level(rows)
    not_usable = score_not_usable(predict_not_usable(manifest, labelled), manifest)
    raw_rows = [{"result": "accepted_correct" if r["raw_box_exact"] else "accepted_wrong", "accepted": True,
                 "error": r["raw_box_error"], "abs_error": abs(r["raw_box_error"]),
                 "would_be_exact": r["raw_box_exact"]} for r in reps]
    results = {
        "logic": "Worker 318eb04 = staging 47cb2378 (layer_span.py, block_model.py _face, captureQuality port); "
                 "rim verification off (RIM_VERIFY unset on staging)",
        "inputs": {"detections": "reports/field-labelled-20261007/raw/batch-*.json",
                   "manifest": (Path(MANIFEST).relative_to(REPO) if Path(MANIFEST).is_relative_to(REPO)
                                else Path(MANIFEST)).as_posix()},
        "detection_duplicates": duplicates,
        "settings_check": settings_check(labelled),
        "detection_reproducibility": detection_reproducibility(labelled),
        "summary_labels": stratify(rows),
        "summary_clusters": stratify(reps),
        "summary_blocks": stratify(block_reps),
        "raw_v2_box_count_clusters": summarize(raw_rows),
        "clusters": cluster_table,
        "blocks": block_table,
        "photos": rows,
        "not_usable_secondary": not_usable,
        "per_stack": evaluate_per_stack(manifest, labelled),
        "per_stack_summary": None,
        "multi_view": evaluate_multi_view(manifest),
        "multi_view_not_replayed": manifest["multi_view_not_replayed"],
    }
    results["per_stack_summary"] = per_stack_summary(results["per_stack"])
    if args.js_parity:
        results["js_parity"] = js_parity(args.js_parity, manifest, labelled)
    if args.js_old_worker:
        old = js_old_worker(args.js_old_worker, manifest)
        results["old_worker"] = {"module": old["module"]}
        for trio in results["multi_view"]:
            for rep in trio["replays"]:
                rep["old_worker"] = old["replays"][rep["path"]]
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    write_csv(rows, out / "results.csv")
    s = results["summary_clusters"]["all"]["all"]
    print(f"clusters n={s['n']}: accepted {s['accepted']} (correct {s['accepted_correct']}, wrong {s['accepted_wrong']}), "
          f"withheld {s['withheld']} (gate {s['withheld_gate']}, flagged {s['withheld_flagged']}); "
          f"MAE all {s['mae_all']}, accepted {s['mae_accepted']}")
    b = results["summary_blocks"]["all"]["all"]
    print(f"blocks n={b['n']}: accepted {b['accepted']} (correct {b['accepted_correct']}, wrong {b['accepted_wrong']}); "
          f"not usable n={not_usable['n']}: accepted {not_usable['accepted_ids']}")
    if "js_parity" in results:
        print("js parity:", results["js_parity"])
    return results


if __name__ == "__main__":
    main()
