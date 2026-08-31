# Production readiness gate

Decision: **NOT PRODUCTION READY**. Keep `projec-mutta/2` as the frozen comparison baseline; do not promote it as an accurate production counter.

## Blocking evidence

- Product baseline: exact 2/10, MAE 22.9 trays, mean relative error 41.57%.
- A true 60-tray scene produced 9, 12, and 93 detections across its three views.
- V2 contains only 69 train, 22 validation, and 8 test images; scene grouping is undocumented.
- Canonical data has three visually confirmed same-scene cross-split leaks.
- 34 canonical boxes extend outside image geometry and all 137 scene/view records still need human review.
- No independent, untouched 50-scene final acceptance set exists.

## Promotion requirements

1. Resolve all cross-split scenes and keep every LEFT/STRAIGHT/RIGHT capture from one scene in one split.
2. Complete `scene-metadata.csv`, independently verify tray totals, and review all annotation-policy violations.
3. Train the controlled experiments in `training-experiments.csv`; preserve all run IDs and metrics.
4. Select a candidate on the scene-grouped internal test, not Roboflow mAP alone.
5. Run once on 50 unseen scenes × three views and record every prediction in `final-acceptance-results.csv`.
6. Promote only if exact-count accuracy is at least 90%, MAE at most 1 tray, mean relative error at most 3%, and no count-range/viewpoint slice has a catastrophic miss over 10% relative error.

If these thresholds prove infeasible after the expanded real dataset, report the measured ceiling and require operator verification instead of hiding uncertainty.
