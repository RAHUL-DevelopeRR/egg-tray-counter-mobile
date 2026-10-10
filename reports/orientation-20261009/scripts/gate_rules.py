"""Offline evaluation of two candidate gate rules on the 39 tagged photos (V2 detections) and on the
landscape variants measured today: (1) waive the width-coverage test when height_frac >= 0.8;
(2) reject when the median detection width/height < 3.5 (sideways / garbage boxes)."""
import csv, json, statistics as st, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gate_replay import capture_quality, GATE
from app.vision.layer_span import count_layers_by_span
ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "reports/field-labelled-20261007/raw"; ORIG = ROOT / "datasets/field-2026-10/labelled-20261007/originals"
tags = {int(r["id"]): r["capture"] for r in csv.DictReader(open(ROOT / "reports/field-labelled-20261007/capture_tags.csv"))}
labels = {int(r["id"]): r["file"] for r in csv.DictReader(open(ROOT / "datasets/field-2026-10/labelled-20261007/labels.csv"))}
dets = {}
for f in sorted(RAW.glob("batch-*.json")):
    d = json.load(open(f))
    for view, iid in d["ids"].items(): dets.setdefault(iid, d["response"]["views"][view]["detections"])
def verdict(cols, w, h, waiver):
    acc, reasons, m = capture_quality(cols, w, h)
    if waiver and "coverage" in reasons and m.get("height_frac", 0) >= 0.8:
        reasons = [r for r in reasons if r != "coverage"]; acc = not reasons
    return acc, reasons, m
tally = {}; aspects = []
for iid, tag in sorted(tags.items()):
    w, h = Image.open(ORIG / labels[iid]).size
    cols = count_layers_by_span(dets[iid])
    a0, r0, m = verdict(cols, w, h, False); a1, r1, _ = verdict(cols, w, h, True)
    d = dets[iid]
    asp = st.median(x["width"] / x["height"] for x in d) if d else None
    aspects.append((iid, tag, round(asp, 2) if asp else None, len(d), round(m.get("coverage") or 0, 3), m.get("height_frac")))
    t = tally.setdefault(tag, {"n": 0, "now": 0, "waiver": 0}); t["n"] += 1; t["now"] += a0; t["waiver"] += a1
    if a0 != a1: print("flip", iid, tag, r0, "->", r1, m)
print("tagged photos, current rule vs height-fill waiver:", json.dumps(tally))
print("median box aspect (w/h) on the 39 tagged photos: min", min(a for _, _, a, *_ in aspects if a), "max", max(a for _, _, a, *_ in aspects if a))
print("lowest five:", sorted([a for a in aspects if a[2]], key=lambda a: a[2])[:5])
# today's landscape variants
rows = [json.loads(l) for l in (ROOT / "work/scratch-landscape/worker/results.jsonl").read_text().splitlines()]
seen = set()
print("\nvariant           cov    hf     now     waiver")
for r in rows:
    k = f"{r['base']}-{r['variant']}"
    if k in seen or r["variant"] not in ("cpad", "cpad95", "ccrop", "orig"): continue
    seen.add(k)
    cov, hf = r["coverage_x"], r["height_frac"]
    now = r["accepted"]
    waived = now or (r["reasons"] == ["stacks cover too little of the frame width"] and hf is not None and hf >= 0.8)
    print(f"{k:17s} {cov:<6} {hf:<6} {str(now):7s} {waived}")
