# Testing

## Automated

`scripts/test_all.ps1` runs backend Ruff, backend pytest, ML metric tests, then
Flutter analyze/test when Flutter is installed.

Backend coverage includes:

- original/model coordinate round trip;
- blur/exposure/resolution and invalid decode;
- quadrilateral rectification;
- rail signal, pitch, peaks, and a supported internal gap;
- spatial-order association and stack-count mismatch rejection;
- `[18,18,17]`, `[18,17,19]`, two-view, and one-view fusion cases;
- MIME/signature, size, missing/duplicate view, UUID idempotency;
- Roboflow coordinate normalization, tray-box rejection, timeout, auth-style
  errors, and malformed JSON.

## Golden scenes

Real golden data belongs in `tests/golden/<scene_id>/` with three original images
and `ground_truth.json`. Regression passes only on exact per-stack and scene
counts. A threshold change must be evaluated for both accepted accuracy and
coverage; increasing rejection until accuracy looks good is not acceptable.

## Pilot reporting

Use `ml/evaluate.py <scenes.json>`. Treat the plan's 99.5% accepted exact-scene
accuracy, <=0.5% false accepts, >=85% coverage, and sub-3-second P95 as targets to
measure, never as current results.

## Environment distinction

Flutter is an external SDK. When it is unavailable, scripts print
`ENVIRONMENT NOT INSTALLED`; that is not reported as a passing mobile test.

