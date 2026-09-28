# Dataset checkpoint — 2026-09-28

The builder verified 947 local image paths, 527 unique byte contents, and zero
unreadable images. It scanned canonical/Roboflow datasets, archived source
photos, benchmark photos, the manual corrections and focused crops, MUTAA, and
the four relevant WhatsApp capture folders under Downloads. Two files from the
September22 folder were visually reviewed as unrelated voter UI/persona designs
and excluded; their hashes and reasons are saved in `out-of-scope.json`. Every inventory
entry records SHA-256, dHash, conservative scene/session group, annotation
status, split, parent lineage, view and ground-truth status.

`inventory.json` records every found path; `source-availability.json` also checks
the older Windows paths referenced by repository manifests. The old
C:/Users/dharani paths and frozen V2 export are not present here. Canonical
images found by content hash are inventoried without promoting their queued
annotations to reviewed labels.

## Leakage and label boundaries

Capture-day/session grouping is a conservative barrier rather than a claimed
physical arrangement. Filename dates plus exact content links and dHash Hamming
distance <=8 union candidate duplicates into one leakage group. The 138 near
duplicate edges leave two conservative inventory groups. This can overmerge
different arrangements; it is deliberately safer than splitting uncertain
views. `duplicate-lineage.json` preserves all candidate links. Derived faces
inherit the source group and source SHA-256. Views without explicit provenance
remain unknown. No random image split is used.

The original six reviewed faces fall in ONE leakage group: five focused faces
20/20/20/20/19, plus side19. Targets describe 118 assistant-reviewed visible
layers. The side photograph clips its top; its top endpoint is unsupported.
The wide and side photo association was never physically established, so these
are separate face examples under a conservative shared session, not a 118-tray
inventory total. Occupancy remains unknown. No physical count is certified.

A seventh face was manually reviewed in the enlarged center-stack crop of
`reports/individual-trays-20260915/image-06.jpg`: seven visible loaded-tray
layers, identified from the top tray and six side egg rows/seven supporting
rims. Its original quad is [[454,578],[560,586],[552,705],[447,693]], with literal
original center points x505/y591,607,625,640,655,671,688. The builder projects
these through the saved homography before deriving normalized Gaussian targets.
Those approximate labels are DEVELOPMENT visual references, occupancy unknown;
source blur is moderate and endpoints are not physically calibrated. This
September15 source remains in its own conservative group. Source approval is
limited to this face, not the other targets in the full photograph. The new
face is excluded from the V5 control snapshot. See `scene2-source-review.jpg`.

Three older reviewed crops (wh009/wh025/wh069: 47 labels) are excluded because
their original hashes were not recoverable among found files. No substitute
image was assigned those coordinates. All 72 V2 overview-policy candidates are
excluded because the saved audit explicitly requires full-resolution QA.
Queued canonical labels, generated stack preannotations and band outputs are
also excluded. Five crop approvals do not approve their full-frame parent.

## Frozen control subset and heatmap targets

`v5-clean-control/train/_annotations.coco.json` freezes six reviewed crops and
118 layer boxes; valid and test contain zero images. This is an INCOMPLETE
reviewed layer-presence subset, not an eligible filled-tray control release.
It cannot support RF-DETR control training/evaluation gates yet: independently
reviewed groups and occupancy-compatible labels are missing. The original
full-frame correction COCO has two approximate visible-reference frames/118
boxes, but those are not promoted as complete occupancy-certified control
frames. Existing originals and frozen benchmark files were not modified.

`faces.json` is the heatmap training contract. Each record has original quad,
homography, source hash, normalized centers, count, group, endpoint support and
label status. Centers come from saved reviewed box midpoints, never bands or RF
predictions. `targets/*.npy` stores 256-row Gaussian probability targets with
sigma=max(1/256,0.16*median layer spacing). `heatmap-qa.jpg` shows the layer
centers beside those target curves. No synthetic augmentation is written here;
any training-time derivative must retain this group and endpoint visibility.

The heatmap corpus now has seven faces/125 reviewed layer targets across TWO
groups: six TRAIN faces and one VALID development face. `development-splits.json`
records two leave-one-group-out development folds. Original+derivatives remain
together in each fold; the one-face group has moderate blur and only seven
layers, making this a small development probe rather than general accuracy
evidence. A smoke run on all faces only checks implementation/overfit behavior.
The frozen V5 control stays six TRAIN crops with empty VALID/TEST. Final
warehouse acceptance still requires new physical truth.

## Reproduce

From repository root, using Python with Pillow, NumPy and OpenCV (the builder
adds the existing `work/vision-deps` path):

```powershell
python model-improvement/stack-heatmap/build_dataset.py --check
python model-improvement/stack-heatmap/build_dataset.py --check-only
python model-improvement/stack-heatmap/build_dataset.py --reuse-inventory --check
```

The saved-content check verifies original source hashes, derivative group
inheritance, exact/near duplicate barriers, split boundaries, normalized centers
and exactly one generated peak per reviewed layer. `summary.json` records the
actual Python executable and the face-manifest hash for run provenance.
