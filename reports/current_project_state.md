# Current project state

Verified on 2026-08-22.

## Ready

- Flutter source: analysis clean; 4 tests pass.
- FastAPI backend: 25 tests pass; mock end-to-end development path works.
- Mobile capture: portrait LEFT/RIGHT/STRAIGHT guides and a per-view framing
  checklist gate are implemented. It is operator-confirmed, not live ML
  containment detection.
- Roboflow model: V2 (`projec-mutta/2`) is hosted on Roboflow Serverless and
  directly inferred successfully on 13 selected local images.
- Label Studio: 1.23.0 is installed locally; startup and health check passed.
  The stack-face review queue has 137 tasks and 264 suggestions.

## Not ready / remaining work

- APK: no APK was produced or installed. The installed Android SDK/JDK build
  environment fails on a sandboxed Java `android.jar` close operation, then a
  stale Gradle cache makes follow-up invocation unreliable.
- Real phone test: cannot occur until an APK is built and a device is connected.
- Production inference: V2 detects `egg_tray`, whereas production needs reviewed
  `stack_face` data and a compatible model. The guarded V2 bridge is an
  experimental, single-stack baseline only.
- Product accuracy: no independently labelled complete three-photo scenes exist,
  so exact-count accuracy, coverage and false-accept rate are not measured.

## Model location and request path

`Flutter app -> FastAPI backend -> Roboflow Serverless -> projec-mutta/2`

The API key belongs only in the backend environment. The model is not packaged
inside the APK. The saved Roboflow Workflow still defaults to version 1; the
tested V2 path is the direct endpoint documented in `current_roboflow_endpoint.md`.
