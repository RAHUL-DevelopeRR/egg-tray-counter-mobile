# Claude Code handover - egg tray counter

Updated: 2026-10-07

## Read first

Read AGENTS.md, PROGRESS.md, context.md, this file, and
reports/reconstruct-integration-20261007/README.md. The user is asking for a
recognizable 3D reconstruction of egg trays and ultimately an exact count. The
current deployed feature is only a diagnostic sparse reconstruction. Do not
describe it as a tray model or count.

## Current state

- Working tree is dirty and intentionally uncommitted. Do not reset, commit, or
  push unless the user asks.
- AWS Lambda egg-tray-vision-pilot, ap-south-1, image tag
  pilot-20261007-integration, digest
  sha256:8511bd3af2afb02a8d7c8107bc83f2032c14299eefbd504cf6105e0d30218dba.
- Staging Worker:
  https://egg-tray-counter-api-staging.rahultech72216.workers.dev.
  Production Worker and the default APK URL were not changed.
- APK 0.3.4+10 is installed in BlueStacks. SHA256 is recorded in
  reports/reconstruct-integration-20261007/apk-signature.txt and the report.
- Tests already recorded: backend 82, Worker 20, Flutter 66; TypeScript compile,
  staging dry-run, and final Flutter analyzer passed.

## What the current algorithm does

backend/app/vision/reconstruction.py detects SIFT features, matches two
images, estimates a fundamental/essential geometry, sweeps focal assumptions,
triangulates sparse points, and returns colored [x,y,z,r,g,b] evidence plus
camera poses and bounds. It does not reconstruct surfaces. The points in the APK
are image correspondences; 0.376/0.447 px reprojection error is a geometric fit
metric, not a tray-count metric. The route deliberately returns
physical_trays: null, verified: false, and scale: arbitrary_unit_baseline.

The four API fixtures and direct-AWS equality checks are in the report. The wide
pair produced 175 matches, 125 inliers and 76/94/100 points under focal factors
0.7/1.0/1.4. The 1+4 negative control returned insufficient_matches. A
wide-side pair had only 9 matches and must be treated as weak evidence.

## Correct next implementation

1. Finish or explicitly close the remaining emulator matrix; do not confuse API
   replay JSON with an APK-captured response.
2. Build a local dense reconstruction experiment on a calibrated, unchanged
   capture sequence. A standard pipeline is sparse SfM -> dense multi-view stereo
   depth -> fusion -> mesh/texturing. Keep it behind a diagnostic endpoint until
   measured. Do not promise that a mesh solves hidden trays.
3. Add tray/stack instance association: detect tray rims/layers, assign one
   physical stack identity across views, and reject duplicate front/side evidence.
4. Compare the proposed count with physical filled/empty per-stack ground truth
   on held-out scenes. Report exact-match rate, absolute error, duplicates and
   omissions. Only then consider physical_trays non-null.

## Commands and paths

Use the bundled runtimes listed in AGENTS.md and the report. Useful checks:

    pytest -q backend/tests
    npm test --prefix cloudflare-worker
    npm run build --prefix cloudflare-worker
    .\work\toolchains\flutter\bin\flutter.bat analyze --directory mobile
    .\work\toolchains\flutter\bin\flutter.bat test --directory mobile
    git diff --check

Never print or commit the AWS/Cloudflare/Roboflow secrets. Preserve the private
R2 archive and the current production route. Any new billable AWS resource or
production deployment needs the user's explicit approval.

## Tools and skills used

See tools.md for the full inventory. This handover used local shell/ADB,
@oai/sky via mcp__node_repl__js, AWS CLI, Wrangler, and public web docs.
The recorded skills are computer-use, antislop, antislop-ui, and ponytail; the
active plugins were codex-app-tools and unified-computer-use. Availability of a
skill or plugin does not prove that it was used or authenticated.
