# Model improvement workspace

This workspace preserves the deployed `projec-mutta/2` Medium baseline and gates every future model on independent count metrics. RF-DETR Large and the policy-consistent V3 Medium candidate were evaluated and rejected; no replacement was promoted.

Current decision: **NOT PRODUCTION READY**.

## Status

- 2026-09-08 cell-identity fix implemented locally in Worker/mobile: operator-entered per-photo cell IDs, same-cell grouping, manual recount for unresolved cells, old-server rejection. Eight Worker tests and five Flutter tests pass; analyzer clean. V2 regression remains **2/10 exact, MAE 22.9**. **Not deployed** under the strict shipment gate; independent safety-fix approval requested.
- Fixed V2 SAHI-style 2x2 tiling trial: **0/10 exact, MAE 46.2; DO NOT DEPLOY**. Forty tile requests, unchanged confidence 35 / overlap 50, no post-result tuning. See [tiled evidence](07-validation/v2-tiled-2x2-c35-o50-20260908/README.md).
- Warehouse convention confirmed: **only egg-filled trays**, one box per individual tray layer; empty nested trays are non-targets. All 74 originals are hash-verified and have an explicit review-queue row. Full-frame box review is **incomplete** (two local 7-box drafts, zero training approvals). Do not confuse contact-sheet triage, a convention assignment, or prior crop labels with complete annotation. Retraining/data expansion release remains blocked.
- V4 pilot **COMPLETED; DO NOT DEPLOY** (evaluated 2026-09-08): unchanged ten-file benchmark at confidence 35 / overlap 50 gives **1/10 exact, MAE 21.4**, versus deployed V2 **2/10, MAE 22.9**. Strict two-metric gate failed. Two supplied warehouse photos: V4 **0/2 exact, MAE 2.0** versus V2 **0/2, MAE 1.5**; these are not an independent acceptance set. Production unchanged. V4 trained on 75 images (54/16/5), adding only three crops / 47 tray boxes, not the whole folder. See [benchmark evidence](07-validation/rfdetr-medium-v4-c35-o50/README.md) and [warehouse comparison](07-validation/warehouse-spot-check-20260908/README.md).
- New warehouse intake (2026-09-07): 82 files, 74 byte-unique images, eight duplicates. Three images / 24 stack-face boxes saved to Roboflow, isolated from the legacy individual-tray dataset. **Training not started; DO NOT DEPLOY.** New-image diagnostics expose both a target-unit mismatch and layer-counting failures. See [warehouse checkpoint](09-data-expansion/warehouse-2026-09-07/README.md). APK 0.1.1 was rebuilt, but contains no accuracy upgrade.
- Dataset audit: complete for the exact 99-image frozen V2 export, locally available V1, and `canonical_clean`.
- Full V2 visual policy gate: failed on 2026-09-02; all 99 images were opened and 27 conflicted assets were identified. Those 27 were removed from `projec-mutta` (retained in the workspace asset library), leaving 72 policy-consistent images. See `01-dataset-audit/v2-visual-policy-audit.md` and `v2-label-policy-review.csv`.
- Public-source discovery: complete; no external image was downloaded or added.
- Scene/view metadata: generated as a human-review queue; unknown fields were not guessed.
- Candidate training: Large run `9fd5202da865a4447708` completed; it regressed from 20% to 10% exact-count accuracy and was rejected.
- V3 candidate: frozen as `V3 Policy-Consistent 72` with 51 train / 16 validation / 5 test images, Auto-Orient plus Fit within 640x640, and no augmentations. RF-DETR Medium run `0981ff81168f8d0f02da` (`projec-mutta-3-rfdetr-medium-t1`) completed from the V2 Medium checkpoint with mAP@50 74.3%, precision 84.3%, recall 67.5%, and F1 75.0%.
- V3 count gate: **DO NOT DEPLOY**. On the unchanged 10-file benchmark at confidence 35% and overlap 50%, V3 scored 2/10 exact and MAE 20.7. MAE improved from 22.9, but exact match did not strictly exceed the deployed Medium baseline's 2/10, so the two-metric promotion gate failed and production remains on V2.
- Final acceptance set: not yet collected; it must stay unseen until model selection.

## Files

- `01-dataset-audit/dataset-audit.md`
- `01-dataset-audit/dataset-stats.csv`
- `01-dataset-audit/duplicate-report.csv`
- `01-dataset-audit/v2-image-manifest.csv`
- `01-dataset-audit/v2-label-policy-review.csv`
- `01-dataset-audit/v2-visual-policy-audit.md`
- `02-external-data/dataset-sources.csv`
- `03-clean-dataset/scene-metadata.csv`
- `04-annotations/annotation-policy.md`
- `05-training/training-plan.md`
- `06-experiments/training-experiments.csv`
- `06-experiments/model-comparison.md`
- `07-validation/validation-results.csv`
- `07-validation/validation-count-results.csv`
- `07-validation/viewpoint-consistency.csv`
- `07-validation/error-analysis.md`
- `07-validation/rfdetr-large-c35-o50/`
- `07-validation/rfdetr-medium-v3-c35-o50/`
- `08-final-test/final-test-results.csv`
- `07-validation/failure-analysis.md`
- `08-final-test/final-acceptance-results.csv`
- `10-production/production-readiness.md`

Run `.venv/Scripts/python.exe model-improvement/evaluate_count_model.py --help` to reproduce count-model evaluation. The API key must be supplied only through `ROBOFLOW_API_KEY`.
