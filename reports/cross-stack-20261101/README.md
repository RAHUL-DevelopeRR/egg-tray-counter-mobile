# Phase P: five/six parity and occupancy checker. Disabled (1 Nov 2026)

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3), step 3.
**Code.** `backend/app/vision/cross_stack.py`. **Evaluation.** `scripts/evaluate_cross_stack.py`; output in
`results.json`.

## Verdict (measured, thresholds frozen before scoring)

| Pass bar | Result |
|---|---|
| The hand-checked alternation holds on every reviewed stack | **Pass**, on the hand review (`benchmarks/annotations-20261101`) |
| Automatic row type matches the hand labels on at least 95% of the end layers it types | **Fail: 3 of 7 (43%)** |
| The known false counts it can see are flagged | Pass. img-30 c2 and L-109 c4 get `unboxed_egg_layer` |
| At most one correctly counted face gets a false flag | **Fail: 10 faces**, mostly `unboxed_egg_layer` |
| Far faces are unreadable, not typed | Pass. W05: 0 of 9 columns readable |

**So P is disabled, as the plan requires.**
- The module stays in the repository and is not wired into the Worker.
- **Consequence for the grid:** no validated reader measures a layer's occupancy, so occupancy stays `unknown` unless
  the operator's declaration or top-view taps supply it, labelled with that source.
- **The physical rule itself holds:** the 5/6 alternation and the end-layer parity on every hand-reviewed stack. Only
  the automatic reading fails.

## Why the automatic reading fails
- **The egg mask is not specific.** Eggs are bright and unsaturated, and so are the white walls and the eggs of the
  stacks behind and beside a column. Probing beyond the detector's ends therefore finds "egg layers" that belong to the
  wall or to another stack: false `unboxed_egg_layer` flags on img-01, img-02, img-19, img-34, L-100 and others.
- **The cell count per row is fragile.** Neighbouring cells merge into one blob, and dark 6-cell rows split or vanish.
  So exactly 5 or 6 evenly spaced blobs is rare: only 9 of 252 columns were readable at both ends.
- **Perspective hides the true top.** On the frame-cut img-30, the top row is seen from above, and it read 5 where the
  hand review reads 6.

## What would be needed (not done here)
- **A cell model instead of colour blobs:** a learned egg/cup classifier, or template matching on the cup pattern.
- **A stack mask that excludes walls and neighbours,** using the detector's column x-range plus tray-colour segmentation.
- **Validation on photos never used for development** (D2 blind counts, field captures).
