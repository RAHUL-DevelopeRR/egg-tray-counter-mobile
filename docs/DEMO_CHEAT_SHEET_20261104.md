# Demo cheat sheet, 4 Nov 2026 (app 0.5.1+28, "DEMO — SAVED RESULTS")

The demo screen shows three answers the **test server** gave earlier. They are bundled in the app
(`mobile/assets/demo/`), shown offline, never sent and never saved to history. It is not a live scan.

## The three screens

| Screen | Number on screen | What it is | Truth it was checked against | Source |
|---|---|---|---|---|
| 5 × 1 row | 20/20/20/20/19 = 99 | All 5 stacks seen; nothing assumed | Handwritten label 99. The front photo was used in tuning and the side photos came from other pictures: a worked example, not a fresh test | `reports/eval-20261015/staging47-replay/6fe33b1d-….json` |
| 4 × 3 block | Counted 105 + Assumed 60 = Estimated 165 | 7 stacks on the faces counted; front-right spot seen empty; 4 middle stacks never photographed, assumed at 15 each | Visual count of the same photos: 104 egg trays on the seen stacks (the 1 difference is an empty cover tray); 6 of 7 seen stacks identical. The 60 is an assumption in both. No hand count on the farm | `reports/field-scans-20261013/` (README and `replay/9b4c783e-….json`) |
| Refused (L-100) | No total | Both side photos show the front again, so the depth is unknown; the app holds the answer back | Without this check, a false depth gave 500 for this ~100-tray block in an earlier test | `reports/mutaa-validation-0.5.0-20261101/raw/set-L-100.json`, PROGRESS.md 2026-11-02 |

The 4 × 3 answer came from an older server (f5776f0d). Today's server holds that block back until a
CORNER photo confirms its depth.

## How the hidden trays are worked out (the 4 × 3 screen, step by step)

1. Width 4 from the front photo, depth 3 from the side photos.
2. Stacks no photo can see: (4 − 2) × (3 − 1) = 4, the ones in the middle and back.
3. Each is assumed as tall as the faces around it (15): 4 × 15 = 60 tray layers.
4. A top photo can show whether one of them is missing or taller. It cannot count their trays, and a
   stack one tray shorter on a far row stays hidden even from above.

## Numbers you may quote (all from AI visual counts or labels, none physical)

- On photos that passed the photo check, the stacks the app was sure about matched two independent AI
  visual counts on **20 of 21**.
- Only **37 of 94** farm photos passed the photo check (far or angled faces are refused).
- Block W05: about 70 stacks and about 1,366 trays; **48 stacks** are never seen by the three photos, and
  only about **196 trays** sit on the faces a photo can see.
- On 22 saved scans, the next version (0.5.1) released a total on **4**, all the same 99-tray row,
  **0 wrong**.
- Physical counts so far: **zero**. The farm day is the next step.

## Never say

"X% accurate", "field-validated", "blind counts" without "AI visual", "the 3D model counts hidden trays",
"exact" or "confirmed" for a deep block, eggs or rupees for a block, "works on any photo",
"production-ready", "rotate the 3D view".
