# AWS two-view reconstruction deployment — 7 October 2026

Deployed `egg-tray-vision-pilot` in `ap-south-1` using image tag
`pilot-20261007`, digest
`sha256:4ef6034d8adb553478d86f73a131d6c8dff3ba943cf1d49a063b11315cda70fb`.
Lambda directly reported Active / Successful; the resolved image digest was
verified. Official AWS CLI 2.37.10 was installed per-user and authenticated
through the user's browser. AWS Core remained unavailable.

Public health: https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/health

Authenticated POST `/candidate/reconstruct` accepts multipart `first` and
`second` JPEG/PNG photos: distinct images, equal dimensions, at most 2 MB and
12 megapixels per image. It reuses the local SIFT/mutual matching/RANSAC/
essential-matrix camera-pose/triangulation implementation. The result includes
camera poses and sparse point coordinates for three assumed focal lengths.
Every non-health route requires the existing server-side bearer secret. One
reconstruction per process is allowed; overlapping requests receive 429.
Temporary photos and output files are removed after each request.

## Verification

- 15 local hosting/spatial tests passed, with one anyio deprecation warning.
- Real-photo local HTTP replay returned 200 and matched CLI geometry exactly.
- Hosted health returned 200 and advertised `two_view_sfm_diagnostic_v1`.
- Unauthenticated stack and reconstruction requests returned 401.
- Authenticated stack/band diagnostic returned 200 in 12.233 seconds: 16 stack
  candidates, zero accepted correspondences, null inventory, recapture required.
- Authenticated reconstruction returned 200 in 10.703 seconds. The two originals
  were warehouse-20260923/input/image-1.jpg and image-2.jpg; response SHA-256
  hashes match local originals. There were 175 strict matches and 125 fundamental
  inliers; assumed focal factors 0.7 / 1.0 / 1.4 yielded 76 / 94 / 100 points.
- A second hosted reconstruction returned exactly equal JSON in 10.568 seconds.
  AWS median reprojection errors were 0.376 / 0.315 / 0.447 pixels.
- Windows returned 121 fundamental inliers and 67 / 86 / 100 points from the same
  algorithm and photos. The Windows and Linux fits are not exactly equivalent;
  do not treat platform-sensitive geometric support as a tray count.

Cold health took 7.305 seconds in this one replay; timings include HTTP overhead
and are individual observations, not throughput or latency benchmarks.

## Counting limitation and next work

This is an uncalibrated sparse reconstruction, not a completed inventory solver.
`physical_trays=null`, `verified=false`, unknown intrinsics, arbitrary scale and
unconfirmed stable stock remain explicit. Feature points include background and
tray/egg texture; they are not tray instances. Archived model detections were
replayed; no fresh Roboflow inference or retraining occurred. Reviewed visible
references remain 99 wide-view trays and 19 narrow-view trays; they are not
summed across views or promoted to independently verified warehouse truth.

The Worker and APK still use the existing production model route. They have not
been changed to call this AWS route. Next: obtain camera calibration and an
unchanged physically counted scene, restrict geometry to identified stack faces,
match each physical stack once, and compare predicted layers/occupancy with held
out truth before exposing a verified inventory result to the mobile client.

## Artifacts and cleanup

`deployment.json`, `live-image.json`, and `source-manifest.json` record image and
source hashes. `api-summary.json` and `candidate-response.json` contain band/stack
evidence. `reconstruction-response.json`, `reconstruction-summary.json`, and
`comparison.json` contain hosted geometry and repeatability checks. The three
`aws-hypothesis-*.ply` files contain uncalibrated point clouds in unit-baseline
coordinates. The source archive is private S3 `source/vision-20261007.zip`;
private build logs/status use `build/20261007/` with the existing 7-day lifecycle.

Temporary t3.small builder `i-06d048e4cbd40a49d` was directly confirmed terminated;
its IAM role/profile and no-ingress security group were removed. Lambda has
2048 MB, a 120-second timeout, and no provisioned concurrency. ECR/S3 storage and
Lambda usage remain metered; no claim of zero cost is made. No private token is
stored in these artifacts or in the APK.
