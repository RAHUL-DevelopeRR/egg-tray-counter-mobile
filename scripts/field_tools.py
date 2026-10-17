"""Shared plumbing for the field-scan scripts: replay_field_scans.py, score_field_blocks.py and
export_manual_counts.py.

Admin credential: when the environment variable EGG_ADMIN_TOKEN is set, every Worker call carries
`Authorization: Bearer <token>` (contract: docs/SCAN_JOBS_AND_DEVICES.md). The token is never printed,
logged or written to a file, and it is only sent over https (or to localhost). A 401/403 stops the script
with a message that says whether the variable was set, never what it contains.

R2 downloads: wrangler 4.x `r2 object get --file X` creates X before it looks the key up, so a missing key
or a dropped download leaves an empty or partial X behind. Downloads therefore go to `X.part` and are moved
into place only when wrangler succeeded and the file is non-empty (and, when the caller knows it, has the
expected SHA-256). A cached file counts only under the same conditions; an empty or wrong file left by an
older version of these scripts is deleted and fetched again.

Manual counts (fetch_manual_count): a Worker in AUTH_MODE enforce or observe stores them under its state prefix,
which the open production Worker on the same bucket cannot write, and serves them on the admin route
GET /v1/scans/<id>/manual-count. Older Workers (and AUTH_MODE open) answer that route 404 not_found; then the
legacy R2 object scans/<id>/manual-count/latest.json is read with wrangler. Every record returned is tagged with
its `storage`: "state", or "legacy_scans" with tamper_proof false (the open Worker can overwrite it). The route's
answer and the R2 object are cached under different names (legacy_cache_path), so a cached copy keeps the way it
was fetched: an R2 read never returns a record cached from the route, and an R2 object is always tagged
"legacy_scans", whatever it says about itself.
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple

STAGING = "https://egg-tray-counter-api-staging.rahultech72216.workers.dev"
BUCKET = "egg-tray-scan-archive"
TOKEN_VARIABLE = "EGG_ADMIN_TOKEN"
USER_AGENT = "egg-tray-tools/1.1"
VIEWS = ("left", "right", "straight")
WORKER_DIR = Path(__file__).resolve().parent.parent / "cloudflare-worker"
RETRY_DELAYS_S = (2.0, 5.0, 10.0, 20.0)

sleep = time.sleep  # module attribute so the offline tests can replace it


class WorkerAuthError(RuntimeError):
    """401/403 from the Worker. Scripts stop: every later call would be refused too."""


class WorkerHTTPError(RuntimeError):
    """Any other HTTP error answer from the Worker."""

    def __init__(self, status: int, code: str, message: str, payload: dict | None = None):
        super().__init__(f"HTTP {status} {code}" + (f": {message}" if message else ""))
        self.status, self.code, self.message, self.payload = status, code, message, payload or {}


class TransportError(RuntimeError):
    """No complete HTTP answer: refused or reset connection, TLS failure, timeout, truncated body."""


def admin_token_set() -> bool:
    return bool(os.environ.get(TOKEN_VARIABLE, "").strip())


def admin_headers(url: str) -> dict[str, str]:
    """The admin Authorization header when EGG_ADMIN_TOKEN is set, else nothing."""
    token = os.environ.get(TOKEN_VARIABLE, "").strip()
    if not token:
        return {}
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" and parts.hostname not in ("localhost", "127.0.0.1", "::1"):
        raise WorkerAuthError(f"refusing to send {TOKEN_VARIABLE} over {parts.scheme or 'an unknown scheme'}; use an https URL")
    return {"Authorization": f"Bearer {token}"}


def auth_message(status: int, code: str, message: str) -> str:
    if status == 401 and admin_token_set():
        hint = (f"{TOKEN_VARIABLE} is set but was refused; check that it matches the Worker's ADMIN_TOKEN secret "
                "for this URL (while that secret is unset every admin call is refused)")
    elif status == 401:
        hint = f"{TOKEN_VARIABLE} is not set and this Worker requires the admin credential (AUTH_MODE enforce or observe)"
    else:
        hint = message or "forbidden"
        hint += f" ({TOKEN_VARIABLE} {'is' if admin_token_set() else 'is not'} set)"
    return f"the Worker refused the request: {status} {code}: {hint}"


def _describe(error: BaseException) -> str:
    reason = getattr(error, "reason", None)
    text = str(reason if reason is not None else error) or type(error).__name__
    return f"{type(error).__name__}: {text}"


def _error_detail(raw: bytes) -> tuple[str, str, dict]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return "unknown", "", {}
    if not isinstance(payload, dict):
        return "unknown", "", {}
    detail = payload.get("detail")
    if isinstance(detail, dict):
        return str(detail.get("code", "unknown")), str(detail.get("message", "")), payload
    return "unknown", str(detail or ""), payload


def call_json(url: str, *, method: str = "GET", data: bytes | None = None, headers: dict[str, str] | None = None,
              timeout: float = 60) -> tuple[int, Any]:
    """One HTTP exchange; (status, parsed JSON) for a 2xx answer.

    Raises WorkerAuthError (401/403), WorkerHTTPError (other HTTP errors) or TransportError (no complete answer).
    """
    request = urllib.request.Request(url, data=data, method=method, headers={
        "User-Agent": USER_AGENT, "Accept": "application/json", **(headers or {}), **admin_headers(url)})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = int(getattr(response, "status", 200) or 200)
            raw = response.read()
    except urllib.error.HTTPError as error:
        try:
            raw = error.read() or b""
        except (OSError, http.client.HTTPException):
            raw = b""
        code, message, payload = _error_detail(raw)
        if error.code in (401, 403):
            raise WorkerAuthError(auth_message(error.code, code, message)) from None
        raise WorkerHTTPError(error.code, code, message, payload) from None
    except (OSError, http.client.HTTPException) as error:  # URLError, resets, TLS, timeouts, IncompleteRead
        raise TransportError(_describe(error)) from None
    try:
        return status, json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as error:
        raise TransportError(f"unreadable answer ({len(raw)} bytes): {error}") from None


def retry_delay(attempt: int) -> float:
    return RETRY_DELAYS_S[min(attempt - 1, len(RETRY_DELAYS_S) - 1)]


def get_json(url: str, *, attempts: int = 4, timeout: float = 60, log=print) -> Any:
    """GET with retries on transport errors only (GETs are safe to repeat)."""
    attempts = max(1, attempts)
    for attempt in range(1, attempts + 1):
        try:
            return call_json(url, timeout=timeout)[1]
        except TransportError as error:
            if attempt >= attempts:
                raise
            delay = retry_delay(attempt)
            log(f"    GET failed ({error}); retry {attempt}/{attempts - 1} in {delay:g} s")
            sleep(delay)
    raise AssertionError("unreachable")  # the loop returns or raises


class Fetched(NamedTuple):
    ok: bool              # target holds a complete copy
    cached: bool = False  # the copy is from an earlier run (refresh not asked for, or the refresh failed)
    missing: bool = False  # wrangler said the key does not exist
    error: str = ""       # why the download (or the refresh) failed


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _complete(path: Path, sha256: str | None) -> bool:
    try:
        if path.stat().st_size == 0:
            return False
    except FileNotFoundError:
        return False
    return sha256 is None or sha256_file(path) == sha256.lower()


def r2_get(key: str, target: Path, *, refresh: bool = False, sha256: str | None = None) -> Fetched:
    """Download R2 object `key` of the scan archive to `target` with wrangler (needs `npx wrangler login`).

    refresh=False: a complete cached file is used without asking R2. refresh=True: ask R2 again (for objects
    that change, such as manual-count/latest.json); a complete cached copy is kept if that download fails.
    """
    cached_ok = _complete(target, sha256)
    if cached_ok and not refresh:
        return Fetched(True, cached=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    part = target.with_name(target.name + ".part")
    part.unlink(missing_ok=True)
    result = subprocess.run(
        ["npx", "wrangler", "r2", "object", "get", f"{BUCKET}/{key}", "--remote", "--file", str(part.resolve())],
        cwd=str(WORKER_DIR), capture_output=True, encoding="utf-8", errors="replace", shell=True,
    )
    if result.returncode == 0 and _complete(part, sha256):
        part.replace(target)  # only a complete download ever appears under the cached name
        return Fetched(True)
    output = "\n".join(s for s in (result.stderr, result.stdout) if s).strip()
    missing = "does not exist" in output
    if result.returncode != 0:
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        error = next((line for line in lines if "ERROR" in line or "does not exist" in line), lines[-1] if lines else "")
        error = (error or f"wrangler exited with {result.returncode}")[:200]
    elif not part.exists() or part.stat().st_size == 0:
        error = "wrangler reported success but the file is empty"
    else:
        error = "downloaded file does not match the SHA-256 in its key"
    part.unlink(missing_ok=True)
    if cached_ok:
        return Fetched(True, cached=True, missing=missing, error=error)
    target.unlink(missing_ok=True)  # an empty, partial or wrong file never stays under the cached name
    return Fetched(False, missing=missing, error=error)


LEGACY_STORAGE_NOTE = "stored under scans/, which the open production Worker can overwrite; not tamper-proof"


def _write_json(target: Path, value: Any) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    part = target.with_name(target.name + ".part")
    part.write_text(json.dumps(value, indent=1, ensure_ascii=False), encoding="utf-8")
    part.replace(target)  # a cached copy is always complete


def _read_record(path: Path) -> tuple[dict | None, str]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, "no copy from an earlier run"
    except (ValueError, UnicodeDecodeError) as error:
        return None, f"unreadable ({error})"
    return (value, "") if isinstance(value, dict) else (None, "not a JSON object")


def _legacy_tagged(record: dict) -> dict:
    return {**record, "storage": "legacy_scans", "tamper_proof": False, "storage_note": LEGACY_STORAGE_NOTE}


def legacy_cache_path(target: Path) -> Path:
    """Where fetch_manual_count caches the legacy R2 object: next to `target` (the route's answer), never under it."""
    return target.with_name(f"{target.stem}.legacy{target.suffix}")


def fetch_manual_count(scan_id: str, target: Path, *, url: str | None = None, attempts: int = 4, log=print) -> dict | None:
    """The scan's latest manual count (tagged with its storage); None when there is none.

    With `url`, the Worker's admin route GET /v1/scans/<id>/manual-count is asked (state record first, else the
    legacy one, tagged by the Worker); its answer is cached at `target`. Only a Worker without that route (404
    not_found) and url=None fall back to the legacy R2 object with wrangler, cached at legacy_cache_path(target) and
    always tagged "legacy_scans". Any other error from the route (another 404 code, 422, 5xx) never reads the
    overwritable scans/ object. The count is asked for on every run, so a count recorded or corrected since the
    last run is picked up; when the question fails, a complete copy from an earlier run of the same source is used
    and said so. Wrangler's "does not exist" is final: no copy is used then.
    Raises WorkerAuthError on 401/403: every later call would be refused too.
    """
    if url:
        try:
            payload = get_json(f"{url}/v1/scans/{scan_id}/manual-count", attempts=attempts, log=log)
        except WorkerHTTPError as error:
            if not (error.status == 404 and error.code == "not_found"):
                return _cached_manual(scan_id, target, str(error), log)
            # This Worker predates the route (or runs AUTH_MODE open): read the legacy R2 object.
        except TransportError as error:
            return _cached_manual(scan_id, target, str(error), log)
        else:
            latest = payload.get("latest") if isinstance(payload, dict) else None
            if not isinstance(latest, dict):
                target.unlink(missing_ok=True)  # the Worker says there is none: no stale copy stays behind
                log(f"  {scan_id}: no manual count recorded yet")
                return None
            if latest.get("storage") != "state":
                latest = _legacy_tagged(latest)
                log(f"  {scan_id}: manual count read from the legacy scans/ copy ({LEGACY_STORAGE_NOTE})")
            _write_json(target, latest)
            return latest
    legacy = legacy_cache_path(target)
    _move_r2_copy(target, legacy)
    got = r2_get(f"scans/{scan_id}/manual-count/latest.json", legacy, refresh=True)
    if got.missing:
        legacy.unlink(missing_ok=True)  # the key is gone: a copy from an earlier run is stale
        log(f"  {scan_id}: no manual count recorded yet")
        return None
    if not got.ok:
        log(f"  {scan_id}: manual count not fetched ({got.error}); scored without it")
        return None
    if got.error:
        log(f"  {scan_id}: manual count not refreshed ({got.error}); using the copy from an earlier run")
    record, problem = _read_record(legacy)
    if record is None:
        log(f"  {scan_id}: manual count {problem}; scored without it")
        return None
    return _legacy_tagged(record)  # read from scans/, whatever the object says about its storage


def _move_r2_copy(target: Path, legacy: Path) -> None:
    """Earlier versions of these scripts cached the R2 object at the route's cache name. A file there without
    `storage` (every route answer has one) is such a copy and moves to the legacy name, unless a copy is already
    there; an empty or unreadable file (a failed wrangler download) is deleted."""
    if not target.is_file():
        return
    record, _problem = _read_record(target)
    if record is not None and record.get("storage"):
        return
    if record is not None and not legacy.exists():
        target.replace(legacy)
    else:
        target.unlink(missing_ok=True)


def _cached_manual(scan_id: str, target: Path, error: str, log) -> dict | None:
    """The route's answer from an earlier run (only route answers are cached at `target`)."""
    record, problem = _read_record(target)
    if record is None:
        log(f"  {scan_id}: manual count not fetched ({error}); scored without it")
        return None
    log(f"  {scan_id}: manual count not refreshed ({error}); using the copy from an earlier run")
    return record if record.get("storage") == "state" else _legacy_tagged(record)


def app_total_state(record: dict | None) -> tuple[str, int | None]:
    """What the phone showed as the block total, from a stored manual-count record.

    known: an integer app_total. withheld: app_total null in a 0.4.12 record (one with count_id), where the app
    always sends the total it showed. unknown: everything else, in particular records stored before 0.4.12,
    which have no app_total at all because the Worker did not keep it. Unknown is never counted as withheld.
    """
    if not record:
        return "unknown", None
    value = record.get("app_total")
    if isinstance(value, int) and not isinstance(value, bool):
        return "known", value
    if "app_total" in record and value is None and record.get("count_id"):
        return "withheld", None
    return "unknown", None


def manual_total(record: dict) -> int:
    """Operator's count over the reachable stacks (filled + empty)."""
    return sum(int(c.get("filled", 0)) + int(c.get("empty", 0)) for c in record.get("cells") or [] if not c.get("unreachable"))
