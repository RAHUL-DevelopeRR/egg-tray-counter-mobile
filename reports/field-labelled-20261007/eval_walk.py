"""Compare span count vs walk count against the per-stack references (53 resolved stacks)."""
import csv, json, sys
sys.path.insert(0, "backend")
from pathlib import Path
from app.vision.layer_span import count_layers_by_span
R = Path("reports/field-labelled-20261007"); dets = {}
for f in sorted((R / "raw").glob("batch-*.json")):
    rec = json.load(open(f))
    for view, i in rec["ids"].items(): dets[i] = rec["response"]["views"][view]["detections"]
refs = [r for r in csv.DictReader(open(R / "per_stack_counts.csv")) if r["assistant_count"]]
stats = {"span": [0, 0], "walk": [0, 0]}; rows = []; n = 0
for r in refs:
    cols = count_layers_by_span(dets[int(r["image"])]); c = cols[int(r["col"]) - 1]; ref = int(r["assistant_count"]); n += 1
    for k in ("span", "walk"):
        d = abs(c[f"{k}_count"] - ref); stats[k][0] += d == 0; stats[k][1] += d <= 1
    rows.append((r["image"], r["col"], ref, c["span_count"], c["walk_count"], c["perspective_gradient"]))
print(f"n={n}  span exact {stats['span'][0]} within1 {stats['span'][1]}  |  walk exact {stats['walk'][0]} within1 {stats['walk'][1]}")
print("image col ref span walk gradient  (rows where they differ or either is wrong)")
for row in rows:
    if row[3] != row[4] or row[3] != row[2] or row[4] != row[2]: print(*row)
