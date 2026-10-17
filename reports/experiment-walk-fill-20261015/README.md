# Walk-overfill experiment: is the walk's gap filling, not the detector, behind the inconsistent layer counts? (15 October 2026)

Experiment session, 2026-10-15 (Claude Code subagent). Offline on saved detections only. No inference, no
network, no deployment, no phone, no commit. New files only: `scripts/experiment_walk_fill.py`,
`scripts/tests/test_experiment_walk_fill.py`, this README and `results.json`. `backend/` is not modified:
the deployed `layer_span.py` and `block_model.py` stay as they are in 0.4.12.

**M** = measured here. **I** = inference. **D** = taken from a repo document or an earlier report.

**Revised the same day after a second verification.** Stage 2's "not used in tuning" row now follows the eval
manifest's tags instead of a hard-coded img-32 exception: the gate tuning set, the walk reference photos, the
walk-development photos (img-01, img-32) and the new capture-gate development tag on img-46
(`evaluate_labelled.used_in_logic_tuning`). `results.json` was regenerated. Compared key by key (M), only
`stage_2_label_based.clusters_22.<V0-V4>.clusters_not_used_in_tuning` changed (n 6 → 5, plus withheld, the
error sum and mae; for V3 also accepted 2 → 1 and wrong 1 → 0). Stage 1, the choice and every other number are
unchanged. `scripts/tests/test_label_perturbation.py` now covers this script (section 7).

## In brief

- **The deployed walk has a mechanical overfill bug (M).** After it fills one gap, it feeds the filled
  sub-gaps (gap/steps) back into its local pitch. The pitch then falls to its 0.6 floor, and from there every
  ordinary gap of 0.9 pitch or more is counted as 2 layers. Example: img-04 `f` has 17 boxes, its span is 19
  and the walk reads 27. This is the verifier's "12 polygons, 74 of 92 fills" (reproduced, M).
- **The variant was chosen without labels, by a rule fixed in code before any label score existed.**
  - Chosen: **V4, "observed pitch"**. The local pitch follows only gaps the walk read as one layer.
  - Excluded: V1 (cap) and V2 (span fallback). Their count is built from span, so the deployed "span/walk
    disagree" flag could never fire.
  - Excluded: V3 (strict fill). It broke the clean reference columns: within-photo pairs that differ by more
    than 1 went from 0 to 3, and 4 of the 53 columns changed.
- **Label-free effect of V4 (M).**
  - Equal-extent pairs that differ by more than 1 layer: 15 → 11 of 29. In physical terms, 13 → 11 of
    25 pairs.
  - Sum of the pair differences: 97 → 47.
  - Filled layers: 92 → 58.
  - Unchanged: 0 of 53 reference columns, 0 of 19 accepted photo totals and every block status.
- **Walk overfill is part of the inconsistency, not all of it (M).**
  - Even with the overfill removed (V1, V2, V4), 10-11 of the 18 small-scale pairs still differ by more
    than 1, against 15 under V0. All of them are in far photos, where a layer is less than 3% of the frame
    height. Only V3 gets lower (2), and it does so by refusing legitimate fills.
  - On one face photographed twice (ef823816 LEFT and RIGHT), 3-4 of 4 stacks still differ by more than 1
    under every variant. The box counts of the two photos differ: for example, 15 against 22 boxes on stack
    (4,1).
- **The walk change barely moves what users see (M).** Of 66 photos under the deployed gate and flags:
  - V4 newly accepts 1 and withholds 0. The one it accepts is img-45, 25 trays from a column that merges a
    front stack with 2 narrower boxes behind it (I, visual). Arm C reads that column as 20 under V0 and V4
    alike.
  - V1 and V2 newly accept 0 and withhold 0.
  - V3 newly accepts 1 and changes 3 accepted totals.
- **The label check is secondary and leaves the choice unchanged.**
  - On the 22 clusters, V4 keeps accepted 10, correct 9, wrong 1. Total absolute error rises from 431 to
    451; the whole increase is on withheld photos, where removing overfill exposes missing rows.
  - On the user-reported per-stack values (9 observations, 8 stacks), absolute error falls from 26 to 22.
    The user-100 stacks read 16/26/24/15/14 under V0 and 16/16/18/15/14 under V4, against 20 each.
  - The 53 references stay 51 exact.
- **Recommendation:**
  - Trial V4 in shadow mode on the next physically counted field scans: compute it and log it, but do not
    show it. It is not in 0.4.12.
  - Pair it with C's depth split, or a guard against merged columns, before it can change acceptance.
  - Do not use V1, V2 or V3.
- **For "detector retraining first":**
  - The walk overfill inflated the experiment's consistency evidence: it disagreed in 15 of 18 small-scale
    pairs, against 11 with V4.
  - With the overfill removed, the remaining errors on far faces are undercounts with missing boxes (I).
  - So detector recall, or closer capture, stays the lever for withheld far faces, now on corrected
    evidence. A walk fix does not move accepted results in this data.

## 1. Inputs and variants

Inputs (read only):
- `reports/experiment-stack-faces-20261015/annotations.json`: 20 photos, 74 target polygons. The 62
  polygons with 3+ boxes are 46 physical stack keys; unkeyed polygons count as their own stack.
- The saved `projec-mutta/2` boxes named there and in `reports/field-labelled-20261007/raw/batch-*.json`.
- `reports/field-scans-20261013/replay/*.json`, warehouse image-4 (`scan-99block-walk2.json` LEFT) and the
  dataset manifest. These give image sizes only.
- `reports/field-labelled-20261007/per_stack_counts.csv`. Stage 1 reads only the image and column of the 53
  resolved rows.
- Labels: in stage 2 only.

Variants. Each keeps the deployed column grouping, the 0.65-pitch duplicate rule and
`MAX_FILLED_PER_GAP = 2`:

| | Rule | Where it comes from |
|---|---|---|
| V0 | deployed `layer_span.walk_layers` | as is |
| V1 | V0 clipped to [span − 1, span + 1] | task |
| V2 | span when \|V0 − span\| > 1, else V0 | task |
| V3 | fill only when \|gap/pitch − steps\| ≤ 0.25 and the local pitch is within 15% of the global pitch; otherwise the gap counts as one step | task (thresholds given; the unfilled gap enters the pitch history as in V0) |
| V4 | local pitch = clamped median of the last 3 gaps read as **one** layer; filled sub-gaps no longer feed it | defined here from the walk's arithmetic (section 2), before any variant was scored |

Each variant is applied by swapping the walk function that `count_layers_by_span` and
`stack_separation.column_record` call (`use_walk`).
- Grouping, capture gate, block-model flags and `build_block` are the deployed code.
- With its defaults, the generic `walk()` equals `layer_span.walk_layers` on 3,000 random columns and on all
  74 polygons (M). A test keeps the 500-column check.

## 2. Why V4: the pitch ratchet (M, label-free)

The deployed walk's trace on img-04 `f` (gaps in units of the global pitch):

- A gap of 1.49 at local pitch 0.96 is split into 2 layers.
- The history now holds 0.75, 0.75, so the local pitch falls to 0.75, then to 0.62 and to the 0.6 floor.
- From then on, gaps of 0.98, 0.96 and 1.02 each count as 2 layers.

Result: 27 layers from 17 boxes, against a span of 19. ef823816 LEFT `l3` does the same: 15 boxes, span 16,
walk 27. From the fourth gap on, every gap except the last counts as 2 or 3 layers.

Physically, a stack's spacing cannot halve partway down. The deployed gate already flags columns whose
top-to-base spacing ratio exceeds 1.5. V4 removes the feedback and changes nothing else.

**V4 does not fix the opposite drift** (M, synthetic test):
- after several wide gaps the local pitch rises, and later boxes are dropped as duplicates;
- img-04 `f` reads 16 under V4 from 17 boxes.

## 3. Stage 1: label-free criteria (decides the variant)

### 3.0 The overfill decomposition (V0, reproduces the verifier)

Over the 62 polygons with 3+ boxes:
- 92 layers are filled;
- 12 polygons read walk > span + 1 and hold 74 of the 92 fills;
- 10 of those have regular boxes (box/pitch ≥ 0.75) and hold 60 fills;
- 4 polygons read span > walk + 1.

Per polygon. Columns V0 to V4 give the count with its filled layers in brackets:

| Photo, polygon | Boxes | Box/pitch | Span | V0 | V1 | V2 | V3 | V4 |
|---|---|---|---|---|---|---|---|---|
| img-04 `a` | 18 | 1.00 | 17 | 19 (3) | 18 (2) | 17 (1) | 17 (1) | 19 (3) |
| img-04 `b` | 18 | 1.01 | 18 | 15 (1) | 17 (3) | 18 (4) | 14 (0) | 15 (1) |
| img-04 `f` | 17 | 0.94 | 19 | **27 (11)** | 20 (4) | 19 (3) | 15 (1) | 16 (2) |
| img-09 `f_front` | 10 | 1.42 | 12 | 14 (4) | 13 (3) | 12 (2) | 11 (1) | 14 (4) |
| img-09 `l` | 18 | 1.05 | 18 | 21 (4) | 19 (2) | 18 (1) | 17 (0) | 21 (4) |
| img-09 `r1` | 17 | 1.23 | 17 | 20 (4) | 18 (2) | 17 (1) | 16 (0) | 20 (4) |
| img-09 `r2` | 14 | 1.01 | 15 | 20 (6) | 16 (2) | 15 (1) | 15 (1) | 20 (6) |
| ef823816 S `s2` | 13 | 0.80 | 14 | 19 (6) | 15 (2) | 14 (1) | 11 (0) | 18 (5) |
| ef823816 S `s3` | 12 | 0.67 | 11 | 18 (7) | 12 (1) | 11 (0) | 11 (0) | 14 (3) |
| ef823816 L `l_short` | 12 | 0.87 | 12 | 9 (0) | 11 (2) | 12 (3) | 9 (0) | 9 (0) |
| ef823816 L `l2` | 15 | 0.77 | 14 | **22 (7)** | 15 (0) | 14 (0) | 14 (2) | 15 (3) |
| ef823816 L `l3` | 15 | 0.91 | 16 | **27 (12)** | 17 (2) | 16 (1) | 14 (0) | 16 (2) |
| ef823816 L `l4` | 17 | 0.98 | 18 | 15 (1) | 17 (3) | 18 (4) | 14 (0) | 15 (1) |
| MUTAA-07 `F3` | 11 | 0.71 | 10 | **17 (7)** | 11 (1) | 10 (0) | 10 (0) | 11 (1) |
| MUTAA-07 `F4` | 11 | 0.76 | 11 | 9 (0) | 10 (1) | 11 (2) | 9 (0) | 9 (0) |
| img-46 `s1` | 18 | 1.03 | 17 | 19 (3) | 18 (2) | 17 (1) | 17 (1) | 19 (3) |

- **V4 changes 6 of the 62 polygons.** These are the ratchet cases: img-04 `f`, ef823816 S `s2`/`s3`,
  ef823816 L `l2`/`l3` and MUTAA `F3`.
- **8 polygons stay above span + 1 under V4:** img-04 `a`, the four img-09 polygons, ef823816 S `s2`/`s3`
  and img-46.
  - Their single gaps of about 1.25-1.8 global pitches sit next to observed one-layer gaps of about
    0.65-0.9, and V4 still reads each as 2 layers.
  - Without a count, nothing label-free tells a missed row from a perspective jump or a depth change
    there (I).

### 3.1 The criteria per variant (M)

(a) Equal-extent pairs use the experiment's own definition (`experiment_stack_faces.equal_extent_pairs`):
- 29 pairs in 9 photos, which are 7 distinct faces and 25 physical pairs (30aca6a1 S repeats the 9b4c783e S
  face, and ef823816 L repeats R);
- large scale (layer ≥ 3% of the frame height): 11 pairs, 3 faces, 10 physical pairs;
- small scale: 18 pairs in 5 photos, which are 4 faces, 15 physical pairs and 3 blocks (ef823816,
  MUTAA-07, img-04).

(b) Walk-span uses the 62 polygons.

(c) Cross-view uses the base-visible target polygons of 9b4c783e S/L/R, 30aca6a1 S and ef823816 S/R:
5 physical stacks in 2 blocks.

(d) Reference consistency uses the 53 reference columns. That is 10 photos and 67 within-photo pairs of
equal extent; the reference values are not read.

| Criterion | V0 | V1 cap | V2 fallback | V3 strict | **V4 observed pitch** |
|---|---|---|---|---|---|
| (a) pairs differing > 1 / 29 | 15 | 10 | 10 | 2 | **11** |
| (a) physical pairs differing > 1 / 25 | 13 | 8 | 8 | 2 | **11** |
| (a) sum of \|difference\| | 97 | 32 | 31 | 18 | **47** |
| (a) large-scale pairs differing > 1 / 11 | 0 | 0 | 0 | 0 | 0 |
| (a) small-scale pairs differing > 1 / 18 | 15 | 10 | 10 | 2 | **11** |
| (b) polygons count > span + 1 / 62 | 12 | 0 * | 0 * | 0 | **8** |
| (b) polygons count < span − 1 / 62 | 4 | 0 * | 0 * | 9 | **5** |
| (b) filled layers (total layers) | 92 (907) | 48 (863) | 41 (855) | 10 (814) | **58 (867)** |
| (c) stacks with spread > 1 / 5 (sum of spreads) | 1 (8) | 1 (8) | 1 (8) | 1 (8) | 1 (8) |
| (d) reference columns changed vs V0 / 53 | 0 | 0 | 0 | 4 | **0** |
| (d) reference pairs differing > 0 / > 1, of 67 | 1 / 0 | 1 / 0 | 1 / 0 | 13 / 3 | **1 / 0** |

\* By construction: V1 and V2 force the count within 1 of span, so (b) cannot judge them.

Notes:
- **(c) had no power here.**
  - The only stack with spread > 1 is ef823816 (4,0): STRAIGHT 8 against RIGHT 14, from 9 against 14 boxes.
    That is a box-count difference, the same under every variant.
  - None of the ratchet polygons is seen base-visible in a second allowed view.
- **Supplement: ef823816 LEFT vs RIGHT** (the same face photographed twice; outside the criterion as the
  task asked).
  - Stacks with spread > 1, of 4 (sum of spreads): V0 3 (18), V1 4 (13), V2 3 (13), V3 4 (19), V4 4 (18).
  - V4 fixes (4,2): 27 against 19 becomes 16 against 19.
  - It breaks (4,1): 22 against 21 becomes 15 against 21. LEFT `l2` has 15 boxes and RIGHT `r2` 22. V0's
    overfill there happened to land near the other photo.
- **Supplement: G01 (4,0)** (img-01, img-32, warehouse-4, walk-development photos): 19/19/19 under every
  variant.
- **Reference columns under V3:** img-01 col 2, img-08 cols 4 and 5 and img-23 col 4 drop from 20 to 19
  or 18. V3 refuses legitimate one-layer fills when the local pitch has drifted more than 15%.

### 3.2 The choice rule (fixed in code before the first run; `choose_variant`)

Eligibility, label-free:
- G1: the count must not use span. This rules out V1 and V2, which would make the deployed
  "span/walk disagree" flag impossible.
- G2: no more cross-view stacks with spread > 1 than V0.
- G3: no more reference equal-extent pairs differing by more than 1 than V0.

Ranking of the eligible variants:
1. (a) pairs differing by more than 1;
2. then the (a) sum of |difference|;
3. then reference columns changed.

A walk change is recommended for a trial only if the winner is not V0.

Result (M):
- eligible: V0 and V4;
- V3 fails G3 (3 pairs against 0);
- V4 ranks first, with key (11, 47, 0) against V0's (15, 97, 0).

**Chosen: V4.**
- The stage-1 output was written and hashed at 19:48 IST (scratch, SHA-256 `b8e037a4…`) before the stage-2
  code existed.
- The final `results.json` has the same choice and the same criteria; only descriptive keys were added.
- A perturbation run changed every label value: manifest labels +7, per-stack values +3, labels.csv +11,
  reference values +5. The stage-1 output stayed byte-identical (M).
- That check is now a test (second revision): `scripts/tests/test_label_perturbation.py` changes every manifest
  label, per-stack value, labels.csv value and reference value (`per_stack_counts.csv` `label_total` and
  `assistant_count`), reruns this script and asserts that the stage-1 output is byte-identical, the choice is
  unchanged and every stage-2 section changes. Mutation check (M): a reference value read into stage 1, or a
  choice that depends on the manifest labels, makes it fail.

### 3.3 What the variants do under the deployed gate and flags (66 photos, M)

The photos:
- the 52 labelled WhatsApp photos: the 24 usable ones, which form 22 clusters and 19 blocks, plus the 28 the
  audit marks not usable;
- warehouse image-4, the same stack as img-32;
- the 12 field-scan views of 13 Oct: f81c04d7 re-uses img-50 and img-41, 30aca6a1 S is 9b4c783e's front
  from far, and ef823816 L repeats R;
- MUTAA image-07.

V0 accepts 19 of them.

| | Newly accepted | Newly withheld | Accepted photos whose total changes | Withheld photos whose total changes |
|---|---|---|---|---|
| V1, flag on the variant | 0 | 0 | 0 | 24 |
| V2, flag on the variant | 0 | 0 | 0 | 24 |
| V1 or V2, flag kept on the deployed walk | 0 | 0 | 0 | 24 (internal numbers only) |
| V3 | 1 (img-46: 17) | 0 | 3 (img-01 99 → 98; img-08 and img-23 160 → 158) | 28 |
| **V4** | **1 (img-45: 25)** | **0** | **0** | **17** |

- **Why V1 and V2 accept nothing new here.** Every photo whose span/walk flag they clear is still withheld by
  the gate, or by a flag the disagreement flag was masking. Usually that is "camera looked down", because
  the flags are checked in order.
- **The photo V4 newly accepts, img-45.**
  - It is one 21-box column. V0 read 28 and raised the unresolved-gap flag: after its pitch ratcheted down,
    the top gap of 3.36 pitches counted as more than 2 missing layers.
  - V4 reads 25, with 7 filled layers.
  - The column includes 2 narrower boxes on trays behind and above the front stack (I, visual check of
    `img-45.jpeg` with the boxes drawn).
  - Arm C (`stack_separation`) drops those 2 boxes as a background group and reads the front stack as 20
    under both V0 and V4 (M).
  - So the deployed flag was right for the wrong reason, and V4 removes that accidental protection.
- **Block results** (the 6 saved multi-view replays): every variant keeps every status. 99-block 99
  estimated, mechanics 399 estimated, 9b4c783e 165 estimated; 30aca6a1, ef823816 and f81c04d7 need a view.
  The one exception is V3, which turns the 99-block into 98.

## 4. Stage 2: label-based check (secondary, after the choice)

Labels are user-written or user-reported, not physical recounts.
- Tier B scopes are the audit's reading.
- "Not used in logic tuning" follows the eval manifest's tags (revised): the gate tuning set, the walk reference
  photos, the walk-development photos (img-01, img-32) and the capture-gate development photo img-46. It leaves
  5 clusters: img-35, 39, 40, 47 and 49.

**22 labelled clusters.** Each row gives n, exact (ungated), accepted, accepted correct, accepted wrong and
the sum of absolute errors:

| | V0 | V1 | V2 | V3 | **V4** |
|---|---|---|---|---|---|
| All clusters (22) | 9 / 10 / 9 / 1 / 431 | 9 / 10 / 9 / 1 / 442 | 9 / 10 / 9 / 1 / 450 | 7 / 11 / 7 / 4 / 481 | **9 / 10 / 9 / 1 / 451** |
| Leak-free clusters (6) | 1 / 2 / 1 / 1 / 25 | 1 / 2 / 1 / 1 / 39 | 1 / 2 / 1 / 1 / 45 | 1 / 3 / 1 / 2 / 50 | **1 / 2 / 1 / 1 / 34** |
| Leaked clusters (16) | 8 / 8 / 8 / 0 / 406 | 8 / 8 / 8 / 0 / 403 | 8 / 8 / 8 / 0 / 405 | 6 / 8 / 6 / 2 / 431 | **8 / 8 / 8 / 0 / 417** |
| Not used in logic tuning (5; img-32 and img-46 moved out) | 1 / 1 / 1 / 0 / 13 | 1 / 1 / 1 / 0 / 13 | 1 / 1 / 1 / 0 / 13 | 1 / 1 / 1 / 0 / 13 | **1 / 1 / 1 / 0 / 13** |
| Blocks (19, lowest id per block) | 7 / 8 / 7 / 1 / 414 | 7 / 8 / 7 / 1 / 411 | 7 / 8 / 7 / 1 / 415 | 5 / 9 / 5 / 4 / 444 | **7 / 8 / 7 / 1 / 424** |
| Leak-free blocks (5) | 1 / 2 / 1 / 1 / 8 | 1 / 2 / 1 / 1 / 8 | 1 / 2 / 1 / 1 / 10 | 1 / 3 / 1 / 2 / 13 | **1 / 2 / 1 / 1 / 7** |

V0 reproduces the eval: 10 accepted, 9 correct, 1 wrong, MAE 19.59.

V4 changes 4 clusters, all of them withheld under both versions:

| Cluster | Label | V0 | V4 |
|---|---|---|---|
| img-04 | 115 | 120 | 109 |
| img-31 (leak-free) | 80 | 63 | 53 |
| img-38 | 118 | 102 | 92 |
| img-50 (leak-free) | 40 | 44 | 37 |

**9 polygon photos** (A = deployed grouping, B = polygons):
- img-01, img-32 and warehouse-4 are all block G01;
- img-32 and warehouse-4 are one stack and both are walk-development photos;
- the 9 photos are 7 blocks.

| Photo | Label | Leak | V0 A / B | V1 | V2 | V3 | V4 |
|---|---|---|---|---|---|---|---|
| img-01 | 99 | leaked | 99 acc / 99 | same | same | 98 acc / 98 | 99 acc / 99 |
| img-32 | 19 | leaked (walk dev) | 19 acc / 19 | same | same | same | same |
| warehouse-4 | 19 | not in manifest (walk dev) | 19 acc / 19 | same | same | same | same |
| img-04 | 115 (B) | leaked | 120 / 119 | 114 / 113 | 113 / 112 | 98 / 98 | 109 / 108 |
| img-09 | 75 (B, low) | leaked | 85 / 85 | 77 / 76 | 74 / 72 | 69 / 69 | 85 / 85 |
| img-35 | 1 | leaked | 0 / 1 | same | same | same | same |
| img-39 | 2 | leaked | 3 / 3 | same | same | same | same |
| img-47 | 7 | leak-free | 7 acc / 7 | same | same | same | same |
| img-46 | 20 (B) | leak-free | 19 / 19 | 18 / 18 | 17 / 17 | 17 acc / 17 | 19 / 19 |
| **A exact, sum of absolute errors** | | | **4, 18** | 4, 7 | 4, 8 | 3, 29 | **4, 19** |
| **B exact, sum of absolute errors** | | | **5, 16** | 5, 6 | 5, 10 | 4, 28 | **5, 19** |

- The span-bounded V1 and V2 come closest here, through img-04 and img-09. Both are tier B labels with an
  uncertain scope, and both photos are withheld under every variant.
- On the 22 clusters, V1 and V2 do worse than V0 (442 and 450 against 431).
- So the labels make no consistent case for V1 or V2 either.

**User-reported per-stack values** (9 observations of 8 physical stacks; user reports, not physical counts):

| | V0 | V1 | V2 | V3 | **V4** |
|---|---|---|---|---|---|
| Equal / within 1 | 3 / 4 | 3 / 3 | 3 / 3 | 3 / 3 | **3 / 4** |
| Sum of absolute errors | 26 | 23 | 26 | 35 | **22** |
| user-100 face, 5 stacks (20 each) | 16/26/24/15/14 | 16/17/17/15/14 | 16/16/16/15/14 | 11/14/14/15/14 | **16/16/18/15/14** |
| Accepted and equal | 3 | 3 | 3 | 3 (+ img-46 accepted at 17) | 3 |

The 3 accepted and equal observations are img-32 and warehouse-4, which are one walk-development stack, and
img-47.

**53 reference columns** against their reference values. 7 of the 53 values were inferred from the image
label; the CSV holds 8 such rows, and the 8th is an unresolved img-50 row.
- V0, V1, V2 and V4: 51 exact and 53 within 1. Without the 7 inferred rows, 45 of 46 are exact.
- V3: 47 exact and 52 within 1; 42 of 46 without the inferred rows.

**Labels the audit marks not usable**:
- V4 changes the outcome of img-45 only: accepted at 25. Its labels.csv value is 107. The audit says it is
  a "533 px-wide crop of an L arrangement; most stacks hidden or cropped". This is not a headline number.
- V3 changes no outcome among them.

## 5. Recommendation

**1. Trial V4, not deploy it (it is not in 0.4.12).**
- It is the only variant that passes the label-free rule.
- It removes a real mechanical fault, the pitch ratchet, and halves the equal-extent disagreement (97 → 47).
- It changes nothing on the reference columns or on any accepted total in this data.

The trial:
- Run V4 in shadow next to V0 on the next physically counted field scans. Log both counts and both flags
  per column.
- Do not let V4 change acceptance until a merged-column guard is in place: C's depth split or a check on
  the share of filled layers. Its only new acceptance here, img-45, is a merged front/rear column.
- Score it on physical counts, with blocks held out.
- V4's upward drift (img-04 `f`: 17 boxes read 16) is known and untested. Do not tune it further on these
  photos.

**2. Do not use V1, V2 or V3.**
- V1 and V2 change no outcome in the 66 photos. Their only lasting effect would be to disable the
  span/walk disagreement check, the one check that catches this fault.
- V3 makes counting consistent by refusing legitimate fills. In the labelled data it accepts 3 more wrong
  totals (img-01, img-08 and the newly accepted img-46) and drops the references from 51 to 47 exact.

**3. Detector retraining first?**
- **The evidence shrinks.** The experiment's label-free argument for missing detector rows ("15 of 18
  equal-extent pairs disagree in small-scale photos") was partly walk overfill. With V4, 11 of 18 remain;
  the sum of the differences falls from 97 to 47 (M).
- **What remains is far-face undercounting (M):**
  - all of it in the 5 far photos (layer < 3% of the frame);
  - the same face photographed twice still disagrees on 3-4 of 4 stacks under every variant, with different
    box counts per photo;
  - without the overfill, the user-100 stacks all read under 20 (14-18 from 14-16 boxes);
  - the totals of img-31 and img-38 move further below their labels.
- **That points at missing boxes on far faces (I).** The remedy is recall: retraining, or capture from
  closer.
- **Restated recommendation (I):**
  - Among the measurable levers, detector recall on far and cross-stacked faces, together with capture
    distance, is still first for the withheld far faces.
  - A walk change does not move accepted results in this data.
  - The V4 shadow trial and a retraining run can proceed in parallel, because they touch different code.
- Retraining is not shown by a measured improvement: no retrained model exists, and nothing here is a
  held-out physical count.

## 6. Limitations

- **Designer exposure.** The designer of V4 had read the stack-face README, which lists the label values of
  the 9 polygon photos, and the verifier notes, before designing V4.
  - V4 was derived from label-free gap traces (img-04 `f`, ef823816 LEFT `l3`).
  - It was frozen, and the choice rule written, before any variant was scored.
  - The label stage was coded after the stage-1 result had been saved.
- **Development data only.** The deployed walk and gate were tuned on most labelled photos, and the 53
  reference columns are walk-validation data.
- **Small n:**
  - 29 equal-extent pairs (25 physical) in 7 faces;
  - 5 cross-view stacks in 2 blocks;
  - 22 clusters in 19 blocks;
  - 9 per-stack observations of 8 stacks;
  - no physical count anywhere.
- **What the label-free criteria reward.** They reward agreement, not truth. V3 shows that a counter can
  agree by undercounting the same way everywhere.
- **Visual readings.** The img-45 merged-column reading and the polygons' physical-stack keys are Claude's
  visual inferences. The user has not reviewed them.

## 7. Reproduce and test

From the repository root, with `work/vision-deps` on `PYTHONPATH`:

```
python scripts/experiment_walk_fill.py --out <dir>          # default: this folder
python -m pytest -p no:faulthandler -p no:cacheprovider scripts/tests/test_experiment_walk_fill.py scripts/tests/test_label_perturbation.py
```

Measured on 2026-10-15:
- **Two runs** gave a byte-identical `results.json`, SHA-256 `3aa1b07c4032243c8ae45d0ff92a173b80ff8e2b23fcce6c5adbd48ebfb6f013`.
- **After the second revision**, two runs again gave a byte-identical `results.json`, SHA-256
  `77f4b6d0b65909ae25689540597c7968066a13dd592137ff8c11f85a2306d0ee`.
- **Tests:**
  - `test_experiment_walk_fill.py`: 12 passed (new);
  - with `test_experiment_stack_faces.py` and `test_evaluate_labelled.py`: 27 passed;
  - second revision, all of `scripts/tests`: 75 passed, including `test_label_perturbation.py` 3 passed.
- **ruff:** `ruff check` clean under the backend config (line length 110) and the default config;
  `ruff format --check` clean under the backend config (re-measured in the second revision).

`results.json` has two parts.

`stage_1_label_free`:
- `overfill_decomposition_V0`, `criteria.<variant>` (a-d with supplements);
- `equal_extent_pairs`, `polygon_counts`;
- `choice`;
- `outcomes` (`flag_on_variant`, `flag_kept_on_deployed_walk`), `block_results`.

`stage_2_label_based`:
- `clusters_22`, `polygon_photos_9`;
- `per_stack_user_reported`, `reference_columns_53`;
- `not_usable_outcome_changes`.
