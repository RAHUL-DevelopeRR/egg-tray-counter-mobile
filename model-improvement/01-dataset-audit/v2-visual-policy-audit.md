# Frozen V2 visual labeling-policy audit

Date: 2026-09-02

Gate result: **FAIL — manual relabeling is required before version generation or training.**

## Evidence

- Audited the exact 99-image V2 export (69 train / 22 valid / 8 test), not the 668-file raw pool.
- Export SHA-256: `20EB2D6795BC104A97C88A63EC32A67A0AA16595372055E52A96B1CA8E185EEC`.
- Opened all 99 annotated images in 11 review sheets.
- `v2-label-policy-review.csv` records every V2 member and its review status.
- 27/99 images visibly require manual relabeling.
- 72/99 are overview-policy-consistent candidates; they still require full-resolution QA while correction is performed.

The failed images mix several incompatible targets: one box around a whole vertical stack, one box around an unrelated wall/vent region, partial fragments, excessive overlapping boxes, and one tight box per physical tray/layer. The required target is one tight `egg_tray` box per individual visible physical tray/layer. A top-down image containing one physical tray can therefore correctly contain one whole-tray box; box size alone is only a triage signal.

Examples of confirmed failures include:

- `train/images/71135eb061c4bb2834b5_jpg.rf.b42d50b809427781e11aabcafe881960.jpg`: one large box on the wall/vent area while the green tray stacks are unlabelled.
- `valid/images/0ed3cb7f3aa5427610af_jpg.rf.ffe412dceea1720a8e55ac13f28be2f1.jpg`: background openings are boxed instead of individual trays.
- `test/images/WhatsApp-Image-2026-07-03-at-11-57-43-AM-1-_jpeg.rf.d840b7abac2e92acfb799fc58c88830d.jpg`: 121 dense overlapping boxes use a different unit from the rest of V2.
- `train/images/392dd4934876e29bf6cd_jpg.rf.542e12abbaac80100e33d02ab4d181e3.jpg`: vertical whole-stack faces are boxed rather than individual trays/layers.

Roboflow's prompted automatic-label attempt returned no usable objects on a confirmed bad dense image, so it was not used to overwrite labels. Fabricating boxes or accepting zero-object automation would fail the evidence gate.

## Decision

No corrected frozen version was generated, no RF-DETR Medium training was launched, and no benchmark was run because the input-label gate did not pass. The deployed Medium model and backend configuration remain unchanged. After the 27 failed images are manually corrected and all 99 receive full-resolution QA, rerun this audit, freeze auto-orient + fit-within-640 with no augmentation, train Medium, and evaluate the unchanged 10-file benchmark at confidence 35% / overlap 50%.
