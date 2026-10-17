"""Evaluate the sideways-photo guard on the 39 tagged photos and on every measured variant."""
import csv, json, statistics as st, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gate_replay import capture_quality
from app.vision.layer_span import count_layers_by_span
ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "reports/field-labelled-20261007/raw"; ORIG = ROOT / "datasets/field-2026-10/labelled-20261007/originals"
tags = {int(r["id"]): r["capture"] for r in csv.DictReader(open(ROOT / "reports/field-labelled-20261007/capture_tags.csv"))}
labels = {int(r["id"]): r["file"] for r in csv.DictReader(open(ROOT / "datasets/field-2026-10/labelled-20261007/labels.csv"))}
dets = {}
for f in sorted(RAW.glob("batch-*.json")):
    d = json.load(open(f))
    for view, iid in d["ids"].items(): dets.setdefault(iid, d["response"]["views"][view]["detections"])
def shape(d):
    if not d: return None, None
    return st.median(x["width"] / x["height"] for x in d), st.mean(x.get("confidence", 0) for x in d)
rules = {
  "aspect<2.75": lambda a, c: a is not None and a < 2.75,
  "aspect<3.0&conf<0.65": lambda a, c: a is not None and a < 3.0 and c < 0.65,
  "aspect<2.5|conf<0.6": lambda a, c: a is not None and (a < 2.5 or c < 0.6),
}
rows = []
for iid, tag in sorted(tags.items()):
    a, c = shape(dets[iid])
    acc, reasons, m = capture_quality(count_layers_by_span(dets[iid]), *Image.open(ORIG / labels[iid]).size)
    rows.append((f"tagged-{iid}", tag, a, c, len(dets[iid]), acc))
print("tagged photos: lowest aspect", sorted([(r[0], r[1], round(r[2], 2), round(r[3], 3)) for r in rows if r[2]], key=lambda r: r[2])[:6])
print("tagged photos: lowest confidence", sorted([(r[0], r[1], round(r[2], 2), round(r[3], 3)) for r in rows if r[3]], key=lambda r: r[3])[:6])
for name, rule in rules.items():
    hits = [(r[0], r[1], r[5]) for r in rows if rule(r[2], r[3])]
    print(f"{name:24s} would reject {len(hits)} tagged photos: {hits}")
# measured variants: per-view detections from the staging responses
seen = {}
for line in (ROOT / "work/scratch-landscape/worker/results.jsonl").read_text().splitlines():
    r = json.loads(line)
    seen[f"{r['base']}-{r['variant']}"] = r
resp_dir = ROOT / "work/scratch-landscape/worker/responses"
print("\nvariant              aspect  conf   boxes accepted  " + "  ".join(rules))
for k, r in seen.items():
    j = json.load(open(resp_dir / f"{r['scan_id']}.json"))
    d = j["response"]["views"][r["slot"]]["detections"]
    a, c = shape(d)
    flags = ["REJECT" if rule(a, c) else "-" for rule in rules.values()]
    sideways = r["variant"] in ("b90", "b270")
    print(f"{k:20s} {a if a is None else round(a,2)!s:7s} {c if c is None else round(c,3)!s:6s} {len(d):5d} {str(r['accepted']):8s} " + "  ".join(f"{x:>{len(n)}s}" for x, n in zip(flags, rules)) + ("   <- sideways" if sideways else ""))
