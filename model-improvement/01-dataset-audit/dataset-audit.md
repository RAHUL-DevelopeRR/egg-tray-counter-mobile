# Dataset and model audit

## Verified deployed state

| Item | Value |
|---|---|
| Workspace | `rahuls-workspace-l9ylz` |
| Project | `projec-mutta` |
| Project type / class | object detection / `egg_tray` |
| Deployed version | `projec-mutta/2` |
| Architecture | RF-DETR Medium |
| Inference preprocessing | V2: auto-orient, fit-within 640×640 |
| Confidence / overlap | 35% / 50% |
| V2 frozen split | 69 train / 22 valid / 8 test (99 images) |
| Model-record metrics | mAP50 69.28%, precision 79.7%, recall 67.3%, F1 73.0% |
| Product baseline | exact 2/10, MAE 22.9, mean relative error 41.57% |

## Data inventory

| Dataset | Images | Annotations | Train / valid / test | Main issue |
|---|---:|---:|---:|---|
| Original manual export | 70 | 3,372 | 57 / 7 / 6 | 406 polygons, 23 out-of-image geometries; scene IDs absent |
| Roboflow V1 local export | 371 | 102,723 | 260 / 74 / 37 | 86,912 polygons, 5,572 high-overlap pairs, 37 exact duplicate annotations |
| Canonical cleaned local | 137 | 3,683 | 106 / 20 / 11 | 34 clipped/out-of-image boxes remain; view and scene metadata absent |
| Roboflow V2 frozen version | 99 | API does not expose count here | 69 / 22 / 8 | too small and not proven scene-grouped |

Roboflow V1 averages 276.9 annotations per image, versus 26.9 in the canonical set. Its median normalized annotation area is `0.0000886`, compared with `0.00410` in canonical. That 46× area difference plus the large polygon/overlap counts is strong evidence that V1 auto-labels do not follow one consistent physical-tray policy.

## Exact diagnosis

1. **Viewpoint coverage is unknown, therefore not balanced.** There are no reliable LEFT/RIGHT/STRAIGHT labels in the canonical manifest. All 137 rows are reported as `UNKNOWN`, not guessed. The same 60-tray scene producing `9 / 12 / 93` is direct evidence that viewpoint generalization failed.
2. **Annotation policy is mixed.** Original sources contain bounding boxes and polygons, tiny fragments, out-of-image geometry, and extensive overlap. Individual visible tray layers, whole trays, fragments, and auto-generated shapes were not consistently separated.
3. **Training volume is too small for the observed variation.** V2 has only 69 training images while the product must cover color, material, lighting, distance, stack height, occlusion, and three camera views.
4. **Small repetitive targets are resolution-sensitive.** Dense distant tray boundaries become only a few pixels high after 640-pixel resizing. V1 also used stretch-to-640, which changes aspect ratios; V2 corrected this to fit-within, but still loses distant detail.
5. **Scene-level leakage was not controlled.** Exact SHA duplicates are absent from canonical, but dHash screening found 9 near-duplicate pairs, including 3 cross-split candidates. These require visual review. Timestamp-adjacent LEFT/STRAIGHT/RIGHT photographs may still represent the same scene even when hashes differ.
6. **The product test is undersized.** V2 has eight test images and no documented scene grouping. It cannot support a production claim.
7. **Threshold/NMS is not the root cause.** Previous experiments showed confidence changes reduce some false positives but do not repair side-view misses; overlap 20–90% did not change the 120-tray result.
8. **Backend/app logic is not removing detections.** Direct Roboflow and Cloudflare per-view counts matched on all ten baseline frames.

## Current distribution limitations

`dataset-stats.csv` reports split, source, and annotation-count proxy ranges. It intentionally reports `view=UNKNOWN`; annotation count is not scene ground truth. Until `scene-metadata.csv` is human-completed, no honest LEFT/RIGHT/STRAIGHT or scene-count distribution exists.

## Proposed expansion target

Build a development set of **240 independently counted real production scenes**, each captured LEFT/STRAIGHT/RIGHT: 720 images. Add 80 OTHER/edge-case frames (blur, partial, extreme distance, alternate tray material) for 800 development images.

- Train: 168 scenes × 3 + 56 OTHER = 560 images
- Validation: 36 scenes × 3 + 12 OTHER = 120 images
- Internal test: 36 scenes × 3 + 12 OTHER = 120 images
- Final acceptance: separate 50 unseen scenes × 3 = 150 images
- Total target: 950 real images, before safe augmentation

For the 240 development scenes, collect at least 40 scenes in each ground-truth range: 1–10, 11–30, 31–60, 61–90, 91–120, and 120+. Keep every scene and all its views in one split.

External licensed images may add visual diversity, but they cannot replace real production scenes or independent tray counts.
