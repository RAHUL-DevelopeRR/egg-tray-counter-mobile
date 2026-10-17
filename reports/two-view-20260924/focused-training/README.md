# Focused tray counting preparation

## Cloud checkpoint

Uploaded batch `Focused rectified faces 2026-09-24 TRAIN only` to existing
projec-mutta. All five added to TRAIN; dataset395, training283. Upload parser
recognized five annotated images. Cloud detail pages verify saved label counts
20/20/20/20/19. No new dataset version generated or training launched.

| Face | Roboflow image ID | Expected labels |
|---|---|---:|
| 1 | m25JPbPECWVnhkSjkFHI | 20 |
| 2 | TO9aGwkdUEtJlYZS5sDZ | 20 |
| 3 | BukAU2fSe16682vGzzuJ | 20 |
| 4 | JcNJARYTeyzohD2DdKFn | 20 |
| 5 | jXJrt4PgF1LwHy78dvQj | 19 |

The inherited required tag filter remains locked for editing on the current plan.
The wizard shows zero images dropped, but selected-record inclusion still needs
verification before training; no paid plan or bypass was attempted.

## Local evidence

Five perspective-corrected faces, 99 visible-layer annotations (20/20/20/20/19).
One COCO box per reviewed layer; top surface belongs to the uppermost tray.
Boxes describe the visible rectified layer extent, not egg-instance outlines or
hidden occupancy. Manual boundaries remain approximate where rims slope.
This supplements the larger curated training set; five crops of one photo are
not a sufficient independent dataset and must never be split across train/test.

The script prepare_focused_training.py produces the import ZIP, COCO file,
numbered review board and row-to-detection audit from saved model responses.
Green lines mean one model centre was assigned to that row; orange means zero
or multiple centres. This flags misses/duplicates for review, not measured
object-detection precision or recall. A box spanning rows can still have only
one centre. Stack 3's nominally correct 20 detections still has centre mismatches.

Reviewed original crops, coordinate-ruler images and the final numbered board.
An initial bounds assertion caught an incorrect fifth-face coordinate scale;
corrected to its actual 703-pixel height. Ruler review corrected second/third-face
boundaries. Assertions enforce image bounds, count totals and non-overlapping
contiguous layer intervals. Original annotations and frozen benchmarks preserved.

Validation audit: no trustworthy independent warehouse holdout is currently
certified. img05.jpeg is a different six-stack scene with 120 saved layer boxes
and a historical V2 result of 124, but dataset_reconciliation.csv identifies a
near-duplicate in the old Roboflow TRAIN data; do not use it to claim independent
post-training accuracy. img04.jpg has visual reference32 and historical V2=29,
but the same reconciliation report also finds a near-duplicate in the old TRAIN
data. Use either only for diagnostics, not independent validation. img01/02/03/06
show the current training arrangement and are excluded from independent testing.
The physical count of each benchmark was not confirmed by the user; stored
visual counts are references, not physical inventory ground truth.

Next training run must include these five faces in TRAIN alongside the reviewed
curated source images. The Roboflow wizard currently reports 283/76/36 splits
and a required tag filter, but does not expose enough evidence that its held-out
sets are scene-separated; do not generate/train this snapshot until the split is
audited. Existing model checkpoint, RF-DETR Medium and 640 fit-within form the
baseline configuration. Evaluate row errors as well as total errors; deploy only
after a new, physically counted scene is acquired and reserved before training.
