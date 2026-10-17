"""Score field-test blocks: app block count vs the operator's in-app manual count.

Inputs: scan ids, taken from the app's "COPY ALL COUNTS AS CSV" export
(scan_id column) or given on the command line. For each scan the script
reads the latest manual count and scores:

- per stack: app layers vs manual filled+empty, exact / within 1 / worse,
  split by cell status (observed vs computed);
- per block: app total vs manual total, only where the record says what the app
  showed (app_total known);
- rescan rate: blocks where the app withheld the total, among blocks whose app
  result is known;
- interior assumption: computed cells vs the counted interior, where reachable.

app_total is "unknown" (not "withheld") when the stored record does not say:
records stored before 0.4.12 have no app_total because the Worker did not keep
it. Unknown blocks are counted separately and never enter the rescan rate.

Where the manual count comes from (field_tools.fetch_manual_count): the
Worker's admin route GET <url>/v1/scans/<id>/manual-count (AUTH_MODE enforce
or observe; set EGG_ADMIN_TOKEN, it is never printed), which returns the
record kept under the Worker's state prefix, else the legacy scans/ record.
A Worker without that route (0.4.11, AUTH_MODE open) or --r2-only: the legacy
R2 object scans/<id>/manual-count/latest.json with wrangler (needs the
Cloudflare login used for deployment). Records from scans/ are tagged
storage "legacy_scans" (the open production Worker can overwrite them) and
counted in the summary.

The count is asked for again on every run, so a manual count recorded or
corrected since the last run is picked up. A failed download never leaves a
file that a later run would take as cached (see field_tools.r2_get).

Usage (any directory):
  python scripts/score_field_blocks.py --csv counts-from-app.csv --out reports/field-test-<date> [--url URL]
  python scripts/score_field_blocks.py --scan <uuid> [--scan <uuid> ...] --out ... [--r2-only]
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path

import field_tools as ft
from field_tools import STAGING, WorkerAuthError


def fetch_latest(scan_id: str, out_dir: Path, url: str | None = None, *, log=print) -> dict | None:
    """The scan's latest manual count: through the Worker at `url` when it has the route, else (or with url None)
    the legacy R2 object. Raises WorkerAuthError when the Worker refuses the admin credential."""
    return ft.fetch_manual_count(scan_id, out_dir / f"{scan_id}.json", url=url, log=log)


def score(records: list[dict]) -> dict:
    stacks = Counter()
    blocks = {"n": 0, "with_total": 0, "exact": 0, "within_2": 0, "abs_err_sum": 0, "withheld": 0, "unknown": 0}
    interior = Counter()
    storage = Counter()
    rows = []
    for rec in records:
        state, app_total = ft.app_total_state(rec)
        manual_total = ft.manual_total(rec)
        blocks["n"] += 1
        storage[str(rec.get("storage") or "unknown")] += 1
        if state == "unknown":
            blocks["unknown"] += 1
        elif state == "withheld":
            blocks["withheld"] += 1
        else:
            blocks["with_total"] += 1
            err = abs(app_total - manual_total)
            blocks["abs_err_sum"] += err
            blocks["exact"] += err == 0
            blocks["within_2"] += err <= 2
        for c in rec.get("cells") or []:
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
            rows.append({"scan_id": rec.get("scan_id"), "block_id": rec.get("block_id"), "x": c["x"], "y": c["y"],
                         "status": c.get("app_status"), "app_layers": c["app_layers"], "manual_filled": c["filled"],
                         "manual_empty": c["empty"], "diff": c["app_layers"] - manual})

    def pct(a, b):
        return round(100 * a / b, 1) if b else None

    known = blocks["with_total"] + blocks["withheld"]
    mae = round(blocks["abs_err_sum"] / blocks["with_total"], 2) if blocks["with_total"] else None
    summary = {
        "blocks": {**blocks, "mae_when_total": mae,
                   "rescan_rate_pct": pct(blocks["withheld"], known),
                   "note": "unknown = record stored without app_total (before 0.4.12); excluded from the rescan rate"},
        "stacks": {b: {"n": stacks[(b, "n")], "exact_pct": pct(stacks[(b, "exact")], stacks[(b, "n")]),
                       "within_1_pct": pct(stacks[(b, "within_1")], stacks[(b, "n")])} for b in ("observed", "computed")},
        "interior_assumption": {"n": interior["n"], "exact_pct": pct(interior["exact"], interior["n"])},
        "manual_count_storage": {**dict(sorted(storage.items())),
                                 "note": "legacy_scans = stored under scans/, which the open production Worker can "
                                         "overwrite (not tamper-proof); state = kept by the Worker under its state prefix"},
    }
    return {"summary": summary, "rows": rows}


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", help="CSV copied from the app (needs a scan_id column)")
    ap.add_argument("--scan", action="append", default=[], help="scan id (repeatable)")
    ap.add_argument("--out", required=True, help="output directory for fetched records and scores")
    ap.add_argument("--url", default=STAGING, help=f"Worker base URL for the admin manual-count route (default {STAGING})")
    ap.add_argument("--r2-only", action="store_true",
                    help="read only the legacy R2 object scans/<id>/manual-count/latest.json (no Worker call)")
    args = ap.parse_args(argv)
    out = Path(args.out)
    (out / "manual-counts").mkdir(parents=True, exist_ok=True)
    ids = list(args.scan)
    if args.csv:
        with open(args.csv, newline="", encoding="utf-8-sig") as f:
            ids += [r["scan_id"] for r in csv.DictReader(f) if r.get("scan_id")]
    ids = list(dict.fromkeys(i.strip().lower() for i in ids if i.strip()))
    url = None if args.r2_only else args.url.rstrip("/")
    print(f"reading {len(ids)} manual counts " + (f"through {url} ({ft.TOKEN_VARIABLE} {'set' if ft.admin_token_set() else 'not set'})"
                                                  if url else "from the legacy R2 objects only"))
    try:
        records = [r for r in (fetch_latest(i, out / "manual-counts", url) for i in ids) if r]
    except WorkerAuthError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    result = score(records)
    (out / "scores.json").write_text(json.dumps(result["summary"], indent=1), encoding="utf-8")
    with open(out / "per_stack.csv", "w", newline="", encoding="utf-8") as f:
        if result["rows"]:
            w = csv.DictWriter(f, fieldnames=result["rows"][0].keys())
            w.writeheader()
            w.writerows(result["rows"])
    print(json.dumps(result["summary"], indent=1))
    print(f"{len(records)} of {len(ids)} blocks scored; details in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
