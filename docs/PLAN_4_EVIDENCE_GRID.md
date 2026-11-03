# Plan 4 (draft 2, 2 Nov 2026): measured faces, honest interior, decided by a field pilot

**Count every tray the phone can really see. Use the top of the block only for what it can prove: presence, holes and
steps. Label everything else as assumed. A field pilot with physical counts decides which product to build, before
weeks of work go in.**

- **Status:** draft 2, for the user's approval. Until then Plan 3 (Worker 0.5.1 local, staging 0.5.0, app 0.5.0+27) stays as it is.
- **Critique:** draft 1 was reviewed by three independent critics (physics, validation design, scope). Their
  blockers changed this draft. §11 lists what changed and why.

## 1. Why a new plan (measured, 1–2 Nov)

| Fact | Evidence |
|---|---|
| The backend is one trained detector plus rules | `projec-mutta/2` boxes tray layers. Second readers failed when measured: rim reader, 5/6 parity checker, on-phone layer signal, point clouds |
| It counts well on close, square-on faces | On accepted photos, undoubted columns match two blind counts on 20 of 21 stacks (tier V) |
| Coverage is the real problem | 37 of 94 MUTAA photos pass the photo check; all 33 staging scans were `needs_view`; far faces read about half |
| Most trays of a big block are never photographed | Front and two sides leave (X−2)(Y−1) stacks unseen. About 52% of the trays in the 8 kept MUTAA sets stand in such stacks; W05: 48 of 70 stacks |
| The detector does not see stack tops | Saved staging detections on 7 elevated photos box no interior top (first-row tops only, as face boxes) |
| Heights vary inside a block | W05 interior tops sit a layer lower in places; L-115 stacks are 20–21; W05 front reads 19/20 |
| **No physical count exists** | Every accuracy figure is a Claude visual count (V) or a handwritten label (U) |

## 2. What the physics allows (from the critique's geometry, to be confirmed in Phase 0)

- **A face photo** counts a stack from top to floor. This is the only real count.
- **A top photo:**
  - shows **presence, holes and step-ups**;
  - **mostly hides a one-tray step down on far rows.** Beyond about 22 degrees below horizontal, half or more of
    the lower top is hidden;
  - with the phone held up at arm's length (camera about 2.0 m, top about 1.2 m), frames a usable top only up to
    about **4×4**;
  - with a 1 m handheld pole, about **6×6**, while **10×7 stays marginal**;
  - a front-elevated photo counts X and the near rows; **Y needs a side- or corner-elevated photo.**
- **A level top never proves a count.** A hidden stack one tray short, a cover tray, mixed tray types, a pallet or
  a slope all look level from a phone. With 48 hidden stacks, a correct total at 95% would need each stack to equal
  its neighbour 99.89% of the time, which no pilot can show.
- **Trays seen behind the front stacks** are almost always another stack or block well behind (box-size ratio
  0.53–0.72 in img-26 and img-45), not the row behind. A level row behind is never visible from eye level. These
  trays are a reason to doubt a column, never a reading.
- **Rows that touch the block** cannot be told from the block by any photo. Only the operator can say where the block
  ends.

**Consequence:** for a block more than one stack deep, the honest ceiling from photos is a **labelled estimate**:
counted trays on the faces, and hidden stacks whose presence and steps were checked from the top but whose counts are
assumed. Release it as `confirmed` only if Phase 0 shows hidden stacks equal their neighbours nearly always, or with an
interval (Decision 2).

## 3. Decision 0 (the user, before any work)

1. **What is the count used for?** Stock-take, dispatch or audit.
2. **Acceptable error on a block total:** for example ±1% or ±N trays.
3. **Minimum share of blocks that must get a released total** (any status).
4. **Minutes per block,** and blocks per stock-take.

These set the Phase 0 thresholds and the Phase 5 bars. Without them no gate can say "good enough".

## 4. Two candidate products (Phase 0 decides)

| | **A: faces plus declared layout** | **B: faces plus a top reader** |
|---|---|---|
| Hidden stacks | assumed from the operator's declared layout (X, Y, missing cells) | presence, holes and steps from a trained top-photo detector; counts still assumed |
| Status for deep blocks | `estimated`, labelled "layout declared", never `exact`/`confirmed` | `estimated` (or `confirmed` only under Decision 2) |
| Flags | conflicts between faces and declaration; front holes and steps | plus interior holes and step-ups on near rows |
| New work | small (app and Worker copy, export) | a top detector (training approval, about 100+ labelled tops), the capture flow, a contract change |
| Fits when | declarations are nearly always right, and hidden stacks nearly always equal their neighbours | declarations are often wrong, or holes inside blocks are common |

**Both** keep the measured face counts, refuse when unsure, and never claim eggs inside hidden trays.

## 5. Phase 0: field decision pilot (needs the user, the farm and the phone)

**Runs on what exists:** APK 0.5.0+27 against staging. A staging deploy is not needed for the data: photos and
headings are archived and replay offline on any Worker version.

**Before the farm day:**
- **A truth protocol** (written into `docs/PHYSICAL_VALIDATION.md`). A hidden stack's count may come only from:
  - `lift_count`: taken apart from the top and restored, after the scan's result hash is recorded;
  - `exposed_on_loadout`: cleared row by row, each newly exposed row counted and photographed as a face;
  - `built_counted`: built in the session from counted stacks.

  `from_above` is valid for presence, footprint and steps, **never** for a count. A block's status is scored only
  when every cell has a count; otherwise only its visible cells and footprint are scored.
- **Paper truth sheets** keyed to chalk or tag markers on the front-face stacks and the front-left corner, which are
  photographed. Counters A and B fill separate sheets. The in-app manual count is not used.
- **`scripts/score_physical_pilot.py`:**
  - validates the schemas;
  - checks that every result hash is recorded before truth starts;
  - matches cells by marker;
  - writes per-cell, per-block, per-class and per-status tables.
- **The scored total** is `total_trays` = filled + partly filled + empty layers, cover trays included.
  `eligible_egg_trays` is scored only when its basis is measured.
- **A protocol card for the current app:**
  - order: STRAIGHT, LEFT, RIGHT, declaration, then CORNER (front-left) and TOP (the ELEVATED slot, taps
    skipped), then one upload;
  - no RETAKE or NEW SCAN until both blind counts are recorded;
  - what the result asked for is written down.
- **Phases 1/2 offline work** done before Phase 0 is frozen (commit plus replay hash) before the pilot photos are
  opened, so pilot-1 is a held-out test once.

**On the farm day:**
- **About 10 counted blocks**, at least 6 with full cell truth (built, loaded out or lifted). They include:
  - 2 free-standing deep blocks with a short side of at most 4;
  - plant-and-restore trials on test blocks: 2 interior stacks removed, 2 interior stacks one tray short, plus sham
    plants;
  - 1 block with another block behind across a narrow aisle, and 1 pair of touching blocks, with the intended
    boundary marked.
- **Per counted block:**
  - the TOP photo twice (arms up, and with a 1 m pole or step stool), with framing success and time recorded;
  - 2–3 shots of each face at increasing distance (retraining data with physical truth);
  - the operator's time from the first photo to the result.
- **About 20 cheap TOP-only blocks** (every other block on site): 2 TOP photos each, with footprint, hole and step
  truth from walking round and a ladder (valid for these, never for counts).
- **For the record:**
  - how many blocks stand against a wall (no capture path today);
  - pallets, curbs or slopes;
  - tape-measured heights of 20 stacks of known count.

**Measured outputs (`reports/field-pilot-1/`, photos frozen as registry tier P):**
1. Face coverage and per-stack exact rate on measured faces, with bounds, plus A-vs-B agreement as truth noise.
2. **How often a hidden stack differs from its neighbours** (from cell truth). This decides Decision 2 and A vs B.
3. **Declaration errors** per block (X, Y, missing cells), on the first scan only.
4. TOP-photo feasibility by block size and method (arms up vs pole).
5. Refusals by reason, the share of wall-bound blocks, and minutes per block.

**Decision gate (thresholds come from Decision 0, written down before the farm day):**
- **Product A** if declaration errors and neighbour differences are both near zero.
- **Product B** if declarations are often wrong or interior holes are common, and the TOP photo is feasible.
- Either way, if far or angled faces are a top-three loss, the detector retrain (Phase 4) moves ahead.

## 6. Phases after the decision

### Phase 1 (only if Phase 0 shows depth runs are a top-three loss): depth guard
- A run of boxes above the front stack's top, or at a box-width step of at least 3 sigma against the column's own
  trend, is removed from the front column and becomes a doubt. **Never a reading.** No `measured_partial` and no
  `lower_bound` in 0.6.0.
- **Gate (held out):** 0 front stacks overcounted by trays behind; no regression in replay (0 wrong releases).

### Phase 2 (product B only): top-photo reader
- **2a (done by the critique):** the current detector does not box interior tops.
- **2b:** label the TOP photos by block, at least 100 tops across at least 15 blocks (Phase 0 plus the TOP-only
  blocks), and train a one-class top detector. **This needs the user's approval for a training run and for the
  detector calls.**
- **2c:** turn the detected tops into a footprint and per-cell states (present, missing, step-up). This counts an axis
  only where it runs across the frame, and reads near rows only, where the far edge is at least about 22 degrees
  below horizontal.
- **Gate (sealed blocks only):**
  - each footprint exact or withheld, and 0 wrong footprints that agree with the faces;
  - every planted missing stack found;
  - every planted one-tray-short stack reported as step or unsure, never level.

### Phase 3: result contract (Worker 0.6.0)
- **Cell classes:**
  - `measured` (face, top to floor);
  - `top_present`, `top_missing`, `top_step` (product B; presence and steps only, never a count);
  - `declared`;
  - `assumed`.
- **`block.inventory`** gives counted, assumed (with how the hidden stacks were checked: declared, top photo) and
  cover trays separately.
- **Statuses:**
  - `exact`: one-stack and one-wide blocks with every stack read by two captures;
  - `confirmed`: only if Decision 2 allows it;
  - deep blocks otherwise top out at `estimated`.
- **Depth of more than one stack** (S25) follows Decision 1.
- **Gate:**
  - replay on the adversarial library plus pilot-1: 0 wrong `exact`/`confirmed`;
  - S25 variants, including touching rows, withheld or correct.

### Phase 4 (moves ahead if Phase 0 says so): detector retrain on farm photos
- Use the Phase 0 distance series and faces, with physical truth, to raise face coverage, which is the largest
  measured loss. Needs approval.
- A retrained detector needs a fresh held-out pilot before production.

### App work
- **4a, small, before or right after Phase 0:**
  - ADD PHOTO on the result screen for CORNER and TOP, keeping the declaration, the extras and the heading session;
  - map `suggested_views` to it;
  - fix the fallback that turns an unknown view into LEFT;
  - always offer TOP on the guided path, skippable with a reason;
  - drop the word "optional" where a total depends on the photo;
  - if Decision 0 says stock-take: a block ID in the declaration, a session list of blocks with status and split,
    and a CSV export.
- **4b, after Phase 3:** evidence-class colours and the split total.
- **No operator stack correction on the result screen.** It anchors on the app's number. If the farm needs adjusted
  totals, they go through the blind manual-count path as a separate "operator-adjusted" line. That line is never
  counted as measured, never raises the status, and is excluded from scoring.
- **Wall-bound blocks:** either a "side against a wall" option (a contract change, costed after Phase 0 measures
  how common they are), or declared out of scope.

### Phase 5: pre-registered pilot and the release decision
- **A freeze file** (`reports/field-pilot-2/PREREGISTRATION.md`, committed before the first block) fixes:
  - the Worker and APK versions, the detector id, the thresholds and the scorer commit;
  - every bar;
  - the block-selection, scored-scan and stopping rules.

  Any change during the run ends it.
- **Two sets:**
  - a representative sample (every block meeting a selection rule written in advance) for rates and coverage;
  - an adversarial set (planted errors, S25 layouts) for safety recall.
- **Bars:**
  - run until **30 blocks are released as `exact` or `confirmed` with 0 wrong** (bound about 10%); stop at the
    first wrong one;
  - **coverage of at least C%** (Decision 0);
  - per-class exact rates with bounds;
  - every planted error has its expected outcome (correct or withheld; one tray short never "level");
  - minutes per block within Decision 0.
- **Budget:** at a 50% release rate, about 60 blocks. Production only after the user approves the results.

## 7. What stops now

- **The Claude visual counts of old photos.** The partial report stands.
- **New heuristic readers before pilot data.** Phase 1 is a guard, and only if Phase 0 asks for it.
- **The claim that a level top proves a count.** Draft 1 made it, and the critique showed it false.
- **Point clouds, NeRF and new architectures.** A retrain of the existing detector and, for product B, one small top
  detector are the only model work, each with approval.

## 8. Order

1. **The user:**
   - Decision 0;
   - Decisions 1 and 2 (§10);
   - a farm day, with which blocks will be built, loaded out or lifted, and who counts.
2. **Me, before the farm day:**
   - the truth protocol;
   - the scorer;
   - the protocol card;
   - optionally app 4a (APK 0.5.1+28, install approval).
3. **Phase 0**, then the A-or-B decision with the user.
4. **Then:** Phases 1 to 3 and 4a/4b as the decision says; Phase 4 if faces are the main loss.
5. **Phase 5**, then production with the user's approval.

## 9. Approvals (each asked separately)

- Staging deploys (0.5.1 when wanted, 0.6.0 later). Production stays untouched until Phase 5 is approved.
- APK installs on the Redmi.
- Training runs (top detector, detector retrain).
- Detector (Roboflow) calls for offline reads of new photos, with the count stated.
- Pushes to GitHub.

## 10. Decisions for the user

1. **S25, rows behind the block, with a real turn.** Either require a footprint photo (TOP or CORNER) for any depth
   over one stack, or require an agreeing declaration. Costs:
   - the photo option adds a capture and fails on big blocks;
   - the declaration option rests on the operator.

   Touching rows are always the operator's call.
2. **Can hidden counts ever be `confirmed`?**
   - (a) Never: deep blocks are `estimated`, with the split shown.
   - (b) Only if Phase 0 shows hidden stacks equal their neighbours nearly always.
   - (c) Released as an interval (for example ±1 tray per hidden stack), scored as "the true total lies inside".
3. **Pilot people and day:** the operator, counters A and B, the planter, and the blocks to build, load out or lift.

## 11. What the critique changed (draft 1 → draft 2)

| Draft 1 | Problem found | Draft 2 |
|---|---|---|
| "Level top proves the same count"; `confirmed` built on it | Heights vary by about a layer inside a block; a one-tray step down hides on far rows; untestable at pilot sizes | Top evidence is presence, holes and steps only; `confirmed` only under Decision 2 |
| One handheld top photo for every deep block | Works up to about 4×4 arms-up, about 6×6 with a pole; W05 frames half; Y needs a side view | Phase 0 measures arms-up vs pole by size; the reader reads near rows only |
| Back trays become partial readings of the row behind | They are other blocks well behind; a back stack's floor is never seen | A guard (doubt), not a reading; deferred unless Phase 0 asks |
| Ground truth "as built or loaded out", in-app recount | Circular "from above" counts; in-app recount anchors and lists the app's own cells | Three non-circular methods, paper sheets with markers, scorer script |
| Phases 1–3 gated on pilot photos | Built and tested on the same photos | Freeze before pilot-1; sealed TOP-only blocks; Phase 5 pre-registration |
| Phase 5: 0 wrong in 30 blocks | Needs 30 *released* blocks; no coverage floor, so withholding everything passes | 30 released with 0 wrong, plus a coverage floor and per-class scoring |
| No statement of what the farm needs | No gate can say "good enough" | Decision 0 first; A vs B decided by Phase 0 |
| Operator stack correction | Anchoring; contaminates scoring | Dropped; a blind adjusted line if needed |
| Detector retrain last | Face coverage is the largest loss | Moves ahead if Phase 0 says so; distance series collected |
