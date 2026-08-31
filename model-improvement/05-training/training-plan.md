# Controlled training plan

Training is gated on human-reviewed scene metadata and labels. Starting another cloud run on the current data would spend credits without fixing the known cause.

## Experiments

1. **A — frozen baseline:** RF-DETR Medium, V2, 640 fit-within. Already measured.
2. **B — clean-control:** RF-DETR Medium on the reviewed, scene-split individual-tray dataset at 640.
3. **C — balanced-data:** same architecture and settings as B, but with the expanded 800-image development set. This isolates the effect of data.
4. **D — architecture:** RF-DETR NAS on exactly C's frozen version, if plan entitlement permits; otherwise RF-DETR Large. Select by count metrics, not mAP.
5. **E — resolution/tile:** best B–D model at 960 or the highest supported practical resolution; separately evaluate 2×2 tiled inference with duplicate merging.
6. **F — stack-face hybrid:** detect stack faces, rectify perspective, run the existing horizontal-periodicity counter per face, then sum stacks.
7. **G — viewpoint-aware:** only if C remains view-sensitive, compare a lightweight LEFT/RIGHT/STRAIGHT classifier plus calibrated view selection against the universal model.

## Realistic augmentation

Use auto-orient, fit-within resize, mild brightness/exposure/contrast, JPEG compression, slight blur/noise, small rotations, and modest perspective. Exclude vertical flips, extreme rotation, severe warping, and crops that remove stack top/bottom.

## Selection gate

For each candidate, run the unchanged 10-frame baseline and a scene-held-out validation set. Record exact accuracy, MAE, RMSE, mean relative error, median absolute error, worst errors, under/over rates, view-specific metrics, latency, and abstention coverage. Promote only after the untouched 50-scene acceptance test.
