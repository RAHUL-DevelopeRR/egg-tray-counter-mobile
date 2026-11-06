# Plan 5 (draft 3, 5 Nov 2026): count the outer ring, fill the inside by the stacking rule, check it with more photos

**Photos only show the outside of a block. On 5 Nov the user stated the farm's stacking rules: half-filled stacks stand only on the photographed faces, the back row is always full, and no inside position is ever empty. Plan 5 counts every face stack from the photos. It sets every hidden stack to the block's full height H by that rule, and the app says so plainly. Extra photos (a repeat of a face, a long face in parts, a close photo of one stack) measure the outer ring and H better. A scan stays 3 photos by default; a deep block also needs a CORNER photo and the typed block size, as in 0.6.0. The first step changes only the server and is tested offline, with no new photo and no paid detector call.**

- **Update, 5 Nov evening:** the user answered **Decision 1: yes**. Phase 1 is built offline as Worker 0.7.0
  (`docs/GRID_CONTRACT_0.7.0.md`; results in `reports/stacking-rule-0.7.0-20261105/README.md`, which also corrects three
  expectations below: S21 is withheld because its sides are copies, FR18's printed range misses the truth by 2, and
  §4.6's option (c) example missed RIGHT's 14). Decision 3 stays open; the build uses default (a).
- **Update, 6 Nov:** Phase 2 built locally as app 0.7.0+31 (not installed, not pushed); the research capture mode is not
  built. See `PROGRESS.md`.
- **Status:** draft 3, 2026-11-05, **not approved**: draft 1 corrected the same day after a code-accuracy review and a physics-and-honesty review; draft 3 adds the user's answer on cover trays (Decision 4: sometimes, §4.6). Nothing in it is built. Until it is approved, Plan 4 (draft 2, not approved), `docs/GRID_CONTRACT_0.6.0.md` and Worker 0.6.0 (merged locally, not deployed) stay as they are. Staging runs Worker 0.5.0 (`52a1d5e8`). No step of this plan touches production (`4c1480e6`).
- **Sources of this draft:** two drafts (one ordered by build steps, one by risks) and three read-only maps of the Worker, the app and the evidence, all made on 5 Nov, then two reviews checked against the code. §2.3 lists where it departs from the starting design. Draft 2 adds Decisions 17–19.
- **The farm rules are requirements, not measured facts.** No block has been opened to check them. **Physical counts so far: zero.**

## 1. What changes and why

| Fact | Evidence |
|---|---|
| Most trays in a block are hidden. W05 shows about 196 of about 1,366 trays; L-115 about 232 of about 734. W05 has 48 of 70 stacks hidden; about 52% of trays in the 8 kept MUTAA sets stand in hidden stacks. | [V] MvB; Plan 4 §1. The W05 source does not add up: "196 visible + 1,239 hidden" is 1,435, not 1,366. Its 196 is about the front alone (9 × 20 + 6 = 186 [math]); a three-face scan of 10 × 7 shows 22 of 70 stacks, about 430 trays at H 20 [math]. |
| Worker 0.6.0 sets a hidden stack to `floor(median)` of the face stacks in line with it, or the commonest face height when there are none. | [C] `index.ts:656-681` (670; fallback 673-674) |
| Under farm rule 1, half-filled stacks stand on the faces, and the 0.6.0 median takes face partials as neighbours, so it under-reads the hidden stacks behind them. Contract case H2: hidden (1,2) gets 19 from 19, 18 and 20; total 236 where the rule gives 237. | inference from rule 1 [U]; H2 [S] Contract §4; [C] `index.ts:665` |
| Close, square-on faces read well: 9 of 10 stacks exact, 1 within one. Far faces read about half (M16-NEAR −8 to −10 per stack). | [M vs V] MvB findings 1–2 |
| On accepted photos, columns with no doubt and no gap fill match double-counted manual counts on 20 of 21 stacks. | [M vs V] VAL |
| The photo check accepted 37 and refused 57 of 94 photos. Staging 0.5.0 gave `needs_view` on all 33 gallery scans. | [M] VAL |
| With 3 photos, only the two front-corner stacks (and every stack of a one-wide block) can be read by two photos. | [C] `index.ts:740-743, 798-801` |
| The upload takes exactly 3 faces plus at most 1 CORNER and 1 ELEVATED. A second photo of a face is dropped or refused. | [C] `index.ts:17, 241, 270-286` |
| AI visual counters are not a truth source: they disagreed on 21 of 29 double-counted accepted photos; L-115 was read 771 / 897 / 1,455. | [V] VAL; MvB |
| **Physical counts: zero.** | ctx; Plan 4 §1; EG |

**What changes:** (1) hidden stacks become H "by the stacking rule" instead of the neighbour median; (2) the upload accepts more photos per face, so more face stacks are read twice and H rests on better readings; (3) two farm days audit the rules and give the first physical counts.

**How numbers are labelled.** [P] physical count (none yet). [M] measured system output (staging, app, detector). [V] AI visual count of photos, not physical. [U] stated by the user, or a handwritten label. [R] offline replay (synthetic library, or saved detections with made-up headings, CORNER or declaration: *counterfactual*). [S] synthetic case, true by construction. [C] current code, read from source. [E] expected or proposed, not measured. [math] arithmetic only.

**Sources.** Plan 4 `docs/PLAN_4_EVIDENCE_GRID.md`; Contract `docs/GRID_CONTRACT_0.6.0.md`; PV `docs/PHYSICAL_VALIDATION.md`; ctx `context.md` (5 Nov entry); PROG `PROGRESS.md` (5 Nov entry: this plan; the farm rules are in ctx); VAL `reports/mutaa-validation-0.5.0-20261101/README.md`; MvB `reports/mutaa-manual-vs-backend-20261031/README.md`; AUD `reports/phone-audit-20261104/README.md`; EG `reports/evidence-grid-0.6.0-20261103/README.md` and `saved-scans/`; FS `reports/field-scans-20261013/README.md`. `index.ts:N` is `cloudflare-worker/src/index.ts` (Worker 0.6.0). App paths are under `mobile/lib/`; `test/` paths in app rows are `mobile/test/`. Line numbers come from the 5 Nov maps; re-check them before editing.

## 2. What the user decided, and the defaults this plan assumes

### 2.1 The farm rules (stated by the user, 5 Nov) [U]

| Rule | What the server may do | What stays unknown |
|---|---|---|
| 1. Partial stacks are placed only on the photographed faces (STRAIGHT, LEFT, RIGHT). Workers are strictly told never to put them inside. The back row is always full. | Every hidden stack, including the hidden middle of the back row, is H. The two back corners are seen by the side photos and must read H: a free self-check. | Whether workers always follow it. Whether a wall side counts as a "face" (rule 4 covers only the back). Where partials stand: MvB describes short stacks beside or in front of a block ("6x3 + 2", "4x2 + 1 short", "6x6 + a short stack of 14 in front") [V], outside the X × Y grid (Decision 18). |
| 2. No interior position is ever empty. | A hidden stack is never 0 unless the operator reports an exception. | A hidden hole cannot be seen (S29: 180 released for 160 [S]). |
| 3. Full height varies per block; the tallest normal face stacks show it. | H is read from the block's own faces. | FS saw an empty cover tray on most full stacks [V]; whether every full stack has one, inside too, is unknown. AUD read covers inconsistently (10, 10, 11 for 10 + 1 each [M vs V]). Decision 4. |
| 4. The back is usually against a wall; a BACK photo is rarely possible. | No BACK photo by default. | How often a side is also against a wall (ef823816 had its left side and back against walls [V, FS]). |
| 5. Photos from above or below are impractical. | ELEVATED stays optional and is never suggested. | Interior holes go unseen (§9, R1). |

**Earlier decisions still in force:** deep-block totals are never `confirmed` (Decision 2(a), 3 Nov); the unit is tray layers, cover trays included, never eggs or rupees (Contract; ctx). **The user chose 3D reconstruction of the hidden trays from the three photos as the core use case.** Here that means the existing block grid: cells with heights, "not a point cloud or a measured mesh" (`index.ts:1765`).

### 2.2 Defaults this plan assumes (each is one named switch, like `DEPTH_PROOF` at `index.ts:935-941`)

| Switch | Default | Alternative | Decision |
|---|---|---|---|
| Hidden stacks | H by the stacking rule; replaces the 3 Nov default "neighbours' face height" (Contract lines 22–24) | keep 0.6.0 | 1 |
| `RULE_MIN_STACKS`, `RULE_MIN_FACES` | 2 distinct clean face stacks at H, read on 2 different faces (a side settled by CORNER and declaration counts as its face; a repeat, part or close photo counts as its face); a back corner among them when Y ≥ 2 (§4.1) | strict trust (a side that repeats the front never counts); any photo; doubted readings allowed | 3 |
| `RULE_PLURALITY` | **off**: covers are "sometimes" (Decision 4, §4.6), so H and H − 1 together are expected | withhold when more clean face stacks read H − 1 than H | 3, 4 |
| `RULE_COVER_RANGE` | **on** (Decision 4 answered "sometimes"): hidden stacks reported K × H with a range across the two full heights (§4.6) | off, if covers prove to be always or never used | 4 |
| `RULE_TALLER` | beyond the full-height pair only (§4.6): withhold until a second capture of that stack reads the same; then count it as read, keep H, show a note | release at H with a note | 5 |
| `RULE_BACK_CORNER` | a back corner below H withholds; a second capture reading the same releases the total, noted "rule broken at back corner" | warn only | 6 |
| `RULE_ONE_SIDE` | withhold a deep block with one side photographed | wall-side column full by the rule | 7 |
| `RULE_INSIDE_EXCEPTIONS` | honour operator-reported holes and partials with a height; withhold when no height is given | every exception is a conflict | 8 |
| `RULE_LOW_DOUBTED` | a doubted face reading below H stays at its reading; the result shows how far it could rise (up to H) | counted as read, no range (0.6.0); rescan that face | 9 |
| `RULE_HEIGHT_RANGE` | off | the farm's normal full-height range | 10 |
| `RULE_REFERENCE_HEIGHT` | asked for when K ≥ 8: the operator hand-counts one full face stack; a cross-check only | optional, as in 0.6.0 | 19 |
| `EXACT_FROM_EXTRAS` | never: a repeat, part or close photo never makes a block `exact` | allowed after farm day B | 17 |
| Depth proof | stays the declared X × Y (`index.ts:935-941, 1017-1020`) | — | 13 |
| Photos per scan | 3 by default (a deep block adds CORNER and the typed size); at most 9 | — | 12 |
| Wording | "read the same in two photos" | "verified by two photos" | 11 |

Every switch setting is covered by replay, so an answer changes one constant, not the design.

### 2.3 Where this plan departs from the starting design

| Starting design | Problem found | Plan 5 |
|---|---|---|
| H = the largest height "two independent readings" agree on | Undefined, and the choice changes totals [math on R readings, EG]. Counting photos would give the 99-block H = 19 and four false retakes, if the rule ran on one-deep rows. Counting raw readings gives the 4 × 3 H = 16 and 169, not 165. | Two **distinct** face stacks with clean readings on **two different faces**, a back corner among them when Y ≥ 2, and a plurality guard (§4.1). A corner stack counts once. |
| A single taller stack → retake | It may be a real cover tray (4 × 3 back-left 16 = 15 filled + 1 cover [V, FS]); a retake reads it again. | Withhold. If a second capture reads the same height, the stack is counted as read, H is unchanged and a note is shown. |
| Only over-reads are checked | Two agreeing under-reads pass (ef823816 app front 10, 10 vs hand 20 [M vs V]); two over-reads in one photo set H; one over-read on each of two faces sets H (one 21 in front and one on a side among 20s). | Clean-only basis on two faces, back corner in the basis, plurality guard, back-corner check, close photo (§4). |
| "The back row is always full" stated only | Never used as a check. | Back corners must equal H and anchor it. They disagree on the only real deep block (4 × 3: 16 vs 15 [R]). |
| Every hidden stack is H | A one-side scan's unseen side column may hold partials; short (1–2 tray) partials become strays and shift positions; a partial with the full stack behind showing above it can merge into one column, which under rule 1 is the normal case; partials may also stand outside the X × Y rectangle [V, MvB]. | One-side withheld; declared X catches shifts; mixed-column cases over a range of scales and a column split (§7, Phase 1); where partials stand is asked (Decision 18). |
| K × H sensitivity | True, but a size error costs 2.5–15 times more (§4.4). | The depth guard and declaration stay central. |
| Segments merged without double counting | With equal heights any overlap offset fits (`index.ts:962-967`); a declared width that picks the offset then confirms itself. | A segmented face needs the parts order from the app. A seam the heights cannot place is never placed by the declaration: withheld unless a CORNER photo reads the same width (§5.4). |
| "M verified by two photos" | "verified" is banned in the estimate panel (`test/evidence_grid_test.dart:820-823`); two photos share the detector's habits (AUD: 10/10/11 for 11/11/11 layers [M vs V]). | "M stacks read the same in two photos". Repeats never make a block `exact` (§3, Decision 17). |
| Extra photos as needed | A retake resends every photo under a new scan id, and each is a paid call again (`scan_session.dart:116-137`; `index.ts:339-340, 351`). | Detector cache keyed on photo hash (Phase 4); a follow-up sends only its new photo (Phase 5). |
| Farm day: open 2–3 blocks | 0 breaks in 3 opened blocks bounds the per-block break rate only to ≤ 63%; the per-stack bound (about 2–4%) overstates it, because a block is built at once (§8.4; PV: the unit is the block). | Two farm days, opened blocks picked at random by a written rule, and a load-out log (§8.2); the limits are stated. |

### 2.4 What this plan supersedes and keeps

- **Supersedes** (once approved): the neighbour median (`index.ts:656-681`) and the 3 Nov "neighbours' face height" default; `suggested_views: ["elevated"]` (`index.ts:1540-1543, 1715`); Plan 4 product B, the Phase 2 top detector and the TOP-photo trials (rule 5); the 0.6.0 upload contract (a new 0.7.0 contract doc is written; the 0.6.0 doc is not edited); PV's planted "remove or lower one interior stack" trials as accuracy tests (they become rule-break trials).
- **Keeps:** never `confirmed`; `exact` for one-deep blocks only (`index.ts:702-703, 1539`), and never from a repeat, part or close photo; the declared-size depth proof; CORNER photos; the Plan 4 §5 truth protocol; Plan 4 Phases 4–5 (retrain only with approval; pre-registered release test); no operator stack correction; the Plan 3 rule (no new neural network, VLM, NeRF or photogrammetry); the frozen 38-case replay library.
- **Plan 4 Decision 0** stays open and sets every tolerance below.

## 3. How a block is counted

Grid (Contract §4): x runs across the front (0 = left), y into the block (0 = front row). Example 5 wide, 3 deep:

```
            x=0   x=1   x=2   x=3   x=4
back  y=2    L     H     H     H     R     back corners: seen by the side photos, must read H
      y=1    L     H     H     H     R
front y=0   S+L    S     S     S    S+R    front corners: seen by two photos

S, L, R = face stack read from the STRAIGHT, LEFT or RIGHT photo (counted as read, partials included)
H       = hidden stack, set to the block's full height by the stacking rule (never seen)
```

- **Outer ring (measured).** Every face stack is read from a photo and counted as read, half-filled or not. A stack read the same, cleanly, by two distinct captures is "read twice" (the code's `verified` flag, `index.ts:798-801`). Copies of a photo count once (`index.ts:718, 1662`). A stack read twice only through a repeat, part or close photo counts in M but never makes a block `exact` (Decision 17).
- **Interior and the hidden middle of the back row (rule, not seen).** Each of the K hidden stacks is H, labelled "full by the stacking rule".
- **Formula [math]:** T = N + K × H − E. N = sum of face stacks. E = what the operator reports missing or short inside. K = max(0, X−2) × (Y−1) with both sides photographed (Contract §4, unchanged). With one side, K = (X−1)(Y−1); withheld by default (§4.3).
- **Operator effort.** A deep block needs, as in 0.6.0, a CORNER photo and the typed block size (`DEPTH_PROOF`, `index.ts:941`), so its default is 3 photos + CORNER + typed size.
- **Result line (app 0.7.0):**
  > Counted N on faces (M stacks read the same in two photos) + K hidden stacks × H − E reported by the operator = R, full by the stacking rule. Size X × Y as declared.
  > Estimate T tray layers (up to T + D if the doubted low face readings are full stacks). One layer wrong in H changes T by K.
- With K = 0 the line is only "Counted N on faces (M stacks read the same in two photos)". The "up to" part appears only when a doubted face reading is below H (Decision 9).
- **Residual line**, replacing "A hidden stack can be missing, shorter or taller." (`block_view.dart:565`):
  > Hidden stacks are not seen. The farm's stacking rule says they are full. If the rule was broken in this block, the
  > estimate is wrong.
- **M is in stacks.** Today's `visible_verified_trays` is in trays (`index.ts:697`), so a new field carries M (§6).

| Status | When | Change |
|---|---|---|
| `exact` | one-deep block, every stack read twice, no ambiguity | none (`index.ts:702-703, 1539`). Readings from a repeat, part or close photo never make a block `exact`; only today's paths do. Widening `exact` is a separate decision, taken only after farm day B shows F2 = 0 on physically counted stacks (Decision 17). A repeat shares the detector's habits: AUD set A read 10/10/11 for 11/11/11 layers [M vs V], so a repeat with the same cover habit would give `exact` 31 for 33. |
| `estimated` | a total, with K > 0, a single reading or an ambiguity | every rule-based block is `estimated` |
| `conflict` | no total; a named face or stack to retake | new withheld reasons (§6) |
| `needs_view` | a face is missing or refused | none |
| `confirmed` | never | none (Decision 2(a); test H9, `hidden.test.mjs:186-202`) |

**Wording rules.** A rule-based value is never called "counted", "measured", "exact", "verified", "physically verified" or "confirmed". No new block status is added: old apps show an unknown status as RETAKE NEEDED (`result_look.dart:40-45`). The app test that bans "exact", "confirmed" and "verified" in an estimate panel stays.

## 4. The full-height rule H

### 4.1 Definition

1. **Candidates.** A candidate is one capture's reading of one face stack. It must be **clean**: no gap-filled layer and no doubt (`index.ts:798`), `count_agreement` true (`index.ts:629-634`), and from a **rule-eligible capture**: camera still, not blocked, not a copy, and for a side, side status `turned` (`index.ts:1016-1019`).
   - A rule-eligible side includes one that repeats the front once a CORNER photo and the declaration settle its depth (`repeats_front: true`, `index.ts:1014, 1018`). The code's `trusted` (`index.ts:1659-1660`) also requires `!repeats_front`, so such a side never makes a stack read twice; that stays.
   - Why: `mirrorsFront` matches whenever side and front lengths differ by at most 1 and heights agree within 1 (`index.ts:958-970`), which the stacking rule makes the normal case for near-square blocks. Measured offline on 5 Nov (library replayed on worker-0.6.0 `dist/index.js`, plus the saved 4 × 3 scan; no detector call): every released deep case in the library (S21, S26, S28, S29) and the field 4 × 3 in `camera-corner-declared` has trusted = STRAIGHT only, with both sides `repeats_front`. With the strict `trusted`, none of them would ever have an H (Decision 3).
2. **H** is the largest height h such that:
   - at least **two distinct face stacks** have a clean reading equal to h;
   - those readings come from photos of **at least two different faces**; a repeat, part or close photo of a face counts as that face;
   - when Y ≥ 2, one of the two is a **back corner** (the rule says the back row is full);
   - two readings of one stack never count twice; a corner stack counts once, for one face whose clean reading equals h.
3. **Plurality guard:** if more clean face stacks read exactly H − 1 than read H, the total is withheld (`rule_height_ambiguous`); H may rest on two over-reads or two covers. **Off while covers are "sometimes"** (Decision 4): the cover range of §4.6 replaces it.
4. **No qualifying height:** no H, the total is withheld (`no_rule_height`), and the server asks for a close photo of a back corner (Phase 5; until then, a retake of the side with the most doubts).
5. **K = 0** (one-deep rows, blocks at most 2 wide): the rule is not used and the block reads `rule.applied: false`. One-deep answers and `typical_layers` stay as in 0.6.0.

### 4.2 Checks after H is found

Each failed check withholds the total and names a face or stack. Two parts are new code [C]:
- **Provisional figures.** Today they exist only for depth withholds (sides `depth_unproven` or `turned_repeats_front`, `index.ts:1697-1711`). A `buildBlock` conflict leaves `withheldReason` null, so the reason reads `conflict` (`index.ts:1592, 1712`). New provisional code and new `withheldReason` plumbing are needed.
- **Naming the cell.** Each check is raised in `buildBlock` with a face prefix, so `namedFace` (`index.ts:1667-1674`) names the face. `rescan_cells` is built from cell status, not from the conflicts list (`index.ts:699`), so the check must also set the cell to `conflict`. That nulls its layers (`index.ts:791`), so `block.rule` keeps the reading for the provisional figures.
- A conflict raised later in `assembleGrid` would retarget the retake to `straight` (`index.ts:1766-1767`).

| Check | Fires when | Result |
|---|---|---|
| Taller | a face stack reads above H (clean or not) | `stack_taller_than_rule_height`; provisional totals at H and at the taller value; retake that face, or a close photo of that stack (Phase 5). If a second clean capture reads the same height, the stack is counted as read, H is unchanged, and the result says "one stack taller than the block's full height". |
| Plurality (off while covers are "sometimes", §4.6) | more clean face stacks read H − 1 than H | `rule_height_ambiguous`; a close photo of a back corner |
| Back corner (Y ≥ 2) | a clean back-corner reading differs from H | below H: `back_corner_below_rule_height`, retake that side or a close photo of that corner. If a second capture reads the same, the corner is counted as read and the total is released with "rule broken at back corner" (Decision 6). Above H: the taller check. |
| Inside hint | a stack glimpsed through a gap on a hidden cell (a hint, `index.ts:771-783`) reads below H | `inside_hint_below_rule` (it may be a short interior stack or another block) |
| Reference height | the declared, measured `reference_height` (`index.ts:1274-1275`) differs from H | `reference_height_differs` |
| Range (off by default) | H lies outside the farm's normal full-height range | `rule_height_out_of_range` |

### 4.3 Edge cases

- **Face stacks below H** are partials and are counted as read. A clean low reading is a point value. A doubted or gap-filled low reading stays in the estimate at its reading, and the result shows how far it could rise: up to H (Decision 9). Under the rule, a doubted low reading cannot be told from an under-read full stack. Measured on accepted photos [M vs V, VAL]: clean readings were wrong on 1 of 21 stacks; doubted or gap-filled ones matched on only 9 of 21 and were off by 2 or more on 10.
- **Partials outside the rectangle.** MvB describes short stacks beside or in front of a block [V] (§2.1). The grid cannot hold them. From the front, a partial in the face row and one standing in front of it look the same, yet the totals differ by H. Decision 18.
- **Face holes** are allowed (rule 2 covers the interior). The 4 × 3 front-right spot is empty [R].
- **One side photographed:** the unseen side column counts as hidden (`index.ts:721, 804`). Rule 1 does not say whether partials may stand on a wall side, so the block is withheld (`one_side_only`) until Decision 7.
- **Short partials (1–2 trays)** are stray groups, never counted, and shift later positions (`index.ts:567, 611-615, 740-743`). A stray group at column spacing on the floor line means "may hold one more stack": no total unless the declared X matches (`index.ts:1433`).
- **Operator-reported exceptions on hidden cells** (`index.ts:1408-1424, 1439-1518`). The total can go down, never up:

| Input on a hidden cell | Plan 5 |
|---|---|
| Declared missing stack, or an ELEVATED `missing` tap | honoured: 0, flag `rule_exception`, the cell is named |
| Declared partial with a height | honoured: that height, flag `rule_exception` |
| Declared partial without a height, or a `step_down` tap | withheld (height unknown; already true, `index.ts:1533-1534`) |
| `interior: "partial"` | withheld (`inside_declared_partial`): no cell is named |
| `step_up` tap | withheld (`inside_step_up`): H may be too low |
| `interior: "full"` | recorded as `rule.affirmed_by_operator: true` |

### 4.4 Sensitivity [math, on V block sizes and H]

| Block | K | H off by 1 = K trays | Width X off by 1 ≈ (Y−1)·H | Depth Y off by 1 ≈ (X−2)·H + 2 side stacks |
|---|---|---|---|---|
| W05, 10 × 7, H 20 | 48 | ±48 (3.5% of 1,366) | ±120 | ±200 |
| L-115, 6 × 6, H 20 | 20 | ±20 (2.7% of 734) | ±100 | ±120 |
| L-109, 6 × 3, H 20 | 8 | ±8 (2.1% of 375) | ±40 | ±120 |
| Field 4 × 3, H 15 | 4 | ±4 (2.4% of 165) | ±30 | ±60 |
| L-100, 5 × 1, H 20 | 0 | 0 | 0 | depth falsely 5: +400 (the false 500) |

One interior rule break costs +H for an empty place and +(H − h) for a partial of h trays. **A size error costs 2.5–15 times more than an H error** (W05 width 120/48 to L-109 and 4 × 3 depth 120/8 and 60/4 [math]), so the depth guard matters more under the rule, not less. Front-only H, MUTAA [M staging 0.4.12 vs V]: W05 backend H 19 vs manual 20 (48 trays apart); L-115 19 vs 20 (20); L-109 20 vs 20; M16-FAR 17 vs 15 (wrong width read).

### 4.5 Worked examples (rule outcomes are [E] until the Phase 1 replay runs)

| Block | Readings | Worker 0.6.0 | Plan 5 default | Reference |
|---|---|---|---|---|
| 99-block, 5 × 1 [R, EG] | front 20, 20, 20, 20, 19; each side shows one stack, 19 | `estimated` 99 in all 4 modes | K = 0, rule unused: 99. Camera modes: "Counted 99 on faces (1 stack read the same in two photos)". | label 99 [U]. Front photo used in tuning: an example, not a test. |
| Field 4 × 3 [R, counterfactual `camera-corner-declared`] | front 15, 15, 15 (front-right spot empty); LEFT 16, 15, 16; RIGHT gap, 14, 15. Only STRAIGHT's front-left 15 is clean; every other face reading has `end_at_frame_edge`. Both sides repeat the front and are settled by the CORNER photo and the declaration, so `trusted` is false for them (`index.ts:1660`). | 105 counted + 60 assumed = 165 (range 163–167) | One clean stack: withheld `no_rule_height`, provisional 165; the server asks for a close photo of a back corner. A clean back-right 15 would give H = 15, and the back-left 16 is then taller: withheld until a second capture of it. With doubts allowed (Decision 3(c)): H = 15 (S, L, R), back-left 16 taller → still withheld, provisional 165 at H 15 or 169 at H 16. | 164 filled [V, FS]; back-left = 15 + 1 cover [V] |
| L-100, 5 × 1 [R, MvB] | 20 × 5 on every face; "sides" are re-shots of the front [V] | withheld in all modes | withheld by the depth guard. If taken as 5 deep: 13 × 20 + 12 × 20 = 500 [math], the false 500 staging 0.4.12 gave [M]. | 100 [U, V] |
| Contract H2 [S] | front 20/19/20/20; LEFT 20/20/18; RIGHT 20/20/20 | 236 | H = 20; face stacks 157; K = 4; back-left 18 < H → withheld, provisional 237 (released 237 if Decision 6 is "warn") | 0.5.0 gave 237 [R] |
| ef823816, 5 × 4, wall left and back [FS] | app front 10 / rescan / 18 / 10 / 12 [M]; hand front 20/20/20/20/13, right 13/20/20/20 [V] | not run; staging f5776f0d would have given 233 (89 + 144), withheld by the gate [M, FS] | As uploaded: `needs_view` (the gate refused STRAIGHT and LEFT; LEFT and RIGHT were the same right face [V, FS]). With a correct capture (no LEFT possible): `one_side_only`. The two 10s are in one photo: no H. With "any photo": H = 10, but the 18 and 12 are taller, so only a provisional 120 inside, for about 240. Hand reading with a full wall column: 153 + 12 × 20 = 393. | 393 filled + 19 covers [V] |
| Phone audit A, 3 × 1 [AUD] | 10 / 10 / 11 [M] | 0.5.0: withheld (stand-in side refused) [M]; 0.6.0 not run | K = 0. The 11 is "taller" only if K > 0. A repeat reading 10/10/11 again stays `estimated` (Decision 17), not `exact` 31 for 33. | 10 filled + 1 cover each = 33 [V] |

**Counterfactual inputs:** the `camera*` replay modes use made-up headings, and `camera-corner-declared` adds a synthetic CORNER photo and the declared size (`scripts/replay_saved_scans.mjs`). **The back corners fail the check on both deep examples** (4 × 3: 16 vs 15; H2: 18). That is why cover trays (Decision 4) and back corners (Decision 6) must be settled before the check runs in the field.

### 4.6 Cover trays: "sometimes" (Decision 4, answered by the user on 5 Nov) [U]

A full stack holds F filled trays, and sometimes an empty cover tray on top, inside the block too. So a full stack is
F or F + 1 tray layers, and the photos cannot tell which hidden stacks carry a cover. The unit stays tray layers,
covers included. Consequences for §4.1–4.2:

1. **Two adjacent heights are both "full".** After H is found as in §4.1, the block's full heights are H and its
   partner one away: H − 1 if a clean face stack reads H − 1, otherwise H + 1 if one reads H + 1. A face stack at the
   partner height is a full stack, with or without its cover, and is counted as read. It is not a partial and not
   "taller".
2. **The hidden stacks get a range, not one value.** Point estimate: K × H, as before. Range: K × the lower full height
   to K × the higher one when the faces show both heights; K × (H − 1) to K × (H + 1) when the faces show only H,
   because then nobody knows whether H includes a cover. The result line adds: "Cover trays are sometimes used: the
   hidden stacks hold A to B tray layers."
3. **The plurality guard is off** (`RULE_PLURALITY`): a mix of H and H − 1 is now expected. Two over-reads that lift H
   by one stay inside the range, which is printed.
4. **The taller check fires only beyond the pair:** a clean face stack two or more above H, or one above H when the
   faces already show H − 1 (three full heights cannot be explained by covers). Then it withholds as in §4.2.
5. **Back corners** pass at either full height; below the lower one, the back-corner check of §4.2 applies.
6. **Examples [math on R readings, rule outcomes E]:**
   - Field 4 × 3, if doubted readings were allowed (Decision 3(c)): H = 15. The back-left 16 is its cover partner (FS
     saw 15 + 1 cover there [V]), not a taller stack, so the block is no longer withheld for it. The hidden stacks
     come to 60, with a range of 60–64, so the total is 165, with a range of 165–169. Under the default (a) it is still
     withheld, with only one clean reading (§4.5).
   - Contract H2 [S]: H = 20; the front 19 is the partner, so the hidden range is 76–80. The back-left 18 is below the
     pair and still withholds.
   - W05-size block (K = 48) with only H seen on the faces: the range is ±48 trays, which is 3.5% of about 1,366.
7. **How to narrow it later.**
   - Telling a cover from a filled top tray on the face stacks (Plan 3 Phase P occupancy; not active today) would
     fix F on the faces. The range would then be K × F to K × (F + 1) and could not be narrowed further from photos.
   - Farm day A records cover use on face and hidden stacks (§8.2). If covers turn out to be on nearly every full
     stack, or on almost none, the user can move the point estimate to that side.

## 5. Multi-photo capture

### 5.1 Roles

| Role | When | Per scan | What it adds | App guidance |
|---|---|---|---|---|
| STRAIGHT, LEFT, RIGHT (primary) | always | 3 | as today | as today |
| CORNER | deep blocks (routine under the rule: near-square blocks of near-equal heights make `turned_repeats_front` common, `index.ts:961, 1009-1012`) | 1 | width/depth cross-check, settles a side that repeats the front | as today |
| Repeat of a face | when the server asks, or by choice | ≤ 1 per face | a second reading of every stack on that face | "Step one or two paces to the side. Same face, whole face in the frame." Same-face heading within 45° |
| Face in parts | a face that does not fit the frame | 2–3 parts | closer photos (9 of 10 exact close up [M vs V, MvB]) | "PART 1 OF 2" chips, overlap band "keep the last stack of part 1 here", part 1 kept while part 2 is taken |
| Close photo of one stack | only when the server asks (`requested_captures`) | ≤ 2 | a second, close reading of the named stack: the two back corners when H has no basis, a taller stack, a back corner below H | narrow single-column guide; the earlier photo shown with the target column highlighted, not a stack number |
| BACK | rare (rule 4) | ≤ 1 | field name reserved and archived; not read in this plan | none |

Default stays 3 photos; a deep block also needs CORNER and the typed size, as today. Repeats and close photos are asked for by the server, not by habit (operator effort).

### 5.2 How two captures read a stack the same

The existing rule (`index.ts:798-801`) is kept: a stack is read twice when clean readings from two distinct capture ids give the same value. Readings are keyed by capture, not by face name, because today two STRAIGHT readings would collapse (`index.ts:784-796`). STRAIGHT's primary still wins a tie (`index.ts:796`). **Two photos agreeing means the reader agrees with itself, not that the count is true:** a repeat shares the detector, light and angle. So a stack read twice only through a repeat, part or close photo counts in M but never sets what makes a block `exact` (`index.ts:801, 703`; Decision 17), and a repeat never adds a second face to the H basis (§4.1).

### 5.3 Matching a repeat to its primary photo

- Equal column counts: match by order. Counts one apart: try offsets −1, 0, +1 and keep the single offset with the most exact matches, at least 3. No unique winner: the repeat gives no readings and an ambiguity is noted.
- A one-stack slip changes a result only where heights differ, which is where heights reveal it.
- A repeat whose heights disagree with its primary on more than one stack by more than 1 is refused: "another face or another block?". A stack differing by 2 is a conflict (`index.ts:788-793`).

### 5.4 Merging parts without double counting

1. The **app's part index** orders the parts. The heading cannot: yaw does not sense walking sideways (`heading_tracker.dart:102-147`).
2. The app asks for exactly one stack of overlap: the last column of part k is the first column of part k+1. The seam stack is one stack with two readings. Step 4 checks that this happened.
3. The seam readings must agree within one tray, or the stack is a conflict.
4. **Check:** try seam overlaps of 0, 1 and 2 stacks. If more than one fits the heights (equal heights fit every offset, `index.ts:962-967`), the seam is unproven. A seam the heights cannot place is **never placed by the declaration**: a declared X that picks the overlap would then equal the merged width by construction, and the independent check of photo width against the declaration (`index.ts:1017`) would be lost, so a habitual wrong X would pass (W05: ±(Y−1)·H plus the seam stack, about ±140 [math]). The block is withheld (`segment_seam_unproven`) unless a CORNER photo reads one of the fitting widths and the declaration names the same; the result line then names the width "as declared". Otherwise the app asks for fewer, wider parts.
5. `cut_at_frame_side` (`index.ts:587`) is expected on the continuing side of a part and is waived there only.
6. Width, the side check and `mirrorsFront` use the merged lists (`index.ts:726, 976-981`).

### 5.5 Mismatched photos

| Case | Handling |
|---|---|
| Byte-identical photo | refused, 422 `duplicate_view`, now across every photo (`index.ts:270-276, 283`) |
| Copy or re-encode (overlap score ≥ 0.8, `index.ts:1188-1218`) | counted once; takes the original's capture id; never read twice. The 0.8 line was measured on re-encodes (0.944–0.995), the same photo or near-identical bursts (0.952–0.976), and different captures of one block (0–0.52) [M, code comment `index.ts:1189-1191`]. A repeat from the same spot is therefore already expected to score as a copy; repeats from a step aside are measured in Phase 4. |
| Repeat or part turned away from its face | untrusted when more than about 45° from its face's primary; a side repeat must also pass the turn check (`index.ts:1026-1037`) |
| Photos of another block | refused by the repeat height match (§5.3), the declared X × Y, and a time window [E]: the primary set within 10 minutes of each other; a follow-up (close photo, repeat asked for after a result) within its own window tied to the parent scan. The time is `measured_at` (`frame_preflight.dart:179-200`). Today it reaches the server only in the faces' full `_constraint_evidence`. CORNER and ELEVATED send only `_capture` (`source`, `blocked`, `yaw_deg`, `yaw_session`: `api_client.dart:533-536`; `test/scan_job_test.dart:829-835`), so the app must add `measured_at` to `captureField` [E, app change]. |
| Gallery photo (testing only) | no heading (`photo_upload_pane.dart:214-222`): untrusted, never read twice, never a deep total (`index.ts:1042-1043`) |

## 6. API and contract changes, and backward compatibility

**Request (`POST /v1/scans/count`).** The three face fields stay the primary photos. New, unique field names, never a repeated name (`form.get` keeps only the first, `index.ts:241`): `<face>_repeat`, `<face>_part2`, `<face>_part3`, `close_stack` with `close_stack_target {face, stack_index}`, and `back`. Each new field has `_capture` (with `measured_at` added) and `_constraint_evidence`, through the existing checks (`index.ts:242-253`) and `readCapture` (`index.ts:197-212`). That is a new extras contract: today's extras send `_capture` only (`test/scan_job_test.dart:829-835`). One `captures` JSON field lists `{field, face, role, part, of, overlap_side}`. At most 9 photos.

**Follow-ups [E].** A close photo or a repeat asked for after a result is sent under a new scan id with `parent_scan_id` and only its new photo. The server takes the parent's photos from the archive (`index.ts:300-327`) and their detections from the cache. Today a follow-up resends every photo (`scan_session.dart:116-137`), on a link measured once losing 40% of packets (§10).

**Response.** Locked key lists only gain keys (H13, `side_check.test.mjs:397-426`).
- Hidden cells: `evidence_class: "assumed"` (known to app 0.6.x), `assumed_from: "stacking_rule"`, `assumed_range [H, H]` (the app uses a cell's range only to draw a ghost with no height, `block_view.dart:103-106`); exceptions carry `rule_exception`.
- `block.rule`: `applied`, `height`, `basis` (stack and capture ids), `taller` (with the kept reading), `back_corners`, `plurality`, `exceptions`, `affirmed_by_operator`. `typical_layers` holds H when the rule applies; when K = 0 it keeps 0.6.0's mode. Null there still withholds (`index.ts:700-702`).
- Inventory keeps `counted_trays`, `assumed_trays` (= K × H), `estimated_total`; adds `rule_stacks`, `rule_height`, `rule_trays`, `two_photo_stacks` (M), `sensitivity_per_layer` (K), `rule_exceptions`, `doubted_low_up_to` (D, Decision 9), `rule_trays_range` and `rule_full_heights` (the cover range and the full-height pair, §4.6; new fields, so 0.6.x apps ignore them).
- For a rule-based block, inventory `assumed_range` and `estimated_range` are **null**. App 0.6.x then prints "(range not given)" in its split line (`block_view.dart:505-516`) and hides its range row, whose label "If every hidden stack is there at its neighbours' heights" would be false and whose "291–291" would look certain (`block_view.dart:839-844`).
- `block.total_eggs` is unchanged: null whenever a stack is assumed (`index.ts:1759`), so null for every rule-based block. One-deep blocks keep the legacy capacity figure for app 0.5.0; removing it is a separate compatibility choice.
- New withheld reasons in `WITHHELD_NOTE` (`index.ts:1556-1561, 1592`): the ones named in §4 and §5.
- `block.extra_captures` reports repeats and parts; `views` keeps exactly the three faces, because old apps parse it strictly (`scan_result.dart:14-18`).
- `block.requested_captures: [{kind: "close_stack", face, stack_index, reason}]`. Never in `recommended_view`: app 0.6.1 turns an unknown view into LEFT (`scan_flow_screen.dart:301-304`).
- `suggested_views` drops `"elevated"`; `["corner"]` and `suggested_inputs: ["declaration"]` stay (`index.ts:1719-1722`).
- Notes (`index.ts:640-641, 1309, 1600-1603`) say "N counted on faces; K hidden stacks × H = R full by the stacking rule (not seen)".
- Versions: `grid_contract` 0.7.0 (`index.ts:1764`), `worker-0.7.0` and up (`index.ts:1855`); new doc `docs/GRID_CONTRACT_0.7.0.md`.

**Server housekeeping.** `/health` lists `multi_photo_v1` in `scan_contracts` (`index.ts:2557-2561`). Request fingerprint version 4, with every photo's hash and role, when any extra photo is present; version 3 otherwise (`index.ts:1870, 2138-2158, 2165`). Without it, a retry with other *new* extra fields (not in v3) would replay a stale answer (`index.ts:2123-2127`); a different CORNER or ELEVATED already changes the v3 fingerprint and gets 409 `scan_id_conflict` (`index.ts:2146-2147`). `evidence.json` per photo field, not per view (`index.ts:327`); `listArchive` and `hasArchivedPhotos` list the extras (`index.ts:1132, 2306`). Detector cache by photo sha256 plus model id, under the staging state prefix in the existing R2 bucket. That bucket is shared with production (`wrangler.jsonc`: both bind `SCAN_ARCHIVE` to `egg-tray-scan-archive`), so the prefix is asked for before Phase 4 is deployed; no new binding. A gallery CORNER is checked before its detector call, not after (`index.ts:351, 1639`).

| Pair | What happens | Checked by |
|---|---|---|
| App 0.6.0+29 / 0.6.1+30 with Worker 0.7.x | Same 3-photo request. Rule cells draw as assumed ghosts "~H"; the line reads "Counted N + Assumed K·H (range not given) = Estimated T" (`block_view.dart:502-516`) and the range row is hidden (`:839-844`); new withheld reasons show the generic withheld line (`:772-783`); RETAKE names only STRAIGHT, LEFT or RIGHT. Needs kept: `processing.mode: model_spatial_v1`, `scan_id`, `cell_ids` (`scan_job_runner.dart:137-157`), numeric `quality` and boolean `accepted` per view, `stacks`, the legacy top-level fields (`index.ts:1735-1736`). | Phase 1 gate 8 |
| App 0.7.x with Worker 0.5.0 / 0.6.0 | No `rule` fields: the old split line. No `multi_photo_v1`: no extra-photo tiles, so no photo is uploaded for nothing. | Phase 2, 4 tests |
| 3-photo request to Worker 0.7.1+ | fingerprint v3, same inference order and count (`compatibility.test.mjs:38`, `grid.test.mjs:135`) | Phase 4 gate |
| Stored jobs | a finished job replays its stored answer forever (`index.ts:2123-2127`) | none needed |
| Pending scans saved by 0.6.1 | restore still reads the `views` manifest (`pending_scans.dart:178-192`); new scans add a `captures` list | `test/pending_scan_test.dart:596-620` pattern |
| History | stores status and tray count only, no block JSON (`history_database.dart:104-115`): nothing to migrate. New columns, if ever, need schema v3, nullable, upgrade from < 3 (`:98, 151-160`). | n/a |

## 7. Phases in build order

Phases 1–2 and the offline parts of 4–6 can be built while farm day A is arranged. **Nothing from Phases 4–6 goes to staging before the Phase 3 gate.** No phase touches production. Every push, deploy, install and batch of paid calls is asked for separately.

### Phase 1: the stacking rule on the server, offline (Worker 0.7.0)

- **Changes:** `ruleHeight()` beside `mode` (`index.ts:643-650`), called in `buildBlock` after the cell merge (after 818), replacing `typical` (820). In `assumeHidden` the neighbour median, the mode fallback and the `[0, …]` range (`index.ts:665-676`) go; each computed cell gets H; line 1327 passes H. The checks of §4.2, the exceptions of §4.3, the response fields of §6, `suggested_views` without `elevated`. Request, inference calls, side check, depth proof, column reader and `exact` guards unchanged.
- **Tests that change (each listed with its reason in the report):** `hidden.test.mjs` H1–H5 (H2: 236 becomes withheld, provisional 237; H3/H4 lose the ranges down to 0; one-side withheld); `block.test.mjs:29-39`; H6, H8, H14 by input type; H13 (`side_check.test.mjs:397-426`: key lists only gain keys; its hole-plus-step-up case, released 281 today, becomes withheld `inside_step_up`); `grid.test.mjs:25` version; library cases S09, S28, S29 kept and relabelled "rule-break cases" (S29 still releases 180 for 160 without a tap, `replay_benchmark.mjs:230-233`).
- **Library cases that depend on Decision 3** [R trust flags, measured offline 5 Nov; rule outcomes E]: S21 and S26 (`total_ok` 180) and S28 (`total_ok` 100) keep their right answers under the default, because their sides, settled by CORNER and declaration, count for H. Under the strict option they become withheld `no_rule_height`: right answers in the library drop from 11 to 8, and S29 is withheld too.
- **Must pass unchanged:** H9, `compatibility.test.mjs`, the observe tests, `replay_benchmark.test.mjs:17-44`.
- **New tests:** `test/rule.test.mjs`; a `withheld_reason` judge check (`replay_benchmark.mjs:237-246`); cases built with `syntheticFace` (`replay_benchmark.mjs:68-89`), camera headings and a matching declaration:

| Case | Input [S] | Expected |
|---|---|---|
| FR01 | 5 × 3: front 20, 20, 20, 19, 12; LEFT 20, 20, 20; RIGHT 12, 20, 20 | 291 = 171 counted + 6 × 20 |
| FR02 / FR03 | FR01 with front x=2 at 21 / FR01 with front 21, 21, 20, 19, 12 (two over-reads in one photo; sides as FR01) | FR02: withheld, retake `straight`, provisional 292 at H 20 or 298 at 21. FR03: H = 20 (the 21s are on one face), the 21s are taller, withheld, no wrong total |
| FR04 | every face under-read by 2 | stretch case: documents the residual risk |
| FR05 / FR07 | LEFT back corner 18 / one side only | `back_corner_below_rule_height`, retake `left` / `one_side_only` |
| FR06 | 5 × 1 row 20, 20, 20, 20, 19 | same answer as 0.6.0 |
| FR08–FR11, FR16 | declared missing (2,1); `interior: partial`; `step_up` at (2,2); hint 14 on a hidden cell; reference height 21 | 271 with `rule_exception`; withheld in the rest |
| FR12 | a 2-tray stack at front x=2, declared 5 × 3 | withheld (width 4 vs 5), never wrong |
| FR13 | front x=1: 8 trays at scale 1.0 with 12 boxes above (the full stack behind), swept over scales 0.80–0.97. With trays about 0.3 m deep, the row behind is at about 0.91 from 3 m and 0.87 from 2 m [math, tray depth and standoff unmeasured]. | `no_wrong_total` at every scale; if any fails, Phase 1b |
| FR13-side / -corner / -outside | the FR13 column on a side face / a corner partial misread the same way by STRAIGHT and the side / a partial standing in front of the face row, declared X × Y | `no_wrong_total`; the corner is never "read twice" at the wrong value; the outside partial is withheld or flagged |
| FR14 | hidden hole, no tap | stretch: released 20 high (S29's twin) |
| FR15 / FR17 | every reading `end_at_frame_edge` / cover trays on 3 of 8 full face stacks | `no_rule_height` / released with the cover range of §4.6: the covered stacks are the partner height, never "taller"; the true total lies inside the printed range |
| FR18 | FR01 with front x=1 and the LEFT back corner at 21 (one over-read on each of two faces) | with covers "sometimes" (§4.6): H = 21, 20 is its partner, hidden range 120–126; the point is 6 too high, the true total is inside the printed range. With the plurality guard on (covers never used): `rule_height_ambiguous`, withheld |
| FR20 | FR01 with front x=3 (19) doubted | 291, "up to 292" |

- **Phase 1b (only if an FR13 case fails):** split a column where box scale or pitch steps down (`index.ts:475, 635`); the upper part becomes a hint for the stack behind, never a count. With `RECESS_SCALE` 0.85 a stack 0.3 m behind is told apart only from within about 1.7 m [math], so Phase 1b needs its own step threshold, set from the FR13 sweep and farm day A photos. The error changes sign with distance [E]: far away the mixed column reads as full (+(H − h)); close up it can be marked recessed or missing (−h). The 52 labelled faces and MUTAA columns must not change (`replay_benchmark.test.mjs:17-35`).
- **Replay:** `scripts/replay_saved_scans.mjs` and `compare_replay_versions.mjs` (0.6.0 vs 0.7.0) into `reports/stacking-rule-0.7.0-<date>/`.
- **Gate (offline):** (1) `npm test` 0 failures; (2) 38 old + new cases, 0 wrong `exact`/`confirmed`; (3) no case 0.6.0 got right or withheld becomes a wrong released total (wrong = the true total lies outside the printed range; point errors inside the cover range of §4.6 are listed one by one); the 5 known wrong 0.6.0 estimates (S03, S04, S07, R04, S29 [R, EG]) and the rule-break cases reported one by one; (4) registry 22 trios 0 wrong, 72 faces unchanged; (5) 99-block 99 in all modes, L-100 withheld in all modes, 4 × 3 as §4.5 or explained; (6) a released-case table, 0.6.0 vs 0.7.0 (0.6.0 released 16 [R]), each newly withheld case with its reason; (7) fingerprint v3; H13 key lists only gain keys, and its step-up case becomes withheld (`inside_step_up`); (8) one new `mobile/test` feeds three 0.7.0 answers to the 0.6.1 parser: no error, rule cells drawn as assumed, the split line says "(range not given)" and no range row is shown; (9) two replay runs give identical hashes; (10) no deploy, no push, 0 paid calls.
- **Approvals:** building starts after the user approves this plan (Decision 1) and answers Decision 4 (covers); a push only if asked.

### Phase 2: the app shows the rule (app 0.7.0+31)

- **Changes:** read `assumed_from: "stacking_rule"`; draw "=H" ghosts with the legend "full by the stacking rule" (`block_view.dart:103-182`); rule fields in `BlockInventory`/`TraySplit` (`block_result.dart:516-685`); a `ruleSplitLine` beside `traySplitLine` (`block_view.dart:502-516`); headline "N COUNTED + K × H BY THE STACKING RULE" (`:630-634`); the residual line (`:565`); the sensitivity line replaces the range row (`:839-844`); text for each withheld reason (`:772-783`); an unknown retake view shows text only, not LEFT (`scan_flow_screen.dart:301-304, 423`); interior entries in the declaration pane labelled "rule exception" (`declaration_pane.dart:184-275`), and the same on the manual-count screen (`manual_count_screen.dart:65-74`). No change to the upload, no history change.
- **Research capture mode (recommended before farm day A) [E]:** a camera-path mode that saves the heading, role and part with each photo and uploads nothing. Without it, farm day A research photos carry no heading, and the Phase 4 and 6 replay gates on them pass by construction.
- **Gate:** `flutter test` all pass (255 [M, PROG] + new widget tests from Phase 1 answers; the wording ban stays); `dart analyze` clean; APK secret scan 0 hits.
- **Approvals:** APK install on the Redmi first (replaces the pending 0.6.1+30; the Redmi runs 0.6.0+29 [M, AUD]). Then the Worker 0.7.0 staging deploy (`--env staging`), only after app 0.7.0 is on every phone pointed at staging; smoke test, about 7 paid calls [E]. Recommended before farm day A, so its product scans show the rule live (Decision 2).

### Phase 3: farm day A — audit the rules, first physical counts, real photos (§8.2)

- **Before:** freeze Worker 0.7.0 and app 0.7.0 (commit plus replay hash) before any farm-day photo is opened; write the protocol card, the opened-block selection rule and `scripts/score_physical_pilot.py` (named in Plan 4 §5, not built); estimate person-hours for opening blocks.
- **Gate:** §8.6. If the rule fails, the plan stops after Phase 2 and the user chooses a way on (§8.6).
- **Approvals:** about 140 paid calls in two batches [E] (§10).

### Phase 4: a repeat photo of a face, plus the detector cache (Worker 0.7.1, app 0.7.1)

- **Server:** repeat fields, matching and merge (§5.2–5.3), duplicate check across all photos, same-face direction, fingerprint v4, archive per photo, `extra_captures`, `multi_photo_v1`, the detector cache, the gallery-CORNER fix. A stack read twice only through a repeat counts in M and never makes a block `exact`; a repeat never adds a face to the H basis. Inference: faces first in today's order, then extras; bounded parallel calls if the mocked worst case exceeds `LEASE_MS` (`index.ts:1856-1865`).
- **App:** captures become a list `{id, face, role, part, of}` with `pathFor(view)` still the primary (`scan_session.dart:11-24, 90-137`); "ANOTHER PHOTO: FRONT / LEFT / RIGHT" tiles in the extras pane, camera path only (`extra_views_pane.dart:9-185`); same-face heading check beside `sideHeadingProblem` (`heading_tracker.dart:66-100`); upload only when `/health` lists `multi_photo_v1` (`device_auth.dart:136-145`); `sendTimeout` scales with photo count (`api_client.dart:69`); pending `captures` manifest; "Analyzing N photos..." (`scan_flow_screen.dart:491-494`). First, find the intermittent `pending_scan_test.dart` failure [M, PROG].
- **Cases [S]:** repeat agrees (middle stacks read twice); differs by 2 (conflict); same-spot copy counted once; one column fewer, matched by heights; equal heights with different counts (ignored); side repeat turned wrong (untrusted); gallery repeat (untrusted); one-deep row read twice everywhere (stays `estimated`, Decision 17); FR19: FR03 plus a STRAIGHT repeat reading 21, 21 again (H = 20, one face; withheld); 3-photo request identical to Phase 1.
- **Gate:** earlier cases unchanged; 3-photo answers byte-identical apart from version strings; 0 wrong `exact`/`confirmed`; farm day A repeats replayed with 0 false "read twice" (with research-mode headings; without them this gate is labelled [R, counterfactual trust]); tests updated (`test/scan_job_test.dart:822-828, 862`, `scan_session_test.dart`, `guided_capture_lifecycle_test.dart:419-462`).
- **Approvals:** the cache prefix in the R2 bucket shared with production (§6); staging deploy; APK install; field check of the copy line, about 30 calls [E]: 10 faces repeated from a step aside must score below 0.8 and 5 from the same spot above it, or the line is re-set and the library re-run.

### Phase 5: a close photo of one stack, when the server asks (Worker 0.7.2, app 0.7.2)

- **Server:** `requested_captures` for no H basis (the two back corners), a taller stack or a short back corner; at most 2 close photos per scan. The reading comes from the column nearest the image centre, not touching a frame edge or side (`index.ts:583-588`), else refused with the reason. It is one more photo of the target stack and counts as its face. A close photo whose reading differs from the target's face reading by more than 1 is refused ("another stack?") and the face is retaken instead. A back-corner close photo must show the block's end (no column beyond it). The server checks the face direction, the reading and the block end; it cannot prove which stack was aimed at.
- **App:** `ExtraView.closeStack` with a narrow guide (`extra_capture.dart:6-25`, `camera_guide_overlay.dart:47-56`), showing the earlier photo with the target column highlighted; a result-screen button. The follow-up goes under a new scan id with `parent_scan_id` and only the new photo (§6) [E], in the same screen session, because leaving deletes the photos (`scan_flow_screen.dart:277-285`). With the cache, 1 paid call [E].
- **Cases [S]:** agrees; corrects a one-layer over-read; a second capture reads a taller stack the same (counted as read, note); reading differs by more than 1 (refused); back corner with a column beyond it (refused); a real partial at a back corner read the same twice (released, "rule broken at back corner"); two columns in frame; gallery (untrusted); 3-photo request unchanged. **Gate:** as Phase 4. **Approvals:** deploy, install, about 5 calls [E].

### Phase 6: a long face in 2–3 parts (Worker 0.7.3, app 0.7.3)

- **Server:** §5.4. **App:** part chips (`guided_capture_pane.dart:1018-1048`), part 1 kept (`:430-432`), overlap band (`camera_guide_overlay.dart:47-91`), `CaptureAim.segment` silencing "move back" on the continuing side (`frame_preflight.dart:62, 277-293, 535-549`).
- **Cases [S]:** mixed heights merge to the right width; equal heights with overlap 0 or 2: withheld (`segment_seam_unproven`) with or without a declared width, released only when a CORNER photo reads the same width; a declared width that differs from every fitting width (withheld); seam heights 2 apart (conflict); three parts; seam stack cut at the side (counted once); 3-photo request unchanged.
- **Gate:** no double count released in any equal-height seam case; farm day A parts replayed with 0 wrong joins (heading-free photos test joins only). **Approvals:** deploy, install, about 9 calls for 3 long faces [E].

### Phase 7: farm day B — pre-registered blind pilot (§8.3), then the user's decision

- **Approvals:** the pre-registration and the build freeze; about 75 paid calls plus requests [E] (§10); any staging deploy during the run ends it.
- Production is not part of this plan; it needs its own approval after Plan 4 Phase 5's bar (30 released, 0 wrong).

## 8. Farm-day validation protocol

### 8.1 Kept from Plan 4 §5

- **Truth methods:** `lift_count`, `exposed_on_loadout`, `built_counted`. `from_above` is never a count.
- **Two counters,** blind to each other and to the app, on paper sheets keyed to chalk or tag markers. Disagreement means a joint recount. The in-app manual count is not used.
- **Integrity:** the answer hash is recorded before truth starts; no RETAKE or NEW SCAN until both blind counts are taken; photos the server asks for during a scan belong to it, and the first released answer is scored; the build is frozen before photos are opened.
- **Unit:** tray layers, cover trays recorded separately.

### 8.2 Farm day A: audit the rules (Phase 3)

- **Blocks:** 2–3 opened (the user's direction), taken from blocks being loaded out anyway: opening a K ≥ 40 block means lifting about 1,400 trays. Among those, they are picked at random by a rule written in advance, from blocks built before the audit was announced; aim for one large (K ≥ 40), one medium and one with a wall side. Plus 8–10 blocks scanned only.
- **Per opened block:**
  1. Product scan on the camera path: S, L, R, CORNER, and a blind declaration by someone who is not a counter. Record the hash, minutes and paid calls.
  2. Research photos (about 12): a repeat of each face from a step aside (3), the longest face in 2 and in 3 parts (5), close photos of both back corners (2), the other CORNER (1), BACK if reachable (0–1).
  3. Two people count every face stack blind [P].
  4. Open the block: record every hidden stack's position, filled trays, cover tray, partial or empty, blind; and each partial's position against the X × Y rectangle (in the face row, in front, beside).
  5. Photograph each opened layer, for the record only. Note which sides stand against a wall and the camera standoff for each face photo.
- **Scanned-only blocks:** steps 1 and 3, plus a 6-photo research set: a repeat of each face (3), the longest face in 2 parts (2), a close photo of one back corner (1).
- **Research photos before Phase 4 is installed** are keyed to the paper sheet and replayed offline later in one approved batch. With the Phase 2 research capture mode they carry heading, role and part. Taken with the plain phone camera they carry no heading: they then test reading and merging only, and replay gates on them are [R, counterfactual trust].
- **Measured outputs [P]:** interior rule breaks per hidden stack and per block; Σ physical hidden stacks against K × H per block; back-row heights; cover-tray use on faces and inside; where partials stand; face readings against physical counts (today known only against V); app H against the commonest physical full height; declared X and Y against physical; minutes and paid calls per block; person-hours for opening; real repeats, parts and mixed columns for replay.
- **Load-out log (proposed, from farm day A, 4–6 weeks):** for every block loaded out, two counters record each hidden stack by position (filled, cover, partial, empty) on the paper sheet. About 20–30 blocks [E]. It reaches a per-block bound near 10% without opening blocks only for the audit, and the blocks were not built for an audit.

### 8.3 Farm day B: blind pilot of the frozen build (Phase 7)

- About 15 fresh blocks, not used in development, chosen by a rule written in advance (`PREREGISTRATION.md`, as Plan 4 Phase 5; any change ends the run): 4 one-deep rows, 2 small blocks (X ≤ 2), 4–6 deep blocks with interior truth from load-out or build counts, 2 long faces needing parts, 1–2 wall-side blocks.
- The operator uses the app as in production. Recorded per block: answer hash, photos, paid calls, minutes.

### 8.4 What these sample sizes can show [math; PV "Statistics"]

| Result | Supports (95%) |
|---|---|
| 0 rule breaks in 3 / 10 / 30 opened or logged blocks | per-block break rate ≤ 63% / 26% / 10% (1 − 0.05^(1/n)) |
| 0 rule breaks in 70 / 140 / 300 hidden stacks | break rate ≤ 4.3% / 2.1% / 1% per stack (3/n), only if stacks broke the rule independently |
| A 48-stack interior all at H 95% of the time | each stack at H 99.89% of the time (0.95^(1/48)): about 2,800 stacks with 0 breaks |
| 0 wrong in 30 released blocks | ≤ about 10% of blocks wrong |

The farm days can catch a common rule break. They cannot make the interior exact, which is why rule totals stay `estimated`. A block is built at once by one crew, and stacks in one photo share errors; the unit is the block (PV), so the per-block row is the one that counts. Workers who know an audit is coming may stack more carefully; the random pick and the load-out log reduce that.

### 8.5 Pass bars (proposals; tolerances come from Decision 0)

| Bar | Pass |
|---|---|
| S1 wrong `exact` | 0, ever |
| S2 `confirmed`, "verified" or "physically verified" on a rule value | never shown |
| F1 clean face readings vs physical | ≥ 95% exact, ≥ 99% within 1 (today 20/21 against V only) |
| F2 stacks "read the same in two photos" that are wrong | 0; each listed |
| H1 Σ physical hidden stacks vs K × H, per released deep block | within Decision 0; app H against the commonest physical full height reported for every block, with K |
| D1 declared X and Y vs physical | equal on every block (blind declaration by someone who is not a counter) |
| A1 opened or logged blocks with an interior partial or hole | 0, for the rule to stay the default (provisionally, §8.6) |
| A2 back-row stacks at H | all; each exception reported |
| T1 / T2 released deep / one-deep totals | within Decision 0 (proposal: ±1% or ±H, whichever is larger) / exact |
| W1 camera scans that release a total | proposal ≥ 50% |
| C1 paid calls per block | median ≤ 5, maximum 9 |
| M1 operator minutes per block | recorded on both farm days; bar from Decision 0 |

### 8.6 Gates

- **After farm day A:** A1, A2 and D1 pass: the rule stays the default only provisionally, until the load-out log reaches 30 blocks with 0 breaks; Phases 4–6 go to staging as planned. 1–2 breaks: the user decides whether the rule stays, with the measured rate printed in the result. Common breaks: the rule cannot be the default; the user chooses (a) print the measured spread as the error, (b) ask for ELEVATED on such blocks, or (c) return to the Plan 4 product choice. Covers standard on full stacks: H includes the cover and the taller check is tuned.
- **After farm day B:** every bar passes before any wider use.

## 9. Risks and how each is handled

| # | Risk | Size | Measured today | Handled by | What remains |
|---|---|---|---|---|---|
| R1 | Rule broken inside the block | +H per hole, +(H−h) per partial | No. W05 tops "a layer lower in places" [V, Plan 4 §1] | operator exceptions; farm day A | **main residual risk**; stated on every result |
| R2 | H off by one | ±K | W05 H 19 vs 20 = 48 [M vs V]; covers read 10/10/11 [M vs V, AUD] | clean basis on two faces with a back corner, back-corner check, close photo, reference height when K ≥ 8, range; with covers "sometimes" the hidden range of §4.6 is printed (the plurality guard is off) | a bias shared by every H stack; the point estimate can be off by up to K inside the printed range |
| R3 | One over-read or covered stack | +1–3 | 4 × 3 16 among 15s [R]; L-115 23, 22 among 19–20 [M], next to the short 14 (maybe a mixed column, R6) | cannot set H; withheld until a second capture | a real cover tray (Decision 4) |
| R4 | Under-read face stack taken as a partial | missed trays on one stack | 1 of 21 undoubted columns (7 for 15); doubted ones 9 of 21 matched [M vs V, VAL] | repeats; doubted lows shown with their range up to H (Decision 9) | undoubted under-reads |
| R5 | Short partial dropped as a stray | −(Y−1)·H | code only [C] | stray at column spacing → declared X must match | undeclared blocks |
| R6 | Mixed column (partial plus the stack behind) | the default case under rule 1; +(H−h) far away, −h close up [E] | none of the 3 MUTAA face partials was read as itself: W05's 6 where 8 was read (not aligned), L-109's 10 read 17, L-115's 14 (in front of the face) has no column of its own [M vs V, MvB; alignment approximate] | FR13 sweep 0.80–0.97, FR13-side, -corner and -outside; Phase 1b split; Decision 18 | a partial outside the rectangle; a corner partial misread the same way by both photos |
| R7 | Seam error between parts | ±1 stack and ±(Y−1)·H | unmeasured | part index, seam agreement, CORNER width; never the declaration alone | an equal-height face with no CORNER agreement stays withheld |
| R8 | Copy taken as a repeat | false "read twice" | copies [M]; repeats no | hash, 0.8 score, camera-only repeats, Phase 4 field check | shared detector bias |
| R9 | Photos of different blocks mixed | anything (500 for 100) | L-100 [M] | headings, repeat match, time window, declared size | identical neighbouring blocks |
| R10 | Side photo cuts a corner (shift) | about −(X−2)·H | no (code only). Nearest record: the substituted 99-block trio placed a side photo of the (4,0) end at (0,0), flagged only as a one-layer ambiguity [R, `reports/experiment-stack-faces-20261015/README.md`] | corner readings within 1, declared Y, rescan of a cut side | equal heights hide a shift |
| R11 | Sides repeat the front | +400 on a 5 × 1 | 500 for 100 [M] | side check, declared size, CORNER (unchanged) | a wrong declaration |
| R12 | Gallery photos (no heading) | false depth | 33/33 `needs_view` [M] | never a deep total | none for release |
| R13 | Side against a wall | partials in the hidden side column | ef823816 [V] | withheld (Decision 7) | depends on the farm |
| R14 | Stale stored answer for other photos | another scan's total | code [C] | fingerprint v4 | none once built |
| R15 | Time-outs and cost with more photos | no total; money | lease 150 s vs worst case about 182 s for 3 photos, 243 s with CORNER [C]; farm day A runs before Phase 4's parallel calls | cap 9, cache, parallel calls, follow-ups send one photo | §10 |
| R16 | A repeat makes a wrong `exact` | a wrong `exact` (S1) | AUD row 10/10/11 for 11/11/11 layers [M vs V] | repeats, parts and close photos never make `exact` (Decision 17) | none while the rule holds |

## 10. Cost per scan and time

| Scan | Paid detector calls |
|---|---|
| 3 faces (today) | 3 [C] `index.ts:339-340` |
| + CORNER (routine for deep blocks) | 4 [C] `index.ts:351`; a gallery CORNER is wasted today (sent before the check at 1639) |
| ELEVATED | 0 extra [C] `index.ts:355` |
| A retake or follow-up today | 3–4 again [C]: new scan id, every photo resent and inferred again (`scan_session.dart:116-137`; `index.ts:339-340, 351`), no detection cache |
| + one repeat per face / + a close photo | +1 each [E]; a follow-up with the cache: 1 [E] |
| Long face in 2 / 3 parts | +1 / +2 [E] |
| W05-size example: front in 2 parts, CORNER, close photo | 6 [E] |
| Cap per scan | 9 [E] |
| Farm day A | 12 blocks × 4 = 48 live, plus research photos 3 × 12 + 9 × 6 = 90 in a later batch (§8.2): about 140 [E] |
| Farm day B | about 15 × 5 = 75, plus requests [E] |

- **Server time [C]:** inference runs one photo after another, 3 tries of 20 s each (`index.ts:108-122, 339-340`). The worst case for 3 photos is about 182 s, already above `LEASE_MS` 150 s (`index.ts:1856-1865`). CORNER, routine for deep blocks, is a 4th sequential call (`index.ts:351`): about 243 s; `RIM_VERIFY` would add up to 60 s (`index.ts:1862`). Farm day A runs on this sequential path. With 9 photos in sequence it roughly triples [E], so extras need bounded parallel calls (for example 3 at a time), measured with mocked delays in Phase 4.
- **App limits:** `sendTimeout` 150 s (`api_client.dart:69`) and a 3-minute result wait (`:102-118`) must scale with the photo count.
- **Upload:** about 1.5 MB for 3 photos on a Jio LTE link losing 40% of packets [M, 12 Oct, code comment `api_client.dart:66-68`, not re-measured]. 9 photos ≈ 4.5 MB [E, linear], resent in full on each of up to 4 tries (`:93-100`). A follow-up that sends only its new photo (§6) avoids resending the rest. Per-photo upload with a final commit is the safer later design.
- **Operator time [E, unmeasured]:** a W05-size deep block (3 photos, CORNER, typed size, front in 2 parts, one close photo, two result waits) is roughly 10–15 minutes. Farm day A measures it (M1).
- **`RIM_VERIFY`,** if ever turned on, adds one external call per photo (`index.ts:1145-1149`); off by default.

## 11. Open decisions for the user

1. **Replace the 3 Nov default** (hidden = neighbours' face height) with H by the stacking rule. (a) Yes, build now, test on farm day A **(recommended)**; (b) no.
2. **Staging timing.** (a) Deploy 0.7.0 to staging before farm day A, so its scans test the rule live **(recommended)**; (b) wait and replay farm-day photos offline. Also: skip the pending Worker 0.6.0 staging deploy (recommended if Phases 1–2 take about a week or less [E]), or deploy it now for depth-guard field data.
3. **How H is found** (§4.1).
   - (a) Two distinct clean stacks on two different faces, a back corner among them when Y ≥ 2, plurality guard; a side settled by CORNER and declaration counts as its face **(recommended)**. Cost [R readings; rule outcomes E]: the 4 × 3 replay is withheld (one clean stack); S21, S26 and S28 keep their right answers.
   - (a′) As (a), but with the code's strict `trusted`: a side that repeats the front never counts. S21, S26, S28 and S29 and the 4 × 3 are withheld (right answers in the library 11 → 8), and so is every near-square block of near-equal heights until a close photo (Phase 5) adds a second face.
   - (b) Two distinct stacks, any photo: one photo can set H (ef823816: H = 10, but the 18 and 12 are taller, so only a provisional 120 inside, for about 240).
   - (c) As (a), doubted readings allowed: the 4 × 3 gives H = 15 (S, L, R), and the back-left 16 still withholds it as taller.
4. **Cover trays. Answered 5 Nov: sometimes** [U]. A full stack may carry an empty cover tray, inside too. Handled in §4.6: two adjacent full heights, a printed range of up to K for the hidden stacks, the plurality guard off, and the taller check only beyond the pair. Farm day A measures how often covers are used.
5. **A face stack taller than H.** (a) Withhold until a second capture **(recommended)**; (b) release at H with a note.
6. **Back corners.** Is a partial ever placed at a back corner? Never: the check withholds, and a second capture reading the same releases the total with "rule broken at back corner" **(default)**. Sometimes: it only warns.
7. **Wall side.** Can partials stand on a side against a wall? (a) Never: that column is full by the rule, K = (X−1)(Y−1); (b) yes or unknown: withhold **(default until farm day A)**.
8. **Operator-reported exceptions inside.** (a) Honour with a height, withhold without one **(recommended)**; (b) all are conflicts.
9. **Doubted face readings below H.** (a) Kept at their reading, and the result shows how far they could rise: "up to T + D" **(recommended)**; (b) counted as read with no range, as today; (c) rescan that face. Doubted or gap-filled readings matched on only 9 of 21 stacks [M vs V, VAL].
10. **The farm's normal full-height range**, for the range check (off until given).
11. **Wording.** "M stacks read the same in two photos" **(recommended)**, or "verified by two photos", which changes `test/evidence_grid_test.dart:820-823` on purpose.
12. **Photo cap per scan:** 9 (proposed), with at most 2 close photos. Also approve the detector cache by photo hash, stored under the staging prefix of the R2 bucket that production shares.
13. **Depth proof** stays the declared X × Y (Decision 1 corrected, Contract §5), and S27 (Contract §6) stays open. Both matter more under the rule.
14. **Decision 0** (Plan 4 §3, still open): use, acceptable error per block, minimum share released, minutes per block. On W05 one layer of H is 48 trays.
15. **Farm days:** one or two; dates; people (operator, a declarer who is not a counter, counters A and B); the written rule for picking 2–3 opened blocks at random from blocks being loaded out (§8.2); whether to keep the load-out log for 4–6 weeks; whether app 0.7.0 gets the research capture mode before farm day A.
16. **Confirm** that Plan 5 replaces the Plan 4 product choice (A vs B) and Phase 2, and that the Plan 3 rule (no VLM, NeRF or photogrammetry) stays.
17. **`exact` from extra photos.** (a) A repeat, part or close photo never makes a block `exact`; widening it is decided after farm day B shows F2 = 0 on physically counted stacks **(recommended)**; (b) allow it from Phase 4.
18. **Where partials stand.** Only in the face rows, or also in front of or beside the block ("6x6 + a short stack of 14 in front" [V, MvB])? A partial outside the X × Y rectangle cannot be told from one in the face row, and the totals differ by H. If "outside" happens, the declaration needs a field for it.
19. **Reference height.** (a) When K ≥ 8, the operator hand-counts one full face stack and declares it as measured; it only cross-checks H (`reference_height_differs`) **(recommended)**; (b) optional, as in 0.6.0. On W05 one layer of H is 48 trays.

## 12. Not in scope

- **A VLM or any AI visual counter** as a count source (Plan 3 rule; measured disagreement 21 of 29 [V]).
- **Photogrammetry, NeRF, point clouds or meshes.** `/v1/reconstruct` stays diagnostic and staging-only (`index.ts:1771-1846`).
- **Drones and fixed cameras.** The product stays phone-only.
- **Top view by default,** a top-view reader and Plan 4 product B (rule 5). ELEVATED stays optional, never suggested.
- **Reading a BACK photo** (rule 4): the field is reserved and archived only.
- **New neural networks or a detector retrain** (Plan 4 Phase 4 stays separate, with approval).
- **Operator stack correction** on the result screen; eggs or rupees; production (`4c1480e6`).
- **Edits to existing docs.** PV and the 0.6.0 contract are not edited by this plan; a 0.7.0 contract doc is written when Phase 1 is built.
