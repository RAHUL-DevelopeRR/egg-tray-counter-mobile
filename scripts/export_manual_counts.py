"""Write the master CSV of every manual count recorded in the app.

Pulls GET /v1/manual-counts from the Worker (each scan's latest manual count:
block id, per-stack app layers and the operator's filled/empty count) and
writes one row per stack plus a per-block summary.

Paging: a 0.4.12 Worker answers {count, records, cursor}; the script follows
`?cursor=` until cursor is null. A 0.4.11 Worker answers {count, records} in
one page, which stops at 500 records (a warning is printed when it is full).

Fields a record does not carry are left blank, never guessed: app_total is
only filled when the record says what the phone showed (app_total_state
known / withheld / unknown; records stored before 0.4.12 are unknown), and
count_id, created_at, recorded_by exist only in 0.4.12 records.

Credentials: when the Worker runs AUTH_MODE=enforce, set EGG_ADMIN_TOKEN to
its admin token; it is sent as `Authorization: Bearer ...` and never printed.

Usage (repo root):
  python scripts/export_manual_counts.py --out reports/field-test-20261009 [--url URL]
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import urllib.parse
from pathlib import Path

import field_tools as ft
from field_tools import STAGING, TransportError, WorkerAuthError, WorkerHTTPError

OLD_PAGE_LIMIT = 500
MAX_PAGES = 1000
BLOCK_FIELDS = ["recorded_at", "block_id", "scan_id", "stacks", "unreachable_stacks", "app_total", "manual_filled",
                "manual_empty", "manual_total_reachable", "diff_app_minus_manual", "app_version", "notes",
                "app_total_state", "count_id", "created_at", "recorded_by", "storage", "tamper_proof"]
STACK_FIELDS = ["recorded_at", "block_id", "scan_id", "x", "y", "app_status", "app_layers", "manual_filled",
                "manual_empty", "unreachable", "diff_app_minus_manual", "count_id"]


def fetch_records(url: str, *, attempts: int = 4, log=print) -> tuple[list[dict], int]:
    """Every record over all pages -> (records, pages)."""
    records: list[dict] = []
    cursor, seen, pages = None, set(), 0
    while True:
        query = f"?{urllib.parse.urlencode({'cursor': cursor})}" if cursor else ""
        payload = ft.get_json(f"{url}/v1/manual-counts{query}", attempts=attempts, timeout=120, log=log)
        page = payload.get("records") if isinstance(payload, dict) else None
        if not isinstance(page, list):
            raise WorkerHTTPError(200, "unexpected_answer", "the answer has no records list")
        records.extend(r for r in page if isinstance(r, dict))
        pages += 1
        if "cursor" not in payload and len(page) >= OLD_PAGE_LIMIT:
            log(f"warning: this Worker returns one page of at most {OLD_PAGE_LIMIT} records and it is full; "
                "older records may be missing")
        cursor = payload.get("cursor")
        if not cursor:
            return records, pages
        if cursor in seen or pages >= MAX_PAGES:
            raise WorkerHTTPError(200, "pagination_loop", "the Worker repeated a cursor; stopping")
        seen.add(cursor)


def _time(record: dict) -> str:
    return str(record.get("created_at") or record.get("recorded_at") or "")


def _rank(record: dict) -> tuple[int, str]:
    # A state record (written through the device-checked route, under the
    # environment's private prefix) beats a legacy scans/ copy, which the open
    # production route can overwrite; time only breaks ties within one kind.
    return (1 if record.get("storage") == "state" else 0, _time(record))


def latest_per_scan(records: list[dict], log=print) -> list[dict]:
    by_scan: dict[str, dict] = {}
    for rec in records:
        key = str(rec.get("scan_id", ""))
        if key in by_scan:
            log(f"warning: scan {key} listed twice; keeping the state record, else the newer one")
            if _rank(rec) <= _rank(by_scan[key]):
                continue
        by_scan[key] = rec
    return sorted(by_scan.values(), key=lambda r: str(r.get("recorded_at") or ""))


def rows_for(records: list[dict]) -> tuple[list[dict], list[dict]]:
    stack_rows, block_rows = [], []
    for rec in records:
        cells = rec.get("cells") or []
        totals = rec.get("totals") if isinstance(rec.get("totals"), dict) else {}
        state, app_total = ft.app_total_state(rec)
        manual_total = ft.manual_total(rec)
        block_rows.append({
            "recorded_at": rec.get("recorded_at"), "block_id": rec.get("block_id"), "scan_id": rec.get("scan_id"),
            "stacks": len(cells), "unreachable_stacks": sum(1 for c in cells if c.get("unreachable")),
            "app_total": app_total, "manual_filled": totals.get("filled"), "manual_empty": totals.get("empty"),
            "manual_total_reachable": manual_total,
            "diff_app_minus_manual": app_total - manual_total if app_total is not None else None,
            "app_version": rec.get("app_version"), "notes": rec.get("notes"),
            "app_total_state": state, "count_id": rec.get("count_id"), "created_at": rec.get("created_at"),
            "recorded_by": rec.get("recorded_by"),
            # Blank when an older Worker did not say where the record lives.
            "storage": rec.get("storage"), "tamper_proof": rec.get("tamper_proof"),
        })
        for c in cells:
            layers = c.get("app_layers")
            stack_rows.append({
                "recorded_at": rec.get("recorded_at"), "block_id": rec.get("block_id"), "scan_id": rec.get("scan_id"),
                "x": c.get("x"), "y": c.get("y"), "app_status": c.get("app_status"), "app_layers": layers,
                "manual_filled": c.get("filled"), "manual_empty": c.get("empty"), "unreachable": c.get("unreachable", False),
                "diff_app_minus_manual": (layers - c["filled"] - c["empty"])
                if layers is not None and not c.get("unreachable") else None,
                "count_id": rec.get("count_id"),
            })
    return stack_rows, block_rows


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default=STAGING, help=f"Worker base URL (default {STAGING})")
    ap.add_argument("--attempts", type=int, default=4, help="tries per page on transport errors (default 4)")
    args = ap.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    url = args.url.rstrip("/")
    try:
        raw, pages = fetch_records(url, attempts=args.attempts)
    except WorkerAuthError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except (WorkerHTTPError, TransportError) as error:
        print(f"error: {url}/v1/manual-counts: {error}", file=sys.stderr)
        return 1
    records = latest_per_scan(raw)
    (out / "manual_counts.json").write_text(json.dumps(records, indent=1), encoding="utf-8")
    stack_rows, block_rows = rows_for(records)
    for name, fields, rows in (("manual_counts_per_stack.csv", STACK_FIELDS, stack_rows),
                               ("manual_counts_per_block.csv", BLOCK_FIELDS, block_rows)):
        with open(out / name, "w", newline="", encoding="utf-8") as f:
            if rows:
                w = csv.DictWriter(f, fieldnames=fields, restval="")
                w.writeheader()
                w.writerows(rows)
    print(f"{len(records)} manual counts ({pages} page{'s' if pages != 1 else ''}), {len(stack_rows)} stack rows -> {out}")
    for b in block_rows:
        app = b["app_total"] if b["app_total_state"] == "known" else b["app_total_state"]
        print(f"  {str(b['block_id']):<12} app {app!s:>8}  manual {b['manual_total_reachable']:>5}  stacks {b['stacks']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
