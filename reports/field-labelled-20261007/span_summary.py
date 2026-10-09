"""Summarise span counts against the per-stack assessments in per_stack_counts.csv."""
import csv
from collections import Counter
rows = list(csv.DictReader(open("reports/field-labelled-20261007/per_stack_counts.csv")))
resolved = [r for r in rows if r["assistant_count"]]
def stats(key):
    exact = sum(int(r[key]) == int(r["assistant_count"]) for r in resolved)
    within1 = sum(abs(int(r[key]) - int(r["assistant_count"])) <= 1 for r in resolved)
    return exact, within1
n = len(resolved)
print("resolved columns:", n, "(scenes:", len({r["image"] for r in resolved}), ")")
for key in ("model_boxes", "span_count"):
    e, w = stats(key); print(f"{key:12s} exact {e}/{n} ({100*e/n:.0f}%)  within ±1 {w}/{n}")
print("unresolved columns:", Counter(r["image"] for r in rows if not r["assistant_count"]))
