"""Offline regression tests for the field-scan scripts (no network, no wrangler, no inference).

subprocess.run is replaced by a fake wrangler that behaves like wrangler 4.125.0 `r2 object get --file`: it
creates the output file BEFORE looking the key up, so a missing key leaves a zero-byte file (the crash measured
on 2026-10-14). urllib.request.urlopen is replaced by a fake Worker with the 0.4.12 scan-job semantics
(docs/SCAN_JOBS_AND_DEVICES.md) or the 0.4.11 open behaviour. Sockets are blocked.

Run from the repository root:
  python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import export_manual_counts as export_mod  # noqa: E402
import field_tools as ft  # noqa: E402
import replay_field_scans as replay_mod  # noqa: E402
import score_field_blocks as score_mod  # noqa: E402

URL = "https://worker.test"
SCAN = "11111111-2222-4333-8444-555555555555"
TOKEN = "tok-DO-NOT-PRINT-7f3a9c"
WORKER_SCAN_ID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
BLOCK = {"status": "exact", "total_trays": 10, "cells": [{"x": 0, "y": 0, "status": "observed", "layers": 10}]}
NOTE = "caf\u00e9 \u00d7 corner"  # non-ASCII: cp1252 decoding would garble it


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def jpeg(tag: str) -> bytes:
    return b"\xff\xd8\xff\xe0" + tag.encode() * 40


def manual_record(filled: int = 9, *, scan: str = SCAN, **extra) -> dict:
    cell = {"x": 0, "y": 0, "filled": filled, "empty": 1, "unreachable": False, "app_layers": 10, "app_status": "observed"}
    return {"kind": "manual_count_v1", "scan_id": scan, "block_id": "B1", "notes": NOTE,
            "recorded_at": "2026-10-13T09:00:00.000Z", "cells": [cell],
            "totals": {"filled": filled, "empty": 1, "unreachable": 0}, **extra}


class FakeWrangler:
    """`npx wrangler r2 object get <bucket>/<key> --remote --file <path>` as wrangler 4.125.0 does it."""

    def __init__(self):
        self.objects: dict[str, bytes] = {}
        self.drop: set[str] = set()  # keys whose download breaks off after a few bytes
        self.calls: list[str] = []

    def __call__(self, cmd, cwd=None, capture_output=None, text=None, shell=None, **kwargs):
        assert cmd[:5] == ["npx", "wrangler", "r2", "object", "get"], cmd
        bucket, key = cmd[5].split("/", 1)
        assert bucket == ft.BUCKET
        target = Path(cmd[cmd.index("--file") + 1])
        self.calls.append(key)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.open("wb").close()  # fs.createWriteStream happens before the key lookup
        if key in self.drop:
            target.write_bytes(self.objects[key][:5])
            return subprocess.CompletedProcess(cmd, 1, "", "\u2718 [ERROR] fetch failed: socket hang up")
        if key not in self.objects:
            return subprocess.CompletedProcess(cmd, 1, "", "\u2718 [ERROR] The specified key does not exist.")
        target.write_bytes(self.objects[key])
        return subprocess.CompletedProcess(cmd, 0, "Download complete.", "")

    def put_manual(self, record: dict, scan: str = SCAN) -> None:
        self.objects[f"scans/{scan}/manual-count/latest.json"] = json.dumps(record, ensure_ascii=False).encode("utf-8")


class FakeResponse(io.BytesIO):
    def __init__(self, payload, status: int = 200):
        super().__init__(json.dumps(payload).encode("utf-8"))
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def http_error(url: str, status: int, code: str, message: str = "") -> urllib.error.HTTPError:
    body = json.dumps({"detail": {"code": code, "message": message}}).encode()
    return urllib.error.HTTPError(url, status, message or code, None, io.BytesIO(body))


def parse_multipart(request) -> tuple[dict[str, str], dict[str, bytes]]:
    boundary = request.get_header("Content-type").split("boundary=")[1].encode()
    fields, files = {}, {}
    for part in request.data.split(b"--" + boundary):
        if b"\r\n\r\n" not in part:
            continue
        head, _, body = part.partition(b"\r\n\r\n")
        body = body[:-2] if body.endswith(b"\r\n") else body
        name = re.search(rb'name="([^"]+)"', head).group(1).decode()
        if b"filename=" in head:
            files[name] = body
        else:
            fields[name] = body.decode()
    return fields, files


class FakeWorker:
    """The routes the scripts call. jobs=True: 0.4.12 scan jobs (stored result per scan id); False: 0.4.11.

    manual_route=True adds GET /v1/scans/<id>/manual-count (answer from `manual`: the tagged latest record or None);
    without it that route is 404 not_found, as on a 0.4.11 or open Worker. manual_errors: (status, code) answers
    the route gives first. archive_jobs[scan] adds a `job` block (image_hashes) to that scan's archive listing;
    archive_fields[scan] adds other fields (truncated, truncated_prefixes); archive_cap cuts every listing to its
    first keys in R2 order, as the open Worker's single 100-key listing does.
    """

    def __init__(self, *, jobs: bool = True, token: str | None = None):
        self.jobs_enabled, self.token = jobs, token
        self.archive: dict[str, list[dict]] = {}
        self.archive_jobs: dict[str, dict | None] = {}
        self.archive_fields: dict[str, dict] = {}
        self.archive_cap: int | None = None
        self.jobs: dict[str, dict] = {}
        self.pending: dict[str, int] = {}  # scan id -> 202 answers still to give
        self.post_faults: list[str] = []
        self.manual_route = False
        self.manual: dict[str, dict | None] = {}
        self.manual_faults: list[str] = []
        self.manual_errors: list[tuple[int, str]] = []
        self.requests: list[tuple[str, str, dict]] = []
        self.posts: list[dict] = []
        self.inferences = 0
        self.manual_pages: dict[str | None, dict] = {}

    def stored(self, scan_id: str) -> dict:
        response = self.jobs[scan_id]
        return {**response, "job": {**response["job"], "replayed": True}}

    def __call__(self, request, timeout=None):
        url, method = request.full_url, request.get_method()
        headers = dict(request.header_items())
        self.requests.append((method, url, headers))
        parts = urllib.parse.urlsplit(url)
        path = parts.path
        if self.token is not None and headers.get("Authorization") != f"Bearer {self.token}":
            raise http_error(url, 401, "admin_auth_failed", "Admin credentials are required")
        if method == "GET" and path.endswith("/archive"):
            scan_id = path.split("/")[3]
            keys = sorted(self.archive.get(scan_id, []), key=lambda k: k["key"])  # R2 lists keys in order
            answer = {"scan_id": scan_id, "keys": keys[:self.archive_cap], **self.archive_fields.get(scan_id, {})}
            if scan_id in self.archive_jobs:
                answer["job"] = self.archive_jobs[scan_id]
            return FakeResponse(answer)
        if method == "GET" and path.endswith("/manual-count") and self.manual_route:
            if self.manual_faults and self.manual_faults.pop(0) == "reset":
                raise urllib.error.URLError(ConnectionResetError(10054, "An existing connection was forcibly closed"))
            if self.manual_errors:
                status, code = self.manual_errors.pop(0)
                raise http_error(url, status, code)
            scan_id = path.split("/")[3]
            latest = self.manual.get(scan_id)
            return FakeResponse({"scan_id": scan_id, "latest": latest, "storage": (latest or {}).get("storage"),
                                 "count_ids": [], "legacy_count_ids": []})
        if method == "POST" and path == "/v1/scans/count":
            fields, files = parse_multipart(request)
            scan_id = fields["scan_id"]
            fault = self.post_faults.pop(0) if self.post_faults else None
            self.posts.append({"fields": fields, "files": files})
            if fault == "reset_before":  # dropped before the Worker got the body (urllib wraps it)
                raise urllib.error.URLError(ConnectionResetError(10054, "An existing connection was forcibly closed"))
            if self.jobs_enabled and scan_id in self.jobs:
                return FakeResponse(self.stored(scan_id))
            self.inferences += 1
            response = {"scan_id": scan_id, "block": BLOCK,
                        "job": {"scan_id": scan_id, "status": "done", "attempt": 1, "replayed": False,
                                "pipeline_version": "worker-0.4.12"}}
            if self.jobs_enabled:
                self.jobs[scan_id] = response
            if fault == "reset_after":  # counted and stored, but the answer was lost
                raise ConnectionResetError(10054, "An existing connection was forcibly closed")
            if fault == "processing":
                self.pending[scan_id] = 2
                return FakeResponse({"detail": {"code": "processing"}, "job": {"status": "running", "retry_after_s": 3}}, 202)
            return FakeResponse(response)
        if method == "GET" and path.endswith("/result"):
            if not self.jobs_enabled:
                raise http_error(url, 404, "not_found", "Route not found")
            scan_id = path.split("/")[3]
            if scan_id not in self.jobs:
                raise http_error(url, 404, "scan_not_found", "The server never received this scan")
            if self.pending.get(scan_id):
                self.pending[scan_id] -= 1
                return FakeResponse({"detail": {"code": "processing"}, "job": {"status": "running", "retry_after_s": 3}}, 202)
            return FakeResponse(self.stored(scan_id))
        if method == "GET" and path == "/v1/manual-counts":
            cursor = urllib.parse.parse_qs(parts.query).get("cursor", [None])[0]
            return FakeResponse(self.manual_pages[cursor])
        raise http_error(url, 404, "not_found", "Route not found")


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    def refuse(*args, **kwargs):
        raise AssertionError("network or process access attempted in an offline test")

    monkeypatch.setattr(socket, "create_connection", refuse)
    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(subprocess, "run", refuse)
    monkeypatch.setattr(urllib.request, "urlopen", refuse)
    monkeypatch.delenv(ft.TOKEN_VARIABLE, raising=False)
    sleeps: list[float] = []
    monkeypatch.setattr(ft, "sleep", sleeps.append)
    return sleeps


@pytest.fixture
def wrangler(monkeypatch):
    fake = FakeWrangler()
    monkeypatch.setattr(subprocess, "run", fake)
    return fake


@pytest.fixture
def worker(monkeypatch):
    fake = FakeWorker()
    monkeypatch.setattr(urllib.request, "urlopen", fake)
    return fake


def add_scan(wrangler: FakeWrangler, worker: FakeWorker, scan: str = SCAN, uploaded: str = "2026-10-13T08:00:00.000Z",
             tag: str = "") -> dict[str, bytes]:
    photos = {}
    for view in ft.VIEWS:
        data = jpeg(f"{scan}-{view}{tag}")
        key = f"scans/{scan}/{view}/{sha(data)}"
        wrangler.objects[key] = data
        worker.archive.setdefault(scan, []).append({"key": key, "size": len(data), "uploaded": uploaded})
        photos[view] = data
    return photos


def run_replay(out: Path, logs: list[str] | None = None, **kwargs) -> dict:
    return replay_mod.replay(SCAN, out, url=URL, log=(logs.append if logs is not None else lambda _m: None), **kwargs)


# ---- the zero-byte / partial download bug -------------------------------------------------------------------

def test_score_fetch_latest_does_not_cache_the_empty_file_of_a_failed_get(tmp_path, wrangler):
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    target = folder / f"{SCAN}.json"
    legacy = ft.legacy_cache_path(target)
    assert legacy == folder / f"{SCAN}.legacy.json"
    assert score_mod.fetch_latest(SCAN, folder) is None
    assert sorted(p.name for p in folder.iterdir()) == []  # no empty file, no .part

    target.write_bytes(b"")  # what the old script left behind; it crashed the next run (JSONDecodeError)
    legacy.write_bytes(b"")  # the same under today's name for the R2 copy
    assert score_mod.fetch_latest(SCAN, folder) is None
    assert not target.exists() and not legacy.exists()
    assert len(wrangler.calls) == 2  # asked again instead of trusting the empty file

    wrangler.put_manual(manual_record(9))
    record = score_mod.fetch_latest(SCAN, folder)
    assert record["cells"][0]["filled"] == 9 and record["notes"] == NOTE  # read as UTF-8

    wrangler.put_manual(manual_record(8, created_at="2026-10-15T07:00:00Z", count_id=str(uuid.uuid4())))
    assert score_mod.fetch_latest(SCAN, folder)["cells"][0]["filled"] == 8  # a correction is picked up


def test_r2_get_never_leaves_a_partial_or_wrong_file_under_the_cached_name(tmp_path, wrangler):
    data = jpeg("photo")
    key = f"scans/{SCAN}/left/{sha(data)}"
    wrangler.objects[key] = data
    target = tmp_path / "left.jpg"
    wrangler.drop.add(key)
    got = ft.r2_get(key, target, sha256=sha(data))
    assert not got.ok and "socket hang up" in got.error
    assert not target.exists() and not (tmp_path / "left.jpg.part").exists()

    wrangler.drop.clear()
    target.write_bytes(b"\xff\xd8 another photo")  # e.g. the first-listed object chosen by the old script
    got = ft.r2_get(key, target, sha256=sha(data))
    assert got.ok and not got.cached and target.read_bytes() == data
    assert ft.r2_get(key, target, sha256=sha(data)).cached  # complete and matching: no wrangler call
    assert wrangler.calls == [key, key]

    wrangler.drop.add(key)
    got = ft.r2_get(key, target, refresh=True)  # a failed refresh keeps the complete copy
    assert got.ok and got.cached and got.error and target.read_bytes() == data


def test_replay_rerun_picks_up_a_later_manual_count(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    out = tmp_path / "out"
    folder = out / "scans" / SCAN
    folder.mkdir(parents=True)
    (folder / "manual-count.json").write_bytes(b"")  # leftovers of the old script
    (folder / "left.jpg").write_bytes(b"")

    first = run_replay(out)
    assert first["status"] == "replayed" and first["manual"] is None and first["block"] == BLOCK
    assert not (folder / "manual-count.json").exists()
    assert worker.inferences == 1 and len(worker.posts) == 1

    wrangler.put_manual(manual_record(9))
    second = run_replay(out)
    assert second["manual"]["cells"][0]["filled"] == 9 and second["manual"]["notes"] == NOTE
    assert second["replay_scan_id"] == first["replay_scan_id"]
    assert len(worker.posts) == 1  # the cached answer is reused: nothing sent

    wrangler.put_manual(manual_record(8, count_id=str(uuid.uuid4()), created_at="2026-10-15T07:00:00Z", app_total=10))
    third = run_replay(out)
    assert third["manual"]["cells"][0]["filled"] == 8 and third["manual_ref"]["count_id"]
    summary, _rows, blocks = replay_mod.score([third])
    assert summary["blocks"]["with_total"] == 1 and summary["phone_total_at_scan_time"]["known"] == 1
    assert blocks[0]["diff_replay_minus_manual"] == 10 - (8 + 1)  # replay total - (filled + empty)

    # the manual count is evaluation data only: never sent to the Worker
    assert set(worker.posts[0]["fields"]) == {"scan_id", "scan_contract"}
    assert set(worker.posts[0]["files"]) == set(ft.VIEWS)


# ---- photo choice and the stable replay id ------------------------------------------------------------------

@pytest.mark.parametrize("newest_listed_first", [False, True])
def test_newest_archived_photo_per_view_is_used_and_flagged(tmp_path, wrangler, worker, newest_listed_first):
    photos = add_scan(wrangler, worker)
    retake = jpeg("retaken left")
    retake_key = f"scans/{SCAN}/left/{sha(retake)}"
    wrangler.objects[retake_key] = retake
    original = next(k for k in worker.archive[SCAN] if "/left/" in k["key"])
    times = ("2026-10-13T08:00:00.000Z", "2026-10-13T08:05:00.000Z")
    # control where the newer object lands in R2's key order
    original_newer = (original["key"] < retake_key) == newest_listed_first
    original["uploaded"] = times[1] if original_newer else times[0]
    worker.archive[SCAN].append({"key": retake_key, "size": len(retake), "uploaded": times[0] if original_newer else times[1]})
    newest, older_key = (photos["left"], retake_key) if original_newer else (retake, original["key"])

    logs: list[str] = []
    entry = run_replay(tmp_path / "out", logs)
    assert entry["status"] == "replayed"
    assert worker.posts[0]["files"]["left"] == newest
    assert [o["key"] for o in entry["older_objects"]["left"]] == [older_key]
    assert any("LEFT has 2 archived photos; using the newest" in line and sha(newest)[:12] in line for line in logs)

    skipped = run_replay(tmp_path / "out-skip", multi_object="skip")
    assert skipped["status"] == "skipped" and "--multi-object skip" in skipped["reason"]
    assert len(worker.posts) == 1


def test_a_view_with_several_photos_and_no_upload_time_is_refused(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    worker.archive[SCAN].append({"key": f"scans/{SCAN}/right/{'0' * 64}", "size": 9})
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "skipped" and "RIGHT has 2 archived photos" in entry["reason"]
    assert worker.posts == [] and wrangler.calls == []


def test_replay_scan_id_is_stable_and_a_rerun_spends_no_inference(tmp_path, wrangler, worker):
    photos = add_scan(wrangler, worker)
    first = run_replay(tmp_path / "run-1")
    second = run_replay(tmp_path / "run-2")  # no local cache: the Worker is asked again
    expected = replay_mod.replay_scan_id(SCAN, replay_mod.DEFAULT_TAG, {v: sha(photos[v]) for v in ft.VIEWS})
    assert first["replay_scan_id"] == second["replay_scan_id"] == expected
    assert [p["fields"]["scan_id"] for p in worker.posts] == [expected, expected]
    assert uuid.UUID(expected).version == 5 and WORKER_SCAN_ID.match(expected) and expected != SCAN
    assert worker.inferences == 1 and second["job"]["replayed"] is True  # stored result, one archive prefix

    other = run_replay(tmp_path / "run-3", tag="worker-0.4.13")
    assert other["replay_scan_id"] != expected and worker.inferences == 2


# ---- transport errors and scan jobs -------------------------------------------------------------------------

def test_count_post_is_retried_after_tls_resets_without_counting_twice(tmp_path, wrangler, worker, offline):
    add_scan(wrangler, worker)
    worker.post_faults = ["reset_before", "reset_after"]
    logs: list[str] = []
    entry = run_replay(tmp_path / "out", logs)
    assert entry["status"] == "replayed" and entry["block"] == BLOCK
    assert len(worker.posts) == 2 and worker.inferences == 1  # the second answer was recovered from the result route
    assert [m for m, u, _ in worker.requests if u.endswith("/result")] == ["GET", "GET"]
    assert offline == [ft.retry_delay(1)]
    assert sum("failed" in line for line in logs) == 2


def test_open_worker_without_result_route_gets_the_same_scan_id_again(tmp_path, wrangler, monkeypatch):
    worker = FakeWorker(jobs=False)
    monkeypatch.setattr(urllib.request, "urlopen", worker)
    add_scan(wrangler, worker)
    worker.post_faults = ["reset_before"]
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "replayed"
    assert len({p["fields"]["scan_id"] for p in worker.posts}) == 1 and len(worker.posts) == 2


def test_processing_answer_waits_for_the_stored_result(tmp_path, wrangler, worker, offline):
    add_scan(wrangler, worker)
    worker.post_faults = ["processing"]
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "replayed" and len(worker.posts) == 1 and worker.inferences == 1
    assert offline == [3.0, 3.0]


def test_a_scan_that_never_gets_an_answer_is_reported_failed(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    worker.post_faults = ["reset_before"] * 4
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "failed" and "after 4 upload attempts" in entry["reason"]
    assert not list((tmp_path / "out" / "scans" / SCAN).glob("replay-*.json"))


# ---- admin credential ---------------------------------------------------------------------------------------

def _all_text(paths: list[Path]) -> str:
    return "\n".join(p.read_bytes().decode("utf-8", "replace") for p in paths if p.is_file())


def test_admin_header_only_when_the_variable_is_set_and_never_printed(tmp_path, wrangler, worker, monkeypatch, capsys):
    add_scan(wrangler, worker)
    worker.manual_pages = {None: {"count": 0, "records": [], "cursor": None}}
    assert replay_mod.main(["--scan", SCAN, "--out", str(tmp_path / "a"), "--url", URL]) == 0
    assert worker.requests and all("Authorization" not in h for _m, _u, h in worker.requests)

    worker.requests.clear()
    worker.token = TOKEN
    monkeypatch.setenv(ft.TOKEN_VARIABLE, TOKEN)
    assert replay_mod.main(["--scan", SCAN, "--out", str(tmp_path / "b"), "--url", URL, "--tag", "t2"]) == 0
    assert export_mod.main(["--out", str(tmp_path / "c"), "--url", URL]) == 0
    routes = {(m, urllib.parse.urlsplit(u).path.rsplit("/", 1)[-1]) for m, u, _h in worker.requests}
    assert {("GET", "archive"), ("POST", "count"), ("GET", "manual-counts")} <= routes
    assert all(h.get("Authorization") == f"Bearer {TOKEN}" for _m, _u, h in worker.requests)

    captured = capsys.readouterr()
    assert TOKEN not in captured.out + captured.err
    assert TOKEN not in _all_text(sorted(tmp_path.rglob("*")))


def test_refused_credential_stops_with_a_clear_message(tmp_path, wrangler, worker, monkeypatch, capsys):
    add_scan(wrangler, worker)
    worker.token = TOKEN
    assert replay_mod.main(["--scan", SCAN, "--out", str(tmp_path / "a"), "--url", URL]) == 2
    err = capsys.readouterr().err
    assert "401 admin_auth_failed" in err and f"{ft.TOKEN_VARIABLE} is not set" in err

    monkeypatch.setenv(ft.TOKEN_VARIABLE, "wrong-token-value-x")
    assert export_mod.main(["--out", str(tmp_path / "b"), "--url", URL]) == 2
    err = capsys.readouterr().err
    assert f"{ft.TOKEN_VARIABLE} is set but was refused" in err and "wrong-token-value-x" not in err
    assert worker.posts == []


def test_the_token_is_not_sent_over_plain_http(monkeypatch):
    monkeypatch.setenv(ft.TOKEN_VARIABLE, TOKEN)
    with pytest.raises(ft.WorkerAuthError) as raised:
        ft.admin_headers("http://worker.example/v1/manual-counts")
    assert TOKEN not in str(raised.value)
    assert ft.admin_headers("http://127.0.0.1:8787/x") == {"Authorization": f"Bearer {TOKEN}"}


# ---- export: pagination and unknown fields ------------------------------------------------------------------

def _csv_rows(path: Path) -> list[dict]:
    import csv
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_export_follows_the_cursor_and_keeps_unknown_fields_blank(tmp_path, worker):
    old = manual_record(9, scan="aaaaaaaa-2222-4333-8444-555555555555")
    old.pop("totals")
    known = manual_record(9, scan="bbbbbbbb-2222-4333-8444-555555555555", count_id=str(uuid.uuid4()),
                          created_at="2026-10-15T07:00:00Z", app_total=12, recorded_by="admin")
    withheld = manual_record(9, scan="cccccccc-2222-4333-8444-555555555555", count_id=str(uuid.uuid4()),
                             created_at="2026-10-15T07:05:00Z", app_total=None)
    worker.manual_pages = {None: {"count": 2, "records": [old, known], "cursor": "page-2 token"},
                           "page-2 token": {"count": 1, "records": [withheld], "cursor": None}}
    assert export_mod.main(["--out", str(tmp_path), "--url", URL]) == 0
    assert [urllib.parse.urlsplit(u).query for _m, u, _h in worker.requests] == ["", "cursor=page-2+token"]

    blocks = {r["scan_id"][:8]: r for r in _csv_rows(tmp_path / "manual_counts_per_block.csv")}
    assert blocks["aaaaaaaa"]["app_total"] == "" and blocks["aaaaaaaa"]["app_total_state"] == "unknown"
    assert blocks["aaaaaaaa"]["manual_filled"] == "" and blocks["aaaaaaaa"]["count_id"] == ""
    assert blocks["aaaaaaaa"]["diff_app_minus_manual"] == ""
    assert blocks["bbbbbbbb"]["app_total_state"] == "known" and blocks["bbbbbbbb"]["diff_app_minus_manual"] == "2"
    assert blocks["cccccccc"]["app_total"] == "" and blocks["cccccccc"]["app_total_state"] == "withheld"
    assert blocks["aaaaaaaa"]["notes"] == NOTE
    assert len(_csv_rows(tmp_path / "manual_counts_per_stack.csv")) == 3


def test_export_accepts_the_old_single_page_shape(tmp_path, worker):
    worker.manual_pages = {None: {"count": 1, "records": [manual_record(9)]}}
    assert export_mod.main(["--out", str(tmp_path), "--url", URL]) == 0
    assert len(worker.requests) == 1
    assert json.loads((tmp_path / "manual_counts.json").read_text(encoding="utf-8"))[0]["scan_id"] == SCAN


def test_export_stops_on_a_repeated_cursor(tmp_path, worker, capsys):
    worker.manual_pages = {None: {"records": [], "cursor": "again"}, "again": {"records": [], "cursor": "again"}}
    assert export_mod.main(["--out", str(tmp_path), "--url", URL]) == 1
    assert "repeated a cursor" in capsys.readouterr().err


# ---- scoring: a missing app_total is unknown, not withheld ---------------------------------------------------

def test_missing_app_total_is_unknown_not_withheld():
    old = [manual_record(9), manual_record(10)]  # stored before 0.4.12: no app_total key
    withheld = manual_record(9, count_id=str(uuid.uuid4()), app_total=None)
    known = manual_record(9, count_id=str(uuid.uuid4()), app_total=12)  # manual 9 filled + 1 empty = 10
    blocks = score_mod.score(old + [withheld, known])["summary"]["blocks"]
    assert (blocks["unknown"], blocks["withheld"], blocks["with_total"]) == (2, 1, 1)
    assert blocks["rescan_rate_pct"] == 50.0 and blocks["within_2"] == 1 and blocks["exact"] == 0

    only_old = score_mod.score(old)["summary"]["blocks"]
    assert only_old["withheld"] == 0 and only_old["unknown"] == 2 and only_old["rescan_rate_pct"] is None
    assert ft.app_total_state({"app_total": None}) == ("unknown", None)  # null without count_id: not 0.4.12


# ---- manual counts through the admin route; legacy R2 fallback ------------------------------------------------

def state_record(filled: int = 8, **extra) -> dict:
    """A record as GET /v1/scans/<id>/manual-count answers it from the Worker's state prefix."""
    return {**manual_record(filled, count_id=str(uuid.uuid4()), created_at="2026-10-15T07:00:00Z", app_total=9, **extra),
            "storage": "state", "tamper_proof": True}


def test_score_reads_the_manual_count_through_the_admin_route(tmp_path, wrangler, worker, monkeypatch):
    worker.manual_route, worker.token = True, TOKEN
    monkeypatch.setenv(ft.TOKEN_VARIABLE, TOKEN)
    state = state_record(8)
    worker.manual[SCAN] = state
    wrangler.put_manual(manual_record(1))  # a legacy copy the open production Worker could have overwritten
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    logs: list[str] = []
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) == state
    assert wrangler.calls == [] and logs == []
    assert json.loads((folder / f"{SCAN}.json").read_text(encoding="utf-8")) == state  # cached as UTF-8
    assert worker.requests[-1][1] == f"{URL}/v1/scans/{SCAN}/manual-count"
    assert worker.requests[-1][2]["Authorization"] == f"Bearer {TOKEN}"

    # The Worker's legacy fallback is used as answered, and the log says it is not tamper-proof.
    worker.manual[SCAN] = {**manual_record(9), "storage": "legacy_scans", "tamper_proof": False}
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append)["storage"] == "legacy_scans"
    assert any("legacy scans/ copy" in line and "not tamper-proof" in line for line in logs)

    # None recorded: no stale copy stays behind for a later run to take as cached.
    worker.manual[SCAN] = None
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) is None
    assert not (folder / f"{SCAN}.json").exists() and wrangler.calls == []


def test_score_falls_back_to_the_legacy_r2_object_on_a_worker_without_the_route(tmp_path, wrangler, worker):
    wrangler.put_manual(manual_record(9))
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    record = score_mod.fetch_latest(SCAN, folder, URL)
    assert record["cells"][0]["filled"] == 9 and record["notes"] == NOTE
    assert record["storage"] == "legacy_scans" and record["tamper_proof"] is False
    assert wrangler.calls == [f"scans/{SCAN}/manual-count/latest.json"]
    assert [u for _m, u, _h in worker.requests] == [f"{URL}/v1/scans/{SCAN}/manual-count"]  # asked first: 404 not_found
    # The R2 object is cached as stored under its own name; the tags are added when it is read.
    assert "storage" not in json.loads((folder / f"{SCAN}.legacy.json").read_text(encoding="utf-8"))
    assert not (folder / f"{SCAN}.json").exists()  # the route's cache name holds only the route's answers


def test_an_unreachable_worker_falls_back_to_the_copy_from_an_earlier_run(tmp_path, wrangler, worker, offline):
    worker.manual_route = True
    state = state_record(8)
    worker.manual[SCAN] = state
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    worker.manual_faults = ["reset"] * 4
    logs: list[str] = []
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) is None  # nothing cached yet
    assert any("manual count not fetched" in line for line in logs)
    assert score_mod.fetch_latest(SCAN, folder, URL) == state
    worker.manual_faults = ["reset"] * 4
    logs.clear()
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) == state
    assert any("using the copy from an earlier run" in line for line in logs)
    assert wrangler.calls == []  # a transport failure is not a reason to read the legacy object
    assert offline == [2.0, 5.0, 10.0] * 2


def test_score_main_uses_the_admin_route_and_stops_on_a_refused_credential(tmp_path, wrangler, worker, monkeypatch, capsys):
    worker.manual_route, worker.token = True, TOKEN
    worker.manual[SCAN] = state_record(8)
    assert score_mod.main(["--scan", SCAN, "--out", str(tmp_path / "a"), "--url", URL]) == 2
    err = capsys.readouterr().err
    assert "401 admin_auth_failed" in err and f"{ft.TOKEN_VARIABLE} is not set" in err

    monkeypatch.setenv(ft.TOKEN_VARIABLE, TOKEN)
    assert score_mod.main(["--scan", SCAN, "--out", str(tmp_path / "b"), "--url", URL]) == 0
    scores = json.loads((tmp_path / "b" / "scores.json").read_text(encoding="utf-8"))
    assert scores["blocks"]["with_total"] == 1 and scores["manual_count_storage"]["state"] == 1
    assert TOKEN not in capsys.readouterr().out

    worker.requests.clear()
    wrangler.put_manual(manual_record(9))
    assert score_mod.main(["--scan", SCAN, "--out", str(tmp_path / "c"), "--r2-only"]) == 0
    assert worker.requests == []
    scores = json.loads((tmp_path / "c" / "scores.json").read_text(encoding="utf-8"))
    assert scores["manual_count_storage"]["legacy_scans"] == 1


def test_replay_reads_the_manual_count_through_the_admin_route(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    worker.manual_route = True
    state = state_record(8)
    worker.manual[SCAN] = state
    wrangler.put_manual(manual_record(1))  # legacy copy: must not be read when the route answers
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "replayed" and entry["manual"] == state
    assert entry["manual_ref"]["storage"] == "state" and entry["manual_ref"]["count_id"] == state["count_id"]
    assert f"scans/{SCAN}/manual-count/latest.json" not in wrangler.calls
    summary, _rows, blocks = replay_mod.score([entry])
    assert blocks[0]["manual_storage"] == "state" and summary["manual_count_storage"]["state"] == 1
    assert set(worker.posts[0]["fields"]) == {"scan_id", "scan_contract"}  # never sent to the Worker


# ---- photo choice by the scan job's image_hashes -------------------------------------------------------------

def test_replay_uses_the_photos_its_scan_job_counted(tmp_path, wrangler, worker):
    photos = add_scan(wrangler, worker)
    # Another Worker (production runs open on the same bucket) adds a newer LEFT photo under the same scan id.
    extra = jpeg("added by the open worker")
    extra_key = f"scans/{SCAN}/left/{sha(extra)}"
    wrangler.objects[extra_key] = extra
    worker.archive[SCAN].append({"key": extra_key, "size": len(extra), "uploaded": "2026-10-13T09:00:00.000Z"})
    worker.archive_jobs[SCAN] = {"image_hashes": {v: sha(photos[v]) for v in ft.VIEWS}, "status": "done", "attempt": 1}
    logs: list[str] = []
    entry = run_replay(tmp_path / "out", logs, multi_object="skip")  # no ambiguity: the job names the photo
    assert entry["status"] == "replayed" and entry["photo_choice"] == "job_image_hashes"
    assert worker.posts[0]["files"] == {v: photos[v] for v in ft.VIEWS}
    assert [o["key"] for o in entry["older_objects"]["left"]] == [extra_key]
    assert any("using the one its scan job counted" in line and sha(photos["left"])[:12] in line for line in logs)
    assert extra_key not in wrangler.calls
    _summary, _rows, blocks = replay_mod.score([entry])
    assert blocks[0]["photo_choice"] == "job_image_hashes" and blocks[0]["views_with_several_objects"] == "left"

    # Without the job block (older Worker, open mode) the newest photo is taken, as before.
    del worker.archive_jobs[SCAN]
    newest = run_replay(tmp_path / "out-newest")
    assert newest["photo_choice"] == "newest_per_view" and worker.posts[-1]["files"]["left"] == extra


def test_a_job_photo_missing_from_the_listing_is_fetched_by_its_key(tmp_path, wrangler, worker):
    photos = add_scan(wrangler, worker)
    worker.archive_jobs[SCAN] = {"image_hashes": {v: sha(photos[v]) for v in ft.VIEWS}}
    worker.archive[SCAN] = [k for k in worker.archive[SCAN] if "/left/" not in k["key"]]  # beyond the 100-key listing
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "replayed" and worker.posts[0]["files"]["left"] == photos["left"]
    assert entry["views"]["left"]["uploaded"] is None and entry["views"]["left"]["sha256"] == sha(photos["left"])

    del wrangler.objects[f"scans/{SCAN}/right/{sha(photos['right'])}"]
    gone = run_replay(tmp_path / "out-2")
    assert gone["status"] == "failed" and "RIGHT photo not downloaded" in gone["reason"]


def test_malformed_job_hashes_are_refused_not_guessed(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    worker.archive_jobs[SCAN] = {"image_hashes": {"left": "x", "right": None}}
    entry = run_replay(tmp_path / "out")
    assert entry["status"] == "skipped" and "not three SHA-256 values" in entry["reason"]
    assert worker.posts == [] and wrangler.calls == []
    worker.archive_jobs[SCAN] = None  # a Worker that lists no job for this scan: newest per view
    assert run_replay(tmp_path / "out-2")["photo_choice"] == "newest_per_view"


def test_the_result_poll_outlasts_the_job_lease():
    # A count that stopped is retried only after the Worker's lease runs out; read it from the Worker's source.
    source = (Path(__file__).resolve().parents[2] / "cloudflare-worker" / "src" / "index.ts").read_text(encoding="utf-8")
    lease_ms = int(re.search(r"^const LEASE_MS = ([\d_]+);", source, re.M).group(1).replace("_", ""))
    assert lease_ms == 150_000
    assert replay_mod.POLL_BUDGET_S > lease_ms / 1000
    assert replay_mod.POLL_BUDGET_S > 242  # the longest count, computed in the comment above LEASE_MS


# ---- review follow-up: manual-count provenance, route errors, cut archive listings ------------------------------

@pytest.mark.parametrize("status, code", [(404, "scan_not_found"), (422, "invalid_scan_id"), (503, "state_prefix_missing")])
def test_only_a_missing_route_falls_back_to_the_legacy_r2_object(tmp_path, wrangler, worker, status, code):
    worker.manual_route = True
    wrangler.put_manual(manual_record(1))  # an overwritable scans/ copy: never read while the route exists
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    worker.manual_errors = [(status, code)]
    logs: list[str] = []
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) is None  # nothing cached yet
    assert any(f"HTTP {status} {code}" in line and "not fetched" in line for line in logs)
    state = state_record(8)
    worker.manual[SCAN] = state
    assert score_mod.fetch_latest(SCAN, folder, URL) == state
    worker.manual_errors = [(status, code)]
    logs.clear()
    assert score_mod.fetch_latest(SCAN, folder, URL, log=logs.append) == state  # the route's answer from the last run
    assert any("using the copy from an earlier run" in line for line in logs)
    assert wrangler.calls == []


def test_r2_reads_never_report_a_state_record_cached_from_the_route(tmp_path, wrangler, worker):
    worker.manual_route = True
    state = state_record(8)
    worker.manual[SCAN] = state
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    route_cache, legacy_cache = folder / f"{SCAN}.json", folder / f"{SCAN}.legacy.json"
    assert score_mod.fetch_latest(SCAN, folder, URL) == state  # run 1 caches the route's answer
    key = f"scans/{SCAN}/manual-count/latest.json"

    # --r2-only and no legacy object: nothing, never the state record cached by run 1.
    logs: list[str] = []
    assert score_mod.fetch_latest(SCAN, folder, None, log=logs.append) is None
    assert logs == [f"  {SCAN}: no manual count recorded yet"] and wrangler.calls == [key]

    # An R2 object is tagged legacy_scans whatever it says about its own storage.
    wrangler.put_manual(manual_record(1, storage="state", tamper_proof=True))
    legacy = score_mod.fetch_latest(SCAN, folder, None)
    assert (legacy["storage"], legacy["tamper_proof"], legacy["cells"][0]["filled"]) == ("legacy_scans", False, 1)
    assert json.loads(legacy_cache.read_text(encoding="utf-8"))["storage"] == "state"  # cached as stored

    # A failed refresh uses the R2 copy from an earlier run, still tagged legacy_scans.
    wrangler.drop.add(key)
    logs.clear()
    again = score_mod.fetch_latest(SCAN, folder, None, log=logs.append)
    assert again["storage"] == "legacy_scans" and again["cells"][0]["filled"] == 1
    assert any("using the copy from an earlier run" in line for line in logs)

    # Wrangler's "does not exist" is final: the earlier R2 copy is dropped, not used.
    wrangler.drop.clear()
    del wrangler.objects[key]
    assert score_mod.fetch_latest(SCAN, folder, None) is None and not legacy_cache.exists()

    # The route's cache was never touched by the R2 reads, and a route failure still finds it.
    assert json.loads(route_cache.read_text(encoding="utf-8")) == state
    worker.manual_faults = ["reset"] * 4
    assert score_mod.fetch_latest(SCAN, folder, URL) == state


def test_an_r2_copy_cached_under_the_route_name_by_an_older_script_moves_to_the_legacy_name(tmp_path, wrangler):
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    old = folder / f"{SCAN}.json"
    old.write_text(json.dumps(manual_record(7)), encoding="utf-8")  # raw R2 object, no storage tag
    wrangler.drop.add(f"scans/{SCAN}/manual-count/latest.json")
    wrangler.put_manual(manual_record(9))
    record = score_mod.fetch_latest(SCAN, folder, None)  # refresh fails: the moved copy is used, tagged legacy
    assert (record["storage"], record["cells"][0]["filled"]) == ("legacy_scans", 7)
    assert not old.exists() and json.loads((folder / f"{SCAN}.legacy.json").read_text(encoding="utf-8"))["cells"][0]["filled"] == 7


def test_the_worker_tags_a_legacy_answer_and_an_untagged_one_is_tagged_legacy(tmp_path, worker):
    worker.manual_route = True
    worker.manual[SCAN] = manual_record(5)  # a route answer without storage: never taken as tamper-proof
    folder = tmp_path / "manual-counts"
    folder.mkdir()
    record = score_mod.fetch_latest(SCAN, folder, URL, log=lambda _m: None)
    assert (record["storage"], record["tamper_proof"]) == ("legacy_scans", False)
    assert json.loads((folder / f"{SCAN}.json").read_text(encoding="utf-8"))["storage"] == "legacy_scans"


def _flood(worker: FakeWorker, n: int) -> None:
    """n objects the open manual-count route adds; their keys sort between left/ and right/."""
    worker.archive[SCAN] += [{"key": f"scans/{SCAN}/manual-count/2026-10-15T11-16-{i:03d}Z.json", "size": 9,
                              "uploaded": "2026-10-15T11:16:00.000Z"} for i in range(n)]


def test_a_cut_open_listing_fails_the_scan_instead_of_reporting_missing_views(tmp_path, wrangler, worker):
    add_scan(wrangler, worker)
    _flood(worker, 98)
    worker.archive_cap = 100  # the open Worker's one listing: LEFT, 98 manual counts, RIGHT; STRAIGHT is cut off
    logs: list[str] = []
    entry = run_replay(tmp_path / "out", logs)
    assert entry["status"] == "failed" and "holds 100 keys and does not say whether there are more" in entry["reason"]
    assert "views in the archive" not in entry["reason"]
    assert worker.posts == [] and wrangler.calls == []

    worker.archive_cap = None
    worker.archive[SCAN] = worker.archive[SCAN][:99]  # the three photos and 96 manual counts: the whole prefix
    assert run_replay(tmp_path / "out-2")["status"] == "replayed"


def test_a_truncated_view_prefix_fails_the_scan_unless_its_job_names_the_photos(tmp_path, wrangler, worker):
    photos = add_scan(wrangler, worker)
    _flood(worker, 120)
    # A 0.4.12 admin listing: each view listed on its own; only the manual counts were cut. Photos chosen as usual.
    worker.archive_fields[SCAN] = {"truncated": True, "truncated_prefixes": [f"scans/{SCAN}/manual-count/"]}
    assert run_replay(tmp_path / "out")["status"] == "replayed"

    worker.archive_fields[SCAN] = {"truncated": True, "truncated_prefixes": [f"scans/{SCAN}/manual-count/", f"scans/{SCAN}/right/"]}
    entry = run_replay(tmp_path / "out-2")
    assert entry["status"] == "failed" and "truncated for RIGHT" in entry["reason"]
    worker.archive_fields[SCAN] = {"truncated": True}  # a cut listing that does not say where
    assert run_replay(tmp_path / "out-3")["status"] == "failed"
    assert len(worker.posts) == 1

    # The scan job names the three photos by hash: a cut listing does not matter.
    worker.archive_fields[SCAN] = {"truncated": True, "truncated_prefixes": [f"scans/{SCAN}/right/"]}
    worker.archive_jobs[SCAN] = {"image_hashes": {v: sha(photos[v]) for v in ft.VIEWS}}
    entry = run_replay(tmp_path / "out-4")
    assert entry["status"] == "replayed" and entry["photo_choice"] == "job_image_hashes"


def test_listing_cut_reads_every_listing_shape():
    keys = [{"key": f"scans/{SCAN}/left/{'a' * 64}"}]
    assert replay_mod.listing_cut({"keys": keys}, SCAN) == ""
    assert replay_mod.listing_cut({"keys": keys, "truncated": False, "truncated_prefixes": []}, SCAN) == ""
    assert replay_mod.listing_cut({"keys": keys * 100, "truncated": False, "truncated_prefixes": []}, SCAN) == ""
    assert replay_mod.listing_cut({"keys": keys * 100}, SCAN).startswith("the archive listing holds 100 keys")
    assert replay_mod.listing_cut({"keys": keys, "truncated": True,
                                   "truncated_prefixes": [f"scans/{SCAN}/left/", f"scans/{SCAN}/straight/"]},
                                  SCAN) == "the archive listing is truncated for LEFT, STRAIGHT"
