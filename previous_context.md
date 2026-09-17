# Previous context — 2026-09-14 checkpoint

## Latest continuation — 2026-09-15 retraining clarification

Read the latest section in docs/100_TRAY_SCENE_PLAN.md before the historical
entries below. New photos are archived under reports/individual-trays-20260915/:
14 attachments, six unique files, ten draft foreground observations. No model
retraining yet. Complete labels and occupancy review, evaluate the unchanged
model, then train/evaluate a separate candidate on scene-separated data.
19/19/20/19/19 are assisted band measurements, not tray counts or RF output.
No truth-based correction, production deployment or APK rebuild is authorized
by this documentation update.

Created at the user's request. This filename did not previously exist.
Existing conversation history remains in previous_chat.md; current requirements
remain in context.md and chronological evidence in PROGRESS.md.

## User objective

Count each physical tray containing eggs exactly once from LEFT, STRAIGHT and
RIGHT photos of the same group. Floor-cell IDs are optional. Combine model
detections, layer structure and calibrated height/markers when available.
Agreement between whole-photo totals is not the requested counting algorithm.
Retain manually counted references, measure errors and precision honestly,
deploy the backend/model and deliver an Android APK.

## Actual state

- Existing deployed Worker routes to Roboflow serverless projec-mutta/2. Fresh
  inference succeeded. It is the old cloudflare_roboflow_egg_tray_baseline, not
  the new hybrid service. Latest health is only status ok; ready identifies V2.
- Wrangler whoami still says unauthenticated on this machine. Previous OAuth
  device flows timed out. This prevents a new deployment, not operation of the
  already deployed Worker. Browser sign-in and CLI authorization are separate.
- Local Worker accepts model_spatial_v1 without floor IDs, preserves boxes,
  and returns unresolved per-photo evidence. It does not infer a scene total.
- Local mobile now captures without mandatory IDs and expects that new contract.
  Consequently the existing live deployment fails its preflight until updated.
- backend/app/vision/hybrid.py contains a tested height/fusion policy, but no
  image/API adapter calls it. The separate older Python layer pipeline uses
  spatial-order association; it is not the required robust identity solution.
- Missing: automatic physical stack association across angles, per-layer egg
  occupancy evidence, image-to-hybrid integration and deployed Python gateway.
  Fixing authentication does not complete these implementation tasks.

## Evaluation and artifact

The retained img04.jpg reference is 32 visible trays, 16 + 16. It was a non-blind
visual recount of an existing benchmark, not physical stock/hidden occupancy
verification. Image SHA-256:
38fac27c726aae28c7d31c177793772d0c3b4932a901bc13402848e21e4ed330.

Fresh V2 inference returned 29: error -3, absolute error 9.375%, count closeness
90.625%. This is not precision. Assisted layer-only returned 23; detector-guided
layer experiment was unresolved. The live evaluation submitted three separate
benchmark scenes to the endpoint's required upload slots, not a three-view
inventory scene. No exact hybrid accuracy or instance precision/recall exists.
Evidence is in reports/manual-reference-20260913/; preserve frozen labels.

Built local egg-tray-counter-0.2.2-hybrid.apk, version 0.2.2+5, 59,631,396 bytes.
SHA-256: 1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b.
Manifest, v2 signature and ZIP integrity passed. It is a development build;
its filename is not a claim of operational hybrid counting. Its debug signing
key differs from 0.2.1, preventing an in-place update. Preserve installed data.
No device/emulator was connected. See reports/APK_0.2.2_BUILD.md.

Flutter analysis was clean; 16 mobile, 44 backend and 11 Worker tests passed.
Worker compilation/dry-run and targeted Ruff passed. No model promotion or new
Cloudflare deployment occurred. APK is ignored locally, not a GitHub release.

## Resume in this order

1. Read AGENTS.md, PROGRESS.md and context.md; verify the actual checkout.
2. Establish deployment authorization via Wrangler OAuth or a scoped deployment
   token stored as a secret. Alternatively configure Cloudflare Workers Builds
   from GitHub. Never put private keys in chat, logs, source or APK.
3. Deploy the compatible optional-marker diagnostic contract and test it with
   the APK, clearly distinguishing diagnostics from an accepted inventory total.
4. Implement the missing image/identity/occupancy adapters and server-side Python
   gateway. Use model/layer evidence when markers are absent; calibrated geometry
   only when real calibration is available. Do not replace this with voting.
5. Obtain same-scene three-view data with checked per-stack/occupancy truth;
   measure exact-match rate, MAE, instance precision/recall and accepted coverage
   on held-out scenes. Do not tune or fabricate predictions from saved truth.
6. Rebuild after integration, recover the original signing key for an in-place
   upgrade, and perform actual device capture/inference tests before claiming
   production readiness. Update the handover with measured results.

Full plan and reusable prompt: docs/COUNTING_EXECUTION_PLAN.md.
This checkpoint publishes the actual unfinished source alongside its documents;
it must not repeat the older handover's mistake of claiming absent local code.

Publication verified: checkpoint bc0a0e67d947c2a06badc6db5b2e497b64e2fb1b is
pushed to origin/codex/hybrid-cell-counting; the remote branch SHA was verified
equal to the local checkpoint. It includes the actual source/tests/reports above.
This is not a Cloudflare deployment or an APK release upload.

## Later update — successful CLI deployment, 2026-09-14

User-approved OAuth completed and Wrangler deployed the updated Worker:
0519381f-b99e-4015-8279-cb2c0f99f7f2. Health and live marker-free model inference
passed; APK 0.2.2 contract compatibility is restored. Read
reports/cloudflare-deployment-20260914/README.md for evidence. Earlier deployment
blockers above are superseded. Exact hybrid integration and device validation
remain unfinished; do not interpret successful deployment as counting accuracy.

## Later update — requested baseline rollback, 2026-09-15

User explicitly requested restoring the older backend without required cell IDs.
Wrangler rollback succeeded: version 621a5a9c-f486-455f-9a15-0965ca3a710f at
100% traffic. Health and V2 readiness passed. Fresh upload checks encountered
TLS resets, so post-rollback inference is unverified. Local source remains newer;
do not redeploy it accidentally. APK 0.2.2 requires the removed model_spatial_v1
contract and is incompatible with this baseline. No APK rebuilt in this turn.


## Later update — 100-tray evidence and architecture checkpoint, 2026-09-15

User confirmed five columns of 20 egg-containing trays, plus one empty on top
of the middle column. Supplied folder contains two result photographs and the
annotated scene, not original captures. Archived source images/hashes, reported
84/90/87 counts and manual-ROI layer diagnostic 40/10/10/11/11 under
reports/user-100-tray-case-20260915/. Neither is an exact hybrid result.
Local service guard rejects individual tray boxes as whole-stack faces;
44 backend tests passed. No production deployment or APK rebuild occurred.

Read docs/COUNTING_ARCHITECTURE.md for current/proposed pipelines and independent
truth/scoring, and docs/100_TRAY_SCENE_PLAN.md for next steps and validation gates.
User requested these records and images be appended and pushed to GitHub.


## 2026-09-15 — local per-stack research checkpoint

User's pasted engineering task explicitly prohibits APK rebuild and replacing
production Worker 621a5a9c-f486-455f-9a15-0965ca3a710f. Keep that override active.
See reports/user-100-tray-case-20260915/RESEARCH_20260915.md for the full report.
New local stack_measurement candidate ranks signed-edge paired bands across
p/2,p,2p hypotheses; old serving layer algorithm is preserved pending validation.
The existing individual-tray-as-stack guard remains intact. No RF training,
model promotion, production deployment or Android build occurred.

Assisted real-image results: legacy 40/10/10/11/11 -> exploratory bands
19/19/20/19/19. Band MAE against reported physical per-column truth is 1.0;
physical and eligible totals remain null. Bands follow brightness/egg structure,
not yet validated physical tray rims. No +1/global multiplier or truth counts
enter inference. Exact physical101/eligible100 NOT reached.

Added geometry-only input, pending101-instance truth records with no invented
geometry, one-to-one bbox-IoU scoring, detection-based stack proposals, native
rectification and versioned measured-height adapter using existing calibration.
52 backend tests passed during development; final checks are recorded in the
report. Source overlays, signal plots, measurements, post-inference scoring and
failed attempts are archived. Manual ROIs are not automatic localization. Real
RF boxes, original triplet, reviewed labels, occupancy training examples and
physical calibration are missing; those measurements cannot be claimed.

Next: full-resolution top/bottom-complete captures/raw RF boxes and per-instance
rim/visibility review; evaluate automatic proposals, physical rim identity and
endpoint evidence, then independent held-out arrangements. Preserve old frozen
benchmarks. Continue only locally/candidate route; do not rebuild Android yet.


## 2026-09-15 — individual tray photographs received

Archived14 attachments as6 byte-unique photographs under
reports/individual-trays-20260915/ with hashes and duplicate mapping. Visually
reviewed: four foreground loaded trays in images1/2, one central loaded tray
in4/5; image3 blurred; image6 mixed/nested/sparse-content stacks needs review.
Added10 selected foreground observation boxes as manual drafts, not10 unique
physical trays. Background annotations incomplete; no training-ready export.
No inference, retraining, deployment or APK rebuild. New scene totals unknown;
never transfer the earlier100-tray truth to these captures. Next: review full
instance/rim labels, confirm small-stack physical counts and egg-vs-shell
occupancy, run unchanged model and measure matched detection errors.
Verification: unique source hashes preserved; annotation boxes in image bounds;
all JSON parsed. This intake changes data/docs only; no runtime tests required.


## 2026-09-16 — live APK/backend compatibility fix

User reported reachable server but optional-marker FormatException before
upload and explicitly requested a fix. Confirmed live baseline health lacked
model_spatial_v1 required by APK0.2.2. Deployed compatibility repair version
ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 with existing model/settings/secrets retained.
Modern model_spatial_v1 scans accept no floor IDs and return spatial evidence;
old no-contract/no-ID requests retain the original baseline route. Explicit
cell-ID contract still validated. This supersedes the previous production
rollback state for this user-requested repair, not for experimental hybrid work.
Compile,12 Worker tests and dry-run passed; live health advertises required
contract. See reports/backend-compatibility-20260916/ for runtime evidence.
No retraining or APK rebuild. Exact hybrid remains unfinished; modern total
stays unresolved. Next: verify a fresh phone scan; continue research separately.


## 2026-09-16 — new upload timeout and reported severe undercount

User reports2/2/25 on views each said to contain100 trays; screenshot separately
shows Dio45-second sendTimeout. Counts are user-reported, not independently
replayed. Compatibility repair did not solve model accuracy or upload reliability.
Source inspection: CameraController uses ResolutionPreset.max; ApiClient sends
original files with45-second send and receive timeouts. Large payload/network
conditions are plausible causes, not confirmed without phone/file evidence.
Band algorithm remains local assisted research and is NOT in the deployed Worker.

APK logs are not uploaded to backend. SQLite history stores result summaries,
not raw images/detection JSON/network traces. Worker observability is enabled,
but modelDiagnostics currently lacks a scan_complete console event; legacy/cell
routes emit counts. Thus historical per-view details may be unavailable even if
request events exist. Do not claim the2/2/25 request was found in logs.
ADB checked: no connected device. Requested USB debugging connection and scan
time/ID to capture upload timing, bytes, network errors and actual input photos.
Need compare returned raw boxes to exact uploaded images before changing model
thresholds or retraining. No additional APK build or deployment in this diagnosis.


## 2026-09-16 — MUTAA local 3D/band candidate checkpoint

User supplied a detailed research prompt and two sketches: complementary X/Y
views, per-stack Z evidence, shared corner counted once, egg-containing trays
only, explicit SOP constraints. No deployment, APK rebuild or immediate training
in this task. Starting branch codex/hybrid-cell-counting, HEAD bd8abb4b6ecc8c0fcfaff5e9661b5688e212d558.

Completed: recursively archived all 35 MUTAA originals with SHA-256, dimensions,
top-level EXIF and contact sheet (35 unique); preserved prompt/sketches. Fresh
unchanged projec-mutta/2 inference obtained for all 35 through current gateway,
confidence35/overlap50/class egg_tray. Saved gateway JSON, request mappings,
EXIF-oriented boxes, automatic stack polygons, beam hypotheses and 35 overlays.
Gateway does not expose full raw upstream RF JSON; this remains a limitation.
First pass hit HTTP503 Worker exceeded resource limits on batches05-12; later
retries and one-large-image/two-small-companion batches recovered all inputs.
Original images unchanged. This is not proof of the earlier phone timeout cause.

Implemented local POST /candidate/count-3d for images plus hash-bound saved RF
boxes (disabled for APP_ENV=production). Reuses existing localization and band
analysis, preserves RF/band/height disagreement, unknown occupancy and SOP
violations. SIFT/RANSAC proposes correspondences but never certifies identity.
Explicit-coordinate grid accounting deduplicates shared physical cells, handles
known gaps/unequal heights and blocks conflicts/unknown occupancy. Synthetic
fixtures validate 200/180 totals, shared-anchor dedup and harmonic abstention.

Real findings: image07 RF56, band candidates16/20/22/19/19 from five incomplete
proposals; image10 RF12 and only one partial ROI despite multiple visible stacks.
Image17 broken egg/shell falsely classified egg_tray; image24 empty tray also
uses generic egg_tray label. No accepted cross-view anchor for tentative07/10/11.
Real X/Y grid, physical totals and eligible totals remain unresolved. No audited
real-world98% accuracy claim. No MUTAA truth imported from the old100-tray scene.

Verification: 62 Python backend tests passed; targeted Ruff passed; TypeScript
compiled and12 Worker tests passed (prior compatibility changes included in
publication). Original/source hashes checked,35 results present. Existing AnyIO
deprecation and Node module-type warnings only. All current context docs updated.

Artifacts: reports/mutaa-20260916/README.md, RESULTS.md, scene-groups.json,
per-image-results.json, cross-view-prototype.json, raw/, analysis/, originals/,
design/. Architecture/SOP: docs/3D_BEAM_COUNTING_ARCHITECTURE.md.
APK stays0.2.2+5; latest recorded live Worker stays
ab67cd59-3f4e-4628-a0fa-d085f56a3fe8. No new deployment/retraining/APK.

Blockers/next: user physical totals and scene identity still pending. Review
stack-face/rim/corner/occupancy annotations; test a separate localized-crop V2
ablation and audited labels before training. Complete calibrated correspondence
and per-layer occupancy before claiming an image-to-3D exact count. Instrument
large multipart/base64 resource use separately; do not deploy as part of research.
Commit/push requested to codex/hybrid-cell-counting; verify remote ref after push.

## 2026-09-16 — verified publication and continuation handover

The MUTAA research checkpoint was committed and pushed as
`d5ddcc8d9fa8ed06052e14503ec1ce2a3a07b9ba` on
`origin/codex/hybrid-cell-counting`. A fresh `git ls-remote` check matched local
HEAD before this documentation update; the working tree was clean. This
supersedes the preceding entry's pending commit/push instruction.

Completed evidence: 35 unique originals preserved with hashes, fresh unchanged
V2 results for all 35, automatic stack/band overlays, tentative scene grouping,
local candidate endpoint and synthetic physical-grid accounting. Recorded checks
from that implementation session: 62 Python tests, 12 Worker tests, TypeScript
compile and targeted Ruff passed. These tests were not rerun for this docs-only
update; they do not establish real-image counting accuracy.

Exact counting remains unfinished. No reliable shared anchor was established
for the tested cross-view group; whole-stack coverage, physical rim endpoints,
hidden depth and per-layer egg occupancy remain unresolved. The broken-shell
false positive and empty-tray detection demonstrate why generic egg_tray boxes
cannot directly certify egg-containing inventory. The phone's 98/100 view is a
single count comparison, not an audited 98% real-world accuracy rate.

Continue from reports/mutaa-20260916/README.md and
 docs/3D_BEAM_COUNTING_ARCHITECTURE.md:
1. Obtain physical per-stack filled/empty counts and confirm unchanged scene
   grouping; do not transfer the old 100-tray truth to MUTAA.
2. Review full stack faces, rim endpoints, shared corners and occupancy labels.
3. Run a separately recorded localized-crop V2 comparison before deciding on
   retraining; keep expected totals outside inference.
4. Validate physical correspondence and occupancy before populating a trusted
   X/Y/Z inventory. Preserve unresolved states instead of filling hidden stock.
5. Investigate multipart/base64 resource use separately. Successful retries do
   not establish a permanent fix for the earlier phone upload timeout.

No new deployment, retraining or APK build. APK remains 0.2.2+5; latest recorded
Worker version remains ab67cd59-3f4e-4628-a0fa-d085f56a3fe8. The user's current
research scope prohibits replacing production or rebuilding Android yet.

## 2026-09-17 — regional quality and physical-grid candidate milestone

Continued from d5ddcc8 on codex/hybrid-cell-counting. Added source/view/layer
provenance to the existing X/Y/Z accounting core, stronger provisional mutual
SIFT + RANSAC + face-coverage/projected-overlap filtering, regional top/middle/
bottom diagnostics, explicit SOP/visibility declarations and structured targeted
recapture recommendations. Local candidate contract revision candidate-20260917
uses geometry/cells and lowercase statuses, rejects expected truth inputs and
string boolean flags, and cannot claim verified inventory. This is a local
research contract change, not a deployed mobile contract migration.

Verification: 65 backend tests passed; after final SOP/production-guard additions,
all 13 spatial candidate tests passed again. All 13 Worker tests, TypeScript,
targeted Ruff and Wrangler deploy --dry-run passed. Synthetic accounting gives
200/180/195, counts shared front/right and rear left/right stacks once, separates
201 physical from 200 eligible with an empty tray, and withholds totals for
unknown occupancy or unobserved rear positions. Harmonic and regional darkness
checks pass. These are synthetic correctness results, not camera accuracy.

Replayed 35 archived MUTAA originals with matching SHA-256 hashes: regional
analysis on 106 historical proposed faces; one bottom-dark warning (image05),
one possible top crop and eight possible base crops. Missing/incomplete ROIs
remain unassessed; unflagged regions are not certified. Thresholds are pilot
heuristics. Zero new RF calls, no training. Tentative 07/10/11 group still has
zero supported correspondence proposals; same-scene grouping and physical
truth remain unknown. See reports/candidate-20260917/README.md and JSON artifacts.

Worker source now uses native Buffer base64 (compile-time Node types added),
sequential hashing and existing sequential inference, with safe byte-size/stage
logs. Local 12,597,763-byte encoding benchmark: identical output in three runs;
median old 2295 ms versus native 10.93 ms. This does not measure Worker peak RAM
or prove a production resource-limit fix; multipart remains buffered. npm install
reported three high advisories in the dependency tree; no blanket dependency
upgrade was attempted in this counting milestone.

APK stays 0.2.2+5. No deployment, APK rebuild or model change. Latest recorded
Worker version stays ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 (historical, not refreshed).
OpenCV stays local. No hosted Python service or WebSocket integration was added.

Blockers and exact next steps:
1. Confirm one unchanged LEFT/STRAIGHT/RIGHT triplet and independent per-X/Y
   physical/filled/empty counts, including gaps. User confirmation remains pending.
2. Freeze truth separately; annotate complete faces/endpoints, shared corners and
   occupancy. Do not inherit old100-tray truth or correct predictions toward it.
3. Calibrate quality and identity gates on labeled examples; run crop-RF ablation
   before deciding on retraining. Validate per-layer occupancy and unseen coverage.
4. Only then integrate hosted Python with Cloudflare, run resource/load validation,
   and implement guided Android capture against the stabilized production contract.
5. Publish this checkpoint and verify the remote branch matches local HEAD.
