# Phase B: what actually causes each known miss (1 Nov 2026)

Plan: `C:\Users\rahul\.claude\plans\spicy-growing-flame.md`, Phase B.

**How this was done.** Each saved detection set was drawn on its photo, prepared the way it was sent, with each
detector box coloured by the stack column the counter put it in and numbered top to bottom. This used the new
`scripts/overlay_columns.py`; the overlays and per-column gap lists are in `overlays/`.

- No inference and no network.
- Detections come from the existing saved responses:
  - `reports/field-labelled-20261007/raw/batch-10.json` (img-30, 7 Oct);
  - `reports/mutaa-manual-vs-backend-20261031/raw/*.json` (the app-equivalent 1600 px re-encodes, 31 Oct).

**Evidence labels.** **M** means measured from the saved boxes. **V** means visual inspection of the overlay. The
truth values are the user's handwritten totals (U) or the 31 Oct agent consensus (V), as in
`benchmarks/registry-20261101`.

## Classification

| Case | Reading vs truth | Where | Cause | Already caught? |
|---|---|---|---|---|
| img-30 stack 2 (7 Oct) | 19 vs 20 (U 80 = 4 x 20) | top | **One wide box spans the top trays of stacks 1 and 2.** It is box 1 of column 1, x 105-596, about 1.8 x the face's box width (M). Column 2's own top tray has no box, and its first box is the 2nd tray (V). | No: accepted, 78 for 80 |
| img-30 stack 4 (7 Oct) | 19 vs 20 | bottom | **A tall box covers the bottom two trays.** Box 19 is elongated, so its centre sits only 0.32 pitch above the real bottom box 20 (M). The walk counter merges gaps under 0.65 pitch as duplicates, so the bottom tray is dropped (V). | No |
| L-80 stack 4 (31 Oct re-encode of img-30) | 19 vs 20 | bottom | Same tall bottom box; gap 0.31 pitch (M). | No: accepted, 79 for 80 |
| L-80 stack 2 (re-encode) | 20 vs 20 | top | After the re-encode, stack 2's own top tray is detected (first box y 42 vs 91 before). The wide box still exists but is no longer the only box over stack 2 (M). | Count is right, by luck |
| L-109 stack 4 (re-encode of img-36) | 18 (truth V 20; 19 by my reading of the overlay) | bottom | **The bottom tray at the floor has no box at all** (V). The column's last box is at y 677 against 701-715 for its neighbours, about 0.9 pitch higher (M). Boxes 9 and 10 sit on one tray (gap 0.22) and are correctly merged. | Yes: the face is refused, because column 1 is flagged |
| L-109 column 1 | 17, meaningless | depth | **One column holds two stacks.** Boxes 1-5 are the top of a back-row stack, and boxes 6-15 are the short front stack (V). Unbridged gaps of 3.1 and 5.0 pitch. | Yes: flagged (unresolved gaps) |
| W05 STRAIGHT, stacks 2-6 | 19/19/20/19/19 vs 20 (V) | inside | **Far face.** Pitch is 26 px (2.2% of the frame height), and the detector finds alternate layers. Gaps of 1.5-2.0 pitch are filled by rounding, and one layer per stack is still lost (filled 2-5 per stack) (M). Edge columns c1 and c9 are partial stacks cut by the frame. | Partly: 4 of 9 columns flagged, so no total; but 5 wrong cells are marked `observed` |
| M16-FAR STRAIGHT | 5 columns for 3 stacks | frame | **Two blocks plus loose trays in one elevated view** (V). The left block is seen from its side, and a loose tray lies on the floor (column 4, boxes 12-14; column 1's last box is 9.6 pitches lower). | Yes: flagged; only a declared X would catch it if it were accepted |
| L-100 stack 4 (re-encode of img-19) | 20 vs 20 (U) / 21 (V, includes one empty tray) | inside | One layer had no box (gap 2.1) and was filled correctly. | Correct; the U vs V difference is trays vs filled trays |

## Findings

1. **Every silent miss on a close, accepted face is at a stack end:** 3 of 3, namely img-30 stacks 2 and 4 and
   L-80 stack 4. L-109 stack 4 is a 4th end miss on a refused face. A layer lost *inside* a stack was filled
   correctly in every close case seen (L-100 stack 4, M).
2. **Two different mechanisms produce end misses, and box geometry exposes both:**
   - **A box spanning two stacks** at the top. Its width is about 1.8 x the face's median box width.
   - **An elongated end box** at the bottom. It is taller than normal, so the real end box sits under 0.65 pitch
     from it and is merged away as a "duplicate".
   - **An end box missing outright** (L-109) is visible only against the floor line of the neighbouring stacks.
3. **Far faces lose layers inside the stack.** Gap filling cannot recover them, because it fills only to the
   nearest whole pitch. They are already refused by the per-column flags. In a block, though, their unflagged
   columns still become `observed` cells.
4. **Re-encoding moves boxes.** The same img-30 gave 78 at its original size and 79 after the app's 1600 px
   re-encode, because stack 2's top box appeared. In the replay set, 7 of 10 re-encoded views changed count
   (`reports/replay-baseline-20261101`).

## What this means for Phase C

The plan adopts an end-tray rule only if end misses actually occur. **They do, and they are the only silent miss
seen on close faces.** Candidate rules, to be measured in the replay harness for false refusals before adoption:

- **End-box anomaly.** A column whose top or bottom box is over about 1.5 x the face's median box width or
  height, or whose end box was merged as a duplicate, cannot be read exactly. That cell becomes single-reading or
  rescan. *Catches img-30 stacks 2 and 4 and L-80 stack 4.*
- **Floor line.** A column whose bottom box sits more than about half a pitch above the line through its
  neighbours' bottoms may have lost its bottom tray. *Catches L-109 stack 4.* Not valid for stacks standing on a
  pallet or step; such stacks must be refused, never silently accepted.
- **Gap-filled layers demote the cell** (plan Phase C3). *Catches the W05 cells.*

Neither the top-of-stack nor the floor rule can prove a count. They can only stop a wrong count from being called
exact. The second reading (Phase E) or the operator declaration (Phase F) is still needed to release `exact`.
