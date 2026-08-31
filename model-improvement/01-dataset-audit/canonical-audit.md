# Canonical Clean Dataset Audit

Source: `C:\Users\dharani\Documents\Codex\2026-08-20\roboflow-plugin-roboflow-roboflow-build-a\outputs\egg-tray-counter\datasets\canonical_clean`

> Read-only audit: source images and labels were not changed.

## Summary

- Format: YOLO detection/segmentation text
- Classes: `[]`
- Images / labels / annotations: 137 / 137 / 3683
- Split counts: `{"test": {"images": 11, "labels": 11}, "train": {"images": 106, "labels": 106}, "valid": {"images": 20, "labels": 20}}`
- Annotation types: `{"bbox": 3683}`
- Class distribution: `{"0": 3683}`
- Corrupt images: 0
- Missing / orphan labels: 0 / 0
- Exact duplicate image groups: 0
- Cross-split duplicate leakage groups: 0

## Annotation QA

Candidate duplicate IoU threshold: 0.85

- geometry_outside_image: 34
- high_overlap_pair: 0

## Distribution

- Image resolution: `{"height_max": 1600, "height_median": 640, "height_min": 496, "unique": 11, "width_max": 1600, "width_median": 640, "width_min": 368}`
- Normalized annotation area: `{"max": 0.9251193665956188, "median": 0.004098573281250008, "min": 1.2207031249998613e-06}`
