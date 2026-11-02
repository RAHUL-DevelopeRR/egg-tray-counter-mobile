# MUTAA validation of build 0.5.0: app vs blind manual counts (1–2 Nov 2026, partial)

**Request:** validate the build on the real MUTAA photos and compare the manual count with the app's count.

**Status: partial.** Every photo went through the app's backend. The blind manual counts are incomplete: usage limits
stopped the counting runs four times. Every figure below says how strong its manual count is.

## Method

**App side (measured).** `scripts/validate_build_staging.py` sent all 94 photos to the **staging Worker 0.5.0**
(version `52a1d5e8`, observe mode), prepared exactly as the app prepares them:
- EXIF-upright, long side 1600 px, JPEG quality 92;
- 3 photos per scan, 33 scans, 99 detector calls;
- the 8 kept MUTAA block sets from `reports/mutaa-manual-vs-backend-20261031` (STRAIGHT, LEFT, RIGHT), then the other
  MUTAA field photos and the 52 labelled photos, three per scan;
- no capture fields, so every scan is a gallery upload of unknown provenance.

The answers are in `raw/`. The prepared photos (`_sent/`, 38 MB of re-encoded field photos) are not committed; the
script regenerates them.

**Manual side (tier V: visual counts by Claude subagents, not physical counts).** Counters were blind:
- each one saw only the photo and its own zoomed crops, no app output or reports;
- handwritten ink marks were ignored.

Three runs, merged by `manual-blind.json`'s per-photo `truth_basis`:

| Run | Protocol | Model | Finished |
|---|---|---|---|
| heavy (`wf_c0153606-a48`) | two counters per photo, different methods (rims; pitch then 5/6 parity), a third recount where they disagree | Opus 5.5 | 9 photos |
| lean 1 (`wf_186c60c6-daa`) | one counter, at most 10 crops, rims with 5/6 parity check | Fable 5.1 | 51 first counts |
| lean 2 (`wf_34d0529c-6b4`) | a second blind counter (pitch then parity) where the app disagrees with the first; a recount where the counters disagree | Opus 5.5 | 28 second counts, 6 recounts |

- The app's readings decided only *whether* a second count was spent. No counter ever saw them.
- Where the two counters disagreed and the recount never ran, only the stacks both counters agree on are scored. The
  disputed stacks are kept at low confidence, so they are never scored.

**Comparison.** `scripts/compare_mutaa_validation.py` writes `comparison.json`.
- Each app column (`walk_count`) is matched to a manual stack by horizontal position.
- A stack is scored only when the counters called it fully countable, at more than low confidence.
- "exact" is against filled trays. The cover-tray column also accepts filled + cover, because the app counts an empty
  top tray as a layer.

## Results

### Staging (measured)

- **All 33 scans returned `needs_view` with no total.** That is the 0.5.0 contract for gallery photos.
- **The photo check accepted 37 photos and refused 57.** Refusal reasons:
  - trays sideways or unclear: 29;
  - too far away: 21;
  - no stacks: 20;
  - stacks too narrow in the frame: 12;
  - pitch changes across the face (angled view): 12.
- **The app read 261 columns, and 135 of them carry a doubt.**

### Manual count coverage (94 photos)

| Manual truth | Photos |
|---|---|
| two blind counters agree | 10 |
| reconciled by a third blind count | 7 |
| partly double-counted (agreed stacks only, recount not done) | 21 |
| one blind count, app agrees | 5 |
| one blind count, app disagrees, second count not done | 13 |
| one blind count, app found no stacks | 7 |
| no manual count yet (all refused by the photo check) | 31 |

### Per stack, photos the photo check accepts (37 photos)

Only stacks with double-counted manual truth are scored: 42 stacks.

| | Stacks | Match | Off by 1 | Off by 2+ |
|---|---|---|---|---|
| all | 42 | 29 | 2 | 11 |
| no doubt, no gap fill | 21 | 20 | 0 | 1 |

- **10 of the 11 large misses carry a doubt or gap fill**, so they cannot verify a stack.
- **One undoubted column is wrong:** IMG_20260916_151409127, a back-block stack at x 0.66, where the app reads 7 and
  the manual count is 15.
- With single counts included (67 scored stacks): 50 match the filled count exactly, 5 are off by 1, 12 are off by
  2 or more.
- The two blind counters disagreed on 21 of the 29 double-counted accepted photos. The manual truth is itself noisy by
  about one tray on 20-high stacks.

### Photos the check refuses (57 photos)

37 stacks are scored. Only 3 match, and 34 carry a doubt. The refusal is doing its job here: these readings are poor.

### Photo totals against the handwritten labels (tier U, 24 labelled photos)

On the 16 accepted labelled photos:
- **the app's photo total equals the label on 10**;
- the manual total equals it on 9.

Notable disagreements:

| Photo | Label | Manual | App |
|---|---|---|---|
| img-32 | 19 | 18 | 31 (doubted) |
| img-36 | 109 | 123 | 115 |
| img-34 | 120 | 113 | 120 |

### Blocks (the 8 kept sets)

Staging gave `needs_view` with no total on every set. No wrong block total was released.

| Set | Manual footprint | Manual total (31 Oct) |
|---|---|---|
| L-100 | 5 x 1 | 100 |
| L-80 | 4 x 1 | 80 |
| L-109-ORANGE | 6 x 3 | 375 |
| L-115 | 6 x 6 | 734 |
| M16-CORNER-STACK | 1 x 1 | 14 |
| M16-FAR | 3 x 5 | 240 |
| M16-NEAR | 4 x 2 | 177 |
| W05-ORANGE | 10 x 7 | 1366 |

### What-if replays (offline, `scripts/replay_mutaa_validation.mjs`, `replay-what-if.json`)

The 8 sets were replayed from the staging detections:
- as sent;
- with an honest declaration;
- as if the photos were guided-camera captures with a quarter turn each way (a counterfactual);
- the camera case with the declaration.

| Build | L-100 as camera captures | With declaration | Every other set and mode |
|---|---|---|---|
| 0.5.0 (historical, 1 Nov) | **`estimated` 500** (truth 100) | `conflict` | `needs_view` |
| 0.5.1 (2 Nov, `replay-what-if.json`) | `needs_view`, asks for a CORNER photo | `needs_view` | `needs_view` |

The 500 was the main blocker found, and the declaration that caught it can be skipped in the app. Worker 0.5.1 fixes
it: a side whose stacks repeat the front no longer gets its depth from the phone heading alone. See
`docs/SCAN_JOBS_AND_DEVICES.md`, "Sides that repeat the front (0.5.1)", and `reports/replay-0.5.1-20261102`.

## Limits

- **The manual counts are tier V** (Claude visual counts), not physical counts. Counters disagree with each other and
  with some handwritten labels by about a tray.
- **The validation is incomplete:**
  - 31 refused photos have no manual count;
  - 21 accepted photos lack the recount;
  - 13 refused photos lack a second count.
- **Lean first counts came from Fable 5.1; the other counts from Opus 5.5.**
- **The production path (guided camera, real headings, real blocks) is not covered** by gallery photos. It needs the
  field pilot in `docs/PHYSICAL_VALIDATION.md`.

## Files

| File | What |
|---|---|
| `raw/*.json` | staging 0.5.0 answers, one per scan, with what was sent |
| `manual-blind.json` | merged blind counts per photo: final stacks, both counters, recount, truth basis |
| `comparison.json` | per-photo and per-stack comparison, summaries, block table |
| `replay-what-if.json` | offline what-if replays of the 8 sets on the current build (0.5.1) |

To reproduce:

```
python scripts/validate_build_staging.py --mutaa C:/Users/rahul/MUTAA --out reports/mutaa-validation-0.5.0-20261101
python scripts/compare_mutaa_validation.py --report reports/mutaa-validation-0.5.0-20261101
node scripts/replay_mutaa_validation.mjs reports/mutaa-validation-0.5.0-20261101
```

The first command needs `EGG_ADMIN_TOKEN`, which is never printed; it reuses saved answers.
