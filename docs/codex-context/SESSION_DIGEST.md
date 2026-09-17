> Latest checkpoint (2026-09-17): local candidate revision `candidate-20260917`.
> Read `reports/candidate-20260917/README.md` and the latest PROGRESS/context entries.
> Regional quality, structured recapture, strict schemas, shared-stack provenance
> and stronger provisional matching implemented. Synthetic 200/180/195 pass;
> 65 backend tests and 13 Worker tests passed, plus focused final checks.
> 35 archived images replayed, 106 proposed faces, no new RF calls or physical truth.
> Real correspondence/occupancy remain unresolved. Worker encoding/logging changes
> are local only. No deployment, training or APK rebuild; APK stays 0.2.2+5.
> Next: confirm a same-scene triplet and independent per-stack truth, then calibrate
> geometry/occupancy/quality acceptance before hosted integration and Android work.

> Latest checkpoint (2026-09-16): the active work is the **local MUTAA 3D/band
> candidate**, documented in `docs/3D_BEAM_COUNTING_ARCHITECTURE.md` and
> `reports/mutaa-20260916/README.md`. 35 originals have fresh V2 results and
> automatic band/ROI evidence; real 3D identity and eligible totals remain
> unresolved. 62 Python tests and 12 Worker tests pass. APK remains 0.2.2+5;
> latest recorded live Worker is ab67cd59-3f4e-4628-a0fa-d085f56a3fe8.
> No new deployment, APK or retraining. Earlier deployment/training priorities
> below are historical and do not override the current research-only scope.
> Read the latest PROGRESS.md and context.md entries first.

# Codex Session Digest: Egg Tray Counter

- **Session Thread:** Build egg tray counter app
- **Session ID:** `01a01fe8-0a0e-7011-9a80-0fab4a36a2ea`
- **Timeline:** 2026-08-20 to 2026-09-12
- **Pausing Reason:** OpenAI Codex weekly token limit reached (resets Sep 15, 2026, 12:07 PM).
- **Final Result:** APK 0.2.1 built, passed all 14 tests, and completed 3 successful emulator cold-launch verifications.

---

## Chronological Overview & Key Decisions

1. **Phase 1: Initial Vision Prototype & Cloudflare Bridge**
   - Established three-view guided capture (Straight, Left 30°, Right 30°).
   - Designed serverless bridge via Cloudflare Worker connecting mobile client to Roboflow model `projec-mutta/2`.
   - Addressed network timeouts and private APK delivery.

2. **Phase 2: Mobile Build Engineering & Sandbox Toolchains**
   - Set up custom offline Android/Flutter toolchains under Documents/Codex (`temurin-17`, `flutter-3.47.1`, `android-sdk`).
   - Addressed permission and sandbox constraints to compile release APKs with debug signing.

3. **Phase 3: Model Evaluation & Benchmark Guardrails**
   - Benchmarked Roboflow V2 detector: 2/10 exact match, MAE 22.9.
   - Evaluated candidate V4 RF-DETR Medium (1/10 exact, MAE 21.4) and Tiled V2 (0/10 exact, MAE 46.2).
   - Enforced strict deployment gates: candidate models with worse exact counts were rejected.

4. **Phase 4: Floor-Cell & Height Pilot (APK 0.2.0 & 0.2.1)**
   - Shifted focus to a measurement-assisted warehouse workflow: painted floor cells with clear IDs and wall height reference marks.
   - Generated illustrative diagram `mobile/assets/floor-cells-wall-reference.png`.
   - Built APK 0.2.0; diagnosed native CameraX cold startup crash.
   - Built APK 0.2.1; deferred camera enumeration to photo preflight, resolving startup crash.
   - Passed 14 Flutter unit tests and 3 cold-launch checks on emulator right before rate limit reached.
