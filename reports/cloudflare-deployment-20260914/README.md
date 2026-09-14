# Verified Cloudflare deployment — 2026-09-14

- Worker: egg-tray-counter-api
- URL: https://egg-tray-counter-api.rahultech72216.workers.dev
- Version ID: 0519381f-b99e-4015-8279-cb2c0f99f7f2
- Source checkpoint: e92babb97ba84400dba81ad71b288f8f304e8e18
- CLI: Wrangler 4.125.0; OAuth succeeded after user approval.
- Command: `wrangler deploy --keep-vars` from cloudflare-worker, with
  NODE_OPTIONS=--use-system-ca. Existing variables and server-side credentials
  were preserved. No secret value was read or published.
- Predeployment npm run check passed compilation, dry-run and all 11 tests.

health.json advertises cell_identity_v1 and model_spatial_v1, status ok and
hybrid_ready false. ready.json identifies Roboflow serverless projec-mutta/2.

optional-marker-smoke.json is an HTTP 200 response from a new model_spatial_v1
request without floor-cell ID fields. LEFT was img04.jpg, RIGHT img01.jpg and
STRAIGHT img02.jpg. These are separate benchmark scenes for an API test, not
three angles of the same inventory.

Verified: correct response mode/model; cell_ids {}; nonempty spatial detections
with finite coordinates, positive dimensions and confidence between 0 and 1;
box counts equal per-photo counts; accepted false; tray and egg totals null.
Counts were 29/9/12 and server latency 11,827 ms. This verifies authenticated
Roboflow inference and marker-free API compatibility, not hybrid accuracy.

The APK 0.2.2 backend-contract mismatch is resolved; no APK rebuild was needed.
No physical device scan was run. Automatic stack identity, occupancy and
image-to-hybrid integration remain unfinished. The new path returns unresolved
model evidence. Legacy cell_identity_v1 behavior remains for older clients.
Earlier deployment-blocked reports are historical and superseded here.
