# Model improvement workspace

This workspace preserves the deployed `projec-mutta/2` Medium baseline and gates every future model on independent count metrics. RF-DETR Large and the policy-consistent V3 Medium candidate were evaluated and rejected; no replacement was promoted.

Current decision: **NOT PRODUCTION READY**.

## Status

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
