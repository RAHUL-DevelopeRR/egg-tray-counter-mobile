# Local Manual Dataset Audit

Source: `C:\Users\dharani\Downloads\Egg-Tray-Counter.yolov8 (1)`

> Read-only audit: source images and labels were not changed.

## Summary

- Format: YOLO detection/segmentation text
- Classes: `["Egg-Tray-Counter"]`
- Images / labels / annotations: 70 / 70 / 3372
- Split counts: `{"test": {"images": 6, "labels": 6}, "train": {"images": 57, "labels": 57}, "valid": {"images": 7, "labels": 7}}`
- Annotation types: `{"bbox": 2966, "polygon": 406}`
- Class distribution: `{"0": 3372}`
- Corrupt images: 0
- Missing / orphan labels: 0 / 0
- Exact duplicate image groups: 0
- Cross-split duplicate leakage groups: 0

## Annotation QA

Candidate duplicate IoU threshold: 0.85

- geometry_outside_image: 23
- high_overlap_pair: 0

## Distribution

- Image resolution: `{"height_max": 1600, "height_median": 1280.0, "height_min": 496, "unique": 10, "width_max": 1600, "width_median": 1200.0, "width_min": 368}`
- Normalized annotation area: `{"max": 0.5604828125, "median": 0.004040393743425668, "min": 2.557112068965328e-05}`
