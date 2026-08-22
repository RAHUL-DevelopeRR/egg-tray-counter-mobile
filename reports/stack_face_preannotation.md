# Stack-face heuristic pre-annotation

Generated: 2026-08-21  
Source: `datasets/canonical_clean`  
Output: `datasets/stack_face_review/tasks.json`  
Label: `stack_face` polygon  
Status: **review-only; human verification required**

## Result

| Measure | Value |
|---|---:|
| Canonical images processed | 137 |
| Train / valid / test tasks | 106 / 20 / 11 |
| Source `egg_tray` boxes | 3,683 |
| Suggested `stack_face` polygons | 264 |
| Tasks with no source box or suggestion | 38 |
| Tasks with one suggestion | 43 |
| Tasks with multiple suggestions | 56 |
| Median suggestions per image | 1 |
| Maximum suggestions in one image | 8 |
| Invalid source label rows skipped | 0 |

All 137 task IDs and image references are unique, every referenced canonical
image exists, and all 264 four-point polygons are within Label Studio's 0–100
percent coordinate range.

## Heuristic

`ml/preannotate_stack_faces.py` parses canonical YOLO boxes, connects pairs that
are horizontally aligned and vertically close, forms connected components, and
wraps each component in a padded rectangular polygon. Defaults are:

- minimum horizontal overlap: `0.45`
- alternative center-distance tolerance: `0.35 × larger box width`
- minimum normalized vertical-gap allowance: `0.04`
- adaptive gap allowance: `2.5 × median tray-box height`
- envelope padding: `0.01` of image dimensions

Suggestions use model version `heuristic-vertical-clustering-v1` and deliberately
low scores capped below 0.50. The source data and the existing
`datasets/review` queue are not modified.

## Required review

This geometry is a productivity aid, not ground truth. A reviewer must correct
boundaries, split merged physical stacks, merge fragments belonging to one stack,
add missed stacks, delete false suggestions, and inspect the 38 images with no
suggestion. Scene identity and LEFT/RIGHT/STRAIGHT correspondence remain absent.

Do not train or promote a production model directly from this generated queue.
Only human-approved `stack_face` polygons should enter a new segmentation dataset,
and exact-count product evaluation still requires scene-level physical counts.

## Validation performed

- Python bytecode compilation: passed
- Ruff check: passed
- Synthetic aligned/separate/empty clustering smoke tests: passed
- Generated JSON parse and schema assertions: passed
- Image-reference existence and uniqueness checks: passed
- Polygon count and coordinate-bound checks: passed
