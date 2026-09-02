# Model improvement workspace

This workspace preserves the deployed `projec-mutta/2` Medium baseline and gates every future model on independent count metrics. RF-DETR Large was evaluated and rejected; no replacement was promoted.

Current decision: **NOT PRODUCTION READY**.

## Status

- Dataset audit: complete for the exact 99-image frozen V2 export, locally available V1, and `canonical_clean`.
- Full V2 visual policy gate: failed on 2026-09-02; all 99 images were opened and 27 clearly require manual relabeling. See `01-dataset-audit/v2-visual-policy-audit.md` and `v2-label-policy-review.csv`.
- Public-source discovery: complete; no external image was downloaded or added.
- Scene/view metadata: generated as a human-review queue; unknown fields were not guessed.
- Candidate training: Large run `9fd5202da865a4447708` completed; it regressed from 20% to 10% exact-count accuracy and was rejected.
- Next training: blocked until the 27 failed V2 images are manually corrected and all 99 pass full-resolution QA. No corrected version or Medium run was created from known-bad labels.
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
- `08-final-test/final-test-results.csv`
- `07-validation/failure-analysis.md`
- `08-final-test/final-acceptance-results.csv`
- `10-production/production-readiness.md`

Run `.venv/Scripts/python.exe model-improvement/evaluate_count_model.py --help` to reproduce count-model evaluation. The API key must be supplied only through `ROBOFLOW_API_KEY`.
