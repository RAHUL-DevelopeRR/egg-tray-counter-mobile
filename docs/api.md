# API

## Endpoints

- `GET /health`: process liveness.
- `GET /ready`: provider readiness/configuration summary.
- `GET /version`: application version.
- `POST /v1/scans/count`: synchronous verified/rescan result.

## Multipart fields

Required file fields: `left`, `right`, `straight`. Allowed media types and content
signatures are JPEG and PNG. Optional form fields include `scan_id`,
`device_model`, `app_version`, `warehouse_id`, and `lane_id`.

Use the same UUID for a network retry. The three images execute concurrently at
the inference-provider boundary. Physical matching and fusion wait for all
available results.

## Verified response invariant

`accepted=true` requires non-null `physical_stack_count`, `total_trays`, and
`total_eggs`. Each stack contains per-view counts, final exact count, confidence,
association confidence, and a reason.

## Rejected response invariant

`accepted=false` requires all inventory totals to be null. `rescan` contains an
actionable reason and recommended view. This is enforced by a Pydantic model
validator, not only UI convention.

## Errors

- 413: configured upload size exceeded.
- 415: invalid MIME or JPEG/PNG signature.
- 422: missing/duplicate view, invalid UUID, or domain validation failure.
- 409: same scan UUID reused with different photographs.
- 503: typed inference-provider timeout/auth/model/malformed-response failure.
