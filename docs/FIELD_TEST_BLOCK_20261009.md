# Field test — block counting (Day 2 of the 3-day scope)

Written 2026-10-08. Purpose: measure the per-stack and per-block accuracy of
APK 0.4.0 (block model) on real blocks with on-site counts. Nothing in this
test is a development input; the scenes stay untouched until the code is
frozen and are scored once.

## What the app does now

- STRAIGHT photo = X face (front row). LEFT and RIGHT photos = Y faces (the
  two side columns). The server counts layers per stack on each face, checks
  that the corner stacks match between faces and that LEFT and RIGHT agree on
  the depth, and multiplies out the block: X × Y stacks, heights from the faces.
- Interior stacks (not on any face) are COMPUTED from the face heights. The
  screen shows observed trays and computed trays separately, plus the total.
- A missing front stack is detected when the stack behind shows through.
- If faces disagree, the app shows RESCAN and names the stack.

## Capture rule (what the app will enforce; follow it even if the build is lenient)

1. One block per scan. Write the block ID on the notepad before you shoot.
2. STRAIGHT: stand square in front of the block, phone upright at chest
   height, far enough that the whole front face fills the frame left to right
   with a small margin, top row and floor both visible. Do not angle.
3. LEFT: walk to the left side of the block and photograph the left face the
   same way. RIGHT: same from the right side.
4. Nothing moves between the three photos.
5. No zoom, main camera, torch off unless the face is in shadow.
6. If the app says RESCAN, read the reason, fix that one thing, and shoot
   again. Record that a rescan happened (it is one of the numbers we measure).

## Blocks to scan (target 10, minimum 6)

Pick a mix: short blocks (≤ 10 layers) and tall (≥ 20); narrow (2–3 stacks)
and wide (6+); at least two blocks that are more than one row deep; at least
one block with a known gap or a shorter stack; if you have orange or pulp
trays, at least two blocks of those. Include one single-row block (depth 1) —
that one can be fully observed, so it tests the "all stacks observed" path.

## On-site count (the only ground truth)

For every block, count every stack you can reach, including interior ones,
and write filled and empty trays per stack. Use `counts.csv` in
`datasets/field-2026-10/` (one row per stack). Number stacks as the app does:
`x` left to right as seen from the STRAIGHT position, starting at 0; `y`
front to back, starting at 0. A missing stack is a row with 0/0 and
`missing=yes`.

If an interior stack cannot be reached, write `unreachable` in notes; those
stacks are excluded from per-stack scoring but still count toward the block
total you report.

## What to send back

- The original photo files from the phone (USB or Drive; not WhatsApp).
- `counts.csv` and `tray.csv` (tray width, depth, height of 10 filled trays,
  height of 10 empty trays — measured once with a tape).
- The app's result screen screenshot per block, including any RESCAN.

## What gets measured (Day 3)

Per block: app total vs on-site total; per stack: exact / ±1 / worse;
rescan rate; how often the computed interior differed from the counted
interior. These four numbers are the accuracy claim; nothing else is.
