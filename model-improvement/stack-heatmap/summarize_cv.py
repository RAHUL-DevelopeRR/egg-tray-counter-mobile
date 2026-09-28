"""Aggregate grouped development results without summing views as inventory."""
import argparse
import json
from pathlib import Path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("folder", type=Path); args = parser.parse_args()
    runs = [json.loads(path.read_text()) for path in sorted(args.folder.glob("fold-*/run.json"))]
    if len(runs) < 2:
        raise ValueError("At least two independent group folds required")
    rows = []
    hashes = {r["config"]["manifest_sha256"] for r in runs}
    if len(hashes) != 1: raise ValueError("Different manifests cannot be one controlled comparison")
    for run in runs:
        if set(run["train_scene_ids"]) & set(run["validation_scene_ids"]):
            raise ValueError("Scene leakage in a fold")
        if run["evaluation_scope"] != "development_validation":
            raise ValueError("Training fit cannot enter cross-validation statistics")
        rows += [{k: v for k, v in row.items() if k not in ("probabilities", "peaks")} for row in run["metrics"]["rows"]]
    if len({r["id"] for r in rows}) != len(rows): raise ValueError("A face appears in multiple held-out folds")
    summary = {"scope": "tiny_grouped_development_not_physical_acceptance", "folds": len(runs),
               "stacks": len(rows), "per_stack_exact": sum(r["signed_error"] == 0 for r in rows),
               "group_exact": sum(r["metrics"]["scene_exact"] for r in runs),
               "mae": sum(abs(r["signed_error"]) for r in rows) / len(rows),
               "mean_signed_error": sum(r["signed_error"] for r in rows) / len(rows),
               "missed_layers": sum(r["missed_layers"] for r in rows),
               "duplicate_or_spurious_layers": sum(r["duplicate_or_spurious_layers"] for r in rows),
               "latency_ms_per_stack": sum(r["latency_ms"] for r in rows) / len(rows),
               "false_accepted_count": 0, "rejection_rate": 1., "accepted_scan_accuracy": None,
               "manifest_sha256": next(iter(hashes)), "rows": rows}
    (args.folder / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
