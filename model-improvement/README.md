# Model improvement workspace

This workspace preserves the deployed `projec-mutta/2` baseline and gates every future model on independent count metrics. No new model has been trained or promoted from these files.

Current decision: **NOT PRODUCTION READY**.

## Status

- Dataset audit: complete for locally available V1, V2 metadata, and `canonical_clean`.
- Public-source discovery: complete; no external image was downloaded or added.
- Scene/view metadata: generated as a human-review queue; unknown fields were not guessed.
- Candidate training: blocked until scene grouping and annotation review are complete.
- Final acceptance set: not yet collected; it must stay unseen until model selection.

## Files

- `01-dataset-audit/dataset-audit.md`
- `01-dataset-audit/dataset-stats.csv`
- `01-dataset-audit/duplicate-report.csv`
- `02-external-data/dataset-sources.csv`
- `03-clean-dataset/scene-metadata.csv`
- `04-annotations/annotation-policy.md`
- `05-training/training-plan.md`
- `06-experiments/training-experiments.csv`
- `06-experiments/model-comparison.md`
- `07-validation/validation-results.csv`
- `07-validation/failure-analysis.md`
- `08-final-test/final-acceptance-results.csv`
- `10-production/production-readiness.md`

Run `python model-improvement/build_audit.py` to regenerate distribution, duplicate-screening, and scene-review CSV files from the canonical manifest.
