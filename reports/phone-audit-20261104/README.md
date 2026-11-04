# Phone audit: MUTAA photos never used as a block set, scanned on the Redmi (4 Nov 2026)

**Request:** new 3D examples from MUTAA images that were not tested before, no worked examples; move them to the
phone and audit the 3D scan.

**What "untested" can mean here (measured).** The MUTAA repository (`C:\Users\rahul\MUTAA`) has 41 photos. 11 were
used in the 8 block sets of 31 Oct (`reports/mutaa-manual-vs-backend-20261031/sets-sent.json`). The other 30 were
never sent as a STRAIGHT/LEFT/RIGHT block set, but every one of them went to staging once on 1–2 Nov in arbitrary
groups of three in file order (`scripts/validate_build_staging.py`, `mutaa-batch-*`). So these photos are new as block
scans, not new to the server. None of them was used to tune the counter.

**How the sets were chosen.** A random pick of three of the 30 would mix different blocks, which the server must
refuse and which tests nothing. The 30 photos were sorted into scenes (contact sheet), and every scene with a front
view plus at least one other view of the same block was used:
- **A, a row of 3 stacks** (16 Sep 15:12): front `IMG_20260916_151210436`, right end `IMG_20260916_151224648`. No
  photo shows the left end, so `IMG_20260916_151204619` (a separate single stack nearby, same height) is a stand-in
  LEFT. Blind manual count (two counters agree, tier V): 3 stacks, each 10 filled trays + 1 empty cover tray.
- **B, the M16 block** from angles never used as a set: front `IMG_20260916_151353868`, left
  `IMG_20260916_151339474`, right `IMG_20260916_151436402`. Blind manual count of the block (31 Oct, M16-NEAR, tier V):
  about 4 × 2, 177 trays; this front photo: 4 front stacks of 20 (two counters agree). The first choice for RIGHT,
  `IMG_20260916_151506512`, was refused by the app before upload (see finding 1); the next view from that side,
  `IMG_20260916_151447066`, is also 50 MP, so the 12.6 MP `151436402` was used.
- Not usable as sets: the orange W05 block (three high views of the same front, frame cuts the floor), the paper-pulp
  block (one view), single loose trays and broken eggs.

**Setup.** Redmi Note 9 Pro, app 0.6.0+29, staging Worker 0.5.0 (`52a1d5e8`), detector `projec-mutta/2`. Photos pushed
to `/sdcard/Pictures/EggTrayAudit/`, chosen in the system photo picker by their capture time. Gallery scans switched on
for the test. Declaration skipped (blind). "Same stacks" ticked (required to upload; for A the LEFT is a stand-in).

## Results

### A: row of 3 stacks

| | |
|---|---|
| Phone result | **RETAKE NEEDED, total withheld.** 3D grid model drawn: 3 wide × 1 deep, stacks **10, 10, 11** (31 layers, all "counted, read once"). |
| Why withheld | "LEFT: stacks are too small in the frame (too far away)": the stand-in photo was refused. Correct. |
| Per-photo detections | Left 14, Right 12, Straight 33. |
| Manual truth | 10 filled + 1 empty cover per stack: 30 filled trays, 33 layers. |
| Audit | Each stack matches either its filled count (10) or filled + cover (11), but the app is not consistent about the cover tray across the three stacks: as layers it reads 31 against 33. The front photo's 33 detections equal the 33 layers. No total was released, so nothing wrong was shown. |

Screens: `A-01-3d-withheld.png`, `A-02-reasons.png`.

### B: the M16 block

| | |
|---|---|
| Phone result | **RETAKE NEEDED, no total, no 3D model drawn.** |
| Why | LEFT and RIGHT "not confirmed as a side face (no phone heading from the camera session that took STRAIGHT)" on a block read as 3 stacks deep; depth differs between LEFT (3) and RIGHT (2); STRAIGHT boxes found on only some layers (trays too small) on 3 of 4 front stacks; layer counts disagree on 3 stacks (span 15–17 against walk 19–21); RIGHT refused as too small in the frame. |
| Per-photo detections | Left 38, Right 15, Straight 57. |
| Manual truth | About 4 × 2, 177 trays; 4 front stacks of 20 on this front photo (80 filled trays on the front row). |
| Audit | Width 4 matches. LEFT's depth 3 is wrong (manual 2), RIGHT's 2 is right, and the server refuses rather than choosing. The front row reads 57 detections against 80 trays: the photo is too far for the detector, and the server says so per stack. No total was released, so nothing wrong was shown. |

Screens: `B-00-50mp-refused.png` (first RIGHT choice refused in the app), `B-01-retake-reasons.png`,
`B-02-per-photo.png`. `C-home-history.png`: both audit scans in the phone's history.

## Findings

1. **The app refuses photos over 40 MP from the gallery** ("Photo not selected: FormatException: Choose a valid JPEG
   or PNG of at most 40 megapixels", `mobile/lib/features/capture/photo_upload_pane.dart:27`). 4 of the 23 MUTAA
   `IMG_` photos are 8192 × 6144 (50.3 MP; `151444583`, `151447066`, `151453724`, `151506512`). The validation script
   resized them before sending, so this limit was never hit before. The camera path is not affected.
2. **No new 3D total from gallery photos on Worker 0.5.0.** Of 2 new sets, the 1-deep row drew its 3D model but was
   withheld for a refused photo; the deep block got no model, because gallery side photos cannot prove a depth.
   Neither showed a wrong total (0 wrong of 2).
3. **The cover tray is read inconsistently** on the row: 10, 10, 11 for three stacks that each carry 10 filled trays
   and 1 empty cover tray.
4. **The MUTAA repository has no complete new block set left.** Every scene with a front and both true side views was
   used on 31 Oct. A genuine new 3D example needs new photos: a camera scan on the farm (which records the phone
   heading), with a hand count of the same block.

Cost: 2 scans, 6 detector calls (the refused 50 MP photo never left the phone).
