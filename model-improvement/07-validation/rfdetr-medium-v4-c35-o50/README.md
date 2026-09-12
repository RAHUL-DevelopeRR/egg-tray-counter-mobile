# V4 benchmark — 2026-09-08

**DO NOT DEPLOY.** V4 does not strictly beat both deployed V2 baseline metrics. No backend environment, Worker, or APK was changed.

| Model | Exact / 10 | MAE (trays) |
|---|---:|---:|
| Deployed V2 Medium (historical controlled baseline) | 2 | 22.9 |
| V3 Medium (historical comparison) | 2 | 20.7 |
| V4 Medium (this run) | 1 | 21.4 |

V4 improves MAE by 1.5 trays against V2 but loses one exact match. Promotion requires **exact > 2 AND MAE < 22.9**, not either metric alone. The only exact V4 case is img10, the single-tray frame; none of the nine stacked-tray cases is exact. Largest errors remain the 60-tray scene: predictions 11, 6, and 103 across its views. Those errors cannot be repaired by averaging or relaxing agreement.

## Reproduction and evidence

Run from the repository root with the API key in `ROBOFLOW_API_KEY`:

```powershell
.\.venv\Scripts\python.exe model-improvement/evaluate_count_model.py --model rahuls-workspace-l9ylz/projec-mutta-4-rfdetr-medium-t1 --confidence 35 --overlap 50 --output model-improvement/07-validation/rfdetr-medium-v4-c35-o50
```

The evaluator is unchanged (SHA-256 `50CE5E443824679099C52729E799A661BD81865C6510698A577702EFF9D70F04`). The original `accuracy-evaluation/manual-ground-truth.csv` is unchanged. Its source suffix selects img01–04.jpg, img05–07.jpeg, img08–10.jpg; stale alternate extensions are ignored, not substituted. `input-hashes.csv` records the actual ten inputs. `raw-json/` preserves all responses, `count-results.csv` every prediction/error, and `summary.json` the aggregate.

Training `518b30dcad42a78a5d33` finished on September 7 at 21:56 IST. V4 is 75 images (54/16/5), including only three new warehouse crops with 47 individual-tray boxes, not the entire new folder. Roboflow's reported mAP50 71.48%, precision 78.2%, recall 66.3% are detection metrics, not count accuracy.

This ten-image set is a repeated development benchmark, contains related scene views, and is not an independent final acceptance set. No near-100% generalization claim is supported. See the separate [warehouse spot check](../warehouse-spot-check-20260908/README.md).

Next useful work: review missed/extra individual-tray boxes on full-frame warehouse development scenes, keep physically related scenes in the same split, and reserve new physically counted scenes untouched for acceptance. Do not repeatedly tune this ten-file test or treat V4's three training crops as test data.
