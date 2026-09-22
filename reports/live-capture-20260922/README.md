# Live capture pilot verification — 2026-09-22

This checkpoint reviews and completes the pre-existing uncommitted 0.3.0+6
capture implementation. Live image/sensor measurements run on the phone; the
existing Cloudflare gateway continues to call Roboflow projec-mutta/2.

Validation and APK metadata are recorded below after the checks finish.
Fresh health and readiness requests succeeded. They advertise model_spatial_v1
and configured projec-mutta/2. Readiness alone does not test model inference.

The inherited framing heuristic measures arbitrary image edges. It cannot
establish that a tray or entire stack is missing. Those checks must be advisory;
neither a passed capture gate nor three agreeing detections certify inventory.

The historical 14/10/30 values are not this checkpoint's inference results.
See ../production-20260918/README.md for the prior actual assigned-view demo.

## Fresh gateway smoke test

POST /v1/scans/count using the unchanged archived RIGHT/LEFT/STRAIGHT demo
images, model_spatial_v1 and an additive left_constraint_evidence field
returned HTTP 200 in 18.107 seconds. Multipart upload was 6,901,609 bytes.
Saved response: gateway-smoke.json. Actual detections: LEFT 8, RIGHT 15,
STRAIGHT 34; model projec-mutta/2, accepted=false, total_trays=null,
status=rescan_required. These different arrangements exercise compatibility;
they do not constitute a same-scene counting-accuracy evaluation.

No Worker deployment or model retraining is needed for local capture feedback.
The gateway accepts but does not validate the client constraint-evidence field.

Implementation references: [Flutter camera lifecycle](https://pub.dev/packages/camera)
and [Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion).
