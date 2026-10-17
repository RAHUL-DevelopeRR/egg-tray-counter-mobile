# Current counting logic on the labelled photos (saved detections only), 15 October 2026

Evaluation session, 2026-10-15 (Claude Code). No inference, no paid call, no deployment, no phone, no commit.
Only new files were written; frozen benchmarks and earlier report data are untouched.

**Revised the same day after an adversarial verification.** These changes were made:
- img-32 and warehouse image-4 are tagged as walk-counter development photos;
- the walk reference rows derived from labels are disclosed;
- a block-level line and a secondary table for the 28 not-usable labels are added;
- a label-perturbation test is added.

`results.json` and `results.csv` were regenerated. Only the `logic_dev` strata changed. New keys were added:
`summary_blocks`, `blocks`, `not_usable_secondary`, `in_walk_development_photos` and the per-stack
`walk_development_photo`. Every other number is unchanged (M).

**Revised again the same day after a second verification.** These changes were made:
- the walk reference set is disclosed as label-conditioned as a whole, not only in the rows that cite the
  label (section 5);
- img-46 is tagged as a capture-gate development photo (`in_orientation_development_photos`, section 5). The
  logic-tuning strata are recomputed: "not used in logic tuning" is now n = 5, and a new stratum "untouched by
  detector and logic" is n = 2;
- the label-perturbation test now also covers `scripts/experiment_walk_fill.py`.

`results.json` and `results.csv` were regenerated again and compared key by key with the previous output (M).
Only the `logic_dev` strata changed; their `untouched` key is renamed `not_used_in_logic_tuning`. New: the
`detector_and_logic` strata and the per-photo `in_orientation_development_photos` field, which is also a CSV
column. Every other number is unchanged.

**M** = measured here. **I** = inference. **D** = taken from a repo document.

## In brief

- **What was scored:** the counting logic that staging `47cb2378` runs (Worker commit `318eb04`, app 0.4.11).
  It was applied to the Roboflow boxes saved on 7 Oct for the count-labelled WhatsApp photos. The logic is the
  walk counter, the block model's per-column retake reasons and the capture gate. No new detection was run.
- **Primary unit:** 22 near-duplicate clusters, one for each distinct usable label. 10 were accepted: 9 exact
  and **1 wrong**. 12 (55%) were withheld: 8 by the capture gate and 4 by a column flag. **The one incorrect
  accepted result is img-30** (label 80, shown 78 = 20/19/20/19). It is one of the six photos with no copy in
  any training export (M).
- **Leaked vs leak-free:** among the 16 leaked clusters, 8 of 8 accepted results were exact. Among the 6
  leak-free clusters, 1 of 2 was exact. Every number here also comes from photos the counting thresholds were
  tuned on (see Leakage), so these are development-set numbers, not a held-out accuracy (M/D).
- **Physical blocks:** the 22 clusters sit on 19 blocks. With one photo per block (the lowest label id), 8 are
  accepted: 7 correct and 1 wrong. On the 5 leak-free blocks, 2 are accepted: 1 correct and 1 wrong (M).
- **The accepted results are in-sample (M).** 8 of the 10 accepted clusters (img-01, 02, 08/23, 19, 20,
  21/24, 30, 34) are the 9 Oct walk validation photos, and this evaluation repeats that validation column for
  column: every column it sums on them is one of the 53 reference columns, with the same walk count. Those
  references are label-conditioned as a whole (section 5). With img-32, a walk-development photo, 9 of the
  10 accepted clusters are in-sample. Only img-47 is out of sample.
- **Not used in logic tuning:** 5 clusters (img-35, 39, 40, 47, 49). 1 is accepted and correct (img-47, 7
  trays); the other 4 are withheld by the gate. img-32 (walk-counter development, 9 Oct) and img-46
  (capture-gate development for 0.4.8) are not counted here (section 5). Untouched by both detector training
  and logic tuning: 2 clusters, img-47 (accepted, correct) and img-49 (withheld).
- **Labels the audit marked not usable (28, secondary):** the gate accepts 2 of them. img-25 shows 13
  against a written 80, and img-26 shows 83 against a written 125. The other 26 are withheld (M).
- **Withholding:** none of the 12 withheld photos would have been exact (M). Every abstention was on a photo
  the walk sum got wrong. Loose trays (1, 2, 1 and 10 trays) are always withheld: fewer than three boxes do not
  make a stack.
- **Per stack:** 9 observations of 8 physical stacks, all user-reported. The 3 accepted observations equal the
  user value (19, 19, 7). Two of them (19, 19) are the same physical stack, photographed in img-32 and
  warehouse image-4. Both photos were part of the walk-counter development, so only img-47's 7 is
  independent. The 5 user-100 stacks read 16/26/24/15/14 against 20 each. The gate refuses that photo, but 2
  of those 5 columns carry no column flag (M).
- **Multi-view:** no trio gives `exact` on the 0.4.11 logic. Two non-genuine trios still show a total marked
  `estimated`: the substituted 99-block trio shows 99 and the mechanics trio (three different blocks) shows
  399. On the pre-0.4.11 Worker both had a total with no conflict (M).
- **Not done:** the two unidentified R2 scans could not be downloaded. The wrangler OAuth token expired
  2026-10-14 16:52 UTC and the API answered 403. It was not refreshed.

## 1. Saved detections and their settings

| Check | Result |
|---|---|
| Files | `reports/field-labelled-20261007/raw/batch-01..18.json`: 18 responses, all HTTP 200, `model.model_id` = `projec-mutta/2`, `processing.mode` = `model_spatial_v1` (M). Requests went to the production Worker (D: `run_v2_baseline.py`). |
| Ids 1 and 2 | Present twice: id 1 in batch-01 LEFT and batch-18 RIGHT, id 2 in batch-01 RIGHT and batch-18 STRAIGHT. The box lists are **identical** (M), so the choice has no effect. **The batch-01 copies are used** (first occurrence). |
| CONFIDENCE | Not recorded in the responses. The Worker config at the time had `CONFIDENCE "35"` (D: `git show 5967ce8:cloudflare-worker/wrangler.jsonc`). Measured: 2,839 boxes over 52 photos, minimum confidence 0.3504, **0 below 0.35** (M). Consistent with 35. |
| OVERLAP | Config `OVERLAP "50"` (D). The returned boxes are **not** NMS-filtered at IoU 0.5: 67 box pairs over IoU 0.5 in 35 of 52 photos, maximum IoU 0.992 (M). Inferred: the production RF-DETR model (Roboflow v2 trainings are `rfdetr-large`/`rfdetr-medium`) applies no NMS, so the parameter has no visible effect. That holds equally today. Duplicate boxes are removed by the walk counter, not by the detector (I). |
| Today | Staging `47cb2378`: `MODEL_ID projec-mutta/2`, `CONFIDENCE 35`, `OVERLAP 50` in the source config (D: `git show 318eb04:cloudflare-worker/wrangler.jsonc` env.staging). Checked live: the 14 Oct `/ready` returned `projec-mutta/2`. The Cloudflare audit lists the same var names on the deployed version but **not their values**, and they were not re-read today because the token had expired. `RIM_VERIFY` is unset: all five live `47cb2378` responses report rim verification `disabled` (M). It is off here too. |
| Same boxes later? | The same photo files re-sent to staging on 8-9 Oct gave **identical box sets** for img-01, img-32, img-19, img-30 and img-02 (5/5, M). Warehouse image-4 on 23 Sep (production) and on 9 Oct (staging): identical, 19 boxes (M). img-50 versus f81c04d7 LEFT differ, but those are different files: the app's 1600 px re-encode. |
| Image size for the gate | The 7 Oct responses carry no `image` field. The gate uses the file's pixel size (`datasets/.../manifest.json`; no EXIF orientation). Roboflow's reported size equals the file size for the 5 labelled photos where staging returned it (M). |
| MUTAA 2026-09-16 boxes | `reports/mutaa-20260916/raw`: 42 view responses, 989 boxes, `projec-mutta/2`. The request metadata says confidence 35, overlap 50, but `settings_source` is "checked-in gateway configuration", not read from the Worker. Minimum confidence 0.3504, 0 below 0.35. 41 pairs over IoU 0.5 in 19 views, max 0.973 (M). These photos carry **no count label**, so they are not scored. |

## 2. What the labels mean

- Each label is the number the user wrote on the photo (WhatsApp, 7 Oct). The audit re-read the digits and all
  agree with `labels.csv`. The user called them verified manual counts of the stack face. **They are not
  independent physical recounts.**
- What each number covers was decided by the assistant in the 2026-10-15 audit and has **not been confirmed by
  the user**. Tier A (14 labels) = scope clear. Tier B (10) = scope probable, for example two depths, edge
  clutter, an oblique view, a distant view, or whether empty trays count.
- Usable at image level: 24 labels on 23 distinct photographs. They form 22 near-duplicate clusters on 19
  physical blocks. img-08 = img-23 is the same photograph; img-21 and img-24 are burst shots.
- Labels are scoring targets only. `predict_face` and `predict_block` have no label parameter, and labels are
  joined in `score_photo` after prediction. `scripts/tests/test_label_perturbation.py` changes every label value
  and per-stack truth value. Every prediction stays byte-identical, and the scores change (M). In this
  evaluation's code, no threshold, column choice or stack count used a label. The user-100 column selection uses
  only SIFT geometry (section 6).
- **This does not hold for the logic under test.** The deployed walk counter was validated on
  `reports/field-labelled-20261007/per_stack_counts.csv`. That reference set is label-conditioned as a whole:
  on every resolved photo the per-stack references sum exactly to the label (section 5).

## 3. Method

For every usable photo (`eval_manifest.json`, built from the audit's `dataset_inventory.json`):

1. **Columns:** `count_layers_by_span` (backend/app/vision/layer_span.py). Boxes are grouped into x-columns, and
   only columns with 3 or more boxes are kept. Each kept column gets a span count and a walk count (duplicates
   merged, at most 2 missed layers filled per gap).
2. **Column flags:** block model `_face` (block_model.py), the same reasons the Worker uses. A column is
   flagged for: box/pitch ratio < 0.75, an unbridged gap (more than 2 missed layers), span and walk differing
   by more than 1, or a perspective gradient > 1.5 (camera looked down). The rim veto is off on staging.
3. **Capture gate:** a line-by-line Python port of `captureQuality` / `medianBoxAspect` from index.ts at
   318eb04. The rules are sideways boxes (median w/h < 2.75), pitch gradient > 1.2 across the face, width
   coverage < 0.45 (0.25 for a single column, waived when the face fills 80% of the height), height < 0.4, and
   no stacks.
4. **Predicted total = the sum of `walk_count` over every kept column on the photo.** It includes columns the
   block model would mark *recessed*: the block model counts those as an observed stack behind a missing front
   one. It also includes *flagged* columns, but those are only reported, because a flag withholds the photo.
   Boxes in groups of fewer than 3 are never counted. No accepted photo has a recessed column, so excluding
   recessed columns changes no accepted result (M).
5. **Outcome:** a gate refusal gives **withheld (gate)**. Otherwise, any flagged column gives
   **withheld (flagged)**. Otherwise the photo is **accepted**. An accepted photo is **correct** when the
   predicted total equals the label, and **wrong** (an incorrect shown result) otherwise.
6. **Metrics:**
   - completion rate = accepted / n, and withheld rate = withheld / n;
   - exact on accepted = correct / accepted;
   - absolute tray error over all photos, using what the walk sum would have said (0 when no stack was found),
     and over accepted photos only.
7. **Units:** the primary unit is the near-duplicate cluster (n = 22), represented by its lowest label id. In
   both multi-member clusters (8/23 and 21/24) the members give the same result. The label-level table
   (n = 24) and the block-level line (n = 19 physical blocks, lowest label id per block; added after
   verification) are secondary.

This is a **single-face proxy**. The deployed scan needs three distinct photos. These numbers cover the parts
of the pipeline that act on each face (gate, columns, flags) and the observed front-row count. They do not
cover the block model's cross-face rules or its computed interior (section 6 covers those as workflow tests).

**Parity (M):** the HEAD Worker source (`git show 318eb04`) was transpiled with the Worker's own TypeScript and
run through its real request path, with Roboflow mocked by the saved boxes. On all 38 cases it matches the
Python result exactly: 24 photos and 14 multi-view replays, comparing gate decision, reasons, metrics, columns,
block cells and conflict reasons. Mutation check: changing the gate height floor to 0.3, or the box/pitch
floor to 0.8, in the Python side produces mismatches, so the comparison is not vacuous.

## 4. Results (image level)

### Headline, 22 clusters

| Stratum | n | accepted | correct | wrong | exact on accepted | withheld (gate, flagged) | abs error all: mean / median | abs error accepted: mean |
|---|---:|---:|---:|---:|---:|---|---|---:|
| **all** | **22** | **10** | **9** | **1** | **9/10** | **12 (8, 4)** | 19.59 / 1 | 0.20 |
| tier A | 12 | 9 | 8 | 1 | 8/9 | 3 (3, 0) | 0.42 / 0 | 0.22 |
| tier B | 10 | 1 | 1 | 0 | 1/1 | 9 (5, 4) | 42.6 / 7.5 | 0 |
| leak-free (30, 31, 46, 47, 49, 50) | 6 | 2 | 1 | 1 | 1/2 | 4 (2, 2) | 4.17 / 1.5 | 1.0 |
| leaked | 16 | 8 | 8 | 0 | 8/8 | 8 (6, 2) | 25.38 / 0.5 | 0 |
| label <= 10 trays | 5 | 1 | 1 | 0 | 1/1 | 4 (4, 0) | 2.6 / 1 | 0 |
| 11-60 | 4 | 2 | 2 | 0 | 2/2 | 2 (0, 2) | 1.25 / 0.5 | 0 |
| > 60 | 13 | 7 | 6 | 1 | 6/7 | 6 (4, 2) | 31.77 / 2 | 0.29 |
| not used in logic tuning (35, 39, 40, 47, 49) | 5 | 1 | 1 | 0 | 1/1 | 4 (4, 0) | 2.6 / 1 | 0 |
| used in gate tuning, walk reference, walk development or capture-gate development | 17 | 9 | 8 | 1 | 8/9 | 8 (4, 4) | 24.59 / 1 | 0.22 |
| untouched by detector and logic (47, 49) | 2 | 1 | 1 | 0 | 1/1 | 1 (1, 0) | 0.5 / 0.5 | 0 |

The logic-tuning rows were corrected twice after verification. First img-32 left the untuned row (n 7 → 6): it
is a walk-counter development photo. Then img-46 left it (n 6 → 5): it is a capture-gate development photo
(section 5). The last row is new. At block level the two logic rows read n = 5 (1 accepted, 1 correct) and
n = 14 (7 accepted, 6 correct), and the untouched row n = 2 (`summary_blocks`).

**Block level (M).** The 22 clusters sit on 19 physical blocks (`group_id`). G01 has 2 clusters (img-01,
img-32), G02 has 2 (img-19, img-21/24) and G03 has 2 (img-30, img-31). With one photo per block (the lowest label
id):

| Blocks | n | accepted | correct | wrong | withheld (gate, flagged) |
|---|---:|---:|---:|---:|---|
| all | 19 | 8 | 7 | 1 | 11 (7, 4) |
| leak-free (G03, G29, G30, G31, G32) | 5 | 2 | 1 | 1 | 3 (1, 2) |

G03 is the only block whose photos disagree: img-30 is accepted and wrong, and img-31 is withheld. If img-31
represented G03 instead, the lines would read 7 accepted, 7 correct and 0 wrong (all), and 1 accepted, 1 correct
and 0 wrong (leak-free). Every stratum is in `results.json` → `summary_blocks`, and the membership is in `blocks`.

- Completion rate 10/22 = 45%, withheld rate 12/22 = 55%, correct and shown 9/22 = 41%.
- **Incorrect accepted: 1** (img-30).
- Withheld photos that would have been exact: **0 of 12**.
- The mean error over all photos is dominated by img-33: label 358, a distant 19-column face that got 1 box.
  The median absolute error over all is 1.

At label level (n = 24, counting 8/23 and 21/24 twice): accepted 12, correct 11, wrong 1, withheld 12 (8 gate,
4 flagged). Mean absolute error 17.96 over all, 0.17 over accepted. Every stratum's table is in
`results.json` → `summary_labels`.

Comparison on the same 22 clusters: the **raw V2 box count** (the August baseline) is exact on 4 of 22, with
mean absolute error 21.05 and median 3 (M).

### Per photo

| id | label | tier | leak | cluster | boxes | walk per column | predicted | error | gate | column flags | result |
|---|---:|---|---|---|---:|---|---:|---:|---|---|---|
| 1 | 99 | A | leaked | ND0014 | 101 | 20/20/20/20/19 | 99 | 0 | pass | - | accepted correct |
| 2 | 80 | A | leaked | ND0141 | 81 | 20/20/20/20 | 80 | 0 | pass | - | accepted correct |
| 4 | 115 | B | leaked | ND0143 | 110 | 19/15/21/19/19/27 | 120 | +5 | too far (height 0.395) | span/walk disagree | withheld gate |
| 8 | 160 | A | leaked | ND0145 | 157 | 20 x 8 | 160 | 0 | pass | - | accepted correct |
| 9 | 75 | B | leaked | ND0146 | 71 | 21/7/17/20/20 | 85 | +10 | pass | span/walk disagree, unbridged gap | withheld flagged |
| 19 | 100 | A | leaked | ND0049 | 100 | 20 x 5 | 100 | 0 | pass | - | accepted correct |
| 20 | 60 | B | leaked | ND0071 | 63 | 20/20/20 | 60 | 0 | pass | - | accepted correct |
| 21 | 100 | A | leaked | ND0155 | 101 | 20 x 5 | 100 | 0 | pass | - | accepted correct |
| 23 | 160 | A | leaked | ND0145 | 157 | 20 x 8 | 160 | 0 | pass | - | accepted correct (= img-08) |
| 24 | 100 | A | leaked | ND0155 | 101 | 20 x 5 | 100 | 0 | pass | - | accepted correct (burst of 21) |
| **30** | **80** | A | **leak-free** | ND0160 | 81 | **20/19/20/19** | **78** | **-2** | pass | - | **accepted WRONG** |
| 31 | 80 | B | leak-free | ND0161 | 52 | 16/19/18/10 | 63 | -17 | sideways (w/h 2.19), angled | box/pitch, span/walk | withheld gate |
| 32 | 19 | A | leaked | ND0013 | 24 | 19 | 19 | 0 | pass | - | accepted correct |
| 33 | 358 | B | leaked | ND0162 | 1 | - | 0 | -358 | no stacks | - | withheld gate |
| 34 | 120 | A | leaked | ND0019 | 125 | 20 x 6 | 120 | 0 | pass | - | accepted correct |
| 35 | 1 | A | leaked | ND0088 | 1 | - | 0 | -1 | no stacks | - | withheld gate |
| 36 | 109 | B | leaked | ND0163 | 117 | 16/20/20/18/20/20 | 114 | +5 | pass | unbridged gap | withheld flagged |
| 38 | 118 | B | leaked | ND0057 | 94 | 21/20/29/23/9 | 102 | -16 | too narrow (0.395) | box/pitch, span/walk | withheld gate |
| 39 | 2 | A | leaked | ND0045 | 5 | 3 | 3 | +1 | sideways, too narrow | - | withheld gate |
| 40 | 10 | B | leaked | ND0061 | 4 | - | 0 | -10 | sideways, no stacks | - | withheld gate |
| 46 | 20 | B | leak-free | ND0168 | 18 | 19 | 19 | -1 | pass | span/walk disagree (17 vs 19) | withheld flagged |
| 47 | 7 | A | leak-free | ND0169 | 7 | 7 | 7 | 0 | pass | - | accepted correct |
| 49 | 1 | A | leak-free | ND0170 | 1 | - | 0 | -1 | sideways, no stacks | - | withheld gate |
| 50 | 40 | B | leak-free | ND0010 | 35 | 25/19 | 44 | +4 | pass | span/walk disagree, steep perspective | withheld flagged |

Per-column metrics (pitch, box/pitch ratio, gradient, recessed flag, reasons) are in `results.json` → `photos[].columns`.
img-01 and img-32 are walk-counter development photos, and img-46 is a capture-gate development photo
(section 5).

### Secondary: the 28 labels the audit marked not usable (M, never in a headline number)

The audit excluded these labels because the scope of the written number is unclear: region brackets, several
faces, an occluded or cut part, or duplicate photos. In places the exclusion was reasoned from the value itself
(for example img-41: "arithmetic of 81 does not fit the visible stacks"). The deployed logic was still run on
them, on the same saved 7 Oct boxes and with each file's pixel size. The written number is shown for orientation
only and is not a valid target.

| id | written (regions) | block | shown (walk per column) | outcome | audit: why not usable |
|---|---|---|---|---|---|
| 3 | 80 | G04 | 65 (19/18/19/9) | withheld, gate | one face of a multi-face, multi-object frame |
| 5 | 235 (120, 115) | G05 | 17 (17) | withheld, gate | region labels; 235 is not a whole-image count |
| 6 | 4 | G07 | 0 (no stack) | withheld, gate | region label (bracket) |
| 7 | 4 | G07 | 3 (3) | withheld, gate | region label (bracket) |
| 10 | 30 | G09 | 39 (8/16/15) | withheld, gate | unit or scope unclear |
| 11 | 8 (2, 6) | G07 | 0 (no stack) | withheld, gate | same photograph as img-40 |
| 12 | 205 (100, 105) | G11 | 0 (no stack) | withheld, gate | the sum double-counts the shared corner column |
| 13 | 204 (84, 120) | G12 | 0 (no stack) | withheld, gate | region labels |
| 14 | 132 (80, 52) | G13 | 80 (18/15/7/5/9/26) | withheld, gate | two faces; one is cut by the frame |
| 15 | 62 | G13 | 16 (8/5/3) | withheld, gate | region label (bracket) |
| 16 | 119 | G14 | 130 (19/20/20/20/20/20/11) | withheld, flag | region label; same photograph as img-22 |
| 17 | 109 | G15 | 63 (6/12/19/19/7) | withheld, gate | region label; same block as img-36 |
| 18 | 129 | G16 | 128 (10/19/22/19/20/20/18) | withheld, flag | region label |
| 22 | 119 | G14 | 124 (19/20/20/20/20/20/5) | withheld, flag | same photograph as img-16 |
| **25** | 80 | G03 | **13 (13)** | **accepted** | the label covers one of two visible faces |
| **26** | 125 | G18 | **83 (22/20/21/20)** | **accepted** | front block plus a partly occluded back block; cannot be checked |
| 27 | 80 | G03 | 21 (4/17) | withheld, gate | the label covers one of two visible faces |
| 28 | 143 | G19 | 104 (14/11/19/20/20/20) | withheld, flag | same block as img-51, which is labelled 262 |
| 29 | 130 | G20 | 48 (15/15/18) | withheld, gate | scope unclear |
| 37 | 4 | G07 | 3 (3) | withheld, gate | the label covers a subset of the visible trays |
| 41 | 81 | G18 | 48 (4/4/20/20) | withheld, flag | 81 does not fit the visible stacks |
| 42 | 180 | G25 | 15 (13/2) | withheld, gate | the label exceeds what is visible |
| 43 | 5 | G26 | 5 (5) | withheld, gate | stack cut by the frame |
| 44 | 185 | G27 | 120 (16/26/24/15/14/14/11) | withheld, gate | multi-part scene (contains the user-100 face) |
| 45 | 107 | G28 | 28 (28) | withheld, flag | the label exceeds what is visible |
| 48 | 180 | G25 | 13 (11/2) | withheld, gate | duplicate of img-42 |
| 51 | 262 | G19 | 92 (12/19/20/20/21) | withheld, gate | conflicts with img-28 (143) |
| 52 | 25 | G33 | 22 (5/6/11) | withheld, gate | whether empty trays count is unknown |

- **Accepted: 2 of 28.** img-25 shows 13 against a written 80. It is a grazing view of the G03 block, the block
  of img-30 and img-31, and one column of 13 boxes passes the gate. img-26 shows 83 against a written 125: its
  four front columns read 22/20/21/20, and the label also covers a partly occluded block behind. Neither
  shown number equals the written one. The app would show both as results.
- **Withheld: 26** (20 by the gate, 6 by a column flag).
- These were excluded by label scope, not by outcome. They show that the gate can accept a photo whose
  intended count it cannot see (img-25). Rows are in `results.json` → `not_usable_secondary`.

## 5. Leakage

- **Detector training (M, audit):** 18 of the 24 labels have an un-inked copy in a training export (v1 export,
  review queue or canonical_clean). Only ids **30, 31, 46, 47, 49, 50** (5 blocks) have none.
- **Roboflow `projec-mutta` version 2 (M, read-only MCP, today):**
  - `versions_get`: 99 images (train 69, valid 22, test 8), created 2026-08-21. Auto-orient, resize to fit
    within 640, required filter tag `clean-manual-auto-reconciled-v2`. Trainings `rfdetr-large` and
    `rfdetr-medium`.
  - Today **109** images carry that tag (`images_workspace_search`). A `version:2` RoboQL query returned an
    error, and no available tool lists a version's frozen images, so **the frozen 99 cannot be established**.
  - Clean copies of ids 19, 20, 34 and 40 carry the tag in the train split today; 35 and 38 carry it in the
    valid split. The other leaked ids have copies only in the v1 export, review queue or canonical sets, with
    no v2 tag today.
- **Counting-logic development (D):**
  - 17 of the 24 labels were in the 39-photo set that tuned the capture gate (`capture_tags.csv`).
  - 13 photos are the walk-counter reference photos (`per_stack_counts.csv`). The box/pitch 0.75 floor was
    checked on the same references.
  - Leak-free 30, 31 and 50 were in the gate tuning set.
  - **img-46 is a capture-gate development photo** (D/M, added in the second verification). The 0.4.8
    orientation work (`reports/orientation-20261009`) used it as one of its five scenes. Its padded landscape
    variant `img-46-cpad` is one of the 7 landscape variants on which the 0.4.8 full-height waiver (0.8) and
    sideways guard (median box width/height 2.75) were checked (commit 1e8591e; PROGRESS 2026-10-10: "all 7
    landscape variants accepted"). The manifest tags it `in_orientation_development_photos`. It was in no
    other tuning set, so it leaves the "not used in logic tuning" stratum.
- **Walk-counter development photos (D/M, added after verification): img-32 and warehouse image-4.**
  - On 9 Oct the walk counter was changed while the 99-block trio was being probed on staging. In that trio
    img-01 is STRAIGHT, warehouse image-4 is LEFT and img-32 is RIGHT.
  - `reports/staging-block-20261008/scan-99block-walk.json` (11:30, walk v1) read img-32 as 23. After the
    change, `scan-99block-walk2.json` (11:34) read it as 19. PROGRESS 2026-10-09 records this: "the from-above
    side photo now reads 19 (was 23 with walk v1)".
  - img-32's boxes in `scan-99block-walk2.json` are identical to the 7 Oct boxes used here (section 1), and
    both runs hold 24 boxes for it. Warehouse image-4 read 19 in both runs.
  - The manifest therefore tags `in_walk_development_photos` (img-01, img-32) and the per-stack
    `walk_development_photo` (img-32, warehouse image-4). img-32 is no longer in the "not used in logic
    tuning" stratum.
- **The walk reference set is label-conditioned as a whole (M, revised in the second verification).**
  - The deployed walk counter was checked against the 53 reference stacks with an `assistant_count` in
    `reports/field-labelled-20261007/per_stack_counts.csv` (`eval_walk.py`; walk exact 51/53, PROGRESS
    2026-10-09).
  - That file covers 13 photos. 10 are resolved: img-01, 02, 08, 19, 20, 21, 23, 24, 30 and 34. On **all 10**
    the per-stack references sum exactly to the photo's label (99, 80, 160, 100, 60, 100, 160, 100, 80 and
    120).
  - 13 of the 53 references differ from the span count, and **every one of the 13 is set to 20**: img-01 col 1,
    img-02 col 1, img-08 cols 6 and 8, img-20 col 3, img-23 cols 4 and 6, img-24 cols 3 and 5, img-30 cols 2, 3
    and 4, and img-34 col 3. 7 of them cite the label in their basis (for example "label 80 implies 20"). The
    other 6 cite a spurious, extra or duplicate box, or a column cut by the frame or the crop window.
  - img-04, img-09 and img-50 were left unresolved, with no reference value. img-50 col 2 cites the label but
    has no value. The 8 rows that cite the label are listed in the manifest
    (`walk_reference_rows_citing_label`); two of them are on leak-free photos (img-30 col 2, img-50 col 2).
  - So the whole reference set was fitted to the labels, not only the 7 rows that cite them (I, from the exact
    sums and the uniform 20). The counter under test is not independent of these labels, even though this
    evaluation's code never reads a label before scoring.
- **What that means for the accepted results (M, added in the second verification).**
  - The 10 resolved reference photos are exactly the 10 accepted labels of 8 accepted clusters: img-01, 02,
    08/23, 19, 20, 21/24, 30 and 34. Every column this evaluation sums on them is one of the 53 reference
    columns (5 + 4 + 8 + 5 + 3 + 5 + 8 + 5 + 4 + 6 = 53).
  - The walk count of each of those columns is the same under the 9 Oct `layer_span.py` (badf693) and the
    evaluated one (318eb04), and equals this evaluation's. These 8 clusters therefore repeat the 9 Oct walk
    validation column for column. Its 2 misses, img-30 cols 2 and 4 (walk 19 against a reference of 20), are
    this evaluation's one wrong accepted result.
  - With img-32 (walk development), 9 of the 10 accepted clusters are in-sample. Only img-47 is out of sample.
- **Only 47 and 49 are untouched by detector training and by all logic tuning** (n = 2): 47 accepted
  correct, 49 withheld (gate). img-46 left this set in the second verification (capture-gate development).

## 6. Per stack (user-reported, not physical)

Per-stack truth that is not a total divided by a stack count: 5 photos, 8 physical stacks, 9 observations.

| case | photo outcome | stack | user | walk (span, boxes) | walk - user | column flag |
|---|---|---|---:|---|---:|---|
| img-32, free end of the 99 block | accepted | 1 | 19 | 19 (19, 24) | 0 | - |
| warehouse image-4, same 19 stack (top clipped in the photo) | accepted | 1 | 19 | 19 (19, 19) | 0 | - |
| img-46, single stack (391 px crop) | withheld (flag) | 1 | 20 | 19 (17, 18) | -1 | span/walk disagree |
| img-47, single stack | accepted | 1 | 7 | 7 (7, 7) | 0 | - |
| user-100 face in img-44 | withheld (gate: too far) | 1 | 20 | 16 (16, 15) | -4 | steep perspective; recessed |
| | | 2 | 20 | 26 (16, 16) | +6 | span/walk disagree |
| | | 3 | 20 + 1 empty | 24 (16, 15) | +4 (+3 vs 21 trays) | span/walk disagree |
| | | 4 | 20 | 15 (16, 15) | -5 | **none** |
| | | 5 | 20 | 14 (14, 14) | -6 | **none** |

- Equal to the user value: 3 of 9 observations. Within 1: 4 of 9. All 3 accepted observations are equal.
- **The 3 accepted observations are 2 physical stacks** (M, `per_stack_summary`). img-32 and warehouse image-4
  both show the 99 block's free-end stack (S99-end), and both photos were in the 9 Oct walk-counter development
  (section 5). The only accepted per-stack observation outside every tuning set is img-47 (7 trays).
- User-100 columns are the img-44 columns whose centre lies inside the crop
  `reports/user-100-tray-case-20260915/scene-annotated.jpg`. The crop was located by SIFT + RANSAC similarity:
  1,089 of 1,212 matches inliers, x 12.8-562.4. Exactly 5 columns fall inside, numbered left to right.
- img-44's boxes (99) come from the 7 Oct run. The photo's own label (185) is not usable at image level.
- Warehouse image-4 boxes come from `scan-99block-walk2.json` (staging, 9 Oct) and are identical to the
  23 Sep production boxes (M).

## 7. Multi-view trios (workflow and rejection tests only, no accuracy)

The saved responses' boxes were run through the 0.4.11 logic (Python, equal to the 318eb04 Worker build). They
were also run through the pre-0.4.11 Worker build `1e8591e`. That build reproduces all four saved f5776f0d
responses of the 13 Oct scans exactly (summary and cells, M), so it stands for the Worker behind app
0.4.9/0.4.10. App 0.4.10 shows the verified icon whenever the block has a total (D: PROGRESS 2026-10-12).

| trio | genuine? | saved response (version) | pre-0.4.11 logic (1e8591e) | 0.4.11 logic (318eb04) | live 47cb2378 = recomputed? |
|---|---|---|---|---|---|
| 99-block, laptop originals | no: LEFT and RIGHT are the same free end | `scan-99block-a` (9 Oct 08:22, span era): withheld, corner 21 vs 19 | 99, fully observed, no conflict | **estimated 99**: corner (0,0) STRAIGHT 20 vs LEFT 19 | - |
| | | `scan-99block-walk` (9 Oct 11:30): withheld, RIGHT read 23 | 99, fully observed | estimated 99 | - |
| | | `scan-99block-walk2` (9 Oct 11:34): 99, no conflict | 99 (reproduces saved) | estimated 99 | - |
| 99-block, phone scan 6fe33b1d | no | live 47cb2378: estimated 99 | 99, fully observed | estimated 99 | yes |
| mechanics (img-19 / img-30 / img-02) | no: three different blocks | `scan-img19-30-02` (8 Oct, a012c14e): 400 = 220 + 180 | 399 = 219 + 180, no conflict | **estimated 399** (180 computed; corner 20 vs 19) | - |
| | | `scan-mech-walk` (9 Oct): 399 | 399 (reproduces saved) | estimated 399 | - |
| 30aca6a1 | no: unrelated views | f5776f0d: withheld, gate refused all 3 | withheld (reproduces) | needs_view; first retake RIGHT (too far) | yes |
| ef823816 | no: LEFT = RIGHT face | f5776f0d: withheld, gate refused LEFT and STRAIGHT | withheld (reproduces) | needs_view; 11 conflicts | yes |
| f81c04d7 | no: label photos | f5776f0d: withheld, RIGHT too narrow | withheld (reproduces) | needs_view; depth 2 vs 3 | yes |
| 9b4c783e | plausible genuine; **no count** | f5776f0d: 165 (105 + 60) | 165, no conflict | **estimated 165**: 60 computed, corner 15 vs 16 | yes |

- **Exact results:** none of the 6 trios (14 replays) gives `exact` on 0.4.11 (M). The expected rejection holds
  in that narrow sense.
- **Totals still shown:** 2 of the 5 non-genuine trios still display a total, marked `estimated`: 99 and 399.
  The 0.4.11 change turned their status from "total, no conflict" (verified icon in app 0.4.10) into
  `estimated`. It did not reject them.
- **Why the 99-block trio is not exact:** it is 1 wide and 1 deep, so nothing is computed. From the code (I), it
  is `estimated` only because of the one-layer corner difference. Had the substituted side read 20, 0.4.11
  would return `exact` 99 for a fake trio. Neither version can tell that two faces come from different blocks
  when their layer counts agree within one.
- **Not replayed** (no saved block-model response): the warehouse pairs, production-20260918 and the 13 Sep
  manual-reference trio.

## 8. The two unidentified R2 scans

**Not done.** The Cloudflare OAuth token in the wrangler config expired 2026-10-14T16:52:14Z. The first
read-only API call (accounts list) returned HTTP 403, and the token was not refreshed (M). What is known from
the 14 Oct key listing (no content):

| scan | received (UTC) | photos |
|---|---|---|
| 014ee9a6-844b-4c42-94a6-7419cb6460b2 | 2026-09-24 09:08 | left 2,384,804 B, right 2,245,705 B, straight 2,470,476 B (camera-size) |
| 2b75577c-9bd0-454c-b746-c30a991a44bc | 2026-10-09 10:29 | left 489,964 B, right 693,672 B, straight 456,341 B |

A search by exact byte size of Downloads, Pictures, Desktop and Documents ran for 10 minutes and timed out
without a match. It is therefore incomplete. Next step: the user runs `npx wrangler login`. Then fetch each
key under `scans/<scan>/<view>/<sha256>` with
`npx wrangler r2 object get egg-tray-scan-archive/<key> --remote --file <scratch>/r2-unknown/...` into a
scratch folder, not the repo, and compare with the labelled photos. Until then, whether either scan holds an
un-inked original of a labelled photo is unknown.

## 9. Limitations

- **Small n.** The leak-free stratum has 6 clusters on 5 blocks, and the one untouched by detector and logic
  has 2. Rates there are anecdotes. At block level the headline is 19 blocks: 8 accepted, 7 correct.
- **Development-set numbers.** The capture gate and the walk counter were tuned on these photos. img-32 and
  warehouse image-4 were used while the walk counter was being changed, and img-46 while the 0.4.8 capture gate
  was being changed. The walk counter's 53 reference values were fitted to these labels: every resolved photo
  sums exactly to its label, and all 13 references that differ from the span are 20. 9 of the 10 accepted
  clusters are in-sample; only img-47 is not. The detector saw clean copies of 18 of the 24 labels in some
  training export, and the frozen v2 membership is unknown.
- **Selection by label scope.** 28 of 52 labels were excluded as not usable, partly by reasoning from the
  written value. The gate accepts 2 of them (img-25, img-26) with totals that do not match the written number.
- **Single-face proxy.** Cross-face rules and interior computation are not scored for accuracy. No genuine
  counted trio exists.
- **Labels:** user-written, not recounted. The scope is the assistant's reading. Whether empty cover trays count
  is unknown. The tier B scopes and the per-stack user reports are unconfirmed.
- **Inputs:** WhatsApp re-encodes with ink, 0.2-1.9 MP. The app uploads 1600 px camera photos. Box sets were
  reproduced on staging up to 9 Oct; drift after that is not measured, though Roboflow lists no training after
  August.

## Reproduce

From the repository root in Git Bash. Python needs numpy (the codex runtime has it, or set
`PYTHONPATH=work/vision-deps`). The JS checks need node and `cloudflare-worker/node_modules/typescript`.

```bash
PY=C:/Users/DELL/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
T=$(mktemp -d)
for c in 318eb04 1e8591e; do
  git show $c:cloudflare-worker/src/index.ts > $T/index-$c.ts
  node -e "const ts=require('./cloudflare-worker/node_modules/typescript');const fs=require('fs');const [i,o]=process.argv.slice(1);fs.writeFileSync(o,ts.transpileModule(fs.readFileSync(i,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)" $T/index-$c.ts $T/index-$c.mjs
done
$PY scripts/evaluate_labelled.py --out $T/eval --js-parity $T/index-318eb04.mjs --js-old-worker $T/index-1e8591e.mjs
$PY -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_evaluate_labelled.py scripts/tests/test_label_perturbation.py
```

`--out` defaults to this folder; pass a scratch folder to reproduce without overwriting the report. Without the
two JS flags the script is pure Python and writes the same results minus `js_parity` and `old_worker`. Two runs
gave byte-identical `results.json` and `results.csv` (M, rerun after the second revision: SHA-256
`9588bbf9…75f75e6` and `41ce7ebc…dbae632`). JS parity: 38 cases, 0 mismatches.

Tests:
- `test_evaluate_labelled.py`, 12 passed: synthetic scoring arithmetic, the gate, duplicate and gap handling,
  and no label parameter.
- `test_label_perturbation.py`, 3 passed. It changes every label value, per-stack truth value and walk
  reference value (`per_stack_counts.csv`), then reruns this script, `experiment_stack_faces.py` and
  `experiment_walk_fill.py` on the repo data. It asserts that every prediction is byte-identical, that the
  walk-fill stage-1 output and its chosen variant do not move, and that the scores change.
- A deliberate label leak injected into any of the three scripts makes the perturbation test fail (M,
  mutation check). For the walk-fill script two leaks were tried in the second revision: a reference value
  read into stage 1, and a choice that depends on the manifest labels.

## Files

- `eval_manifest.json` holds:
  - labels, tiers, scope text, clusters, groups, leak and tuning membership;
  - walk-development tags (`walk_development_source`), the capture-gate development tag
    (`orientation_development_source`, `in_orientation_development_photos`: img-46) and the label-citing walk
    reference rows (`walk_reference_rows_citing_label`);
  - per-stack truth, the trio list, and the 28 not-usable labels (`not_usable`).

  It was built from the audit inventory, and the label values are checked against `labels.csv`.
- `results.json` holds:
  - settings checks, duplicates and reproducibility;
  - summaries by cluster, label and block, each with the strata `all`, `tier`, `leak`, `size`, `logic_dev`
    and `detector_and_logic`;
  - per-photo rows with per-column detail, and the not-usable secondary rows;
  - per stack, multi-view (saved, pre-0.4.11, 0.4.11, live match) and parity.
- `results.csv`: one row per label.
- `staging47-replay/*.json`: the five live staging `47cb2378` responses of 14 Oct (Worker responses with boxes;
  no photos), copied from the session scratchpad so the multi-view section is reproducible.
- `scripts/evaluate_labelled.py`, `scripts/tests/test_evaluate_labelled.py`,
  `scripts/tests/test_label_perturbation.py`.
