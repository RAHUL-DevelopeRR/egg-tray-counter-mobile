# Blind count sheet (plan Phase D2), for the user

**Why your count matters.** It is the only way to turn the existing photos into trustworthy truth. The agent counts
from 31 Oct are visual estimates, and the counters disagreed by up to 2x on deep blocks. Your handwritten totals
exist for only 3 blocks. Every accuracy figure the project can honestly state rests on counts like these.

## How to count

1. **Do not look at any app or report number first.** That means `reports/*`, the app's result screen, and the
   handwritten numbers on the labelled photos where you can avoid them. A count that starts from the app's answer
   tends to repeat it.
2. Open each photo listed in `sheet.csv`, at full size, and zoom in.
3. For each stack in the photo's main block, from left to right, count **all trays, empty ones included**. Write the
   counts in `stacks_left_to_right_trays`, separated by `;` (for example `20;20;19;20`).
4. Put the number of empty trays in `empty_trays_total`.
5. Give the same `block_id` to every photo of the same block, for example `M16-A` or `W05`.
6. Where you can tell, fill in:
   - **`stacks_wide` and `stacks_deep`.** The top or elevated photos show the grid.
   - **`interior_full_yes_no_unknown`.** Can you see, or do you know, that no stack inside is missing or short?
   - **`stacks_outside_rectangle`.** For example "1 short stack against the west side".
   - **`side_not_reachable`.** For example "east side against a wall".
7. If a stack cannot be counted, because it is too far, blocked or cut by the frame, write `?` for it and set
   `can_count_yes_partly_no`.
8. **A second person, counting independently, makes the count much stronger.** Fill `counted_by` (a name or
   initials). Recount wherever the two of you differ, zoomed in.

## Order

**Priority 1:**
- the 24 phone photos of 16 Sep (MUTAA `IMG_*`). None of them was ever in the detector's training data.
- the 5 Sep WhatsApp photos (the W05 orange block).

**Priority 2:** the 15 distinct straight-on labelled photos.

**Priority 3:** the 15 Sep WhatsApp photos.

## What happens next

When you return `sheet.csv`, the counts are added to the registry as tier `U-blind`. The replay benchmark then
scores against them, and the pixel counter in Phase E is judged against them.

Physical recounts of real blocks (Phase H) remain the only route to proving 95–99%. These counts measure and
protect the counting logic.
