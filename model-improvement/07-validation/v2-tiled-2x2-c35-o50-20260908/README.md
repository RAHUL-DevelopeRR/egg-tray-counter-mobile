# Fixed SAHI-style tiled V2 experiment — 2026-09-08

**DO NOT DEPLOY.** Exact count **0/10**, MAE **46.2 trays**, versus the same-day single-pass V2 **2/10**, MAE **22.9**. Seven images overcount; three undercount. The exact same ten-image manifest, source-suffix selection, confidence 35%, overlap 50%, and count metric formula were retained. No threshold/grid search was performed after seeing results.

## Method

The configuration was fixed before inference: two tiles per dimension, 20% tile overlap, four tiles per image, plus the full-image result; translate tile boxes to original coordinates and perform global class-specific OpenCV NMS at IoU 0.5. Lossless PNG crops preserve decoded pixels. Full-image results are reused from the immediately preceding V2 regression run, not a different model. This used 40 additional API calls; no training.

This is a minimal **SAHI-style experiment**, not a claim of equivalence to every SAHI implementation or its default merge strategy. Slicing, coordinate shifting, and postprocessing follow the [SAHI sliced-inference design](https://obss.github.io/sahi/predict/). We reused installed Pillow/OpenCV/httpx and the original evaluator's `summarize` function; `evaluate_count_model.py` itself and its manifest were not modified. The new harness records identical per-image count metrics plus tile timing. The tile timing excludes the cached full pass and is not end-to-end mobile latency.

```powershell
.\.venv\Scripts\python.exe model-improvement/evaluate_tiled_count_model.py --self-check
# ROBOFLOW_API_KEY must be supplied through the process environment.
.\.venv\Scripts\python.exe model-improvement/evaluate_tiled_count_model.py
```

`config.json` records fixed parameters and all ten input hashes; `count-results.csv` preserves every case; `raw-json/` contains full responses, tile offsets/content hashes, translated merged results, and pre-merge counts. Resume verifies the same config and crop hashes; HTTP/response failures never become zero predictions or a partial benchmark score. Unit checks cover tile coverage, offsets, duplicate suppression, invalid responses, and shared metrics.

## Interpretation

More detections did not mean more correct counts. For example, the one-tray img10 becomes four detections after merging (seven before): a full-tray box and smaller tile-local fragments survive IoU suppression. This illustrates a stitching/fragment failure mode; it does not quantify all false positives without box-level ground truth. Dense img08 changes from 73 to 172 for truth 46; img09 from 25 to 172 for truth 76.

V4 recall alone cannot establish that missed trays are the only important error source: the count benchmark also has serious overcounts. This fixed slicing variant regresses; it does not prove that all slicing methods fail. Any later stitching change must be chosen/checked on development scenes, then assessed with the same gate, without cherry-picking or repeated threshold optimization on these ten images.

No Worker environment, deployed model, release APK, or Roboflow dataset was changed by this experiment. Retraining remains blocked by incomplete full-frame annotation review and the user's other prerequisites. New independent acceptance scenes remain necessary for real-world accuracy claims.
