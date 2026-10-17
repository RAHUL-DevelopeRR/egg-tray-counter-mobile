# Codex prompt — 3D reconstruction, API integration, emulator run

Written 2026-10-07 against branch `codex/hybrid-cell-counting` (HEAD 58aeac1 plus
uncommitted AWS reconstruction work). Paste everything below the line into Codex.

---

You are continuing the Egg Tray Counter repository at
`C:\Users\DELL\Downloads\self-enhancing-agent-framework\egg-tray-counter-mobile`,
branch `codex/hybrid-cell-counting`. Follow `AGENTS.md`: read `PROGRESS.md` (top
three entries) and `context.md` (top section) before changing anything, and
update both before you finish.

## Goal of this task

Make the deployed 3D reconstruction usable end to end:

    APK (photo upload) -> Cloudflare Worker (new route) -> AWS Lambda
    /candidate/reconstruct -> Worker -> APK "3D evidence" screen

then run it in an Android emulator using egg tray photos already on this
laptop, and show a 3D view built from them. This is a diagnostic feature. It
must not produce or display a verified tray count.

## Current state (verified 2026-10-07, do not redo)

- AWS Lambda `egg-tray-vision-pilot`, ap-south-1, account 608942062000, image
  `pilot-20261007` (digest sha256:4ef6034d8adb553478d86f73a131d6c8dff3ba943cf1d49a063b11315cda70fb).
  Function URL: https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/
- `GET /health` is public and advertises `two_view_sfm_diagnostic_v1`.
- `POST /candidate/reconstruct` (multipart `first`, `second`; JPEG/PNG; distinct;
  equal dimensions; <= 2 MB and <= 12 MP each; one request per process, else 429)
  returns camera poses and sparse points for assumed focal factors 0.7/1.0/1.4.
  Code: `backend/app/vision_service.py`, `backend/app/vision/reconstruction.py`.
- `POST /candidate/count-3d` is the stack/band diagnostic (always null inventory).
- Every non-health route needs `Authorization: Bearer <token>`. The token is in
  SSM SecureString `/egg-tray-vision-pilot/service-token`. AWS CLI 2.37.10 is
  installed per-user and was authenticated through the user's browser.
- Known real result: `reports/warehouse-20260923/input/image-1.jpg` + `image-2.jpg`
  give 175 strict matches, ~121-125 inliers, 76/94/100 points (AWS). Evidence in
  `reports/aws-reconstruction-deploy-20261007/`.
- Production: Worker `egg-tray-counter-api` (cloudflare-worker/src/index.ts) calls
  Roboflow `projec-mutta/2` on `/v1/scans/count`, archives originals to private
  R2, `hybrid_ready=false`. The APK default URL is
  `https://egg-tray-counter-api.rahultech72216.workers.dev` (settings_store.dart).
- APK 0.3.3+9 (`mobile/`, Flutter, `photo_upload_pane.dart` already supports
  picking LEFT/RIGHT/STRAIGHT files). No 3D screen exists. No 3D package is in
  pubspec.yaml.
- Emulator: BlueStacks Pie64 via ADB `127.0.0.1:5555`. APK 0.3.3+9 showed a white
  screen (EGL_BAD_MATCH in logs). Renderer was switched to OpenGL-only and
  restarted; the app has not been re-tested since. ADB is at
  `work/toolchains/android-sdk/platform-tools/adb.exe`; ANDROID_HOME/ANDROID_SDK_ROOT
  = `<repo>/work/toolchains/android-sdk`; Java needs
  `JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStoreType=Windows-ROOT -Djavax.net.ssl.trustStore=NONE`.

## Photos available on this laptop

| Path | Use |
|---|---|
| `reports/warehouse-20260923/input/image-1.jpg`, `image-2.jpg` | Primary positive pair (overlapping wide views, known to reconstruct) |
| `reports/warehouse-20260923/input/image-3.jpg`, `image-4.jpg` | Side views; try pairs with 1/2 and record results |
| `reports/two-view-20260924/input-1.jpg`, `input-2.jpg` | Negative control (2 strict matches; must fail gracefully, no pose) |
| `reports/mutaa-20260916/originals/` (35 images) | Additional pairs; only pair images the MUTAA README says share a scene |
| `datasets/field-2026-10/scene-*/` | New user captures with hand counts, if present; use these first when they exist |

Never modify originals. Record SHA-256 of every input you use.

## Work to do, in order

### 1. Backend response for rendering (backend/app/vision/reconstruction.py, vision_service.py)
- Add a compact, render-ready section to the reconstruct response: per hypothesis,
  at most 2,000 points (deterministic downsampling), each `[x, y, z, r, g, b]`
  with colour sampled from the first image; both camera centres and orientations;
  the scene bounding box; median reprojection error; inlier count.
- If the photos carry EXIF focal length (FocalLength + FocalLengthIn35mmFilm or
  sensor size), compute a focal estimate from it and return it as an extra
  hypothesis labelled `exif_focal`. Keep the assumed 0.7/1.0/1.4 hypotheses.
  Never label any hypothesis "calibrated" unless it came from real intrinsics.
- Add a top-level `status`: `reconstructed` | `insufficient_matches` |
  `pose_failed`, and a human-readable `reason`. The negative control must return
  HTTP 200 with `insufficient_matches` or `pose_failed`, not a 500.
- Keep `physical_trays: null`, `verified: false`, `scale: "arbitrary_unit_baseline"`.
- Add tests: response shape, downsampling cap and determinism, negative-control
  status, EXIF hypothesis present only when EXIF exists, no count fields non-null.
- Redeploy the Lambda only after local tests pass, using the same process as
  `reports/aws-reconstruction-deploy-20261007/` (temporary builder or CodeBuild,
  then remove temporary resources and record digest). Ask the user before
  creating any new billable resource type.

### 2. Worker route (cloudflare-worker/src/index.ts) — staging only
- Add `POST /v1/reconstruct` that validates two images (type, size, distinct
  SHA-256), archives them to R2 under `reconstruct/<scan_id>/<first|second>/<sha>`,
  forwards them to the Lambda with the bearer token from Worker secret
  `VISION_SERVICE_TOKEN` and `VISION_SERVICE_URL` var, and returns the Lambda
  JSON plus `scan_id`, input hashes and timing. Map Lambda 401/429/5xx to clear
  error codes. Add `"reconstruct_v1"` to `/health` `scan_contracts` on this route's
  Worker only.
- Do NOT change `/v1/scans/count` or any existing behaviour.
- Deploy to a separate staging Worker (e.g. `egg-tray-counter-api-staging`, its
  own wrangler env), not the production Worker. Ask the user before running
  `wrangler deploy` and before `wrangler login` if auth is needed.
- Set the secret without printing it, e.g. pipe
  `aws ssm get-parameter --with-decryption ... --query Parameter.Value --output text`
  into `npx wrangler secret put VISION_SERVICE_TOKEN --env staging`.
  The token must never appear in source, logs, reports, chat output or the APK.
- Add Worker tests: validation, forwarding with auth header, error mapping,
  existing routes unchanged.

### 3. APK 3D evidence screen (mobile/) — version 0.3.4+10
- New flow from home: "3D reconstruction (diagnostic)". Pick two photos with the
  existing file_selector pattern or capture two with the camera.
- Photo constraints enforced before upload: two different files, same pixel
  dimensions, not WhatsApp-compressed (warn if EXIF missing), 1x/main camera when
  captured in-app, existing tilt/blur/exposure gates for captured photos.
  If a file exceeds 2 MB / 12 MP, downscale both identically on-device and
  record that in the request (geometry stays consistent; say so in the UI).
- New `ApiClient.reconstruct()` against the configured base URL; check `/health`
  for `reconstruct_v1` first and show a clear message if absent.
- Render the 3D view with a Flutter `CustomPainter` and a simple orbit/zoom
  camera (perspective projection, drag to rotate, pinch to zoom). Do not add a
  heavy 3D dependency. Draw coloured points, the two camera frusta and the
  bounding box. Hypothesis selector (0.7 / 1.0 / 1.4 / EXIF if present).
- Persistent banner on this screen: "Diagnostic 3D evidence — arbitrary scale,
  feature points are not trays, no count". Never display a tray total here.
- If status is not `reconstructed`, show the reason and suggest a recapture
  with more overlap.
- Point the staging APK at the staging Worker via the existing settings URL
  field, not a hard-coded change to the production default.
- Flutter tests: response parsing, constraint checks, projection maths,
  screen shows banner and never a count.

### 4. Emulator run
- Retest BlueStacks (OpenGL-only) with the new APK. If it still renders white,
  record the evidence and try an Android Studio AVD with the SDK above (ask the
  user before downloading a system image).
- `adb push` the photo pairs to `/sdcard/Download/egg-tray-test/`.
- Run positive pair, negative control and at least two further pairs. For each,
  save: emulator screenshot of the 3D screen (two rotations), the Worker JSON,
  timing, input hashes.
- Confirm Worker-relayed JSON equals a direct authenticated Lambda call for the
  same inputs (ignoring timing fields).

## Verification required before you report done
- `pytest` backend suite, Worker `npm test` + TypeScript compile + `wrangler deploy --dry-run`,
  `flutter analyze` and `flutter test` — all pass, with counts reported.
- APK built, signature/version checked (0.3.4+10), installed on the emulator.
- Live: staging Worker `/health` lists `reconstruct_v1`; unauthenticated direct
  Lambda call still 401; production Worker `/health` unchanged.
- Save everything in `reports/reconstruct-integration-<YYYYMMDD>/README.md`
  with a table of every pair: hashes, status, matches, inliers, points per
  hypothesis, latency, screenshot paths.

## Hard rules
- No tray count, eggs count or "verified" anywhere in this feature. Points,
  matches and inliers are not trays. Do not sum views.
- Production Worker, `/v1/scans/count`, Roboflow V2 and the production APK
  default URL stay unchanged.
- No secrets in source, logs, reports, screenshots, commits or the APK.
- Distinguish measured results from expectations in every report line. If a
  step is blocked (auth, emulator rendering, quota), say so, keep going on
  independent steps, and list it under blockers.
- Do not commit or push unless the user asks.
- Stop and ask before: new AWS resource types, production Worker changes,
  downloading emulator images, any paid plan change.

## Finish
Update `PROGRESS.md` (new top entry: work done, test counts, live checks,
artifact versions/digests, blockers, exact next steps) and `context.md` (top
note). Final reply: what works end to end, what was measured, what is blocked,
links to the report and screenshots.
