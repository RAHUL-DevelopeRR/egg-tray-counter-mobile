# Verification report

Verified on 2026-08-22 in Windows PowerShell.

- Ruff: passed for backend and ML code.
- Backend: 25 tests passed.
- ML: 3 tests passed.
- Flutter analyze: no issues found.
- Flutter: 4 tests passed.
- Live FastAPI smoke: `/health`, `/ready`, and `/version` returned HTTP 200.
- Android platform files and camera/network permissions: present.
- Android SDK: API 36, Build Tools 36.0.0, Platform Tools 37.0.1 and NDK 28.2
  are installed; Android licenses were accepted and Flutter doctor reported a
  healthy Android toolchain.
- APK: not produced. The app reaches Android compilation, but the sandboxed
  Windows Java process throws `AccessDeniedException` while closing the SDK
  `android.jar`; the direct Flutter retry subsequently stalled after the Gradle
  cache had been interrupted. This is an environment/build-cache blocker, not a
  source validation failure. There is no installable APK to claim or test.

Roboflow V2 RF-DETR Medium training `34b83955e7339d2ebeb6` finished. Direct
hosted `projec-mutta/2` inference succeeded on 13 selected local images. This
is a serverless model hosted by Roboflow, not a model embedded in the app. Raw
detection count matched available image annotations on 2/13 images (MAE 14.46);
one zero-label image visibly contains trays. Therefore it is a prototype
detector, not validated three-view exact counting. Exact-count product metrics
remain unavailable until complete LEFT/RIGHT/STRAIGHT scenes receive independent
ground-truth totals.

Security verification found no committed real API key. HTTPX request logging is
held at WARNING so its request URLs cannot expose Roboflow's query-string API
key in normal application logs. Same-scan work is serialized before the
idempotency check and inference, preventing concurrent duplicate processing.
