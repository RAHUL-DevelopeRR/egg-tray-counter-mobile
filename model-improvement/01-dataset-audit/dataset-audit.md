# Dataset and model audit

Audit date: 2026-09-01

## Verified Roboflow state

| Item | Value |
|---|---|
| Workspace / project | `rahuls-workspace-l9ylz` / `projec-mutta` |
| Project type / class | object detection / `egg_tray` |
| Frozen version | `projec-mutta/2` |
| V2 split | 69 train / 22 valid / 8 test (99 images) |
| V2 preprocessing | auto-orient; fit within 640×640 |
| V2 augmentation | none |
| V2 source filter | one required tag; 99 images at generation time |
| Medium model | `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1` |
| Large model | `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-large-t2` |

The V2 YOLOv8 export was downloaded from Roboflow and audited read-only. Exact exported membership is recorded in `v2-image-manifest.csv`.

## Frozen V2 audit

| Check | Result |
|---|---:|
| Images / label files | 99 / 99 |
| Annotations | 3,681 |
| Mean / median annotations per image | 37.18 / 17 |
| Minimum / maximum annotations per image | 1 / 159 |
| Corrupt images | 0 |
| Missing / orphan labels | 0 / 0 |
| Exact duplicate image groups | 0 |
| Exact cross-split duplicate groups | 0 |
| Annotation pairs with IoU ≥ 0.85 | 0 |

V2 is therefore the 99-image frozen subset, not all 411 current project images. It is not proven to be a fully trustworthy reconciled subset: the current `clean` tag is attached too broadly and frozen-version membership alone does not verify annotation semantics.

## Critical labeling inconsistency

Stratified visual inspection disproved a consistent one-box-per-tray policy:

- Low-density sample `train/images/71135eb061c4bb2834b5...jpg` shows many dense tray stacks but has only one `egg_tray` box (`0 0.16484375 0.4703125 0.3296875 0.4390625`).
- Median sample `...11-57-21-AM...jpg` has 17 boxes on a visible single stack, consistent with per-layer counting.
- High-density sample `...11-57-38-AM...jpg` has 159 boxes on a dense warehouse wall, consistent with individual-tray labeling.

The same class therefore represents a large stack region in some images and individual visible tray layers in others. This mixed target explains why RF-DETR can alternate between catastrophic undercounting and overcounting. Geometric validity checks cannot detect this semantic error.

## Split leakage

- No byte-identical image crosses V2 splits.
- Existing benchmark metadata identifies `img02` (V2 test) and `img03` (V2 validation) as views of the same 60-tray physical scene. That is scene-level validation/test leakage even though the pixels and hashes differ.
- Scene IDs and capture-group IDs are absent for the remaining V2 images, so a complete negative claim about scene leakage is impossible.
- Timestamp adjacency produced 26 cross-split review candidates within two seconds, but spot checks showed timestamps alone are not proof of the same scene. They must be human-grouped, not automatically relabeled as leaks.

V2's eight-image test split is not an untouched, scene-independent final holdout.

## Other dataset inventories

| Dataset | Images | Annotations | Train / valid / test | Main issue |
|---|---:|---:|---:|---|
| Original manual export | 70 | 3,372 | 57 / 7 / 6 | mixed boxes/polygons; scene IDs absent |
| Roboflow V1 local export | 371 | 102,723 | 260 / 74 / 37 | 5,572 high-overlap pairs and tiny auto-label fragments |
| Canonical local set | 137 | 3,683 | 106 / 20 / 11 | scene/view metadata absent; 34 out-of-image boxes |
| Roboflow frozen V2 | 99 | 3,681 | 69 / 22 / 8 | mixed labeling unit; scene leakage not controlled |

The current project dashboard reports 411 images and 97,651 boxes (237.6/image), but frozen V2 averages only 37.18 annotations/image. The 411-image pool must not be used for a new version merely because it currently carries a `clean` tag.

## Required correction before retraining

1. Define `egg_tray` as exactly one tight box per visible/countable tray layer; never a whole stack.
2. Review all 99 V2 images, starting with annotation-count extremes and the benchmark failures.
3. Add verified `scene_id`, `capture_group_id`, `view`, and true total count.
4. Re-split by scene, keeping all LEFT/STRAIGHT/RIGHT views together.
5. Create a separate untouched final holdout; do not reuse the current 10-image benchmark as final test data.

Do not launch another paid training run until these corrections produce a frozen, scene-grouped version.
