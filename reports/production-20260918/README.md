# Assigned-view demonstration — 2026-09-18

Starting checkpoint: 27e7e87, branch codex/hybrid-cell-counting.
The user requested running the supplied files as RIGHT, LEFT, STRAIGHT even
after confirming they are separate counting references rather than one unchanged
arrangement. The demonstration was executed with those exact assignments.

## Actual execution

Fresh inference through the existing Cloudflare gateway using `projec-mutta/2`;
no detector settings changed. Saved detections were then passed, with original
image hashes, through the local FastAPI `/candidate/count-3d` route. This executes
stack localization, RF/band evidence, regional diagnostics and cross-view matching.
No expected count, visual reference or physical truth was supplied to inference.
Gateway request: about 15.17 seconds. Local analysis: about 10.24 seconds.

| Assigned view | RF detections | Proposed faces | Exploratory band counts |
|---|---:|---:|---|
| RIGHT | 15 | 1 | 14 |
| LEFT | 8 | 1 | 10 |
| STRAIGHT | 34 | 3 | 8 / 11 / 16 |

LEFT's single proposed face uses only four of its eight detections. STRAIGHT
faces use 11/11/12 detections. These are observations, not unique inventory cells.

**Backend result: recapture_required; verified=false; X/Y unresolved; eligible
total=null; no supported correspondence proposals.** Three front face proposals
do not establish the full footprint or depth. No common 3D coordinate system or
verified reconstructed grid was recovered. No fabricated prism arrangement has
been substituted for reconstruction.

The response does not prove that the algorithm recognized the images as unrelated.
The existing candidate always withholds certification, including coherent scenes.
This test exercises the real evidence path and exposes its current limitations;
it does not validate a production certifier or a successful scene solver.

## Evidence and audit

- `manifest.json` and `input/`: exact assigned originals and SHA-256.
- `codex_reference.json`: tentative visual estimates frozen before the new run.
- `physical_truth.json`: truth not supplied; no invented physical recount.
- `gateway_request.json`, `gateway_result.json`: fresh live request metadata and
  complete gateway result. Full upstream Roboflow JSON is not exposed by the gateway.
- `candidate_request.json`, `backend_result.json`: local route input and output.
- `reconstruction.json`: extracted scene state, unresolved per-view observations
  and Z alternatives; no invented shared cells or Y positions.
- `comparison.json`: visual-versus-backend diagnostic comparison, not accuracy.
- `demo-summary.json`, `timing.json`: counts, timings and status.

The image hashes match earlier MUTAA originals. Therefore this is not an unseen
blind benchmark despite freezing a reference before this new inference run.
The original reference remains preserved; the limitation is recorded separately.

Tentative visual estimates were 14 eligible for RIGHT, an uncertain 12–14 range
for LEFT, and approximately ten visible egg-containing layers per STRAIGHT column
with possible empty top caps. These estimates are not authoritative truth.
RIGHT band agreement does not certify inventory; LEFT and STRAIGHT discrepancies
require face/endpoint/harmonic inspection. No scene accuracy or precision reported.

## Broader production milestone status

The user has authorized the next production architecture milestone: a SceneSolver,
separate deterministic SceneCertifier, hosted Python service behind Cloudflare,
guided Android capture and staged release. This supersedes the previous blanket
research-only scope, but all requested release gates still apply. The user confirmed
no Python container host is currently available. The actual unchanged-scene triplet
and physical per-stack truth also remain outstanding.

This immediate demonstration does not implement those missing components. No
production deployment, model retraining, signing or APK build occurred. The
existing baseline remains available; current APK remains 0.2.2+5.

Next: implement solver/certifier with trustworthy internal evidence boundaries;
use a genuinely unchanged triplet for shared-cell validation. Continue container,
gateway and mobile work locally until hosting is available, and withhold release
until hosted/device/truth regression gates pass.

Reproduce: set `PYTHONPATH=work/vision-deps;backend` on Windows and run
`python scripts/run_triplet_demo.py`. The runner preserves/reuses a saved gateway
response on rerun; its first execution made the fresh RF request reported above.
