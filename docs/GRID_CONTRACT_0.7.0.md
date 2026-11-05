# Grid contract 0.7.0: hidden stacks by the stacking rule (Worker 0.7.0)

Written 5 Nov 2026 with Plan 5 Phase 1 (`docs/PLAN_5_MULTI_PHOTO.md`). It changes only what 0.6.0
(`docs/GRID_CONTRACT_0.6.0.md`, not edited) says about hidden stacks; everything else in 0.6.0 stands. **Worker 0.7.0 is
built and tested offline only. It is not deployed:** staging runs 0.5.0 and production `4c1480e6` is untouched.
Replay results: `reports/stacking-rule-0.7.0-20261105/README.md`.

## 1. The rule

The farm's stacking rules, stated by the user on 5 Nov 2026 and **not yet audited**: partial stacks stand only on the
photographed faces (STRAIGHT, LEFT, RIGHT), the back row is always full, and no inside place is ever empty. Cover
trays are used "sometimes" (Decision 4). The user answered Decision 1 "yes" on 5 Nov: hidden stacks follow the rule.

- **Hidden stack** (one no face photo sees): the block's full height H, labelled "full by the stacking rule (not
  seen)". It is never counted, measured, exact, verified or confirmed. K = max(0, X − 2) × (Y − 1) with both sides
  photographed. This replaces 0.6.0's floor of the median of the line-of-sight neighbours, which took half-filled face
  stacks as neighbours (case H2: 0.6.0 released 236; the rule gives 237 and withholds it, below).
- **H** (Decision 3, still open; default (a)): the largest height that two **distinct** face stacks read **cleanly**
  (no doubt, no gap-filled layer, the layer counts agree) on **two different faces**, **one of them a back corner**.
  A stack counts once. Only **rule-eligible** photos count: a guided-camera still, not blocked, not a copy of another
  photo; for a side, the heading confirms a side face (`turned`, or `depth_unproven` while only the declared size is
  missing). A side that repeats the front counts once a CORNER photo and the declaration settle it (`trusted` stays
  false for it, so it never makes a stack read twice).
- **Cover partner**: H − 1 if a clean face stack reads H − 1, else H + 1 if one reads H + 1. The full heights are H and
  the partner. The hidden stacks' range is K × the lower to K × the higher full height. When the faces show only H, the
  range is K × (H − 1) to K × (H + 1).
- **K = 0** (one-deep rows, blocks at most 2 wide): the rule is not used (`block.rule` null) and answers are 0.6.0's.

`RULE_DEFAULTS` in `index.ts` holds one switch per open decision: `basis` (`two_faces` = (a), `strict_sides` = (a′),
`any_photo` = (b), `doubted_allowed` = (c)), `plurality` (off), `coverRange` (on), `taller` (`withhold`), `backCorner`
(`withhold`), `oneSide` (`withhold`), `heightRange` (null). `modelDiagnostics` takes `extras.rule` to override them
offline; nothing in a request sets them.

## 2. Checks: each failure withholds the total and names its reason

| `withheld_reason` | When | Retake named |
|---|---|---|
| `one_side_only` | one side face shows stacks (Decision 7: partials may stand on the unseen side) | the missing side |
| `no_rule_height` | no height meets the H definition | the side with the most doubted readings |
| `rule_height_out_of_range` | H outside the farm's normal range (off) | the basis face |
| `rule_height_ambiguous` | plurality guard (off while covers are "sometimes") | the basis face |
| `stack_taller_than_rule_height` | a face stack above the higher full height, unless a second capture reads it the same | its face |
| `back_corner_below_rule_height` | a clean back-corner reading (or a seen gap) below the lower full height, unless a second capture reads it the same | its side |
| `inside_hint_below_rule` | trays glimpsed through a gap on a hidden cell read below the lower full height | the face that saw them |
| `inside_step_up` | an ELEVATED `step_up` tap on a hidden cell | STRAIGHT (grid-level) |
| `inside_declared_partial` | `interior: "partial"` declared without naming the stacks | STRAIGHT (grid-level) |
| `reference_height_differs` | the declared, measured reference height is not a full height | STRAIGHT (grid-level) |

A withholding check adds a conflict tagged `check: <reason>`; a named stack's cell becomes `conflict`, and its reading
is kept in `block.rule.kept_readings`. `inventory.withheld_reason` is the first rule reason when every conflict comes
from a rule check; any other conflict gives `conflict`. A released taller stack or broken back corner (two captures
agree) adds a note to `block.rule.notes`.

**Operator exceptions** on hidden cells (Decision 8 (a)): declared missing, or ELEVATED `missing`, is 0; a declared
partial with a height is that height. Both are flagged `rule_exception` and listed in `block.rule.exceptions`. A
declared partial without a height, or a `step_down` tap, leaves the height unknown (no total, as in 0.6.0).
`interior: "full"` sets `block.rule.affirmed_by_operator`.

**Doubted face readings below H** (Decision 9 (a)) stay at their reading; `inventory.doubted_low_up_to` = the estimate
if each rose to H.

## 3. Response changes (keys only gain)

- `block.grid_contract` `"0.7.0"`; `pipeline_version` `worker-0.7.0`. Request, views, legacy fields and the job
  fingerprint (version 3) are unchanged.
- Hidden cells: `evidence_class: "assumed"`, `assumed_from: "stacking_rule"`, `assumed_layers` = `z_layers` = H,
  `assumed_range: [H, H]`, `neighbours: []`. Uncertainty: "hidden: full by the stacking rule, not seen; if the rule was
  broken here, this stack can be missing or shorter".
- `block.rule` (null when no stack is hidden, or when the photos are withheld before the grid is built): `applied`,
  `options`, `height`, `partner`, `full_heights`, `range_heights`, `hidden_stacks`, `basis` (`{x, y, face, layers}` ×
  2), `stacks_at_height`, `taller`, `back_corners`, `plurality`, `hints_below`, `doubted_low`, `kept_readings`,
  `one_side`, `withheld_reason`, `notes`, `exceptions`, `affirmed_by_operator`, `provisional`.
- `block.rule.provisional` (rule withholds only; **never a total**): `kind`, `reason`, `counted_on_faces`,
  `rule_height`, `hidden_stacks_at_rule`, `at_rule_height`, `at_rule_range`, `at_taller {height, estimated_total}`,
  `at_typical_face_height {height, estimated_total}` (when no H). `inventory.provisional` stays for depth withholds
  only, because app 0.6.x titles any inventory provisional "DEPTH NOT PROVEN".
- Inventory, new: `rule_stacks`, `rule_height`, `rule_trays` (= rule_stacks × H), `rule_trays_range`,
  `rule_full_heights`, `sensitivity_per_layer` (one layer of H moves the total by this), `rule_exceptions`,
  `doubted_low_stacks`, `doubted_low_up_to`, `two_photo_stacks` (face stacks read the same, cleanly, by two captures; in
  stacks). For a rule block, `assumed_range` and `estimated_range` are **null**. The note reads "N counted on faces; K
  hidden stacks x H = R full by the stacking rule (not seen); cover trays are sometimes used: the hidden stacks hold A
  to B tray layers".
- `suggested_views` never contains `"elevated"` (farm rule 5); `["corner"]` and `suggested_inputs` are unchanged.
- `block.total_eggs` stays null whenever a stack is assumed.

## 4. Compatibility

| Pair | Behaviour | Checked by |
|---|---|---|
| App 0.6.0+29 / 0.6.1+30 with Worker 0.7.0 | Rule cells parse and draw as assumed; the split line reads "Counted N + Assumed K·H (range not given) = Estimated T"; no neighbour range row; a rule withhold shows the generic withheld line, no provisional panel; RETAKE names STRAIGHT, LEFT or RIGHT | `mobile/test/worker_070_compat_test.dart` (3 real answers) |
| Uploads without capture provenance (no `source` / `blocked`) | can never set H, so a deep block is withheld (`no_rule_height`); before 0.7.0 they only could not verify a stack | `capture.test.mjs` |
| Photos the copy check marks as copies | never set H (a copy is not a second face) | `rule.test.mjs` (S21 / FR21) |
| Stored jobs | a finished job replays its stored 0.6.0 / 0.5.0 answer | unchanged |

## 5. Open

Decision 3 (how strict H is) is still the user's call. Phase 1b (a column mixing a face partial with the stack behind)
and Decision 18 (partials standing outside the X × Y rectangle) are open; see the report's findings.
