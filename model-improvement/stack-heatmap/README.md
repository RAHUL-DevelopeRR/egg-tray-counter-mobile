# STACK-HEATMAP-HYBRID-V1

Follow-up: ../../reports/stack-heatmap-followup-20260928/README.md contains the
expanded reviewed subset and four measured CPU comparisons. `expand_reviewed.py`
creates/checks a separate frozen release, preserving V1. Trainer now supports
`--backbone-mode frozen|last-block` (defaultfrozen; BN statistics fixed), and
`--checkpoint-criterion bce|count` (defaultbce). Count ranks development checkpoints
by exact stacks, MAE, position errors, BCE; it never certifies inventory. Default
architecture remains the baseline described below. Actual QA curves and fixed
training-target sigma are documented separately. No production model change.


Research baseline, not an exact warehouse counter. See
`reports/stack-heatmap-20260928/README.md` for measured results and failures.

## What runs

`build_dataset.py` inventories local content and freezes reviewed visible-layer
labels, preserving original hashes, quads, homographies and conservative session
groups. `model.py` imports the shared backend implementation. MobileNetV3 Small
ImageNet weights supply frozen stride-eight features (first four feature blocks);
horizontal mean pooling feeds a 24→32→1 Conv1d head interpolated to 640 vertical
positions. Only the head trains. Input is a complete rectified face normalized
to 640×192 with ImageNet normalization. Normalizing stack heights changes apparent
pitch; the small current training set does not generalize across stack sizes.

One manually reviewed center creates one Gaussian peak. Saved QA targets are
256 positions with pitch-dependent sigma; the training baseline regenerates the
same centers at640 with fixed sigma3px. BCE weight1, positive weight4, endpoint
loss0, scalar count loss0. Brightness/contrast0.9–1.1 are the only augmentations.
No bands, RF predictions, expected totals, vertical flips or cropped endpoints
become labels. Learning rate.003, Adam, seed20260928; threshold.5, peak distance8
and matching tolerance6 are fixed before validation, not tuned against the99 scene.

LOCO excludes a whole leakage group at a time; all five focused faces stay
together. Validation BCE selects the checkpoint and five stale epochs stop the
run. Raw-count exact rates and layer-position errors are both reported. Training
fit is never a holdout score. Each run records code hashes, start git commit,
manifest hash, scenes, config, loss history, checkpoints and count metrics.
Checkpoints remain under ignored `work/`; report metadata and QA are published.

`backend/app/vision/heatmap_sequence.py` retains pitch/harmonic alternatives,
competes nearby peaks, orders candidates and requires independent support for a
missing position. Endpoints are observed layer centers, not the crop border/rim.
Unknown endpoint/quality evidence stays unknown. RF is diagnostic support and
cannot independently reconstruct a missing layer. Occupancy remains a separate
unknown task. Neither model nor solver can emit verified inventory.

## Run locally

Use Python3.12 plus requirements.txt (CPU torch wheels are sufficient). Existing
`work/vision-deps` can supply NumPy/Pillow/OpenCV/scipy/FastAPI for this checkout.

```powershell
python model-improvement/stack-heatmap/build_dataset.py --check-only
python model-improvement/stack-heatmap/test_training.py
python model-improvement/stack-heatmap/train_heatmap.py --manifest reports/stack-heatmap-20260928/dataset/faces.json --output work/heatmap-loco --epochs 20 --mode loco
python model-improvement/stack-heatmap/evaluate.py --run work/heatmap-loco/fold-0/run.json --manifest reports/stack-heatmap-20260928/dataset/faces.json --output reports/heatmap-local/fold-0
python model-improvement/stack-heatmap/evaluate.py --run work/heatmap-loco/fold-1/run.json --manifest reports/stack-heatmap-20260928/dataset/faces.json --output reports/heatmap-local/fold-1
python model-improvement/stack-heatmap/summarize_cv.py reports/heatmap-local
python model-improvement/stack-heatmap/train_control.py --dataset reports/stack-heatmap-20260928/dataset/v5-clean-control --output work/v5-control --prepare-only
```

The last command records the incomplete-control gate rather than training blindly.
RF-DETR Medium/640 and compatible V2 checkpoint are the planned control; obtain and
pin the SDK/checkpoint and confirm identical fit-within preprocessing/augmentation
before interpreting a later comparison. Current V5 snapshot has no eligible
validation/full-frame control labels, so no V5 result exists.

Optional diagnostic host: install the heatmap extras, set server-only
STACK_HEATMAP_CHECKPOINT to a trusted local best.pt, VISION_SERVICE_TOKEN to a
secret32+characters, optionally STACK_HEATMAP_DEVICE=cpu|cuda. It loads once per
process. The existing authenticated vision-service entrypoint adds
`/candidate/stack-heatmap`; absent a checkpoint it returns503. It accepts multipart
image/evidence with source SHA, EXIF-transposed coordinates, source_view and up
to30 proposed quadrilaterals. Saved RF centers are optional and untrusted. It
returns image-quality diagnostics, all evidence and null inventory. It cannot
certify a client polygon or supply a cross-view grid. Verify a real checkpoint:
`python model-improvement/stack-heatmap/verify_route.py work/heatmap-loco/fold-0/best.pt`.

AWS configuration/container and production architecture are in `aws/README.md`.
The AWS path is prepared; billing approval, credentials/quotas, Docker build and
cloud execution remain separate. No APK/production route/model was changed.

Primary references:
[MobileNetV3 Small](https://docs.pytorch.org/vision/main/models/generated/torchvision.models.mobilenet_v3_small.html),
[RF-DETR training](https://rfdetr.roboflow.com/learn/train/).
