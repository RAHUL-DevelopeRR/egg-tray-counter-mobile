# Current development context

Updated: 2026-09-12. Read with `PROGRESS.md` before work.

The user requests continued development, not a rewrite. Existing repository:
`https://github.com/RAHUL-DevelopeRR/egg-tray-counter-mobile`.

## Latest clarified requirement

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

- Full available user/assistant conversation is preserved in `previous_chat.md`, with the supplied continuation brief included. Read it when the concise context here is insufficient.
- The user asked whether the existing three-angle Roboflow analysis was enough. The answer was that three views are useful but not independent proof of correctness; the user then explicitly said, “Okay do the hybrid verification.”
- The user authorized opening Cloudflare and Roboflow sign-in pages. Tabs were opened for the user; authenticated access is not yet confirmed.
- Current branch: `codex/hybrid-cell-counting`, based on main at `8073dbe`. Remote main was fetched and matched the local starting commit.
- Backend/OpenCV and Worker dependency setup succeeded. Hybrid backend/gateway code exists only as untested local edits; see the exact file list and review concerns in `PROGRESS.md`.
- The chosen draft approach uses surveyed ArUco floor/wall references and camera calibration to recover 3D pose, then analyzes each configured physical column. This is not yet a field-tested implementation of arbitrary painted-line recognition.
- No mobile integration, live deployment, new benchmark or new APK has been completed. Never describe version 0.2.2 as built or working.
- Latest request is a documentation checkpoint and GitHub push. The checkpoint includes documentation only; unfinished source remains local.
