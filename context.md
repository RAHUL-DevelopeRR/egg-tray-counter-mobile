> Latest checkpoint (2026-09-16): the active work is the **local MUTAA 3D/band
> candidate**, documented in `docs/3D_BEAM_COUNTING_ARCHITECTURE.md` and
> `reports/mutaa-20260916/README.md`. 35 originals have fresh V2 results and
> automatic band/ROI evidence; real 3D identity and eligible totals remain
> unresolved. 62 Python tests and 12 Worker tests pass. APK remains 0.2.2+5;
> latest recorded live Worker is ab67cd59-3f4e-4628-a0fa-d085f56a3fe8.
> No new deployment, APK or retraining. Earlier deployment/training priorities
> below are historical and do not override the current research-only scope.
> Read the latest PROGRESS.md and context.md entries first.

# Current development context

Latest live state (2026-09-16): user-requested APK compatibility repair deployed
as ab67cd59-3f4e-4628-a0fa-d085f56a3fe8. Health supports model_spatial_v1 again;
legacy no-contract/no-ID requests retain baseline behavior. Earlier rollback
version below is historical. Exact hybrid remains unfinished; no APK rebuild.
See reports/backend-compatibility-20260916/README.md and latest progress append.

## Latest publication request — 2026-09-15

User authorized pushing all pending repository changes, including PROGRESS.md,
context.md, supporting documentation and individual-tray photo/annotation data,
to codex/hybrid-cell-counting. This is a development checkpoint; the existing
no-APK-rebuild and no-production-replacement requirements remain active.

## Latest clarification — retraining, 2026-09-15

User requested appending context and explaining retraining and the band counts.
See docs/100_TRAY_SCENE_PLAN.md, latest clarification, for the execution sequence.
Retraining has not started. Six unique newly supplied photos have incomplete
draft foreground labels; they supplement development data. Need full visible
tray labels, shell/egg occupancy review, unchanged-model inference, varied
arrangements and a scene-separated held-out evaluation before model promotion.
19/19/20/19/19 are assisted brightness-band candidates, not RF predictions or
verified physical trays. Do not add one per stack or force the known total.
Physical and eligible counts remain unresolved. Production and APK stay unchanged.

Updated: 2026-09-15. Read with `PROGRESS.md` before work.

Latest override: local per-stack research only; no APK rebuild or baseline
replacement. See `reports/user-100-tray-case-20260915/RESEARCH_20260915.md`
and the latest append below for 19/19/20/19/19 assisted band candidates and
unresolved physical/eligible counts. Earlier results remain historical.

User has now authorized implementing the 100-tray plan. Confirmed truth: five
columns with 20 egg-containing trays each; one extra empty atop the middle.
The supplied WhatsApp folder has result screens and an annotated scene, not
original capture views; originals requested. Local service now rejects treating
egg_tray detections as stack faces (44 backend tests passed). Assisted existing
layer counter failed this scene with 40/10/10/11/11 candidates; do not promote it.
Evidence and truth: reports/user-100-tray-case-20260915/. Continue development
without replacing the user's rolled-back production baseline during experiments.

CURRENT OVERRIDE: user requested rollback to the original no-cell-ID baseline.

New planning evidence (2026-09-15): user reports a separate scene with 100
egg-containing trays plus one empty; screenshots show 84/90/87, unverified.
Treat this as user-reported truth, not the prior 32-tray reference. See
docs/100_TRAY_SCENE_PLAN.md for model audit/training plus per-stack geometric
reconstruction and validation plan. No production change authorized by this
planning question; keep the requested baseline running.
Wrangler confirmed version 621a5a9c-f486-455f-9a15-0965ca3a710f now receives
100% traffic. Health/ready passed; fresh photo upload tests hit TLS connection
resets and are unverified. Local code remains the newer implementation. APK
0.2.2's model_spatial_v1 preflight is incompatible with this restored baseline;
no APK changes were requested/performed in the rollback. The September 14
deployment status below is historical, superseded by this explicit request.

Latest verified status: OAuth succeeded and the updated Worker is DEPLOYED,
version 0519381f-b99e-4015-8279-cb2c0f99f7f2. Live health and a no-floor-ID
model_spatial_v1 inference request passed. The APK 0.2.2 backend-contract
mismatch is resolved. Older authentication/deployment blockers below are
historical. Exact hybrid counting remains unfinished; hybrid_ready is false.
See reports/cloudflare-deployment-20260914/README.md and latest PROGRESS.md.

The user requests continued development, not a rewrite. Existing repository:
`https://github.com/RAHUL-DevelopeRR/egg-tray-counter-mobile`.

## Latest user requirements — optional markers and measured evaluation

- Floor-cell IDs are OPTIONAL. The user captures LEFT, RIGHT and STRAIGHT; without floor IDs the backend must use model localization, visual stack association and layer evidence. Calibrated markers/height enhance counting when present. Do not block scans solely because IDs are absent.
- Count physical trays containing eggs, not merely agreement between whole-photo totals. Preserve spatial evidence and avoid duplicate counting across views.
- The user requested manually counting a selected photograph and remembering it, then comparing RF and hybrid predictions to that reference before building an Android APK. A saved reference is now in reports/manual-reference-20260913/reference.json: 16 + 16 = 32 visible trays, explicitly a non-blind visual recount of an existing benchmark photo, not a physical inventory audit.
- The user reports Cloudflare and Roboflow authenticated. Browser inventory showed account/workspace URLs, but page control timed out. Do not report the user as unauthenticated; CLI/API access and fresh inference remain unverified.
- The user requests a solid execution plan and reusable prompt. See docs/COUNTING_EXECUTION_PLAN.md.

## Earlier clarified requirement (apply with optional-marker update above)

The user explicitly clarified that “boxed strips” means **painted floor boxes and wall-height reference marks**, not just horizontal tray edges.

Build one photo-counting flow: LEFT / STRAIGHT / RIGHT → automatic physical-cell identification and calibrated geometry + server-side Roboflow V2 tray evidence + optional layer-edge evidence → per-cell hybrid fusion → sum each unique accepted cell once. Do not leave model, height and grid counting as unrelated modes.

- Fix the reported backend-offline issue and deploy the compatible gateway.
- Keep RF bounding boxes and spatial evidence; do not reduce everything to whole-photo totals.
- Recognize floor boundaries/IDs automatically where reliable; manual correction is a fallback.
- Recognize calibrated wall marks and account for depth/perspective before estimating tray-rim height. A floor homography cannot measure a vertical stack by itself.
- Preserve physical cell identity across views. Different-view totals of 40, 40 and 100 can represent different cells; neither compare nor sum them blindly.
- Reject unresolved evidence disagreement; no arbitrary correction factors or fabricated counts.
- Count only egg-filled trays; compute eggs as accepted trays × 30. Detecting the `egg_tray` class alone does not establish egg-filled status.
- Keep expensive vision processing server-side. Reuse Python/OpenCV behind the Cloudflare gateway when Workers cannot run it effectively.
- User authorizes necessary Cloudflare/Roboflow authentication, deployment, new APK build, and verified source publication. Request only genuinely required login actions; continue independent work while blocked.
- Keep private credentials server-side and out of APK, source, logs and documentation.
- Retain V2 `projec-mutta/2`; do not promote V3/V4/tiled models without evaluation.
- Preserve the frozen benchmark. Do not claim 100% accuracy: the supplied handover explicitly says the isolated warehouse result does not establish overall accuracy.

## Delivery requirements

Build and verify a new version, intended `0.2.2+5`, with root artifact `egg-tray-counter-0.2.2-hybrid.apk`. Run Flutter clean/pub get/analyze/tests, Worker/backend tests, APK metadata/signature checks and available emulator/device end-to-end checks. Clearly distinguish completed tests from blocked tests.

Final report should include commit SHA, artifact version/path/hash, service URL/health/readiness, actual model version, RF/height/hybrid benchmark metrics, device results and remaining limitations. Update `PROGRESS.md` before ending substantial sessions.

## Existing reference documents

- `docs/codex-context/CODEX_HANDOVER.md`
- `docs/codex-context/MASTER_SPECIFICATION.md`
- `docs/codex-context/AI_CONTINUATION_PROMPT.md`
- `docs/codex-context/SESSION_DIGEST.md`
- `README.md`

These describe historical state; the clarified requirements above supersede the old split-mode design.

## Latest conversation and work checkpoint

- 2026-09-14: 0.2.2+5 APK BUILT and verified at egg-tray-counter-0.2.2-hybrid.apk. SHA-256 1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b. It is an incomplete development build; exact hybrid counting and compatible backend deployment remain unfinished. Its debug signer differs from the old APK, so an in-place upgrade is unavailable without the original key. No device test occurred. See reports/APK_0.2.2_BUILD.md. This supersedes earlier statements that no new APK exists.

- 2026-09-13 continuation: Flutter/Android setup recovered; analysis clean, 16 mobile tests and 44 backend tests passed, Worker compilation/dry-run/11 tests passed. Source version is 0.2.2+5; release build underway, no new APK yet verified. Existing live Worker successfully called Roboflow V2: img04 fresh count 29 versus retained visual reference 32, error 3/9.375%. See reports/manual-reference-20260913/LIVE_EVALUATION.md. This was a per-image check using separate benchmark scenes, not three-view validation. Deployment CLI remains unauthenticated; old live contract does not support changed mobile preflight. Exact hybrid integration remains unfinished.

- Full available user/assistant conversation is preserved in `previous_chat.md`, with the supplied continuation brief included. Read it when the concise context here is insufficient.
- The user asked whether the existing three-angle Roboflow analysis was enough. The answer was that three views are useful but not independent proof of correctness; the user then explicitly said, “Okay do the hybrid verification.”
- The user authorized opening Cloudflare and Roboflow sign-in pages. Tabs were opened for the user; authenticated access is not yet confirmed.
- Current branch: `codex/hybrid-cell-counting`, based on main at `8073dbe`. Remote main was fetched and matched the local starting commit.
- Backend/OpenCV and Worker dependency setup succeeded. Hybrid backend/gateway code exists only as untested local edits; see the exact file list and review concerns in `PROGRESS.md`.
- The chosen draft approach uses surveyed ArUco floor/wall references and camera calibration to recover 3D pose, then analyzes each configured physical column. This is not yet a field-tested implementation of arbitrary painted-line recognition.
- No mobile integration, live deployment, new benchmark or new APK has been completed. Never describe version 0.2.2 as built or working.
- Latest request (2026-09-13) resumes implementation toward exact or near-exact counting of trays containing eggs using one hybrid flow. The earlier documentation-only checkpoint is superseded.
- Live checkout inspection found the previously described uncommitted hybrid draft absent. New standalone height/fusion policy is in backend/app/vision/hybrid.py with 20 synthetic unittest cases; API/mobile integration and image evidence extraction remain incomplete.
- The new core distinguishes egg-containing tray count from actual egg count. Trays times 30 is capacity unless every accepted tray is established to contain 30 eggs. Existing UI behavior is not changed by this core.
- Real surveyed calibration and per-layer occupancy evidence are still needed; the user was asked for the dataset folder path. See docs/hybrid-evidence-contract.md and the current correction at the top of PROGRESS.md.

## 2026-09-14 clarification — runtime, deployment and unfinished counting

The existing live backend works: app -> Cloudflare Worker -> Roboflow V2 ->
Worker -> app. Deployment is separately blocked because local Wrangler has no
usable authentication (whoami rechecked), not because Cloudflare inference is
offline. The prior device codes expired. Existing Worker secrets continue to
serve existing requests. Do not conflate browser login, CLI authorization and
runtime Roboflow inference.

The deployed Worker is the old photo-count baseline. Local optional-marker
model_spatial_v1 code preserves detections but deliberately has no accepted
inventory total; Python hybrid policy is not connected to live images/API.
Robust stack matching, occupancy, automatic evidence extraction and the Python
gateway remain to be implemented. Authentication alone will not fix these.
The app preflight currently rejects the old deployment's missing contract.

User now explicitly requests appending progress/previous context and pushing
GitHub. Preserve the source/tests/reports as an unfinished development checkpoint
on codex/hybrid-cell-counting; do not describe this push as deployment or an APK
release. Read previous_context.md for a concise resumption snapshot and the
latest PROGRESS.md append for verification and next steps.


## 2026-09-15 — latest ground-truth and architecture decision

User requested appending the discussion, relevant images and architecture and
pushing GitHub. See docs/COUNTING_ARCHITECTURE.md and
reports/user-100-tray-case-20260915/README.md for linked diagrams/evidence.
Keep physical truth separate from model output: five columns of 20 filled plus
one empty atop column 3 is user-reported inventory. Diagnose instance errors;
do not force any scan to 100. Markers remain optional. Calibrated geometry helps
pose/height; 3D displays evidence and cannot reveal hidden occupancy. Near-100%
requires held-out evaluation and coverage reporting, not one known-image match.
Original capture triplet is still missing. Preserve the rolled-back baseline
while developing the candidate hybrid; this publication is not a deployment.


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

## Device diagnosis update — 2026-09-16

USB ADB connection is authorized; Redmi Note 9 Pro has APK 0.2.2 (build 5).
App-specific live log capture started; failing scan reproduction requested.
Release app private cache is inaccessible through run-as. Connection success
alone does not establish that upload timeout or counting accuracy is fixed.

Physical-device retry result (2026-09-16): phone screen directly verified
96/89/98 model detections, projec-mutta/2, 9127 ms, count not verified. Upload
completed on this attempt. Historical timeout and 2/2/25 remain unexplained;
no claim of permanent fix. Bands remain offline research, not deployed.


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

## 2026-09-18 — production scope accepted; assigned-view demo executed

User's new production-architecture prompt supersedes the prior research-only
restriction. Requested next work: SceneSolver, deterministic SceneCertifier,
containerized Python, Cloudflare object/session integration and guided Android;
production promotion/APK still require the explicit live/device/truth gates.
User confirms no Python container host is available yet.

Immediate user-directed demonstration completed using supplied RIGHT, LEFT,
STRAIGHT files, despite user confirming they are separate arrangements/count
references. Exact originals/hashes and a pre-run tentative visual reference saved
in reports/production-20260918. Hashes match MUTAA image01/image02/image04; this
is not an unseen blind benchmark. No physical truth supplied.

Fresh unchanged projec-mutta/2 gateway request passed: RIGHT15 LEFT8 STRAIGHT34.
Local FastAPI candidate request passed: faces1/1/3; band candidates RIGHT14,
LEFT10, STRAIGHT8/11/16. Gateway15.17s plus local10.24s. No supported shared-stack
correspondence. X/Y, physical/eligible totals unresolved; verified=false and
recapture_required. No manual reference or expected totals fed into inference.
This is an attempted reconstruction, not a successfully reconstructed 3D scene.
The always-abstaining candidate cannot validate a production certifier. It also
did not establish an automatic unrelated-scene classification.

Saved gateway/candidate inputs and outputs, reconstruction.json, comparison.json,
demo-summary.json and report. Reproducible runner scripts/run_triplet_demo.py;
Ruff passed and live/local requests returned200 with result invariants checked.
No production logic changed; full automated suites were not rerun for this
report/runner-only change. No deployment, training or APK build. APK0.2.2+5.

Next: implement requested production solver/certifier/service/mobile work; obtain
an unchanged triplet and independent per-cell truth for valid 3D regression.
Prepare hosting only when a target is available. Do not replace unobservable
geometry/occupancy with a known-total correction or forced verification.

## 2026-09-18 — current device and publication state

The phone was reported as connected, but restarting ADB and running adb devices
-l returned an empty device list. Treat device capture, APK logs, camera
quality, upload timing and live inference as unverified until an authorized
serial is visible. No agent patch for live lighting/orientation measurement or
the preview endpoint is present in the tracked checkout.

The next implementation reference is the “Live capture pilot and device gate”
section in docs/COUNTING_EXECUTION_PLAN.md: enumerate an authorized device,
capture one reproducible scan with logs, validate the three uploaded files and
server response, then add local quality/orientation gates and bounded preview
sampling. These gates may reject unusable evidence; they cannot prove hidden
trays or egg occupancy. Preserve the old no-ID route and keep verified totals
disabled until same-scene, independently counted validation data exists.
