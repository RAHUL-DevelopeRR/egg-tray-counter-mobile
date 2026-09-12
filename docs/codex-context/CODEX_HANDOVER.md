# Codex Project Handover: Egg Tray Counter

> **Generated:** 2026-09-12  
> **Source Session ID:** `01a01fe8-0a0e-7011-9a80-0fab4a36a2ea` ("Build egg tray counter app")  
> **Session State:** Paused due to weekly Codex usage limit reaching 100% (resets Sep 15, 2026, 12:07 PM).  
> **Integrity Status:** Clean shutdown. APK 0.2.1 compiled, verified with 14 unit tests, and smoke-tested on Android emulator.

---

## 1. Executive Summary & Current State

The **Egg Tray Counter** project is a production-oriented edge vision system designed for counting stacked egg trays (30 eggs/tray) in commercial egg farm warehouses.

### What is Completed & Verified (as of 2026-09-12)
1. **Offline Grid + Height Pilot (APK 0.2.1 / Build 4):**
   - Implemented an offline, measurement-assisted physical tally workflow (`mobile/lib/features/grid_height/`).
   - Fixed the cold-startup native crash observed in 0.2.0 by moving camera enumeration out of app initialization and into photo-mode preflight.
   - Built and signed `egg-tray-counter-0.2.1-grid-pilot.apk` (59.6 MB, Android debug cert).
   - Passed all **14 Flutter unit & contract tests**.
   - Verified with **3 cold-boot launch smoke tests** on Android emulator (`reports/apk-runtime-20260912/startup-check.log`).
2. **Backend Gateway (Cloudflare Worker):**
   - Implemented `cell_identity_v1` multi-cell fusion logic (`cloudflare-worker/src/index.ts`).
   - Requires painted floor cell IDs for photo views to prevent false cross-cell view matching.
   - Passed all **9 Worker tests** (`cloudflare-worker/test/`).
3. **Roboflow Inference Integration:**
   - Active deployed detector: V2 (`projec-mutta/2`).
   - Benchmark ground truth: 2/10 exact match, MAE 22.9.
   - Note: Retraining on new warehouse datasets is pending (V4 and tiled models were evaluated and rejected due to higher error rates).

---

## 2. Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │          Flutter Mobile App            │
                      │  (v0.2.1+4: Grid Pilot + Guided Photo) │
                      └──────────────────┬─────────────────────┘
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   │                                           │
         [Offline Mode]                                [Online Photo Mode]
         - Floor-cell ruler measurement                - 3-view guided capture
         - Pairwise calibration solver                 - Requires scan_contract:
         - Local JSON tally storage                      cell_identity_v1
                   │                                           │
                   ▼                                           ▼
         [Physical Recount]                     ┌──────────────────────────────┐
         - Operator ground truth                │      Cloudflare Worker       │
         - Safe against drift                   │ (Gateway, Fusion, Auth gate) │
                                                └──────────────┬───────────────┘
                                                               │
                                                               ▼
                                                ┌──────────────────────────────┐
                                                │  Roboflow Serverless Engine  │
                                                │      (projec-mutta/2)        │
                                                └──────────────────────────────┘
```

---

## 3. Subsystem Breakdown

### A. Mobile App (`mobile/`)
- **Framework:** Flutter 3.47.1 / Dart SDK `>=3.9.0 <4.0.0`
- **Application ID:** `com.dharani.eggtray.egg_tray_counter`
- **Key Modules:**
  - `lib/features/grid_height/`: Offline Grid + Height screen, ruler-based calibration solver, recount logger.
  - `lib/features/scan_flow/`: Three-angle guided camera capture (Straight, Left 30°, Right 30°).
  - `lib/services/api_client.dart`: Backend API client with contract preflight checks (`cell_identity_v1`).
  - `lib/services/settings_store.dart`: Local configuration and tally persistence.
- **Assets:** `assets/floor-cells-wall-reference.png` (conceptual illustration of painted floor boxes and wall height levels).

### B. Cloudflare Worker (`cloudflare-worker/`)
- **Path:** `cloudflare-worker/src/index.ts`
- **Contract:** Advertises `scan_contract: cell_identity_v1` on `/health`.
- **Endpoints:**
  - `GET /health`: Returns status and contract version.
  - `GET /ready`: Validates Roboflow API key readiness.
  - `POST /count`: Multipart upload accepting 3 images + `straight_cell_id`, `left_cell_id`, `right_cell_id`.
- **Fusion Logic:** Fuses multi-view detections per cell ID. Rejects ambiguous or disagreeing angles.

### C. Datasets & Model Research (`model-improvement/`)
- Contains historical evaluation runs, annotation policies, and benchmark logs.
- Evaluated candidates:
  - V2 (`projec-mutta/2`): Deployed baseline (MAE 22.9).
  - V4 RF-DETR Medium: MAE 21.4 (rejected due to lower exact accuracy).
  - V2 Tiled (2x2): MAE 46.2 (rejected).

---

## 4. Current Operational Boundaries & Remaining Work

1. **Cloudflare Worker Deployment:**
   - The Worker code in `cloudflare-worker/src/index.ts` has been updated and tested locally, but **has not yet been deployed to the live Cloudflare URL**.
   - As a result, photo mode in APK 0.2.1 safely flags that the server requires an update, while the offline Grid + Height pilot is completely functional.
   - **Action:** Run `npx wrangler deploy` in `cloudflare-worker/` with Cloudflare account credentials.
2. **Roboflow Retraining:**
   - Retraining on clean stack-face warehouse data is staged in `model-improvement/09-data-expansion/`.
3. **Field Metrology:**
   - The Grid + Height pilot currently relies on operator manual ruler measurements in cm. Homography-based automatic vision metrology is deferred until calibrated warehouse photos with depth markers are available.

---

## 5. Build Artifacts Reference

- **Latest APK:** `egg-tray-counter-0.2.1-grid-pilot.apk` (59,631,400 bytes, SHA-256 verified)
- **Previous APK:** `egg-tray-counter-0.2.0-grid-pilot.apk` (59,315,255 bytes)
- **Base Release APK:** `egg-tray-counter-0.1.1-release.apk` (56,092,991 bytes)
