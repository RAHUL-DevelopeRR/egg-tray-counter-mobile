# MUTAA field photos: manual 3D count vs backend 3D count (31 Oct 2026)

The user asked for this: clone MUTAA, pick STRAIGHT/LEFT/RIGHT sets, count them by hand, build the 3D
count, and compare it with the backend's count and 3D block.

Evidence labels:
- **M** means measured here.
- **V** means a visual count from the photos by three independent counting agents, reconciled. It is not
  a physical recount.
- **U** means the user's handwritten total on the photo.

## What was done

1. **Source.** `https://github.com/RAHUL-DevelopeRR/MUTAA` (commit a27877b), cloned to
   `C:\Users\rahul\MUTAA`, outside this repo.
   - 24 phone-camera photos from 16 Sep (one shed).
   - 18 WhatsApp photos (5 Sep orange block; 15 Sep loose trays).
   - `FileOfEggLabels`: the 52 labelled photos already in `datasets/field-2026-10/labelled-20261007`.
2. **Grouping** (`sets-verified.json`). One agent proposed 10 block sets and a second agent tried to
   refute each one. Two sets were dropped (different blocks) and several roles were corrected.
   **None of the 8 kept sets is a genuine trio of three different faces.** No photo of any back face exists,
   and the "side" photos are often the front again.
3. **Backend (M).** Each set was sent to the staging Worker (0.4.12, `ef7c1dd3`) the way the app sends it:
   upright, 1600 px long side, JPEG quality 92, admin auth, 21 detector calls in total. The Worker refuses
   a set that uses the same photo twice (`422 duplicate_view`). For the four sets with only two photos of
   their block, RIGHT was filled with an unrelated single-tray photo, so only the real faces' counts are
   used there (`filler_right` in `comparison.json`).
4. **Manual (V).** For each set, three blind counters used different methods: tray rims, egg rows plus
   pixel pitch, and a cross-view grid. None of them saw labels or backend output. A reconciler then
   re-counted every stack where they differed by 2 or more. The reconciled count is in
   `manual-consensus.json`.

## Results

Front face = STRAIGHT photo. Per-stack values are filled trays.

| Set | Block (manual) | Manual front stacks (V) | Backend front stacks (M) | Front exact | Photo check | Manual 3D total, filled (V) | Backend 3D result (M) | User total (U) |
|---|---|---|---|---|---|---|---|---|
| M16-CORNER-STACK | 1x1 | 14 | 14 | 1/1 | front OK | **14** | no total: side photo reads 8, conflict | - |
| L-80 | 4x1 | 20 20 20 20 | 20 20 20 19 | 3/4 | front OK | **80** | no total; side photo is not a side face, block read as 4x4 | **80** |
| L-100 | 5x1 | 20 20 20 20 20 | 20 20 20 20 20 | 5/5 | all OK | **100** | **500 "estimated"** (5x5: LEFT/RIGHT are front photos) | **100** |
| M16-NEAR | 4x2 + 1 short | 17 20 20 20 20 | 8 10 11 12 10 | 0/5 | refused: too far | 177 (vis 127 + hidden 59) | no total | - |
| M16-FAR | 3x5 | 15 15 15 | 17 18 17 19 8 (5 columns) | n/a | front OK, side refused | 240 (236-268) | no total | - |
| W05-ORANGE | 10x7 | 20 x9 + a short stack of 6 | 10 19 19 20 19 19 19 19 8 | n/a | front OK | 1366 (vis 196 + hidden 1239), low reliability | no total | - |
| L-109-ORANGE | 6x3 + 2 | 10 20 20 20 19 20 \| 21 5 20 | 17 20 20 18 20 20 | 3/6 (first six, left-aligned) | front OK | 375 (low reliability) | no total | **109** (= manual's first six front stacks) |
| L-115 | 6x6 | 20 20 20 20 20 20 + a short stack of 14 in front | 19 23 22 19 20 18 | 1/6 (short stack dropped) | refused: too far | 734 (645-897; counters 771 / 897 / 1455) | no total | - (the inked 115/120 split the block) |

## Findings

1. **Close, square-on faces: the backend's per-stack count matches the manual count.**
   - Stacks: 9 of 10 exact and 1 within 1, on CORNER, L-80 and L-100.
   - Totals: on L-80 and L-100 the manual count equals the user's handwritten total (80, 100), and so does
     the backend's front face (79 and 100).
2. **Far faces: the backend reads about half.** On M16-NEAR it reads -8 to -10 trays per stack, but the
   capture check refuses those photos, so no wrong total is shown. Moderately far faces (W05, L-115) are
   within about ±1-3 per stack.
3. **The 3D total is only as good as the photo roles.**
   - L-100's LEFT and RIGHT photos are both front views. The block model took them as side faces and
     reported **500, status "estimated"**, for a 100-tray block. Nothing checks that a "side" photo really
     shows a side face. This is the most dangerous failure seen: a confident-looking wrong total.
   - L-80 fails the same way, but there the bad side photo was refused, so no total was shown.
4. **Big blocks are mostly hidden interior.**
   - W05: only 196 of about 1366 trays are visible. L-115: 232 of about 734.
   - Neither the hand count nor the app can be exact for these from photos. The interior is an assumption
     in both.
   - The hand counters themselves disagree widely on footprint depth (L-115: 771 / 897 / 1455).
5. **The field photos contain no genuine STRAIGHT/LEFT/RIGHT trio** (see the grouping step). The capture
   protocol has not yet been followed in any photo set we hold.

## What this means

- **Exact counting is reached for what the camera sees clearly:** close, square-on faces. These are the
  trays that can be counted by eye.
- **The errors come from three places.** Only the first is fixed by training:
  1. Detector recall on far or small trays: retrain on field crops, and capture closer.
  2. Wrong view roles: a code guard is needed, not training.
  3. Hidden interiors: these cannot be learned from photos. They need operator confirmation or extra views.
- **Ranking of fixes by effect:**
  1. A same-face guard: never return a total when a "side" photo shows the front face. Downgrade to
     needs_view.
  2. Genuine trios captured close, per the SOP.
  3. A detector retrain on far faces, held out by block.
  4. An interior policy for big blocks: operator-confirmed, or flagged as estimated with the visible share
     shown.

## Caveats

- All manual numbers are visual counts by agents, not physical counts. Agreement with the two user totals
  (L-80, L-100) is encouraging but small (n = 2 blocks).
- The labelled photos carry ink marks, and counters were told to ignore them.
- Per-stack alignment for L-109 and L-115 is approximate (left-aligned; the short stack dropped for L-115).
- The scans are stored on staging under the admin owner. Scan ids are in `comparison.json`. No manual
  counts were written.

## Files

- `comparison.json`: one row per set, manual vs backend.
- `backend-summary.json`: per-view walk/raw counts, capture-check verdicts, block grid, conflicts.
- `manual-consensus.json`: reconciled manual counts and each counter's block.
- `sets-verified.json`, `sets-sent.json`: the grouping and what was uploaded.
