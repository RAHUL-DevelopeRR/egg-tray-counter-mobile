# Stack-face polygons: independent review (15 Oct 2026)

- **Input:** `annotations.draft.json` (SHA-256 `d65a0e92…44e32ca`). It was not changed.
- **Output:** `annotations.json` (schema `stack-faces-reviewed-1`). It has a per-image `review` block with the change log and two confidence ratings: geometry and membership.
- **Reviewer:** a second Claude Code agent that did not draw the draft. The user has not reviewed it.

## What was checked

All 20 photos were rendered with the polygons and the saved detection boxes (PIL), then checked at 2–3x zoom along every questioned edge. Measured checks:

- a pairwise rasterised overlap of polygons
- a green tray-rim profile on the outer edges
- the source SHA-256s
- the upright size against the size recorded in each detection file

The checks covered five things:

1. **One polygon per target stack face.** Stacks with two visible faces keep one polygon per face, linked by `physical_stack_inferred`: img-09 `f`, MUTAA `F1`.
2. **No polygon spans two stacks**, including stacks at two depths.
3. **Neighbours are tagged.**
4. **Coordinates are in the detection frame:**
   - Labelled batch view slots map to the right image ids through the batch `ids` field.
   - img-01 has the same detections in batch-01 `left` and batch-18 `right`.
   - In every overlay the boxes sit on the tray rows.
5. **The flags are right.**

No handwritten number, `labels.csv` value or user count was read, and no layers were counted.

**The annotation was not blind to the labels** (added 15 Oct after an adversarial verification). The sentence
above describes what the two agents used, not what they could see.

- **The numbers were visible.** The 11 labelled photos (img-01, 04, 06, 09, 32, 35, 39, 41, 43, 46, 47) were
  drawn and reviewed on the inked WhatsApp originals in `datasets/field-2026-10/labelled-20261007/originals/`.
  In those files the user's handwritten number is part of the frame. In img-06 the user's drawn bracket around
  the counted trays is visible too, and in img-46 the number is partly cut off at the top.
- **The target role is a reading of the label's scope.** Whether a stack is `target` or `neighbour` encodes the
  audit's reading of what each number covers (the per-image `label_scope`). That reading was partly reasoned
  from the values. For img-41 the audit noted "arithmetic of 81 does not fit the visible stacks". In img-47
  the target is "a single stack of 7 filled trays", and the empty stacks behind it are neighbours. In img-06
  the target is the region the user bracketed.
- **What is label-free.** Polygon geometry, depth rows and the visibility flags were drawn from pixels. Which
  stacks are targets, and so which boxes arm B sums, is partly label-informed.
- The other 9 photos carry no written number: the 9b4c783e and ef823816 scans (3 views each), 30aca6a1
  STRAIGHT, MUTAA image-07 and warehouse image-4. Checked by eye: img-47 shows a large hand-drawn "7" beside
  the stack, and warehouse image-4 shows no number.

## Corrections (16 polygon geometries in 13 images; 1 polygon added; 8 flag changes)

**Overlaps removed.** The draft polygons crossed into a neighbouring stack:

| Image | Polygons | Fix | Draft overlap |
|---|---|---|---|
| 9b4c STRAIGHT | `n1` | redrawn along `s4`'s right edge | 3007 px, 19% of `n1` |
| img-39 | `t_lower` | moved onto the seam with `n1` | 4788 px, 26% of `n1` |
| img-06 | `t_fl` / `t_fr` | new shared seam along the measured gap | 2057 px |
| img-09 | `rb` / `r1` | boundary set to the depth step at x ≈ 650→643 | 1610 px |
| ef823816 RIGHT | `r_setback`, `r_short` corner | moved onto `r2`'s measured left edge, (330,775)→(316,775) | 1345 px |
| img-47 | `n3` | right edge now follows `s1`'s left edge | 893 px |
| img-43 | `s1` | lower-right corner now follows `t1`'s eggs | 811 px |
| 30aca6a1 | `n_far` | left edge now follows `s4` | 731 px |

**Edges.** Each edge was compared with the tray rims:

| Image | Polygon | Edge | Error in the draft | Change |
|---|---|---|---|---|
| img-39 | `t_lower` | right | 5–35 px outside the tray | moved in to the rim |
| ef823816 LEFT | `l_setback` | left | took in 7–20 px of wall | moved in |
| img-01 | `s1` | upper left | 8–14 px inside the shadowed tray ends | moved out |
| img-47 | `n4` | left | missed about 18 px of the tray | moved out |
| img-47 | `s1` | top right | about 14 px inside the top tray's post | moved out |

**Flags:**

- img-04 `n1`: `base_visible` changed to true.
- img-35 `n1`: `depth_row` changed from 0 to 2 (background).
- img-41 back group: `depth_row` for `b1` changed from 1 to 2, and for `b2`/`b3` from 2 to 3. Their bases are about 200 px above the front pair's, so they stand several stack depths behind it, not one.
- img-47 neighbours re-ranked by their measured base lines (`n1`→1, `n2`→2, `n4`→3).

**Added:** img-35 `n2`, a defocused green tray stack (or crate) in the background. It was untagged, so it is marked `membership_uncertain`.

**Notes only:**

- img-09 `mb`: the narrow strip may be a gap rather than `mb`'s face, and the upper l/mb boundary may be off by about 20 px.
- img-43 `s1`: one polygon covers two faces.
- img-47 `s1`: its `sharpness_lapvar` is lower than blurred `n3`'s because of texture, not focus.

## Final set

- **20 images, 99 polygons:** 74 target and 25 neighbour.
- **After review, remaining overlaps are boundary-only:** at most about 2 px along shared edges.
- **Detection diagnostic** (centres inside target polygons, diagnostic only): every detection in 16 images. Exceptions: img-09 70/71, 30aca6a1 61/62, MUTAA 55/56, img-39 3/5. In 30aca6a1, MUTAA and img-39 the remaining centres fall inside neighbour polygons. The one img-09 centre, at (350,510), is inside no polygon: it sits on `f`'s top tray seen from above, and tops get no polygon.

## Still judgement calls (unchanged)

- **9b4c `s4`:** kept as target, with `membership_uncertain`. The reviewer agrees with the annotator's layout reading. The user has not confirmed which columns they count.
- **Other membership calls:** MUTAA `L`, img-04 `e` (depth row), img-43 `s1`, img-09 `n1`. Label scope for img-06, img-41 and img-43 is the audit's reading.
- **Cross-view `physical_stack_inferred` links.** Top-tray contents agree across views for every linked stack (for example 9b4c (0,0) has an empty cover in STRAIGHT and LEFT, and ef82 (4,0) is filled in all three views). These links were not verified pixel by pixel.
- **Top-down img-39.** The top and base flags describe the visible tray walls. Trays nested underneath cannot be seen.
- **Edge accuracy.** Measured edges agree within about ±10 px wherever trays contrast with the background. The exceptions are img-04's green wall, the dark trays (ef823816 STRAIGHT, MUTAA), and the defocused img-41 back group, where the accuracy is about ±10–15 px by eye.

Review scripts and overlays (draft `d0-*.jpg`, final `final-*.jpg`, `final-contact-sheet.jpg`) are in the session scratchpad under `review-polygons/`, not in the repo.
