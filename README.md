# Egg Tray Counter V2

## Latest checkpoint — 2026-09-07

[Download APK 0.1.1 (release mode, debug signed)](https://media.githubusercontent.com/media/RAHUL-DevelopeRR/egg-tray-counter-mobile/main/egg-tray-counter-0.1.1-release.apk)

**Not production ready.** New warehouse intake: 82 files / 74 unique; three images with 24 stack-face boxes saved in Roboflow and isolated from legacy individual-tray labels. Retraining has not started. The APK still uses the deployed V2 model; its Cloudflare Worker does not run the Python layer counter described below. No accuracy upgrade is claimed. See the [evidence and remaining work](model-improvement/09-data-expansion/warehouse-2026-09-07/README.md).

## Intended counting architecture

Mobile-assisted, conservative egg-tray counting from three photos. The capture
contract is **LEFT, RIGHT, STRAIGHT**. The backend rectifies detected stack
faces, estimates repeating tray layers, matches the same physical stack across
views, and returns either `VERIFIED` or `RESCAN REQUIRED`.

Counts from different photos are never added together. A stack needs two usable
views with the same layer count before it contributes to the total.

## Current status

- Backend: FastAPI implementation and tests pass.
- Mobile: Flutter analyze and tests pass. Portrait-only LEFT/RIGHT/STRAIGHT
  framing guides and an operator-confirmed capture gate are implemented.
- Android toolchain: SDK API 36, Build Tools 36.0.0, Platform Tools 37.0.1,
  NDK 28.2 and licenses are installed. APK packaging status is recorded in
  `reports/verification_report.md`.
- Roboflow project: workspace `rahuls-workspace-l9ylz`, project `projec-mutta`.
- Existing version 1: 371 images; YOLOv11n mAP50 12.02%, precision 59.7%, recall
  12.5%, F1 20.7%.
- Clean version 2: 99 tagged images (69 train, 22 validation, 8 test), generated
  with auto-orient and 640x640 fit-within preprocessing and no augmentation.
- Version 2 training finished. RF-DETR Medium training ID
  `34b83955e7339d2ebeb6` reports mAP@50 67.75%, precision 81.1%, recall 61.3%;
  the separate model record reports 69.28%, 79.7%, 67.3%, and F1 73.0%.
- Direct hosted V2 inference succeeded on 13/13 selected local images. Raw
  detection count matched existing annotation count on 2/13; this is a smoke
  test, not three-view product accuracy.
- Label Studio 1.23.0 is installed in an isolated project environment and its
  health endpoint passed. The priority queue has 137 stack-face review tasks.
- Exact-count accuracy, MAE, false-accept rate, and coverage are not measurable
  until scene-level exact-count ground truth is added.

The Roboflow class is still `egg_tray`, while the production pipeline expects
`stack_face` or `counting_face`. A deliberately experimental bridge can count a
single framed stack when two accepted views agree; it never sums views. Keep it
off for production and review/train the generated stack-face queue first.

## Repository

```text
backend/   FastAPI API, Roboflow/mock providers, OpenCV counting, tests
mobile/    Flutter camera workflow, local quality gate, SQLite history
ml/        dataset audit, reconciliation, metrics, tests
datasets/  canonical dataset and Label Studio review queue
reports/   dataset, model, and evaluation evidence
docs/      API, architecture, deployment, and endpoint notes
scripts/   Windows setup, run, audit, and test commands
```

## Windows setup

Prerequisites are Python 3.11+ and, for mobile development, Flutter plus the
Android SDK. Flutter 3.47.1 and the required Android CLI components are already
available in this Codex workspace under `Documents\Codex\toolchains`; the setup
script detects them automatically.

From the repository root in PowerShell:

```powershell
Copy-Item .env.example .env
.\scripts\setup_windows.ps1
```

The script creates `.venv`, installs dependencies, runs `flutter pub get`, and
checks the Android toolchain. Verify it with:

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

## Configuration

`.env.example` contains the verified V2 identifiers but defaults to the mock
provider and leaves the experimental bridge off. Secrets belong only in `.env`;
never put the Roboflow API key in Flutter. The tested direct endpoint is
`https://serverless.roboflow.com/projec-mutta/2`; the saved Roboflow Workflow
still points to V1. See `docs/roboflow_endpoint.md`.

## Run the API

```powershell
.\scripts\run_backend.ps1
Invoke-RestMethod http://localhost:8000/health
Invoke-RestMethod http://localhost:8000/ready
Invoke-RestMethod http://localhost:8000/version
```

OpenAPI is at `http://localhost:8000/docs`.

For the single-stack V2 experiment, provide the key only in the current backend
environment and run `scripts\run_backend_roboflow_v2.ps1`. The launcher enables
the guarded baseline and prints its limitations.

Submit three distinct JPEG/PNG files with PowerShell 7:

```powershell
$Form = @{
  scan_id = [guid]::NewGuid().ToString()
  left = Get-Item 'C:\photos\left.jpg'
  right = Get-Item 'C:\photos\right.jpg'
  straight = Get-Item 'C:\photos\straight.jpg'
}
Invoke-RestMethod -Method Post -Uri http://localhost:8000/v1/scans/count -Form $Form
```

## Run Flutter

Start the API, then in another PowerShell window:

```powershell
.\scripts\run_mobile.ps1
```

Use `http://10.0.2.2:8000` from an Android emulator. For a physical phone, put
the phone and PC on the same LAN, keep FastAPI bound to `0.0.0.0`, and set the
app URL to `http://<PC-LAN-IP>:8000`. Allow private-network port 8000 through
Windows Firewall if needed.

Build a local debug APK:

```powershell
Set-Location .\mobile
flutter build apk --debug
```

## Dataset audit and review

The original folders remain unchanged. Reproduce both audits and the canonical
dataset:

```powershell
.\scripts\audit_datasets.ps1
```

The local source has 70 images and 3,372 annotations. The downloaded Roboflow
snapshot has 371 images and 102,723 annotations. Reconciliation selected 137
canonical files locally and produced 299 review tasks. The uploaded, tagged
Roboflow version contains 99 non-empty labeled images; ambiguous and empty-label
items were not presented as completed labels. The recommended stack-face
correction queue is in `datasets/stack_face_review`; launch Label Studio with:

```powershell
.\scripts\run_label_studio.ps1
```

## Tests

```powershell
.\scripts\test_all.ps1
```

This runs Ruff, backend tests, ML tests, Flutter analysis, and Flutter tests.
Flutter checks are explicitly skipped with a warning if Flutter is unavailable.
An APK build is an environment check, not part of the default test script.

## Production rule

Pilot accuracy targets are goals, not current claims. Promote a model only after
human-reviewed exact-count test scenes show acceptable accepted-scene accuracy,
MAE, false-accept rate, and coverage. Retain failed images only with explicit
purpose, access controls, and an automatic deletion policy.
