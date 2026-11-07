# Hand-reviewed layer annotations, 1 Nov 2026 (tier V)

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3), step 1. These annotations are the
prerequisite for Phase E (independent rim reader) and Phase P (5/6 parity and occupancy).

**What this is.** 11 detector columns, reviewed by eye on zoomed crops by Claude Code.
- For each column: the egg-row type of the top and bottom layers (5 or 6 front-row cells), cover trays, occupancy and
  image quality.
- **Tier V:** a visual review, not a physical count. The user's blind counts (`reports/blind-count-20261101`) and
  physical recounts (plan step 10) take precedence.

## How the crops were made
One image per column: the top three layers and the bottom three layers, cropped to the column's x-range, zoomed to
900 px wide.
- **Photos:** prepared the way they were sent. MUTAA files were EXIF-upright and resized to `_sent`; the 7 Oct batches
  used raw pixels.
- **Columns:** from `backend/app/vision/layer_span._columns`, ordered by x.

## Findings

**The rule holds.** The 5/6 alternation held on every reviewed window: 11 columns, top and bottom.

**Parity matches the known counts, and contradicts every known miss:**

| Column | Top / bottom | Parity | Known count | Detector (walk) |
|---|---|---|---|---|
| img-19 c1, c3 | 5 / 6 | even | 20 | 20 |
| img-19 c5, img-34 c1 and c4, img-20 c2 (each with a cover) | 6 / 5 | even | 20 filled | 20 |
| W05 c3 (far), M16-CORNER c1 | 5 / 6 | even | 20, 14 | 19, 14 |
| **img-30 c2** | 6 / 5 | even | 20 | **19** |
| **img-30 c4** | 6 / 5 | even | 20 | **19** |
| **L-109 c4** | 6 / 6 | odd | unknown (this review: 19) | **18** |

- The parity contradicts the detector on all three known misses. **But only if the top and bottom layers are read
  beyond the detector's own first and last box**, because the missed layer is exactly the unboxed one.
- At L-109 c4, the 31 Oct visual consensus (20) contradicts the parity; this review reads 19.

**Cover trays are common.**
- An empty cover tray sits on 6 of 11 columns: 5 plastic, and on L-109 a stack of 3 or more grey pulp trays.
- **On the columns checked, the detector did not box them** (img-19 c5, img-34 c4, img-20 c2). The detector's count
  there equals the filled (eligible) count.

**Far faces are hard to read.** On W05, the 6-type rows are dark and their eggs barely visible. That is why the
detector boxes mostly the 5-type rows and far faces read about half. Automatic typing must answer `unreadable` there.

**A partly filled top tray occurs** (M16-CORNER c1). It counts as one eligible tray.

## Limits
- One reviewer.
- 11 columns from 7 photos.
- The counts for the labelled photos are implied by the handwritten totals (for example, 100 = 5 × 20), not counted
  per stack.
