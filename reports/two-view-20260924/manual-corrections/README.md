# Manual recount and retraining checkpoint — 2026-09-24

Assistant visually inspected each enlarged stack and prepared numbered layers.
Wide image reference: 20+20+20+20+19 = 99 visible egg-containing trays.
Side image reference: 19, including the cropped top tray. These are image-based
manual references, not physically verified inventory or a recovered 3D total.
The two counts must not be added: shared physical identity remains unresolved.

Fresh production request `77824bf2-c4d7-4c08-9714-7018f1c6d67f` returned HTTP 200,
model `projec-mutta/2`, 76 wide / 19 side / 87 auxiliary wide-view detections.
The third image was required by the existing API contract; slots were diagnostic,
not claims of calibrated viewpoints. Responses saved in fresh-backend.json.
Wide absolute count error is 23 (23.2323% of manual reference), side error zero.
Count agreement is not precision/recall; neither metric was measured here.

`prepare_manual_corrections.py` renders numbered overlays and 118 approximate
front-face bounding boxes in COCO. Local hash checks, annotation bounds, and
99/19 annotation totals pass. Boxes are assistant-reviewed correction proposals;
their boundary precision is not a pixel-level benchmark. Numbered images are
review artifacts only; originals, not numbered images, were uploaded.

## Actual Roboflow changes

Upload duplicate detection reported both originals already exist and their
annotations were applied to existing dataset records. Verified in the UI:

| Local input | Existing record | Labels | Split |
| --- | --- | ---: | --- |
| wide | ClMOF3wMZhPg4OJENlvT — WhatsApp Image 2026-07-03 at 11-57-18 AM (2).jpeg | 99 | TRAIN |
| side | KCJZzPDrafDfPRAWM3Vn — WhatsApp Image 2026-07-03 at 11-57-17 AM (2).jpeg | 19 | TRAIN |

Both tagged `manual-correction-20260924`. No duplicate copies created. Existing
frozen versions remain historical snapshots. These examples are not independent
test cases for a model trained on them. Broader scene-level leakage was not audited.

## Retraining blocker

Prepared draft name `V5 manual recount corrections 2026-09-24`, not generated.
Current dataset: 390 images (278 train / 76 valid / 36 test); latest frozen v4:
75 curated images (54 train / 16 valid / 5 test), tag-filtered, fit within 640.
Roboflow filter editor says advanced transformations require a paid plan.
NAS is also upgrade-only. No plan upgrade, purchase, new version, training job,
or deployment was performed. Do not remove the curated filter just to proceed:
reports/roboflow_dataset_audit.md records extensive overlap/duplicate annotations
in the historical broad dataset. The exact current v4 required tag was not
established in this session; do not assume adding the new review tag includes it.

Next: resolve paid Roboflow filter access or a user-provided GPU/Colab path;
assemble the curated cohort plus both corrected train records, verify inclusion
and preserved splits, then launch a bounded candidate training run. Compare it
against V2 on independent scenes and report count errors as well as detection
metrics before any production promotion. Production remains V2; APK 0.3.3+9.
