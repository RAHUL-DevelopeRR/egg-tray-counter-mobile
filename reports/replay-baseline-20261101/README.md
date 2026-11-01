# Offline replay: Worker 0.4.13 baseline and 0.4.14 (release contract), 1 Nov 2026

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md`, Phases A, C and D1.

**Method.** The inputs are `benchmarks/registry-20261101`. Scoring is done by
`cloudflare-worker/test/replay_benchmark.mjs`, which runs the Worker's own dist build on saved detections.
- No inference, no network, no deploy.
- **Every number below is measured (M) on development data**, apart from the two untouched photos. None of it is
  proof of field accuracy.
- Output files:
  - this folder for the 0.4.13 baseline;
  - `reports/replay-phase-c-20261101/` for 0.4.14 (`summary.json` and `details.json` in each).

## Faces (one photo on its own: capture gate plus per-column retake reasons)

These are unchanged between 0.4.13 and 0.4.14: the new rules never refuse a face, they only stop it from verifying.

| Group | Accepted / n | Accepted and correct | Wrong |
|---|---|---|---|
| Labelled photos, U, one per near-duplicate cluster | 10 / 22 | 9 | img-30: 78 for 80 |
| MUTAA re-encodes of labelled photos, U | 4 / 7 | 3 | L-80 STRAIGHT (img-30 re-encoded): 79 for 80 |
| MUTAA re-encodes, V (filled + empty trays) | 2 / 4 | 0 | L-100: 100 for 101 (V counts one empty tray; U says 100); L-80: 79 for 80 |
| MUTAA phone photos, V | 1 / 2 | 1 | – |
| Untouched (img-47, img-49), U | 1 / 2 | 1 | – |

**Parity.** The TypeScript per-face verdict equals the Python evaluation of the 0.4.11 logic
(`reports/eval-20261015/results.json`) on all 52 labelled photos: outcome and total, 0 mismatches. That evaluation
replayed exactly the 15 Oct numbers (10 accepted, 9 correct, img-30 wrong).

**Re-encode stability.** The same photo sent through the app's 1600 px re-encode changed its count in 7 of 10
views; img-30 went from 78 to 79. A face count is therefore not stable to ±1 under re-encoding.

## Three-view replays (22 records, 14 sets)

| | 0.4.13 | 0.4.14 |
|---|---|---|
| Released totals | 4, all the 99-block (substituted sides): `estimated` 99 = U 99 | the same 4 |
| Wrong releases (a total ≠ truth, or a total from a non-genuine set with unknown truth) | 0 | 0 |
| Wrong `exact` | 0 | 0 |

## Adversarial library (18 cases, tier S, plus real detections with synthetic headings)

| Case | 0.4.13 | 0.4.14 |
|---|---|---|
| S03, S04: top or bottom tray of a front-middle stack missed (truth 80) | **`exact` 79** | `estimated` 79 |
| S07: two front stacks merged into one column (truth 80) | **`exact` 60** | `estimated` 60 |
| S01: genuine 4x1, all 20 | `exact` 80 | `estimated` 80: middle stacks are seen by one photo only |
| S11b: back face (180°) sent as LEFT of a square block | `estimated` 180 (the counts cannot tell) | withheld (`faces_back`) |
| S14 / R02: side photos of *another* block, phone really turned | `estimated` 240 / 500 | unchanged: needs Phase F (declared X and Y) |
| Every other case (L-100 gallery, front re-shot, swapped sides, M16-FAR, ...) | pass | pass |

- **Contract checks:** 0.4.13 failed 5 cases. 0.4.14 fails 2, both planned for Phase F.
- **Stretch checks**, which require that an *estimate* is also right, still fail:
  - S03 and S04: Phase E, the independent pixel counter;
  - S07: Phase F;
  - S09, a missing interior stack: Phase H, a top view or physical count.

## What 0.4.14 changes (cloudflare-worker/src/index.ts)

- **When a stack is verified.** Only when two different photos read it the same, with no gap-filled layer and no
  doubt. **`exact` now needs every visible stack verified**, so a stack seen by one photo only makes the block
  `estimated`.
  - New block fields: `visible_verified_trays`, `visible_single_reading_trays`, `single_reading_cells`, and
    per-cell `verified` and `readings`.
- **Doubts per column**, from the Phase B taxonomy (`reports/miss-taxonomy-20261101`):
  - `box_over_two_stacks`, `box_over_two_trays`, `end_box_cut_short` and `bottom_above_floor`.
  - They flag all 4 known silent misses: img-30 stacks 2 and 4 and L-80 stack 4 on accepted faces, and L-109 stack 4
    on a refused face.
  - On the 82 accepted columns, 14 are flagged. That is the 3 misses plus 11 others: 7 known to be correct, and 4
    whose truth is unknown or not usable.
  - A doubt never refuses a count; it only stops that reading verifying a stack.
- **Stray groups.** Groups of 1–2 boxes are reported per view (`stray_groups`). A face with any makes the block an
  estimate.
- **Back faces.** A side turned more than 135° from STRAIGHT is refused (`faces_back`). The turn direction is
  recorded (`direction_ok`) but not enforced until a phone confirms the sign.
- **Headings are kept.** They are archived in the R2 metadata of each photo and form part of the job fingerprint
  (version 3). Version 2 jobs still replay.

**Cost.** Coverage of `exact` falls sharply. Until Phase E gives front-middle stacks a second reading, only blocks
whose every visible stack is a corner seen twice can be `exact`; in practice, one-stack and two-stack-wide blocks.
That is the honest state.
