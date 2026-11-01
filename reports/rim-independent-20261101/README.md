# Phase E: independent pixel-periodicity reader. Rejected (1 Nov 2026)

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3), step 2.
**Code.** `backend/app/vision/rim_count.py`. **Evaluation.** `scripts/evaluate_independent_rim.py`; output in
`results.json`.

## Verdict (measured, development data)

| Pass bar | Result |
|---|---|
| 0 readable readings agreeing with the detector on a known wrong count | **Pass.** img-30 c2 and c4 and L-80 c4 are unreadable (frame edge). L-109 c4 reads 13 against the detector's 18 |
| Exposes the L-109 stack 4 disagreement | **Pass in form only.** It disagrees, but with 13, which is also wrong (this review reads 19) |
| Half/double-pitch readings on at most 10% of reviewed faces | **Fail.** 3 of 14 faces (21%): img-02, img-21, img-24 |

**So E is rejected, as the plan requires.**
- The reader stays in the repository as a diagnostic.
- The Worker does not use it as a reading, and Phase Q gets no rim readings.
- `RIM_VERIFY` stays off.

**Accuracy on the 64 columns with truth:**

| Measure | Result |
|---|---|
| Readable | 52 (81%) |
| Exact | 18 |
| Off by one | 15 |
| Wrong by more than one | 19 |
| Contradicts a correct detector count | 33 stacks |
| Catches a detector miss | 1 (W05 c3, though with 15 for 20, also wrong) |

**Truth tiers, never pooled:** 11 hand annotations (V), the 7 Oct label-implied assistant references (A), and the
MUTAA consensus (V).

## What the reader does
- **Inputs:** only the column x-range (the median box width and centre) and the image. The detector's vertical
  positions and pitch are not used for counting; they only feed comparison fields.
- **Scale:** from the strip width, since tray boxes are 3-6 times wider than tall.
- **Search window:** the whole strip.
- **Anchor:** the band with the strongest local periodicity.
- **Pitch:** the band's autocorrelation, halved while the half-lag is periodic. The p/2, p and 2p alternatives are
  scored and reported.
- **Rim tracking and run ends:** compared with the period template of each layer's own parity.
- **Unreadable when** confidence is low, the pitch is ambiguous, or the run comes within 1.5 pitches of the frame edge.
- **Thresholds** were frozen in code before scoring. After the first scoring, one defect fix followed: the frame-edge
  margin became 1.5 pitches, to match the Worker's frame rule. It was found by a unit test on a cut stack and did not
  change the verdict.

**Recorded limitation.** E depends on the detector's column x-range for where each stack is. It is not independent of
stack localisation.

## Why it fails: the physics
The trays are cross-stacked, so alternate layers show opposite front rows: 5 eggs, then 6.
- **The edge signal alternates polarity and shape layer by layer.** The autocorrelation at the true layer lag can be
  weak or even negative ("half" values of -0.05 to -0.6 in `results.json`), while the two-layer pair period is strong.
- **Doubled pitch.** On the high-resolution close faces (img-02, img-30, L-80), the band pitch locks onto the pair (75-87
  px where the layers are about 40 px). The halving rule never fires, so these columns read about half (10 for 20).
- **Runs end too early.** On the low-resolution 1280 × 582 frames (img-21, img-24), the run stops after 5-11 layers.
- **The same mechanism defeated the on-phone estimator (Phase K2):** half or double pitch on 28% of faces
  (`reports/layer-signal-20261101`).

## What would be needed (not done here)
- **A two-layer model that fits the alternation directly.** That means a pair template carrying both orientations,
  or periodicity on |edge| with a polarity-free rim detector.
- **Validation on photos never used for development:** the user's blind counts (D2) or new field captures. Re-tuning
  on these 14 faces would be tuning on the test.
