"""Replay the Worker's captureQuality gate (index.ts:503-560) in Python on the 39 tagged labelled
photos using the archived V2 detections (reports/field-labelled-20261007/raw/batch-*.json), then
re-score with the width coverage judged against the frame's SHORT side instead of its width.

Run from backend/ with PYTHONPATH="../work/vision-deps;." so app.vision.layer_span imports.
"""
from __future__ import annotations

import csv
import json
import statistics as st
from pathlib import Path

from PIL import Image

from app.vision.layer_span import count_layers_by_span

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "reports/field-labelled-20261007/raw"
ORIG = ROOT / "datasets/field-2026-10/labelled-20261007/originals"
GATE = dict(max_pitch_gradient=1.2, min_coverage_x=0.45, min_coverage_single=0.25, min_height_frac=0.4, recess_floor=0.6)
RECESS_SCALE = 0.85


def median(v):
    return st.median(v)


def capture_quality(columns, w, h, short_side=False):
    """Port of captureQuality. short_side=True divides the covered width by min(w, h)."""
    if not columns:
        return False, ["no stacks detected"], {}
    ordered = sorted(columns, key=lambda c: c["x_min"])
    pitches = [c["pitch_px"] for c in ordered]
    face_median = median(pitches)
    reference = median([p for p in pitches if p >= face_median])
    scales = [p / reference if reference else 1 for p in pitches]
    recessed = [i for i, s in enumerate(scales) if s < RECESS_SCALE]
    grad_cols = [c for i, c in enumerate(ordered) if i != recessed[0]] if len(recessed) == 1 and scales[recessed[0]] >= GATE["recess_floor"] else ordered
    k = max(1, -(-len(grad_cols) // 3))
    head = median([c["pitch_px"] for c in grad_cols[:k]])
    tail = median([c["pitch_px"] for c in grad_cols[-k:]])
    gradient = max(head / tail, tail / head) if len(grad_cols) >= 2 and head > 0 and tail > 0 else 1
    covered, span = 0, None
    for c in ordered:
        if span and c["x_min"] <= span[1]:
            span[1] = max(span[1], c["x_max"])
        else:
            if span:
                covered += span[1] - span[0]
            span = [c["x_min"], c["x_max"]]
    if span:
        covered += span[1] - span[0]
    denom = min(w, h) if short_side else w
    coverage = covered / denom
    height_frac = max(c["y_last"] - c["y_first"] + c["pitch_px"] for c in ordered) / h
    reasons = []
    if gradient > GATE["max_pitch_gradient"]:
        reasons.append("pitch gradient")
    min_cov = GATE["min_coverage_single"] if len(ordered) == 1 else GATE["min_coverage_x"]
    if coverage < min_cov:
        reasons.append("coverage")
    if height_frac < GATE["min_height_frac"]:
        reasons.append("height")
    return not reasons, reasons, dict(columns=len(ordered), coverage=round(coverage, 3), height_frac=round(height_frac, 3), gradient=round(gradient, 3), aspect=round(w / h, 2))


def main():
    tags = {int(r["id"]): r["capture"] for r in csv.DictReader(open(ROOT / "reports/field-labelled-20261007/capture_tags.csv"))}
    labels = {int(r["id"]): r["file"] for r in csv.DictReader(open(ROOT / "datasets/field-2026-10/labelled-20261007/labels.csv"))}
    dets = {}
    for f in sorted(RAW.glob("batch-*.json")):
        d = json.load(open(f))
        for view, iid in d["ids"].items():
            dets.setdefault(iid, d["response"]["views"][view]["detections"])
    rows = []
    tally = {}
    for iid, tag in sorted(tags.items()):
        im = Image.open(ORIG / labels[iid])
        w, h = im.size
        cols = count_layers_by_span(dets[iid])
        acc, reasons, m = capture_quality(cols, w, h)
        acc2, reasons2, m2 = capture_quality(cols, w, h, short_side=True)
        rows.append((iid, tag, f"{w}x{h}", m.get("aspect"), acc, reasons, m.get("coverage"), acc2, reasons2, m2.get("coverage"), m.get("height_frac")))
        t = tally.setdefault(tag, {"n": 0, "accepted_now": 0, "accepted_short": 0})
        t["n"] += 1
        t["accepted_now"] += acc
        t["accepted_short"] += acc2
    print("id  tag               size       w/h   now   reasons_now                 cov_w   short  reasons_short              cov_min  hf")
    for r in rows:
        print(f"{r[0]:2d}  {r[1]:16s}  {r[2]:9s} {str(r[3]):5}  {str(r[4]):5s} {','.join(r[5]) or '-':26s} {str(r[6]):6}  {str(r[7]):5s}  {','.join(r[8]) or '-':26s} {str(r[9]):6}  {r[10]}")
    print(json.dumps(tally, indent=1))


if __name__ == "__main__":
    main()
