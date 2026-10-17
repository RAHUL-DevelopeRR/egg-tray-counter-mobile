# Stack crop diagnostic — 2026-09-24

Completed 12 fresh V2 image inferences through four HTTP 200 Worker requests.
The API's three view slots were used as diagnostic input slots, not as valid
multi-view scenes. No scan total is accepted. Originals, crops, raw responses,
detection overlays and results.json are retained here.

| Input | Stack 1 | Stack 2 | Stack 3 | Stack 4 | Stack 5 | Sum |
|---|---:|---:|---:|---:|---:|---:|
| Assistant manual visible reference | 20 | 20 | 20 | 20 | 19 | 99 |
| Axis-aligned crops, centres within reviewed face | 13 | 14 | 17 | 14 | 15 | 73 |
| Perspective-corrected faces | 19 | 22 | 20 | 22 | 17 | 100 |
| Band candidates on corrected faces | 12 | 11 | 19 | 19 | 10 | 71 |

Fresh full-wide control: 76. Fresh side control: 19. Model projec-mutta/2;
production confidence 35%, overlap 50%, unchanged. Axis-aligned raw counts
13/14/17/17/16 include neighbouring-face detections; centre filtering removes
these using the manually reviewed quadrilaterals. Counts are not inventory totals.

The corrected-image total error is +1, but summed absolute per-stack error is
7 and only one of five stack counts matches. This is not 99% validated accuracy:
errors cancel, and equal counts do not establish correct instance detections.
Visual inspection of corrected stacks 2/4/5 shows overlapping boxes, missed rows
and boxes spanning multiple rows. Approximate row-centre diagnostics are in JSON;
they are not detection precision/recall against verified instance boxes.

Automatic localization was tested separately on the fresh wide detections. It
produces eight regions for five visible stacks. See automatic-localization.jpg.
Manual crop success cannot therefore be presented as an automatic pipeline fix.
Perspective correction changes both geometry and framing; this experiment does
not isolate angle as the sole cause, nor test unseen scenes.

Higher confidence post-filters were evaluated at 45/55/65%. Corrected totals
become 89/78/66; none gives the correct five stack counts. Lower thresholds cannot
be tested through the current Worker, which fixes inference at 35%. No production
threshold was changed and missing lower-confidence predictions were not invented.

## Targeted retraining configuration and next steps

1. Keep this scene, its side photo and every derived crop in TRAIN only. The
   originals already received 118 approximate corrections in Roboflow. Review
   bounding extents and enforce one consistent box per physical tray before
   training; duplicate/spanning labels must not teach contradictory semantics.
2. Build a curated frozen dataset containing the corrected originals plus
   reviewed complete stack-face examples across camera angles. Preserve existing
   held-out scenes and separate by physical scene/session, not individual image.
   Do not treat these known examples as an independent test set.
3. First training comparison: existing RF-DETR Medium family, previous compatible
   checkpoint where available, existing 640 fit-within preprocessing. Compare
   original-frame and rectified-face inputs with the same split. Add only reviewed
   transforms that preserve tray labels; do not infer hidden occupancy from them.
4. Evaluate per-stack exact count, absolute count error, missed/duplicate trays and
   rejection rate on independent physical recounts. Separately measure automatic
   face localization. Do not promote a model based on a near-correct scene sum.
5. Fix/validate face localization before integrating rectification in the APK
   backend. Then test unchanged-scene matching for duplicate removal across views.

Training has NOT started. The paid curated-tag editor is a specific UI blocker;
it does not prove all Roboflow training is paid or unavailable. A reviewed local
export and user-accessible GPU route remain alternatives. No cloud account or
Python host was created, no APK rebuilt, and no new model deployed.

## Reproduce

Run scripts/evaluate_stack_crops.py from repository root with backend and installed
vision dependency directories on PYTHONPATH. Default execution regenerates crops,
overlays, bands and results from saved responses without network inference.
--run requests only batches whose saved response file is absent.
OpenCV uses one thread because its default threaded warp failed in this runtime.

Verification: all four response files parsed; 12 results generated; offline replay
reproduced all counts; manual reference sum assertion passed; git diff --check
passed. This is an assisted image experiment, not a reconstructed 3D count or
physically verified warehouse inventory.
