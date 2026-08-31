# Accuracy recovery audit — 2026-08-31

## Confirmed failure mechanism

- The deployed Worker calls `projec-mutta/2` at confidence 35 and counts every
  returned `egg_tray` box as one tray. It then multiplies by 30 eggs.
- Therefore 19 detections deterministically become 570 eggs; the multiplication
  is correct, but the accepted tray count is not.
- The previous fusion accepted any exact count repeated by two views. It could
  accept `19 / 19 / 120` as 19 even though the third view exposed a severe
  undercount. The Worker now rejects any positive-view max/min ratio above the
  configurable `MAX_VIEW_COUNT_RATIO` (default 1.25).
- Roboflow confidence and NMS overlap are now explicit Worker configuration
  (`CONFIDENCE=35`, `OVERLAP=50`) so a locked holdout sweep can tune them.

## Model and data evidence

| Item | Current evidence |
|---|---:|
| Deployed model | `projec-mutta/2` (RF-DETR Medium) |
| V2 dataset | 99 images: 69 train / 22 valid / 8 test |
| V2 class | `egg_tray` |
| V2 model-record mAP50 / precision / recall | 69.28% / 79.7% / 67.3% |
| 13-image smoke exact matches | 2/13 (15.4%) |
| 13-image smoke MAE | 14.46 detections/image |
| Canonical local set | 137 images, 3,683 source tray boxes |
| Stack-face suggestions | 137 tasks, 264 suggestions |
| Human-approved stack-face tasks | **0** |

The detector metrics are not inventory accuracy. One prior 120-label image
produced 95 detections at confidence 0.50; another produced 122. The result is
capture-dependent and is not safe to promote from mAP alone.

## Public data decision

No public dataset was imported. The Roboflow Universe candidates found during
the audit use incompatible targets: individual eggs or fertile/infertile eggs,
not one label per visible tray layer or a reviewed stack face. Merging them would
change the class meaning and degrade this task. The useful CC BY 4.0 candidate
`thesis-57aqe/egg-tray-detection` labels `Fertile` and `Infertile`, so it was
excluded despite its size.

## Required annotation policy before V3

1. For the current object detector, draw one tight box around every visible tray
   layer/front edge. Do not box a complete multi-layer stack as one tray.
2. Label partially visible layers when their front edge is identifiable; do not
   invent fully occluded trays.
3. Keep complete LEFT/STRAIGHT/RIGHT capture sessions in one split.
4. Lock real 60/90/120-tray scenes as test-only ground truth.
5. Human-review all generated labels. The existing heuristic stack-face queue is
   a suggestion queue, not training truth.

## Training gate and comparison

Training V3 is intentionally blocked until reviewed labels exist. Training the
current zero-reviewed stack-face queue would fabricate ground truth and cannot
support a truthful before/after claim.

When the gate is met, compare:

| Candidate | Data | Model | Selection metric |
|---|---|---|---|
| Baseline | Existing V2 | RF-DETR Medium | Existing count MAE/exact rate |
| V3-A | Reviewed dense-layer data | RF-DETR Medium | Holdout count MAE/exact rate |
| V3-B | Same reviewed data | RF-DETR NAS if plan permits | Holdout count MAE/exact rate |

Use fit-within resizing at a higher small-object resolution, modest brightness /
exposure augmentation only, and sweep confidence plus overlap on the locked
holdout. Promote only if exact-count accuracy, MAE, accepted accuracy, and false
accept rate improve. Do not choose by mAP alone.

## Deployment state

The safety fix is built, its three unit tests pass, and it is deployed at
`https://egg-tray-counter-api.rahultech72216.workers.dev`. The live health check
passes. Live Roboflow inference currently returns upstream HTTP 402, so the
Worker now returns HTTP 503 with `inference_quota_exhausted` instead of a vague
network failure.

Roboflow retraining is not started because this session has no callable
Roboflow MCP server, the account currently has no usable inference credits, and
the replacement stack-face labels have not been human-approved. A 28-task dense
priority batch (60–159 source layers, including the 120+ cases) is ready in
`datasets/stack_face_review_dense`; its one test task must remain out of training.
