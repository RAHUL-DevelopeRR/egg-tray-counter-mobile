"""Score archived V2 detection counts against the user's handwritten labels."""
import csv, json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).parent
labels = {int(r["id"]): r for r in csv.DictReader(open("datasets/field-2026-10/labelled-20261007/labels.csv"))}
pred = {}
for f in sorted((ROOT / "raw").glob("batch-*.json")):
    rec = json.load(open(f))
    for view, i in rec["ids"].items():
        c = len(rec["response"]["views"][view].get("detections") or [])
        if i in pred and pred[i] != c:
            raise SystemExit(f"non-repeatable count for {i}: {pred[i]} vs {c}")
        pred[i] = c
rows = []
for i, l in sorted(labels.items()):
    t, p = int(l["label_total"]), pred[i]
    rows.append({"id": i, "scene_type": l["scene_type"], "material": l["tray_material"],
                 "label": t, "v2": p, "error": p - t, "abs_error": abs(p - t),
                 "pct_error": round(100 * (p - t) / t, 1), "exact": p == t})
with open(ROOT / "results.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)

def summary(group):
    n = len(group)
    return {"n": n, "exact": sum(r["exact"] for r in group),
            "within_2": sum(r["abs_error"] <= 2 for r in group),
            "within_5pct": sum(abs(r["pct_error"]) <= 5 for r in group),
            "mae": round(sum(r["abs_error"] for r in group) / n, 1),
            "mean_signed": round(sum(r["error"] for r in group) / n, 1),
            "label_sum": sum(r["label"] for r in group), "v2_sum": sum(r["v2"] for r in group)}
out = {"all": summary(rows)}
for key in ("scene_type", "material"):
    g = defaultdict(list)
    for r in rows: g[r[key]].append(r)
    for k, v in sorted(g.items()): out[f"{key}={k}"] = summary(v)
json.dump(out, open(ROOT / "summary.json", "w"), indent=1)
for k, v in out.items(): print(f"{k:32s}", v)
print()
for r in rows: print(r["id"], r["scene_type"], r["material"], r["label"], r["v2"], r["error"], f'{r["pct_error"]}%')
