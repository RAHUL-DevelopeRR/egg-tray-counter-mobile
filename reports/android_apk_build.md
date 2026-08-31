# Android APK build

Build completed on 2026-08-22 using Flutter 3.47.1, Dart 3.13.1,
Temurin JDK 17.0.20, Android API 36, Build Tools 36.0.0, and NDK
28.2.13676358.

- Deliverable: `../../egg-tray-counter-debug.apk`
- Package: `com.dharani.eggtray.egg_tray_counter`
- Version: `0.1.0` (`versionCode` 1)
- Minimum Android API: 24
- Target Android API: 36
- Size: 159,673,375 bytes
- SHA-256: `1E1F6A25F7D046FA1476F3EC4FC22303BC5618D3479FFF0E38064259B0E6DF98`
- Signature: verified with APK Signature Scheme v2; one 2048-bit RSA Android
  debug signer (`CN=Android Debug, O=Android, C=US`)

This is an installable debug APK, not a Play Store release artifact. Package and
signature verification passed. No Android device was visible to ADB in this
session, so physical-device installation and camera execution remain unverified.

The model is not embedded in the APK. The mobile app sends its framed
LEFT/RIGHT/STRAIGHT photos to the FastAPI backend; the backend calls the hosted
Roboflow Serverless model `projec-mutta/2`.
