# Current development context

Updated: 2026-09-14. Read with `PROGRESS.md` before work.

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
