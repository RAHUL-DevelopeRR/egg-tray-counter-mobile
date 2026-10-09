"""Score field-test blocks: app block count vs the operator's in-app manual count.

Inputs: scan ids, taken from the app's "COPY ALL COUNTS AS CSV" export
(scan_id column) or given on the command line. For each scan the script
fetches scans/<id>/manual-count/latest.json from R2 with wrangler (needs the
Cloudflare login used for deployment) and scores:

- per stack: app layers vs manual filled+empty, exact / within 1 / worse,
  split by cell status (observed vs computed);
- per block: app total vs manual total (skipped when the app withheld a total);
- rescan rate: blocks where the app withheld the total;
- interior assumption: computed cells vs the counted interior, where reachable.

Usage (from the repository root):
  python scripts/score_field_blocks.py --csv counts-from-app.csv --out reports/field-test-<date>
  python scripts/score_field_blocks.py --scan <uuid> [--scan <uuid> ...] --out ...
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from collections import Counter
from pathlib import Path

BUCKET = "egg-tray-scan-archive"


def fetch_latest(scan_id: str, out_dir: Path) -> dict | None:
    target = out_dir / f"{scan_id}.json"
    if not target.exists():
        result = subprocess.run(
            ["npx", "wrangler", "r2", "object", "get", f"{BUCKET}/scans/{scan_id}/manual-count/latest.json",
             "--remote", "--file", str(target.resolve())],
            cwd="cloudflare-worker", capture_output=True, text=True, shell=True,
        )
        if result.returncode != 0 or not target.exists():
            print(f"  {scan_id}: no manual count found ({result.stderr.strip()[:120]})")
            return None
    return json.loads(target.read_text(encoding="utf-8"))


def score(records: list[dict]) -> dict:
    stacks = Counter()
    blocks = {"n": 0, "with_total": 0, "exact": 0, "within_2": 0, "abs_err_sum": 0, "withheld": 0}
    interior = Counter()
    rows = []
    for rec in records:
        app_total = rec.get("app_total")
        manual_total = sum(c["filled"] + c["empty"] for c in rec["cells"] if not c.get("unreachable"))
        blocks["n"] += 1
        if app_total is None:
            blocks["withheld"] += 1
        else:
            blocks["with_total"] += 1
            err = abs(app_total - manual_total)
            blocks["abs_err_sum"] += err
            blocks["exact"] += err == 0
            blocks["within_2"] += err <= 2
        for c in rec["cells"]:
            if c.get("unreachable") or c.get("app_layers") is None:
                continue
            manual = c["filled"] + c["empty"]
            diff = abs(c["app_layers"] - manual)
            bucket = "observed" if c.get("app_status") == "observed" else "computed"
            stacks[(bucket, "n")] += 1
            stacks[(bucket, "exact")] += diff == 0
            stacks[(bucket, "within_1")] += diff <= 1
            if bucket == "computed":
                interior["n"] += 1
                interior["exact"] += diff == 0
            rows.append({"scan_id": rec["scan_id"], "block_id": rec["block_id"], "x": c["x"], "y": c["y"],
                         "status": c.get("app_status"), "app_layers": c["app_layers"], "manual_filled": c["filled"],
                         "manual_empty": c["empty"], "diff": c["app_layers"] - manual})
    def pct(a, b):
        return round(100 * a / b, 1) if b else None
    summary = {
        "blocks": {**blocks, "mae_when_total": round(blocks["abs_err_sum"] / blocks["with_total"], 2) if blocks["with_total"] else None,
                   "rescan_rate_pct": pct(blocks["withheld"], blocks["n"])},
        "stacks": {b: {"n": stacks[(b, "n")], "exact_pct": pct(stacks[(b, "exact")], stacks[(b, "n")]),
                       "within_1_pct": pct(stacks[(b, "within_1")], stacks[(b, "n")])} for b in ("observed", "computed")},
        "interior_assumption": {"n": interior["n"], "exact_pct": pct(interior["exact"], interior["n"])},
    }
    return {"summary": summary, "rows": rows}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", help="CSV copied from the app (needs a scan_id column)")
    ap.add_argument("--scan", action="append", default=[], help="scan id (repeatable)")
    ap.add_argument("--out", required=True, help="output directory for fetched records and scores")
    args = ap.parse_args()
    out = Path(args.out); (out / "manual-counts").mkdir(parents=True, exist_ok=True)
    ids = list(dict.fromkeys(args.scan))
    if args.csv:
        with open(args.csv, newline="", encoding="utf-8-sig") as f:
            ids += [r["scan_id"] for r in csv.DictReader(f) if r.get("scan_id")]
        ids = list(dict.fromkeys(ids))
    records = [r for r in (fetch_latest(i, out / "manual-counts") for i in ids) if r]
    result = score(records)
    (out / "scores.json").write_text(json.dumps(result["summary"], indent=1), encoding="utf-8")
    with open(out / "per_stack.csv", "w", newline="", encoding="utf-8") as f:
        if result["rows"]:
            w = csv.DictWriter(f, fieldnames=result["rows"][0].keys()); w.writeheader(); w.writerows(result["rows"])
    print(json.dumps(result["summary"], indent=1))
    print(f"{len(records)} blocks scored; details in {out}")


if __name__ == "__main__":
    main()
