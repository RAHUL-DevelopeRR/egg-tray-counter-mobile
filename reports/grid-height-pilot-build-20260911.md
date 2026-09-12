# APK 0.2.0 — local build verification, 2026-09-11

## Artifact

- File: `egg-tray-counter-0.2.0-grid-pilot.apk` at the repository root; copied from `mobile/build/app/outputs/flutter-apk/app-release.apk`.
- Build output timestamp: 2026-09-10 22:32:04 +05:30; verified 2026-09-11.
- Size: **59,315,255 bytes**.
- SHA-256: `FDCBC358F7523D404AE114BD5EFFDD6CB784A55B294D55AC178D6FDA48646100`.
- Package: `com.dharani.eggtray.egg_tray_counter`.
- Version: **0.2.0**, versionCode **3**; min SDK 24, target/compile SDK 36.
- Native ABIs: arm64-v8a, armeabi-v7a, x86_64. Each contains a compiled `libapp.so`.
- Included illustration: `assets/flutter_assets/assets/grid-height-pilot.png`, 2,238,766 bytes. Concept art only, not calibration or training data.

`aapt dump badging` verified the package/version/SDK/ABI metadata. `apksigner verify --verbose --print-certs` succeeded with APK Signature Scheme v2 and one signer. ZIP inspection verified the new asset and compiled native libraries. The copied delivery file has the same SHA-256 as the build output.

The certificate is the existing **Android Debug** certificate, SHA-256 `faa77ec9df2962c8c53a94bcb91993fde85f0959aaa3883194f80888f538b681`, matching APK 0.1.1. This is a release-mode build with debug signing, not a production signing-key migration. An upgrade should retain data when the installed package has this same certificate; installation was not tested on a device.

## Checks completed

- Flutter tests: **13 passed** (calibration, ambiguity/range rejection, local tally persistence/replacement, write failure, scan session and backend contract).
- Flutter analyze: **no issues found**, after mechanical brace formatting.
- Worker TypeScript build: passed.
- Worker tests: **9 passed**, including cell identity and health-contract metadata. Node test harness, not a live Cloudflare deployment.
- `git diff --check`: passed.
- Existing counting evaluator, ground-truth CSV and Worker deployment configuration unchanged by this feature.

The Android build used Flutter 3.47.1, Temurin JDK 17.0.20, SDK 36 and the existing cached Gradle toolchain:

```powershell
flutter --suppress-analytics build apk --release --no-pub --build-name=0.2.0 --build-number=3
```

JAVA_HOME pointed to the installed Temurin 17 directory; ANDROID_HOME/ANDROID_SDK_ROOT, PUB_CACHE and GRADLE_USER_HOME pointed to the existing Documents/Codex toolchains. ANDROID_USER_HOME pointed to the ignored mobile/.android-home directory with the existing matching debug keystore. No dependencies were added, SDK versions downgraded or caches deleted.

## Release boundaries

- **No Android runtime smoke test:** ADB MCP could not find adb (`spawn adb ENOENT`); the installed CLI failed creating its Android user directory (`Cannot mkdir '\\.android': Permission denied`). APK metadata/signature verification is not an emulator or physical-device test.
- **No automatic camera metrology:** this pilot requires real ruler measurements and a physical recount. It counts only egg-filled trays. See [the setup guide](../docs/grid-height-pilot.md).
- **No photo backend deployment:** the new client requires `scan_contract: cell_identity_v1`. The last live health check returned only `{"status":"ok"}`. Photo scanning therefore reports a backend-update requirement before upload; offline pilot mode works independently.
- **No model accuracy change:** recorded V2 benchmark is 2/10 exact, MAE 22.9; V4 was 1/10, MAE 21.4; the tested tiled V2 variant was 0/10, MAE 46.2. V2 remains deployed. No new inference, training, dataset mutation or model promotion occurred in this build.
- **No height accuracy score yet:** synthetic tests do not establish field accuracy. The ten detector benchmark photos lack the measured height references needed to evaluate this mode.
- This APK is local only: no GitHub release upload, commit, push or cloud deployment is claimed.
