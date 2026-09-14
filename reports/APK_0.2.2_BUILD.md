# Android 0.2.2 development build

Built and verified on 2026-09-14. Artifact: `egg-tray-counter-0.2.2-hybrid.apk`
at the repository root. Despite the requested filename, this is an incomplete
hybrid development build, not a validated exact-counting release.

- Package: `com.dharani.eggtray.egg_tray_counter`
- Version: 0.2.2, versionCode 5
- Bytes: 59,631,396
- SHA-256: `1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b`
- Minimum Android SDK 24; target/compile SDK 36
- ABIs: arm64-v8a, armeabi-v7a, x86_64
- APK v2 signature and ZIP CRC checks passed.
- Signing: Android Debug; certificate SHA-256
  `27a05295083b6cdc176db6c3717c39cf0aec1cb3c336e208bc36aaefd15fdcbf`.

The existing 0.2.1 APK has a different signing certificate
(`faa77ec9df2962c8c53a94bcb91993fde85f0959aaa3883194f80888f538b681`).
Android will not install this as an in-place update of that APK. Preserve any
existing inventory data; no uninstall or device change was performed. The old
signing key is needed for an update that preserves the installed application's identity.

## Verification

Flutter 3.47.4 / Dart 3.13.3, JDK 21.0.11, Gradle 9.3.1.
Flutter pub get and analysis passed; all 16 mobile tests passed.
All 44 backend tests passed. Worker tsc, deployment dry-run and 11 tests passed.
Ruff and git diff --check passed for the changed code. The build emitted an SDK
XML-version warning but completed successfully. No Android device or emulator
was connected, so camera, installation and end-to-end device checks are unverified.

## Functional limits and remaining work

Capture accepts optional floor IDs and requests `model_spatial_v1`.
The local Worker implementation preserves model boxes and returns unresolved
per-photo evidence. Automatic cross-view physical-stack matching, occupancy
analysis and integration of the calibrated hybrid core are unfinished.

The deployed Worker still exposes the old baseline contract; the updated app's
preflight will require a backend update before uploading photos. Wrangler was
again verified unauthenticated on 2026-09-14; no new deployment or model promotion
occurred. Previous device-authorization codes expired and must not be reused.

Fresh cloud inference for img04 returned 29 versus the retained non-blind visual
reference of 32: error 3 trays / 9.375%, count closeness 90.625%. This is a single
image model result, not hybrid accuracy or precision. See
`manual-reference-20260913/LIVE_EVALUATION.md` and `../docs/COUNTING_EXECUTION_PLAN.md`.
Need real same-scene LEFT/STRAIGHT/RIGHT images with independently checked totals
and occupancy labels to evaluate the remaining pipeline. No claim of near-100%
accuracy is supported.
