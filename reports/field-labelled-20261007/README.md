# Labelled field photos — V2 baseline, 7 October 2026

## Inputs

52 photos supplied by the user in `C:\Users\DELL\Downloads\FileOfEggLabels`,
copied byte-for-byte to `datasets/field-2026-10/labelled-20261007/originals/`
(SHA-256 per file in `manifest.json`, produced by `intake.py`).

- All are WhatsApp copies: 0.2-1.9 MP, no EXIF. Labels are handwritten totals
  drawn into the pixels; several photos also have bracket lines drawn across trays.
- The user states these are verified manual counts of the stack face.
  `labels.csv` is the assistant's transcription of those handwritten numbers;
  medium-confidence readings and unclear label scope are marked there and need
  user confirmation.
- Labels are scene/region totals, not per-stack counts. Multi-region labels
  (e.g. 120|115) are summed for scene scoring.
- Near-duplicate pairs by dHash: 42/48 (distance 1), 16/22, 8/23, 11/40, 25/27,
  21/24. Several further images show the same block from different angles
  (`same_scene_as` column). Images are therefore not independent samples.

## Method

`run_v2_baseline.py` sent every image through the unchanged production Worker
(`/v1/scans/count`, model_spatial_v1, Roboflow `projec-mutta/2`, confidence 35,
overlap 50) three images per request, using view slots as transport only.
Labels were not sent or read during inference. Per-image detection count is the
prediction. `score.py` compares it to the label afterwards. Images 1 and 2 were
run twice and returned identical counts (101, 81). One request hit a Windows
TLS error (SEC_E_MESSAGE_ALTERED) and succeeded on retry.

## Results (measured)

| Subset | n | Exact | Within ±2 | Within 5% | MAE | Label sum | V2 sum |
|---|---:|---:|---:|---:|---:|---:|---:|
| All photos | 52 | 5 | 12 | 16 | 45.1 | 5041 | 2839 |
| Block faces | 39 | 1 | 6 | 12 | 59.1 | 4931 | 2723 |
| Single stacks | 3 | 1 | 2 | 1 | 2.3 | 46 | 49 |
| Loose trays | 6 | 3 | 3 | 3 | 2.7 | 16 | 32 |
| Orange plastic | 11 | 0 | 1 | 1 | 86.9 | 1551 | 651 |

By capture condition (block faces only; tags in `capture_tags.csv`):

| Capture | n | Within 5% | Median abs % error | Worst |
|---|---:|---:|---:|---:|
| Frontal, one face filling the frame | 18 | 12 | 4.2% | 39.9% (img 28) |
| Angled, corner or multi-block | 16 | 0 | 70.2% | 100% |
| Distant or wide | 5 | 0 | 94.5% | 100% |

Same-block comparisons, which do not depend on the capture tags:

- Block labelled 80 (imgs 25/27/30/31): frontal 30 gives 81; oblique 31 gives 52;
  steep side views 25/27 give 18/20.
- Block labelled 109 (imgs 17/36): corner view 17 gives 60; frontal 36 gives 117.
- Wide/distant scenes collapse: img 33 (358) gives 1; imgs 12/13 (205/204) give 0;
  img 5 (235) gives 13.

## Interpretation

- V2 is usable only for square-on single faces that fill the frame, and even
  there totals are within ±2 on 6/18 and exact on 1/18. Scene totals hide
  per-stack errors; no per-stack truth exists for this set yet.
- Oblique and distant captures fail systematically, consistent with each tray
  layer becoming too small after the model's 640 px resize. This supports two
  measurable next steps: enforce frontal/fill-frame capture in the APK, and test
  tiled or per-face cropped inference for wide scenes.
- Capture tags were assigned by the assistant after seeing the errors, so they
  carry hindsight bias. The same-block comparisons above do not. Future sets
  should be tagged before inference.

## Limitations

- WhatsApp compression, missing EXIF and drawn ink may lower model performance
  versus original captures; un-annotated originals are needed for training and
  for the geometry check.
- Label scope is ambiguous for imgs 3, 26, 40, 41, 43, 52 (see `labels.csv`).
- No physical filled/empty split, per-stack truth or hidden-tray accounting is
  available from these labels. Nothing here establishes an inventory total.

## Files

`raw/batch-*.json` full Worker responses with detections; `results.csv`
per-image scores; `summary.json`; `capture_tags.csv`; `by_capture.py`.

## Per-stack manual verification and span counter — 8 October 2026

Scope: the 13 straight-on block photos (1, 2, 4, 8, 9, 19, 20, 21, 23, 24, 30,
34, 50). Each photo was cut into stack columns using the archived V2 box
x-centres, each column enlarged to 1100–1500 px tall, and inspected with
three overlays: model box centres, fitted rim grid, and per-layer cell strips.
Renders for the disputed columns are in `per-stack/`. Per-column results are in
`per_stack_counts.csv`; the method is `span_summary.py` and
`backend/app/vision/layer_span.py`.

Counting rule adopted: layers = round((last box centre − first box centre) /
median box spacing) + 1 (the **span count**). It removes duplicate boxes; it
cannot recover a top or bottom layer the model never boxed.

| Scene | User label | Raw V2 boxes | Span count | Assistant per-stack |
|---|---:|---:|---:|---|
| 19 | 100 | 100 | 100 | 20 ×5, high |
| 21 | 100 | 101 | 100 | 20 ×5, high |
| 24 | 100 | 101 | 100 | 20 ×5, medium-high |
| 2 | 80 | 81 | 81 | 20 ×4, medium-high |
| 20 | 60 | 63 | 61 | 20 ×3, medium |
| 30 | 80 | 81 | 79 | 20 ×4, medium |
| 34 | 120 | 125 | 121 | 20 ×6, medium-high |
| 8 | 160 | 157 | 158 | 20 ×8, medium |
| 23 | 160 | 157 | 158 | 20 ×8, medium |
| 1 | 99 | 101 | 100 | 20/20/20/20/19 (retained reference) |
| 4 | 115 | 110 | 111 | unresolved: two blocks at different depths merged by x-clustering |
| 9 | 75 | 71 | 74 | unresolved: three depths, one empty top tray, nested empties |
| 50 | 40 | 35 | 35 | unresolved: close-up from above, lower rows perspective-compressed |

Per column on the 53 resolved stacks (10 scenes): raw V2 box count exact
31/53 (58%), within ±1 49/53; span count exact 40/53 (75%), within ±1 53/53.
Scene totals from the span count are within 2 of the user label on all nine
single-block frontal scenes and exact on three.

Caveats, stated plainly:
- The per-stack "assistant" values for 20-per-stack scenes are inferred from
  the user's scene totals plus the ±1 machine evidence. They are not
  independent physical per-stack counts. At 1–2 MP WhatsApp resolution I could
  not reliably separate 19 from 20 by eye on every column.
- Egg-row heuristics based on whiteness or egg colour failed on these copies
  (colour cast, compression); they are not usable without original files.
- Rim-based grids were confused by background tray tops (img 8/23) and by
  wrong pitch priors (img 34 c4); the box-span method was not.
- Three failure modes now have evidence: multi-depth scenes merged into one
  column, perspective compression on close-ups from above, and detector misses
  at a column's top or bottom.

Tests: `backend/tests/test_layer_span.py` — 6 passed (synthetic duplicate /
missed-layer cases plus archived img19 → 20×5 and img21 duplicates removed).


## Follow-up 8 October 2026 — port parity and capture gate

- TypeScript `spanColumns` (Worker) vs Python `count_layers_by_span` on all 52
  archived photos: 180 columns, 1,440 values bit-identical, 0 mismatches.
  Two columns hit an exact .5 span ratio (img 17 right c4, img 41 right c4);
  half-to-even rounding in both languages keeps them equal.
- Capture gate (`captureQuality` in the Worker), tuned on the 39 tagged block
  photos: frontal_fill 17/18 accepted (img 4 rejected by height 0.395), angled
  13/16 and distant 5/5 rejected; imgs 25, 26, 41 pass the gate although tagged
  non-frontal. Thresholds: pitch gradient first-third vs last-third <= 1.2,
  frame-width coverage >= 0.45 (>= 0.25 for a single column), stack height
  >= 0.4 of frame height, no stacks -> reject. Tags were assigned after seeing
  the V2 errors; this is a tuning set, not validation.
