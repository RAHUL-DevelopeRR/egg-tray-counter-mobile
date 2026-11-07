# Evidence grid and hidden-tray calculation: wire contract (Worker 0.6.0, grid contract 0.6.0)

Plan 4 Phase 3 (`docs/PLAN_4_EVIDENCE_GRID.md`) and the Worker side of app work 4b. It extends
`docs/GRID_CONTRACT_0.5.0.md`: every field app 0.5.0 parses stays, with the same meaning. Local build only; not
deployed.

**Deploy gate.** Do not deploy Worker 0.6.0 (staging included) before an app that reads `suggested_inputs` ships
(app work 4b). App 0.5.x shows "RETAKE <SIDE>" for a `depth_unproven` side (`rescan.recommended_view` is the side's
name); retaking the photo can never release such a block, only declaring the block size can. App 0.5.x does show the
rescan reason, which says to declare the size.

**The idea.**
- A stack whose face was photographed gets a **counted** height, read top to floor. This is the only real count.
- A stack that no face photo sees gets an **assumed** height: the median of its line-of-sight neighbours. Assumed
  trays are kept apart and labelled, never counted.
- A top-view tap changes only two things: presence (a hole sets the stack to 0) and a step up (it raises the lower
  bound). It never counts.
- Rows standing against a block look the same in every photo, a CORNER photo included. So any depth over one stack
  needs the operator's declared block size.
- Deep blocks top out at `estimated`. Nothing is ever `confirmed`.

Decisions taken by the user (3 Nov 2026): deep-block totals are estimates, never confirmed (Decision 2a); hidden
stacks are shown as assumed at their neighbours' face height, apart from the counted ones; everything is in tray layers,
never eggs or rupees.

---

## 1. What the top view is for

**It is for:**
- **finding holes inside the block.** Each missing hidden stack is an overcount of 15–20 trays;
- **flagging hidden stacks that are taller** than their neighbours;
- **confirming that hidden stacks are there;**
- **cross-checking X and Y against the faces,** but only when the tap grid is sized from the photo. When a declaration
  exists, the app sizes the grid from it, and `top_view.agrees` then only repeats the declaration.

**It cannot:** count layers, see a one-tray step down on far rows, or prove a depth.

**Rules.**
1. A tap never sets or changes a measured count. On a measured stack, `missing` is a conflict and a step adds a note.
2. `missing` on a hidden cell sets it to 0. This is the only way a top view lowers a total, and it removes whole stacks
   only.
3. `present` confirms presence only. The height stays at the neighbour median and the range is not narrowed, except
   that a lower bound of 0 becomes 1.
4. `step_up` raises the lower bound to the lowest neighbour + 1 and opens the upper bound. The assumed height is the
   median + 1.
5. `step_down` makes the height unknown, with range [1, highest neighbour], and the total is withheld
   (`height_unknown`). Nothing ever infers a step down from missing evidence.
6. `unsure` or no tap: no effect (flag `top_unsure`).
7. The tap-grid size must match the faces, or it is a conflict. Taps never set `depth_basis`.
8. Taps never raise the status. Taps that disagree with each other or with the declaration are a conflict.
9. The ELEVATED photo is suggested while unchecked hidden stacks exist. It is never required for a total.

---

## 2. Upload

As in 0.5.0. One addition: `elevated_taps` accepts the state `step_up`.

```json
{"x": 5, "y": 3, "cells": [{"x": 2, "y": 1, "state": "present|missing|step_up|step_down|unsure"}]}
```
A 0.5.1 server drops `step_up` as an unknown state, which is harmless. A repeated identical tap on one cell is dropped;
two different taps on one cell are a conflict.

---

## 3. Response additions

### 3a. Each `block.grid[y][x]`

| Field | Type | Rule |
|---|---|---|
| `evidence_class` | `measured`\|`seen_empty`\|`top_present`\|`top_step`\|`top_missing`\|`declared_missing`\|`assumed`\|`conflict` | Never null. `conflict` means the readings disagree or need a rescan (`z_layers` is null) |
| `hidden` | bool | True when no face reading counts the cell. This includes a cell seen only through a gap |
| `assumed_layers` | int\|null | Set on present hidden cells only. Null when the height is unknown |
| `assumed_range` | `[int, int\|null]`\|null | The spread of the neighbours, **not a bound on the truth**. The upper value is null after a step up |
| `assumed_from` | `neighbours`\|`face_typical`\|`declared_partial`\|null | Where the assumed height came from |
| `neighbours` | `[{x, y, layers}]` | The measured line-of-sight cells used |
| `top_tap` | `present`\|`missing`\|`step_up`\|`step_down`\|`unsure`\|null | The operator's tap on this cell |
| `flags` | string[] | `single_neighbour`, `no_neighbour`, `step_up_count_unknown`, `step_down_count_unknown`, `top_unsure`, `declared_present`, `line_of_sight_past_gap`, `single_reading` |
| `past_gap_layers`, `past_gap_scale` | int\|null, number\|null | Trays seen through a gap in front of this cell, and their pitch relative to the face (2 decimals). A hint only: never counted and never used as a neighbour |

**Legacy `status` for each class** (app 0.5.0 colours cells by it):

| Class | Legacy `status` |
|---|---|
| `measured` | `verified` or `observed` |
| `seen_empty` | `missing` |
| `assumed` | `computed`. A declared partial stack is `declared`, or `unknown` when no height was given |
| `top_present`, `top_step` from a step up, `top_missing` | `top_view` |
| `top_step` from a step down | `unknown` |
| `declared_missing` | `declared` |
| `conflict` | `conflict` or `rescan` |

On a present hidden cell, `z_layers` equals `assumed_layers`.

**`measurement_sources`** keeps its vocabulary:

| Class | Sources |
|---|---|
| `measured`, `seen_empty` | `["observed"]` |
| `assumed` | `["computed"]`, plus `"declared"` when declared present or partial |
| `top_present`, step up | `["top_view", "computed"]` |
| step down, `top_missing` | `["top_view"]` (plus `"declared"` when also declared missing) |
| `declared_missing` | `["declared"]` |

The uncertainty on a hidden cell reads: "hidden: height assumed from its neighbours' face heights; it can be
missing, shorter or taller".

### 3b. `block.inventory`

The legacy fields (`physical_layers_*`, `eligible_egg_trays`, `empty_cover_layers`, `unknown_occupancy_layers`,
`unknown_cells`) always describe the grid that is returned. Added:

```json
{"unit": "tray_layers", "released": true, "withheld_reason": null, "provisional": null,
 "counted_trays": 157, "counted_stacks": 8,
 "assumed_trays": 79, "assumed_range": [75, 80], "assumed_stacks": 4,
 "estimated_total": 236, "estimated_range": [232, 237],
 "hidden_stacks": 4, "hidden_stacks_top_checked": 0, "unchecked_hidden_stacks": 4,
 "missing_stacks": {"seen_empty": 0, "top_missing": 0, "declared_missing": 0},
 "cover_trays": {"value": null, "basis": "unknown"},
 "note": "157 counted on faces; 79 assumed in 4 hidden stacks, none checked from the top"}
```

**Release.**
- `released` equals `block.total_trays !== null`.
- `withheld_reason`: null, or one of `height_unknown`, `conflict`, `needs_view`, `depth_unproven`,
  `side_repeats_front`.

**Null rules.**
- Every new number is non-null only when the status is `exact` or `estimated`.
- Within that, `assumed_trays` and `estimated_total` are null when a present hidden cell has no height.
- `assumed_range[1]` and `estimated_range[1]` are null when a step up leaves the top open.

**Counts.**
- `assumed_stacks`: hidden cells with `stack_present !== false` (`assumed`, `top_present`, `top_step`, declared partial).
- `hidden_stacks_top_checked`: hidden cells with any tap except `unsure`.
- `unchecked_hidden_stacks`: present hidden cells with no tap, or only `unsure`.

**What the range means.**
- `counted_trays` is the only floor, and there is no ceiling.
- `estimated_range` means "if every hidden stack is there at its neighbours' heights". It is **never a bound**: it
  ignores holes, and one missing hidden stack is 15–20 trays. A client never prints it bare.

**Eligible egg trays.** `eligible_egg_trays.value` is set only when occupancy is declared `egg_filled`, `cover_trays` is
not `yes`, `assumed_stacks` is 0, no height is unknown, and the block is released. Otherwise it is
`{value: null, basis: "unknown", note}`, for example "hidden stacks are assumed: their trays are not counted".
`cover_trays` copies `empty_cover_layers`; cover trays are known only from the declaration.

**`provisional`** is set only for a block withheld for its depth (every faulty side is `depth_unproven` or
`turned_repeats_front`, and no photo was refused):

```json
"provisional": {"kind": "depth_unproven", "reason": "<first faulty side's reason>",
  "front_row_counted": 100,
  "if_depth": {"y": 3, "counted_trays": 180, "assumed_trays": 120, "assumed_stacks": 6, "estimated_total": 300}}
```
- `kind` is `side_repeats_front` when any faulty side is `turned_repeats_front`.
- `front_row_counted`: the sum of STRAIGHT's non-recessed columns; null when any STRAIGHT column fails its count check.
- `if_depth`: the block as the sides read it, with the taps but no declaration and no CORNER photo. Set only for
  `depth_unproven`, with no block conflict and an `estimated` result. Always null for `side_repeats_front`: those
  sides may be the front again (MUTAA L-100 would read 500).
- The block itself stays withheld: `grid: []`, `cells: []`, `depth: null`, `total_trays: null`. A client never puts
  provisional figures in a headline, a history total or an export.

### 3c. Other block fields
- `depth_basis`: `one_deep`, `declaration`, `corner_and_declaration`, or null. `corner` appears only under the
  non-default `DEPTH_PROOF = "corner_or_declaration"`.
- `suggested_inputs`: `["declaration"]` when a side is `depth_unproven` or `turned_repeats_front` and no agreeing
  declaration was sent. Never in `suggested_views` (app 0.5.0 would show a "DECLARATION photo").
- `suggested_views`: `["elevated"]` while an estimate has unchecked hidden stacks and no ELEVATED photo or taps were
  sent; `["corner"]` when the remaining side faults need only a CORNER photo or the declared size, and at least one
  needs the CORNER photo. A wrong-way side is retaken first.
- `computed_trays`: the sum of the known `z_layers` of present hidden cells, after taps and the declaration. An integer
  even when a height is unknown.
- `observed_trays` equals `counted_trays`.
- The hidden entries of the legacy `block.cells` take the grid's `z_layers`, with status `missing` when the stack was
  removed, so a client adding up cells gets the per-stack values the total uses.
- `side_check[side]` gains the status `depth_unproven`, `corner_settles: true` (a CORNER photo settled a side that
  repeats the front), `depth_witness`, and `retake: "declaration"`.
- `confirmed_basis` is always `[]`. `grid_contract` is `"0.6.0"`. `pipeline_version` is `worker-0.6.0`.

---

## 4. How hidden trays are calculated

1. **Footprint.** X from STRAIGHT's columns (measured-empty cells included), Y from the side faces. A declared X or Y
   that disagrees with the faces is a conflict.
2. **Hidden cells** are those no face photo counts: `max(0, X−2)·(Y−1)` with both sides photographed,
   `max(0, X−1)·(Y−1)` with one.
3. **Trays seen through a gap are never readings** (they are usually another stack or block behind). The cell behind a
   set-back stack stays hidden with `past_gap_layers` and `line_of_sight_past_gap`, and its range starts at 0. Two
   different through-gap heights on one hidden cell are a conflict; a through-gap height on a measured cell is dropped
   (an ambiguity when it differs); with no room behind the gap, an ambiguity, and the gap counts 0.
4. **Assumed height.** For each hidden cell, the measured line-of-sight neighbours are the front stack in its column and
   the side end stacks in its row. Assumed = median of their heights, rounded down; range = [min, max];
   `single_neighbour` when only one. With none: the block's typical face height (the mode of the measured stacks, each
   stack once, ties to the lower), range = all measured heights, `no_neighbour`.
5. **Top view, then the declaration** (section 1 and below). The declaration never overrides a tap.
6. **Totals.** `total` = Σ `z_layers` (null when a present cell has no height). `estimated_range` = counted + Σ range.

**Declaration on hidden cells.**
- `missing_cells`: `declared_missing`, z 0. On a cell already `top_missing`, it only adds `"declared"`. On a measured
  stack, a conflict.
- `partial_stacks`: assumed height `p.layers`, range `[p, p]`, `assumed_from: declared_partial`. With no height: z
  null, range `[1, max neighbour]` (or the step's range). A partial stack of 0 trays is read as a declared missing stack.
  Repeated identical entries are dropped.
- `interior: "full"`: flag `declared_present` and source `"declared"` on present hidden cells. It never resolves a cell.
- `interior: "partial"`: hidden cells with no tap (or `unsure`) and no declared partial get lower bound 0; `top_present`
  cells get lower bound 1.
- **Conflicts:** declared missing against a `present` or step tap; declared partial against a `missing` tap; a declared
  partial height below a step-up lower bound or above a step-down maximum; `interior: full` against a `missing` tap on
  a cell not declared missing; two different declared partial heights for one stack; a declared partial stack (with or
  without a height) where a face shows a gap.

**Worked example (H2).** 4 x 3, front 20/19/20/20, LEFT 20/20/18, RIGHT 20/20/20. Hidden (1,1): neighbours 19, 20, 20 →
20 [19, 20]; (2,1) → 20 [20, 20]; (1,2): 19, 18, 20 → 19 [18, 20]; (2,2): 20, 18, 20 → 20 [18, 20]. Counted 157,
assumed 79, estimate 236, "if every hidden stack is there at its neighbours' heights" 232–237. (0.5.0 gave 237.)

---

## 5. Depth proof and statuses

**Depth proof** (Plan 4 Decision 1, corrected: a design default awaiting the user's call, section 6). `DEPTH_PROOF = "declaration"`. A CORNER photo cannot prove depth:
`cornerReading` counts the columns on each side of the largest-pitch stack, so a CORNER photo of a 5x1 row with two
rows standing behind it (S25) sees the same three-deep end the side photo saw and reads 5 x 3 (0.5.1: `estimated` 300;
truth 100). For a turned side more than one stack deep, when the other side has no stacks or the same depth:

| Side | No agreeing declaration | Declaration `x = front width, y = this side's depth` |
|---|---|---|
| does not repeat the front | `depth_unproven` | `turned`, `depth_witness: declaration` |
| repeats the front, CORNER photo settles it | `depth_unproven`, `corner_settles` | `turned`, `depth_witness: corner_and_declaration` |
| repeats the front, not settled | `turned_repeats_front` (0.5.1) | `turned_repeats_front` (0.5.1) |

LEFT and RIGHT of different depths stay `turned`; the block is a conflict ("depth differs between LEFT and RIGHT
faces"). The photos cannot tell which side is wrong, so `rescan` names no side: `recommended_view: "straight"` with the
general reason, as in 0.5.1. A `depth_unproven`
side's reason tells the operator to declare the block size (X x Y) before the scan, and names a declaration that
disagrees. `rescan.recommended_view` stays the side's name. A side shot twice (LEFT and RIGHT facing one way) is still
caught and retaken first.

| Status | 0.6.0 rule |
|---|---|
| `exact` | `depth_basis` is `one_deep`, and every present stack and every gap is read the same by two captures |
| `confirmed` | **Never.** The 0.5 declaration and flush-top paths are removed |
| `estimated` | No conflict, depth proven, and a hidden cell, a single-reading stack, an ambiguity, or Y > 1. `total_trays` may be null (`height_unknown`) |
| `conflict` | As in 0.5, plus the new tap and declaration conflicts |
| `needs_view` | As in 0.5, plus `depth_unproven`. A refused photo keeps `needs_view` |

Older history rows that say `confirmed` are still valid JSON; clients show them as an estimate.

---

## 6. Open points (for the user)

- **Every block more than one stack deep needs a declared size.** A habitual "5 x 3" declared for a 5 x 1 row with two
  rows touching it still gives 300. That is the operator's call: only the operator can say where a block ends.
- **A side that repeats the front still needs a CORNER photo** as well as the declaration.
- **`exact` is for one-deep blocks only.** Plan 4 Phase 3 allowed one-wide deep blocks; the 3 Nov default overrides it.
- **Trays seen through a gap are hints.** This changed three block tests and turned one "no room" conflict into a
  released estimate.
- **Two different through-gap heights on one hidden cell are still a conflict** (as designed, section 4 step 3). By the
  rule that trays seen through a gap are never readings, they could instead be an ambiguity that keeps only the hint: no
  rescan can resolve the conflict.
- **A declared size can confirm the depth the side photos read, never shorten it.** An honest 5 x 1 declaration for a
  row with two rows touching it (S27) is withheld for good, with only `provisional.front_row_counted`. The option: when
  the declared X matches and the declared Y is smaller than the side depth, count the first Y side columns.
- **`block.total_eggs`** (tray capacity, kept for app 0.5.0) is null whenever any tray is assumed. Clients built on this
  contract never show it: everything is in tray layers.

Measured on the offline replay library: `reports/evidence-grid-0.6.0-20261103/README.md`.
