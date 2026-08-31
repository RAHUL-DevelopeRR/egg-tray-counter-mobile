# Egg Tray Counter — Current-Model Accuracy Baseline

Evaluation date: 2026-08-31
No model was retrained during this evaluation.

## Current model

| Setting | Deployed value |
|---|---|
| Workspace | `rahuls-workspace-l9ylz` (repository/Universe reference; the live Worker response leaves this field blank) |
| Project | `projec-mutta` |
| Version | `2` |
| Model | RF-DETR Medium (`projec-mutta/2`) |
| APK backend | `https://egg-tray-counter-api.rahultech72216.workers.dev` |
| Roboflow endpoint | `https://serverless.roboflow.com/projec-mutta/2` |
| Confidence | 35% (`0.35`) |
| Overlap / NMS | 50% (`0.50`) |
| Class filter | `egg_tray` |
| Tray conversion | 1 tray = 30 eggs |

The Cloudflare Worker sends each image to the endpoint above, filters to the `egg_tray` class, and counts the returned predictions. It does not apply another geometric filter or NMS pass. Direct Roboflow and Worker per-view counts matched on all 10 frames. Flutter parses and displays the Worker response without changing the tray count.

The app's three-view fusion is a separate safety rule: at least two positive view counts must agree exactly and the maximum/minimum positive-count ratio must be no greater than 1.25. Otherwise it requests a rescan.

## Ground-truth method

Ten real frames were inspected independently. Tray layers were counted from visible stack boundaries; the repeated 60-tray scene was checked as three 20-tray stacks, the 120-tray wall as six 20-tray stacks, and the brown scene as two 16-tray stacks. Four photos whose physical count could not be recovered reliably were marked `ground_truth_uncertain` and excluded from the final benchmark; see `ground-truth-exclusions.csv`.

One of the ten accepted frames comes from the held-out validation split to complete a genuine left/right/straight view set. No training image was used.

## Accuracy summary

| Metric | Result |
|---|---:|
| Valid images evaluated | 10 |
| Exact matches | 2 / 10 |
| Exact-count accuracy | 20.0% |
| Mean absolute error (MAE) | 22.9 trays |
| Mean relative error | 41.57% |
| Mean count accuracy | 58.43% |
| Average ground truth | 49.7 trays |
| Average prediction | 39.6 trays |
| Largest undercount | 51 trays (`img01`: 60 → 9; tied by `img09`: 76 → 25) |
| Largest overcount | 33 trays (`img03`: 60 → 93) |
| Best frames | `img07`, `img10` (exact) |
| Worst frame | `img01` (85.00% relative error) |

## Detailed comparison

`Backend` is the production Worker's count for that exact view. App fused output is not a per-image value, so it is reported separately in the multi-view section.

| Image | Ground truth | Eggs | Roboflow raw | Backend | Predicted eggs | Abs. error | Relative error | Count accuracy | Exact |
|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| img01 | 60 | 1,800 | 9 | 9 | 270 | 51 | 85.00% | 15.00% | No |
| img02 | 60 | 1,800 | 12 | 12 | 360 | 48 | 80.00% | 20.00% | No |
| img03 | 60 | 1,800 | 93 | 93 | 2,790 | 33 | 55.00% | 45.00% | No |
| img04 | 32 | 960 | 29 | 29 | 870 | 3 | 9.38% | 90.62% | No |
| img05 | 120 | 3,600 | 124 | 124 | 3,720 | 4 | 3.33% | 96.67% | No |
| img06 | 21 | 630 | 9 | 9 | 270 | 12 | 57.14% | 42.86% | No |
| img07 | 21 | 630 | 21 | 21 | 630 | 0 | 0.00% | 100.00% | Yes |
| img08 | 46 | 1,380 | 73 | 73 | 2,190 | 27 | 58.70% | 41.30% | No |
| img09 | 76 | 2,280 | 25 | 25 | 750 | 51 | 67.11% | 32.89% | No |
| img10 | 1 | 30 | 1 | 1 | 30 | 0 | 0.00% | 100.00% | Yes |

## Multi-view test

`img01`, `img02`, and `img03` are the same 60-tray scene.

| View | Prediction | Error |
|---|---:|---:|
| Left / side | 9 | -51 |
| Right / close | 12 | -48 |
| Straight | 93 | +33 |

The straight view was best but still overcounted by 33. The production Worker correctly rejected fusion (`rescan_required`) because 9, 12, and 93 are inconsistent; it returned no final tray or egg count. This prevents a confidently wrong app result but does not recover the correct count.

## Threshold experiment

Counts shown below use overlap 50%. Bold values are closest to each image's manual count within the tested thresholds.

| Image (truth) | 10% | 20% | 30% | 35% deployed | 40% | 50% |
|---|---:|---:|---:|---:|---:|---:|
| img04 (32) | 43 | 34 | **31** | 29 | 29 | 27 |
| img05 (120) | 146 | 132 | 125 | 124 | 123 | **122** |
| img08 (46) | 211 | 99 | 79 | 73 | 71 | **65** |

Lowering confidence produces many false positives on dense/elevated stacks. Across these three frames, 50% had the lowest tested MAE (8.67 trays), but it still overcounted `img08` by 19 and undercounted `img04` by 5. Therefore threshold-only tuning is insufficient.

For `img05`, changing overlap/NMS from 20%, 35%, 50%, 70%, to 90% always returned 124. NMS overlap is not the source of that frame's four-count error.

## Example evidence and failure analysis

### img01 — severe side-view undercount

- Ground truth: 60
- Roboflow raw / backend: 9 / 9
- App: no fused result; rescan required
- Absolute error: 51
- Evidence: most horizontal tray layers have no detection in the saved overlay.
- Likely cause: strong perspective and long side-facing tray geometry are outside the detector's reliable appearance range.

### img05 — 120-tray straight wall

- Ground truth: 120
- Roboflow raw / backend: 124 / 124
- App: not tested as a genuine three-view set
- Absolute error: 4
- Evidence: nearly all rows are detected, with a few extra/duplicate boxes.
- Likely cause: local duplicate/false-positive detections, not backend filtering. The currently deployed endpoint does **not** reproduce the earlier 19-tray result on this straight frame.

### img08 — elevated-angle overcount

- Ground truth: 46
- Roboflow raw / backend: 73 / 73
- App: not tested as a genuine three-view set
- Absolute error: 27
- Evidence: the overlay contains row boxes plus large/overlapping top-surface boxes.
- Likely cause: duplicate and false-positive detections under an elevated perspective. Lower confidence makes this much worse.

### img09 — distant/low-light undercount

- Ground truth: 76
- Roboflow raw / backend: 25 / 25
- Absolute error: 51
- Evidence: detections cover only a central subset; most distant left/right tray rows are missed.
- Likely cause: small tray scale, distance, perspective, and darker exposure.

## Diagnosis

The main accuracy issue is **MODEL + VIEWPOINT SENSITIVITY**, with **MULTI-VIEW LOGIC** acting only as a rejection/safety layer.

- Model: primary cause. Direct Roboflow and backend counts are identical, yet errors vary from exact to 85.0% depending on view.
- Backend: not the cause of per-view count loss; it preserves the Roboflow count.
- Flutter post-processing: not the cause; it does not modify counts.
- Confidence/NMS: secondary. Confidence 50% reduces some overcounting but does not make difficult views accurate. NMS overlap had no effect on the tested 120-tray wall.
- Multi-view fusion: safely rejects inconsistent views but requires exact agreement, so it will reject many real scans rather than estimate a result.

## APK execution status

The APK artifact exists, but no Android device or emulator was available: ADB reported an empty device list and the local Android SDK has no emulator package/AVD. Therefore the APK UI was **not** falsely claimed as executed. The exact production Cloudflare endpoint called by the APK was tested directly, including a genuine three-view request.

## Recommendation

1. Do not retrain from the current labels blindly. First define the counting unit precisely and manually relabel side, distant, elevated, dense, and partial views.
2. Add the failed frames from this baseline to a dedicated evaluation/feedback set, especially the 60-tray three-view scene.
3. Retrain with substantially more viewpoint-diverse examples or test a stronger detector, then rerun this unchanged benchmark.
4. Change fusion from exact count agreement to evidence-based view selection/robust aggregation only after per-view validation; exact agreement is too brittle.
5. Consider row/stack-count estimation or a hybrid detector + structural row counter for dense walls, where individual tray boxes are highly repetitive.
6. Keep confidence near 0.35–0.50 during the next evaluation. Do not lower it globally; the current sweep shows that would sharply increase false positives.

## Evidence files

- `manual-ground-truth.csv` — accepted manual counts and scene notes
- `ground-truth-exclusions.csv` — ambiguous images excluded from primary metrics
- `results.csv` — per-image calculations
- `threshold-experiment.csv` — confidence and overlap sweep
- `multi-view-result.json` — genuine three-view production response
- `raw-json/` — full direct Roboflow and Worker responses
- `detections/` — saved detection overlays
- `test-images/` — exact evaluated frames
- `run_baseline.py` — reproducible evaluator; requires `ROBOFLOW_API_KEY` at runtime
