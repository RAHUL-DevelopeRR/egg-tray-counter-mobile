# Production readiness gate

Decision: **NOT PRODUCTION READY — DO NOT DEPLOY V3.** Keep the current V2 Medium endpoint unchanged.

2026-09-02 correction-run decision: the 27 conflicted assets were removed, V3 was frozen with 72 policy-consistent images, and RF-DETR Medium was trained. The unchanged 10-file benchmark produced **2/10 exact and MAE 20.7**. Because the gate requires both exact >2/10 and MAE <22.9, V3 fails on exact count and is **DO NOT DEPLOY**.

## Evidence

- Medium count benchmark: 2/10 exact, MAE 22.9, mean relative error 41.57%.
- Large count benchmark: 1/10 exact, MAE 24.0, mean relative error 47.203%.
- V3 Medium count benchmark: 2/10 exact, MAE 20.7, mean relative error 38.157%.
- V3 Medium detector metrics: mAP@50 74.3%, precision 84.3%, recall 67.5%, F1 75.0%.
- V3 exactly counted the 120-tray benchmark image, but large errors remained on other warehouse views; one correct showcase image is not enough to pass the fixed benchmark.
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

V3 remains an experiment only. Do not change `ROBOFLOW_MODEL_ID` or `ROBOFLOW_VERSION` until a candidate strictly beats both baseline gates on the same benchmark.
