# AWS and existing-photo user test - 2026-10-07

## Hosting check

The previously deployed AWS Lambda diagnostic remains reachable at:
https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/.
This session measured public health HTTP 200 and an unauthenticated candidate
POST HTTP 401. Health explicitly reports diagnostic_only and
inventory_verification_ready=false. See live-health.json.

AWS Core first returned requires reauthentication, then Unknown tool after the
user reconnected. Account configuration, protected photo replay and new
deployment could not be verified this session. The successful authenticated
Oct 6 replay remains historical evidence in ../aws-vision-check-20261006/.
No resources were created or changed through AWS APIs this session.

## New reconstruction experiment

Used two overlapping wide originals, instead of the earlier wide-to-narrow pair:
reports/warehouse-20260923/input/image-1.jpg and image-2.jpg.
Original bytes are preserved in the existing report; their hashes are recorded
in wide-pair/result.json. Reused scripts/reconstruct_pair.py without changes.
Its synthetic triangulation self-check ran before the actual photo experiment.

| Measurement | Result |
| --- | ---: |
| Strict mutual SIFT matches, ratio 0.65 | 175 |
| Fundamental-matrix RANSAC inliers | 121 |
| Homography RANSAC inliers | 46 |
| Triangulated points, focal width factor 0.7 | 67 |
| Triangulated points, focal width factor 1.0 | 86 |
| Triangulated points, focal width factor 1.4 | 100 |
| Median reprojection error, factor 1.0 | 0.448 px |
| Verified physical tray count | unresolved |

Each hypothesis uses assumed intrinsics and arbitrary unit-baseline scale.
The PLY files are sparse feature clouds, not meshes or tray instances. They
include background and repeated tray/egg texture. 101 of the 121 inlier matches
fall inside coarse manually inspected tray bounding regions in both images;
that check is not segmentation, physical identity validation or a tray count.
The variation with assumed focal length demonstrates remaining calibration
sensitivity. No physically confirmed stable stock or hidden occupancy is supplied.

This is new local geometry evidence. It has not been deployed as an AWS route.
The current hosted candidate route does stack-region/band/correspondence
diagnostics; it does not run this camera-pose/triangulation script.

## Counting comparison

Reviewed the original wide photo and narrow photo against the retained numbered
manual references. The wide visible-layer reference is 20/20/20/20/19 = 99;
the narrow face reference is 19. These are visible-image references, not an
independent physical filled/empty warehouse recount. They are not added together.

| Input | Reviewed visible layers | Archived V2 detections | Absolute error |
| --- | ---: | ---: | ---: |
| Wide photo 1 | 99 | 76 | 23 |
| Narrow photo 4 | 19 | 19 | 0 |

No fresh Roboflow inference was performed for these comparison numbers.
The historical AWS candidate replay had 16 proposed regions and zero accepted
cross-view matches, with null physical/eligible inventory. Whole-image sparse
geometry does not repair fragmented stack localization or missing tray detections.

## App path and next steps

APK 0.3.3+9 still sends /v1/scans/count to Cloudflare/Roboflow V2. The Worker
has no AWS candidate integration; the Lambda's health contract alone cannot
satisfy the APK's model_spatial_v1 preflight. AWS service credentials must remain
server-side. Direct Worker health/ready probes from this machine failed during
TLS with WinError 10054; that does not establish that the Worker itself is down.

Targeted host/spatial checks: 14 passed, with one anyio dependency deprecation
warning. These are code/contract checks, not field accuracy.

### Actual manual Android test

Started the existing BlueStacks Pie64 emulator and launched Egg Tray Counter
by clicking its app icon through the Windows UI. ADB confirmed the installed
version as 0.3.3+9 and copied the four originals to Download/egg-tray-test.
The Android accessibility tree exposes SERVER REACHABLE, Settings, camera and
UPLOAD PHOTOS controls. See android-home-controls.json and android-home-ui.xml.
The actual screen remained white: android-home.png is a failure screenshot,
not a successful count screen. App-process logs show EGL_BAD_MATCH and other
graphics warnings; those logs do not by themselves prove the root cause.

Changed BlueStacks from Vulkan & OpenGL to OpenGL only through its settings UI,
restarted it, and confirmed graphics_renderer=gl and Android boot completion.
The restarted launcher appeared normally. Further app interaction was interrupted
by window minimization/user input; a post-change app upload/result screen was
not verified. No scan was submitted from the APK and no current mobile count
was obtained. This is an attempted user test with a rendering blocker, not an
end-to-end pass. APK, application settings and source were not modified.

Next: restore usable AWS account tooling; connect a separate diagnostic gateway
without claiming inventory readiness; stabilize emulator rendering and repeat
upload/result review; use overlapping wide/corner frames for camera geometry,
then establish stack identities and layer detections. Evaluate against untouched
physically recounted scenes before asserting an exact warehouse count.
