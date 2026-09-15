# Current development context

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
