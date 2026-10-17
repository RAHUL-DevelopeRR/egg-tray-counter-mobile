"""Replay archived field scans through the current Worker algorithm and score them.

For each source scan id:
1. list its R2 keys (GET <url>/v1/scans/<id>/archive);
2. take ONE photo per view. When the listing names the scan job's photos (`job.image_hashes`, a 0.4.12 Worker in
   AUTH_MODE enforce or observe, for a scan counted with a job), those three are used: the open production Worker
   on the same bucket can add other photos under the same scan id. Otherwise the newest archived object per view
   (R2 upload time); a listing that may not hold every photo of a view (truncated, or 100 keys from a Worker that
   does not say) fails the scan instead. Other objects for a view (a retake that kept the scan id, before 0.4.12, or photos added by
   another Worker) are flagged, and the photo used is printed and kept in replay-manifest.json;
   `--multi-object skip` refuses such scans when the photo had to be chosen by upload time;
3. download the three photos with wrangler (checked against the SHA-256 in their keys) and read the scan's latest
   manual count: through the Worker's admin route GET <url>/v1/scans/<id>/manual-count when it has one, else the
   legacy R2 object scans/<id>/manual-count/latest.json (field_tools.fetch_manual_count; records from scans/ are
   tagged storage "legacy_scans", not tamper-proof). The manual count is asked for again on every run, so a count
   recorded or corrected since the last run is picked up. A failed download never leaves a file that a later run
   would take as cached;
4. POST the photos to <url>/v1/scans/count under a STABLE replay scan id: uuid5 of the source scan id, --tag
   and the three photo hashes. A rerun therefore never archives a new scans/<id>/ prefix, and a 0.4.12 Worker
   (scan jobs) answers a repeat with its stored result instead of counting again. Transport errors (TLS
   resets were measured on the operator's links) are retried; before uploading again the script asks
   GET /v1/scans/<replay id>/result, so a count that finished is not paid for twice;
5. score the replayed block against the operator's manual count (evaluation only: the manual count is never
   sent to the Worker or used by the replay).

The Worker's answer is cached in <out>/scans/<id>/replay-<replay id>.json; a rerun with the same photos and
tag sends nothing. Use a new --tag when the counting code changes and a fresh count is wanted (a 0.4.12
Worker returns the stored result for a known replay id, whatever has been deployed since).

This separates "what the phone showed at scan time" (stored in the manual count as app_layers / app_total)
from "what the current algorithm says now".

Credentials: R2 reads use the wrangler login (`npx wrangler login`). When the Worker runs AUTH_MODE enforce or
observe, set EGG_ADMIN_TOKEN to its admin token; it is sent as `Authorization: Bearer ...` and never printed. In
observe mode an upload without the token is answered as by the open Worker (no stored result, counted again on a
rerun), so set the token there too.

Usage (any directory; needs the Cloudflare login used for deployment):
  python scripts/replay_field_scans.py --csv counts-from-app.csv --out reports/field-test-<date>
  python scripts/replay_field_scans.py --scan <uuid> [--scan ...] --out ... [--url URL] [--tag TAG]
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path

import field_tools as ft
from field_tools import STAGING, VIEWS, TransportError, WorkerAuthError, WorkerHTTPError

DEFAULT_TAG = "worker-0.4.12"
# Fixed namespace for replay ids: uuid5(NAMESPACE_URL, "egg-tray-counter:scripts/replay_field_scans.py").
# Never change it, or every replay id (and every server-side stored result) changes with it.
REPLAY_NAMESPACE = uuid.UUID("d8b8b5d6-1ba5-5361-9fb1-b7d315e04af8")
# Longer than the Worker's job lease (LEASE_MS, 150 s) and its longest count (about 242 s, computed): a count that
# stopped is reported 409 processing_interrupted once the lease runs out, and the photos are uploaded again.
POLL_BUDGET_S = 360.0
SHA_HEX = re.compile(r"^[0-9a-f]{64}$")
ARCHIVE_LISTING_LIMIT = 100  # keys per archive listing (per view prefix on a 0.4.12 admin listing)
STACK_FIELDS = ["scan_id", "block_id", "x", "y", "status", "replay_layers", "phone_layers", "manual", "diff", "note",
                "replay_total"]
BLOCK_FIELDS = ["scan_id", "replay_scan_id", "block_id", "replay_status", "replay_total", "phone_total",
                "phone_total_state", "manual_total_reachable", "diff_replay_minus_manual", "views_with_several_objects",
                "manual_count_id", "manual_created_at", "pipeline_version", "served_from_store", "photo_choice",
                "manual_storage"]


def replay_scan_id(source_scan_id: str, tag: str, hashes: dict[str, str]) -> str:
    """Same source scan, tag and photos -> same id, on every run and every machine."""
    name = "|".join([source_scan_id.lower(), tag, *(hashes[v] for v in VIEWS)])
    return str(uuid.uuid5(REPLAY_NAMESPACE, name))


def _uploaded(item: dict) -> datetime | None:
    value = item.get("uploaded")
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def choose_views(keys: list[dict], scan_id: str) -> tuple[dict[str, dict], dict[str, list[dict]], str]:
    """Newest archived object per view -> (chosen, older objects per view, problem or "")."""
    by_view: dict[str, list[dict]] = {}
    for item in keys:
        parts = str(item.get("key", "")).split("/")
        if len(parts) == 4 and parts[0] == "scans" and parts[1] == scan_id and parts[2] in VIEWS:
            by_view.setdefault(parts[2], []).append(item)
    chosen, older = {}, {}
    for view, items in by_view.items():
        if len(items) == 1:
            chosen[view] = items[0]
            continue
        times = [_uploaded(i) for i in items]
        if any(t is None for t in times):
            return chosen, older, f"{view.upper()} has {len(items)} archived photos and not all have an upload time"
        ranked = sorted(zip(times, items, strict=True), key=lambda pair: pair[0])
        if ranked[-1][0] == ranked[-2][0]:
            return chosen, older, f"{view.upper()} has {len(items)} archived photos with the same newest upload time"
        chosen[view], older[view] = ranked[-1][1], [item for _, item in ranked[:-1]]
    return chosen, older, ""


def job_hashes(listing: dict) -> tuple[dict[str, str] | None, str]:
    """The scan job's photo hashes from an archive listing -> (hashes or None, problem or "").

    None without a problem: the listing names no job (an older Worker, AUTH_MODE open, or a scan counted
    without a job), so the photos are chosen by upload time.
    """
    job = listing.get("job")
    if not isinstance(job, dict):
        return None, ""
    hashes = job.get("image_hashes")
    if not isinstance(hashes, dict) or not all(isinstance(hashes.get(v), str) and SHA_HEX.match(hashes[v].lower())
                                               for v in VIEWS):
        return None, "the scan job's image_hashes are not three SHA-256 values"
    return {v: hashes[v].lower() for v in VIEWS}, ""


def listing_cut(listing: dict, scan_id: str) -> str:
    """Why an archive listing may not hold every photo of a view, or "" when it does.

    A 0.4.12 admin listing lists each view separately and names a prefix that had more than 100 keys in
    `truncated_prefixes` (a cut manual-count/ prefix does not matter here). Older and open Workers list the whole
    scan prefix once, at most 100 keys, and do not say whether there were more: the open manual-count route adds a
    key per call that sorts between left/ and right/, so a full listing can hide photos.
    """
    if "truncated" in listing or "truncated_prefixes" in listing:
        prefixes = listing.get("truncated_prefixes")
        if not isinstance(prefixes, list):
            return "the archive listing is truncated" if listing.get("truncated") else ""
        cut = [view.upper() for view in VIEWS if f"scans/{scan_id}/{view}/" in prefixes]
        return f"the archive listing is truncated for {', '.join(cut)}" if cut else ""
    keys = listing.get("keys") or []
    if len(keys) >= ARCHIVE_LISTING_LIMIT:
        return f"the archive listing holds {len(keys)} keys and does not say whether there are more"
    return ""


def job_views(keys: list[dict], scan_id: str, hashes: dict[str, str]) -> tuple[dict[str, dict], dict[str, list[dict]]]:
    """The photos the scan job counted -> (chosen per view, other objects per view).

    A job photo missing from the listing (it shows at most 100 keys) is still named by its key, which is
    content-addressed; the download checks its SHA-256.
    """
    chosen: dict[str, dict] = {}
    others: dict[str, list[dict]] = {}
    for view in VIEWS:
        key = f"scans/{scan_id}/{view}/{hashes[view]}"
        listed = [i for i in keys if (parts := str(i.get("key", "")).split("/"))[:3] == ["scans", scan_id, view] and len(parts) == 4]
        chosen[view] = next((i for i in listed if i.get("key") == key), {"key": key, "uploaded": None, "size": None})
        rest = [i for i in listed if i.get("key") != key]
        if rest:
            others[view] = rest
    return chosen, others


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    chunks = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    for name, path in files.items():
        data = path.read_bytes()
        png = data.startswith(b"\x89PNG\r\n\x1a\n")
        chunks.append((f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; "
                       f"filename=\"{name}.{'png' if png else 'jpg'}\"\r\n"
                       f"Content-Type: image/{'png' if png else 'jpeg'}\r\n\r\n").encode() + data + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), boundary


def poll_result(url: str, replay_id: str, *, budget_s: float = POLL_BUDGET_S, log=print) -> dict | None:
    """Stored answer for replay_id, or None when the photos must be uploaded (again)."""
    waited = 0.0
    while True:
        try:
            status, payload = ft.call_json(f"{url}/v1/scans/{replay_id}/result", timeout=60)
        except WorkerHTTPError as error:
            # 404 scan_not_found: the Worker never received the scan. 404 not_found: this Worker keeps no results
            # (before 0.4.12 / AUTH_MODE open). 409 scan_failed or processing_interrupted: an upload retries the job.
            if error.code not in ("scan_not_found", "not_found"):
                log(f"    result for {replay_id}: {error}")
            return None
        except TransportError as error:
            log(f"    asking for the result of {replay_id}: {error}")
            delay = 5.0
        else:
            if status == 200:
                return payload
            job = payload.get("job") if isinstance(payload, dict) else None
            delay = float((job or {}).get("retry_after_s") or 5)
        if waited + delay > budget_s:
            log(f"    no result for {replay_id} after waiting {waited:g} s")
            return None
        ft.sleep(delay)
        waited += delay


def count_replay(url: str, replay_id: str, photos: dict[str, Path], *, attempts: int = 4, log=print) -> dict:
    """POST the triplet; retry transport errors, follow 202 'processing', reuse a result the Worker stored."""
    body, boundary = multipart({"scan_id": replay_id, "scan_contract": "model_spatial_v1"}, photos)
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    attempts = max(1, attempts)
    for attempt in range(1, attempts + 1):
        try:
            status, payload = ft.call_json(f"{url}/v1/scans/count", method="POST", data=body, headers=headers, timeout=300)
            if status == 200:
                return payload
            log(f"    {replay_id}: HTTP {status}, the Worker is still counting; waiting for its stored result")
        except TransportError as error:
            log(f"    upload {attempt}/{attempts} for {replay_id} failed: {error}")
        except WorkerHTTPError as error:
            if not (error.status == 503 and error.code == "scan_job_busy"):
                raise
            log(f"    upload {attempt}/{attempts} for {replay_id}: {error}")
        # The photos may have reached the Worker before the link dropped: ask for a stored result first.
        stored = poll_result(url, replay_id, log=log)
        if stored is not None:
            return stored
        if attempt < attempts:
            ft.sleep(ft.retry_delay(attempt))
    raise TransportError(f"no answer for {replay_id} after {attempts} upload attempts")


def _manual_ref(manual: dict | None) -> dict | None:
    if not manual:
        return None
    return {k: manual.get(k) for k in ("block_id", "count_id", "created_at", "recorded_at", "app_version", "storage")}


def replay(scan_id: str, out: Path, *, url: str = STAGING, tag: str = DEFAULT_TAG, multi_object: str = "newest",
           attempts: int = 4, log=print) -> dict:
    """Replay one source scan. Returns its manifest entry; status replayed / skipped / failed."""
    scan_id = scan_id.strip().lower()
    entry: dict = {"scan_id": scan_id, "status": "skipped", "reason": "", "views": {}, "older_objects": {},
                   "photo_choice": None, "replay_scan_id": None, "result_file": None, "manual": None, "manual_ref": None,
                   "block": None, "job": None}
    folder = out / "scans" / scan_id
    folder.mkdir(parents=True, exist_ok=True)
    try:
        listing = ft.get_json(f"{url}/v1/scans/{scan_id}/archive", attempts=attempts, log=log)
    except (WorkerHTTPError, TransportError) as error:
        entry.update(status="failed", reason=f"archive listing: {error}")
        log(f"  {scan_id}: {entry['reason']}")
        return entry
    if not isinstance(listing, dict):
        listing = {}
    keys = listing.get("keys") or []
    counted, problem = job_hashes(listing)

    def short(item: dict) -> str:
        return item["key"].rsplit("/", 1)[-1][:12]

    if counted:
        # The photos this scan id was counted with; anything else under the prefix is flagged, never used.
        chosen, older = job_views(keys, scan_id, counted)
        entry["photo_choice"] = "job_image_hashes"
        for view, items in older.items():
            log(f"  {scan_id}: {view.upper()} has {len(items) + 1} archived photos; using the one its scan job counted "
                f"{short(chosen[view])} (others: " + ", ".join(f"{short(i)} {i.get('uploaded')}" for i in items) + ")")
    elif problem:
        chosen, older = {}, {}
    else:
        cut = listing_cut(listing, scan_id)
        if cut:
            # Choosing by upload time needs every photo of a view; a cut listing is an error, not "fewer views".
            entry.update(status="failed", reason=f"archive listing: {cut}; cannot tell which photos to use")
            log(f"  {scan_id}: {entry['reason']}")
            return entry
        chosen, older, problem = choose_views(keys, scan_id)
        entry["photo_choice"] = "newest_per_view"
        if problem:
            problem += "; cannot tell which photo is newest"
        for view, items in older.items():
            used = chosen[view]
            log(f"  {scan_id}: {view.upper()} has {len(items) + 1} archived photos; using the newest "
                f"{short(used)} uploaded {used.get('uploaded')} (older: "
                + ", ".join(f"{short(i)} {i.get('uploaded')}" for i in items) + ")")
    entry["older_objects"] = {view: [{"key": i["key"], "uploaded": i.get("uploaded")} for i in items]
                              for view, items in older.items()}
    entry["views"] = {view: {"key": i["key"], "uploaded": i.get("uploaded"), "size": i.get("size")}
                      for view, i in chosen.items()}
    if problem:
        entry["reason"] = problem
    elif older and multi_object == "skip" and not counted:
        entry["reason"] = "several archived photos for " + ", ".join(v.upper() for v in older) + " (--multi-object skip)"
    elif len(chosen) != 3:
        entry["reason"] = f"{len(chosen)}/3 views in the archive"
    if entry["reason"]:
        log(f"  {scan_id}: {entry['reason']}; skipped")
        return entry

    photos: dict[str, Path] = {}
    hashes: dict[str, str] = {}
    for view in VIEWS:
        key = chosen[view]["key"]
        name = key.rsplit("/", 1)[-1].lower()
        target = folder / f"{view}.jpg"
        got = ft.r2_get(key, target, sha256=name if SHA_HEX.match(name) else None)
        if not got.ok:
            entry.update(status="failed", reason=f"{view.upper()} photo not downloaded: {got.error}")
            log(f"  {scan_id}: {entry['reason']}")
            return entry
        photos[view], hashes[view] = target, ft.sha256_file(target)
        entry["views"][view]["sha256"] = hashes[view]

    # Evaluation data only: read here, never sent to the Worker's count route.
    entry["manual"] = ft.fetch_manual_count(scan_id, folder / "manual-count.json", url=url, attempts=attempts, log=log)
    entry["manual_ref"] = _manual_ref(entry["manual"])

    replay_id = replay_scan_id(scan_id, tag, hashes)
    result_path = folder / f"replay-{replay_id}.json"
    entry.update(replay_scan_id=replay_id, result_file=result_path.relative_to(out).as_posix())
    response = None
    if result_path.exists() and result_path.stat().st_size > 0:
        try:
            response = json.loads(result_path.read_text(encoding="utf-8"))
        except ValueError:
            response = None
    if not isinstance(response, dict):
        try:
            response = count_replay(url, replay_id, photos, attempts=attempts, log=log)
        except (WorkerHTTPError, TransportError) as error:
            entry.update(status="failed", reason=f"count: {error}")
            log(f"  {scan_id}: {entry['reason']}")
            return entry
        if not isinstance(response, dict):
            entry.update(status="failed", reason="count: the answer is not a JSON object")
            log(f"  {scan_id}: {entry['reason']}")
            return entry
        part = result_path.with_name(result_path.name + ".part")
        part.write_text(json.dumps(response, indent=1), encoding="utf-8")
        part.replace(result_path)
    job = response.get("job") if isinstance(response.get("job"), dict) else None
    if job and job.get("replayed"):
        log(f"  {scan_id}: the Worker returned its stored result for {replay_id} "
            f"(pipeline {job.get('pipeline_version')}, attempt {job.get('attempt')}); no new inference")
    answered = response.get("scan_id")
    if answered and str(answered).lower() != replay_id:
        log(f"  {scan_id}: warning: the answer is for scan {answered}, not {replay_id}")
    block = response.get("block") if isinstance(response.get("block"), dict) else None
    if block is None:
        log(f"  {scan_id}: the Worker's answer has no block result")
    entry.update(status="replayed", block=block, job=job)
    return entry


def score(items: list[dict]) -> tuple[dict, list[dict], list[dict]]:
    rows, block_rows = [], []
    blocks = {"n": 0, "with_total": 0, "exact": 0, "within_2": 0, "withheld": 0, "no_block": 0, "no_manual": 0}
    phone = {"known": 0, "withheld": 0, "unknown": 0}
    storage: Counter = Counter()
    stacks = {"n": 0, "exact": 0, "within_1": 0}
    for item in items:
        block, manual = item["block"], item["manual"]
        blocks["n"] += 1
        state, phone_total = ft.app_total_state(manual)
        replay_total = block.get("total_trays") if block else None
        manual_total = ft.manual_total(manual) if manual else None
        diff = replay_total - manual_total if replay_total is not None and manual_total is not None else None
        block_rows.append({
            "scan_id": item["scan_id"], "replay_scan_id": item["replay_scan_id"],
            "block_id": (manual or {}).get("block_id", ""), "replay_status": (block or {}).get("status", ""),
            "replay_total": replay_total, "phone_total": phone_total, "phone_total_state": state if manual else "",
            "manual_total_reachable": manual_total, "diff_replay_minus_manual": diff,
            "views_with_several_objects": " ".join(sorted(item["older_objects"])),
            "manual_count_id": (manual or {}).get("count_id"), "manual_created_at": (manual or {}).get("created_at"),
            "pipeline_version": (item["job"] or {}).get("pipeline_version"),
            "served_from_store": (item["job"] or {}).get("replayed"),
            "photo_choice": item.get("photo_choice"), "manual_storage": (manual or {}).get("storage"),
        })
        if block is None:
            blocks["no_block"] += 1
            rows.append({"scan_id": item["scan_id"], "note": "answer has no block"})
            continue
        if replay_total is None:
            blocks["withheld"] += 1
        if manual is None:
            blocks["no_manual"] += 1
            rows.append({"scan_id": item["scan_id"], "note": "no manual count", "replay_total": replay_total})
            continue
        phone[state] += 1
        storage[str(manual.get("storage") or "unknown")] += 1
        if diff is not None:
            blocks["with_total"] += 1
            blocks["exact"] += diff == 0
            blocks["within_2"] += abs(diff) <= 2
        manual_cells = {(c["x"], c["y"]): c for c in manual.get("cells") or []}
        for cell in block.get("cells") or []:
            m = manual_cells.get((cell.get("x"), cell.get("y")))
            if not m or m.get("unreachable") or cell.get("layers") is None:
                continue
            cell_diff = cell["layers"] - (m["filled"] + m["empty"])
            if cell.get("status") == "observed":
                stacks["n"] += 1
                stacks["exact"] += cell_diff == 0
                stacks["within_1"] += abs(cell_diff) <= 1
            rows.append({"scan_id": item["scan_id"], "block_id": manual.get("block_id", ""), "x": cell["x"], "y": cell["y"],
                         "status": cell.get("status"), "replay_layers": cell["layers"],
                         "phone_layers": m.get("app_layers"), "manual": m["filled"] + m["empty"], "diff": cell_diff})

    def pct(a, b):
        return round(100 * a / b, 1) if b else None

    with_block = blocks["n"] - blocks["no_block"]
    summary = {"blocks": {**blocks, "exact_pct": pct(blocks["exact"], blocks["with_total"]),
                          "rescan_rate_pct": pct(blocks["withheld"], with_block)},
               "observed_stacks": {**stacks, "exact_pct": pct(stacks["exact"], stacks["n"]),
                                   "within_1_pct": pct(stacks["within_1"], stacks["n"])},
               "phone_total_at_scan_time": {**phone, "note": "unknown = manual count stored without app_total "
                                            "(records before 0.4.12); never counted as withheld"},
               "manual_count_storage": {**dict(sorted(storage.items())),
                                        "note": "legacy_scans = stored under scans/, which the open production Worker "
                                                "can overwrite (not tamper-proof); state = kept under the Worker's state prefix"}}
    return summary, rows, block_rows


def _write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, restval="", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Replay archived field scans through the Worker and score them.")
    ap.add_argument("--csv", help="CSV copied from the app (needs a scan_id column)")
    ap.add_argument("--scan", action="append", default=[], help="source scan id (repeatable)")
    ap.add_argument("--out", required=True, help="output directory (photos, cached answers, scores)")
    ap.add_argument("--url", default=STAGING, help=f"Worker base URL (default {STAGING})")
    ap.add_argument("--tag", default=DEFAULT_TAG,
                    help=f"replay tag, part of the stable replay scan id (default {DEFAULT_TAG}); change it for a fresh count")
    ap.add_argument("--multi-object", choices=("newest", "skip"), default="newest",
                    help="a view with several archived photos and no scan job naming the photo: use the newest "
                         "(default, flagged) or skip the scan")
    ap.add_argument("--attempts", type=int, default=4, help="tries per Worker call on transport errors (default 4)")
    args = ap.parse_args(argv)
    url = args.url.rstrip("/")
    ids = list(args.scan)
    if args.csv:
        with open(args.csv, newline="", encoding="utf-8-sig") as f:
            ids += [r["scan_id"] for r in csv.DictReader(f) if r.get("scan_id")]
    ids = list(dict.fromkeys(i.strip().lower() for i in ids if i.strip()))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"replaying {len(ids)} scans on {url} with tag {args.tag} "
          f"({ft.TOKEN_VARIABLE} {'set' if ft.admin_token_set() else 'not set'})")
    entries = []
    try:
        for scan_id in ids:
            entries.append(replay(scan_id, out, url=url, tag=args.tag, multi_object=args.multi_object,
                                  attempts=args.attempts))
    except WorkerAuthError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    items = [e for e in entries if e["status"] == "replayed"]
    summary, rows, block_rows = score(items)
    summary["run"] = {"url": url, "tag": args.tag, "multi_object": args.multi_object, "scans_requested": len(ids),
                      "replayed": len(items), "skipped": sum(e["status"] == "skipped" for e in entries),
                      "failed": sum(e["status"] == "failed" for e in entries),
                      "with_several_objects_per_view": sum(bool(e["older_objects"]) for e in entries)}
    summary["not_replayed"] = [{"scan_id": e["scan_id"], "status": e["status"], "reason": e["reason"]}
                               for e in entries if e["status"] != "replayed"]
    manifest = {"url": url, "tag": args.tag, "multi_object": args.multi_object, "replay_namespace": str(REPLAY_NAMESPACE),
                "scans": [{k: v for k, v in e.items() if k not in ("manual", "block")} for e in entries]}
    (out / "replay-manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    (out / "replay-scores.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    _write_csv(out / "replay-per-stack.csv", STACK_FIELDS, rows)
    _write_csv(out / "replay-per-block.csv", BLOCK_FIELDS, block_rows)
    print(json.dumps(summary, indent=1))
    print(f"{len(items)} of {len(ids)} scans replayed; details in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
