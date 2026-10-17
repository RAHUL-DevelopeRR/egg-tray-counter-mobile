# Controlled training plan

2026-09-28 follow-up result: four actual controlled CPU arms completed on the
new frozen11face/152center subset, keeping2whole leakagegroups. Frozen/count
3/11exactMAE5.091; last-block/count2/11MAE4.818; BCEarms1/11MAE13 and0/11MAE13.818.
Checkpoint selection is now an explicit experiment factor; no threshold tuning.
See ../../reports/stack-heatmap-followup-20260928/README.md for per-stack errors,
code/checkpoint hashes, next pitch/semantic experiments and unresolved gates.
These are development validation, not independent acceptance or filled inventory.


2026-09-28 active milestone: V5-CLEAN-CONTROL and STACK-HEATMAP-HYBRID-V1.
Use [stack experiment](../stack-heatmap/README.md). Existing reviewed data may
support grouped development training before new physical acceptance collection.
Two local group-held-out heatmap runs completed and failed0/7exact MAE12.142857.
V5control snapshot remains incomplete/ineligible; no ordinary blind retrain.
The historical experiment ladder below is not authorization to change several
architecture/data/threshold variables together. Production requires untouched
physical warehouse truth; AWS GPU/account charges require explicit approval.

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
