# Production readiness gate

Decision: **NOT PRODUCTION READY — DO NOT DEPLOY RF-DETR Large.** Keep the current Medium endpoint unchanged.

2026-09-02 correction-run decision: **DO NOT TRAIN / DO NOT DEPLOY.** The all-99-image visual gate found 27 images still requiring manual relabeling, so no corrected V3 or new Medium benchmark exists. The promotion comparison therefore remains current Medium `2/10` exact, MAE `22.9`; candidate metrics are `NOT RUN`.

## Evidence

- Medium count benchmark: 2/10 exact, MAE 22.9, mean relative error 41.57%.
- Large count benchmark: 1/10 exact, MAE 24.0, mean relative error 47.203%.
- Large dashboard metrics also regressed: mAP@50 68.1%, precision 78.9%, recall 63.4%, F1 70.3%.
- Three-view spread worsened from 84 to 85; neither model counted all three views correctly.
- Frozen V2 uses incompatible labeling units, including a dense image with one stack-scale box and dense images with individual-tray boxes.
- V2 validation and test contain documented views of the same benchmark scene; no defensible untouched final holdout exists.

## Current production settings

| Setting | Value |
|---|---|
| Model | RF-DETR Medium / `projec-mutta/2` |
| Confidence | 35% |
| Overlap | 50% |
| Class | `egg_tray` |

These settings are retained only because Large is worse; they are not evidence of production-grade accuracy.

## Promotion requirements

1. Correct all mixed-unit annotations and complete scene/view/count metadata.
2. Freeze a scene-grouped development version and a separate untouched final holdout.
3. Beat Medium on exact accuracy, MAE, difficult scenes, and three-view spread at identical settings.
4. Run the selected candidate once on the untouched holdout and list every failure.

No further paid run is justified until requirement 1 is complete.
