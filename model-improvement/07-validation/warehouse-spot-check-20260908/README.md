# User-supplied warehouse spot check — 2026-09-08

Both models were tested on identical original attachment bytes using the unchanged evaluator, confidence 35%, overlap 50%, and class `egg_tray`. Ground truth is the user's stated visible tray counts, not model-derived labels.

| Photo | User ground truth | V2 prediction | V4 prediction |
|---|---:|---:|---:|
| Front | 100 | 101 | 101 |
| Side | 40 | 42 | 43 |
| Exact matches | — | 0/2 | 0/2 |
| MAE (trays) | — | 1.5 | 2.0 |
| Mean per-image count closeness* | — | 97.0% | 95.75% |

*Evaluator's `max(0, 100 * (1 - absolute_error / truth))`, averaged per image. This is **not exact-count accuracy**, which is 0% on these two images. V4 is worse on the side photo and tied on the front photo. The previous APK screenshot's 39/43/97 counts are historical outputs from a different request; they are not substituted for this same-byte comparison.

Only two distinct originals were supplied for the described Left/Right/Straight scan. We did not duplicate the side image to fabricate a third independent test. These photos relate to the warehouse development imagery; scene independence from training has not been established. This is a development spot check, not a statistically representative held-out real-world accuracy estimate or an end-to-end APK/device test.

The three V4 training crops were not tested as held-out evidence. Counts from different physical sets (40 on each side versus 100 in front) must not be required to agree as if they cover the same trays, nor summed without establishing disjoint coverage. Capture the same physical stack/cell across views; cell IDs can help association but do not supply tray counts.

## Reproduction

`manifest.csv` records the original attachment paths and user-provided truth. Copy those files byte-for-byte to `work/warehouse-spot-check-20260908/front.jpg` and `side.jpg` if needed. SHA-256:

- front: `77AA8978C07B1E70A24BA83A65EDACF12DB33A4FC4216C684CC4C29D8AF62FC3`
- side: `F2DE6037E2A8022B97C650757123BD64644A18A129A7720EFE4C32DF450844CE`

Run the following with `N` replaced by 2 and then 4, and the API key supplied through the environment:

```powershell
.\.venv\Scripts\python.exe model-improvement/evaluate_count_model.py --model rahuls-workspace-l9ylz/projec-mutta-N-rfdetr-medium-t1 --manifest model-improvement/07-validation/warehouse-spot-check-20260908/manifest.csv --images work/warehouse-spot-check-20260908 --confidence 35 --overlap 50 --output model-improvement/07-validation/warehouse-spot-check-20260908/vN
```

Each model directory contains raw responses, per-image counts, and aggregate metrics. **DO NOT DEPLOY V4**: it also failed the original ten-file gate. Production remains V2.
