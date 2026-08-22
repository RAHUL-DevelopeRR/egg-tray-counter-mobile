# Roboflow Auto Dataset Audit

Source: `C:\Users\dharani\Documents\Codex\2026-08-20\roboflow-plugin-roboflow-roboflow-build-a\outputs\egg-tray-counter\datasets\roboflow_auto_original`

> Read-only audit: source images and labels were not changed.

## Summary

- Format: YOLO detection/segmentation text
- Classes: `["egg_tray"]`
- Images / labels / annotations: 371 / 371 / 102723
- Split counts: `{"test": {"images": 37, "labels": 37}, "train": {"images": 260, "labels": 260}, "valid": {"images": 74, "labels": 74}}`
- Annotation types: `{"bbox": 15811, "polygon": 86912}`
- Class distribution: `{"0": 102723}`
- Corrupt images: 0
- Missing / orphan labels: 0 / 0
- Exact duplicate image groups: 1
- Cross-split duplicate leakage groups: 0

## Annotation QA

Candidate duplicate IoU threshold: 0.85

- exact_duplicate_annotation: 37
- high_overlap_pair: 5572

## Distribution

- Image resolution: `{"height_max": 640, "height_median": 640, "height_min": 640, "unique": 1, "width_max": 640, "width_median": 640, "width_min": 640}`
- Normalized annotation area: `{"max": 0.9251193699237017, "median": 8.859536082474206e-05, "min": 6.103515624999307e-07}`
