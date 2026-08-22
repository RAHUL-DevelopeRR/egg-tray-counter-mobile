# Roboflow migration

## Current state

The verified workspace `rahuls-workspace-l9ylz` contains project
`projec-mutta`. Version 2 contains 99 reconciled, tagged images (69/22/8), and
RF-DETR Medium training `34b83955e7339d2ebeb6` finished. Hosted V2 inference
works, but its current `egg_tray` class remains incompatible with the production
stack-face contract except through the explicit single-stack experimental gate.

## Target dataset

- Project type: instance segmentation (immutable after creation).
- Class: `stack_face`.
- Every polygon covers the useful visible counting face of one physical stack.
- External metadata/manifest: `scene_id`, `view`, `physical_stack_id`, and
  `tray_count_gt`.
- Split by complete `scene_id`; duplicates and all views from one capture session
  stay in the same split.
- Maintain difficult and failed photos with quality/rejection labels.

Run `python ml/prepare_dataset.py` to generate a deduplicated review manifest.
It intentionally leaves semantic fields blank rather than guessing them.

## Recommended modeling sequence

1. Correct the 137-task `datasets/stack_face_review` queue and define actual
   LEFT/RIGHT/STRAIGHT scene groups. The existing images do not establish triplets
   safely.
2. Review the 264 heuristic `stack_face` polygon suggestions and enter exact
   counts. Do not accept preannotations blindly.
3. Generate a frozen version with auto-orient/resize preprocessing and conservative
   lighting/perspective augmentation. Keep validation/test scene-level.
4. For custom instance-segmentation training, prefer RF-DETR NAS Seg
   (`rfdetr-nas-seg-parent`) when the workspace is entitled and the version has at
   least 15 validation images. If NAS is unavailable, use
   `rfdetr-seg-medium` as the named-model baseline.
5. Use the model only to locate faces. Tune the OpenCV layer counter and fusion on
   held-out golden triplets.
6. Compare product metrics from `ml/evaluate.py`: exact stack, MAE, exact scene,
   coverage, accepted accuracy, and false-accept rate. Report model mAP separately.

## Deployment

Set a specific `project/version` model reference in backend `.env`. Start with
serverless inference. A saved Roboflow Workflow is the preferred later production
unit for model, filtering, visualization, and active-learning collection; keep
workflow output normalized at the same `InferenceProvider` boundary.

Do not promote a model until a human confirms project privacy/license, scene
metadata, labeling policy, the stack-face class contract, and exact-count results.
