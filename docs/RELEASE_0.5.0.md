# Release 0.5.0: phone-only X/Y/Z grid counter (architecture and release report)

**Plan.** `C:\Users\rahul\.claude\plans\spicy-growing-flame.md` (Plan 3, execution).
**Contract.** `docs/GRID_CONTRACT_0.5.0.md`.
**Branch.** `rollout/0.4.12-staging`, which contains `codex/hybrid-cell-counting` (`7971117`).
**Versions.** Worker `worker-0.5.0`, app 0.5.0+27.

## What the product is
A **handheld phone app** (no CCTV, fixed camera or drone) that reconstructs one warehouse block of cross-stacked egg
trays as a **grid model**: X stacks wide, Y deep, Z trays high per stack. The model is built from:
- three guided photos (STRAIGHT, LEFT, RIGHT), whose provenance is checked (camera only, phone heading, copies counted
  once);
- an optional CORNER photo (width and depth from one capture);
- an optional ELEVATED photo, with the operator's taps on what is seen from above;
- the operator's **blind declaration**, entered before any count is shown.

Every grid cell keeps its sources apart: observed from photos, declared, seen from above, or computed from the
typical height. Each result gets exactly one status:

| Status | Means |
|---|---|
| `exact` | Every stack is visible and verified by two different captures |
| `confirmed` | Visible stacks verified, the declaration agrees with every face, and the interior is declared or seen from above. The basis is shown |
| `estimated` | Some cells are inferred |
| `conflict` | Independent evidence disagrees |
| `needs_view` | A named photo is needed |

It is not a point cloud or a measured mesh.

## Architecture (layers)

| Layer | 0.5.0 contents | State |
|---|---|---|
| Capture (phone) | Live checks, gyroscope heading (45-135°), camera-only provenance, gallery behind a developer switch | Built (0.4.13-0.4.15) |
| Readers | **R1: detector walk** (`rf-walk`). R2: pixel rim reader, **rejected** (`reports/rim-independent-20261101`). R3: 5/6 parity, **disabled** (`reports/cross-stack-20261101`). On-phone layer signal, **killed** (`reports/layer-signal-20261101`) | One validated reader |
| Verification (Q) | A stack is verified by two different **captures** (capture_id; copies of one photo collapse). Readings carry capture_id, reader, physical_stack_id, view, count, evidence, quality and pipeline_version | Built |
| Structure | `block.grid[y][x]`, one physical stack per cell; corner stacks counted once; doubts per column (frame edge, box over two stacks or trays, cut-short end box, floor line, pitch differs) | Built |
| Identity and plan (F) | Blind `block_declaration`: X, Y, interior, missing cells, partial stacks, cover trays, occupancy, a measured reference height (demote only), operator, time | Built |
| Extra views (S, N) | CORNER (width and depth, columns only); ELEVATED (operator taps: present, missing, step, unsure) | Built; **not validated on real photos** |
| Audit | Blind two-person recount fields; physical validation protocol and record schemas | Built; pilot pending |

## Results on existing photos (all development figures)

| Item | Result |
|---|---|
| Saved three-view replays | 22 replays of 14 sets: **0 wrong releases, 0 wrong `exact`** |
| Adversarial library | 25 of 27 pass. The 2 fails are side photos of another block with a real turn and **no declaration**, which no photo-only rule can catch. With the declaration (S14F, R02F) they are withheld |
| Known silent misses | All flagged as doubts. img-30 now reads `estimated` 79, never `exact` |
| Phase E rim reader | Half/double readings on 3 of 14 faces (bar 10%); exact on 18 of 52 readable stacks. **Rejected** |
| Phase P parity | Row typing right on 3 of 7 annotated layers (bar 95%); false flags on 10 correct faces (bar 1). **Disabled.** The 5/6 rule itself holds on every hand-reviewed stack |
| CORNER on real photos | img-12: no stacks found. img-14: a split of 3 \| 4 where the labels suggest 4 \| 3. **Not validated** |
| ELEVATED on real photos | The only blocks with top photos (M16-NEAR, W05) have refused faces, so the comparison cannot be scored |

## Honest limits of 0.5.0
- **`confirmed` is effectively unreachable with three photos.** Front-middle and side-middle stacks are each read by
  one capture, and E (a second reader) was rejected. So any block with hidden stacks also has unverified visible
  stacks.
  - `exact` is reachable only where every stack is seen by two captures: one-stack and one-wide blocks.
  - A second front photo (Phase M) or a validated second reader is the route to more `exact` and `confirmed` results.
- **Occupancy is not measured.** `eligible_egg_trays` has a value only when the operator declares "every counted tray
  holds eggs"; its basis is then `declared`. Otherwise it is unknown.
- **Cover trays:** the detector was not seen to box empty cover trays (3 of 3 checked), but this is not measured.
- **No physical recount exists yet.** Accuracy can be claimed only after `docs/PHYSICAL_VALIDATION.md` has run.

## Tests (measured)
Recorded in PROGRESS.md for the final commit: Worker `npm test`, backend pytest, `flutter analyze`, `flutter test`.

## Deployment
**Staging only** (`npx wrangler deploy --env staging`) after the offline gates.
- Production `4c1480e6` is untouched.
- The phone install and field test need the Redmi connected.
- The Lambda (rim route) is not redeployed: E is rejected.

## 0.5.1 addendum (2026-11-02): sides that repeat the front

The "2 fails" in the adversarial row above (S14, R02: side photos with a real turn) are closed in Worker 0.5.1 for
sides that repeat the front. Such a side gets its depth only from a guided-camera CORNER photo that reads the same
width and depth; otherwise the block is `needs_view`. This also closes the L-100 false 500 found by the MUTAA
validation, and a lone stack whose side photos show a stack behind it (0.5.0: `exact` 40 for 20). The adversarial
library goes to 32 of 33, with 0 wrong releases. The open case S25 (rows standing behind a row, sides not repeating the
front) needs a product decision. Details: `docs/SCAN_JOBS_AND_DEVICES.md`, "Sides that repeat the front (0.5.1)".
