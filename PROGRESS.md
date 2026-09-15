# Progress

Updated: 2026-09-15. Read this file before modifying the repository.

## Development resumed — 100-tray case, 2026-09-15

- User authorized proceeding and confirmed five columns of 20 egg-containing
  trays plus one empty on top of middle column (physical per-column 20/20/21/20/20).
  Saved attachments with hashes and user-reported truth in
  reports/user-100-tray-case-20260915/reference.json. This is not independently
  recounted inventory; keep separate from the earlier 32-tray img04 benchmark.
- Inspected the user-supplied WhatsApp folder. It contains two screen photos and
  the blue-annotated scene, not the original LEFT/RIGHT/STRAIGHT captures. Asked
  for those originals or a fresh triplet; no confirmed triplet yet available.
- Fixed local CountingService: individual egg_tray boxes cannot enter the
  whole-stack layer counter even with the experimental provider alias. Updated
  API regression test verifies typed unsupported_model_output rather than false
  verification. Production Cloudflare baseline remains unchanged.
- All 44 backend tests passed using the Python standard OS fallback after this
  host's WMI query failed (0x8007000e). Initial WMI-disabled retry failed because
  platform expected an exception, not None; final harness raised OSError from
  _wmi_query, with no application logic patched. Targeted Ruff checks passed.
- Added runnable scripts/evaluate_100_tray_layers.py using existing rectification,
  layer extraction and overlays. Manual face ROIs on the 675x507 supplied image
  produced 40/10/10/11/11 physical-layer candidates versus 20/20/21/20/20.
  Column-2 overlay visually skips alternating rows despite quality 0.86. This
  demonstrates layer-period ambiguity; quality is not calibrated count accuracy.
  No global factor, truth-based pitch or automatic eligible total applied.
- Next: original captures/raw detections, diagnose per-tray errors and layer
  harmonics together, improve stack localization and spacing ambiguity handling,
  then cross-view identity/occupancy integration. No training, deployment or APK
  rebuild in this development checkpoint. Full hybrid objective remains incomplete.

## Latest production state — baseline rollback, 2026-09-15

Planning update: user supplied screenshots reporting V2 84/90/87 and a scene
photo; states 100 trays plus one extra empty. Interpreted as 100 egg-containing
and 1 empty, user-reported (not independently recounted). Count errors 16/10/13;
no instance precision can be derived. Saved phased diagnosis, retraining,
row/column/layer reconstruction, optional marker and held-out validation plan in
docs/100_TRAY_SCENE_PLAN.md. Original three capture files, raw detections and
per-stack/empty-tray labels are still needed to identify causes. No model training,
backend redeployment or APK change made for this planning request. Preserve the
32-tray img04 benchmark separately; production remains the rolled-back baseline.

- User explicitly requested the older baseline backend without cell IDs.
  Wrangler deployment history identified the immediately preceding version as
  621a5a9c-f486-455f-9a15-0965ca3a710f (2026-08-31). Rolled back to that exact
  version with `wrangler rollback <version> --yes`; CLI confirmed 100% traffic.
- Replaced version 0519381f-b99e-4015-8279-cb2c0f99f7f2. Local source was not
  reverted; do not redeploy it unintentionally, since it restores the newer API.
- Live /health returned status ok and /ready identified Roboflow projec-mutta/2.
  Evidence: reports/cloudflare-rollback-20260915/. Post-rollback image uploads
  could not be verified: curl and httpx both hit connection resets during TLS.
  No successful fresh inference or no-ID upload is claimed for this rollback.
  The same historical baseline previously passed inference in the saved report.
- The 0.2.2 APK requires model_spatial_v1 and will reject the restored baseline
  health response. Rolling back the server does not remove mandatory UI fields
  from 0.2.1 either. A baseline-compatible APK is required; none rebuilt here.
- Previous successful optional-marker deployment entries below are historical
  and superseded by this user-requested rollback. Hybrid work remains preserved.

## Latest deployment checkpoint — 2026-09-14

- User-approved OAuth succeeded; Wrangler deployment access is now verified.
  Earlier authentication-blocked statements below are historical.
- Deployed egg-tray-counter-api using Wrangler 4.125.0 deploy --keep-vars.
  Version 0519381f-b99e-4015-8279-cb2c0f99f7f2, source checkpoint
  e92babb97ba84400dba81ad71b288f8f304e8e18. URL:
  https://egg-tray-counter-api.rahultech72216.workers.dev.
  Existing variables/secrets preserved. Compile/dry-run/all 11 tests passed.
- Live health advertises model_spatial_v1; readiness identifies projec-mutta/2.
  No-floor-ID live request returned HTTP 200 with empty echoed cell_ids and
  valid spatial detections/counts 29/9/12 for separate benchmark scenes.
  Response contract/model, box validity/count consistency and null inventory
  totals verified. Evidence: reports/cloudflare-deployment-20260914/.
- APK 0.2.2's backend-contract mismatch is RESOLVED; no APK rebuild required
  for this server update. No physical Android-device scan was performed.
- hybrid_ready remains false. Exact hybrid counting, robust physical-stack
  matching, occupancy and image-to-hybrid integration remain unfinished. This
  smoke test is not a same-scene three-view accuracy evaluation.
- Next: implement those missing vision/integration components, evaluate held-out
  same-scene captures with checked truth and run device tests. Preserve the
  known signing-key limitation. Earlier deployment blockers are superseded.

## Latest artifact checkpoint — 2026-09-14

- After the prior process ended without an APK, resumed the cached release build successfully. Root artifact egg-tray-counter-0.2.2-hybrid.apk is version 0.2.2+5, 59,631,396 bytes, SHA-256 1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b. Manifest, APK v2 signature and ZIP CRC verified. Full evidence: reports/APK_0.2.2_BUILD.md.
- This is an incomplete DEVELOPMENT hybrid build. Optional-marker capture/model diagnostics are implemented; automatic physical-stack matching, occupancy evidence and image-to-hybrid integration remain unfinished. No near-100% claim is supported.
- The debug signing certificate differs from the old 0.2.1 APK. It cannot update that installation in place; preserve existing inventory data and obtain the original signing key for an upgrade. No device install/uninstall was attempted; adb listed no devices.
- Checks: Flutter analysis clean, 16 mobile tests passed; 44 backend tests passed; Worker tsc/dry-run/11 tests passed; Ruff and whitespace checks passed. These validate code/build behavior, not field counting accuracy.
- Fresh deployed V2 inference returned 29 versus img04 visual reference 32 (error 3, 9.375%). Instance precision and three-view hybrid accuracy remain unavailable. See reports/manual-reference-20260913/LIVE_EVALUATION.md.
- Wrangler whoami is still unauthenticated on 2026-09-14. Existing deployment uses the old contract and is incompatible with the new mobile preflight. No new deployment, model promotion, commit or push occurred.
- Next: obtain original signing key for in-place upgrades, complete CLI authentication and deploy the tested compatible backend, obtain real same-scene three-view photos with checked counts/occupancy, implement and evaluate automatic association/occupancy/hybrid integration, then perform device end-to-end tests. Plan and reusable prompt: docs/COUNTING_EXECUTION_PLAN.md.

## Latest execution checkpoint — optional markers and reference evaluation

### Continuation verification (2026-09-13, supersedes setup blockers below)

- Flutter 3.47.4 / Dart 3.13.3 now run. Android platform 36, build-tools 36.0.0 and NDK 28.2.13676358 are installed under work/toolchains/android-sdk; user authorized SDK license acceptance. Android tools archive SHA-256 verified against vendor: 90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a.
- Mobile pub get succeeded, analysis has no issues after removing one redundant null fallback, and all 16 Flutter tests passed. Source version bumped to 0.2.2+5. Release APK build is running through initial Gradle setup; no artifact verified yet. Gradle 9.3.1 archive hash matches vendor 17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43.
- All 44 backend tests passed again; Ruff passed the new hybrid core, tests and evaluator. Worker npm run check passed tsc, Wrangler deployment dry-run and all 11 runtime tests. Git diff --check passed with line-ending warnings only.
- Fresh inference through the existing deployed Worker succeeded (HTTP 200), V2 returned 29 for img04 against reference 32: absolute error 3, relative error 9.375%. This replaces the earlier limitation that only saved RF output was available. See reports/manual-reference-20260913/LIVE_EVALUATION.md and raw JSON. The request used three different benchmark scenes to exercise required upload fields; it is NOT a multi-view accuracy test.
- Existing live health returns only status ok; ready reports configured V2. Actual inference is now verified through that deployment, but its old baseline contract is incompatible with the changed app. Wrangler whoami remains unauthenticated after the user-approved device flow timed out. No deployment or model promotion occurred.
- Exact hybrid remains incomplete: automatic physical-stack association and per-layer occupancy evidence are not integrated. The new Worker path provides unresolved model evidence, not a certified count. Asked for a real same-scene three-view folder and checked physical tray total.
- After midnight 2026-09-14: a second Wrangler device authorization also timed out; do not reuse either expired code. No Android device/emulator is attached (adb devices empty). APK build remains active in Gradle dependency/configuration compilation; the JVM is making progress, but available RAM is under 1 GB. No new APK has been produced or verified.

Build continuation (PowerShell from mobile, after checking for an existing build process): set ANDROID_HOME and ANDROID_SDK_ROOT to the absolute work/toolchains/android-sdk directory; set JAVA_TOOL_OPTIONS to `-Djavax.net.ssl.trustStoreType=Windows-ROOT -Djavax.net.ssl.trustStore=NONE`; run `..\work\toolchains\flutter\bin\flutter.bat build apk --release`. Version is 0.2.2+5 and signing still uses the existing debug key configuration. If a package is produced, verify manifest, signature and SHA-256 before copying/delivering it. The current source is an incomplete development counter, not a near-100% hybrid release.

- Restored backend requirements into work/vision-deps using bundled Python 3.12 and the official PyPI index. All 44 backend tests passed (dependency deprecation and pytest cache-write warnings). The 11 Worker runtime tests passed using Node TypeScript transformation; full tsc/Wrangler checks are still blocked by npm installation failures.
- Mobile capture now accepts omitted floor IDs; optional IDs remain validated. Mobile API requests model_spatial_v1; Worker accepts that contract without markers, retains spatial model boxes and returns explicitly unresolved diagnostic counts. This is NOT an operational exact-count hybrid. Mobile edits/tests have not yet run under Flutter.
- Saved manual reference and reproducible evaluation script. Reference: 32 visible trays (16 + 16), non-blind visual recount. Historical RF replay: 29, error -3, absolute error 9.375%. Fresh assisted layer-only experiment: 23, error -9, absolute error 28.125%. Exploratory RF-guided layer candidate: unresolved left face, 14 on right, no total. No operational three-view hybrid accuracy or instance precision/recall result exists. No benchmark labels changed.
- Created docs/COUNTING_EXECUTION_PLAN.md with ordered work and reusable prompt. Saved a user-requested memory note for the visual reference, including its limitations.
- User reports service authentication complete; browser tab inventory contains the Cloudflare dashboard and Roboflow workspace. Repeated page-control failures (CDP focus/Page.enable and webview attachment timeouts) prevent live inference/deployment verification. Preserve the sessions; do not ask for private credentials in chat.
- APK setup underway: Flutter stable source cloned to work/toolchains/flutter but checkout initially failed on Windows long paths. core.longpaths enabled locally; restore is running/needs verification. Android command-line tool download was resumed after a nearly-complete timeout; verify vendor SHA-256 before extraction. No new APK exists.
- Worker npm ci retries fail with npm exit-handler/network errors, including an escalated retry; inspect latest log and use a supported package manager/runtime. No deployment, model promotion or source push performed.

### Immediate continuation steps

1. Finish/verify Flutter checkout and Android SDK tool hash/extraction, then resolve required JDK/SDK licenses and run Flutter checks/build. Do not label diagnostic-only source as a completed hybrid APK.
2. Recover browser control or verified Wrangler/API access using existing authenticated sessions; do not deploy diagnostic-only changes as exact counting.
3. Improve automatic stack-face localization, tray rim counting and cross-view association against development images; handle occupancy explicitly. Keep saved manual truth outside inference inputs.
4. Re-run frozen and held-out multi-view evaluation; report count errors, rejected coverage, assistance and missing precision labels honestly. Complete image-to-hybrid integration before claiming an exact backend count.

## Current checkout correction — 2026-09-13

- Verified starting HEAD: `a6c4263b9f211068572d6e510847d077a9cdec53`, branch `codex/hybrid-cell-counting`; starting working tree was clean.
- The older interrupted hybrid source listed below is ABSENT from this checkout. Treat that section as history, not present implementation. No local backend virtualenv or Worker node_modules was found. The installed Python 3.14 and parent virtualenv lack pytest/OpenCV; Flutter is not on PATH.
- Read AGENTS.md, context.md and the handover/digest/continuation documents, plus the relevant prior conversation. Root previous_context.md and prompt.md are absent; context.md and previous_chat.md supply continuation requirements.
- Implemented new standalone `backend/app/vision/hybrid.py`: uncertainty-aware measured height candidates, stable column identity, exact evidence agreement, distinct image/pose checks, explicit per-layer egg occupancy, and complete-scope totals. It is NOT connected to API/mobile and does NOT detect image markers or egg occupancy.
- Added `backend/tests/test_hybrid_core.py`: 20 unittest cases passed using Python 3.14, covering measurement ambiguity, bounds, disagreement, missing columns, empty trays, unknown occupancy, duplicate images/columns and camera pose consistency. Full backend/Worker/Flutter suites have not run in this checkout.
- Added `docs/hybrid-evidence-contract.md` with required trusted vision inputs and held-out evaluation rules. No new field accuracy result exists.
- Final core rerun: all 20 tests passed after strict boolean validation. Python syntax checks passed; git diff --check passed for tracked edits (line-ending normalization warnings only). Recomputed historical summary.json metrics: 10 images, 2 exact, MAE 22.9; no inference was rerun.
- Existing artifacts, model and endpoints are unchanged. No APK build, deployment, live readiness verification, commit or push in this session. Earlier APK hash and live-service checks below remain historical reports.

### Next steps from this checkout

1. Obtain real three-view warehouse photographs with manually verified per-column tray/occupancy counts, surveyed floor/wall references and camera calibration. Asked the user for the folder path; no answer received yet.
2. Restore a compatible backend test environment and Worker dependencies, then implement and test image-to-evidence geometry, spatial RF association and occupancy adapters against those measurements. Never mark generic egg_tray detections as occupancy proof.
3. Connect the tested evidence component to an authenticated Python service and Worker gateway, including calibration identity and idempotency, then unify mobile capture/results and manual review.
4. Evaluate untouched held-out scenes with exact counts, MAE and acceptance/rescan coverage. Calibrate evidence thresholds from development data; do not claim near-100% from unit tests.
5. Verify service authentication/readiness, run all platform checks, then build/deploy the requested 0.2.2+5 APK and record hash/signature/device evidence. Those delivery goals remain incomplete.

## Completed work (historical checkpoint)

- Inspected repository history and current mobile/Worker counting flow at commit `8073dbe`.
- Read the user's continued-development handover and existing technical handover.
- Confirmed that the current app splits photo detection and manual Grid + Height into separate modes; automatic floor and wall marker analysis is not implemented.
- Added persistent working rules in `AGENTS.md` and current requirements in `context.md`.
- Fetched origin and confirmed main matched `8073dbe` (0 commits ahead/behind); created `codex/hybrid-cell-counting`.
- Installed the existing backend requirements plus pytest/Ruff into `.venv`; verified OpenCV 4.12.0 exposes `aruco`.
- Ran `npm ci` and `npm run types` in `cloudflare-worker` successfully. npm reported 3 high-severity dependency advisories; these have not been investigated yet.
- Began hybrid implementation in local working-tree files listed below. These edits are incomplete and untested, and are NOT part of this documentation-only checkpoint.
- No model promotion, deployment, or new APK build has been performed.

## Interrupted implementation (local only, not ready to deploy)

- New `backend/app/services/hybrid.py`: layout/camera/marker validation, ArUco floor/wall pose recovery, projected column ROIs, height/rail evidence, RF spatial assignment and per-cell fusion. Draft only; no new runnable tests yet.
- Modified `backend/app/config.py`, `main.py`, `api/routes.py`, `repository.py`: hybrid configuration, optional service setup, gateway token validation, camera profile checks, response routing and reuse of idempotency storage.
- Modified `backend/app/providers/roboflow.py`: retain `egg_tray` boxes for hybrid mode, fixed overlap setting, additional numeric validation, 401 authentication handling.
- Modified `cloudflare-worker/src/index.ts`: draft HTTPS gateway forwarding, upstream token, upload bounds, explicit hybrid-request routing, no silent fallback for hybrid clients.
- Mobile source has not been updated. It still requests the old contract and shows separate modes. There is no end-to-end hybrid path yet.
- Review the draft geometry and fusion before relying on it: empty-cell handling, occlusion/completeness, camera-profile identity, calibration tolerances, rail-vs-rim distinction, marker visibility, and input validation need tests and field evidence. The one-tray RF tolerance is a draft policy, not validated accuracy.
- New `/ready` draft deliberately reports configuration rather than claiming a successful live inference. Authenticated Roboflow readiness still needs implementation/verification.
- This documentation push does not contain these source edits. On another machine, resume from the plan or obtain the local working tree; do not assume the draft is on GitHub.

## Verification results

- Existing APK ZIP integrity passed; embedded manifest is version `0.2.1`, versionCode `4`, package `com.dharani.eggtray.egg_tray_counter`, min SDK 24, target SDK 36.
- APK includes `floor-cells-wall-reference.png` and arm64-v8a, armeabi-v7a, x86_64 native libraries.
- Live Worker `/health` returned HTTP 200 and `{"status":"ok"}` after retry with a browser user agent. It lacks `scan_contract: cell_identity_v1`, which the existing APK requires.
- Live `/ready` could not be verified: connection failure / Cloudflare 403 on probes. Do not report it as ready.
- Direct Roboflow `projec-mutta/2` responded HTTP 401 without credentials. This confirms a reachable authentication gate, not successful inference.
- Saved repository logs report three successful emulator cold launches; the handover reports 14 Flutter tests and signature verification. These have not been rerun on this computer.
- Frozen historical RF-only benchmark: V2 2/10 exact, MAE 22.9 trays. No new height or hybrid accuracy evaluation exists.

## Current artifacts

- Latest existing APK: `egg-tray-counter-0.2.1-grid-pilot.apk`.
- Version: `0.2.1+4`; size: 59,631,400 bytes.
- SHA-256: `c4459142ec145510de0cc961208dd78ff0357c605eb05d55de15af252413b6a2`.
- Configured model: `projec-mutta/2` (RF-DETR Medium), unchanged.
- Public API: `https://egg-tray-counter-api.rahultech72216.workers.dev`.
- Requested next artifact: `egg-tray-counter-0.2.2-hybrid.apk`; not built.

## Blockers and open prerequisites

- Cloudflare and Roboflow browser sessions both opened at login pages; no authenticated service session was available.
- Flutter, Android SDK/ADB, and the earlier `Documents/Codex/toolchains` installation were not found in the checked locations. Python, Node, and Java are available. Toolchain setup is still needed.
- Worker and Python dependencies are now installed locally; Flutter/Android build tools remain unavailable in checked locations.
- Flutter release metadata and an attempted SDK URL returned HTTP 404. No SDK was downloaded; resolve the official archive location/version before building.
- `npx wrangler whoami` explicitly reported unauthenticated. Cloudflare and Roboflow login tabs were reopened at the user's request; successful sign-in is not yet verified.
- Real calibrated marker photographs and camera/depth calibration have not yet been located. An illustration is not metrology or test evidence.

## Exact next steps

1. Read `context.md` and `previous_chat.md`; inspect git status and the local draft files above. Preserve them while synchronizing the documentation branch.
2. Add runnable tests for calibration validation, synthetic marker pose, perspective height, RF assignment, occlusion, distinct views, fusion disagreements, idempotency and gateway failures. Run Ruff and backend/Worker checks; fix the draft before proceeding.
3. Check the user's Cloudflare/Roboflow sign-in state and complete CLI authorization as needed. Do not ask for private keys in chat.
4. Obtain or construct a real measured layout/camera profile and select an authenticated Python hosting runtime. Do not use the illustration as calibration. Finish server-side geometry/fusion and gateway wiring.
5. Integrate this into one mobile scan/result flow, preserve manual corrections as fallback, and distinguish network failure, incompatible backend, and unavailable inference in status.
6. Test geometry/association/fusion and gateway contracts, evaluate untouched warehouse benchmark assets, and report unavailable height evidence rather than inventing a score.
7. Deploy only after local verification and authenticated runtime availability; verify `/health`, `/ready`, authenticated Roboflow inference and a full scan.
8. Run requested Flutter clean/pub get/analyze/tests, backend and Worker checks, build a new APK, verify version/signature/hash and emulator scan if available.
9. Update this file and technical handover, commit legitimate source changes, push the branch/PR and publish the verified APK when possible.

## Documentation checkpoint

The user requested preserving the chat and pushing it to GitHub. `previous_chat.md` records the available user/assistant conversation; runtime instructions and raw tool logs are excluded. `context.md` contains the concise continuation context. Only these documentation files and `AGENTS.md` are intended for this checkpoint. Documentation verification and push result are recorded below after execution.

Documentation verification: all four files read successfully; both supplied continuation briefs are preserved in full, transcript placeholders are resolved, and targeted credential-pattern checks found no matches. Git whitespace checks passed. Checkpoint commit `a95a162a7af918a3f393db2099abfdd53db1ca57` was successfully pushed to `origin/codex/hybrid-cell-counting`. Git confirmed creation of the remote branch and tracking configuration. Unfinished hybrid source remains local and uncommitted.

## 2026-09-14 — backend clarification and requested GitHub checkpoint

The user asked why deployment is blocked while inference works, whether the
backend routes directly to Roboflow, why exact hybrid counting is unfinished,
what to do next, and to append the progress/previous context and push to GitHub.

- Live checks repeated: /health returns status ok; /ready reports ready and
  projec-mutta/2. Wrangler whoami again explicitly reports unauthenticated.
  These are different capabilities: the existing deployed Worker can serve
  requests using its server-side Roboflow credential even though this machine
  lacks authorization to replace the Worker. Browser sign-in is not proof that
  Wrangler completed its own authorization. Previous device flows expired.
- Verified request path: Android app -> Cloudflare Worker -> Roboflow serverless
  projec-mutta/2 -> Worker response -> app. The APK does not call Roboflow with a
  bundled private key. The deployed processing mode observed in the saved live
  response is cloudflare_roboflow_egg_tray_baseline. It uses whole-photo count
  agreement/mismatch logic, not the requested physical-stack hybrid.
- The current Python service has a separate layer-counting path with spatial-order
  association. The newly added calibrated hybrid core has no API/image adapter
  and the live Worker does not call it. Automatic robust cross-view identity,
  per-tray egg occupancy and optional-marker evidence extraction/integration are
  unfinished implementation work, not merely authentication blockers.
- The 0.2.2 app expects model_spatial_v1, which the live health response does not
  advertise. Deploying the current local Worker would restore that contract and
  expose unresolved model evidence; it would NOT complete exact hybrid counting.
  APK compilation and 71 passing tests do not prove inventory accuracy.
- Remedy for deployment: complete Wrangler OAuth on the deploying machine, or
  configure a narrowly scoped Cloudflare deployment token through a local secret
  environment/GitHub Actions secret, or connect the repository using Cloudflare
  Workers Builds. No private token belongs in chat, source or the APK.
- Remedy for counting: finish the image-to-evidence adapter and Python gateway,
  robustly associate physical stacks across views, classify visible occupancy,
  fuse model/layer/calibrated-height evidence with explicit uncertainty, then
  evaluate held-out same-scene three-view captures with checked per-stack counts.
  Missing floor IDs must use the model/layer route. Occluded/ambiguous content
  cannot be certified from photo-count agreement.
- Retained evidence: fresh V2 29 vs visible manual reference 32 (error 3, 9.375%);
  assisted layer-only 23; guided hybrid unresolved. No measured hybrid precision
  or three-view exact-count accuracy exists. Existing references stay frozen.
- This GitHub checkpoint includes the actual source, tests, plan and reports,
  explicitly labelled unfinished, to avoid a handover referring to absent code.
  The APK remains a local ignored artifact, not a GitHub release upload.
  previous_context.md is newly created because no file with that name existed;
  existing context.md and previous_chat.md history is preserved.

Authentication references: https://developers.cloudflare.com/workers/wrangler/commands/general/
and https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/.

Publication verified: checkpoint bc0a0e67d947c2a06badc6db5b2e497b64e2fb1b
successfully pushed to origin/codex/hybrid-cell-counting. git ls-remote returned
the identical SHA and the working tree was clean after that push. All 28 source,
test, context and report files in the checkpoint are now on GitHub. Staged
whitespace and targeted credential-pattern checks passed. This is source
publication only; Cloudflare was not deployed and the APK was not uploaded as
a release asset. This follow-up documentation records the verified push outcome.


## 2026-09-15 — requested evidence and architecture publication

Appended the ground-truth discussion and linked source images, diagnostic overlays
and current/proposed architecture in docs/COUNTING_ARCHITECTURE.md and the case
README. Preserved user-reported 100 filled + 1 empty separately from inference
and the older 32-tray reference. Ground truth is for labels/scoring, never a
runtime correction factor. Optional markers aid pose/scale; a 3D display cannot
recover hidden occupancy by assumption.

This checkpoint includes the pending local stack-face guard/regression test,
reproducible layer diagnostic and rollback evidence. Earlier verification: 44
backend tests and targeted Ruff passed; the real layer diagnostic failed with
40/10/10/11/11 candidates. No new training, APK build or deployment is claimed.
Current recorded production version remains 621a5a9c-f486-455f-9a15-0965ca3a710f;
local APK remains 0.2.2+5 and incompatible with that baseline preflight.

Next: obtain original LEFT/RIGHT/STRAIGHT images/raw predictions; label per-tray
errors, fix localization/layer ambiguity, integrate occupancy and cross-view
identity, evaluate held-out scenes, then build/test a compatible APK. Publish
this checkpoint on codex/hybrid-cell-counting after evidence/whitespace checks.

Publication checks: all three supplied image SHA-256 hashes match reference.json;
case JSON parses and local architecture/report links resolve. Staged whitespace
and targeted credential-pattern checks passed. Remote branch was fetched and
matched local HEAD before this checkpoint commit. Prior 44-test result retained;
documentation/image append does not introduce new runtime changes.
