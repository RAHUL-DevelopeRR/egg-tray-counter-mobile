# Worker 0.7.0 stacking rule: offline replay (5 Nov 2026)

Plan 5 Phase 1 (`docs/PLAN_5_MULTI_PHOTO.md` §7), built after the user answered **Decision 1: yes** on 5 Nov.
Hidden stacks are now the block's full height H "by the stacking rule" instead of the 0.6.0 neighbour median.
**Offline only:** nothing deployed or pushed, 0 detector calls. Staging still runs Worker 0.5.0 (`52a1d5e8`), and
production (`4c1480e6`) is untouched. **Physical counts: still zero.** Every "truth" below is synthetic [S] or a label
or visual reading [U, V].

Tags as in Plan 5: [S] synthetic, true by construction; [R] offline replay of saved detections (the camera modes are
counterfactual); [M] measured system output; [V] AI visual count.

## What was built

- `cloudflare-worker/src/index.ts`: `stackingRule()` (H, the cover-tray partner, the checks), `assumeHidden()` now
  sets H, exceptions and the reference check in `assembleGrid()`, `ruleProvisional()`, the new inventory fields, and
  `RULE_DEFAULTS` (one switch per open decision). `PIPELINE_VERSION` is `worker-0.7.0` and `grid_contract` is `0.7.0`.
  The request and the job fingerprint (v3) are unchanged.
- Contract: `docs/GRID_CONTRACT_0.7.0.md`.
- Tests: `cloudflare-worker/test/rule_cases.mjs` (FR01–FR21: 43 cases, counting the FR13 scale sweeps) and
  `test/rule.test.mjs`; app `mobile/test/worker_070_compat_test.dart` with three real 0.7.0 answers in
  `mobile/test/fixtures/worker_0_7_0/`.
- Scripts: `scripts/replay_stacking_rule.mjs` (rule cases and Decision 3 options; older build vs current) and
  `scripts/write_worker_070_fixtures.mjs`.

Default settings: Decision 3 **(a)**, still open (two clean stacks on two faces, a back corner among them; a side
settled by a CORNER photo and the declaration counts). Decision 4 answered "sometimes": cover range on, plurality guard
off. Decisions 5, 6, 7 and 9 at the plan's defaults.

## Files here

| File | What |
|---|---|
| `summary.json`, `details.json` | `scripts/replay_benchmark.mjs`: registry faces, 22 trios, the 38-case library (0.7.0) |
| `compare-0.6.0.json` | `scripts/compare_replay_versions.mjs`: the library, 0.6.0 (`c4b0360` dist) vs 0.7.0 |
| `stacking-rule.json` | `scripts/replay_stacking_rule.mjs`: rule cases 0.6.0 vs 0.7.0, the four Decision 3 options on the rule cases, the library and the saved scans |
| `saved-scans/` | `scripts/replay_saved_scans.mjs`: 3 saved real scans × 4 modes, 0.7.0 |

## Results

### Tests [M, local]
- Worker `npm test`: 270 tests, 238 pass, **0 fail**, 32 todo. Before this change: 214 tests, 210 pass, 0 fail, 4 todo.
  The 28 new todos are the known failures listed below; the 4 old ones are S03, S04, S07 and S29 (stretch checks).
- App `flutter test`: 258 of 258 on two full runs (255 before, plus 3 new); `dart analyze lib test`: no issues. The
  intermittent `pending_scan_test.dart` failure did not appear.

### Plan 5 Phase 1 gates

| Gate | Result |
|---|---|
| 1. `npm test` 0 failures | met: 0 fail |
| 2. 38 old + new cases, 0 wrong `exact`/`confirmed` | met: library 0 confirmed, 1 exact (S18, right); no rule case is exact or confirmed |
| 3. nothing 0.6.0 got right or withheld becomes a wrong released total | met on the library and the saved scans. Not met on the new rule cases: **FR18 and FR14** (below) |
| 4. registry 22 trios 0 wrong, faces unchanged | met: 0 face verdicts changed, 0 of 22 trios changed, 0 wrong releases |
| 5. 99-block 99 in all modes, L-100 withheld in all modes, 4 × 3 as §4.5 | met for the 99-block and L-100; the 4 × 3 matches §4.5 under (a); under (c) it differs from §4.6 (below) |
| 6. released-case table, 0.6.0 vs 0.7.0 | below: library 16 → 15 released (S21 now withheld) |
| 7. fingerprint v3; H13 keys only gain; its step-up case withheld | met (`inside_step_up`) |
| 8. the 0.6.1 parser reads three 0.7.0 answers | met: `worker_070_compat_test.dart`, 3/3 |
| 9. two replay runs give identical hashes | met: `stacking-rule.json` `5a3b1ab2da87a946`, `details.json` `29fbc6e32688a232` (dist `47a9278f1b920dbe`) |
| 10. no deploy, no push, 0 paid calls | met |

### The 38-case library [S, R] (`compare-0.6.0.json`)
- 38 of 38 pass. Released totals: 0.6.0 16, 0.7.0 15. Wrong releases are the same 5 as 0.6.0 (S03, S04, S07, R04: a
  missed tray, already estimates; S29: a hidden hole with no tap, 180 for 160).
- **One answer changed: S21**, from 180 to withheld (`no_rule_height`). Its LEFT and RIGHT detections are identical
  to STRAIGHT's, so the Worker takes them as copies of the front photo, and a copy never sets H. Plan 5 expected S21 to
  keep 180 because it did not notice the copies. The same block with the sides framed differently (FR21) gives 180. S21's
  check changed from `total_ok` to `no_wrong_total`, with this reason in `replay_benchmark.mjs`.

### The rule cases [S] (`stacking-rule.json`)

| Case | Truth | 0.6.0 | 0.7.0 (a) |
|---|---|---|---|
| FR01 base 5 × 3 | 291 | 291 | 291 (range 285–291) |
| FR02 one over-read 21 | 291 | 292 wrong | withheld, retake STRAIGHT; provisional 292 at H 20, 298 at 21 |
| FR03 two over-reads in one photo | 291 | 293 wrong | withheld (taller) |
| FR05 back corner 18 (rule broken) | unknown | 288 | withheld, retake LEFT |
| FR09 / FR10 / FR11 partly empty / step-up / short hint | unknown | 291 / 292 / 271 | withheld for each named reason |
| FR08 declared missing | 271 | 271 | 271 |
| FR15 every reading at the frame edge | 291 | 291 | withheld `no_rule_height` |
| FR16 reference height 21 | 291 | 291 | withheld `reference_height_differs` |
| FR17 covers on some stacks | 295–301 | 296 | 301, range 295–301 |
| FR20 a doubted 19 | 291 | 291 | 291, "up to 292" |
| FR21 S21 with separate captures | 180 | 180 | 180 |
| **FR18** over-reads on two faces (21) | 291 | 294 | **299, range 293–299: wrong, and the range misses the truth** |
| FR04 every face under-read by 2 | 291 | 261 | 261 (residual risk, as planned) |
| FR14 hidden hole, no tap | 271 | 291 | 291 (residual risk, as planned) |
| FR13 / -side / -corner, 8 trays with the stack behind, scales 0.80–0.97 | 279 | withheld to 0.85, then 291 | the same |
| FR13-outside, a partial in front of the block | 299 | 291 | 291 |

0.6.0 released 22 wrong totals over the 43 cases; 0.7.0 releases 19, all in the families above.

**Findings:**
1. **FR18 is worse than in 0.6.0** (299 against 294, truth 291). One over-read on each of two faces lifts H to 21, and
   the 20s become its cover partner. The hidden range 120–126 contains the hidden truth 120, but the two over-read face
   stacks are counted as read, so the printed total range 293–299 misses 291 by 2. Plan 5 §7 says "the true total is
   inside the printed range"; that holds for the hidden stacks only.
2. **FR13 needs Phase 1b.** A short partial in the face row, with the full stack behind it showing above it, reads as
   one full column from scale 0.87 (+12 trays), in 0.6.0 and in 0.7.0 alike. The corner variant is read the same by two
   photos. Plan 5 sets Phase 1b's step threshold from this sweep and farm day A photos; the sweep shows a column-scale
   step of 3–13% would have to be told from perspective, on frontal photos whose top-to-bottom spacing ratio reaches
   1.42 (`MAX_PERSPECTIVE_GRADIENT` note in `index.ts`). Not attempted.
3. FR13-outside (a partial standing in front of the block) is missed by 8, as Decision 18 warns.

### Decision 3: the four options [S, R]

| Option | Library released (wrong) | Rule cases passing | Where it differs from (a) |
|---|---|---|---|
| (a) two faces, back corner (default) | 15 (5) | 24 of 43 | — |
| (a′) strict sides | 12 (4) | 23 | S26 and S28 withheld (right answers lost), S29 withheld; FR21 withheld |
| (b) any photo | 16 (5) | 23 | FR03 released **299 for 291** (two over-reads in one photo set H); S21 released 180 from one photo |
| (c) doubted allowed | 15 (5) | 23 | FR15 released 291 from readings that all touch the frame edge |

On the saved real scans the options differ only on the field 4 × 3 (next section).

### Saved real scans [R] (`saved-scans/`, `stacking-rule.json`)
- **99-block** (`6fe33b1d`): 99 in all four modes, both builds, every option. One deep, so the rule is not used.
- **MUTAA L-100**: withheld in all four modes, both builds, every option (the sides repeat the front).
- **Field 4 × 3** (`9b4c783e`), `camera-corner-declared` (counterfactual headings, a synthetic CORNER photo, the
  declared size): 0.6.0 gave 165. 0.7.0 under (a), (a′) and (b) withholds it (`no_rule_height`, retake LEFT), with the
  provisional figure 165 at the typical face height 15; only STRAIGHT's front-left 15 is clean, and every other reading
  has `end_at_frame_edge`. This is Plan 5 §4.5's prediction. Under (c), H = 15 but the block is still withheld as
  taller: **Plan 5 §4.6's example missed that RIGHT reads 14 at (3, 1).** With doubted readings allowed, 14 becomes the
  partner (the rule tries H − 1 first), so the back-left 16 is a third height that a cover tray cannot explain.
  Provisional: 165 at H 15, 169 at 16. Visual reading [V, FS]: 164 filled, back-left 15 + 1 cover.

## What this does not show
- Nothing here is a physical count. The farm rules are not audited (farm day A, Plan 5 §8.2).
- The camera modes of the saved scans use headings and a CORNER photo these photos never had.
- The synthetic faces are clean; real photos add doubts (on the field 4 × 3, 7 of the 8 readings of standing stacks touch
  the frame edge).
