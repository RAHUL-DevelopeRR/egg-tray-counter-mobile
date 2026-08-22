# Egg Tray Dataset Audit

Source: `C:\Users\dharani\Downloads\egg pic\egg pic`

> The source was inspected read-only. No source media was moved, renamed, rewritten, or uploaded.

## Executive conclusion

- No supported box, polygon, COCO, or Pascal VOC annotations were detected. The source is raw capture media, not a trainable labeled dataset.
- No train/valid/test directory split or explicit scene/view triplet manifest was detected. Do not randomly split these sequential captures: first assign scene_id plus LEFT/RIGHT/STRAIGHT, then split by scene.
- The production target should be instance-segmentation polygons for `stack_face`, with scene-level metadata and integer tray-count ground truth.
- Duplicate content must be grouped before split creation to prevent leakage.

## Inventory

- Total files: 668
- Images: 662 (662 readable, 0 corrupt)
- Videos: 6
- Other files: 0
- Image bytes: 144,755,348
- Duplicate-content groups: 263 (303 redundant copies)

## Formats and splits

- Image extensions: `{".jpeg": 662}`
- Inferred splits: `{"unsplit": 662}`
- Annotation formats: `{}`
- Class distribution: `{}`

## Image dimensions

- Unique dimensions: 13
- Width min/median/p95/max: 580 / 1200.0 / 1600.0 / 1600
- Height min/median/p95/max: 580 / 1280.0 / 1600.0 / 1600
- Most common: `[["1200x1600", 260], ["1600x1200", 90], ["960x1280", 77], ["582x1280", 58], ["1280x582", 58], ["580x1280", 56], ["1280x960", 31], ["1280x580", 22], ["1599x899", 3], ["1599x1200", 2], ["720x1600", 2], ["1600x720", 2], ["1280x1109", 1]]`

## Required migration before Roboflow training

1. Deduplicate exact copies and keep a non-destructive manifest back to every original path.
2. Group each capture session into a stable `scene_id`; assign each image `view=left|right|straight`.
3. Record `physical_stack_id` and `tray_count_gt` for every stack in every scene.
4. Draw instance-segmentation polygons around visible counting faces using the single class `stack_face`.
5. Split train/valid/test by complete `scene_id`, never by individual image.
6. Keep difficult/failed photos with quality labels; they are needed to calibrate the rescan policy.
7. Evaluate exact stack count, MAE, exact scene count, coverage, accepted accuracy, and false-accept rate in addition to model mAP.

## Directory counts

- `WhatsApp Unknown 2026-07-03 at 12.08.24`: 99 images
- `WhatsApp Unknown 2026-07-03 at 12.08.40`: 86 images
- `WhatsApp Unknown 2026-07-03 at 12.08.46`: 81 images
- `WhatsApp Unknown 2026-07-03 at 12.09.02`: 18 images
- `WhatsApp Unknown 2026-07-03 at 12.09.12`: 3 images
- `WhatsApp Unknown 2026-07-03 at 12.24.54`: 19 images
- `egg pic data`: 356 images

## Duplicate-content examples

- `015c90fdb6fd` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.46/WhatsApp Image 2026-07-03 at 12.00.27.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.00.27 PM.jpeg`
- `03fc9a25e614` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.46/WhatsApp Image 2026-07-03 at 11.58.59 (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.59 AM (1).jpeg`
- `04ffe40c159c` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.46/WhatsApp Image 2026-07-03 at 11.59.01 (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.59.01 AM (1).jpeg`
- `05859d1fd4a9` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.24.54/WhatsApp Image 2026-07-03 at 12.03.39.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.03.39 PM.jpeg`
- `07b5c4eced27` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.24.54/WhatsApp Image 2026-07-03 at 12.02.31.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.02.31 PM.jpeg`
- `08e41a2135d1` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.46/WhatsApp Image 2026-07-03 at 12.01.04.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.01.04 PM.jpeg`
- `09e8555bb6ea` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.57.32.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.57.32 AM.jpeg`
- `0ae4583da591` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.09.02/WhatsApp Image 2026-07-03 at 12.01.16.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.01.16 PM.jpeg`
- `0bdb05b78227` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.34.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.34 AM.jpeg`
- `0da66d5ec36e` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.18 (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.18 AM (1).jpeg`
- `0f9df9a3ce07` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.30 (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.30 AM (1).jpeg`
- `12be1ee147e8` (3 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.59.00.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.59.00 AM (3).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.00.36 PM.jpeg`
- `14dbc45a33c3` (4 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.57.00.jpeg`, `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.11 (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.57.00 AM.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.11 AM (1).jpeg`
- `16685e90ac8c` (4 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.57.01 (1).jpeg`, `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.11 (3).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.57.01 AM (1).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.11 AM (3).jpeg`
- `18022aba0e62` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.46/WhatsApp Image 2026-07-03 at 12.01.07.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 12.01.07 PM.jpeg`
- `181bfbf19aa9` (4 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.56.57.jpeg`, `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.13 (2).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.56.57 AM.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.13 AM (2).jpeg`
- `184b8cb03bfe` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.57.46.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.57.46 AM.jpeg`
- `185176b841d0` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.23 (2).jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.23 AM (2).jpeg`
- `18b1cbf3c220` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.24/WhatsApp Image 2026-07-03 at 11.57.19.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.57.19 AM.jpeg`
- `18d412ffab23` (2 copies): `WhatsApp Unknown 2026-07-03 at 12.08.40/WhatsApp Image 2026-07-03 at 11.58.19.jpeg`, `egg pic data/WhatsApp Image 2026-07-03 at 11.58.19 AM.jpeg`

## Corrupt image details

No corrupt images detected.

Machine-readable details are in `ml/audit-report.json`.
