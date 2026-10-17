# Scan jobs, device credentials and failure classes (contract for 0.4.12)

Status: contract for staging release 0.4.12 (2026-10-15). Production keeps today's open behaviour until
this is validated on staging. The Worker and the app implement this; tests pin it. The section
"As built" at the end records where the implementation refined the first draft and wins over the
text above it.

## Why

Audit of 0.4.11 (2026-10-14/15) measured, offline on the built Worker and in code:

- every route is open: anyone can spend inference, add photos to any scan, overwrite a manual count
  (ground truth) and list every scan id that has one;
- a retried upload repeats archive writes and inference (3 attempts = 9 detector calls, 9 R2 puts, no
  stored result); a lost response can only be recovered by counting again;
- a retake keeps the scan id, so one id ends up with two photos for one view;
- a scan in flight is lost when Android kills the app; nothing on the phone can resume it.

## Storage

All state lives in the existing R2 bucket `egg-tray-scan-archive`, outside the `scans/` photo prefix,
under a per-environment prefix `STATE_PREFIX` (staging `state/staging/`, production default
`state/production/`) because both Workers bind the same bucket.

- `${STATE_PREFIX}devices/<device_id>.json` - `{v:1, device_id, secret_sha256, status: pending|active|revoked,
  label, app_version, created_at, approved_at, revoked_at}`; `customMetadata.status` mirrors `status`.
- `${STATE_PREFIX}jobs/<scan_id>.json` - `{v:1, scan_id, owner, image_hashes:{left,right,straight},
  fingerprint, pipeline_version, status: running|done|failed, attempt, lease_until, created_at,
  updated_at, result?, error?}`; `customMetadata.status` and `.owner` mirror the fields.

Atomicity: claims use `put(key, body, {onlyIf: new Headers({'If-None-Match': '*'})})` (create-only; `null`
means someone else holds the key). Status changes and takeovers use `onlyIf: {etagMatches: <etag>}`
(compare-and-swap; `null` means the record changed). Never decide a claim from a GET.

## Authentication (`AUTH_MODE`)

`AUTH_MODE=enforce` (staging) turns everything below on. Unset or `open` keeps the 0.4.11 behaviour
(production until promoted). `/health` reports `"auth": "device_v1"` and adds `scan_jobs_v1` to
`scan_contracts` when enforce is on, so the app can tell.

Device credential: the app creates `device_id` (UUID v4) and a 32-byte random secret (base64url) on first
launch and keeps them in Android secure storage. Neither is ever in the APK, the repo or logs.

Requests carry `X-Device-Id: <device_id>` and `Authorization: Device <secret>`. The Worker loads the
device record, compares SHA-256(secret) with `secret_sha256` in constant time, and requires
`status == active` (except `GET /v1/devices/me`).

Admin: `Authorization: Bearer <ADMIN_TOKEN>` (Worker secret, compared in constant time). The admin token
lives only in Cloudflare and in the operator's laptop file `work/secrets/staging-admin-token`
(git-ignored); scripts read it from the environment variable `EGG_ADMIN_TOKEN`.

| route | who | notes |
|---|---|---|
| `GET /health`, `GET /ready` | anyone | unchanged |
| `POST /v1/devices` | anyone | body `{device_id, secret, label?, app_version?}`; create-only; returns `{device_id, status, display_code}`; same id + same secret = idempotent; same id + other secret = 409 `device_exists` |
| `GET /v1/devices/me` | that device (any status) | `{device_id, status, display_code}` |
| `POST /v1/scans/count` | active device or admin | job semantics below |
| `GET /v1/scans/<id>/result` | job owner or admin | job semantics below |
| `POST /v1/scans/<id>/manual-count` | job owner or admin | needs an existing job (admin may write for pre-0.4.12 scans with archived photos); idempotent by `count_id` |
| `GET /v1/scans/<id>/archive` | admin | |
| `GET /v1/manual-counts` | admin | paginated: `?cursor=`; returns `{records, cursor}` |
| `POST /v1/reconstruct` | active device or admin | staging only, unchanged otherwise |
| `POST /v1/diagnostics/upload` | active device or admin | discards the body, returns `{bytes, ms}`; measures uploads without spending inference |
| `GET /v1/admin/devices` | admin | |
| `POST /v1/admin/devices/<id>/approve`, `/revoke` | admin | compare-and-swap on the record |

`display_code` = first 8 hex digits of the device id as `XXXX-XXXX`, shown on the phone so the
admin approves the right device.

Errors (JSON `{detail:{code, message}}`), never collapsed into 500:

- 401 `device_credentials_required` (headers missing)
- 401 `device_auth_failed` (unknown id or wrong secret; one code, no oracle)
- 403 `device_pending` (message names the display code)
- 403 `device_revoked`
- 401 `admin_auth_failed`
- 403 `scan_forbidden` (the scan belongs to another device)

## Scan jobs (idempotency)

The client always sends `scan_id`. One scan id = one ordered triplet of photos. A retake makes a new
scan id. Retries and app recovery reuse it.

`POST /v1/scans/count`:

1. authenticate;
2. parse and validate the photos as today, then hash them; `fingerprint` = SHA-256 of
   `left|right|straight` hashes;
3. claim `jobs/<scan_id>` create-only with `status: running, attempt: 1, lease_until: now + 180 s`.
   - **Won**: archive the photos, run inference and the block model, store the full response in the
     job (`status: done`, CAS on the claim etag), return it with HTTP 200.
   - **Lost**: read the job.
     - different owner: 403 `scan_forbidden`;
     - different fingerprint: 409 `scan_id_conflict` ("this scan id was already used with other photos");
     - `done`: return the stored response, HTTP 200, `job.replayed = true`; no inference, no archive write;
     - `running`, lease valid: 202 `{detail:{code:"processing"}, job:{status:"running", retry_after_s}}`;
     - `running`, lease expired, or `failed`: take over with CAS (`attempt + 1`, new lease) and process;
       if the CAS loses, answer 202 processing.
4. On a processing error after the claim: store `status: failed, error:{status, code, message}` (CAS)
   and return the error as today.

Every count response gains `job: {scan_id, status, attempt, replayed, pipeline_version}`.
`PIPELINE_VERSION` is a constant in the Worker; a stored result keeps the version that produced it (a
retry after a deploy returns what was computed, it does not recount).

`GET /v1/scans/<id>/result`:

- 200: done; body = the stored count response (`job.replayed = true`);
- 202: running with a valid lease (`detail.code = "processing"`, `job.retry_after_s`);
- 404 `scan_not_found`: the server never claimed this scan id; it is safe to upload again;
- 409 `scan_failed`: failed, or running with an expired lease (`detail.code = "scan_failed"` or
  `"processing_interrupted"`); POSTing the same photos again retries the job.

## Manual counts

Body as today plus `count_id` (UUID v4, one per operator save; the same on transport retries; a
correction is a new `count_id`), `created_at` (client ISO time) and `app_total`. Stored create-only at
`scans/<id>/manual-count/<count_id>.json`; a repeat of the same `count_id` returns the stored record
(200, `replayed: true`), and a different body under the same `count_id` returns 409.
`latest.json` is replaced only when the new `created_at` is newer than the stored one (CAS loop), so a
late retry of an older count cannot overwrite a newer correction. `app_total` is kept.

## Client failure classes (app)

The app keeps every unfinished scan on disk (`pending_scans` table plus a copy of the three photos
under the app documents directory) until a result is stored in history. It distinguishes:

- **upload failed**: no full request reached the server (connect/TLS/send errors before the body
  completed). Photos kept; the operator retries the upload.
- **result lost**: the body was sent but no answer arrived (receive timeout, connection reset after the
  upload). The app asks `GET /v1/scans/<id>/result` instead of uploading again: 200 = done, 202 = wait
  and ask again, 404 = upload again, 409 = upload again (server retries the job).
- **processing failed**: the server answered with an error after receiving the photos (5xx, 409
  `scan_failed`). Retry allowed.
- **rejected**: 4xx that cannot succeed by retrying (413, 415, 422, 409 `scan_id_conflict`): no retry
  button; retake.
- **not authorised**: 401/403 device errors: shows the device code and status; no retry until approved.

On launch, an unfinished scan is offered as RESUME; resuming first asks for the result, then uploads
only if the server has none.

History: rows written by 0.4.12 record `app_version`. Rows from older apps keep their stored values
but are shown as "unknown (older app)" when they carry the old `rescan_required` with no count; they are
never reclassified.

## Provisioning and revocation

1. Install the APK. On first launch the phone registers itself (pending) and shows
   `WAITING FOR APPROVAL - device XXXX-XXXX`.
2. The admin runs `python scripts/devices.py list` and `python scripts/devices.py approve <device_id>`
   with `EGG_ADMIN_TOKEN` set. The phone shows `DEVICE APPROVED` on its next check.
3. To revoke a lost phone: `python scripts/devices.py revoke <device_id>`. It is refused on its next
   request (R2 reads are strongly consistent).
4. Reinstalling the app or clearing its data creates a new device id (pending); approve it again and
   revoke the old one.
5. Rotating the admin token: `npx wrangler secret put ADMIN_TOKEN --env staging`, then update the local
   file. Device credentials are unaffected.


## As built (2026-10-15, after review) - wins over the draft above

Modes (`AUTH_MODE`):

- `open` (unset or empty; production): 0.4.11 behaviour. New routes answer 404 `not_found`; no `job` block.
- `observe` (staging during rollout; the value in `wrangler.jsonc`): `/health` advertises `auth: device_v1`,
  `scan_jobs_v1` and `auth_mode: observe`. A request that carries `X-Device-Id` or any `Authorization`
  header is handled exactly as in enforce. Count, manual-count and reconstruct requests with neither
  header get the open 0.4.11 answer (logged `observe_open_request`), so an installed 0.4.11 app keeps
  working. Listings and archive are admin-only; result and per-scan manual-count routes need a device or
  admin.
- `enforce`: everything needs a device or admin. Any value other than empty/`open`/`observe` fails closed
  to enforce. Switching staging to enforce: `npx wrangler deploy --env staging --var AUTH_MODE:enforce`
  (then set the file to `enforce` too, or every later deploy returns to observe).
- `STATE_PREFIX` is required in observe/enforce; missing gives 503 `state_prefix_missing` (no silent
  production default, because both Workers bind one bucket).

Jobs:

- Lease 150 s (`LEASE_MS`). After a client disconnects Cloudflare keeps the request alive only about
  30 s (`waitUntil`), so a longer lease mostly delays recovery of an abandoned job. The worst-case count
  (sequential inference with retries plus rim verify) is computed at about 242 s, not measured; a slow but
  live job can therefore be taken over and counted twice. Answers stay consistent: the first stored
  result wins and later attempts return it.
- Fingerprint v2 = SHA-256 of the three photo hashes, `scan_contract` as sent and `[view, cell_id]` pairs
  sorted by view; jobs store `fingerprint_version: 2`, `scan_contract`, `cell_ids`. Older jobs without these
  fields replay for the same photos whatever metadata is sent.
- `PIPELINE_VERSION = worker-0.4.12`. A failure after a lost lease returns the other attempt's stored
  result (200) or 202 if it is still running; `job.status` says `failed` only when the failure was stored.
- A missing `scan_id` is still minted by the server (no idempotency for such a request).

Devices:

- Registration answers 200 for a new or repeated registration; bodies over 4 KiB get 413
  `request_too_large`; labels are cleaned of control and bidi characters.
- Revocation is final: approving a revoked device answers 409 `device_revoked`.
- `scripts/devices.py approve` takes the full device id (or a display code only when it is unique across
  all devices; a shared code needs `--shared-code-ok`) and echoes label and registration time.

Manual counts (observe-authenticated and enforce):

- Stored only under `${STATE_PREFIX}manual-counts/<scan_id>/<count_id>.json` and `.../latest.json`,
  never under `scans/` (the open production route can write `scans/`). `latest.json` is ordered by the
  earlier of the phone's `created_at` and the server's `recorded_at` (a fast phone clock cannot pin it).
  `created_at` must carry a zone, be after 2020 and at most 1 hour ahead of the server.
- New codes: `invalid_count_id`, `invalid_created_at`, `invalid_app_total`, 409 `manual_count_conflict`,
  503 `manual_count_busy`, 404 `scan_not_found` (no job).
- `GET /v1/scans/<id>/manual-count` (owner or admin) -> `{scan_id, latest, storage, count_ids,
  legacy_count_ids}`. A scan with a job never serves a legacy copy as `latest`.
- Admin `GET /v1/manual-counts?limit=&cursor=` lists state records (`storage: state`, `tamper_proof:
  true`) then legacy `scans/*/manual-count/latest.json` records (`storage: legacy_scans`, `tamper_proof:
  false`); the cursor is opaque base64url; at most 400 R2 calls per request.
- Admin `GET /v1/scans/<id>/archive` adds a `job` block (`image_hashes`, `status`, `attempt`, `owner`,
  `pipeline_version`, `created_at`) and `truncated` flags; the job's `image_hashes` name the scan's
  photos (other objects under the prefix may come from the open route).

App (0.4.12+23):

- Rejected (photos discarded): 400, 413, 415, 422, 409 `scan_id_conflict`, 403 `scan_forbidden`.
  408, 425, 429 are retried after `Retry-After`; if they persist the class is upload failed. Any other
  unexpected 4xx is processing failed (photos kept).
- Result polling has a 3-minute wall-clock budget (requests included); with the 150 s lease a scan whose
  count was abandoned turns into 409 `processing_interrupted` inside that budget and is uploaded again.
- On a server without `scan_jobs_v1` (production) a lost result can only be recovered by sending the
  photos again; the screen says so (SEND PHOTOS AGAIN).
- A device check that gets no answer keeps the last server answer and does not block scanning; pending,
  revoked and refused do.
- Android backup and device transfer are disabled (`allowBackup=false`, data extraction rules), so a
  restored phone registers as a new device instead of carrying an unreadable key.

Open risks (staging): with no credential, observe still lets anyone spend inference, add photos under any
scan id and write legacy `scans/` manual counts, as production does today; state records and job photo
lists stay protected. Manual counts saved by earlier 0.4.12 test builds under `scans/` show as legacy.
