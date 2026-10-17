# Stack-face experiment: localization, layer counting or cross-view association? (15 October 2026)

Experiment session, 2026-10-15 (Claude Code subagent). All three arms run offline on saved detections. No new
inference, no paid call, no deployment, no phone access, no R2 read, no commit. New files only:
`backend/app/vision/stack_separation.py`, `backend/tests/test_stack_separation.py`,
`scripts/experiment_stack_faces.py`, `scripts/tests/test_experiment_stack_faces.py`, this README and
`results.json`. `annotations.json`, `annotations.draft.json`, `REVIEW.md`, the eval reports, the frozen
benchmarks and the datasets were read only in that session. The revision below added a note to `REVIEW.md`.

**M** = measured here. **I** = inference. **D** = taken from a repo document or an earlier report.

**Revised the same day after an adversarial verification.** These changes were made:
- the bottleneck claim is narrowed and the root cause is downgraded to an inference;
- a label-free walk-versus-span decomposition is added;
- physical n, a leak column and the G01 triple-count are stated;
- C's gains are marked as development results;
- `--out` is added to the script;
- `scripts/tests/test_label_perturbation.py` is added;
- `REVIEW.md` gains a note on how blind the annotation was;
- ruff findings in `stack_separation.py` and its test are fixed, with no change to their behaviour.

`results.json` was regenerated. It gains `walk_vs_span_B`, `physical_n` and a leak and block field per scored
photo. Every earlier number is unchanged (M).

**Revised again the same day after a second verification.** Text only; `results.json` and the code are
unchanged. These changes were made:
- the In brief and section 9 are reconciled with the walk-fill experiment
  (`reports/experiment-walk-fill-20261015/`): its V4 numbers are cited, and section 9 now states the verified
  bottleneck and a plan instead of deferring to that report;
- the hold-out in section 9 is listed by physical block with every member from the dataset audit, not by
  photo id.

## In brief

- **Bottleneck, revised: among the two measurable arms, on single faces, layer counting is the larger.**
  Localization comes second: it is frequent per stack but changes face totals very little. Cross-view
  association cannot be measured, because there is no counted genuine trio.
- **The root cause is not established.** The earlier claim was that the detector misses tray rows. That is an
  inference (I). A label-free check shows the walk counter's own gap filling is a measurable contributor:
  - In 12 of 62 polygons the walk exceeds the span by more than 1. These 12 hold 74 of the 92 layers the walk
    filled.
  - 10 of the 12 have regular boxes (box height / pitch ≥ 0.75) and hold 60 of those fills (M).
  - In 4 other polygons the span exceeds the walk by more than 1: the walk dropped boxes as duplicates (M).

  This experiment did not separate missing detector rows from the walk's fill and duplicate rules. The
  walk-fill experiment (`reports/experiment-walk-fill-20261015/`) has since separated part of it (M, its
  README): the deployed walk's pitch ratchet is a label-free defect, and the observed-pitch walk V4 removes it
  without changing any of the 19 accepted totals. Section 9 gives the reconciled bottleneck.
- **With perfect localization the errors stay.** Counting inside the reviewed polygons (arm B) leaves 16 of
  the 18 absolute-error trays of the deployed logic (arm A). This is on the 9 polygon photos with a usable label,
  which show 7 physical blocks: img-01, img-32 and warehouse image-4 are all block G01 (M).
  - 14 of the 16 come from two tier-B photos with unconfirmed scope: img-09 +10 and img-04 +4.
  - Over all 20 polygon photos, A's face totals differ from B's by 11 trays in total out of 917 (M).
- **Layer counts are inconsistent where the trays are small in the frame.** This is measured on 3 blocks per
  scale bucket.
  - In the 5 photos where one layer spans 2.0-2.7% of the frame height, target stacks of the same extent read
    different walk counts. Under the deployed walk (V0) they differ by more than 1 layer in 15 of 18 pairs, and
    by up to 12 layers. Under the walk-fill experiment's observed-pitch walk (V4), 11 of 18 pairs still differ
    by more than 1, by up to 8 layers (M, walk-fill README section 3.1).
  - 12 of those 18 pairs come from the one ef823816 block, whose LEFT and RIGHT photos show the same face.
    There are 15 physically distinct pairs.
  - In the 4 photos where a layer spans at least 3.4%, 0 of 11 such pairs differ by more than 1 (M).
  - Scale is confounded with block.
  - 83 of the 92 layers the walk had to fill are in 5 photos: four of these small-scale photos and the close
    oblique img-09 (M).
- **Detector recall per layer** (user-reported counts, not physical): 45 of 45 layers on three close
  single-stack observations. Two of these are the same stack (img-32 and warehouse image-4), and both photos
  were part of the walk-counter development. img-46 is not in the 45: it has 16 boxed layers against 20, and its
  base is cut by the frame. The far user-100 face gives 72 of 100. Its five stacks were localized correctly but
  read 16/26/24/15/14 against 20 each (M).
- **Cross-view association** was right for 9 of the 9 counted columns of the one plausible genuine set
  (9b4c783e), in all three arms. The 6 wrong assignments measured elsewhere come from:
  - a duplicated or substituted photo: 5 of 6;
  - the pitch-based set-back test misfiring on a far face whose boxes skip layers: 1 of 6 (M).
- **Arm C** is the new `stack_separation.py`. It raises correctly localized target stacks from 48 to 58 of
  71 (M).
  - On the 22 labelled clusters it is exact (ungated) on 12 against A's 9. The 3 gains (img-35, img-39 and
    img-49, labels 1, 2 and 1) are development results, not evidence. C's designer had seen these labels and
    A's errors on them before writing the short-stack and sliver rules that produce the gains.
  - Its total absolute error is 435 against 431. The worse result comes from one unverifiable split in img-38
    (M).
- **Bottleneck and plan, reconciled with the walk-fill experiment (second revision; section 9):**
  - The binding constraint is held-out physical truth. No count here is physical, and 9 of the 10 accepted
    eval clusters are in-sample (eval README, section 5).
  - On single faces, the walk's pitch ratchet is a real, label-free defect. V4 fixes the consistency (summed
    equal-extent difference 97 → 47) and moves 0 of the 19 accepted results.
  - The remaining error is far-face undercounting where a layer is under 3% of the frame height (3 blocks).
    It points at detector recall at small scale or at capturing closer; these data cannot separate the two.
  - Cross-view matching cannot be ranked: there is 1 plausible genuine set and no counted one.
  - Plan: physical per-stack counts on 3 or more new blocks, as STRAIGHT/LEFT/RIGHT sets with a distance
    ladder; then retraining on far and cross-stacked field faces, held out by block. Meanwhile V4 and C run in
    shadow mode.
  - Cheap alongside: a duplicate-face check for trios (section 9, item 2).

## 1. Inputs and method

**Photos and polygons.** `annotations.json` (schema `stack-faces-reviewed-1`) has 20 photos and 99 polygons:
74 target and 25 neighbour. They were drawn by one Claude Code agent and reviewed by a second; the user has
not reviewed them (D: `REVIEW.md`).
- **Not blind.** The 11 labelled photos were drawn on the inked WhatsApp originals, where the user's handwritten
  number (and for img-06 the drawn bracket) is part of the frame.
- **Target role.** Which stacks are `target` encodes the audit's reading of each label's scope, and that
  reading was partly reasoned from the value. For img-41 the audit noted "arithmetic of 81 does not fit the
  visible stacks" (see `REVIEW.md`).

**Physical n (M, `results.json` → `physical_n`):**
- The 20 photos show 13 physical blocks. G44 has 4 photos: 9b4c783e S/L/R, plus 30aca6a1 S, which shows the
  same STRAIGHT face from further back. G43 is ef823816 S/L/R, and its LEFT and RIGHT show the same face. G01
  is img-01, img-32 and warehouse image-4; img-32 and warehouse image-4 show the same end stack.
- The 74 target polygons are 55 physical-stack keys: `physical_stack_inferred`, with a polygon that has no
  link counted as its own key. The 62 polygons with 3+ boxes are 46 keys.
- Every polygon-level count below is therefore over correlated observations.

| Photo set | Photos | Count usable as a target here |
|---|---|---|
| Labelled WhatsApp photos | 9 with usable labels: img-01 (99, A), img-32 (19, A), img-04 (115, B), img-09 (75, B, low confidence), img-35 (1, A), img-39 (2, A), img-47 (7, A), img-46 (20, B) and warehouse image-4 (19, user-confirmed per stack) | yes. The value is the user's written number and the scope is the audit's reading; neither is a physical recount |
| Labelled, audit says not usable | img-06 (4), img-41 (81), img-43 (5) | shown only in a secondary table |
| 13 Oct field scans | 9b4c783e S/L/R, ef823816 S/L/R, 30aca6a1 S | no count. These are used for localization and cross-view consistency only |
| MUTAA archive | image-07 | no count |

**Detections.** The saved `projec-mutta/2` boxes in each photo's `detections_path` are used:
- 897 boxes: 892 have their centre in a target polygon, 4 in a neighbour polygon and 1 in no polygon;
  0 are in two polygons (M);
- warehouse image-4's analysis file has the same 19 boxes as the 9 Oct staging response the eval harness
  uses (M);
- img-01 appears twice (batch-01 LEFT and batch-18 RIGHT, identical boxes); the batch-01 copy is used, as in
  `scripts/evaluate_labelled.py`.

**Arms.** All are deterministic. Two runs gave a byte-identical `results.json`: SHA-256 `ae60c77c…790886`
originally, and `6b86fa5d…26f9dd` after the revision. The revision added keys and changed no earlier value.

- **A, deployed.** `evaluate_labelled.predict_face`:
  - `layer_span.count_layers_by_span` (x-columns of 3+ boxes, walk counter);
  - the block model's column reasons and the capture gate;
  - total = the sum of walk counts over all of the photo's columns.

  Column membership comes from `layer_span._columns`. For every column, the script asserts that
  `stack_separation.column_record(members)` reproduces `count_layers_by_span`'s record field for field.
- **B, polygons.** Each box goes to the polygon containing its centre, and each polygon gets one walk.
  - Only target polygons are summed, with one count per physical stack. In img-09 and MUTAA the two
    polygons of one stack's two faces count once: the face with more boxes is used.
  - Stacks with 1-2 boxes count as their box count and are flagged. The walk count of those boxes is
    reported alongside as "B (short = walk)".
  - Set-back stacks whose base is hidden count their visible layers only.
- **C, automatic separation** (`backend/app/vision/stack_separation.py`). It applies A's x-grouping with
  four rules taken from the polygon failure modes:
  1. Boxes with width/height < 0.5 are dropped as frame-edge slivers. Only 3 boxes in the 20 photos are
     below 0.5 (0.09-0.13); the next lowest is 1.19.
  2. A column is split at its widest vertical gap of at least 1.4 pitches where the boxes above are at most
     0.85 x as wide as those below. The upper part is a set-back stack with a hidden base.
  3. Groups of 1-2 boxes are kept as short stacks counted by their walk, unless their boxes are under 0.65 x
     the front stacks' width (background).
  4. A depth label: front, `set_back` (box width < 0.85 x the front width) or `set_back_partial`.

  **How C was tuned (honest account):**
  - Thresholds came from polygon geometry only. Every vertically adjacent box pair inside A's columns was
    labelled by whether it crossed a polygon boundary. The five true front/rear crossings with a gap had
    gaps of 1.54-4.3 pitches and width ratios of 0.63-0.81. After splitting at the widest such gap, no pair
    inside one polygon met both thresholds.
  - **Re-measured after verification (M).** Six vertically adjacent pairs inside A's columns meet both split
    thresholds:
    - the 5 true crossings: gap 1.54-4.3 pitches, width ratio 0.627-0.809;
    - one pair inside a single polygon: ef823816 LEFT `l_setback`, gap 2.13 pitches, ratio 0.791. Its lower
      3-box window reaches into the wider `l_short` boxes below.

    That column is split once, at its widest qualifying gap: 2.8 pitches, the true `l_setback`/`l_short`
    boundary. When the upper part is examined again, the same pair has a width ratio of 1.045 and is not split.
    So `l_setback` stays whole only because of the widest-gap rule. The margin rests on 5 positive examples
    from 3 blocks (img-09; ef823816 S, R and L; MUTAA). Two of them, ef823816 R and L, are the same physical
    crossing seen in the duplicated face.
  - No label value was used to set or change a threshold.
  - However, the designer had read the evaluation summary and the label values for these photos before
    designing C. C was frozen before it was scored against labels and not changed afterwards.
  - The short-stack and sliver rules target failure modes seen on img-35, img-39 and img-49, after their labels
    (1, 2, 1) and A's errors on them had been seen. C's +3 exact clusters on those three photos (section 7) are
    therefore development results, not evidence that the rules generalise.
  - The 20 photos are C's development set. A's thresholds were also tuned on many of the labelled photos
    (D: eval README).

**Localization status** (A columns or C stacks against the target polygons, by box-centre membership):
- `correct`: all of the polygon's boxes are in one found stack that holds no other polygon's boxes;
- `merged_with_target`, `merged_with_neighbour` or `merged_with_unassigned`;
- `split`: the polygon's boxes are spread over 2 or more found stacks;
- `missed`: none of its boxes is in any found stack;
- `no_boxes`: the detector placed no box in the polygon.

**Labels are scoring targets only.** They are read in `score_*` after every prediction. A test checks that
no prediction function takes a label parameter. That check goes by parameter name only.
`scripts/tests/test_label_perturbation.py` adds the real check. It changes every label value (manifest,
not-usable list, `labels.csv`) and every per-stack truth value, then reruns the experiment. All predictions
stay byte-identical, including localization, layer statistics, association and A vs C, while the scores
change (M). This covers the code only: the design-level influences are in section 1 and `REVIEW.md`.

## 2. Totals against labels: 9 polygon photos (M)

| Photo | Block | Leak (detector) | Label (tier) | A (deployed outcome) | B | B (short = walk) | C | A − label | B − label | C − label |
|---|---|---|---|---|---|---|---|---|---|---|
| img-01 | **G01** | leaked | 99 (A) | 99 (accepted) | 99 | 99 | 99 | 0 | 0 | 0 |
| img-32 | **G01** (end stack) | leaked; walk development | 19 (A) | 19 (accepted) | 19 | 19 | 19 | 0 | 0 | 0 |
| warehouse image-4 | **G01** (same end stack) | leaked; walk development | 19 (per stack) | 19 (accepted) | 19 | 19 | 19 | 0 | 0 | 0 |
| img-04 | G05 | leaked | 115 (B) | 120 (withheld, gate) | 119 | 119 | 120 | +5 | +4 | +5 |
| img-09 | G08 | leaked | 75 (B, low) | 85 (withheld, flag) | 85 | 85 | 85 | +10 | +10 | +10 |
| img-35 | G22 | leaked | 1 (A) | 0 (withheld, gate) | 1 | 1 | 1 | −1 | 0 | 0 |
| img-39 | G24 | leaked | 2 (A) | 3 (withheld, gate) | 3 | 2 | 2 | +1 | +1 | 0 |
| img-47 | G30 | **leak-free** | 7 (A) | 7 (accepted) | 7 | 7 | 7 | 0 | 0 | 0 |
| img-46 | G29 | **leak-free** | 20 (B) | 19 (withheld, flag) | 19 | 19 | 19 | −1 | −1 | −1 |
| **exact / sum of absolute error** | | | | **4 / 18** | **5 / 16** | **6 / 15** | **6 / 16** | | | |

- **Physical n.** The 9 rows are 7 blocks. G01 is counted three times: img-01 shows the whole 5-stack face, and
  img-32 and warehouse image-4 both show its free-end stack. That stack is also one of img-01's five columns.
  img-32 and warehouse image-4 were walk-counter development photos (eval README, section 5). 7 of the 9 photos
  have a training copy; warehouse image-4 is byte-identical to
  `datasets/canonical_clean/train/images/fb5bd22bfe8d1b3da171.jpeg` (M). Only img-47 and img-46 are
  leak-free.

- **What perfect localization removes.** It removes 2 of the 18 error trays: img-35's dropped single tray and
  one layer in img-04 (M).
- **What remains.** The other 16 remain with the polygons: img-09 +10, img-04 +4, img-46 −1 and img-39 +1.
  14 of the 16 are in the two tier-B photos. The img-39 error exists only under the box-count rule.
  - img-04 and img-09 are tier B labels with unconfirmed scope: two depths in img-04; for img-09, whether the
    empty top tray counts (D: eval manifest).
  - img-46's base is cut off by the frame, according to its polygon flag (D).
- **A's +1 on img-39 is wrong for the wrong reason.** It comes from a "column" of three edge slivers, two of
  them in a neighbour polygon (M).
- **Secondary photos, not usable at image level per the audit.** These are labels.csv values, never in a
  headline number:

| Photo | labels.csv value | A | B | C |
|---|---|---|---|---|
| img-06 | 4 | 0 | 4 | 4 |
| img-41 | 81 | 48 | 48 | 48 |
| img-43 | 5 | 5 | 6 | 6 |

## 3. Localization: 20 photos, 74 target polygons (M)

These are 13 physical blocks and 55 physical-stack keys. Several stacks are counted once per photo, so the 71
and 48/58 below are polygon counts, not independent stacks.

| | A (deployed) | C (stack_separation) |
|---|---|---|
| Target polygons with ≥ 1 box | 71 (3 have no box: img-09 `f_left` and MUTAA `F1_side` are the second face of a stack; img-41 `b1` is a back stack with no detection) | 71 |
| Found stacks | 58 | 67 |
| `correct` | **48** | **58** |
| `merged_with_target` | 12 (img-04: 4, the rear and front stacks at the same x with no gap; img-09: 2; ef823816 S/R/L: 6, short corner stack + set-back stack) | 11 (img-04: 4, unchanged; img-06: 4 and img-39: 2, loose trays side by side; img-09 `r1`: 1) |
| `merged_with_neighbour` | 2 (MUTAA `F2` + a background box; img-39 `t_upper` + 2 slivers) | 0 |
| `merged_with_unassigned` | 1 (img-09 `mb`) | 1 (same) |
| `split` | 1 (img-09 `rb`) | 1 (same) |
| `missed` | 7 (img-06: 4 loose trays, img-35, img-39 `t_lower`, img-43 `t1`: all 1-box groups) | 0 |
| Found stacks holding neighbour boxes | 2 | 1 (MUTAA `BL4`, kept as a one-box set-back stack) |
| Photos with every target correct | 10 of 20 | 16 of 20 |

- **Effect on face totals.** A's total differs from B's in 6 of 20 photos, by 11 trays in total out of 917.
  C differs from B in 3 photos, by 3 trays (M).
- **Merges are mostly count-neutral.** Of A's 10 mixed stacks, 6 count the same as their parts walked
  separately, and the total absolute effect is 6 trays (M).
- **Merges matter per cell.** In ef823816 RIGHT, A reads the short corner stack and the set-back stack above
  it as one column of 20 (14 + 6 when separated). The block model then puts 20 in the corner cell. LEFT
  reads 16 instead of 9 (M).
- **C's depth label** agreed with the polygon's depth row (front vs behind) for 57 of 66 found target stacks
  (M):
  - 7 set-back stacks were called front: img-04 `a`, `b`, `e`, `f`; img-09 `l`, `mb`; MUTAA `L`;
  - 2 front stacks on img-09's receding oblique face were called set-back.
- **Not fixed by C:**
  - x-overlapping stacks at two depths with no vertical gap (img-04);
  - boxes spanning two stacks at a close oblique view (img-09);
  - one neighbour box at the scale of the target (MUTAA `BL4`).

## 4. Layer counting inside the polygons (arm B, M)

Target polygons: 62 with 3+ boxes, 9 with 1-2 boxes and 3 with none. Over the 62 polygons:

| Measure | Value |
|---|---|
| Boxes / walk layers | 882 boxes → 907 layers: 67 boxes skipped as duplicates and 92 layers filled |
| Polygons needing filled layers | 25 of 62 |
| Polygons with box height / pitch < 0.75 (boxes on only some rows) | 10 of 62, in 4 photos: ef823816 STRAIGHT 4 of 5, MUTAA 3 of 5, img-41 back group 2, img-04 `d_rear` 1 |
| Polygons whose span and walk counts differ by > 1 | 16 of 62 (12 with walk > span + 1, 4 with span > walk + 1) |
| Polygons with unresolved gaps (> 2 missing layers in a row) | 0 |
| Polygons the block model would send for a retake | 25 of 62 |

**Walk versus span, added after verification** (M, label-free; `results.json` → `walk_vs_span_B`).
- The walk follows a local pitch, merges boxes closer than 0.65 local pitch as duplicates and fills multi-pitch
  gaps, at most 2 layers per gap (D: PROGRESS 2026-10-09 and 2026-10-14).
- The span divides the first-to-last extent by the median pitch.

| Polygons (3+ boxes) | n | Filled layers | Boxes skipped as duplicates |
|---|---:|---:|---:|
| all | 62 | 92 | 67 |
| walk > span + 1 | 12 | **74** | 9 |
| … of which box height / pitch ≥ 0.75 (regular boxes) | 10 | **60** | 7 |
| span > walk + 1 | 4 | 2 | 12 |
| span and walk within 1 | 46 | 16 | 46 |

- The 12 polygons where the walk exceeds the span by more than 1 are in img-09 (4), img-04 (2), ef823816
  STRAIGHT (2), ef823816 LEFT (2), MUTAA (1) and img-46 (1).
- Example: img-04 `f` has 17 boxes, span 19, walk 27 and 11 filled layers, with box/pitch 0.94.
- In img-04 the equal-extent stacks `a`, `b`, `e` and `f` span 17/18/18/19 but walk 19/15/19/27. In
  ef823816 LEFT, `l2`, `l3` and `l4` span 14/16/18 but walk 22/27/15.
- In the 4 polygons where the span exceeds the walk, the walk dropped boxes as duplicates: img-04 `b`,
  ef823816 LEFT `l_short` and `l4`, and MUTAA `F4`.
- So most filled layers sit where the walk and the span disagree, mostly on faces whose boxes are regular
  in size.
- Walk > span + 1 is a disagreement, not proof that the walk over-counts. On img-46 the walk (19) is closer to
  the user's 20 than the span (17) is (base cut by the frame).
- This experiment does not separate missing detector rows from the walk's fill and duplicate rules. The
  walk-fill experiment produced in parallel (`reports/experiment-walk-fill-20261015/`) addresses that.

**Where the filled layers are.**
- 83 of 92 are in 5 photos: img-04 22, ef823816 LEFT 21, img-09 18, ef823816 STRAIGHT 14 and MUTAA image-07 8.
  Four of them are small-scale photos (layer pitch 2.0-2.7% of the image height); img-09 is a close oblique
  multi-depth view. ef823816 RIGHT, also at 2.5%, filled only 3.
- The other 12 photos fill 9 in total: 9b4c783e S/L/R, 30aca6a1, img-01, img-32, warehouse-4, img-41,
  img-43, img-46, img-47 and ef823816 RIGHT.

**Equal-extent consistency** (labels not needed). The test pairs target stacks in one photo that have:
- the same depth row and face;
- the top and base in frame;
- first and last boxes within 0.6 pitch of each other.

Such stacks should read the same number of layers if the trays are the same type (I).

| Photos | Blocks | Pairs (physically distinct) | Walk differs by > 1 | Span differs by > 1 |
|---|---|---|---|---|
| Layer pitch ≥ 3.4% of the frame height (9b4c783e STRAIGHT 5.3%, img-41 3.7%, img-01 3.5%, 30aca6a1 3.4%) | 3 (G44: 4 pairs, G01: 5, G18: 2) | 11 (10) | 0 | 0 |
| Layer pitch 2.0-2.7% of the frame height (ef823816 STRAIGHT 2.7%, RIGHT 2.5%, LEFT 2.0%, MUTAA image-07 2.4%, img-04 2.0%) | 3 (G43: 12 pairs, G36: 4, G05: 2) | 18 (15) | 15 (up to 12 layers apart) | 6 (up to 4) |

- **Physical n (M, `physical_n.equal_extent_buckets`).** Each bucket has 3 blocks, so scale is confounded with
  block.
- 12 of the 18 small-scale pairs come from the one ef823816 block (G43). Its LEFT and RIGHT photos show the same
  face, so their 3 + 3 pairs are the same 3 physical pairs read twice.
- In the large-scale bucket, the 30aca6a1 pair repeats a 9b4c783e STRAIGHT pair.

Examples:

| Photo | Stacks of equal extent | Walk counts | Span counts |
|---|---|---|---|
| img-04 | `a`, `b`, `e`, `f` | 19 / 15 / 19 / 27 | 17 / 18 / 18 / 19 |
| ef823816 STRAIGHT | `s1`-`s4` | 10 / 19 / 18 / 10 | 11 / 14 / 11 / 11 |
| MUTAA | `F1`-`F4` | 10 / 12 / 17 / 9 | 10 / 11 / 10 / 11 |

The span is steadier but halves when boxes sit on alternate rows. For ef823816 STRAIGHT it gives 11 where
the 13 Oct visual reading was 20 per stack (D, not a physical count). So neither counter recovers missing
boxes.

**Per-stack recall against user-reported values** (columns chosen by geometry; "boxed layers" = walk −
filled, which assumes the walk placed the boxes on the right layers):

| Stack | Boxes | Walk | Boxed layers / user value | Note |
|---|---|---|---|---|
| img-32 (99-block free end) | 24 | 19 | 19 / 19 | close |
| warehouse image-4 (same stack) | 19 | 19 | 19 / 19 | close; the top is clipped in this photo, yet the walk equals the user's 19 |
| img-47 | 7 | 7 | 7 / 7 | close |
| img-46 | 18 | 19 | 16 / 20 | the base is cut by the frame (polygon flag), so the 4 missing layers may be out of the photo |
| user-100 face in img-44, 5 stacks | 15 / 16 / 15 / 15 / 14 | 16 / 26 / 24 / 15 / 14 | 14 / 16 / 15 / 14 / 13 of 20 each | far; box/pitch 0.85-0.90. Localization was right (5 columns for 5 stacks) and the walk was off by −6 to +6 |

The close single stacks give 45 of 45 layers boxed, against 72 of 100 on the far user-100 face. These are 9
observations of 8 physical stacks, all user-reported.
- The 45 come from 3 observations of 2 stacks. img-32 and warehouse image-4 are the same stack, and both were
  walk-counter development photos.
- img-46 is left out of the 45: it has 16 boxed layers against 20, with the base cut by the frame.

## 5. Detector recall question

- **Filled layers.** Within B's target polygons the walk filled 92 layers out of 907 (10.1%), across 25 of 62
  polygons. 83 of the 92 fall in 5 far or oblique photos.
- **Alternate-row boxes.** Box height / pitch < 0.75, the sign of boxes on only some rows, appears in 10 of
  62 polygons (16%) in 4 photos. It covers 4 of the 5 stacks of the far ef823816 STRAIGHT face, whose
  cross-stacked rows are boxed only on the 5-egg rows (D: 13 Oct visual reading).
- **Where counting goes wrong.** Layer counting goes wrong mostly in the photos where these occur.
  Equal-extent stacks disagree in 15 of 18 pairs under the deployed walk (3 blocks; 12 pairs from ef823816),
  and in 11 of 18 under the walk-fill experiment's V4 (M, its README). Cross-view readings of
  one stack disagree by up to 8 layers (section 6). The user-100 stacks miss 4-7 boxed layers each.
- **Where counts are consistent.** In the large-scale photos the detector boxes every row and the walk fills
  almost nothing, and there the counts agree across stacks and across views. img-04 is the counter-example:
  its boxes are regular (box/pitch 0.94-1.01 for `a`, `b`, `e`, `f`), yet those stacks walk 19/15/19/27 against
  spans of 17/18/18/19.
- **Missing rows are not the only cause (M, revised).** Box height / pitch < 0.75 marks only 10 polygons. Of
  the 12 polygons where the walk exceeds the span by more than 1 (74 of the 92 fills), 10 have regular boxes
  (60 fills). There the walk reads more than one layer above the span, and its fills carry the difference
  (section 4). The walk and span counters disagree in 16 of 62 polygons.
- **Recall at the deployed working distance.** For close square-on photos the current model already boxes
  every layer of the three close single-stack observations (45/45, user-reported; 2 physical stacks) and 98 of
  99 layers of img-01 (walk 99, 1 filled). The deployed gate withholds the far and oblique faces.
- **Inferred conclusion, revised.** Detector retraining is a plausible lever for faces with missing rows
  (box/pitch < 0.75; the user-100 face). This experiment does not show that it is the first lever:
  - the walk's fill and duplicate rules were not tested separately here (the walk-fill experiment has since
    tested them; section 9, item 0);
  - 14 of the 16 residual error trays are in two scope-uncertain tier-B photos;
  - the per-stack truth is 9 user-reported observations of 8 stacks.

  It also does not move the accepted photos, which are 9/10 exact already (I).

## 6. Cross-view association (qualitative; there is no counted genuine trio)

The block model associates views by order: STRAIGHT column k is cell (k,0), the side faces are the outer
columns, and set-back columns are promoted. The script maps every view column to the cell the block model
uses and compares it with the polygon's `physical_stack_inferred` link (M).

| Set (audit verdict) | Block status / total (A = B = C) | Correct / wrong / not counted | The wrong ones |
|---|---|---|---|
| 9b4c783e S/L/R (plausible genuine, no count) | estimated / 165 in all three arms | 9 / 0 / 1 | none. RIGHT `r1` is the set-back side of (2,0), correctly not counted. Corner (0,0) reads 15 in STRAIGHT and 16 in LEFT: a one-layer ambiguity, which PROGRESS (14 Oct) attributes to an empty cover tray (D) |
| ef823816 S/L/R (not genuine: LEFT = the right face again) | conflict / none in all three arms | 8 / 5 / 0 | 4 LEFT columns placed on the left face (x = 0) but showing (4, y): a capture duplicate. 1 STRAIGHT `s2` (front, (1,0)) read as set back and promoted to (1,1): its pitch is 0.78 x the face reference, because its neighbours' boxes sit on only some rows (box/pitch 0.64-0.67) |
| 99-block trio (substituted: LEFT and RIGHT are the same free end) | estimated / 99 in all three arms | 6 / 1 / 0 | LEFT warehouse-4 (physically (4,0)) placed at (0,0). It is only flagged as a one-layer ambiguity (19 vs 20), so the total stays, marked estimated |

Localization (B, C) changes no block status or total in these three sets. For ef823816 it changes the corner
readings, as shown in section 3.

**The same physical stack across photos** (B counts; full-base views only for the spread):

| Stack | Views (B count) | Spread |
|---|---|---|
| 9b4c (0,0) | STRAIGHT 15, LEFT 16, 30aca6a1 far 16 | 1 |
| 9b4c (1,0) | STRAIGHT 15, 30aca6a1 15 | 0 |
| 9b4c (2,0) | STRAIGHT 15, RIGHT (set back) 15, 30aca6a1 15 | 0 |
| 9b4c (3,1) | STRAIGHT 14, RIGHT 14, 30aca6a1 13 | 1 |
| G01 (4,0), 99-block free end | img-01 19, img-32 19, warehouse-4 19 | 0 |
| ef82 (4,0) short corner | STRAIGHT 8, RIGHT 14, LEFT 9 (A: 9 / 20 / 16, merged) | 6 |
| ef82 (4,1) | RIGHT 21, LEFT 22 (STRAIGHT sees 1 box of its top) | 1 |
| ef82 (4,2) | RIGHT 19, LEFT 27 | 8 |
| ef82 (4,3) | RIGHT 19, LEFT 15 | 4 |
| ef82 (3,0) | STRAIGHT 10 (RIGHT 6 and LEFT 5 see only its top above the short corner stack) | n/a |

Where views are close and boxes regular, the same stack reads within 1 layer across views and distances: 5
stacks, 14 readings. In ef823816, whose faces are far and boxed irregularly, readings of one stack differ by
up to 8 layers even with the polygons (spreads 6, 1, 8 and 4). That spread is layer counting, not association (I).

## 7. A versus C on the 24 labelled photos (22 near-duplicate clusters, M)

C has no gate, so A is compared ungated (A's predicted total) and with its deployed outcome.

| Clusters | n | A exact ungated | C exact ungated | A accepted (exact) | Abs error sum A / C | Median abs A / C |
|---|---|---|---|---|---|---|
| All | 22 | 9 | **12** | 10 (9) | 431 / 435 | 1 / 0 |
| Tier A | 12 | 8 | 11 | 9 (8) | 5 / 2 | 0 / 0 |
| Tier B | 10 | 1 | 1 | 1 (1) | 426 / 433 | 7.5 / 6.5 |
| Leak-free | 6 | 1 | 2 | 2 (1) | 25 / 24 | 1.5 / 1.5 |

**C's +3 exact clusters are development results.** C's designer had seen the labels and A's errors on img-35,
img-39 and img-49 before writing the short-stack and sliver rules that fix them (section 1). They show that the
rules do what they were written for, not that they generalise. On a held-out set, C's exact count is unknown.

**C differs from A in 6 clusters:**
- img-35 0 → 1 (exact; development result);
- img-39 3 → 2 (exact; development result);
- img-49 0 → 1 (exact; development result);
- img-33 0 → 1 (label 358);
- img-40 0 → 2 (label 10; 4 boxes for 10 trays);
- img-38 102 → 92 (label 118). C split one narrower box off the top of A's 29-layer column, whose walk had
  filled 10 layers. The rest walks 18. img-38 has no polygons, so whether the split is right cannot be
  checked; A's closer total may come from errors cancelling (I).

**C changed nothing elsewhere.** It changed no total on the 9 clusters A already gets exact. In img-36 it
split one column (16 → 10 + 6) and dropped 2 boxes as background short groups, without changing the total.
The big errors are unchanged: img-33 −358/−357 (1 box for a 358-tray face), img-31 −17, img-09 +10, img-04
+5, img-36 +5 and img-50 +4.

**What blocks the 12 withheld clusters** (the reasons are the deployed gate and flags (M); the grouping is
inferred):
- **Short stacks and loose trays** (fewer than 3 boxes): img-35, img-39, img-49 and img-40. C makes the first
  three exact; img-40 also lacks boxes.
- **Missing or irregular boxes:** img-33 (1 box), img-31 (oblique, box/pitch 0.65 in one column), img-38
  (box/pitch 0.64 in one column, 10 and 7 filled layers), img-04 and img-09 (walk/span disagreement; B shows
  that the polygons do not fix them), img-36 (missing layers), img-46 (base out of frame, 3 filled) and
  img-50 (9 filled, camera looking down).

  That is 8 of 12. Several also have two depths, but the img-04 and img-09 results show that depth
  separation alone does not fix the count.

## 8. Bottleneck decision

Scope of the decision: **among the two measurable arms, on single faces.** Association is not measurable, and
no counted genuine trio exists.

| Candidate | Evidence (n) | Verdict |
|---|---|---|
| Localization | 23 of 71 target polygons not `correct` in A (20 photos, 13 blocks), of which 7 are missed 1-box trays. The face-total effect is 11 trays out of 917; 2 of 18 error trays on the 9 labelled photos (7 blocks); 6 of A's 10 mixed stacks are count-neutral. It does change per-cell readings in corner blocks (ef823816). C fixes 10 polygons | **second** of the two measurable arms. Cheap to improve (C), small effect on totals today |
| Layer counting (detector boxes + walk) | 16 of 18 error trays remain with perfect polygons, 14 of them in two tier-B photos (img-09, img-04). 15 of 18 equal-extent pairs disagree by > 1 in the small-scale bucket, against 0 of 11 in the larger-scale one (3 blocks each; 12 of the 18 pairs from ef823816). 92 filled layers: 74 in the 12 polygons where walk > span + 1, 60 of them on regular boxes. 10 of 62 polygons have box/pitch < 0.75. The 5 user-100 stacks were localized right and missed 4-7 rows each. Cross-view spread in ef823816 is up to 8 layers. 8 of 12 withheld clusters | **larger of the two measurable arms, on single faces.** Root cause **not established** (I): missing detector rows (far, oblique, dark, cross-stacked) and the walk's fill and duplicate rules both contribute, and they were not separated here |
| Cross-view association | 1 plausible genuine set: 9/9 correct. 6 wrong assignments elsewhere: 5 from duplicated or substituted photos, 1 from the recess test on a far face with irregular boxes. No counted genuine trio (0) | **not measurable**, and not limiting where measurable. Its failures are capture errors |

The walk-fill experiment later separated one part of the layer-counting row: the walk's pitch ratchet. Section
9, item 0, gives the reconciled statement (second revision).

## 9. Recommendation for the next milestone

**0. Bottleneck after the walk-fill experiment (second revision; checked against both reports' results)**

- **The binding constraint is held-out physical truth.** Every count used here is user-written or
  user-reported. In the eval, 9 of the 10 accepted clusters are in-sample and only img-47 is out of sample, and
  the walk reference set is fitted to the labels (eval README, section 5).
- **On single faces, the walk's pitch ratchet is a real, label-free defect (M, walk-fill README).** After a
  fill, the deployed walk feeds the filled sub-gaps into its local pitch; the pitch falls to its 0.6 floor, and
  normal gaps are then counted as 2 layers. The observed-pitch walk V4 fixes the consistency: equal-extent
  pairs differing by more than 1 fall from 15 to 11 of 29, and their summed difference from 97 to 47. It moves
  0 of the 19 accepted results among 66 photos: no accepted total changes and none is withheld. It newly
  accepts 1 photo, img-45, a merged front/rear column. It changes 0 of the 53 reference columns and no block
  status.
- **The remaining error is far-face undercounting where a layer is under 3% of the frame height.**
  - Under V4, 11 of the 18 small-scale equal-extent pairs still differ by more than 1, against 0 of 11 at
    larger scale (M). The 11 are in 3 blocks: G05 (img-04) 2, G36 (MUTAA image-07) 2 and G43 (ef823816) 7.
  - That the error is under-counting is inferred (I). Under V4 the far user-100 stacks (a layer is 2.0-2.3% of
    the frame) read 14-18 against a user-reported 20 each. ef823816 STRAIGHT reads 10-18 against the 13 Oct
    visual reading of 20 per stack (D, not physical).
- **It points at detector recall at small scale, or at capturing closer.** These data cannot separate the two:
  scale is confounded with block (3 blocks per scale bucket), and no counted face was photographed at several
  distances.
- **Cross-view matching cannot be ranked.** There is 1 plausible genuine set (9b4c783e: 9 of 9 counted columns
  placed right) and no counted one.

**Plan:**
1. Physical per-stack counts on 3 or more new blocks, as STRAIGHT/LEFT/RIGHT sets with a distance ladder
   (section 10, items 1-3).
2. Then retrain on far and cross-stacked field faces, holding out by block (item 1 below).
3. Meanwhile, run V4 and C in shadow mode: compute and log them next to the deployed walk and grouping,
   without changing what the app shows or accepts.

**1. Detector retraining on field data (a candidate lever for faces with missing rows)**

The production model `projec-mutta/2` (rfdetr-medium, 67.3% recall on its own validation set) has never been
trained on October field photos (D: PROGRESS 15 Oct).

Annotate every tray row, including:
- far faces where boxes land on only some rows, boxing both row orientations of cross-stacked trays
  (ef823816 STRAIGHT/LEFT; MUTAA image-07 and img-04 also have irregular rows);
- distant long faces (img-33);
- oblique and looking-down views (img-31, img-50);
- loose and top-down trays (img-06, img-39, img-40);
- empty cover trays (a separate class if they must not be counted).

Hold out by physical block, never by photo (revised in the second verification). Every photo of a held-out
block stays out of training, with every byte copy, crop, synthetic variant and R2 upload of it. These are the
five blocks with no training copy, with their members from the 2026-10-15 dataset audit
(`dataset_inventory.json` → `groups` and `rows`):

| Block | What it is | Members |
|---|---|---|
| G03 | the 80 face, light green, 4 x 20 | labelled `img-25`, `img-27`, `img-30` and `img-31`. Their MUTAA byte copies in `work/external/MUTAA/FileOfEggLabels/`: `WhatsApp Image 2026-10-07 at 9.17.23 PM (1).jpeg` (= img-25), `9.17.24 PM (1).jpeg` (= img-27), `9.17.30 PM (2).jpeg` (= img-30) and `9.17.30 PM.jpeg` (= img-31). R2 uploads: be325a37 LEFT and STRAIGHT (img-25, img-27); 6bc75941 STRAIGHT and eaa108f5, 445c3010 and f3dbf7c6 LEFT (img-30, the last three from the mechanics trio); 0a5206ea LEFT (img-31) |
| G29 | single stack labelled 20 | labelled `img-46`; MUTAA byte copy `FileOfEggLabels/WhatsApp Image 2026-10-07 at 9.54.42 PM.jpeg`; R2 89af7a6b LEFT and 40104561 LEFT |
| G30 | single stack of 7 | labelled `img-47`; MUTAA byte copy `FileOfEggLabels/WhatsApp Image 2026-10-07 at 9.54.44 PM (1).jpeg`; R2 89af7a6b RIGHT |
| G31 | single pulp tray, REDMI 13, 5 Sep | labelled `img-49`; MUTAA byte copy `FileOfEggLabels/WhatsApp Image 2026-10-07 at 9.54.44 PM (3).jpeg`; MUTAA archive `reports/mutaa-20260916/originals/image-30.jpeg`, `image-31.jpeg` and `image-33.jpeg`, which are byte copies of `work/external/MUTAA/WhatsApp Image 2026-09-05 at 9.46.20 AM.jpeg`, `9.46.21 AM (1).jpeg` and `9.46.21 AM.jpeg`; R2 d49f2766 LEFT |
| G32 | two stacks close from above (40) | labelled `img-50`; MUTAA byte copy `FileOfEggLabels/WhatsApp Image 2026-10-07 at 9.54.44 PM (4).jpeg`; crops `reports/field-labelled-20261007/per-stack/full-img50.jpg` and `num-img50-c1-2.jpg`; R2 d49f2766 RIGHT, and the app's 1600 px re-encode uploaded as f81c04d7, 7d34c100 and 1f668334 LEFT (local copies only in the session scratchpad) |

- The audit gave no block to five synthetic variants made from these photos. They go with their blocks:
  `work/scratch-landscape/e2e/raw-46-r90.jpg`, `scene-46-r90.jpg`, `upload-46-r90.jpg` and
  `work/scratch-landscape/worker/images/img-46-cpad.jpg` (G29), and `.../img-50-cpad.jpg` (G32).
- The audit could not confirm whether G32's two stacks are img-41's front pair. img-41 is in block G18 (img-26,
  img-41, their MUTAA byte copies, f81c04d7 RIGHT and STRAIGHT), which has no training copy either. Keep G18
  out until the user settles it.
- Every newly counted block is held out the same way.
- Held out of detector training is not the same as unseen by the counting logic. G03, G29 and G32 were used in
  capture-gate or walk tuning (eval README, section 5). Only G30 (img-47) and G31 (img-49) are untouched by
  both.

The first check needs no labels: on the held-out far photos, equal-extent stacks should read the same, walk
should equal span, fills should be at most 1 per stack and box/pitch should be at least 0.75. The real score
then needs physical counts.

**2. Cheap software, alongside**
- C's sliver filter and short-stack rule. On the labelled set they gave +3 exact clusters (img-35, img-39,
  img-49) and changed no total on the 9 clusters A already gets exact. The +3 are development results: the
  designer had seen these labels. They need a held-out check, and the gate needs a path for 1-2 box stacks,
  before this can ship.
- Keep C's depth split experimental. All 5 splits it made on the polygon photos are at true polygon
  boundaries. However, one pair inside ef823816 `l_setback` also meets both thresholds and stays whole only
  because of the widest-gap rule (section 1). The split also fired on img-36 and img-38, which have no
  polygons. Ship it only after polygons exist for more multi-depth photos.
- A duplicate-face check between side views. From the audit (D, not re-measured): SIFT inliers were 477 for
  ef823816 LEFT vs RIGHT and 168 for warehouse-4 vs img-32, against 6-13 between the genuine 9b4c783e faces.
  That would have caught both non-genuine trios.

**3. Not next: cross-view matching**

Nothing measured points at it, and it cannot be scored until a counted genuine trio exists.

## 10. Photos and physical counts still needed

1. **Physical per-stack counts**, filled and empty covers separately:
   - the 9b4c783e block: 10 visible stacks, plus the 2 hidden cells;
   - the ef823816 block: front 5, right side 4 and interior, if it is unchanged.

   These would be the first counted genuine trio and the first far cross-stacked face with truth.
2. **Three or more new blocks** with STRAIGHT/LEFT/RIGHT photos and physical per-stack counts: one free
   standing, one with a side against a wall, and one with a short or missing corner stack.
3. **A distance ladder on one counted face:** about 1.5 m, 3 m and 5 m, plus the ultra-wide lens. This would
   measure row recall against distance; 9b4c783e vs 30aca6a1 is the only existing pair and it has no count.
4. **Counts or scope for existing photos:** a physical count of the 5 user-100 stacks (now a user report),
   per-stack counts or the user's scope for img-04 (115) and img-09 (75), and the user's scope for img-41
   (81), img-06 and img-43.
5. **Un-inked camera originals** for ids 25-31 and 41-51 (hold-out and annotation). The R2 scans 014ee9a6 and
   2b75577c need `npx wrangler login` first; the token had expired (D: eval README).
6. **Polygons for more multi-depth photos** (img-36, img-38, img-20, img-30, img-31, img-50) to validate C's
   depth split.

## 11. Limitations

- All counts used as truth are user-written or user-reported, not physical recounts. The tier B scopes are the
  audit's reading.
- The polygons and their `physical_stack_inferred` links are Claude's. They were reviewed by a second agent,
  not by the user, and the links were not verified pixel by pixel.
- The polygons were drawn on the inked photos with the handwritten number visible, and the target role
  encodes the audit's scope reading, which was partly reasoned from label values (`REVIEW.md`).
- All numbers are development-set numbers:
  - n is small: 9 labelled polygon photos on 7 blocks; 20 polygon photos on 13 blocks; 74 target polygons on 55
    physical-stack keys; 1 plausible genuine trio;
  - the scale comparison has 3 blocks per bucket, and 12 of the 18 small-scale pairs are one block;
  - C was designed on these 20 photos, after its designer had seen the labels;
  - A's gate and walk were tuned on most of the labelled photos. img-32 and warehouse image-4 were walk
    development photos.
- The bottleneck ranking covers single faces and the two measurable arms only. This experiment did not separate
  the walk's fill rule from detector recall; the walk-fill experiment separated the pitch ratchet (section 9).
- "Boxed layers" assumes the walk placed each box on its true layer. The equal-extent test assumes stacks of
  the same extent hold the same number of trays of one type.
- C has no capture gate. Its totals are compared with A's ungated totals.

## 12. Reproduce and test

From the repository root, with `work/vision-deps` on `PYTHONPATH`:

```
python scripts/experiment_stack_faces.py --out <scratch dir>
cd backend && python -m pytest -p no:faulthandler tests/test_stack_separation.py tests/test_block_model.py tests/test_layer_span.py
python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_experiment_stack_faces.py scripts/tests/test_label_perturbation.py
```

`--out` defaults to this folder. Pass a scratch folder so that reproducing does not overwrite the report. Two
runs after the revision gave a byte-identical `results.json` (M).

Measured on 2026-10-15, after the revision:

| Suite | Result |
|---|---|
| `test_stack_separation.py` + `test_block_model.py` + `test_layer_span.py` | 51 passed (12 + 26 + 13) |
| `test_experiment_stack_faces.py` + `test_evaluate_labelled.py` + `test_label_perturbation.py` | 17 passed (3 + 12 + 2) |
| Full backend suite, one run | 148 passed, 0 failed |
| ruff, backend config, on `stack_separation.py` and `test_stack_separation.py` | clean. The 10 earlier E501/UP031 findings are fixed, and the backend total is back to 34 |
| Second revision (text only): `scripts/experiment_stack_faces.py --out <scratch>` | byte-identical to `results.json` (SHA-256 `6b86fa5d…26f9dd`) |
| Second revision: the three backend suites above | 51 passed |
| Second revision: `test_experiment_stack_faces.py` + `test_evaluate_labelled.py` + `test_label_perturbation.py` + `test_experiment_walk_fill.py` | 30 passed (3 + 12 + 3 + 12); the perturbation test now also covers the walk-fill script |

`results.json` keys:
- `totals_per_image`, `scored_polygon_images`, `not_usable_polygon_images`;
- `localization_A` and `localization_C`, with per-image detail in `per_image.<id>.loc_A` / `loc_C`;
- `layer_counting_B`, `walk_vs_span_B`, `layer_counting_per_image`, `equal_extent_pairs`, `per_stack_recall`;
- `physical_n`: blocks, physical-stack keys, and the equal-extent buckets by block;
- `cross_view_association`, `physical_stacks_in_several_photos`;
- `labelled_set_A_vs_C`;
- `per_image`, which holds every column, polygon and stack.
