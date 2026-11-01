# Offline replay: Worker 0.4.15 (capture provenance and frame doubts), 1 Nov 2026

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 2), phases J and K1.

**Method.** The same replay set and harness as `reports/replay-baseline-20261101`. Everything is measured (M) on
development data; none of it is proof of field accuracy.

## What changed vs 0.4.14

| | 0.4.14 | 0.4.15 |
|---|---|---|
| One photo sent as all three views (S15 camera, S16 gallery) | `exact` (copies verified each other) | `estimated`: copies count once |
| One-deep 2x1 block from gallery photos (S17) | `exact` | `estimated`: gallery photos never verify |
| Corner stack cut by the frame, side photo agreeing (S19) | `exact` | `estimated` (`end_at_frame_edge`) |
| L-80 front (stack 4 frame-cut, read 19) with sides agreeing on 20 / 19 (R04) | `estimated` 79 (the 0.4.14 cut-short-box doubt) | `estimated` 79 |
| Genuine 2x1 camera walk-around (S18) | `exact` 40 | **`exact` 40: still reachable** |
| Contract failures among all adversarial cases | 2 (S14, R02) | 2 (S14, R02; need Phase F) |
| Saved three-view replays: wrong releases / wrong `exact` | 0 / 0 | 0 / 0. Saved responses carry no provenance, so none can be `exact` |

## Doubts on real faces (82 accepted columns)

- **`end_at_frame_edge`:** 8 columns, all on img-30 and its re-encode L-80. These are the only frame-cut faces; every
  correct face has at least 2 box heights of room.
- **`cut_at_frame_side`:** 2 columns, the left edge stack of img-08 and img-23 (the same photo). The count is correct;
  the stack just cannot be verified.
- **`pitch_differs`:** 0.
- **Duplicate-capture score:**
  - re-encodes of one photo: 0.944-0.995 (all 10 flagged);
  - same photo or near-identical burst: 0.952-0.976;
  - different captures of one block (L-100's three photos, img-30 vs img-31): 0.19-0.47. None flagged.

## Not changed

- Face verdicts (accept or withhold) are unchanged. Doubts never refuse a count.
- There is no distance refusal yet. Pitch in pixels does not separate good faces (22.5-25 px) from W05 (26 px, wrong);
  the threshold waits for the distance ladder (plan G).
