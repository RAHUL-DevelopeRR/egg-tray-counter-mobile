# Worker 0.6.0 evidence grid: offline replay, 0.5.1 vs 0.6.0 (3 Nov 2026)

Contract: `docs/GRID_CONTRACT_0.6.0.md`. Local build on branch `real/worker-0.6.0`; **not deployed**. Everything here
is offline: saved detections and synthetic faces through the Worker's own functions. No detector call, no network.

**All figures are development figures.** The adversarial library is synthetic (tier S) apart from three saved MUTAA
trios. No physical count exists for any block here; the 4 x 3 field block's "164" is a visual reading (tier V).

## How it was run

```
cd cloudflare-worker && npm test                                   # tsc build, then node --test
node scripts/replay_benchmark.mjs --out reports/evidence-grid-0.6.0-20261103
node scripts/compare_replay_versions.mjs <0.5.1 build> worker-0.5.1 reports/evidence-grid-0.6.0-20261103/compare-0.5.1.json \
  reports/evidence-grid-0.6.0-20261103/summary.json 10f2c3d
node scripts/replay_saved_scans.mjs reports/evidence-grid-0.6.0-20261103/saved-scans reports/evidence-grid-0.6.0-20261103/summary.json
```
Run in this order: `replay_benchmark.mjs` rewrites `summary.json`, and the other two add `comparison_with_worker_0_5_1`
and `saved_scans` to it. Re-run after the review fixes of 3 Nov: `summary.json` and `compare-0.5.1.json` came out
byte for byte the same; `details.json` changed only in S09's stretch (`fixed_by` null: a guard now), and the 4 x 3
`camera-corner-declared` response only in `block.total_eggs` (null: no capacity figure when trays are assumed).
The 0.5.1 build is `cloudflare-worker/src/index.ts` at `10f2c3d`, transpiled with the repo's TypeScript; both builds
run the **same** library (the 0.6.0 one, 38 cases), so the rows compare like for like.

## Results

| | Worker 0.5.1 | Worker 0.6.0 |
|---|---|---|
| Adversarial cases passing (38) | 36 | **38** |
| Wrong `exact` or `confirmed` (adversarial and trios) | 0 | **0** |
| `confirmed` returned anywhere | 0 here; reachable via declaration or flush-top taps | **never** (path removed) |
| Released totals, adversarial | 18 | 16 |
| ...of which wrong (estimates) | 7 | 5 |
| ...of which right | 11 | 11 |
| Saved trios (22): released / wrong / wrong `exact` | 4 / 0 / 0 | 4 / 0 / 0 (unchanged) |
| Labelled faces (52 photos, 22 clusters): verdicts | 10/22 clusters accepted | unchanged (0 face verdicts differ) |

**Coverage of right answers is unchanged (11 of 38); the two dropped releases were both wrong:**
- **S25** (5 x 1 row with two rows standing behind it, real turn): 0.5.1 `estimated` 300 for 100 → 0.6.0 withheld,
  `depth_unproven`, asking for the declared size.
- **S25C** (S25 plus a CORNER photo, which sees the same touching rows and reads 5 x 3): 0.5.1 `estimated` 300 for 100
  → 0.6.0 withheld. A CORNER photo cannot prove a depth.
- **S27** (S25 with the honest 5 x 1 declaration): 0.5.1 `conflict` → 0.6.0 `needs_view`; the reason names "the
  declaration says 5 x 1". Withheld either way.

**Wrong estimates still released by 0.6.0** (all `estimated`, none `exact`; expected by the contract):
- S03, S04: a front tray missed by the detector (79 for 80); S07: two front stacks merged (60 for 80); R04 (79 for 80).
  These are face-reading errors (Plan 4 Phases E/F), unchanged from 0.5.1.
- **S29**: a 3 x 3 block with its interior stack missing, CORNER photo and declared 3 x 3, no top view: 180 for 160.
  The photos cannot see the hole; the inventory says so ("140 counted on faces; 40 assumed in 2 hidden stacks, none
  checked from the top", and `suggested_views: ["elevated"]`). An ELEVATED tap `missing` on the absent stack gives 160
  (checked offline; S28 shows the same on a 3 x 2: 100).

**The cost of the declared-size rule (measured):** S21 as the 0.5.1 library had it (square 3 x 3, CORNER photo, no
declaration) was `estimated` 180 (right) in 0.5.1 and is withheld in 0.6.0 until the size is declared. With the 3 x 3
declaration it is 180 again. Every block more than one stack deep now needs a declared size.

## Saved scans replayed (`saved-scans/`)

The three real scans the app demo bundles, re-answered by 0.6.0 from the detections the server returned. Keys starting
with `_` and local paths are removed. Modes: `as-sent` (as uploaded: no provenance, no declaration); `camera`,
`camera-declared`, `camera-corner-declared` are **counterfactual** (the photos never had camera headings; the CORNER
photo is synthetic and reads the declared size).

| Scan | as-sent | camera | camera + declared | camera + CORNER + declared |
|---|---|---|---|---|
| 99-block (6fe33b1d), 5 x 1, 99 | `estimated` 99 (99 counted, one-deep) | 99 | 99 | 99 |
| 4 x 3 field block (9b4c783e) | withheld (no heading) | withheld: sides repeat the front; front row 45 | withheld | **`estimated` 165 = 105 counted + 60 assumed in 4 hidden stacks; range 163–167** |
| MUTAA L-100, 5 x 1, 100 | withheld (repeats front) | withheld; front row 100, no what-if | withheld | withheld (the CORNER photo reads 5 x 1, the sides are the front again) |

On the 4 x 3 block (front 15/15/15 with the front-right stack missing; LEFT 16/15/16; RIGHT 14/15 behind the gap):
the hidden stacks are assumed at 15 (neighbours 14–15 in row 1, 15–16 in row 2). The visual reading was 164 filled
(tier V), inside 163–167. 0.4.x gave the same 165 by putting every hidden stack at the median face height; 0.6.0 also
says which trays are counted and which assumed, and that no hidden stack was checked from the top.

## Files

- `summary.json`: the replay summary (as `reports/replay-0.5.1-20261102`) plus `comparison_with_worker_0_5_1` and
  `saved_scans`.
- `details.json`: every face, trio and adversarial case.
- `compare-0.5.1.json`: per-case answers of both builds on the 0.6.0 library.
- `saved-scans/`: 12 full 0.6.0 responses and `index.json`.
