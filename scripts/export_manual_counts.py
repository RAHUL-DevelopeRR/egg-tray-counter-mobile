"""Write the master CSV of every manual count recorded in the app.

Pulls GET /v1/manual-counts from the staging Worker (each scan's latest
manual count: block id, per-stack app layers and the operator's filled/empty
count) and writes one row per stack plus a per-block summary.

Usage (repo root):
  python scripts/export_manual_counts.py --out reports/field-test-20261009
"""

from __future__ import annotations

import argparse
import csv
import json
import urllib.request
from pathlib import Path

STAGING = "https://egg-tray-counter-api-staging.rahultech72216.workers.dev"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default=STAGING)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(f"{args.url}/v1/manual-counts", headers={"User-Agent": "egg-tray-tools/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = json.load(response)
    records = sorted(payload["records"], key=lambda r: r.get("recorded_at", ""))
    (out / "manual_counts.json").write_text(json.dumps(records, indent=1), encoding="utf-8")
    stack_rows, block_rows = [], []
    for rec in records:
        manual_total = sum(c["filled"] + c["empty"] for c in rec["cells"] if not c.get("unreachable"))
        block_rows.append({
            "recorded_at": rec.get("recorded_at"), "block_id": rec["block_id"], "scan_id": rec["scan_id"],
            "stacks": len(rec["cells"]), "unreachable_stacks": sum(1 for c in rec["cells"] if c.get("unreachable")),
            "app_total": rec.get("app_total"), "manual_filled": rec["totals"]["filled"],
            "manual_empty": rec["totals"]["empty"], "manual_total_reachable": manual_total,
            "diff_app_minus_manual": (rec["app_total"] - manual_total) if rec.get("app_total") is not None else "",
            "app_version": rec.get("app_version"), "notes": rec.get("notes", ""),
        })
        for c in rec["cells"]:
            stack_rows.append({
                "recorded_at": rec.get("recorded_at"), "block_id": rec["block_id"], "scan_id": rec["scan_id"],
                "x": c["x"], "y": c["y"], "app_status": c.get("app_status"), "app_layers": c.get("app_layers"),
                "manual_filled": c["filled"], "manual_empty": c["empty"], "unreachable": c.get("unreachable", False),
                "diff_app_minus_manual": (c["app_layers"] - c["filled"] - c["empty"]) if c.get("app_layers") is not None and not c.get("unreachable") else "",
            })
    for name, rows in (("manual_counts_per_stack.csv", stack_rows), ("manual_counts_per_block.csv", block_rows)):
        with open(out / name, "w", newline="", encoding="utf-8") as f:
            if rows:
                w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
                w.writeheader()
                w.writerows(rows)
    print(f"{len(records)} manual counts, {len(stack_rows)} stack rows -> {out}")
    for b in block_rows:
        print(f"  {b['block_id']:<12} app {b['app_total']!s:>5}  manual {b['manual_total_reachable']:>5}  stacks {b['stacks']}")


if __name__ == "__main__":
    main()
