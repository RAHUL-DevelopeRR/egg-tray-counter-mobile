# Physical validation protocol (0.5.0)

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3), step 10.
**Record formats.** `benchmarks/validation-schema/`.

**Purpose.** Measure what the phone-only grid counter releases, against blind physical counts. Until this pilot has run,
every accuracy figure in the repository is a development figure.

## Counting unit (frozen)
- **One eligible tray** = one physical tray holding eggs. A partly filled tray counts as one.
- **Empty cover trays** are recorded as physical layers but are not eligible.
- **Unknown occupancy stays unknown.** The app does not measure occupancy in 0.5.0.
- **Agree on this unit with every counter before the first block.**

## Roles (three people)
- **Operator.** Declares the block blind, then scans it with the app (STRAIGHT, LEFT, RIGHT; CORNER and ELEVATED
  where possible).
- **Counters A and B.** Count the block by hand independently. Neither sees the app's result or the other's count.
- **Planter.** On some blocks, makes one physical change before the scan and records it on paper, sealed in an
  envelope. Nobody else is told.

## Order of work per block (never show app results before step 4)
1. **Planted error (some blocks).** The planter makes one change and seals the record (`planted_error.schema.json`):
   - removes the top tray of a front-middle stack;
   - removes one interior stack;
   - lowers one interior stack by one tray;
   - leaves an empty tray in the middle of a stack.
2. **Declaration.** The operator fills the app's declaration pane before upload. The app does not show any count yet.
   The declaration is frozen with the scan (`declaration_freeze.schema.json`).
3. **Scan.** STRAIGHT, LEFT and RIGHT, with CORNER and ELEVATED where reachable. Write down the block ID.
4. **Blind recount.** Counters A and B each count every stack: filled trays, empty trays, partly filled trays. For
   interior stacks, dismantle or look from a ladder.
   - They record on the app's manual-count screen, which does not show the app's numbers, using **Counted by** and
     **Second counter**, or on paper (`recount.schema.json`).
   - Where A and B differ, they recount together until they agree. Both original counts are kept.
5. **Unseal and record.** The planted-error envelope is opened. The result is recorded with its hash
   (`result_hash.schema.json`), from the response's `job.pipeline_version` and the scan id.

## Pilot mix (about 30 blocks; a smaller pilot is a development gate, not an accuracy claim)

| Block type | Target |
|---|---|
| Ordinary cross-stacked block, close faces | 8 |
| Far-facing (operator cannot get close) | 3 |
| Wall-bound (one side not reachable) | 3 |
| Corner-bound (two sides against walls) | 2 |
| Interior missing stack (planted) | 4 |
| Unequal stack heights / a partial-height stack | 4 |
| Empty cover trays on top | 3 |
| Planted top-tray removal on a front-middle stack | 3 |

## What is scored
- **Wrong `exact` and wrong `confirmed`.** A released total that is not equal to the reconciled blind count. **The target
  is 0.**
- **Coverage per status:** `exact`, `confirmed`, `estimated`, `conflict`, `needs_view`.
- **Recall of planted errors, per type.** A planted error must never sit inside an `exact` or `confirmed` total.
- **Per-stack agreement** of visible stacks with the blind count, per reading type (`reader`, `pair_type`).
- **Operator time** per block, and declaration errors (declared vs recounted X, Y and interior).

## Statistics
- **The unit is the block.** Stacks in one photo share errors.
- **Report Clopper-Pearson bounds per status.**
  - 0 wrong in n blocks bounds the error rate below 3/n (95%).
  - 30 blocks support about "≤ 10% wrong".
  - "≥ 99%" needs 299 of 299.
- **Keep every record:** scan ids, result hashes, recount sheets, sealed planted-error records.
