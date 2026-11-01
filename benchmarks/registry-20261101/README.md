# Replay registry 2026-11-01

**What it is.** Every saved detector output that the offline replay benchmark scores, with its truth and its
provenance. Plan: `C:\Users\rahul\.claude\plans\spicy-growing-flame.md`, Phase A.

**How it is built.** The build is deterministic and uses no network or inference:
1. `scripts/registry_near_duplicates.py` writes `near_duplicates.json` (needs Pillow).
2. `scripts/build_replay_registry.mjs` writes `manifest.json`.

**How it is scored.** `cloudflare-worker/test/replay_benchmark.mjs` runs the Worker's own functions (the dist build)
on every entry:
- `npm test` asserts the safety invariants;
- `node scripts/replay_benchmark.mjs --out <dir>` writes the full report.

## Contents (measured)

- **72 faces:**
  - 52 labelled photos: 24 usable labels and 28 not-usable labels (secondary).
  - 20 views from the 31 Oct MUTAA sets, 10 of which are re-encodes of labelled photos.
- **22 three-view replays of 14 sets:**
  - the 8 MUTAA sets of 31 Oct (staging 0.4.12 responses, copied into
    `reports/mutaa-manual-vs-backend-20261031/raw/`);
  - 14 older saved responses of the 6 trios from `reports/eval-20261015/eval_manifest.json`.
- **None of the 14 sets is a genuine STRAIGHT/LEFT/RIGHT trio with a known total.** The 99-block total of 99 is
  known, but its side photos are substituted.

## Truth tiers (never pooled)

| Tier | Meaning |
|---|---|
| U | The user's handwritten number on the photo. Its scope is from the 15 Oct audit and was not confirmed by the user. |
| U-blind | The user's blind per-stack count (Phase D2). **None yet.** |
| V | Three agent counters, reconciled (31 Oct): trays = filled + empty. Not physical. |
| S | Synthetic, known by construction: the adversarial library in `replay_benchmark.mjs`. |

## Splits

- **untouched:** img-47 and img-49 only. They were used neither in detector training nor in counting-logic tuning.
- **development:** everything else. Every figure from it is a development figure, not proof of accuracy.
  - The labelled photos tuned the capture gate and the walk counter.
  - L-100 (img-19, 21, 24) shaped the side check.
  - The MUTAA sets were studied in Phase B.

## Provenance flags

- `detector_pool_match` is a dHash match, at distance ≤ 8 of 64, against `datasets/canonical_clean`, `review` and
  `roboflow_auto_original`.
  - **Check of the method:** the 18 labelled photos the 15 Oct audit marked leaked all match at distance 0–7. The 6
    marked leak-free match only at 10 or not at all.
  - **Result:** none of the 42 MUTAA field photos matches. They are out of sample for the detector, though not for the
    rules (see Splits).
- `in_gate_tuning_set`, `in_walk_reference_photos`, `in_walk_development_photos` and
  `in_orientation_development_photos` are copied from `reports/eval-20261015/results.json`.
- `in_sidecheck_design`: img-19, img-21 and img-24, the L-100 photos.
