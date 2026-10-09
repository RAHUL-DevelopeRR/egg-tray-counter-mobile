"""Replay archived field scans through the current staging algorithm and score them.

For each scan id: list its R2 keys (GET /v1/scans/<id>/archive), download the
three photos and the manual count with wrangler, re-submit the photos to
/v1/scans/count on the staging Worker (same view assignment), save the block
result, and score the replayed block against the operator's manual count.
This separates "what the phone showed at scan time" (stored in the manual
count as app_layers) from "what the current algorithm says now".

Usage (repo root; needs the Cloudflare login used for deployment):
  python scripts/replay_field_scans.py --csv counts-from-app.csv --out reports/field-test-<date>
  python scripts/replay_field_scans.py --scan <uuid> [--scan ...] --out ...
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import urllib.request
import uuid
from pathlib import Path

STAGING = "https://egg-tray-counter-api-staging.rahultech72216.workers.dev"
BUCKET = "egg-tray-scan-archive"
VIEWS = ("left", "right", "straight")


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def r2_get(key: str, target: Path) -> bool:
    if target.exists():
        return True
    result = subprocess.run(
        ["npx", "wrangler", "r2", "object", "get", f"{BUCKET}/{key}", "--remote", "--file", str(target.resolve())],
        cwd="cloudflare-worker", capture_output=True, text=True, shell=True,
    )
    return result.returncode == 0 and target.exists()


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in fields.items():
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
    for name, path in files.items():
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{name}.jpg\"\r\n"
                 f"Content-Type: image/jpeg\r\n\r\n").encode() + path.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return body, boundary


def replay(scan_id: str, out: Path) -> dict | None:
    folder = out / "scans" / scan_id
    folder.mkdir(parents=True, exist_ok=True)
    keys = get_json(f"{STAGING}/v1/scans/{scan_id}/archive")["keys"]
    photos: dict[str, Path] = {}
    for item in keys:
        parts = item["key"].split("/")
        if len(parts) == 4 and parts[2] in VIEWS:
            target = folder / f"{parts[2]}.jpg"
            if r2_get(item["key"], target):
                photos[parts[2]] = target
    manual_path = folder / "manual-count.json"
    manual = json.load(open(manual_path)) if r2_get(f"scans/{scan_id}/manual-count/latest.json", manual_path) else None
    if len(photos) != 3:
        print(f"  {scan_id}: {len(photos)}/3 photos in archive; skipped")
        return None
    result_path = folder / "replay-block.json"
    if not result_path.exists():
        body, boundary = multipart({"scan_id": str(uuid.uuid4()), "scan_contract": "model_spatial_v1"}, photos)
        request = urllib.request.Request(f"{STAGING}/v1/scans/count", data=body, method="POST",
                                         headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        with urllib.request.urlopen(request, timeout=300) as response:
            result_path.write_bytes(response.read())
    block = json.load(open(result_path))["block"]
    return {"scan_id": scan_id, "block": block, "manual": manual}


def score(items: list[dict]) -> tuple[dict, list[dict]]:
    rows, blocks = [], {"n": 0, "with_total": 0, "exact": 0, "within_2": 0, "withheld": 0}
    stacks = {"n": 0, "exact": 0, "within_1": 0}
    for item in items:
        block, manual = item["block"], item["manual"]
        blocks["n"] += 1
        if block["total_trays"] is None:
            blocks["withheld"] += 1
        if manual is None:
            rows.append({"scan_id": item["scan_id"], "block_id": "", "note": "no manual count", "replay_total": block["total_trays"]})
            continue
        manual_cells = {(c["x"], c["y"]): c for c in manual["cells"]}
        manual_total = sum(c["filled"] + c["empty"] for c in manual["cells"] if not c.get("unreachable"))
        if block["total_trays"] is not None:
            err = abs(block["total_trays"] - manual_total)
            blocks["with_total"] += 1
            blocks["exact"] += err == 0
            blocks["within_2"] += err <= 2
        for cell in block["cells"]:
            m = manual_cells.get((cell["x"], cell["y"]))
            if not m or m.get("unreachable") or cell["layers"] is None:
                continue
            diff = cell["layers"] - (m["filled"] + m["empty"])
            if cell["status"] == "observed":
                stacks["n"] += 1
                stacks["exact"] += diff == 0
                stacks["within_1"] += abs(diff) <= 1
            rows.append({"scan_id": item["scan_id"], "block_id": manual["block_id"], "x": cell["x"], "y": cell["y"],
                         "status": cell["status"], "replay_layers": cell["layers"],
                         "phone_layers": m.get("app_layers"), "manual": m["filled"] + m["empty"], "diff": diff})
    pct = lambda a, b: round(100 * a / b, 1) if b else None  # noqa: E731
    summary = {"blocks": {**blocks, "exact_pct": pct(blocks["exact"], blocks["with_total"]),
                          "rescan_rate_pct": pct(blocks["withheld"], blocks["n"])},
               "observed_stacks": {**stacks, "exact_pct": pct(stacks["exact"], stacks["n"]),
                                   "within_1_pct": pct(stacks["within_1"], stacks["n"])}}
    return summary, rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv")
    ap.add_argument("--scan", action="append", default=[])
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    ids = list(args.scan)
    if args.csv:
        with open(args.csv, newline="", encoding="utf-8-sig") as f:
            ids += [r["scan_id"] for r in csv.DictReader(f) if r.get("scan_id")]
    ids = list(dict.fromkeys(ids))
    out = Path(args.out)
    items = [r for r in (replay(i, out) for i in ids) if r]
    summary, rows = score(items)
    (out / "replay-scores.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    if rows:
        with open(out / "replay-per-stack.csv", "w", newline="", encoding="utf-8") as f:
            fieldnames = sorted({k for r in rows for k in r}, key=lambda k: ["scan_id", "block_id", "x", "y", "status",
                                 "replay_layers", "phone_layers", "manual", "diff", "note", "replay_total"].index(k))
            w = csv.DictWriter(f, fieldnames=fieldnames); w.writeheader(); w.writerows(rows)
    print(json.dumps(summary, indent=1))
    print(f"{len(items)} scans replayed; details in {out}")


if __name__ == "__main__":
    main()
