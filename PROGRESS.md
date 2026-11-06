# Progress

## 2026-11-06 (latest) - Plan 5 Phase 2: app 0.7.0+31 shows the stacking rule (Claude Code, `rollout/0.4.12-staging`)

**Pushed, not deployed, not installed, 0 detector calls.** Phase 1 committed as `e6afb48` (the user said "do next
steps"), Phase 2 as `389f71e`; both, with this doc update, pushed to `origin/rollout/0.4.12-staging` on 6 Nov at the
user's request ("Push to the context and progress.md"). No phone attached (`adb devices` empty), so no install.
Staging still Worker 0.5.0; production untouched.

**Current state, for whoever picks this up next** (supersedes the "Exact next steps" of the 5 Nov HANDOVER below,
whose step 1, Decision 1 and Phase 1, is done):
- Worker `cloudflare-worker/` = worker-0.7.0 (stacking rule, `docs/GRID_CONTRACT_0.7.0.md`), **not deployed**. Staging
  runs 0.5.0 (`52a1d5e8`); production `4c1480e6` must never be deployed.
- App `mobile/` = 0.7.0+31; APK `egg-tray-counter-0.7.0-staging.apk` built (git-ignored), **not installed**. The Redmi
  (`f76d5e20`) still runs 0.6.0+29; 0.6.1+30 was never installed and is superseded by 0.7.0+31.
- Open for the user: Decision 3 (default (a) built; options compared in
  `reports/stacking-rule-0.7.0-20261105/README.md`); every install, staging deploy and paid call needs their OK.
- Known gaps: FR18 (over-reads on two faces lift H), FR13 (Phase 1b, mixed columns), Decision 18 (partials outside the
  block), the intermittent `pending_scan_test.dart` failure, the research capture mode (not built).
- **App changes** (`mobile/lib`): `models/block_result.dart` reads the 0.7.0 inventory rule fields, `block.rule`
  (`RuleSummary`, `RuleProvisional`) and the split's rule fields (`TraySplit.byRule`); `features/scan_flow/block_view.dart`
  draws rule stacks as "=H" ghosts with the legend "= full by the stacking rule, not seen", the headline "ESTIMATE: N
  COUNTED + K × H BY THE STACKING RULE", `ruleSplitLine` ("Counted 171 + 6 × 20 by the stacking rule = Estimated 291
  tray layers"), `ruleLine` (stacks read the same in two photos, the cover-tray range, "up to" for doubted readings),
  the residual line (Plan 5 §3), a sensitivity row in place of the neighbour range row, words for the 10 new withheld
  reasons, a rule provisional panel (never a total), and released-rule notes; `scan_flow_screen.dart` shows a retake
  view it does not know as text, never as RETAKE LEFT; `declaration_pane.dart` says PARTIAL gives no total and names
  missing/partial stacks as rule exceptions. Version 0.7.0+31 (`pubspec.yaml`, `app_version.dart`). The manual-count
  screen is unchanged (it never shows the app's heights). Older servers' answers render as before.
- **Not built (Plan 5 Phase 2 "recommended"):** the research capture mode for farm day A.
- **Verified (measured, local):** `flutter test` 262/262 (7 new: `worker_070_compat_test.dart` now checks the 0.7.0
  screens on three real Worker 0.7.0 answers; 2 retake-view tests in `scan_screens_test.dart`); `dart analyze` clean.
  Four full runs: three 262/262; one had the known intermittent failure, now named: `pending_scan_test.dart` "the
  declaration and the optional extras survive a relaunch and are uploaded again on resume". That file passed alone
  3/3; neither it nor the code it tests changed here. Plan 5 Phase 4 says to find it first.
- **APK:** `egg-tray-counter-0.7.0-staging.apk` (repo root, git-ignored): `flutter build apk --release` in 184 s,
  64,118,060 bytes, SHA-256 `9384a0728009cf69…`, versionName 0.7.0 / versionCode 31, v2 signer `29013b98…` (the
  release key), 0 hits for the staging admin token or the keystore password in the APK or its 393 unpacked entries.
  Not installed anywhere (the emulator was not started).
- **Next:** (1) Decision 3 (the user's call; default (a) built); (2) with the user's OK and the Redmi plugged in, install
  0.7.0+31 (it replaces the pending 0.6.1+30); (3) then, with the user's OK, deploy Worker 0.7.0 to staging only
  (`--env staging`), smoke test about 7 paid calls; (4) farm day A planning (Plan 5 §8.2, Decisions 15, 18).

## 2026-11-05 (evening) - Plan 5 Phase 1 built offline: Worker 0.7.0 stacking rule (Claude Code, `rollout/0.4.12-staging`)

**Committed later as `e6afb48` and pushed on 6 Nov; not deployed, 0 detector calls.** Staging still runs Worker 0.5.0 (`52a1d5e8`);
production `4c1480e6` untouched; the Redmi still runs app 0.6.0+29 (not plugged in, no install). App code unchanged
(only a new test and fixtures).
- **User decisions:** Decision 1 answered **yes** (hidden stacks = full height H by the stacking rule). Decision 3
  (how strict H is) **still open**: the user said they were confused; it was explained in plain terms, and the build
  uses the recommended default (a) behind one switch (`RULE_DEFAULTS.basis`).
- **Worker 0.7.0** (`cloudflare-worker/src/index.ts`): `stackingRule()` (H: two clean stacks on two faces, a back
  corner among them; the cover partner H ± 1; checks taller / back corner / inside hint / one side / plurality off /
  range off), `assumeHidden()` sets H (`assumed_from: "stacking_rule"`, range [H, H], no neighbours), `assembleGrid()`
  exceptions (`rule_exception`, `inside_step_up`, `inside_declared_partial`, `reference_height_differs`),
  `ruleProvisional()` (in `block.rule.provisional`, never in the inventory), the inventory fields `rule_*`,
  `two_photo_stacks`, `doubted_low_up_to`, the neighbour ranges null for rule blocks, no `elevated` suggestion,
  `grid_contract` 0.7.0, `worker-0.7.0`. Rule-eligible photos: camera stills, not blocked, not copies; a side
  `turned` or `depth_unproven`. Request and fingerprint v3 unchanged. Contract: `docs/GRID_CONTRACT_0.7.0.md`.
- **Tests changed on purpose, each with its reason in a comment:** `hidden.test.mjs` H1–H6, H8 (plus new H3b);
  `block.test.mjs` (2 gap tests: one side photographed is now withheld); `capture.test.mjs` 5 x 4 (sides framed apart
  and sent as camera stills; 380 → 392, the under-read Plan 5 fixes); `grid.test.mjs` version; `side_check.test.mjs`
  5 x 5 (sides framed apart), H11 (no `elevated`), H13 (step-up case withheld, as the plan says); library S21 check
  `total_ok` → `no_wrong_total` (its sides are copies of the front). New: `test/rule_cases.mjs`, `test/rule.test.mjs`
  (FR01–FR21, 43 cases with the FR13 sweeps), a `withheld:<reason>` judge in `replay_benchmark.mjs`.
- **Verified (measured, local):** Worker `npm test` 270 tests, 238 pass, 0 fail, 32 todo (4 old stretch + 28 known rule
  failures). App `flutter test` 258/258 on two full runs (new `worker_070_compat_test.dart`: the 0.6.1 parser and panel
  read three real 0.7.0 answers; "(range not given)", no range row, no "depth not proven" panel); `dart analyze` clean.
- **Replay** (`reports/stacking-rule-0.7.0-20261105/README.md`, offline, 0.6.0 dist from `c4b0360`): all 10 Phase 1
  gates met except gate 3 on two new rule cases. Library 38/38, 15 released (0.6.0: 16), the same 5 known wrong
  estimates; only S21 changed (withheld). 0 face verdicts and 0 of 22 trios changed. 99-block 99 and L-100 withheld in
  every mode; field 4 x 3 (counterfactual) 165 → withheld `no_rule_height`, provisional 165. Two runs, identical hashes.
- **Findings (the user should see these):** (1) FR18, one over-read on each of two faces: 0.7.0 releases 299 for 291
  (0.6.0: 294); the printed range covers the hidden stacks, not the over-read faces. (2) FR13: a short partial with the
  full stack behind showing above it reads as one full column from scale 0.87 (+12), as in 0.6.0: Plan 5 Phase 1b,
  not attempted (its threshold needs farm-day photos). (3) A partial standing in front of a block is missed (Decision
  18). (4) Option (c) on the 4 x 3 is withheld as taller, not released as §4.6 expected (RIGHT's 14 is a third height).
  (5) Option (b) releases 299 for 291 when two over-reads sit in one photo; (a′) loses S26 and S28.
- **Next steps, in order:** (1) the user's call on Decision 3, with the options table in the report; (2) commit this work
  (asked, not done); (3) Phase 2 (app 0.7.0: "=H" ghosts, the rule split line, withheld-reason texts); (4) FR18 is the
  case the plurality guard caught, and the guard is off because covers are "sometimes" (Decision 4). Turned on, it also
  withholds FR17, a genuine block with covers on 3 of 8 face stacks. Farm day A's cover count should settle it;
  (5) the Redmi install of 0.6.1+30 or straight to 0.7.0 when it is plugged in, with the
  user's OK; (6) staging 0.7.0 only after app 0.7.0 is on the phones.

## 2026-11-05 - HANDOVER: project state and where to start (Claude Code, `rollout/0.4.12-staging`)

The project is handed to another coding agent (the Claude weekly limit was reached). Project path:
`C:\Users\rahul\egg-tray-counter-mobile`. Branch `rollout/0.4.12-staging`, pushed to `origin` at the commit that
follows this section. The working tree is clean after that push.

**Read first:** `AGENTS.md`, this file, `context.md` (top entry: the farm's stacking rules), and
`docs/PLAN_5_MULTI_PHOTO.md` (draft 3, not approved). Plan 4 (`docs/PLAN_4_EVIDENCE_GRID.md`) is older and not approved.

**What is built and where it stands:**
- App `mobile/` is version 0.6.1+30 (`aa6eab5`): gallery photos over 40 MP are shrunk, not refused; offline demo
  screen; 0.6.0 evidence grid (ghost stacks, counted/assumed split).
- Worker `cloudflare-worker/` is worker-0.6.0, merged locally and **not deployed**. Staging
  (`egg-tray-counter-api-staging`) runs Worker 0.5.0 (version `52a1d5e8`). **Production `4c1480e6` is untouched; never
  deploy it.**
- Phones: Redmi Note 9 Pro (`f76d5e20`) runs 0.6.0+29. The 0.6.1+30 install is pending (phone must be plugged in,
  with the user's OK). Emulator `emulator-5554` runs 0.6.1+30.
- APK for the phone (git-ignored, repo root): `egg-tray-counter-0.6.1-staging.apk` (SHA-256 prefix `2e3651e5ddc991f6`,
  signer `29013b98…`, versionCode 30).
- Zero physical counts exist. Every count so far is an AI or label reading.

**Decisions and approvals outstanding:**
- Plan 5 Decision 1: adopt the stacking rule and build Phase 1 (Worker 0.7.0, offline). Not yet answered.
- Plan 5 Decision 3: how strict "H" is (recommended: two stacks on two faces, a back corner among them).
- Answered: cover trays are used "sometimes" (Plan 5 §4.6; `context.md`).
- Every deploy, install, push and paid detector call needs the user's OK. Staging deploys use `--env staging` only.

**Rules that stay in force:**
- Never run a bare `wrangler deploy` or `npm run deploy`.
- Never print the admin token (`work/secrets/staging-admin-token`) or the keystore password. Both are git-ignored.
- No paid detector calls without approval. `accuracy-evaluation/*` is frozen. Do not open the personal phone gallery.
- No new neural network, VLM, NeRF or photogrammetry (Plan 3 rule). Tray layers only, never eggs or rupees.
- Never use "exact", "confirmed" or "physically verified" for a value that rests on a rule or a declaration.

**Tools and checks:**
- Flutter: `C:\Users\rahul\AppData\Local\Codex\flutter\bin\flutter.bat` (not on PATH). Run `flutter test` and
  `dart analyze lib test` in `mobile/`. Last result: 255 of 255 tests pass; analyzer clean.
- Worker: `npm test` in `cloudflare-worker/` (tsc, then node --test). Last result: 214 tests, 210 pass, 0 fail, 4 todo.
- adb: `C:\Users\rahul\AppData\Local\Android\Sdk\platform-tools\adb.exe`. Use `-s f76d5e20` for the Redmi.

**Worktrees** (`git worktree list`): `real-worker` and `real-app` hold branches already merged into this branch
(`real/worker-0.6.0`, `real/app-evidence-grid`); they can be removed. `vigilant-napier-c0487d` and
`affectionate-heyrovsky-9ff357` are older Plan 3 side sessions, not merged and not reviewed in this handover; leave
them alone unless the user asks.

**Known open issues (not fixed):**
- One earlier full test run had a single failure in `test/pending_scan_test.dart` that did not repeat.
- The old-format fallback split does not check that counted + assumed adds up to the total.
- `traySplitLine` prints "Assumed 0" when the assumed part is unknown.
- Taller and shorter badges of neighbouring hidden stacks can overlap on the block drawing.
- The demo screen's header uses the raw status, not the display status.

**Exact next steps, in order:**
1. Ask the user for Plan 5 Decision 1 and Decision 3. If Decision 1 is "yes", build Phase 1: `ruleHeight()` in
   `index.ts`, the checks of §4.2, the `test/rule.test.mjs` cases FR01–FR20, the replay under
   `reports/stacking-rule-0.7.0-<date>/`. Nothing is deployed or pushed without a separate OK.
2. When the Redmi is plugged in and the user agrees: `adb -s f76d5e20 install -r` the 0.6.1+30 APK, then check
   the scan screens.
3. Staging for Worker 0.7.0 only after app 0.7.0 is on the phones (Plan 5 Phase 2). Farm day A follows (Plan 5 §8.2).

## 2026-11-05 - farm stacking rules and Plan 5 draft 2 (Claude Code, `rollout/0.4.12-staging`)

Planning only: no code changed, nothing deployed. Staging still runs Worker 0.5.0; the Redmi runs app 0.6.0+29;
app 0.6.1+30 is built (`egg-tray-counter-0.6.1-staging.apk`) and pushed as `aa6eab5`.
- **Farm rules stated by the user** (context.md, 5 Nov): partial stacks only on the photographed faces (STRAIGHT,
  LEFT, RIGHT), back row always full, no empty interior position, full height per block shown by the faces, back side
  usually against a wall, photos from above or below impractical. Not audited; physical counts still zero.
- **Answered:** a frontier VLM is not a source of exact counts (measured here: AI counters disagreed on 21 of 29
  photos; L-115 read 771 / 897 / 1455). The Plan 3 "no VLM" rule stands unless the user lifts it.
- **`docs/PLAN_5_MULTI_PHOTO.md` (draft 2, not approved):** hidden stacks = the block's full height H "by the stacking
  rule" instead of the 0.6.0 neighbour median (`index.ts:656-681`, which under-reads hidden stacks behind a face
  partial); H from clean readings of two distinct stacks on two different faces, a back corner among them; extra
  photos (a repeat of a face, a long face in parts, a close photo of one stack on request) that never make a block
  `exact`; two farm days (A audits the rules by opening blocks at random; B is a pre-registered blind pilot).
  Phases: 1 server rule offline (Worker 0.7.0) → 2 app wording (0.7.0) → 3 farm day A → 4–6 multi-photo (0.7.1–0.7.3)
  → 7 farm day B. Written by a 9-agent workflow (`wf_2f112f3e-f94`: 3 readers, 2 drafts, merge, 2 critics, editor);
  key code citations spot-checked by hand.
- **Measured cost of the default H rule** [R, offline replay on worker-0.6.0]: the only real deep block (field 4 × 3,
  counterfactual inputs) has one clean face reading, so it is withheld until a close photo (Phase 5).
- **Decision 4 answered (user, 5 Nov): cover trays are used "sometimes".** Plan 5 draft 3 adds §4.6: a full stack is F or
  F + 1 layers; H and its neighbour are both "full"; the hidden stacks are reported as K × H with a range of up to K;
  the plurality guard is off and the taller check fires only beyond the pair.
- **Next:** the user's answer to Decision 1 (adopt the rule and build Phase 1 offline), then Decision 3 (how strict H
  is); the Redmi install of 0.6.1+30 when it is plugged in.

## 2026-11-04 - offline demo, real work merged, app 0.6.0+29 (Claude Code, `rollout/0.4.12-staging`)

For the faculty demo on the morning of 4 Nov. **Local only: nothing pushed or deployed. Staging still runs 0.5.0
(52a1d5e8); production 4c1480e6 untouched.**
- **Offline demo** (`db66925`, app 0.5.1+28): home button "DEMO — SAVED RESULTS (NOT A LIVE SCAN)" opens
  `mobile/lib/features/demo/demo_screen.dart`, three saved test-server answers bundled in `mobile/assets/demo/`
  (99-tray row, 4 x 3 field block 105 counted + 60 assumed = 165, L-100 refused). Nothing is sent or saved.
  Cheat sheet `docs/DEMO_CHEAT_SHEET_20261104.md`; screenshots `reports/demo-20261104/`.
- **Merged** `real/worker-0.6.0` (`c63f497`) and `real/app-evidence-grid` (`8ad17f4`); conflicts only in PROGRESS.md
  and context.md, both entries kept. Worker 0.6.0 stays undeployed (its deploy gate needs an app that reads
  `suggested_inputs`: app 0.6.0+29 now does).
- **Fixes after an independent review of the app branch** (no crash and no arithmetic error on the 12 saved 0.6.0
  answers or the 3 demo answers): removed "Eggs if every tray is full" from the block panel (it showed 4950 on the
  4 x 3 demo, capacity on 60 assumed trays); the "if every hidden stack is there" range is hidden on a withheld block;
  the assumed row no longer says "(N checked from the top)" (that count includes stacks tapped missing); the
  declaration pane no longer says "can never be CONFIRMED".
- **Version** 0.6.0+29 (`pubspec.yaml`, `app_version.dart`).
- **Verified (measured):** Worker `npm test` 214 tests, 210 pass, 0 fail, 4 todo; `dart analyze` no issues;
  `flutter test` 252 of 252 (one earlier full run had one failure in `pending_scan_test.dart` that passed alone and on
  the next full run: the intermittent failure the app branch also saw, still not identified).
- **APK** `egg-tray-counter-0.6.0-demo-staging.apk` (repo root, git-ignored): 63,888,684 bytes, SHA-256 prefix
  a8320338f21a54f9, versionName 0.6.0 / versionCode 29, signer SHA-256 29013b98…, 0 hits for the staging admin token
  or the keystore password in the APK or its unpacked files. Installed on the emulator (emulator-5554); the demo's
  three tabs render (screenshots in `reports/demo-20261104/`, replaced with the 0.6.0+29 view): the 4 x 3 block shows
  4 see-through "~15" stacks, the eggs row is gone.
- **Redmi (f76d5e20), 09:16 IST, with the user's OK:** `adb install -r` upgraded 0.4.12 (23) to 0.6.0 (29) in place
  (data kept). The app opens with the demo button; Settings show the staging base URL and "DEVICE APPROVED" (nothing
  changed or saved).
- **Pushed** to `origin/rollout/0.4.12-staging` (`10f2c3d..59fb8d1`) with the user's OK.
- **Phone test** (`reports/phone-test-20261104/`, measured, staging 0.5.0, 6 detector calls): laptop photos pushed
  to the Redmi and scanned through the gallery path. L-100 (img-19/21/24): RETAKE NEEDED, no total (sides repeat the
  front), per-photo detections 103/100/101. 99-tray row (img-01, warehouse image-4, img-32): BLOCK ESTIMATE 99 with the
  3D grid 20/20/20/20/19. Both repeat earlier answers for the same photos; the 99 trio is a worked example. Gallery
  scans switched back off; the test photos stay in `/sdcard/Pictures/EggTrayTest/`.
- **Phone audit** (`reports/phone-audit-20261104/`, measured, staging 0.5.0, 6 detector calls): MUTAA photos never
  used as a block set. A, a 3-stack row (front `151210436`, right end `151224648`, stand-in left `151204619`): 3D grid
  3 × 1 at 10/10/11 against a blind manual 10 filled + 1 cover each, total withheld (stand-in LEFT refused as too far).
  B, the M16 block from new angles (`151353868`/`151339474`/`151436402`): RETAKE NEEDED, no model (gallery sides cannot
  prove depth; LEFT read 3 deep against manual 2). 0 wrong totals. **Finding:** the app's gallery path refuses photos
  over 40 MP (`photo_upload_pane.dart:27`); 4 MUTAA photos are 50 MP. No complete new block set is left in MUTAA.
- **App 0.6.1+30: gallery photos over 40 MP are shrunk, not refused** (`photo_upload_pane.dart`:
  `encodedPixelSize`, `OversizedPhotoException`, `shrinkWithPlatformDecoder`, `prepareGalleryPhoto`). The size check
  no longer runs the image package's `startDecode`, which allocated about 300 MB for a 50 MP JPEG. Verified: 3 new tests,
  `flutter test` 255/255, `dart analyze` clean; on the emulator the 8192 x 6144 MUTAA photo is accepted in about 6 s.
  APK `egg-tray-counter-0.6.1-staging.apk` (git-ignored): 64,019,756 bytes, SHA-256 prefix 2e3651e5ddc991f6, signer
  29013b98…, 0 secret hits. **Redmi still on 0.6.0+29** (unplugged before the install).
- **Next:** install 0.6.1+30 on the Redmi when it is plugged in (with the user's OK); the user's call on Decision 1 (corrected) and contract §6; staging deploy of Worker 0.6.0 with
  approval; the farm day with physical counts.
- **Open review notes (not fixed, not on the demo data):** the old-format fallback split does not check that counted
  + assumed adds up to the total; `traySplitLine` prints "Assumed 0" when the assumed part is unknown; taller/shorter
  badges of neighbouring hidden stacks can overlap; the demo header uses the raw status, not `displayStatus`.

## 2026-11-03 - app 4b: evidence classes and the counted/assumed split (Claude Code, branch real/app-evidence-grid)

Plan 4 app work 4b, built from the 0.6.0 final design in parallel with the offline demo. App code only: no Worker
change, no APK, no version bump, nothing deployed or pushed.

- **Parsing** (`mobile/lib/models/block_result.dart`): the 0.6.0 cell fields (`evidence_class`, `hidden`,
  `assumed_layers`, `assumed_range`, `assumed_from`, `neighbours`, `top_tap`, `flags`, `past_gap_*`), the 0.6.0
  inventory (counted/assumed/estimated, ranges, hidden and top-checked stacks, missing stacks, `released`,
  `withheld_reason`, `provisional` with `if_depth`) and `depth_basis`, `grid_contract`, `suggested_inputs`.
- **Older answers** get a derived class (`evidenceClassOf`, `evidenceClassOfBlockCell`) by the design's table. A stack
  whose every reading looked through a gap (`*-recessed` source) is assumed, never counted. The split for older
  answers comes from the stacks, not `computed_trays`; 0.4.x cells that do not cover the block fall back to
  `observed_trays`/`computed_trays`. An older `exact` with such a stack is shown as an estimate (`displayStatus`).
- **Drawing** (`block_view.dart`): counted stacks solid with layer ticks; assumed stacks see-through, hatched, "~N",
  no ticks; top-view present with a blue top outline; step up "▲ ≥N" with a "taller" badge; step down "▼ ?";
  seen-empty a dashed red footprint; top-missing and declared-missing a footprint plus a "0" outline on the block's
  top; conflict orange. The legend lists the classes in the block.
- **Panel** (also on the result screen): headline "ESTIMATE: N COUNTED + M ASSUMED IN K HIDDEN STACKS"; the split
  line "Counted N + Assumed M (range lo–hi) = Estimated T tray layers" ("range not given" for older servers); an
  assumption line; "Egg-filled trays: not checked" unless declared; "TOTAL WITHHELD" with the reason; a grey
  "NOT RELEASED" panel for provisional figures (never a headline, history total or app total); "DECLARE THE BLOCK SIZE
  AND SCAN AGAIN" when the server asks for it.
- **Wording:** a 0.5 `confirmed` is shown as "BLOCK ESTIMATE" / "ESTIMATE (OLDER SERVER)"; the panel never says
  exact, confirmed or verified for a total with assumed stacks. `BlockPanel` and the `BlockResult` API are
  unchanged for the demo screen (checked locally against its three saved answers; the demo's own strings do not
  collide).
- **Verified (measured):** `flutter analyze` no issues; `flutter test` 247 of 247 in 4 of 5 full runs. One full run had
  one failure that did not repeat in four reruns; not identified. New: `test/evidence_grid_test.dart` (25 tests),
  `test/support/grid_06_fixtures.dart`, 2 result-screen tests.
- **Not done:** the tap cycle with `step_up` (`elevated_tap_grid.dart`), the per-cell detail ("neighbours read
  19–20"), export changes, the Worker 0.6.0 side. The app was not run on a device or emulator.

## 2026-11-03 - Worker 0.6.0: review fixes (Claude Code, branch `real/worker-0.6.0`)

A review of the two 0.6.0 commits below; fixes in one more commit on the same branch. **Local only: not deployed, not
pushed, not merged.**
- **Declaration:** a partial stack of 0 trays is a declared missing stack (it used to be a present stack of 0 that
  blocked eligible trays); a cell listed twice as missing counts once; two different declared heights for one stack are
  a conflict; a declared partial stack where a face shows a gap is a conflict with or without a height.
- **`exact`** also needs Y = 1 in `assembleGrid`, whatever `depthBasis` a caller passes.
- **`block.total_eggs`** is null whenever any tray is assumed (kept for app 0.5.0, which shows it only without a grid).
- **Replay:** S09's stretch is a guard now (it passes: withheld without a declared size); the runner reports a stretch
  with `fixed_by` null as a test, not a todo. `scripts/compare_replay_versions.mjs` and `scripts/replay_saved_scans.mjs`
  write `comparison_with_worker_0_5_1` and `saved_scans` into `summary.json`, which now regenerates byte for byte.
- **Texts:** the report folder is `reports/evidence-grid-0.6.0-20261103` (the work was done on 3 Nov, not 4 Nov); the
  "depth differs ... names the retake" comment and contract text corrected (the rescan names no side, as in 0.5.1);
  context.md marks Decision 1 (corrected) and "exact for one-deep only" as design defaults awaiting the user's call.
- **Deploy gate** (contract, top): no deploy of 0.6.0 before an app that reads `suggested_inputs`. App 0.5.x shows
  "RETAKE LEFT" for a `depth_unproven` side, and retaking can never release the block; only declaring the size can.
- **Worktree:** the skip-worktree bits are cleared and the root APKs and `datasets/` restored in this worktree.
- **Verified:** `npm test` 214 tests, 210 pass, 0 fail, 4 todo (S03, S04, S07 and S29 stretches). Replay re-run:
  adversarial 38 of 38, 0 wrong `exact`/`confirmed`, trios and face verdicts unchanged.
- **Open for the user** (contract §6): through-gap heights that disagree are still a conflict; an honest 5 x 1
  declaration for a row with rows touching it (S27) is withheld for good; Decision 1 (corrected) and "exact for
  one-deep only" await the user's call.
- **Not done:** app 4b is on the parallel branch `real/app-evidence-grid` (worktree `.claude/worktrees/real-app`).

## 2026-11-03 - Worker 0.6.0: evidence grid and hidden-tray calculation (Claude Code, branch `real/worker-0.6.0`)

Plan 4 Phase 3, Worker side, run in parallel with the offline demo (main checkout). Built from `10f2c3d` in the
worktree `.claude/worktrees/real-worker`. **Local only: not deployed, not pushed, not merged.**

**Done.**
- **Hidden stacks are assumed, never counted.** A stack no face photo sees gets the median of its line-of-sight
  neighbours (the front stack in its column, the side end stacks in its row); with none, the block's most common
  face height. The range is the neighbours' spread, not a bound. Each grid cell names its `evidence_class`.
- **`block.inventory`** splits counted and assumed trays: `counted_trays`, `assumed_trays`, `estimated_total`,
  `estimated_range` ("if every hidden stack is there at its neighbours' heights"), `hidden_stacks`,
  `unchecked_hidden_stacks`, missing stacks by kind, `released`/`withheld_reason`, and `provisional`.
- **Top view:** presence, holes and step-ups only (`step_up` tap added). A `missing` tap is the only way a top view
  lowers a total; a step down makes the height unknown and withholds the total.
- **Depth proof (Decision 1, corrected):** a CORNER photo cannot prove depth (it sees the same touching rows: S25C).
  A depth over one stack needs the declared block size; a side that repeats the front also needs the CORNER photo.
  Withheld blocks get provisional figures (front row counted, and the what-if total when only the depth is in doubt).
- **Statuses:** `confirmed` is never returned; `exact` only for one-deep blocks. Trays seen through a gap are hints.
- Contract `docs/GRID_CONTRACT_0.6.0.md` (includes the top view's purpose); `PIPELINE_VERSION` `worker-0.6.0`.
- Scripts: `scripts/replay_saved_scans.mjs`, `scripts/compare_replay_versions.mjs`.

**Verification (measured, offline).**
- `npm test` (tsc, then node --test): 213 tests, 208 pass, 0 fail, 5 todo. New: `test/hidden.test.mjs` (H1–H9),
  H10–H13 in `test/side_check.test.mjs`.
- Replay `reports/evidence-grid-0.6.0-20261103`: adversarial 38 of 38; Worker 0.5.1 on the same library 36 of 38
  (S25 and S25C: `estimated` 300 for 100). 0 wrong `exact`/`confirmed`. Trios (4 of 22 released, 0 wrong) and all
  face verdicts unchanged. Right releases 11 in both; 0.6.0 drops the 2 wrong ones.
- Saved scans: the 99-block stays `estimated` 99. The 4 x 3 field block (9b4c783e) is withheld as sent; with
  counterfactual camera headings, a synthetic CORNER photo and the 4 x 3 declaration it is **165 = 105 counted + 60
  assumed (range 163–167)**; the visual reading is 164 (tier V). L-100 stays withheld.
- **Cost:** a square block with a CORNER photo but no declaration (S21 as in 0.5.1, right at 180) is now withheld.

**Not done.** App 4b (`mobile/`, on 0.5.1+28) was not touched. No staging deploy (needs approval). No physical count.
**Disk:** C: reached 0 MB free during this session. I removed only my worktree's copies of the root APKs and
`datasets/` (marked skip-worktree in that worktree's index); the main checkout was not touched. (Restored and the
bits cleared in the review pass above.)

**Next.** App 4b (evidence-class colours, split rows, provisional panel, `step_up` tap, "declare the block size"
prompt); the user's call on the open points in the contract §6; staging deploy of 0.6.0 with approval.

## 2026-11-03 - pitch deck and October weekly/monthly reports (Claude Code)

- **Pitch deck** (13 slides, plain language) for the user and the faculty guides: https://claude.ai/artifact/A5wetZ31tYgQLLdVgVkZLm
  (private until shared). It covers what the app does, the statuses, what was measured, the hidden-stack limit, the
  journey from August to November, Plan 4 and what is needed next.
- **October reports** in `reports/monthly-review-2026/`, each as DOCX and PDF, in the August/September format:
  - `October_2026_Monthly_Progress_Review` (5 pages);
  - `October_2026_Week_1..5_Progress_Report` (4–5 pages each; weeks 1–7, 8–14, 15–21, 22–28 and 29–31 October).
- **How they were built:**
  - The facts come from `october-2026-weeks.json`: five agents read PROGRESS.md, git history and the linked reports,
    and every number names its source.
  - Built by `build_october.py`. `build_reviews.py` `base()` gained keyword arguments; the defaults keep August and
    September unchanged.
  - Rendered by `render_review_pdfs.py <files>`, with compact image sizes only for the files named.
  - Verified: text with no lost characters; pages inspected in the browser.
- **Committed and pushed** on 2026-11-03 to `rollout/0.4.12-staging`, with the Plan 4 draft.

## 2026-11-02 (latest) - MUTAA validation of build 0.5.0 on staging: app vs blind manual counts (Claude Code, in progress)

**Done (measured).**
- All 94 MUTAA/labelled photos went through staging Worker 0.5.0 (52a1d5e8) exactly as the app prepares them
  (`scripts/validate_build_staging.py`; 33 scans, answers in `reports/mutaa-validation-0.5.0-20261101/raw/`).
  Every scan returned `needs_view` with no total, which is the 0.5.0 contract for gallery photos.
- The photo check accepted 37 photos and refused 57. The app read 261 columns, 135 of them with doubts.
- Offline what-if (`scripts/replay_mutaa_validation.mjs`, `replay-what-if.json`): L-100 replayed as guided-camera
  captures with a 90-degree turn gives **`estimated` 500 for a block counted at 100** (with a declaration: `conflict`).
  This false total is the main blocker found.
- Blind visual counts by subagents (tier V, not physical): `manual-blind.json` assembled from three runs
  (`scratchpad/validate/assemble_blind.py`); `scripts/compare_mutaa_validation.py` → `comparison.json`.
  - Accepted photos, stacks with double-counted manual truth: 29 of 42 match (cover tray either way), 2 off by 1,
    11 off by 2 or more. 10 of the 11 big misses carry a doubt or gap fill. Clean columns: 20 of 21 match.
  - One clean wrong column on an accepted photo: IMG_20260916_151409127, back-block stack at x 0.66, app 7 vs 15.
  - The two blind counters disagreed on 21 of 29 double-counted accepted photos, so the manual truth itself is noisy.

**Not done.** 31 refused photos have no manual count; 21 accepted photos lack the third (recount) pass; 13 refused
photos lack a second count. Report README written (partial).
Usage limits stopped the counting runs four times (see memory notes on cost and resume). The validation files, the 0.5.1 fix and the 14 earlier commits are pushed with this entry (the user asked on 2 Nov).

**Worker 0.5.1 (local, not deployed): the L-100 false 500 fixed.**
- A turned side whose heights repeat the front gets its depth only from a guided-camera CORNER photo that reads the
  same width and depth and sees that side. Otherwise the block is `needs_view` with `suggested_views: ["corner"]`.
- Neither a declaration nor ELEVATED taps settle it. A settled side never verifies a stack.
- A one-stack front with deeper sides is treated the same way.
- Docs: `docs/SCAN_JOBS_AND_DEVICES.md` "Sides that repeat the front (0.5.1)", the addendum in `docs/RELEASE_0.5.0.md`,
  and `context.md`.
- **Independent review** (3 reviewers: correctness, bypass, field). Fixed after it:
  - ELEVATED taps were effectively the declaration;
  - a disagreeing CORNER photo leaked the false grid;
  - a front-left CORNER photo vouched for RIGHT;
  - a blocked CORNER photo counted;
  - lone-stack sides gave `exact` 40 for 20;
  - the retake order;
  - leaked single-reading cells.
- **Verification (measured):**
  - Worker `npm test`: 189 pass, 0 fail, 5 todo; `tsc --noEmit` clean.
  - Replay `reports/replay-0.5.1-20261102`: adversarial 32 of 33 (0.5.0: 25 of 27); 0 wrong releases and 0 wrong
    `exact` on 22 trios; labelled faces unchanged.
  - MUTAA what-if: every set and mode is `needs_view`, L-100 included.
  - Cost: S02 and S20 (correct estimates, even 3x2 blocks) are withheld until a CORNER photo is added.

**Open.**
- **S25 (user decision asked):** rows standing behind a row, with a real turn, give 300 for 100.
- **App:** needs an "add CORNER photo" action on the result screen; the copy still calls CORNER optional.
- **CORNER photos are untested on real blocks.**
- **Staging is still Worker 0.5.0.** Redeploying 0.5.1 needs approval.

**Production readiness: no.** The L-100 blocker is fixed in code. Still blocking:
- S25;
- the app flow for the CORNER photo;
- no guided-camera scan of a real block validated;
- APK 0.5.0+27 never installed on the phone;
- the physical pilot (`docs/PHYSICAL_VALIDATION.md`) not run.

**Plan 4 drafted** (`docs/PLAN_4_EVIDENCE_GRID.md`, draft 2, not approved; committed 2026-11-03).
- Draft 1 was critiqued by three independent reviewers. They found that a level top does not prove a count, that a
  handheld top photo works only up to about 4x4, that the hidden-stack truth was circular, and that there was no
  statement of what the farm needs.
- Draft 2 starts with the user's Decision 0, then a field decision pilot (truth from lift, load-out or built blocks)
  that picks product A (faces plus declared layout) or B (faces plus a trained top reader).

**Next.** The user: Decision 0 and Decisions 1–2 of Plan 4, and a farm day. Me: the truth protocol, the scorer and the
protocol card before the farm day. The remaining Claude visual counts are dropped (Plan 4 §7).

## 2026-11-01 - Plan 3 executed: release 0.5.0, phone-only X/Y/Z grid counter (Claude Code)

Plan: `C:/Users/rahul/.claude/plans/spicy-growing-flame.md` (Plan 3, execution; the user's specification).

**Reconciliation (read-only first).**
- Local `rollout/0.4.12-staging` contains `origin/codex/hybrid-cell-counting` (`7971117`, 0.4.12+23) as an ancestor.
- Commits from this session and the last are **not pushed**.

**Side sessions.**
- **K2** (on-phone layer signal) finished and its kill rule fired. Pitch within 10% on 46.8% of columns (bar 90%);
  half or double pitch on 28.1% of faces (bar 10%). Brought in as a negative result (`a69e748`, not wired).
- **E** stopped mid-rewrite. It was continued here.

**Step 1: hand-reviewed annotations** (`benchmarks/annotations-20261101`, tier V, 11 columns).
- The 5/6 alternation holds on every reviewed stack.
- The end-layer parity matches every known count and contradicts all three known misses (img-30 c2 and c4, L-109 c4).
- Empty cover trays on 6 of 11 columns; the detector did not box them where checked.

**Phase E: independent rim reader** (`backend/app/vision/rim_count.py`, `reports/rim-independent-20261101`).
- It takes only the column x-range from the detector, and its thresholds were frozen before scoring.
- **REJECTED:**
  - half or double readings on 3 of 14 faces (bar 10%);
  - exact on 18 of 52 readable stacks;
  - it contradicts a correct detector count on 33 stacks.
- **Cause:** cross-stacked layers alternate polarity, so the pair period dominates (the same failure as K2).
- Not wired; `RIM_VERIFY` stays off.

**Phase P: 5/6 parity and occupancy** (`backend/app/vision/cross_stack.py`, `reports/cross-stack-20261101`).
- **DISABLED:**
  - row typing right on 3 of 7 annotated end layers (bar 95%);
  - false unboxed-layer flags on 10 correct faces (bar 1). The egg colour mask also catches white walls and
    neighbouring stacks.
- **Consequence:** occupancy is unknown unless declared.

**Worker 0.5.0** (`f6c2111`, `0a2c99b`; contract `docs/GRID_CONTRACT_0.5.0.md`).
- **Q, readings:** each carries capture_id, reader (rf-walk), physical_stack_id, view, count, evidence, quality and
  pipeline_version. A stack is verified by two different captures; copies of one photo collapse.
- **`block.grid[y][x]`:** one physical stack per cell (corners counted once), with z / filled / partial / cover /
  unknown layers, views, sources, status and uncertainties.
- **`block.inventory`:** observed, computed, declared and top-view layers kept apart. Eligible egg trays are given only
  from declared occupancy.
- **F, `block_declaration`:** a size, missing cell or partial stack that contradicts a face gives `conflict`. A
  measured reference height only demotes. A declaration never gives `exact`.
- **S, CORNER:** width and depth around the nearest stack.
- **N, ELEVATED:** operator taps (present, missing, step down, unsure); the flush-top rule is conditional.
- **`confirmed`:** visible stacks verified, the plan agrees, and the interior is declared or seen from above. The basis
  is shown.
- **Manual counts** store `counted_by` and `second_counter`.
- **A refused photo keeps `needs_view`.**

**App 0.5.0+27** (`3b5c868`, built by a subagent, verified here).
- A blind declaration pane after the three photos and before upload, asked once per block.
- Optional CORNER and ELEVATED extras, plus a tap grid.
- The extruded grid result, labelled "not a point cloud or measured mesh".
- The confirmed look names its basis and never says "exact".
- Recount name fields.

**Validation tooling:** `docs/PHYSICAL_VALIDATION.md` and `benchmarks/validation-schema/*.schema.json` (recount,
planted error, declaration freeze, result hash).

**Report:** `docs/RELEASE_0.5.0.md`.

**Tests (measured).**
- Worker: 182 tests, 176 pass, 0 fail, 6 todo.
- Backend pytest: 155 pass. The 34 ruff errors predate this work and are in other files; the new files are clean.
- Flutter: analyze clean, test 220/220.
- **Replay** (`reports/replay-0.5.0-20261101`):
  - 22 saved trios: 0 wrong releases, 0 wrong `exact`;
  - adversarial: 25 of 27 pass. The 2 failures are another block's sides with **no** declaration; with a declaration
    (S14F, R02F) they are withheld.

**Offline checks of the extras.**
- **CORNER is not validated:** img-12 finds no stacks; img-14 splits 3 | 4 where the labels suggest 4 | 3.
- **ELEVATED cannot be scored:** the only blocks with top photos have refused faces.

**Honest limits.**
- `confirmed` is effectively unreachable with three photos: front-middle and side-middle stacks are read by one capture,
  and E was rejected.
- Occupancy is not measured.
- There are 0 physical recounts.

**Staging deploy (authorized by the user's specification after the offline gates).**
- `npx wrangler deploy --env staging` gave version `52a1d5e8-f8fa-425d-a98d-64fdfbad78d6`, observe mode. Production is
  untouched and its /health still shows the old contract.
- **Smoke scan on staging** (L-100 photos, declared 5 × 1, admin token not printed):
  - `worker-0.5.0`, `conflict`, total null, "declared 1 stacks deep, the side faces show 5";
  - a 5 × 5 grid with Q reading fields;
  - occupancy unknown.

**APK:** `egg-tray-counter-0.5.0-block-staging.apk` (repo root, git-ignored).
- 63,738,769 bytes, SHA-256 a641bc9196fefca5d12e16e0c522875dc767ade20dc6ddc1c0497e018bd351ec.
- aapt: versionName 0.5.0, versionCode 27.
- apksigner: release signer 29013b98..., the same as 0.4.12 and 0.4.13, so `adb install -r` upgrades in place.
- No admin token or keystore password strings in libapp.so.

**Not done.**
- **Phone install and field test:** no device was connected (`adb devices` empty).
- **The physical validation pilot.**
- **The user's blind counts (D2).**
- **Pushing the branch.**
- **Archiving the E/K2 side sessions** (needs the user's OK).

**Next.**
1. Connect the Redmi, run `adb install -r egg-tray-counter-0.5.0-block-staging.apk`, and run the protocol in
   `docs/PHYSICAL_VALIDATION.md`.
2. A second reader, or a STRAIGHT-2 capture (Phase M), so that wide blocks can reach `exact` / `confirmed`.
3. The user decides on pushing.

## 2026-11-01 (later) - Plan 2: capture provenance and frame doubts (Worker 0.4.15, app 0.4.15+26) (Claude Code)

**Plan 2** (`C:/Users/rahul/.claude/plans/spicy-growing-flame.md`, approved by the user) answers "more client-side
constraints, and a real 3D counter". It came from a 10-agent workflow: 2 repo readers, 3 web researchers, 3 designs,
a critic and a synthesis. Its key verdicts:
- Every phone gate needs a server mirror.
- A "3D counter" means an X x Y grid where every stack carries independent readings, plus an independent footprint
  source.
- ARCore on the Redmi Note 9 Pro: certified, but with no Depth API (official device list), so AR is optional.
- No on-device detector: a 720G is too slow, YOLO is AGPL, and it would not be an independent reading.
- No point-cloud or feed-forward 3D.

Committed first: 5a71e85 (the 0.4.14 work).

**J: provenance** (Worker `readCapture`, `duplicateViews` / `boxOverlapScore`, `buildBlock` `trusted`):
- **Trust rule.** A reading verifies a stack only from a `captured_still` that was not blocked, with a `turned` side
  for side views, and not a copy of an earlier view.
- **Holes closed (measured).** Before this, one photo sent three times gave `exact`, from both the gallery and the
  camera.
- **Duplicate score on saved detections.** Re-encodes score 0.944-0.995; different captures of one block score
  0.19-0.47. The threshold is 0.8.
- **Capture field.** `<view>_capture` is read first, so the 8,000-character evidence limit can no longer drop the
  heading. R2 stores `capture_source` / `capture_blocked` metadata and `evidence.json` beside each photo.
  Fingerprint version 3 covers the capture.

**K1: frame doubts** (`spanColumns(detections, frame)`), on the 82 accepted columns:
- `end_at_frame_edge` (within one box height of the frame edge) fires only on img-30 and L-80.
- `cut_at_frame_side` fires only on img-08's edge stack (correct count, now unverifiable).
- `pitch_differs` (over 1.2x the face pitch) never fires.

**No distance refusal yet.** Pixel pitch does not separate good faces (22.5-25 px) from W05 (26 px, wrong). The
threshold waits for the distance ladder (plan G).

**App 0.4.15+26:**
- The gallery button is behind Settings > "Gallery scans (testing only)", off by default.
- Resume without a camera refuses, unless a result is already kept on the phone or the switch is on.
- The scan form adds `<view>_capture` (`ApiClient.captureField`).

**Replay** (`reports/replay-phase-j-20261101`):
- Adversarial: 22/24 pass. The 2 failures are S14 and R02 (another block's sides), which need Phase F.
- New cases S15-S19 and R04 pass, including S18, a genuine 2x1 camera walk-around that is still `exact` 40.
- Saved trios: 0 wrong releases.

**Tests (measured).**
- Worker: 167 tests, 161 pass, 0 fail, 6 todo (the planned E, F and H cases).
- Flutter: 179/179 on the full run. Analyze is clean after a one-line style fix; the affected suites were re-run
  (51/51).

**Sessions proposed (cards, not started):**
- E: a detector-independent pixel counter, offline.
- K2: the on-phone layer signal, offline.

**Not done.**
- No deploy or install: staging is still ef7c1dd3 (0.4.12), and the phone has 0.4.12.
- The user's blind counts (D2).
- Phases F, G, L, M, N, H and O.

**Next.**
1. F, the blind declaration: Worker `block_declaration` reader and `confirmed` status, plus an app pane before
   upload.
2. With approval: deploy 0.4.15 to staging (`--env staging` only), install APK 0.4.15 on the Redmi, and check the turn
   sign on a walk-around.

## 2026-11-01 - plan to exact counting; Phases A, B, C, D1 built and tested locally (Claude Code)

**The plan.** `C:/Users/rahul/.claude/plans/spicy-growing-flame.md`, approved by the user. It came from a 12-agent
research workflow: 3 repo readers, 4 web researchers, 3 independent designs, an adversarial critic and a
synthesizer.

**Its core decision.** "100%" means zero wrong `exact` or `confirmed` totals, with coverage reported beside it.
Hidden interior stacks cannot be measured from photos.

**Phase A: replay harness and registry (measured, development data).**
- `benchmarks/registry-20261101`: 72 faces and 22 three-view replays of 14 sets, each with truth tier and
  provenance.
  - Built by `scripts/registry_near_duplicates.py` and `scripts/build_replay_registry.mjs`.
  - **dHash check.** The 18 audit-leaked labelled photos match a detector pool at distance 0-7, and the 6
    leak-free ones at 10 or not at all. **None of the 42 MUTAA photos matches**, so they are out of sample for the
    detector.
  - The 8 MUTAA staging responses are now in `reports/mutaa-manual-vs-backend-20261031/raw/`.
- `cloudflare-worker/test/replay_benchmark.mjs` and `.test.mjs` run the Worker's own functions offline.
  - `scripts/replay_benchmark.mjs` writes the report.
  - `scripts/test_all.ps1` now runs the Worker tests.
- **Results:**
  - Per-face verdicts equal the Python 0.4.11 evaluation on all 52 labelled photos (0 mismatches).
  - Labelled clusters: 10/22 accepted, 9 correct, 1 wrong (img-30, 78 for 80).
  - Saved trios: 0 wrong releases.
  - The app's 1600 px re-encode changed the count in 7 of 10 views (img-30: 78 to 79).
  - Report: `reports/replay-baseline-20261101/README.md`.

**Phase B: miss taxonomy** (`reports/miss-taxonomy-20261101`, overlays from `scripts/overlay_columns.py`). Every
silent miss on a close face is at a stack end:
- img-30 stack 2: a box over the top trays of two stacks;
- img-30 and L-80 stack 4: the bottom tray was cut by the frame edge, got a half-height box and was merged as a
  duplicate;
- L-109 stack 4: the bottom tray had no box.

Far faces (W05, M16-FAR) lose layers inside the stack and are already refused.

**Phase C: Worker `worker-0.4.14` release contract.**
- A stack is `verified` only when two photos read it the same, with no gap-filled layer and no doubt.
- `exact` needs every visible stack verified.
- New fields:
  - per column: `doubts` (box_over_two_stacks, box_over_two_trays, end_box_cut_short, bottom_above_floor);
  - per cell: `verified` and `readings`;
  - per block: `visible_verified_trays`, `visible_single_reading_trays`, `single_reading_cells`;
  - per view: `stray_groups`, the 1-2 box groups, which make the block an estimate.
- **Doubts on the 82 accepted columns:** all 4 known silent misses are flagged, plus 11 others (7 known correct).
  The floor check is limited to interior stacks: on end stacks it fired on 4 correct faces.
- **Adversarial library:**
  - 0.4.13 failed 5 cases, including `exact` 79 for 80 (S03, S04) and `exact` 60 for 80 (two stacks merged).
  - 0.4.14 fails 2: side photos of another block with a real turn (S14, R02). These need Phase F.
- **Cost:** blocks wider than two stacks are `estimated` until Phase E adds a second reading for front-middle
  stacks.

**D1: side check and heading archive (Worker and app).**
- A side turned more than 135 degrees is refused as `faces_back`, by the Worker and before the shutter.
- The turn direction is recorded as `direction_ok` (LEFT is a right turn, negative yaw) but not enforced until a
  phone confirms the sign.
- Headings are archived in R2 custom metadata.
- Job fingerprint version 3 includes the headings; version 2 jobs still replay (tested).

**App 0.4.14+25.**
- The result card shows "Seen by two photos" and "Seen by one photo only".
- The manual count is blind: fields start empty, the app's counts and total are hidden, and every reachable stack
  must be entered.
- The heading check refuses back-face side photos.

**Tests (measured).**
- Worker `npm test`: 156 tests, 150 pass, 0 fail, 6 todo. The todos are the remaining planned gaps: S14 and R02
  (Phase F), and the stretch checks S03 and S04 (E), S07 (F) and S09 (H).
- Flutter: analyze clean, 177/177.

**Not done.**
- Python port of the new rules into `scripts/evaluate_labelled.py`. Skipped: the TypeScript harness now runs the
  Worker's own code, and parity of the unchanged parts is asserted.
- No deploy, no APK build, no install. Staging is still ef7c1dd3 (0.4.12); the phone has 0.4.12.
- Phases D2 (the user's blind counts, sheet in `reports/blind-count-20261101`), E, F, G, H and I.

**Next steps.**
1. The user fills `reports/blind-count-20261101/sheet.csv`.
2. Phase E: make `backend/app/vision/rim_count.py` independent (its own pitch and stack ends), score it against
   the blind counts, then verify the Lambda route and `VISION_SERVICE_TOKEN` read-only.
3. Phase F: the operator declaration (Worker `block_declaration` plus an app pane before upload).
4. With approval: deploy 0.4.14 to staging (`--env staging` only), build and install APK 0.4.14 on the Redmi,
   and check the turn sign on a walk-around.

## 2026-10-31 (later still) - same-face guard: Worker 0.4.13 side check + app heading tracker (Claude Code)

Built at the user's request after the MUTAA comparison (L-100: three front photos gave 500 "estimated" for a
100-tray block). Contract and details: docs/SCAN_JOBS_AND_DEVICES.md "Side-face check".

App 0.4.13+24:
- lib/services/heading_tracker.dart: gyroscope yaw about the accelerometer's up.
- One session per scan, owned by ScanFlowScreen and kept across retakes; a heading exists only while the
  gyroscope reports.
- The capture screen refuses a side photo taken without turning, before the shutter.
- yaw_deg and yaw_session go into each view's evidence.

Worker (PIPELINE_VERSION worker-0.4.13):
- sideCheck() reads the headings. A side in the same session must be turned at least 45 degrees, and LEFT
  and RIGHT must be at least 90 degrees apart.
- Without a heading, a side repeating the front's stacks is `repeats_front`, and any other side of a block
  more than one stack deep is `unconfirmed`.
- A refused side gives needs_view with no total, and strips the false depth, cells and tray numbers.

Review:
- A three-lens review workflow raised 9 findings, and skeptics confirmed 8.
- Fixed:
  - Retakes broke the session; the scan-wide session fixes this.
  - The false grid was still drawn; the side-derived structure is now stripped.
  - The count rule leaked on re-shots framed one stack tighter or with one stack misread (400/496
    "estimated" in a perturbation test); fixed by the depth rule.
  - A silent gyroscope froze the heading; fixed with the sample and freshness checks.
  - The tracker re-rated the accelerometer; it now requests the uiInterval rate.
  - Tests were missing for the combined cases.
- Recorded, not done: headings are not archived and not in the job fingerprint, so a replay from R2 has no
  heading. Gyroscope drift weakens the test over long pauses.

Tests (measured):
- Worker npm test 122/122 (11 new side-check tests plus a capture-gate combination test). The two
  capture-gate tests now send camera headings.
- Flutter analyze clean; flutter test 176/176 (8 heading tests, 1 pane test showing that a scan's session
  survives a capture screen and an inactive state).

Replay of saved real responses (sideCheck on stored detections):
- Withheld: L-100 500 (wrong); mechanics trio 399 (three different blocks, also wrong); 9b4c783e 165 (a
  genuine trio from app 0.4.9 with no headings, so it is withheld until a 0.4.13 camera scan).
- Kept: the 99-block (one deep), in all 5 saved scans.

APK built: egg-tray-counter-0.4.13-block-staging.apk (repo root, git-ignored), 62,558,741 bytes, SHA-256
c3b50b8d07407dde7fc772399866315ba4608eeb653e262fcf960986ca1b2e63. Checks:
- apksigner: the release key (29013b98...), the same signer as 0.4.12, so `adb install -r` upgrades the
  Redmi in place and keeps its device key and approval.
- aapt: 0.4.13 / 24.
- No admin token or keystore password in any entry.

Not done:
- Worker 0.4.13 is not deployed (staging is still ef7c1dd3, 0.4.12).
- APK 0.4.13 is not installed.
- On-device check of the heading guard on the Redmi: walk around a block, and confirm a front re-shot is
  refused.

## 2026-10-31 (later) - MUTAA field photos: manual 3D count vs backend (Claude Code)

At the user's request: cloned github.com/RAHUL-DevelopeRR/MUTAA (a27877b) to C:\Users\rahul\MUTAA, outside
this repo. Full write-up: reports/mutaa-manual-vs-backend-20261031/README.md.

Method:
- Two agents grouped the photos into block sets (propose, then refute) and kept 8. NONE is a genuine trio.
- The backend run went through staging ef7c1dd3 in the app's upload format (21 detector calls). The
  Worker refuses a repeated photo (422 duplicate_view), so the 4 two-photo sets used an unrelated filler as
  RIGHT, and only their real faces' counts are used.
- The manual count used 3 blind counters per set plus a reconciler. These are visual counts, not physical.

Results:
- Close square-on faces: backend per-stack equals manual on 9/10 stacks, with 1 off by 1 (CORNER 14, L-80,
  L-100). The manual totals equal the user's written totals: L-80 80 and L-100 100.
- Far face (M16-NEAR): the backend reads -8 to -10 per stack, but the capture check refused it.
- L-100: LEFT and RIGHT are front photos. The block model returned 500 "estimated" for a 100-tray block.
  Nothing checks that a side photo shows a side face.
- Every other set: needs_view (no total).
- Big blocks are mostly hidden interior (W05: 196 visible of about 1366; L-115: 232 of about 734).
  Counters disagree on depth.

Next:
1. Same-face guard (Worker and app): no total when a side view repeats the front. Downgrade to
   needs_view. In the camera path, require a heading change between captures.
2. A genuine close trio with physical counts.
3. A detector retrain on far faces, held out by block.
4. An interior policy for big blocks: operator-confirmed, or estimated with the visible share shown.

## 2026-10-31 - 0.4.12 on the Redmi, approved; NETWORK TEST on Jio LTE (Claude Code)

PR #2 (rollout/0.4.12-staging -> main) is open, mergeable, and has no CI checks configured.

Phone install:
- Redmi Note 9 Pro, serial f76d5e20, Android 12. It was unlocked and had 0.4.11 build 22 (installed
  14 Oct).
- The user chose "uninstall and install". No counts CSV export was found in Downloads. The 0.4.11
  history and any counts saved only on the phone are gone. Server-side counts (WH-99, MECH-DONE) are in
  the 26 Oct snapshot.
- `adb uninstall` then `adb install egg-tray-counter-0.4.12-block-staging.apk` (4da7db0a...): versionName
  0.4.12, versionCode 23, first install 2026-10-31 10:53.
- The fresh install pointed at production. The URL was set to staging in Settings.
- The phone registered as F39D-8C65 (pending, 0.4.12+23). After `scripts/devices.py approve
  f39d8c65-7e75-4222-aaee-29d9632db834` the home card read DEVICE APPROVED.

NETWORK TEST, measured on Jio LTE (jionet), colo SIN. Means over successful requests:

| test | OK | TCP | TLS | total |
|---|---:|---:|---:|---:|
| health ipv4 | 20/20 | 167 ms | 198 ms | 1574 ms |
| health ipv6 | 20/20 | 272 ms | 300 ms | 868 ms |
| trace ipv4 | 10/10 | 113 ms | 131 ms | 388 ms |
| trace ipv6 | 10/10 | 107 ms | 131 ms | 395 ms |
| upload auto (3 x 500 KB, IPv4) | 3/3 | 176 ms | 208 ms | 4624 ms |

- Today there was no loss on either family. On 12-14 Oct IPv6 lost 40-66%. That is one sample, so keep
  the IPv4-first connector and leave the custom-domain decision open.
- The log lines are in reports/rollout-20261031/network-test-logcat.txt, with the phone's public IPs
  redacted.

Devices active on staging: F39D-8C65 (the Redmi) and 1179-C06A (the laptop emulator).

Phone gallery scan, same day:
- The 99-block trio (STRAIGHT img-01, LEFT warehouse image-4, RIGHT img-32) was pushed to
  /sdcard/Pictures/EggTest and picked by timestamp. The user's own photos were not opened, and a picker
  screenshot showing them was deleted.
- Result: "BLOCK ESTIMATE / faces differ by one layer", 5 x 1, 20/20/20/20/19, total 99. Identical to the
  emulator.
- Scan 30d9a59c-1a8a-4946-85d7-f36b1d7b80f8. Admin result: job done, attempt 1, replayed true, worker-0.4.12,
  result_status estimated. Detector boxes: straight 101, left 22, right 24 (identical after the app's
  1600 px re-encode).
- Test manual count PHONE-TEST-20261031, note "phone test only, not ground truth": storage state,
  tamper_proof, count_id 3433c645..., app_total 99, recorded_by f39d8c65.... EXCLUDE PHONE-TEST-* and
  EMU-TEST-* from every score.
- The test photos were deleted from the phone afterwards.

Not done yet:
- A hand test of portrait and sideways capture.
- Switching staging to enforce (wrangler.jsonc AUTH_MODE "enforce", deploy --env staging, verify 401s).
- The field round with independent physical counts.

## 2026-10-29 - APK 0.4.12 end to end on the emulator against staging (Claude Code)

Branch rollout/0.4.12-staging. Commit 3989f95 holds the signing change and the 26 Oct entries; it is not
pushed.

Emulator setup: the existing AVD abi_test (Android 16, x86_64, google_apis_playstore) on this laptop, started
with -no-snapshot-save.

Steps:
- Installed egg-tray-counter-0.4.12-block-staging.apk (SHA-256 4da7db0a...): versionName 0.4.12,
  versionCode 23.
- On launch the app pointed at production (SERVER REACHABLE). The URL was changed to staging in Settings.
- The app then registered itself: "WAITING FOR APPROVAL - device 1179-C06A".
  `scripts/devices.py list` showed it as pending with app 0.4.12+23.
  `approve 1179c06a-9631-4c27-8d8d-432fcab1c718` made it active, and the home card then read DEVICE APPROVED.
  It is still active on staging; revoke it if it is no longer wanted.
- Gallery scan of the 99-block trio:
  - STRAIGHT img-01 (label 99).
  - LEFT warehouse image-4 and RIGHT img-32, both photos of the same 19-tray end stack. No genuine LEFT
    photo exists.
  - Connection: EGGCONN ipv4, tcp 21 ms, tls 36 ms.
  - Result screen: "BLOCK ESTIMATE / faces differ by one layer", 5 wide x 1 deep, 20/20/20/20/19, seen
    99, computed 0, one gap-filled layer, total 99.
  - The ambiguity is cell [0,0]: straight 20, left 19, chosen 20. This is the same outcome as the phone on
    12 Oct and the staging replay on 14 Oct.
- Admin GET /v1/scans/91fbaf6f-a4a2-471f-bb9f-73f62a14df8f/result returned 200 with job done, attempt 1,
  replayed true and pipeline worker-0.4.12 (stored result, no new inference). Raw detector boxes: straight
  101, left 22, right 24. The walk counter turns those into the per-stack layers.
- RECORD MANUAL COUNT: the form opened pre-filled with the app's layers (the anchoring risk).
  - Sent with block id EMU-TEST-20261029 and the note "emulator test only, not ground truth".
  - The app showed "Sent to server: filled 99, empty 0".
  - export_manual_counts lists it with storage state, tamper_proof true, count_id 310c503d...,
    app_total 99, app_version 0.4.12+23 and recorded_by the emulator device.
  - EXCLUDE EMU-TEST-* from every score.

What this shows:
- Registration, approval, upload, scan job, stored result and the manual-count path all work in 0.4.12
  against staging.
- It does NOT show counting accuracy: the trio is constructed, these photos are in the set the walk
  counter was tuned on, and the app itself calls the result an estimate.
- There are still 0 physical counts.
- Not tested here: NETWORK TEST on the phone's Jio link, camera capture, resume after the app is killed,
  enforce mode.

Next: the phone (CSV export, uninstall 0.4.11, install, staging URL, approve), then enforce, then the
field round with independent physical counts.

## 2026-10-26 - new machine: state re-measured, next plan (Claude Code, analysis only)

No code change, deploy, build, secret or commit. This is a fresh clone of main at 1800db9 (PR #1 merge,
2026-10-17; tree identical to codex/hybrid-cell-counting) on a new laptop (C:\Users\rahul).
Git-ignored assets did not come across: work/secrets (staging admin token), work/toolchains, work/vision-deps,
node_modules, .venv and the 0.4.x APKs.

Measured today:
- Cloudflare: staging is 47cb2378 (0.4.11, 2026-10-14) and production is 4c1480e6 (2026-09-23), both 100%
  (`wrangler deployments list`). Staging has no ADMIN_TOKEN secret (`wrangler secret list --env staging`).
- Wrangler on this machine is already logged in to the owning account (Rahultech72216, also used for
  kadan-kanakku-api), with workers write scope. Drop the `wrangler login` step below.
- Worker: a fresh clone fails `npm test`/`build`/`deploy` with TS2688 because tsconfig.json:9 needs the
  git-ignored worker-configuration.d.ts. After `npx wrangler types`: 111/111, dry runs OK.
  `npm run deploy` (package.json:7) has no --env and so targets PRODUCTION.
- Python (scratch venv from backend/requirements-dev.txt): backend 148 passed (4/4 runs, no OpenCV flake),
  ml 3, scripts 75. Ruff gate: 34 findings in research modules. System Python fails backend collection
  because a stray site-packages `tests` package shadows backend/tests, so use a venv.
- The committed eval-20261015, walk-fill and stack-faces results all reproduce byte-identically. The walk-fill
  results.json hash is 77f4b6d0..., not 3aa1b07c (the 3aa1b07c value in the entry below is from the
  first revision).
- App toolchain: Flutter 3.47.0 is at C:\Users\rahul\AppData\Local\Codex\flutter and an Android SDK (adb
  36, build-tools 35-37) is at %LOCALAPPDATA%\Android\Sdk. Neither is on PATH. cmdline-tools are missing
  and the licences have not been accepted. One reader ran Flutter on a scratch copy: analyze clean, tests
  166 passed + 1 skipped.
- Signing: this machine's ~/.android/debug.keystore is not the 27a05295 key that signed 0.2.2-0.4.11
  (build.gradle.kts signs release with the debug key). So an APK built here cannot upgrade the phone in
  place; uninstalling loses on-phone history, unsent counts and the staging URL. After a fresh install the
  app defaults to the PRODUCTION URL (settings_store.dart:11).
- Disk: C: had 0.7 to 8.5 GB free during the analysis. That is not enough for an APK build; aim for 10 GB or more.
- Roboflow projec-mutta is public (MCP projects_get). No October photo is in any training run.

Corrections to earlier wording (no data changed):
- ef823816 "393 vs 233 (-41%)" compares assumed interiors (assistant 240 vs app 144). Only 153 trays were
  seen, so it is not a measured detector undercount.
- 9b4c783e "164" is a visual reading with 60 assumed.
- The far-face undercount (n = 3 blocks) is a hypothesis.
- Both existing manual counts are unusable as truth: MECH-DONE's total equals the app's 399 (form
  pre-filled, manual_count.dart:25-32) and WH-99 was entered by the assistant.
- The live exposure is staging. Its open routes let anyone list and overwrite manual counts and spend
  inference. Production 4c1480e6 returns 404 on those routes. Promoting HEAD to production without
  STATE_PREFIX + ADMIN_TOKEN + AUTH_MODE would open them there.
- ADMIN_TOKEN must be set before the observe deploy. Without it adminTokenMatches (index.ts:1080) fails
  closed and a 0.4.12 phone can never be approved.

Next plan:
- A. Agent-only, now:
  - Make deploys explicit (deploy:staging, guarded deploy:production; pretest/prebuild `wrangler types`).
  - Fix the field scorers (reachable-cell totals, filled-only metric, rescan/missing buckets, block_id
    grouping).
  - Add a hold-out registry and leak check (include the G31 twins wh074/075/077).
  - Add an offline shadow scorer (V0/V4/C + gate) and a same-face check.
  - Commit the Python-TS parity test.
  - Write the field protocol and scoring spec, frozen before data.
- B. 0.4.12 staging rollout. It needs the user's approval and runs in this order:
  1. Confirm the existing wrangler session.
  2. Generate ADMIN_TOKEN and set it on staging.
  3. Deploy staging in observe mode and verify.
  4. Free disk space and choose the signing route (recover the 27a05295 keystore, or uninstall after a CSV
     export and use a new backed-up release key).
  5. Build, install and approve the phone.
  6. Run NETWORK TEST, one scan and one manual count.
  7. Switch to enforce through wrangler.jsonc.
  Decide 0.4.12 as-is vs 0.4.13 safeguards (staging default URL, host on the home card, count_id resend,
  form not pre-filled).
- C. Field round: at least 3 new blocks, STRAIGHT/LEFT/RIGHT at about 1.5/3/5 m, with independent
  per-stack filled/empty counts, ideally two counters. Then the first held-out number, with n.
- D. Then one detector retrain on far and cross-stacked faces, held out by block, in a private Roboflow
  project.
- Production promotion, custom domain, the Lambda and the heatmap/3D tracks stay parked.

Track B started (same day, at the user's request):
- Pre-flight: `npx wrangler types`, then Worker `npm test` 111/111. The staging dry run binds
  AUTH_MODE observe, STATE_PREFIX state/staging/ and MODEL_ID projec-mutta/2 (PIPELINE_VERSION worker-0.4.12).
- Flutter 3.47.0 (process-local PATH): `pub get --enforce-lockfile` OK, analyze clean, tests 167/167.
- Free disk is now 42 GB.
- Snapshot of the staging manual counts before any change: work/snapshots/staging-20261026/ (git-ignored).
  It holds the 2 records (WH-99, MECH-DONE), 25 stack rows and the raw JSON.
- Admin token generated into work/secrets/staging-admin-token (git-ignored; 43 chars, no newline, never
  printed).
- NOT set on staging yet: Claude Code's auto-mode permission check refused `wrangler secret put`. So the
  observe deploy is held too, because without the secret no device can be approved. Staging is still
  47cb2378.
- Signing: the only keystore on this machine is the new debug key (SHA-256 76:39:A3:30...). The 27a05295
  key is only on the DELL machine (probably <old checkout>\mobile\.android-home\debug.keystore or
  C:\Users\DELL\.android\debug.keystore).
- The SDK has a licences file but no cmdline-tools. No phone was attached (`adb devices` empty).
- Next:
  1. Set the secret: from cloudflare-worker, `wrangler secret put ADMIN_TOKEN --env staging` with the file
     as stdin.
  2. `npm run build && npx wrangler deploy --env staging` (never `npm run deploy`).
  3. Verify: /health shows auth device_v1, auth_mode observe and scan_jobs_v1; unauthenticated GET
     /v1/devices/me and /v1/manual-counts return 401; `scripts/devices.py list` with EGG_ADMIN_TOKEN
     returns 200.
  4. Then decide the signing route, attach the phone and build the APK.

Staging 0.4.12 in observe mode is DEPLOYED (same day, after the user explicitly approved it):
- `wrangler secret put ADMIN_TOKEN --env staging` from the file. Staging secrets are now ADMIN_TOKEN,
  ROBOFLOW_API_KEY and VISION_SERVICE_TOKEN.
- `npm run build && npx wrangler deploy --env staging`: staging version ef7c1dd3-2fd2-464b-8a99-0f27cb6deb6e
  (100%, 2026-10-26T15:57Z). Production is still 4c1480e6 (`wrangler deployments list`).
- Verified with no inference spent:
  - /health returns scan_contracts [cell_identity_v1, model_spatial_v1, reconstruct_v1, scan_jobs_v1],
    auth device_v1 and auth_mode observe.
  - With no credentials, GET /v1/devices/me and /v1/scans/<id>/result return 401
    device_credentials_required.
  - GET /v1/manual-counts and /v1/admin/devices return 401 admin_auth_failed with no token or a wrong one.
  - POST /v1/scans/count with no headers reaches the old open path (415 invalid_content_type), so 0.4.11
    keeps working.
  - With the admin token: /v1/admin/devices returns 200 {devices: []}; `scripts/devices.py list` says
    "no devices"; an unknown scan's result returns 404 scan_not_found and its manual-count returns 200
    (empty); export_manual_counts returns the same 2 records as the snapshot.
- Note: plain Python urllib with its default User-Agent gets Cloudflare 403 "error code: 1010" (bot
  signature) before reaching the Worker. The repo scripts are unaffected (they worked).
- Next:
  1. Choose the signing route (the 27a05295 keystore from the DELL machine, or a CSV export and uninstall).
  2. Decide 0.4.12 vs 0.4.13.
  3. Attach the Redmi, build, install, set the staging URL and approve the device by full id
     (`scripts/devices.py approve`).
  4. Run NETWORK TEST, then one scan with a manual count.
  5. Set AUTH_MODE enforce in wrangler.jsonc, deploy staging and verify.

New release key, and APK 0.4.12 built (same day). The user chose a new key: they export the phone's
counts as CSV and uninstall 0.4.11 themselves.
- Keystore: C:\Users\rahul\.egg-tray-signing\ (outside the repo and outside OneDrive). It holds:
  - egg-tray-release.jks: PKCS12, alias egg-tray-release, RSA 4096, valid to 2054-03-13. Certificate
    SHA-256 29013b980c183cabe7d93a0befb59cc06c0a4edd0b3baee06fb04657b4cba76f.
  - storepass.txt (random, never printed).
  - key.properties, plus README.txt with restore steps.
  mobile/android/key.properties (git-ignored) is a copy of key.properties.
- Backup: the only copy is on this laptop, which has a single drive. The user must copy the whole folder
  offline (USB or password manager). Every later APK must be signed with this key.
- mobile/android/app/build.gradle.kts (uncommitted): release builds sign with key.properties. A release
  task without that file fails ("refusing to sign a release with the debug key"); debug and IDE sync still
  use the debug key.
- Build environment (process-local only):
  - PATH gets the Codex Flutter bin and SDK platform-tools; ANDROID_HOME/ANDROID_SDK_ROOT point at
    %LOCALAPPDATA%\Android\Sdk; JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true.
  - The Gradle wrapper's own download timed out twice (Java connect timeout). Gradle 9.3.1-all was fetched
    with `curl -4` into ~/.gradle/wrapper/dists/gradle-9.3.1-all/9ot9r568e8zfvvd4mn8rbu1j0/ and matched
    the published SHA-256 17f27786...6e43.
  - AGP installed Android SDK Platform 35 by itself. `flutter build apk --release` took 824 s.
- APK: egg-tray-counter-0.4.12-block-staging.apk (repo root, git-ignored), 62,542,361 bytes, SHA-256
  4da7db0a1c10f1e64769d84579f318053b66ce40a01c347e98e6e4509c8e596c.
  - apksigner: verifies (v2), 1 signer, CN=Egg Tray Counter Release, digest 29013b98... (the new key).
  - aapt: package com.dharani.eggtray.egg_tray_counter, versionName 0.4.12, versionCode 23, minSdk 24,
    targetSdk 36.
  - Neither the admin token nor the keystore password appears in any APK entry.
  - The default server URL is still production (settings_store.dart:11), so set the staging URL after
    install.
- Not done: install. No phone is attached.
- Next:
  1. The user runs COPY ALL COUNTS AS CSV in 0.4.11, then uninstalls it.
  2. Attach the phone with USB debugging and accept this laptop's RSA key.
  3. `adb install egg-tray-counter-0.4.12-block-staging.apk`.
  4. Settings: staging URL.
  5. `scripts/devices.py approve <full id>`.
  6. Run NETWORK TEST with `adb logcat | findstr EGGNET`.
  7. One scan with RECORD MANUAL COUNT.
  8. Enforce.

## 2026-10-15 (later) - walk-overfill experiment: label-free walk variants (Claude Code subagent)

Offline only (no deploy, no inference, no commit; backend/ untouched, deployed counting unchanged in 0.4.12).
New: scripts/experiment_walk_fill.py (--out), scripts/tests/test_experiment_walk_fill.py (12 pass),
reports/experiment-walk-fill-20261015/ (README, results.json; 2 runs byte-identical, SHA-256 3aa1b07c...).

Measured:
- The deployed walk overfills by a pitch ratchet: filled sub-gaps feed its local pitch down to the 0.6
  floor, so ordinary gaps are doubled (img-04 `f`: 17 boxes, span 19, walk 27).
- Variants were chosen by a pre-declared label-free rule. The stage-1 output was saved before any label
  code existed and does not change when every label value is perturbed.
- Chosen: V4 (local pitch from one-layer gaps only).
  - Equal-extent pairs differing by more than 1: 15 → 11 of 29 (25 physical pairs); sum of differences
    97 → 47; filled layers 92 → 58.
  - Unchanged: 0 of 53 reference columns and 0 of 19 accepted totals. Of 66 photos it newly accepts only
    img-45, at 25 from a merged front/rear column; arm C reads that column as 20.
- Excluded: V1 (cap) and V2 (span fallback), which would disable the span/walk flag and change no outcome.
  Also V3 (strict fill), which broke the reference columns (4 of 53 changed) and, in the labels, made 3
  more accepted results wrong.
- Labels, secondary, scored after the choice:
  - V4 keeps 10 accepted / 9 correct / 1 wrong on the 22 clusters, with absolute error 431 → 451, all of
    it on withheld photos;
  - per-stack absolute error 26 → 22 (9 observations, 8 stacks); references 51/53.

With the overfill removed, far faces undercount: the user-100 stacks read 16/16/18/15/14 against 20. So
detector recall and capture distance stay first for the withheld far faces, on corrected evidence (15 of 18
small-scale pairs → 11).

Next:
- Run V4 in shadow next to V0 on physically counted field scans. Do not let it change acceptance until a
  merged-column guard exists (C's depth split or a filled-share check).
- Not for 0.4.12.

## 2026-10-15/17 - 0.4.12 code complete: scan jobs, device keys, evaluation on existing data (Claude Code)

STATUS 2026-10-17: committed and pushed to codex/hybrid-cell-counting at the user's request. NOT yet
deployed, built or installed: the wrangler OAuth login expired (14 Oct 16:52 UTC) and the Redmi has not
been attached since 14 Oct evening. Staging is still 47cb2378 (0.4.11), the phone still runs 0.4.11.
Measured on the final tree: Worker npm test 111/111, staging and production dry runs OK (production
config unchanged); flutter analyze clean, flutter test 167/167; scripts/tests 75/75; backend suite
passed (one run; OpenCV tests remain intermittently flaky as recorded before).
Remaining steps (need the user): `npx wrangler login` in cloudflare-worker; set ADMIN_TOKEN on staging
from work/secrets/staging-admin-token (`npx wrangler secret put ADMIN_TOKEN --env staging`, value piped,
never printed); `npm run build && npx wrangler deploy --env staging` (wrangler.jsonc staging is
AUTH_MODE observe); build the APK (0.4.12+23) and install on the Redmi; approve it with
`python scripts/devices.py approve <full device id>` (EGG_ADMIN_TOKEN set); run Settings > Diagnostics >
NETWORK TEST and collect `adb logcat | findstr EGGNET`; one complete gallery scan + manual count; then
`npx wrangler deploy --env staging --var AUTH_MODE:enforce`, set the file to enforce, verify 401/403
for unauthenticated requests. Portrait/landscape capture needs a hand on the phone.
mobile/test/support/loopback_tls.dart holds a throwaway self-signed localhost key for loopback TLS
tests only (trusted by nothing else).

Verified start state: HEAD 318eb04 local only (origin at a3e1f89); staging 47cb2378; production
4c1480e6 unchanged (health without block contracts); Redmi had 0.4.11 build 22 (not attached since
14 Oct evening). Contract: docs/SCAN_JOBS_AND_DEVICES.md. Audit outputs (scratch, not in repo):
routes/sessions, Cloudflare options (R2 create-only put `If-None-Match: *` measured atomic in
Miniflare; zone zero-x.live available for a custom domain), network (adb shell has no HTTPS client;
Dart connectionFactory must return a TLS socket; laptop over Jio hotspot 14 Oct: staging /health
IPv4 20/20, IPv6 19/20), dataset (MUTAA repo = the 41 MUTAA originals + the 52 count-labelled
photos already in the repo by SHA-256; 24 labels usable at image level, 8 per-stack user reports,
0 counted genuine three-view sets; only labelled ids 30, 31, 46, 47, 49, 50 have no copy in any
training export). Roboflow (read-only): production projec-mutta/2 rfdetr-medium trained 21 Aug on
99 images (recall 67.3%); v3/v4 trained in Sep, not promoted; no training on any October data.
Rollout order required: set ADMIN_TOKEN on staging, deploy with registration available but not
enforced, install 0.4.12, approve the phone by full device id, then enforce.

Done so far (uncommitted, tests measured):
- Worker: AUTH_MODE open|enforce, devices (self-generated id + secret, admin approve/revoke via
  scripts/devices.py, revocation final, 4 KiB registration cap, sanitised labels, shared-display-code
  guard), scan jobs on R2 create-only/CAS (stored result, replay, 409 scan_id_conflict, 202 while
  running, takeover after lease, result route 200/202/404/409), manual counts idempotent by
  count_id with latest ordered by min(created_at, recorded_at), admin-only listings with cursor,
  diagnostics upload route. Follow-ups done: AUTH_MODE observe (rollout step; 0.4.11 still works
  without headers), lease 150 s (Cloudflare keeps a disconnected request ~30 s; worst-case count
  ~242 s computed, so a slow live job can be redone - results stay consistent), fingerprint v2 incl.
  scan_contract and cell ids, staging manual counts only under STATE_PREFIX (production shares the
  bucket and stays open), per-scan manual-count route, admin archive lists the job's image hashes,
  STATE_PREFIX required. Final: npm test 111/111.
- App 0.4.12+23: device identity in flutter_secure_storage, registration/approval gate, shared Dio
  with IPv4-first TLS connector, NETWORK TEST screen (EGGNET logcat lines), new scan id per
  retake, pending scans on disk with RESUME/DISCARD, five failure classes, result polling, history
  v2 (older rows shown unknown, never rewritten), manual count count_id/created_at/app_total.
  Android backup and device transfer disabled. flutter analyze clean; flutter test 167/167.
- Scripts: 0-byte cache crash fixed in replay and score scripts, admin header from
  EGG_ADMIN_TOKEN, cursor pagination, stable replay ids, newest photo per view; scripts/tests pass.
  accuracy-evaluation/ERRATA-20261015.md (img02 = img06; 99-block labels) without editing the CSV.
- Evaluation (reports/eval-20261015, saved detections, 0.4.11 logic, development set): 22 label
  clusters -> 10 accepted, 9 exact, 1 wrong (img-30, 78 vs 80, leak-free), 12 withheld; trios are
  workflow tests only (substituted 99-block and mechanics trios still give an estimated total).
- Experiment (reports/experiment-stack-faces-20261015): 20 photos / 99 reviewed polygons; manual
  polygons remove 2 of 18 error trays; automatic separation C finds 58/71 target stacks vs 48/71.
  Verifier: "retrain first" not established - the walk counter's gap filling over-counts on
  regular boxes (12 of 62 polygons hold 74 of 92 filled layers).
- Corrections applied after two verification rounds: the walk reference set is label-conditioned as
  a whole, so 9 of the 10 accepted clusters are in-sample and only img-47 is out of sample; img-32 and
  img-46 are logic-development photos ("not used in logic tuning" n=5: 1 accepted, 1 correct);
  hold-out listed by block (G03, G29, G30, G31, G32); label-perturbation tests cover all three
  evaluation scripts (predictions byte-identical when every label changes).
- Walk-overfill experiment (reports/experiment-walk-fill-20261015, entry above): label-free V4
  fixes the pitch ratchet, moves 0 of 19 accepted results; shadow mode only.
- Bottleneck (verified statement): the binding constraint is held-out physical truth (0 physical
  counts, 0 counted genuine trios). On single faces the remaining error after V4 is far-face
  undercounting where a layer is under ~3% of the frame height (3 blocks) - detector recall at small
  scale or capturing closer, not separable with these data; cross-view matching cannot be ranked.
  Next milestone: physical per-stack counts on >= 3 new blocks as STRAIGHT/LEFT/RIGHT sets at about
  1.5/3/5 m, then detector retraining on far and cross-stacked field faces held out by block; V4 and
  stack separation C in shadow mode meanwhile; add a same-face (duplicate side photo) check.

## 2026-10-14 (later) - step 1 counting fixes: merged faces, ambiguity, bounded gap fill, one result status (Claude Code)

Plan bugs B01/B02/B03/B06/B08 from C:\Users\DELL\deepseekfs\future-plan.md, plus the half-count
found in the 13 Oct corner block, fixed in Python (backend/app/vision/block_model.py,
layer_span.py) and the Worker port (cloudflare-worker/src/index.ts), and in the app (0.4.11+22).
Not deployed, not built, not committed.

- B01: every face reading of a cell is merged (no overwrite); a one-wide block whose LEFT and
  RIGHT give the rear stack 18 vs 22 is now a conflict (was 42, consistent, fully observed).
- B02: faces one layer apart keep a total but status "estimated", with an `ambiguities` entry;
  the reading with fewer gap-filled layers wins, STRAIGHT on a tie. Two layers apart = conflict.
- B03: the walk fills at most 2 missed layers per gap (MAX_FILLED_PER_GAP; no reference stack
  needs more than 1); longer runs are `walk_unresolved_gaps` and send the face for a retake.
  [0, 40, 80, 4000] now counts 4 (was 101).
- B06: `walk_filled` is carried to the cell (`filled_layers`) and block (`filled_trays`).
- Half-count: column box height / walk pitch below 0.75 sends the face for a retake ("step
  closer"). References 0.79-1.16; 13 Oct corner block front 0.64-0.67; in the 39 tagged photos
  it flags only 3 sparse or undercounted non-reference columns among the frontal photos.
- B08: block `status` = exact / estimated / conflict / needs_view; top-level `result_status`;
  legacy top-level fields unchanged for installed APKs. The app's icon, headline, block panel
  and history all use it (history used to store block scans as rescan_required with no count);
  egg total labelled "if every tray is full" (`eggs_basis`).

Measured: 53 reference stacks still walk 51/53 exact; Python and Worker give identical block
results on 27 real scenes (18 archived batches, 4 field scans of 13 Oct, 5 staging replays).
Changes on real scenes: the 99-block (fake LEFT photo, corner 20 vs 19) and the 399 mechanics
trio keep their totals but become "estimated"; 9b4c783e stays 165, estimated (corner 15 vs 16 =
cover tray); ef823816 asks for a step-closer retake; archived batch 12 (three unrelated photos)
no longer invents 718. Tests: backend block/layer 53 (11 new), full backend suite passes but 2 of
7 full runs hit intermittent OpenCV "Unknown C++ exception" in untouched cv2 tests (reruns pass);
Worker 57 (6 new) and staging dry-run build OK; Flutter analyzer clean, 99 tests (3 new).

Deployed with the user's approval: staging Worker version 47cb2378-6e3e-483e-b709-b99da9960470
(production 4c1480e6 untouched). Live replay on staging: 99-block 99 estimated, 9b4c783e 165
estimated, ef823816 / 30aca6a1 / f81c04d7 withheld (ef823816 first reason "step closer"); laptop
uploads still hit TLS resets (3 in a row once). APK egg-tray-counter-0.4.11-block-staging.apk,
SHA-256 02ece3b6d52883c92481eee8cc61ab46149091f460f26fc8698a76cb95e768f5, 61,508,183 bytes,
installed on the Redmi 12:00 (versionName 0.4.11, versionCode 22); launched: SERVER REACHABLE,
staging URL kept. Old history rows still read "Rescan required" (stored by the old app). adb
screencap hung on this phone; screen text read with uiautomator instead.

Next: field scans with RECORD MANUAL COUNT on every block (10+, incl. a corner and a
cross-stacked block); then 0.4.12: prefer IPv4, device key on manual-count/list routes, fix
replay_field_scans.py empty-file crash; then detector retrain (far cross-stacked rows, cover-tray
class) and capture options (wall side, same-face check, raised top photo).

Mistake made and repaired this session: editing six files through PowerShell 5.1
Get-Content/Set-Content added a BOM and garbled non-ASCII characters (x sign). Repaired by
reversing the cp1252 misread; every non-ASCII line now matches HEAD. Use the editor tool, not
PowerShell text round-trips, on UTF-8 files here.

Not done in step 1 (need data or capture work): empty cover trays still count as filled (needs a
detector class), same-face-twice detection and a "side against a wall" capture option,
short stacks (< 3 boxes) and different-depth stacks merged in one column (B04/B05).

## 2026-10-14 - 13 Oct field scans replayed; phone, network and backend survey; plan review (Claude Code)

Analysis only: no code change, deployment, APK build or phone setting change.
Details: reports/field-scans-20261013/README.md.

- Phone: 0.4.9+20 still installed (0.4.10 not installed). It rebooted 13 Oct 18:53 and the app
  has not run since, so no app log covers the 13 Oct scans. Jio today: IPv6 to the staging Worker
  host 50% loss, IPv4 0% loss. Laptop uploads were still reset during the TLS handshake 2 of 6 times.
- Backend: staging f5776f0d (block model), production 4c1480e6 of 2026-09-23 (no block model;
  the 2026-10-12 entry's "0482e52c" is not what wrangler lists), Lambda health 200 diagnostic-only,
  AWS token expired. R2: 102 scans; manual counts are still only WH-99 and MECH-DONE.
- 13 Oct scans: 7 arrived; 3 repeat the 99-block photos; 4 new ones without manual counts.
  Replayed on staging: f81c04d7 (mixed label photos) withheld; 30aca6a1 withheld (all faces too far
  away or too narrow); ef823816 (5x4 block in a room corner) withheld, 8 stacks flagged, 144/233
  would be computed; 9b4c783e 4x3 total 165 (105 observed + 60 computed), all faces accepted,
  unverified. The gate refused 6/12 faces, each for a reason visible in the photo.
- Found: replay_field_scans.py crashes on rerun when a scan has no manual count (empty file left).

Hand count by eye (visual, not physical; reports/field-scans-20261013/, app-vs-hand-3d.png):
ef823816 = 393 filled (153 seen + 240 hidden) + 19 empty covers versus the app's 233 (-41%).
Cross-stacked trays (5/6-egg rows alternate) photographed from far are boxed only on alternate
rows, so pitch doubles and layers halve. Its LEFT and RIGHT photos are the same side face (left
side against a wall). 9b4c783e = 164 versus the app's 165 (the empty cover tray was counted);
observed stacks 6/7 exact, 7/7 within 1. Reviewed C:\Users\DELL\deepseekfs\future-plan.md:
B01/B02/B03 reproduced on the current code; the plan lacks cross-stacking, cover trays, duplicate
faces and wall-bound blocks.

Next: (1) manual count on every field scan, 20 blocks minimum; (2) network: prefer IPv4 in the
app and/or the custom domain; (3) install 0.4.10; (4) warehouse capture modes for wall/corner
blocks and an elevated top photo for interior stacks; (5) promote the block model to production
only after the field score. The Sept plans in docs/ (WAREHOUSE_3D_ACCEPTANCE_PLAN.md,
COUNTING_EXECUTION_PLAN.md) predate the block model and need refreshing.

## 2026-10-12 - "backend offline" diagnosed as the mobile network path; retries, smaller uploads, tilt smoothing (0.4.9) (Claude Code)

Operator report on the Redmi: the home screen sometimes says the backend is
offline and scans sometimes fail. Phone log (logcat): no app error, no crash;
MIUI killed the app once from the recents screen ("SwipeUpClean", low-memory
device). Measured (reports/network-20261012/): the staging and production
Workers answer in milliseconds whenever a connection completes, but TLS
handshakes to the two *.workers.dev hostnames are dropped on about a third
of IPv4 attempts from the laptop's Wi-Fi and on every IPv6 attempt; another
workers.dev host and other Cloudflare sites are clean over IPv4, Google is
clean; from the phone's Jio IPv6 path the Worker host loses 40-66% of
packets while Google loses none. So the fault is the network path to the
workers.dev addresses, not the server code. One dropped handshake on the
pre-upload health check failed a scan before any photo was sent, and a 1.5 MB
upload on a 40%-loss link exceeded the 45 s send timeout.

App 0.4.9+20: health check and pre-upload check try three times, the upload
four times with 0.8/2/5 s pauses (connection resets, handshake failures and
timeouts retried; HTTP answers not); send timeout 150 s, receive 90 s; the
status card reads "SERVER NOT REACHED - TAP TO RETRY" and retries on tap;
scan errors are worded for the operator (ApiClient.describe). Uploads are
capped at 1600 px on the long side at JPEG quality 92 (camera and gallery
paths share kUploadLongSide / kUploadJpegQuality): 138-290 KB per photo
instead of 437-669 KB, measured identical per-stack counts at 1280 and 1600
px on photos 01, 02 (both sides) and 19 against staging. Real fix proposed,
not done: a Workers custom domain on the owner's own Cloudflare zone.

Tilt: the operator saw tilt warnings in normal holds. PreflightPolicy
.maxRollDeg was 4 degrees (advisory from 2.4), below hand tremor; a roll of
8 degrees changes the layer spacing the counter reads by under 1% and keeps
a stack in one column, so the limit is now 8 (advisory from 4.8). The
accelerometer is smoothed in LiveFramePreflight (exponential, factor 0.15 per
sample at the UI rate, about a third of a second to settle) with an immediate
snap on moves above about 15 degrees so turning the phone sideways is seen
at once; new test "hand tremor is smoothed away but a real turn is taken at
once". Pitch limits unchanged (looking down costs a layer, measured earlier).

Also today: 0.4.8 installed on the phone and verified; backend survey
(production Worker 0482e52c of 2026-08-22 without the block model, staging
f5776f0d with it, Lambda diagnostic-only, R2 archive shared); the only new
photos on the phone were personal documents (pulled copies deleted, not
used); the 99-block gallery scan was set up (three photos selected) but the
upload was not completed because the operator was using the phone.
Flutter 96 tests, analyzer clean.

0.4.9+20 installed on the Redmi (SHA-256 d48061bc0a1fa76c...) and driven
end to end through the gallery path: the three 99-block photos picked in the
app, uploaded, counted on staging and drawn as a block in 25 s: 5 wide x 1
deep, 20/20/20/20/19, total 99 (phone-e2e/13). Result-screen fix in
0.4.10+21 (built, SHA-256 50914fda4f963bfd..., not yet installed): the warning triangle was shown over every block result because
the legacy top-level "accepted" flag is always false on the block path; the
verified icon now shows whenever the block has a total, the warning only when
the total is withheld.

Next: hand-test sideways capture and the tilt chip, decide on the custom
domain, field scans with hand counts.

## 2026-10-10 - camera follows the hand without turning the screen; sideways photos count exactly (Claude Code)

User feedback on 0.4.5: in landscape the camera picture itself was drawn
sideways ("the camera pans"), and "whether the photo is captured straight or
sideways, the count should be exact". Four independent readers (camera
plugin, app upload path, Worker/Roboflow, live checks) plus staging
measurements established: (1) the pane locked the capture orientation to
portrait; the camera package's CameraPreview rotates by that lock while the
camerax plugin's own rotated preview subtracts the device orientation, so in
landscape they disagreed by one quarter turn, and the same lock tagged every
still as portrait, so a sideways capture reached the server rotated and the
detector collapsed (0-11 boxes); (2) Roboflow honours the EXIF orientation
tag (sideways pixels + tag 6/8 give the same per-column counts as the upright
file) but untagged sideways pixels collapse detection and the old gate still
accepted 2 of 6 such frames; (3) the width-coverage rule rejected correct
landscape frames of 1-3-stack faces that fill most of the height.

Fixes. 0.4.6: lock removed; the still check maps the guide by the still's
orientation. 0.4.7 (installed on the Redmi 2026-10-09 15:55, SHA-256
8f0d2e4bc95f19b7...): the screen never rotates, like a normal camera app.
nextCaptureRotation (mobile/lib/services/captured_still.dart) turns the
accelerometer roll into 0 / 90 / 270 with hysteresis (past 60 deg sideways,
under 30 deg upright, a flat phone keeps the last value); step chips,
instruction, torch, verdict strip, CAPTURE and the rejection dialog are
turned with _WorldOriented (RotatedBox plus rotated MediaQuery padding); the
guide is drawn turned inside the portrait frame. LiveFramePreflight
.setCaptureRotation rotates live frames by (sensorOrientation -
captureRotation), measures roll relative to the hand, lends only the pitch
offset of a stored level reference sideways, and discards the last frame on a
change so a frame measured the other way up cannot unlock capture. After
takePicture, prepareCapturedStill (compute isolate) decodes the still, turns
it by stillRotationCw(captureRotation) into the world-upright picture, strips
the orientation tag, measures blur/exposure, and the session uploads that
file (raw still deleted; evidence JSON gains capture_orientation,
upright_pixels, width, height). 0.4.8 (built, SHA-256 2416b9d9e21f7715...,
NOT installed: the phone was unplugged): the 20:9 screen trim of the upload is
removed and the viewfinder shows the whole frame (BoxFit.contain), so what is
seen is what is counted. Worker (staging f5776f0d, production untouched):
GATE.full_height_waiver = 0.8 (coverage reason waived when the tallest column
spans >= 80% of the frame height; zero verdict changes on the 39 tagged
photos, all 7 landscape variants accepted) and GATE.min_box_aspect = 2.75
(median detection width/height below it -> "the trays look sideways or
unclear in this photo; hold the phone level and retake", placed first so
worstView names that view; metrics.box_aspect added). Lowest usable aspect on
the tuning set 3.09 (img-9), highest sideways 2.64; the rule refuses all 6
sideways frames and none of the 39 tagged photos or landscape variants.

Measured (staging; reports/orientation-20261009/): synthetic Redmi stills
(1920x1080, EXIF 6, sensor pixels per hand position) built from labelled
photos 01 (99), 02 (80), 19 (100), run through the real prepareCapturedStill
and the staging Worker. Without the screen trim: 01 r90, 02 r90, 02 r270,
19 r90 all exact per stack. With the trim: 19 exact both sides, 01 r90 one
stack 19 (ref 20), 02 r90 one stack 19, 02 r270 two stacks 19; the trim alone
reproduces the 02 misses, hence 0.4.8. Old-app sideways files are now refused
(0 / 11 boxes, sideways reason). Upright padded scenes: all exact.

Tests: Flutter 94 (new captured_still_test 7, live_frame_rotation_test 5;
lifecycle: preview never locked, portrait viewfinder, sideways overlays turn
while the screen is never asked to rotate), Worker 51 (full-height waiver,
sideways refusal; one-stack fixture made tray-shaped), analyzer clean. Not
verified: sideways capture by hand on the phone; the synthetic stills assume
CameraX writes EXIF 6 for every still with the display locked portrait
(inferred from the CameraX file path, not measured on the Redmi; the untagged
sensor-pixel case is handled as well). No new field scans: staging holds
only the WH-99 and MECH-DONE manual counts. The formatter touched eleven
unrelated files during this work; those edits were reverted, not committed.

Next: install 0.4.8 when the phone is back (adb install -r
egg-tray-counter-0.4.8-block-staging.apk, then check versionName 0.4.8);
hand-test sideways both ways (picture must not turn, text upright, TILT green
when level); photograph one block upright and sideways and compare the two
counts; run scripts/export_manual_counts.py and scripts/replay_field_scans.py
on real scans; promote the gate rules to production only after real landscape
phone photos confirm them.

## 2026-10-09 (midday) - walk counter, perspective rule, rescan reasons (Claude Code)

Measured fault in the second phone scan: layer spacing shrank 28 -> 16 px
from top to base (camera above mid-height) and the detector double-boxed /
skipped layers; the span rule (one global pitch) rounded to 21 on a 20-layer
stack. Replaced the layer count with walk_layers (backend
app/vision/layer_span.py, Worker walkLayers): local pitch tracked over the
last three accepted gaps, clamped to 0.6-1.4 of the global pitch; a box closer
than 0.65 x local pitch is a duplicate (includes stray half-pitch boxes);
multi-pitch gaps fill missed layers; perspective_gradient = top-third /
bottom-third spacing. On the 53 reference stacks: span exact 40/53, walk exact
51/53, both 53/53 within 1; the two misses have the base layer cut off in the
photo. TS/Python parity on all 180 archived columns (one third-decimal
gradient rounding tie). Block model now uses walk_count; a stack is rescan
when |span - walk| > 1 or gradient > 1.5, with an operator reason ("camera
looked down ...; hold the phone level at mid-height" / "layer counts
disagree ... retake this face"), including side-face corners (bug fixed:
their reason was dropped). Backend 27 tests, Worker 45 tests, lint clean on
touched files. Staging versions 26b23130 -> ec90aef6. Live probe on the real
99 block with raw files: 20/20/20/20/19, 5x1 fully observed, total 99, no
conflicts (previously 21/20/20/20/19 and a corner conflict); the from-above
side photo now reads 19 (was 23 with walk v1). Production untouched; the
phone build 0.4.1 needs no change (reasons arrive through block.conflicts).

Afternoon: rim-edge verification wired in the Worker behind RIM_VERIFY
(rimVerify posts each photo + its columns to the Python service's
/candidate/rim-count in parallel; a confident rim count that differs from the
walk count marks that stack rescan with the reason "rim edges count N layers
but boxes count M"; service errors give verification status "unavailable"
and never block a scan; Python block_model has the same rule; Worker 48
tests, backend 28). Staging a414ea83 with the flag off until the Lambda has
the route. On-device capture rule tightened: camera pitch-down limit 28 -> 12
degrees (comfortable 8) with the message "hold the phone level at the middle
height of the stack"; 32 capture tests pass; APK 0.4.2+13 building, to be
installed when the phone returns. AWS CLI session expired: the Lambda image
rebuild for the rim route needs the user's browser login again.

APK 0.4.2+13 (SHA-256 8a1a42647a3c0fe6...) installed on the Redmi at 11:58 and
launched against staging. User asked for an elevated view showing the block
interior: feasible as an optional fourth photo that observes stack tops
(footprint present/missing and relative top heights), not interior layer
counts; needs a small elevated-view training set and a top-detector; planned
after the face counting is validated. Publishing this checkpoint to
codex/hybrid-cell-counting at the user's request; the rim-count files still in
progress are left for the next commit.

Capture UI rework (user feedback: constraints filled the screen, old
overlapping-views wording, legacy entries on home): capture order is now
STRAIGHT -> LEFT -> RIGHT with block-face instructions (square-on, fill the
frame, phone level at mid-height); the guide is one rectangle for every face;
the painted-cell dialog, the three confirmation checkboxes and the level-
reference bar are gone (the stored level reference still feeds the advisory
only); the live verdict is a thin strip inside the viewfinder (headline,
action, check chips; "SQUARE-ON" replaces "ANGLE", no LEVEL REF chip), so the
camera keeps the screen between the view chips and the capture button. Home
shows SCAN A BLOCK - CAMERA / GALLERY and recent scans; the 3D point cloud
and grid+height pilot moved under Settings > Diagnostics. Analyzer clean, 79
Flutter tests pass (order and label tests updated). APK 0.4.3+14 building.

Camera-first capture (0.4.4+15, user feedback that the camera still had too
little room and no portrait/landscape choice): the viewfinder now fills the
screen between a one-row header (step chips, rotate button) plus a one-line
instruction with the torch toggle, and the capture button; a rotate button
switches the capture screen between portrait and landscape (controls move to
a side column; remembered for the app session; portrait restored on exit).
Main back camera preferred by lens type with a fallback, stills at 1080p
(veryHigh) instead of maximum resolution, zoom errors non-fatal (a fake
camera without zoom revealed that setZoomLevel could abort camera setup).
Gallery photos are capped at 2000 px on the long side before upload. Worker
ca684530: when the block model names a face in its first conflict, the rescan
recommends that face. Added GET /v1/manual-counts and
scripts/export_manual_counts.py; master CSVs in reports/field-test-20261009/
(WH-99 and MECH-DONE so far; the first MECH-TEST record predates latest.json).
Analyzer clean, 79 Flutter tests, 49 Worker tests.

Orientation follows the hand (0.4.5+16, user: "the camera orientation
doesn't change, only whether the image is captured straight or as landscape"
and the 0.4.4 landscape screen was unusable): the rotate button is gone. The
capture screen drops its app bar; the camera frame is scaled to cover the
whole screen with close / torch / view chips / instruction over the top and
the verdict strip + CAPTURE button over the bottom (landscape: button on the
right, strip bottom-left). The screen turns to landscape when the phone is
rolled past 60 degrees and back to portrait under 30 degrees, from the
accelerometer (works with the system rotation lock on); LiveFramePreflight
gets setDisplayRotation so roll is measured against the rotated screen and
live frames are rotated by sensorOrientation minus display rotation. New
widget test covers portrait and landscape viewports (80 Flutter tests, analyzer
clean). Verified on the phone in portrait only (phone-e2e/12); landscape needs
a hand on the phone - if it comes up upside down the roll sign in
_followOrientation is the fix. APK egg-tray-counter-0.4.5-block-staging.apk
(SHA-256 34a0349a3e4b11d4...) installed, versionName 0.4.5.

Rim-edge counter result (same-set tuning on the 13 straight-on WhatsApp
photos, not validation; reports/rim-count-20261009/): rim count exact 38/53
reference stacks, within 1 47/53; where the span count is wrong it disagrees
on 11/13 (and gives the reference value on 7), but it also disagrees on 9/40
stacks where the span is right. Decision: RIM_VERIFY stays off; the rim count
is a rescan hint, not a gate, until held-out field originals show a lower
false-alarm rate. No Lambda rebuild today; the leftover empty builder
security group and instance profile were removed. APK 0.4.4+15 (SHA-256
e94b65fb12d783a5...) installed and checked on the phone in both
orientations (phone-e2e/10, 11).

Added scripts/replay_field_scans.py: lists a scan's R2 keys, downloads photos
and manual count, re-submits to staging, scores replayed block vs manual
(blocks exact / rescan rate / observed stacks exact and within 1). Rim-edge
second count (independent verification) in progress in backend
app/vision/rim_count.py with an offline evaluation; not wired yet.

## 2026-10-09 - manual count in the app, phone picker fix, end-to-end on the Redmi (Claude Code)

User required the on-site count to live inside the app, tied to the scan's
block, and an end-to-end test on the connected phone. Added: Worker route
POST /v1/scans/:id/manual-count (validates block_id and per-stack
filled/empty/unreachable, stores scans/<id>/manual-count/<timestamp>.json and
latest.json in R2, never used for counting; 2 tests), APK ManualCountScreen
(one row per block cell pre-filled with the app's layers, block ID, notes,
SAVE ON PHONE / SAVE AND SEND / COPY CSV; SQLite store; 4 tests), and a
RECORD MANUAL COUNT button on the result screen.

Phone: the system Files picker lists nothing for any app on this Redmi Note 9
Pro (Android 12). Diagnosed from logcat/dumpsys; with user approval reverted
the Files app update (pm uninstall of the /data update) and turned on the
paused Android Device Policy work profile - neither fixed it. Switched the
upload slots to image_picker with useAndroidPhotoPicker; the Photo Picker
lists media correctly. APK rebuilt (0.4.0+11, SHA-256 0c48ffeada0692a3...),
installed, server URL set to staging through the Settings screen.

Measured on the phone (reports/staging-block-20261008/phone-e2e/): mechanics
trio -> 5x4 block drawn, total withheld (two stacks rescan: raw vs span
disagreement on app re-encoded JPEGs; same files raw from the laptop gave 400);
real 99 block with a borrowed left photo -> 5x1 drawn, 101 observed, total
withheld by the corner rule (21 vs 19). Manual counts sent from the phone for
both; WH-99 fetched back from R2 with the app layers and the human
20/20/20/20/19 side by side. Staging versions 4ffa06e0 then fa3a0a49;
production untouched. Suites: Worker 41, Flutter 78 (+manual count), backend 21.

Later the same morning: the user found the manual-count page a dead end.
Added DONE - NEXT BLOCK after a successful send (pops to the scan flow and
starts a new scan), extra bottom padding, keyboard dismiss on save, "SEND
AGAIN (CORRECTION)" label; 2 more Flutter tests. APK 0.4.1+12 built, SHA-256
b6487aea0052bfa7..., installed; third phone run (MECH-DONE) confirmed
scan -> manual count -> send -> DONE -> fresh upload pane. Staging Worker
d70d6495 adds GET /v1/scans/:id/archive (R2 key names for one scan; 42 Worker
tests). scripts/score_field_blocks.py fetches each scan's latest.json with
wrangler and reports per-stack exact/within-1 (observed vs computed), block
agreement, rescan rate and interior-assumption exactness; smoke-tested on the
WH-99 record (5 stacks, 60% exact, 100% within 1, total withheld). Phone is
left on the upload pane with the staging URL, ready for the field test.

Open: app-side JPEG re-encoding (quality 95) shifts detections enough to
trigger the +/-1 rule; decide after field data whether to send originals. No
same-block STRAIGHT/LEFT/RIGHT set exists on the laptop, so no accuracy claim
from today's phone run. Next: field test per docs/FIELD_TEST_BLOCK_20261009.md
using the in-app manual count; Day 3 scoring from R2 latest.json per scan.

Staging deployed and probed (2026-10-08 evening): egg-tray-counter-api-staging version a012c14e-8ad0-4a50-b2ab-9a697a0df857; user set ROBOFLOW_API_KEY on staging; /ready ready; real three-photo scan HTTP 200 in 11.5 s returned block_model_v1 5x4, 220 observed + 180 computed = 400, all views pass the capture gate. Production unchanged. Evidence: reports/staging-block-20261008/. APK 0.4.0 users must set the staging URL in Settings.

## 2026-10-08 - Day 1 of the 3-day block scope: model, Worker, APK, capture gate (Claude Code)

User set the target: STRAIGHT (X face) x LEFT/RIGHT (Y faces) x height ->
block grid -> 3D render -> total; interior stacks are the calculation, not a
doubt; both side faces are photographed; the top view is dropped; photogrammetry
stays diagnostic. Implemented in three layers with the same rules:

- backend/app/vision/block_model.py (build_block/render_boxes, 15 tests) and
  layer_span.py (6 tests): corner counted once and must agree in height and
  recessed state; LEFT/RIGHT depths must agree; recessed column = missing front
  cell, stack behind promoted; no room behind -> conflict; two faces promoting
  different heights -> conflict; interior cells status "computed"; totals keep
  observed_trays and computed_trays separate; total_trays only without
  conflicts/rescans; fully_observed only for single-row blocks. Reference pitch
  is the median of the front group. Rounding half-to-even in both languages.
- cloudflare-worker/src/index.ts: spanColumns/faceColumns/buildBlock port and
  block_model_v1 in the model_spatial_v1 response (legacy top-level total_trays
  stays null for the installed APK); captureQuality gate per view with
  block.capture and an operator rescan reason; ViewInference now keeps the
  Roboflow image size. Tests: 39 pass (block 11, capture 8, existing 20).
- mobile 0.4.0+11: BlockResult model, BlockPanel with isometric painter
  (observed green / computed grey / missing red / rescan amber, far-to-near
  order, front row visible), result screen shows BLOCK COUNT with the panel
  and hides the contradictory legacy evidence rows when a block total exists.
  flutter analyze clean; 74 tests pass. Release APK built:
  egg-tray-counter-0.4.0-block-staging.apk, versionCode 11, 58.3 MB, debug
  signer 27a05295..., SHA-256 f554976ebead827f267e22edbbba39ead38ebdfd351a821bc7f0fe03fa9c78ce.

Verification beyond unit tests (measured): adversarial review found and I
fixed four block-model bugs (largest-pitch reference, lost stack behind a
recessed column at depth 1, corner recess ignored, double promotion) and two
port/painter defects; TS-vs-Python parity on all 52 archived photos: 180
columns, 1440 values bit-identical, 0 mismatches (work/parity-20261008/,
git-ignored); painter orientation/order re-verified by computation. Capture
gate tuned on the 39 tagged photos (tags assigned after seeing V2 errors, so
hindsight-biased; near-duplicates shrink the effective sample): frontal 17/18
accepted (img 4 rejected, the two-depth scene), non-frontal 18/21 rejected
(25, 26, 41 pass: steep single column and uniform-pitch two-depth scenes are
invisible to these signals). Gradient margin is thin (frontal max 1.139 vs
rejection at 1.201). Single-column faces use coverage >= 0.25 so a one-row
block's side face is not refused.

Not done: no deployment (staging Worker still serves the previous code), no
commit, no emulator install (BlueStacks not running), no field data yet. The
block total is X x Y x height computed from faces, not a field-validated
inventory; interior stacks are not observed. Day 2 protocol:
docs/FIELD_TEST_BLOCK_20261009.md with datasets/field-2026-10/counts.csv.

Next: user approves deploy to the STAGING Worker (wrangler, no production
change) and sets the staging URL in the APK; install 0.4.0 on the phone;
scan 10 blocks with on-site per-stack counts; Day 3 scoring (accepted-stack
exactness, block agreement, rescan rate, interior-assumption error).

## 2026-10-08 - block model backend (Claude Code)

User restated the target: photograph the X face and the Y face of a block,
count stacks and layers on each, multiply out the grid, render it in 3D, and
handle missing stacks and unequal heights by depth. Implemented the grid stage
that was missing between layer_span and the existing assemble_grid accounting:
backend/app/vision/block_model.py (build_block, render_boxes). Rules: X face
observes the front row, Y face observes one side column, the corner stack is
counted once and must agree within 1 layer or the cell is a conflict; a face
column whose layer pitch is < 0.85 of the front pitch is recessed -> front
cell missing, the stack behind becomes observed; a column whose raw box count
and span count differ by > 1 is a rescan cell; interior cells are ASSUMED at
the median observed height unless an optional top-view occupancy grid marks
them present or missing. Output keeps observed_trays and assumed_trays
separate, total_if_assumed only without conflicts/rescans, verified_total only
when every cell is observed. render_boxes emits one box per stack by status.

Verification: tests/test_block_model.py 8 passed (5x4 uniform -> 8 observed
cells/160 observed/240 assumed/400 if assumed, single-row verified 100,
corner conflict, recessed column, rescan, top view, render, input rejection);
with test_layer_span 14 passed; ruff clean. Pipeline smoke on real archived
detections (img19 as X face, img30 as Y face; different blocks, mechanics
only): 5x4, observed 159, assumed 240, total_if_assumed 399, verified false.
No Worker, APK, deployment or model change.

Next (3-day scope): port span count + block model into the Worker response
(pure arithmetic on RF boxes) or call Lambda with detections; APK: capture
rule (one face, straight-on, fill frame, mid-height), per-stack screen, block
render from render_boxes with observed/assumed/missing colours; field test of
10 blocks with on-site per-stack counts; report accepted-stack exactness,
scene agreement, rejection rate and interior-assumption error rate.

## 2026-10-08 - per-stack manual verification and span counter (Claude Code)

Cut the 13 straight-on labelled photos into stack columns using archived V2
box x-centres and inspected enlarged columns with model marks, rim grids and
per-layer cell strips (renders in reports/field-labelled-20261007/per-stack/).
Whiteness/egg-colour row heuristics failed on the WhatsApp copies; rim grids
were confused by background tray tops and wrong pitch priors. Adopted a span
count: round((last box centre - first box centre) / median spacing) + 1, which
removes duplicate boxes but cannot recover unboxed top/bottom layers.

Measured on 53 resolved stacks across 10 scenes: raw V2 box count exact 31/53,
within 1 49/53; span count exact 40/53, within 1 53/53. Span scene totals
100/100/100/81/61/79/121/158/158 vs labels 100/100/100/80/60/80/120/160/160.
Per-stack 20s for those scenes are inferred from user totals plus the machine
evidence; they are not independent physical per-stack counts, and 19 vs 20
could not always be separated by eye at 1-2 MP. Unresolved: img04 and img09
(blocks at two or three depths merged by x-clustering; img09 has an empty top
tray and nested empties), img50 (close-up from above; lower rows perspective-
compressed; model and span both 35 vs label 40). Reference 20/20/20/20/19 for
img01 retained.

Code: backend/app/vision/layer_span.py (count_layers_by_span, diagnostic,
verified=False) and backend/tests/test_layer_span.py; 6 tests pass with
work/heatmap-env Python plus work/vision-deps packages. No API route, Worker,
APK, deployment or model change. Evidence: per_stack_counts.csv,
span_summary.py, per-stack/ renders, README section.

Next: segment stacks by depth (face polygons, not x-clusters) before counting;
rectify close-up faces before the span count; wire span count into the
candidate route as diagnostic per-stack evidence; add APK frontal/fill-frame
rule; user confirms label readings and supplies originals; reserve held-out
scenes.

## 2026-10-07 - labelled field photos and first measured V2 baseline (Claude Code)

User supplied 52 photos with handwritten verified stack-face totals in
Downloads/FileOfEggLabels. Copied byte-for-byte with SHA-256 manifest to
datasets/field-2026-10/labelled-20261007/ (intake.py). All are WhatsApp copies
(0.2-1.9 MP, no EXIF) with ink drawn into pixels. Transcribed labels into
labels.csv with confidence and scope notes; user confirmation of
medium-confidence readings (21, 28, 40, 41, 43, 45, 46, 52) and scope (3, 26,
40, 41, 43, 52) is pending. Six near-duplicate pairs and several same-block
multi-angle groups recorded; images are not independent samples.

Ran unchanged production Worker/Roboflow projec-mutta/2 on all 52 (labels not
sent); one Windows TLS error retried successfully; repeat counts for images 1/2
identical. Measured: all 5/52 exact, MAE 45.1, V2 sum 2839 vs label sum 5041.
Block faces 1/39 exact, 6/39 within 2, MAE 59.1. By assistant capture tag
(assigned after seeing errors, so hindsight-biased): frontal fill-frame 12/18
within 5% (median 4.2%); angled/corner/multi-block 0/16 (median 70.2%);
distant/wide 0/5 (median 94.5%). Same-block checks independent of tags: block
80 gives 81 frontal, 52 oblique, 18/20 steep side; block 109 gives 117 frontal,
60 corner. Wide scenes collapse (358 -> 1; 205/204 -> 0). No per-stack truth,
filled/empty split or inventory total established. No code, deployment, model
or APK change. Report: reports/field-labelled-20261007/README.md.

Next: user confirms transcription and supplies un-annotated originals if
available; add APK frontal/fill-frame capture gate; test tiled or per-face
cropped V2 inference on the angled/distant failures (needs Roboflow calls);
label per-stack counts constrained by the user's totals for the three-check
per-stack counter; keep a held-out subset untouched.

## 2026-10-07 - Claude Code handover

This checkout is intentionally uncommitted and unpushed. The active work is the
reconstruction diagnostic, not a verified counting release. APK 0.3.4+10 reaches
the staging Worker and AWS Lambda, but the current view is sparse SIFT/RANSAC
triangulation: its dots are matched image features, not tray objects. It has no
dense depth, mesh, texture, tray-instance association, or exact inventory total.
Keep physical_trays: null, verified: false, and arbitrary scale until those
stages are implemented and measured against physical ground truth.

Handover file: docs/CLAUDE_CODE_HANDOFF.md. It records the current artifacts,
known limitations, commands, deployed endpoints/digests, tools/MCPs, skills,
and the smallest safe next steps. Do not redeploy production or commit/push
unless the user explicitly requests it.

## 2026-10-07 - Staging reconstruction integration and APK checkpoint

Implemented render-ready sparse geometry (colored points capped at 2,000,
camera poses, bounds, EXIF focal estimate when available, explicit failure
statuses), staging-only Worker archive/relay, and APK 0.3.4+10 photo/camera
entry and orbitable diagnostic viewer. Production URL default and counting
route remain unchanged. User approved staging deployment and secret attachment.

AWS image pilot-20261007-integration is Active/Successful, digest
sha256:8511bd3af2afb02a8d7c8107bc83f2032c14299eefbd504cf6105e0d30218dba.
Temporary builder i-010cbb8cea282372d was terminated and its access resources
removed during deployment cleanup. Staging Worker version after secret attachment:
bae12d3c-5069-4c88-97e2-8b2e5e89f452. No production Worker deployment.

Checks: backend 82 tests, Worker 20 tests, TypeScript compile and staging dry-run,
Flutter 66 tests passed. Final flutter analyze: no issues (170.2 seconds).
APK built, signature verified (existing Android debug certificate), version checked,
and installed in BlueStacks. SHA256:
B42252BF5910EDC9A5E017A8EE08B4A23652CA62104564AA3724E87156ED150B.

Four API photo-pair tests returned HTTP 200 and exactly matched direct AWS
geometry: wide 175 matches/125 inliers/76,94,100 points; negative 2 matches and
insufficient_matches; wide-side 9/9/8,9,9 points; side-close 180/129/76,120,87.
Staging health advertises reconstruct_v1; production health does not. Anonymous
AWS reconstruction remains protected. BlueStacks now renders; selecting the wide
pair through the APK displayed 76 points/125 inliers/0.376 px at focal factor 0.7.
One emulator screenshot saved. User supplied a further screenshot showing 100
points/125 inliers/0.447 px. Remaining manual pair tests/two-rotation evidence and
full UI review are pending after interaction interruptions; no complete UI pass claimed.

User clarification: expected a recognizable 3D model of trays. Current algorithm
is sparse two-view SIFT/RANSAC/triangulation, not dense meshing or tray-instance
reconstruction. Low reprojection error is not count accuracy. No calibrated scale,
physical count, model retraining or deduplicated inventory is established.
Report: reports/reconstruct-integration-20261007/README.md.
Next: finish outstanding UI checks; audit tray/stack correspondences with overlays;
evaluate calibrated overlapping views for dense reconstruction separately from
instance counting, against physically counted held-out scenes. No commit or push.

## 2026-10-07 - AWS reconstruction route deployed and photo-tested

The user approved official CLI installation/login and completed browser sign-in.
Installed AWS CLI 2.37.10 per-user; STS confirmed account 608942062000. Reused the
existing Lambda, SSM secret and ECR repository. Moved the existing local geometry
algorithm into app.vision.reconstruction; the CLI now calls that same module.
Added protected POST /candidate/reconstruct with bounded uploads/pixels,
distinct/equal-dimension photo validation, temporary-file cleanup and one active
reconstruction per process. Public health advertises two_view_sfm_diagnostic_v1.

Deployed pilot-20261007, digest
sha256:4ef6034d8adb553478d86f73a131d6c8dff3ba943cf1d49a063b11315cda70fb.
Direct AWS queries confirmed Active/Successful and the resolved image digest.
Temporary t3.small builder i-06d048e4cbd40a49d is confirmed terminated; role,
instance profile and security group were removed. No provisioned concurrency.

Verification: 15 local host/spatial tests passed; real-photo local API geometry
matched CLI exactly. Public health 200, unauthenticated routes 401, authenticated
band diagnostic and reconstruction 200. Original overlapping wide image-1/2
hashes match. AWS: 175 matches, 125 fundamental inliers, 76/94/100 sparse points
under focal factors 0.7/1.0/1.4, 10.703 seconds. A second hosted reconstruction
was exactly equal, 10.568 seconds. Windows: 121 inliers, 67/86/100 points; platform
fits differ and point totals are not tray totals. Band route still reports 16
stack candidates / zero accepted correspondences and null inventory. Both routes
remain diagnostic_only / verified=false. Reports and PLY evidence:
reports/aws-reconstruction-deploy-20261007/.

Current APK 0.3.3+9 and Worker still use their existing production model path;
no AWS/mobile integration, fresh model inference, retraining or verified warehouse
count is claimed. Reviewed visible references 99/19 are retained separately.
Exact next steps: camera calibration; unchanged scene with physical per-stack
filled/empty truth; stack-face localization and cross-view identity/layer matching;
held-out exact-count validation; only then Worker/mobile integration. Earlier
entries below preserve the pre-deployment checkpoints.

## 2026-10-07 - live AWS check and overlapping-wide-photo reconstruction

The existing AWS Lambda diagnostic's public health returned HTTP 200 and its
unauthenticated candidate route returned 401. Health still explicitly says
diagnostic_only/inventory_verification_ready=false. AWS Core first required
reauthentication; after the user reconnected it returned Unknown tool, including
for its list_regions method. No account mutation, new deployment or protected
photo replay succeeded this session. AWS CLI is absent; an installation/login
permission question is pending. Production APK/Worker still use Roboflow V2,
with no AWS diagnostic gateway integration. Windows Worker health/ready probes
failed during TLS with WinError 10054, which does not prove a server outage.

New local geometry experiment reused scripts/reconstruct_pair.py on the two
overlapping wide originals, warehouse-20260923 image-1/image-2: 175 strict mutual
SIFT matches, 121 fundamental inliers, 46 homography inliers. Assumed focal-width
factors 0.7/1.0/1.4 produced sparse PLY hypotheses of 67/86/100 points. Factor 1.0
median reprojection error is 0.448 px. 101 inliers lie inside coarse manually
inspected tray bounds in both images; this is not instance/identity validation.
Unknown intrinsics, arbitrary scale and unconfirmed unchanged stock prevent a
verified inventory claim. Feature points are not trays. This camera-geometry
experiment is local, distinct from the deployed stack/band diagnostic route.

Reviewed wide/narrow photo evidence against the retained numbered visible-layer
references: 99 (20/20/20/20/19) and 19. Archived V2 counts 76/19 have absolute
errors 23/0 against those references. No fresh inference, no sum across views,
no independent physical filled/empty truth, and no 99% field accuracy claim.
Host/spatial contract checks passed all 14 tests with one anyio deprecation.

Launched BlueStacks Pie64 and the installed APK 0.3.3+9 through its visible UI.
Copied four existing photos to its Download/egg-tray-test folder. Android's
accessibility tree shows SERVER REACHABLE and upload controls, but Windows and
Android screenshots are white. App logs contain EGL_BAD_MATCH. OpenGL-only
rendering was selected in BlueStacks settings, restart completed, and config gl
and Android boot completion confirmed. The restarted launcher appeared normally;
further app interaction was interrupted by minimization/user input. A post-change
app upload/result flow is not verified; no scan was submitted from this APK.

Evidence: reports/aws-user-test-20261007/ (health, source hashes, matches, PLY
hypotheses, Android accessibility and startup rendering evidence).
Next: restore AWS tooling or approve official CLI/login; verify protected AWS
photo replay and separately authenticated gateway integration; finish emulator
user upload/result flow; establish calibrated stack identities/layers from
overlapping corner views and evaluate untouched physical recounts.

## 2026-10-06 — AWS vision diagnostic deployed and verified

AWS authentication succeeded for account 608942062000. Deployed the existing
diagnostic FastAPI service to Lambda `egg-tray-vision-pilot` in ap-south-1:
https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/.
Health is public; candidate requests require a server-side bearer credential
stored as SSM SecureString `/egg-tray-vision-pilot/service-token`. Lambda is
Active, 2048 MB, timeout 120 seconds, no provisioned concurrency. ECR image
`pilot-20261006` digest is
`sha256:f4843cebc73d1dbe15f717799cdb9361ef2deb0b5c57e82a0a92cfa3e7b9a472`.

CodeBuild's account build quota was zero, so a temporary no-ingress t3.small
builder built/pushed the image. Confirmed instance i-085685badf81960c1 terminated;
removed its role, profile and security group, plus the unused CodeBuild project
and role. Retained metered resources: on-demand Lambda, ECR image, seven-day
logs, private seven-day S3 staging objects, encrypted standard SSM parameter.
No actual bill estimate or free-service guarantee is established.

Live cold-start verification exposed a Uvicorn connection-limit bug: readiness
plus the initial request exceeded limit 2, producing HTTP 503. Corrected the
Lambda ImageConfig command and future Dockerfile to use one worker without that
connection limit. Replayed saved warehouse photos and archived V2 boxes:
health HTTP 200, unauthenticated candidate HTTP 401, authenticated candidate
HTTP 200; 16 proposed regions, zero accepted matches, null tray/egg-filled
totals, verified=false, recapture_required. These summary results match the
local diagnostic. Candidate client timing 14391 ms is one observation.
This is hosted transport/execution verification, not a 3D or field-count success.
Targeted host/spatial contract tests: 14 passed; one dependency deprecation warning.

Artifacts: backend/Dockerfile.vision-lambda, buildspec.vision-lambda.yml,
build-vision-on-ec2.sh, scripts/probe_vision_host.py and
reports/aws-vision-check-20261006/. Mobile APK/Worker/V2 were not changed.
Next: expose a separately verified gateway diagnostic route if needed; improve
stack localization and layer-center/edge evidence on current reviewed scenes;
add calibrated camera/stack identity evidence; obtain untouched physical
filled/empty scene recounts for independent acceptance before promotion.

## 2026-10-05 — AWS diagnostic deployment attempt and real-photo recheck

User authorized hosting the Python vision backend on AWS and asked for a real
3D verification. AWS Core reconnected long enough to confirm account
608942062000 and inspect ap-south-1. Created private S3 staging bucket
`egg-tray-vision-pilot-608942062000-ap-south-1` (public access blocked,
AES256, seven-day object expiry) and ECR repository `egg-tray-vision-pilot`.
AWS Core then returned `UNAUTHORIZED` again before source upload or image build.
There is no CodeBuild project, Lambda function, service endpoint, or live AWS
image verification yet. The machine has no AWS CLI/profile or Docker. Prepared
`backend/Dockerfile.vision-lambda` and `backend/buildspec.vision-lambda.yml`
and validated the local source ZIP. Production remains Cloudflare Worker +
Roboflow V2; APK and Worker were not changed.

Re-ran the saved two-view photo geometry script: 2 strict mutual matches,
no accepted pose/point cloud, null physical tray total. Re-ran the authenticated
local diagnostic API on three saved warehouse photos with archived V2 boxes:
HTTP 200, diagnostic-only health, recapture required, 16 candidate regions,
zero accepted correspondences, null inventory, verified false. The slot labels
are transport assignments, not calibrated views; scene stability and physical
filled/empty counts are unconfirmed. Targeted host/spatial tests: 14 passed.
Evidence and deployment gate: `reports/aws-vision-check-20261005/`.

Next: after AWS Core reconnects, upload the source ZIP, build the bounded-cost
diagnostic Lambda image and verify its live authenticated route with the same
saved inputs. Inspect and clean up pilot AWS resources if deployment cannot
finish. Do not present
that hosted diagnostic as exact inventory. For exact-count development, capture
untouched physically recounted scenes, complete camera/stack identity evidence,
and evaluate per-stack layer and occupancy errors before app promotion.

## 2026-10-05 — hosted-path and Android emulator audit

Checked the live Cloudflare Worker and the current local release APK without
changing production deployment. The Worker `/ready` reports Roboflow serverless
model `projec-mutta/2`; `/health` reports `hybrid_ready: false`. The Flutter
default URL points to that Worker. No hosted Python 3D/vision endpoint is
configured or integrated into this APK; `backend/app/vision_service.py` remains
diagnostic-only and reports `inventory_verification_ready: false`.

Installed the existing 0.3.3+9 release APK on BlueStacks Pie64 through ADB,
replacing emulator version 0.3.1. Verified app launch, `SERVER REACHABLE`, and
the three-photo upload screen. This is a transport/UI smoke test only: no new
APK was built, no model inference or physically recounted scene was tested on
the emulator, and camera geometry/lighting cannot be validated there.

Next: freeze a physically recounted untouched scene set with per-stack filled
and empty counts; benchmark V2 and the offline stack-localization/layer evidence
pipeline on held-out scenes with exact-match, MAE, and rejection rates. Connect
and host a vision service only after that pipeline beats the current baseline
and preserves unresolved outcomes for hidden occupancy and uncertain matches.

## 2026-10-01 — monthly review print-readability revision

Rebuilt both August and September reviews with 12 pt body text, 16 pt main
headings and at least 10.5 pt PDF table text for A4 print. September now
includes the user-supplied mobile scan screenshot for a user-reported six-stack,
15-per-stack (90-tray) scene: per-photo V2 detections left 89, right 92,
straight 92; the app explicitly shows `COUNT NOT VERIFIED`. The reference is
user-reported and original scan photos/physical recount were not supplied for
independent verification. These per-view comparisons are not an accepted fused
inventory total or a field-accuracy estimate.

Verification: regenerated both editable DOCX files and PDFs from the saved
builders; August PDF is three A4 pages and September PDF is five A4 pages.
Rendered PDF pages were visually inspected; table text, paired photos, captions,
full mobile screenshot, and end sections are readable without orphaned pages.
Source contents and arithmetic were checked. Direct DOCX visual render remains
unavailable on this machine because LibreOffice is absent; PDFs are the
print-verified artifacts. Next remains independent physical per-stack recount
and scene-held-out acceptance before any exact-inventory claim.

## 2026-10-01 — August and September monthly progress reviews

Created separate formal August and September 2026 reviews, each as editable DOCX
and print-ready PDF under `reports/monthly-review-2026/`. They follow the supplied
academic report structure and include retained original/debugging photos, manual
visual references, production per-photo model results, count-agreement arithmetic,
challenges, next-month plans and status tables. The August review records the
frozen 31 August 10-image baseline (2/10 exact, MAE 22.9, 58.43% mean count
agreement). The September review records the fresh 99-layer wide/19-layer side
visual references, V2 counts 76/19, and manually assisted rectified count 100
with only 1/5 exact stacks. It explicitly rejects a 99% field-accuracy claim.
No physical egg-filled inventory ground truth, production retraining, or 3D
reconstruction was inferred from these photographs.

Verification: source figures and counts reconciled against saved evaluation
reports and fresh backend response; both PDFs contain three A4 pages and were
rendered and visually inspected page by page. The editable DOCX files were
generated from the same source, but direct DOCX rendering could not be checked
because LibreOffice is unavailable on this host. PDF was produced and checked
separately. Current artifacts are the four August/September DOCX/PDF files;
production remains V2 and the APK is unchanged. Next steps: obtain a physically
recounted untouched scene with per-stack filled/empty labels; run a controlled
scene-held-out V5 comparison, report exact/MAE/rejection metrics, then consider
backend and APK promotion only after acceptance.

## 2026-09-28 — reviewed-data follow-up and checkpoint-selection diagnosis

Continued from verified local/remote f6164c20ba876f0e9326eb2a4b75e25849a2298f,
clean initial tree. Created a separate frozen follow-up release; original
benchmarks and seven-face release preserved. Four full-source crop reviews add
5/5/7/10 visible layer centers: eleven faces152 targets, two retained conservative
leakage groups. Corrected broad inventory scope:36 unrelated resume screenshots
excluded; current release915 paths495 contents127 near links (includes4new crops).
No extra scene identity or occupancy truth invented; these are visual layer
references, not physically certified egg-filled inventory. V2 export paths checked
for queued full-frame labels are missing; V5 control remains incomplete/untrained.

Ran four actual CPU group-held-out arms on identical data/settings:
frozen/BCE1/11 exact MAE13.000; last-block/BCE0/11 MAE13.818;
frozen/count3/11 MAE5.091; last-block/count2/11 MAE4.818. All0/2 groups exact.
BCE-selected checkpoints suppress peaks; added optional count-based checkpoint
ranking to compare exact/MAE/position errors without changing threshold. Last-block
mode thaws only existing final feature block, keeps BN running stats frozen and
old inference checkpoint loading compatible. Frozen/count still114 missed+70
spurious positions at6px tolerance; no candidate is production-ready. All band/
sequence variants remain unresolved/null inventory. Records and exact runner
source hashes saved; weights stay in ignored work/heatmap-followup-* directories.

Verification:77 backend tests pass; dataset hash/152peak checks pass; training
checks cover gradients/BN, checkpoint compatibility, criterion ranking and input
rejection (crop tampering, source-group leakage, nonfinite points, unreviewed and
acceptance records). New real checkpoint passed authenticated warmed backend
hash/homography/band/null-inventory probe. Independent agent regenerated4crops
byte-for-byte and confirmed old7annotations/group inheritance unchanged. No APK,
production model, Cloudflare update or AWS resource created. Local CPU torch2.6
and torchvision0.21 remain the runtime; no new cloud auth was required.

Artifacts: reports/stack-heatmap-followup-20260928/{README.md,comparison.json,
dataset/,frozen-bce/,lastblock-bce/,frozen-count/,lastblock-count/,code-versions/}.
Exact next steps: recover queued source/label bytes by SHA and review whole frames;
add varied reviewed faces and adjudicated independent whole-scene groups; audit
center/top/base semantics and test physical-pitch-preserving normalization; train/
evaluate stack localizer separately and collect real occupancy labels; complete
eligible V5 control. Then approved AWS execution and untouched physical acceptance
with cross-view identity. See report for reproduction and limitations.


## 2026-09-28 — controlled heatmap development and failed grouped validation

Verified local HEAD and remote codex/hybrid-cell-counting both started at
5967ce82cd76ef9d2c11c1050f347b14a71f3200; initial working tree clean. Implemented
content-addressed inventory/lineage/splits, frozen incomplete V5 control,
Gaussian target builder/QA, pretrained small PyTorch heatmap, train/eval runners,
deterministic sequence solver, polygon localization audit, authenticated warmed
research route, AWS custom-container/Spot configuration and production design.

Final inventory947 egg-image paths527 unique contents138 candidate near links,
two conservative leakage groups;2 unrelated design images excluded. Reviewed
seven faces125 visible-layer centers: original six118 plus a manually inspected
7-layer small stack from the existing individual-tray photos. Same-source five
focused faces always remain together. No physical filled-inventory truth invented.
Source/hash/lineage/frozen-snapshot/125-target checks pass. V5 control stays six
TRAIN crops118 boxes, VALID/TEST empty and training_release_eligible=false;
no V5 model trained. 72 legacy review candidates still need full-resolution QA;
three older reviewed source hashes wh009/025/069 are unavailable locally.

CPU six-face20epoch smoke fit gives6/6 raw counts exact, but19 missed labeled
positions and19 spurious peaks at fixed6px tolerance. Actual two-group LOCO
development validation:0/7 exact,0/2 groups exact, MAE12.142857, signed−9.857143;
103 missed positions34 unmatched/spurious peaks. Held-out counts2/2/4/6/11/16
vs20/20/20/20/19/19;15vs7. This candidate fails generalization and must not replace
V2. Solver rejects all inventory claims: rejection100%, false accepted0,
accepted-scan accuracy undefined. These tiny visual-reference groups are not
new physical acceptance data. Forward-only CPU latency12.21ms/face, excluding
image upload/localization/rectification/bands. The final recorded rerun was
48.80ms/face (earlier12.21ms); these single CPU probes vary with system load and
are not a deployment latency benchmark.

Actual localization5 reviewed→8 proposed:3 IoU.5 matches,3 fragmented faces,
0 merges,0 wholly unassociated faces;2 fail one-to-oneIoU matching. Authenticated
real-checkpoint route/auth/hash mismatch/homography/rim output checks pass;
quality diagnostics present, completeness/occupancy/grid unresolved, total=null,
verified=false. All77 backend tests pass including11 solver cases; training
self-check passes. AWS bundle18 files staged locally, no S3/account operation.
One-epoch local resume check restored a removed output best.pt from checkpoints
with identical SHA256499993284f1205fa0a95aff0705c911f122e487c6bfdc20b9b65b154f2febada.
Docker/AWS CLI unavailable; image build/GPU/cloud execution remain unverified.

Artifacts: STACK-HEATMAP-HYBRID-V1 research only; report
reports/stack-heatmap-20260928/README.md, datasetmanifestSHA
7d376b4e79a363f6d45d82f65b908bb53ae5dcffe566b17349b31303572a30de.
Local-only recorded smokecheckpointSHA8fbac40e4bf813f5fcc785ead7f93011aad3e94f4b11580584e410d745b98512;
CVfold0SHA977d644e8bdab45ec4c5053c57019a95135ab4ddc134b942e870b4f5be114a3c;
CVfold1SHA0119797ad85763bea4b160a6377a0aab33e4009a79a0e788ad3820bd77ee3478.
Weights under ignored work/; report histories/metrics/checksums published.
The report artifact path disables Git newline normalization to preserve its
content hashes across Windows/Linux checkout; staged manifest/frozen bytes checked.
Production RoboflowV2 and last recorded APK0.3.3+9 unchanged by this task;
no live production/version claim was rechecked, no APK rebuilt or deployment.

Next: complete full-resolution existing label/scene QA across varied counts,
freeze an eligible V5 control with independent development groups, audit heatmap
location/pitch failures before tuning, improve stack localization separately,
label occupancy independently. AWS execution requires explicit cost approval and
verified IAM/image/quota. New physically recounted holdout gates production only,
not development/training. Full architecture/reproduction in
model-improvement/stack-heatmap/README.md and aws/README.md.

## 2026-09-24 — focused layer-label audit and training supplement

Prepared five rectified faces with99 manually reviewed visible-layer boxes,
numbered review-board.jpg, per-row detection-centre audit and import ZIP under
reports/two-view-20260924/focused-training. New script prepare_focused_training.py
checks bounds, count totals and contiguous non-overlapping intervals. Ruler review
corrected draft boundaries; final regeneration passes, including UTF-8 BOM CSV.
User authorized choosing any existing photos. Cloud UI verified all five crops
contain 20/20/20/20/19 saved labels, all TRAIN; source count395 (was390), split
currently283/76/36. Audit of the saved candidate records found neither img04
(visual32, old V2=29) nor img05 (visual120, old V2=124) safe as an independent
post-training test: reports/dataset_reconciliation.csv records a near-duplicate
of each in historical Roboflow TRAIN. These historical labels are visual
references, not user-confirmed physical counts. Candidate metadata and README
corrected; frozen files were not changed. V5 not generated and training not
started: wizard still carries a required tag filter, and its 283/76/36 split is
not verified for scene separation. No plan upgraded or credits spent.
The candidate JSON parses and documentation `git diff --check` passes.
Next: reserve a newly photographed, physically counted warehouse scene before
training, confirm scene-grouped splits, then train and compare counts by stack.
ProductionV2/APK0.3.3+9 unchanged; Python host not deployed.


## 2026-09-24 — completed stack crop diagnostic

12 fresh V2 inferences / four HTTP 200 diagnostic requests: full-wide 76, side19;
manual face crops 13/14/17/14/15 (centre-filtered), perspective-corrected faces
19/22/20/22/17. Manual reference20/20/20/20/19. Corrected total100 is NOT exact:
absolute per-stack errors sum7; one of five counts matches. Bands12/11/19/19/10.
Automatic localization still splits five stacks into eight regions. Higher
confidence post-filtering worsens totals; lower threshold unavailable via Worker.
Saved reproducible scripts/evaluate_stack_crops.py, raw responses, overlays,
results and targeted training configuration in reports/two-view-20260924/crop-experiment.
Offline replay/checks pass; git diff --check passes. OpenCV warp required one thread.
No retraining/deployment/APK rebuild: productionV2, APK0.3.3+9; Python unhosted.
Next: review per-tray label extents, assemble curated scene-separated training
snapshot, validate automatic face localization and evaluate on independent counts.
Paid tag editor blocks that UI operation, not all training or local experiments.


## 2026-09-24 — manual recount, fresh backend check and Roboflow corrections

Manual visible references: wide 99 (20/20/20/20/19), side 19. Numbered evidence,
118 approximate front-face COCO boxes and comparison saved under
reports/two-view-20260924/manual-corrections. Hash/bounds/count checks pass.
Fresh HTTP 200 request 77824bf2-c4d7-4c08-9714-7018f1c6d67f: V2 counts 76/19;
wide error 23 (23.23%), side zero. Not precision/recall or physical 3D truth.
Roboflow identified originals as duplicates and applied annotations to existing
records ClMOF3wMZhPg4OJENlvT / KCJZzPDrafDfPRAWM3Vn. UI verifies 99/19 labels,
both TRAIN. Added manual-correction-20260924 tags. Frozen versions preserved.
Draft V5 name entered, but version not generated and training NOT started:
curated tag-filter editing is paid-plan-only; NAS also locked. No upgrade bought.
Do not broaden to all 390 images unchecked; historical audit flags label overlap.
Next: resolve Roboflow plan access or GPU/Colab route, assemble curated snapshot
including corrections, verify split/source inclusion, train and evaluate held-out
scenes. APK remains 0.3.3+9, production model V2, Python service still unhosted.


## 2026-09-24 — actual two-photo reconstruction experiment

Preserved supplied pair and hashes in reports/two-view-20260924. Identical to
previous images 1/4; historical model counts 76/19 reused as history only.
User confirms 19 for the side example, not a full-scene ground truth.
Added reproducible scripts/reconstruct_pair.py using installed OpenCV/NumPy.
Strict mutual SIFT: 2 matches; relaxed 0.75: 8 candidates/7 fundamental inliers;
0.85: 52 candidates/11 fundamental inliers. No accepted physical association,
camera pose, point cloud or total. Synthetic triangulation self-check passes;
real pair does not reach pose stage. Saved matches.jpg and result.json.
Next: unchanged-scene continuous corner sweep, complete top/base, per-stack
physical reference; rerun geometric matching before counting fusion.
No APK rebuild or deployment; APK remains 0.3.3+9, Python service unhosted.


## 2026-09-23 — private R2 deployment and four-photo measurements

User confirmed no Oracle/Google account. Existing Cloudflare R2 access works;
created private egg-tray-scan-archive and deployed archive-before-inference
Worker version 4c1480e6-0136-4514-8640-b67b02eb98ac. No paid plan enabled.
13 Worker tests pass including stored bytes/key metadata. An initial placement
test caught the archive block after the model-path return; moved it before
inference, reran checks and redeployed. Supersedes intermediate 6986844a version.
Live upload + authenticated R2 download SHA-256 match proves preservation.
New scans are archived; old photos are not recovered. In-app download UI is
not yet implemented; operator-only R2 retrieval is documented in VISION_HOSTING.

Four supplied photos retained in reports/warehouse-20260923. Fresh RF counts
76/87/19/19. Automatic localization fragments five wide-view fronts into 8/7
regions; bands are inconsistent and cannot be summed. Side bands 16/18; image
4 top clipped. No accepted correspondence, calibrated 3D, verified total or
accuracy claim. Ground truth/unchanged scene still unconfirmed by user.

Prepared authenticated diagnostic Python hosting entrypoint and Dockerfile.vision;
14 targeted Python tests pass. No Docker runtime available to build-test it.
Not hosted: account creation or explicit paid Cloudflare choice is outstanding.
Next: resolve host choice, deploy/test container, add private Worker-to-service
integration, fix face localization, then authenticated per-scan app retrieval.
APK stays 0.3.3+9; production hybrid_ready remains false. No commit/push performed.

## 2026-09-23 — server-side photo recovery and hosting clarification

User clarified recovery must target previously submitted inference images, not
the phone gallery. No gallery search performed in this investigation. Live
Worker /health again reports hybrid_ready=false. Request code forwards images
to serverless.roboflow.com/projec-mutta/2 without an archive write. Recent scans
in Android store metadata only, with no original image path or download URL.
Python /candidate/count-3d remains local and disconnected from production.

Authenticated Roboflow workspace inspection: Asset Library contains 1,440
images; newest visible assets include warehouse-layer-pilot-20260907 samples
tagged as training/review data. No Redmi scan provenance was established.
Vision Events lists Line Crossing Counts with 0 events / no events received.
No original phone inference images recovered; these checks do not establish
whether Roboflow maintains any provider-internal retention accessible to support.

Recommended next implementation: private durable photo archive indexed by scan
ID/view with authenticated retrieval from recent scans, then hosted Python band
and multi-view service. Oracle Always Free ARM VM is a free CPU pilot candidate
(availability/ARM dependencies must be checked); Cloud Run is a managed fallback
with billing and usage-dependent charges. Neither was provisioned. Hosting the
current candidate does not itself validate exact inventory or hidden occupancy.

## 2026-09-23 — existing-photo upload

Added UPLOAD PHOTOS alongside live THREE-PHOTO SCAN. Native file selection has
explicit LEFT/RIGHT/STRAIGHT slots and previews, preserves user originals, checks
file size/type/resolution/blur/exposure, normalizes owned copies to JPEG off the
UI isolate, and requires confirmation of unchanged stock before submission.
It reuses the existing API/results/retry flow without initializing a camera.
Uploaded evidence explicitly reports no verified pose or live checks. Live
capture and torch remain available. Version advanced to 0.3.3+9.

Full Flutter test suite passed (62 tests); final Flutter analysis is clean.
Expanded upload submission/cleanup checks also pass (2 targeted tests).
Release APK built successfully (518.5 seconds); apksigner verification passed.
Artifact: egg-tray-counter-0.3.3-photo-upload-staging.apk. SHA-256:
8f20ef7a4f7c1b1a583321a1c13f6eae4ac014153d64a32f048579dce1854913.
ADB install -r succeeded on Redmi Note 9 Pro, preserving existing app data;
dumpsys confirms 0.3.3/build 9. Device UI verifies both home capture options and
the three labelled upload slots with confirmation and disabled submit state.
Native picker completion/full server submission remain unverified: phone entered
an active call, so device interaction stopped. No improved counting accuracy is implied.
Production band/3D service is still disconnected; unverified totals stay null.

Photo recovery investigation: Worker source/config has no image storage binding
or retrieval endpoint. Request logs contain metadata, not an image archive.
Android history stores result metadata only; the scan flow cleans cached photos
on accepted results, replacement, new scans and exit. After the user connected
the Redmi Note 9 Pro and ADB was restarted, the phone became accessible. It has
0.3.1/build 7 installed. Its external app directory is empty; run-as refuses
private storage access because the release package is not debuggable.
Recovered two gallery photographs of the old 84/90/87 result screen into the
ignored work/phone-photo-recovery-20260923 folder (IMG_20260915_114750.jpg and
IMG_20260915_114751.jpg). These are NOT the uploaded tray input images. No input
triplet recovered. Roboflow-side retention has not been established. Unrelated
local gallery copies inspected during recovery were removed; phone originals
were not changed.

Next: exercise Android native picker and a full upload after the phone is free.
Original scan inputs need user-selected surviving photos or a new scan.
No commit/push or backend deployment was performed in this checkpoint.


## 2026-09-23 — torch and warehouse-counting requirements

Added native camera torch on/off control, disabled concurrent capture/toggle,
discarded pre-toggle frame measurements, and reported unsupported torch hardware
with an external-lighting recovery action. Version 0.3.2+8. All three targeted
camera lifecycle/torch widget tests pass. Targeted Dart analysis is clean after
fixing two style findings from full Flutter analysis. Release build succeeded
(829.4 seconds); apksigner verification passed and aapt confirmed 0.3.2/build 8.
Artifact: egg-tray-counter-0.3.2-torch-staging.apk, 60,221,864 bytes, SHA-256
63b1ac85ca7a49906a32f8310feac22316da81d2009a0a0eb259fabb09e7db11.
Uses the existing debug signing key for staging. No authorized device/emulator
was listed by ADB this session; physical torch behavior remains unverified.
These changes and this APK have not been pushed in this checkpoint.

Fresh deployed /health and /ready requests confirm hybrid_ready=false and
projec-mutta/2. The APK still submits model_spatial_v1 to the same Cloudflare
gateway. Python band analysis remains local at /candidate/count-3d and is
explicitly disabled in production; the Worker does not forward to it. No
retraining, 3D generator, hosted Python integration or new deployment is claimed.

Added docs/WAREHOUSE_3D_ACCEPTANCE_PLAN.md to capture the user's proposal and
implementation order. It specifies measured real tray geometry, partial/empty
occupancy, per-block identity, calibrated pose/scale, harmonic-aware bands,
corner deduplication and explicit unknown/interior extrapolation status. Current
camera direction guidance is not calibrated pose. Unknown occupancy prevents a
verified warehouse total even when exterior geometry and lighting are good.

Cloudflare documentation was checked: 128 MB isolate memory; Free CPU 10 ms;
Paid default 30 s and configurable up to 5 min. Account plan/current invocation
outcome remain unverified. Multipart/base64 buffering is a resource risk, not
proof of whether previous failures were exceededCpu or exceededMemory. The
mobile 45-second timeout is separate. Next: real-device torch validation, measured
tray geometry and same-scene physical reference triplets, then authenticated
hosting and evaluation of the existing Python candidate before production fusion.

Latest deployment (2026-09-16): ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 fixes the
installed APK preflight mismatch while preserving the old no-ID baseline path.
12 Worker tests passed. See the final append and backend compatibility report.

## GitHub publication checkpoint — 2026-09-15

- User requested committing and pushing all pending changes, including this file
  and context.md, to origin/codex/hybrid-cell-counting.
- Included the retraining clarification, architecture/continuation documents,
  six original photographs, attachment manifest and draft foreground labels.
- Verified both intake JSON files parse, all attachment and annotation hashes
  match archived photos, and all draft boxes fit their manifest dimensions.
  Targeted credential-pattern scan passed. Runtime tests were not rerun because
  this checkpoint changes documentation and data only.
- Artifact remains the previously verified 0.2.2+5 development APK; production
  remains the recorded baseline rollback. No build, training or deployment here.
- Next: complete instance/occupancy label review, save unchanged-model raw
  predictions, then evaluate a separate candidate on held-out scenes. Missing
  reviewed labels and original capture triplet remain development prerequisites.

## Documentation update — retraining clarification, 2026-09-15

Appended the training/validation sequence to docs/100_TRAY_SCENE_PLAN.md and
updated context, previous context, architecture and conversation summary.
Recorded six unique photo inputs, incomplete draft labels and the distinction
between physical tray detection and brightness bands19/19/20/19/19. Training
has not started; no accuracy, deployment or APK changes claimed. Next: reviewed
instance/occupancy labels, raw baseline predictions, representative training
data and held-out evaluation. This update is documentation only.

Updated: 2026-09-15. Read this file before modifying the repository.

Latest research: see `reports/user-100-tray-case-20260915/RESEARCH_20260915.md`
and the final append below. Assisted band candidates are 19/19/20/19/19;
physical/eligible totals unresolved. No APK rebuild or production deployment.

## Development resumed — 100-tray case, 2026-09-15

- User authorized proceeding and confirmed five columns of 20 egg-containing
  trays plus one empty on top of middle column (physical per-column 20/20/21/20/20).
  Saved attachments with hashes and user-reported truth in
  reports/user-100-tray-case-20260915/reference.json. This is not independently
  recounted inventory; keep separate from the earlier 32-tray img04 benchmark.
- Inspected the user-supplied WhatsApp folder. It contains two screen photos and
  the blue-annotated scene, not the original LEFT/RIGHT/STRAIGHT captures. Asked
  for those originals or a fresh triplet; no confirmed triplet yet available.
- Fixed local CountingService: individual egg_tray boxes cannot enter the
  whole-stack layer counter even with the experimental provider alias. Updated
  API regression test verifies typed unsupported_model_output rather than false
  verification. Production Cloudflare baseline remains unchanged.
- All 44 backend tests passed using the Python standard OS fallback after this
  host's WMI query failed (0x8007000e). Initial WMI-disabled retry failed because
  platform expected an exception, not None; final harness raised OSError from
  _wmi_query, with no application logic patched. Targeted Ruff checks passed.
- Added runnable scripts/evaluate_100_tray_layers.py using existing rectification,
  layer extraction and overlays. Manual face ROIs on the 675x507 supplied image
  produced 40/10/10/11/11 physical-layer candidates versus 20/20/21/20/20.
  Column-2 overlay visually skips alternating rows despite quality 0.86. This
  demonstrates layer-period ambiguity; quality is not calibrated count accuracy.
  No global factor, truth-based pitch or automatic eligible total applied.
- Next: original captures/raw detections, diagnose per-tray errors and layer
  harmonics together, improve stack localization and spacing ambiguity handling,
  then cross-view identity/occupancy integration. No training, deployment or APK
  rebuild in this development checkpoint. Full hybrid objective remains incomplete.

## Latest production state — baseline rollback, 2026-09-15

Planning update: user supplied screenshots reporting V2 84/90/87 and a scene
photo; states 100 trays plus one extra empty. Interpreted as 100 egg-containing
and 1 empty, user-reported (not independently recounted). Count errors 16/10/13;
no instance precision can be derived. Saved phased diagnosis, retraining,
row/column/layer reconstruction, optional marker and held-out validation plan in
docs/100_TRAY_SCENE_PLAN.md. Original three capture files, raw detections and
per-stack/empty-tray labels are still needed to identify causes. No model training,
backend redeployment or APK change made for this planning request. Preserve the
32-tray img04 benchmark separately; production remains the rolled-back baseline.

- User explicitly requested the older baseline backend without cell IDs.
  Wrangler deployment history identified the immediately preceding version as
  621a5a9c-f486-455f-9a15-0965ca3a710f (2026-08-31). Rolled back to that exact
  version with `wrangler rollback <version> --yes`; CLI confirmed 100% traffic.
- Replaced version 0519381f-b99e-4015-8279-cb2c0f99f7f2. Local source was not
  reverted; do not redeploy it unintentionally, since it restores the newer API.
- Live /health returned status ok and /ready identified Roboflow projec-mutta/2.
  Evidence: reports/cloudflare-rollback-20260915/. Post-rollback image uploads
  could not be verified: curl and httpx both hit connection resets during TLS.
  No successful fresh inference or no-ID upload is claimed for this rollback.
  The same historical baseline previously passed inference in the saved report.
- The 0.2.2 APK requires model_spatial_v1 and will reject the restored baseline
  health response. Rolling back the server does not remove mandatory UI fields
  from 0.2.1 either. A baseline-compatible APK is required; none rebuilt here.
- Previous successful optional-marker deployment entries below are historical
  and superseded by this user-requested rollback. Hybrid work remains preserved.

## Latest deployment checkpoint — 2026-09-14

- User-approved OAuth succeeded; Wrangler deployment access is now verified.
  Earlier authentication-blocked statements below are historical.
- Deployed egg-tray-counter-api using Wrangler 4.125.0 deploy --keep-vars.
  Version 0519381f-b99e-4015-8279-cb2c0f99f7f2, source checkpoint
  e92babb97ba84400dba81ad71b288f8f304e8e18. URL:
  https://egg-tray-counter-api.rahultech72216.workers.dev.
  Existing variables/secrets preserved. Compile/dry-run/all 11 tests passed.
- Live health advertises model_spatial_v1; readiness identifies projec-mutta/2.
  No-floor-ID live request returned HTTP 200 with empty echoed cell_ids and
  valid spatial detections/counts 29/9/12 for separate benchmark scenes.
  Response contract/model, box validity/count consistency and null inventory
  totals verified. Evidence: reports/cloudflare-deployment-20260914/.
- APK 0.2.2's backend-contract mismatch is RESOLVED; no APK rebuild required
  for this server update. No physical Android-device scan was performed.
- hybrid_ready remains false. Exact hybrid counting, robust physical-stack
  matching, occupancy and image-to-hybrid integration remain unfinished. This
  smoke test is not a same-scene three-view accuracy evaluation.
- Next: implement those missing vision/integration components, evaluate held-out
  same-scene captures with checked truth and run device tests. Preserve the
  known signing-key limitation. Earlier deployment blockers are superseded.

## Latest artifact checkpoint — 2026-09-14

- After the prior process ended without an APK, resumed the cached release build successfully. Root artifact egg-tray-counter-0.2.2-hybrid.apk is version 0.2.2+5, 59,631,396 bytes, SHA-256 1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b. Manifest, APK v2 signature and ZIP CRC verified. Full evidence: reports/APK_0.2.2_BUILD.md.
- This is an incomplete DEVELOPMENT hybrid build. Optional-marker capture/model diagnostics are implemented; automatic physical-stack matching, occupancy evidence and image-to-hybrid integration remain unfinished. No near-100% claim is supported.
- The debug signing certificate differs from the old 0.2.1 APK. It cannot update that installation in place; preserve existing inventory data and obtain the original signing key for an upgrade. No device install/uninstall was attempted; adb listed no devices.
- Checks: Flutter analysis clean, 16 mobile tests passed; 44 backend tests passed; Worker tsc/dry-run/11 tests passed; Ruff and whitespace checks passed. These validate code/build behavior, not field counting accuracy.
- Fresh deployed V2 inference returned 29 versus img04 visual reference 32 (error 3, 9.375%). Instance precision and three-view hybrid accuracy remain unavailable. See reports/manual-reference-20260913/LIVE_EVALUATION.md.
- Wrangler whoami is still unauthenticated on 2026-09-14. Existing deployment uses the old contract and is incompatible with the new mobile preflight. No new deployment, model promotion, commit or push occurred.
- Next: obtain original signing key for in-place upgrades, complete CLI authentication and deploy the tested compatible backend, obtain real same-scene three-view photos with checked counts/occupancy, implement and evaluate automatic association/occupancy/hybrid integration, then perform device end-to-end tests. Plan and reusable prompt: docs/COUNTING_EXECUTION_PLAN.md.

## Latest execution checkpoint — optional markers and reference evaluation

### Continuation verification (2026-09-13, supersedes setup blockers below)

- Flutter 3.47.4 / Dart 3.13.3 now run. Android platform 36, build-tools 36.0.0 and NDK 28.2.13676358 are installed under work/toolchains/android-sdk; user authorized SDK license acceptance. Android tools archive SHA-256 verified against vendor: 90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a.
- Mobile pub get succeeded, analysis has no issues after removing one redundant null fallback, and all 16 Flutter tests passed. Source version bumped to 0.2.2+5. Release APK build is running through initial Gradle setup; no artifact verified yet. Gradle 9.3.1 archive hash matches vendor 17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43.
- All 44 backend tests passed again; Ruff passed the new hybrid core, tests and evaluator. Worker npm run check passed tsc, Wrangler deployment dry-run and all 11 runtime tests. Git diff --check passed with line-ending warnings only.
- Fresh inference through the existing deployed Worker succeeded (HTTP 200), V2 returned 29 for img04 against reference 32: absolute error 3, relative error 9.375%. This replaces the earlier limitation that only saved RF output was available. See reports/manual-reference-20260913/LIVE_EVALUATION.md and raw JSON. The request used three different benchmark scenes to exercise required upload fields; it is NOT a multi-view accuracy test.
- Existing live health returns only status ok; ready reports configured V2. Actual inference is now verified through that deployment, but its old baseline contract is incompatible with the changed app. Wrangler whoami remains unauthenticated after the user-approved device flow timed out. No deployment or model promotion occurred.
- Exact hybrid remains incomplete: automatic physical-stack association and per-layer occupancy evidence are not integrated. The new Worker path provides unresolved model evidence, not a certified count. Asked for a real same-scene three-view folder and checked physical tray total.
- After midnight 2026-09-14: a second Wrangler device authorization also timed out; do not reuse either expired code. No Android device/emulator is attached (adb devices empty). APK build remains active in Gradle dependency/configuration compilation; the JVM is making progress, but available RAM is under 1 GB. No new APK has been produced or verified.

Build continuation (PowerShell from mobile, after checking for an existing build process): set ANDROID_HOME and ANDROID_SDK_ROOT to the absolute work/toolchains/android-sdk directory; set JAVA_TOOL_OPTIONS to `-Djavax.net.ssl.trustStoreType=Windows-ROOT -Djavax.net.ssl.trustStore=NONE`; run `..\work\toolchains\flutter\bin\flutter.bat build apk --release`. Version is 0.2.2+5 and signing still uses the existing debug key configuration. If a package is produced, verify manifest, signature and SHA-256 before copying/delivering it. The current source is an incomplete development counter, not a near-100% hybrid release.

- Restored backend requirements into work/vision-deps using bundled Python 3.12 and the official PyPI index. All 44 backend tests passed (dependency deprecation and pytest cache-write warnings). The 11 Worker runtime tests passed using Node TypeScript transformation; full tsc/Wrangler checks are still blocked by npm installation failures.
- Mobile capture now accepts omitted floor IDs; optional IDs remain validated. Mobile API requests model_spatial_v1; Worker accepts that contract without markers, retains spatial model boxes and returns explicitly unresolved diagnostic counts. This is NOT an operational exact-count hybrid. Mobile edits/tests have not yet run under Flutter.
- Saved manual reference and reproducible evaluation script. Reference: 32 visible trays (16 + 16), non-blind visual recount. Historical RF replay: 29, error -3, absolute error 9.375%. Fresh assisted layer-only experiment: 23, error -9, absolute error 28.125%. Exploratory RF-guided layer candidate: unresolved left face, 14 on right, no total. No operational three-view hybrid accuracy or instance precision/recall result exists. No benchmark labels changed.
- Created docs/COUNTING_EXECUTION_PLAN.md with ordered work and reusable prompt. Saved a user-requested memory note for the visual reference, including its limitations.
- User reports service authentication complete; browser tab inventory contains the Cloudflare dashboard and Roboflow workspace. Repeated page-control failures (CDP focus/Page.enable and webview attachment timeouts) prevent live inference/deployment verification. Preserve the sessions; do not ask for private credentials in chat.
- APK setup underway: Flutter stable source cloned to work/toolchains/flutter but checkout initially failed on Windows long paths. core.longpaths enabled locally; restore is running/needs verification. Android command-line tool download was resumed after a nearly-complete timeout; verify vendor SHA-256 before extraction. No new APK exists.
- Worker npm ci retries fail with npm exit-handler/network errors, including an escalated retry; inspect latest log and use a supported package manager/runtime. No deployment, model promotion or source push performed.

### Immediate continuation steps

1. Finish/verify Flutter checkout and Android SDK tool hash/extraction, then resolve required JDK/SDK licenses and run Flutter checks/build. Do not label diagnostic-only source as a completed hybrid APK.
2. Recover browser control or verified Wrangler/API access using existing authenticated sessions; do not deploy diagnostic-only changes as exact counting.
3. Improve automatic stack-face localization, tray rim counting and cross-view association against development images; handle occupancy explicitly. Keep saved manual truth outside inference inputs.
4. Re-run frozen and held-out multi-view evaluation; report count errors, rejected coverage, assistance and missing precision labels honestly. Complete image-to-hybrid integration before claiming an exact backend count.

## Current checkout correction — 2026-09-13

- Verified starting HEAD: `a6c4263b9f211068572d6e510847d077a9cdec53`, branch `codex/hybrid-cell-counting`; starting working tree was clean.
- The older interrupted hybrid source listed below is ABSENT from this checkout. Treat that section as history, not present implementation. No local backend virtualenv or Worker node_modules was found. The installed Python 3.14 and parent virtualenv lack pytest/OpenCV; Flutter is not on PATH.
- Read AGENTS.md, context.md and the handover/digest/continuation documents, plus the relevant prior conversation. Root previous_context.md and prompt.md are absent; context.md and previous_chat.md supply continuation requirements.
- Implemented new standalone `backend/app/vision/hybrid.py`: uncertainty-aware measured height candidates, stable column identity, exact evidence agreement, distinct image/pose checks, explicit per-layer egg occupancy, and complete-scope totals. It is NOT connected to API/mobile and does NOT detect image markers or egg occupancy.
- Added `backend/tests/test_hybrid_core.py`: 20 unittest cases passed using Python 3.14, covering measurement ambiguity, bounds, disagreement, missing columns, empty trays, unknown occupancy, duplicate images/columns and camera pose consistency. Full backend/Worker/Flutter suites have not run in this checkout.
- Added `docs/hybrid-evidence-contract.md` with required trusted vision inputs and held-out evaluation rules. No new field accuracy result exists.
- Final core rerun: all 20 tests passed after strict boolean validation. Python syntax checks passed; git diff --check passed for tracked edits (line-ending normalization warnings only). Recomputed historical summary.json metrics: 10 images, 2 exact, MAE 22.9; no inference was rerun.
- Existing artifacts, model and endpoints are unchanged. No APK build, deployment, live readiness verification, commit or push in this session. Earlier APK hash and live-service checks below remain historical reports.

### Next steps from this checkout

1. Obtain real three-view warehouse photographs with manually verified per-column tray/occupancy counts, surveyed floor/wall references and camera calibration. Asked the user for the folder path; no answer received yet.
2. Restore a compatible backend test environment and Worker dependencies, then implement and test image-to-evidence geometry, spatial RF association and occupancy adapters against those measurements. Never mark generic egg_tray detections as occupancy proof.
3. Connect the tested evidence component to an authenticated Python service and Worker gateway, including calibration identity and idempotency, then unify mobile capture/results and manual review.
4. Evaluate untouched held-out scenes with exact counts, MAE and acceptance/rescan coverage. Calibrate evidence thresholds from development data; do not claim near-100% from unit tests.
5. Verify service authentication/readiness, run all platform checks, then build/deploy the requested 0.2.2+5 APK and record hash/signature/device evidence. Those delivery goals remain incomplete.

## Completed work (historical checkpoint)

- Inspected repository history and current mobile/Worker counting flow at commit `8073dbe`.
- Read the user's continued-development handover and existing technical handover.
- Confirmed that the current app splits photo detection and manual Grid + Height into separate modes; automatic floor and wall marker analysis is not implemented.
- Added persistent working rules in `AGENTS.md` and current requirements in `context.md`.
- Fetched origin and confirmed main matched `8073dbe` (0 commits ahead/behind); created `codex/hybrid-cell-counting`.
- Installed the existing backend requirements plus pytest/Ruff into `.venv`; verified OpenCV 4.12.0 exposes `aruco`.
- Ran `npm ci` and `npm run types` in `cloudflare-worker` successfully. npm reported 3 high-severity dependency advisories; these have not been investigated yet.
- Began hybrid implementation in local working-tree files listed below. These edits are incomplete and untested, and are NOT part of this documentation-only checkpoint.
- No model promotion, deployment, or new APK build has been performed.

## Interrupted implementation (local only, not ready to deploy)

- New `backend/app/services/hybrid.py`: layout/camera/marker validation, ArUco floor/wall pose recovery, projected column ROIs, height/rail evidence, RF spatial assignment and per-cell fusion. Draft only; no new runnable tests yet.
- Modified `backend/app/config.py`, `main.py`, `api/routes.py`, `repository.py`: hybrid configuration, optional service setup, gateway token validation, camera profile checks, response routing and reuse of idempotency storage.
- Modified `backend/app/providers/roboflow.py`: retain `egg_tray` boxes for hybrid mode, fixed overlap setting, additional numeric validation, 401 authentication handling.
- Modified `cloudflare-worker/src/index.ts`: draft HTTPS gateway forwarding, upstream token, upload bounds, explicit hybrid-request routing, no silent fallback for hybrid clients.
- Mobile source has not been updated. It still requests the old contract and shows separate modes. There is no end-to-end hybrid path yet.
- Review the draft geometry and fusion before relying on it: empty-cell handling, occlusion/completeness, camera-profile identity, calibration tolerances, rail-vs-rim distinction, marker visibility, and input validation need tests and field evidence. The one-tray RF tolerance is a draft policy, not validated accuracy.
- New `/ready` draft deliberately reports configuration rather than claiming a successful live inference. Authenticated Roboflow readiness still needs implementation/verification.
- This documentation push does not contain these source edits. On another machine, resume from the plan or obtain the local working tree; do not assume the draft is on GitHub.

## Verification results

- Existing APK ZIP integrity passed; embedded manifest is version `0.2.1`, versionCode `4`, package `com.dharani.eggtray.egg_tray_counter`, min SDK 24, target SDK 36.
- APK includes `floor-cells-wall-reference.png` and arm64-v8a, armeabi-v7a, x86_64 native libraries.
- Live Worker `/health` returned HTTP 200 and `{"status":"ok"}` after retry with a browser user agent. It lacks `scan_contract: cell_identity_v1`, which the existing APK requires.
- Live `/ready` could not be verified: connection failure / Cloudflare 403 on probes. Do not report it as ready.
- Direct Roboflow `projec-mutta/2` responded HTTP 401 without credentials. This confirms a reachable authentication gate, not successful inference.
- Saved repository logs report three successful emulator cold launches; the handover reports 14 Flutter tests and signature verification. These have not been rerun on this computer.
- Frozen historical RF-only benchmark: V2 2/10 exact, MAE 22.9 trays. No new height or hybrid accuracy evaluation exists.

## Current artifacts

- Latest existing APK: `egg-tray-counter-0.2.1-grid-pilot.apk`.
- Version: `0.2.1+4`; size: 59,631,400 bytes.
- SHA-256: `c4459142ec145510de0cc961208dd78ff0357c605eb05d55de15af252413b6a2`.
- Configured model: `projec-mutta/2` (RF-DETR Medium), unchanged.
- Public API: `https://egg-tray-counter-api.rahultech72216.workers.dev`.
- Requested next artifact: `egg-tray-counter-0.2.2-hybrid.apk`; not built.

## Blockers and open prerequisites

- Cloudflare and Roboflow browser sessions both opened at login pages; no authenticated service session was available.
- Flutter, Android SDK/ADB, and the earlier `Documents/Codex/toolchains` installation were not found in the checked locations. Python, Node, and Java are available. Toolchain setup is still needed.
- Worker and Python dependencies are now installed locally; Flutter/Android build tools remain unavailable in checked locations.
- Flutter release metadata and an attempted SDK URL returned HTTP 404. No SDK was downloaded; resolve the official archive location/version before building.
- `npx wrangler whoami` explicitly reported unauthenticated. Cloudflare and Roboflow login tabs were reopened at the user's request; successful sign-in is not yet verified.
- Real calibrated marker photographs and camera/depth calibration have not yet been located. An illustration is not metrology or test evidence.

## Exact next steps

1. Read `context.md` and `previous_chat.md`; inspect git status and the local draft files above. Preserve them while synchronizing the documentation branch.
2. Add runnable tests for calibration validation, synthetic marker pose, perspective height, RF assignment, occlusion, distinct views, fusion disagreements, idempotency and gateway failures. Run Ruff and backend/Worker checks; fix the draft before proceeding.
3. Check the user's Cloudflare/Roboflow sign-in state and complete CLI authorization as needed. Do not ask for private keys in chat.
4. Obtain or construct a real measured layout/camera profile and select an authenticated Python hosting runtime. Do not use the illustration as calibration. Finish server-side geometry/fusion and gateway wiring.
5. Integrate this into one mobile scan/result flow, preserve manual corrections as fallback, and distinguish network failure, incompatible backend, and unavailable inference in status.
6. Test geometry/association/fusion and gateway contracts, evaluate untouched warehouse benchmark assets, and report unavailable height evidence rather than inventing a score.
7. Deploy only after local verification and authenticated runtime availability; verify `/health`, `/ready`, authenticated Roboflow inference and a full scan.
8. Run requested Flutter clean/pub get/analyze/tests, backend and Worker checks, build a new APK, verify version/signature/hash and emulator scan if available.
9. Update this file and technical handover, commit legitimate source changes, push the branch/PR and publish the verified APK when possible.

## Documentation checkpoint

The user requested preserving the chat and pushing it to GitHub. `previous_chat.md` records the available user/assistant conversation; runtime instructions and raw tool logs are excluded. `context.md` contains the concise continuation context. Only these documentation files and `AGENTS.md` are intended for this checkpoint. Documentation verification and push result are recorded below after execution.

Documentation verification: all four files read successfully; both supplied continuation briefs are preserved in full, transcript placeholders are resolved, and targeted credential-pattern checks found no matches. Git whitespace checks passed. Checkpoint commit `a95a162a7af918a3f393db2099abfdd53db1ca57` was successfully pushed to `origin/codex/hybrid-cell-counting`. Git confirmed creation of the remote branch and tracking configuration. Unfinished hybrid source remains local and uncommitted.

## 2026-09-14 — backend clarification and requested GitHub checkpoint

The user asked why deployment is blocked while inference works, whether the
backend routes directly to Roboflow, why exact hybrid counting is unfinished,
what to do next, and to append the progress/previous context and push to GitHub.

- Live checks repeated: /health returns status ok; /ready reports ready and
  projec-mutta/2. Wrangler whoami again explicitly reports unauthenticated.
  These are different capabilities: the existing deployed Worker can serve
  requests using its server-side Roboflow credential even though this machine
  lacks authorization to replace the Worker. Browser sign-in is not proof that
  Wrangler completed its own authorization. Previous device flows expired.
- Verified request path: Android app -> Cloudflare Worker -> Roboflow serverless
  projec-mutta/2 -> Worker response -> app. The APK does not call Roboflow with a
  bundled private key. The deployed processing mode observed in the saved live
  response is cloudflare_roboflow_egg_tray_baseline. It uses whole-photo count
  agreement/mismatch logic, not the requested physical-stack hybrid.
- The current Python service has a separate layer-counting path with spatial-order
  association. The newly added calibrated hybrid core has no API/image adapter
  and the live Worker does not call it. Automatic robust cross-view identity,
  per-tray egg occupancy and optional-marker evidence extraction/integration are
  unfinished implementation work, not merely authentication blockers.
- The 0.2.2 app expects model_spatial_v1, which the live health response does not
  advertise. Deploying the current local Worker would restore that contract and
  expose unresolved model evidence; it would NOT complete exact hybrid counting.
  APK compilation and 71 passing tests do not prove inventory accuracy.
- Remedy for deployment: complete Wrangler OAuth on the deploying machine, or
  configure a narrowly scoped Cloudflare deployment token through a local secret
  environment/GitHub Actions secret, or connect the repository using Cloudflare
  Workers Builds. No private token belongs in chat, source or the APK.
- Remedy for counting: finish the image-to-evidence adapter and Python gateway,
  robustly associate physical stacks across views, classify visible occupancy,
  fuse model/layer/calibrated-height evidence with explicit uncertainty, then
  evaluate held-out same-scene three-view captures with checked per-stack counts.
  Missing floor IDs must use the model/layer route. Occluded/ambiguous content
  cannot be certified from photo-count agreement.
- Retained evidence: fresh V2 29 vs visible manual reference 32 (error 3, 9.375%);
  assisted layer-only 23; guided hybrid unresolved. No measured hybrid precision
  or three-view exact-count accuracy exists. Existing references stay frozen.
- This GitHub checkpoint includes the actual source, tests, plan and reports,
  explicitly labelled unfinished, to avoid a handover referring to absent code.
  The APK remains a local ignored artifact, not a GitHub release upload.
  previous_context.md is newly created because no file with that name existed;
  existing context.md and previous_chat.md history is preserved.

Authentication references: https://developers.cloudflare.com/workers/wrangler/commands/general/
and https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/.

Publication verified: checkpoint bc0a0e67d947c2a06badc6db5b2e497b64e2fb1b
successfully pushed to origin/codex/hybrid-cell-counting. git ls-remote returned
the identical SHA and the working tree was clean after that push. All 28 source,
test, context and report files in the checkpoint are now on GitHub. Staged
whitespace and targeted credential-pattern checks passed. This is source
publication only; Cloudflare was not deployed and the APK was not uploaded as
a release asset. This follow-up documentation records the verified push outcome.


## 2026-09-15 — requested evidence and architecture publication

Appended the ground-truth discussion and linked source images, diagnostic overlays
and current/proposed architecture in docs/COUNTING_ARCHITECTURE.md and the case
README. Preserved user-reported 100 filled + 1 empty separately from inference
and the older 32-tray reference. Ground truth is for labels/scoring, never a
runtime correction factor. Optional markers aid pose/scale; a 3D display cannot
recover hidden occupancy by assumption.

This checkpoint includes the pending local stack-face guard/regression test,
reproducible layer diagnostic and rollback evidence. Earlier verification: 44
backend tests and targeted Ruff passed; the real layer diagnostic failed with
40/10/10/11/11 candidates. No new training, APK build or deployment is claimed.
Current recorded production version remains 621a5a9c-f486-455f-9a15-0965ca3a710f;
local APK remains 0.2.2+5 and incompatible with that baseline preflight.

Next: obtain original LEFT/RIGHT/STRAIGHT images/raw predictions; label per-tray
errors, fix localization/layer ambiguity, integrate occupancy and cross-view
identity, evaluate held-out scenes, then build/test a compatible APK. Publish
this checkpoint on codex/hybrid-cell-counting after evidence/whitespace checks.

Publication checks: all three supplied image SHA-256 hashes match reference.json;
case JSON parses and local architecture/report links resolve. Staged whitespace
and targeted credential-pattern checks passed. Remote branch was fetched and
matched local HEAD before this checkpoint commit. Prior 44-test result retained;
documentation/image append does not introduce new runtime changes.


## 2026-09-15 — local per-stack research checkpoint

User's pasted engineering task explicitly prohibits APK rebuild and replacing
production Worker 621a5a9c-f486-455f-9a15-0965ca3a710f. Keep that override active.
See reports/user-100-tray-case-20260915/RESEARCH_20260915.md for the full report.
New local stack_measurement candidate ranks signed-edge paired bands across
p/2,p,2p hypotheses; old serving layer algorithm is preserved pending validation.
The existing individual-tray-as-stack guard remains intact. No RF training,
model promotion, production deployment or Android build occurred.

Assisted real-image results: legacy 40/10/10/11/11 -> exploratory bands
19/19/20/19/19. Band MAE against reported physical per-column truth is 1.0;
physical and eligible totals remain null. Bands follow brightness/egg structure,
not yet validated physical tray rims. No +1/global multiplier or truth counts
enter inference. Exact physical101/eligible100 NOT reached.

Added geometry-only input, pending101-instance truth records with no invented
geometry, one-to-one bbox-IoU scoring, detection-based stack proposals, native
rectification and versioned measured-height adapter using existing calibration.
52 backend tests passed during development; final checks are recorded in the
report. Source overlays, signal plots, measurements, post-inference scoring and
failed attempts are archived. Manual ROIs are not automatic localization. Real
RF boxes, original triplet, reviewed labels, occupancy training examples and
physical calibration are missing; those measurements cannot be claimed.

Next: full-resolution top/bottom-complete captures/raw RF boxes and per-instance
rim/visibility review; evaluate automatic proposals, physical rim identity and
endpoint evidence, then independent held-out arrangements. Preserve old frozen
benchmarks. Continue only locally/candidate route; do not rebuild Android yet.

Final checks: 52 backend tests passed after all code fixes; targeted Ruff
passed. Candidate r3 CLI completed; native/upscaled control retained identical
19/19/20/19/19 band counts. Source/report plots visually inspected. Source
image hashes and prediction-to-evaluation SHA-256 verified. APK stays0.2.2+5;
no Android/Worker source changed. Publication targets codex/hybrid-cell-counting.

Publication verification also checks the staged measurement content against
the canonical-JSON SHA-256, avoiding Windows/Git line-ending differences.
All artifact/JSON/link and targeted credential-pattern checks passed.


## 2026-09-15 — individual tray photographs received

Archived14 attachments as6 byte-unique photographs under
reports/individual-trays-20260915/ with hashes and duplicate mapping. Visually
reviewed: four foreground loaded trays in images1/2, one central loaded tray
in4/5; image3 blurred; image6 mixed/nested/sparse-content stacks needs review.
Added10 selected foreground observation boxes as manual drafts, not10 unique
physical trays. Background annotations incomplete; no training-ready export.
No inference, retraining, deployment or APK rebuild. New scene totals unknown;
never transfer the earlier100-tray truth to these captures. Next: review full
instance/rim labels, confirm small-stack physical counts and egg-vs-shell
occupancy, run unchanged model and measure matched detection errors.
Verification: unique source hashes preserved; annotation boxes in image bounds;
all JSON parsed. This intake changes data/docs only; no runtime tests required.


## 2026-09-16 — live APK/backend compatibility fix

User reported reachable server but optional-marker FormatException before
upload and explicitly requested a fix. Confirmed live baseline health lacked
model_spatial_v1 required by APK0.2.2. Deployed compatibility repair version
ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 with existing model/settings/secrets retained.
Modern model_spatial_v1 scans accept no floor IDs and return spatial evidence;
old no-contract/no-ID requests retain the original baseline route. Explicit
cell-ID contract still validated. This supersedes the previous production
rollback state for this user-requested repair, not for experimental hybrid work.
Compile,12 Worker tests and dry-run passed; live health advertises required
contract. See reports/backend-compatibility-20260916/ for runtime evidence.
No retraining or APK rebuild. Exact hybrid remains unfinished; modern total
stays unresolved. Next: verify a fresh phone scan; continue research separately.


Live upload verification succeeded: HTTP200, model_spatial_v1, no cell IDs,
spatial detections/counts4/4/2, model processing7997ms, accepted:false and
inventory total:null. Used archived individual-photo images01/02/03 (third is
blurred); this is a compatibility smoke test, not exact-count evaluation or a
validated left/right/straight inventory capture. model-scan.json retains the
response. Initial curl TLS reset and default-httpx certificate failure were
resolved for this probe using Python ssl.create_default_context (Windows trust).
TLS verification stayed enabled. App preflight and result contract now match;
physical-device capture remains to be retried by the user.


## 2026-09-16 — new upload timeout and reported severe undercount

User reports2/2/25 on views each said to contain100 trays; screenshot separately
shows Dio45-second sendTimeout. Counts are user-reported, not independently
replayed. Compatibility repair did not solve model accuracy or upload reliability.
Source inspection: CameraController uses ResolutionPreset.max; ApiClient sends
original files with45-second send and receive timeouts. Large payload/network
conditions are plausible causes, not confirmed without phone/file evidence.
Band algorithm remains local assisted research and is NOT in the deployed Worker.

APK logs are not uploaded to backend. SQLite history stores result summaries,
not raw images/detection JSON/network traces. Worker observability is enabled,
but modelDiagnostics currently lacks a scan_complete console event; legacy/cell
routes emit counts. Thus historical per-view details may be unavailable even if
request events exist. Do not claim the2/2/25 request was found in logs.
ADB checked: no connected device. Requested USB debugging connection and scan
time/ID to capture upload timing, bytes, network errors and actual input photos.
Need compare returned raw boxes to exact uploaded images before changing model
thresholds or retraining. No additional APK build or deployment in this diagnosis.

## 2026-09-16 — USB device connected; live reproduction pending

ADB now reports authorized Redmi Note 9 Pro (curtana). Installed package
com.dharani.eggtray.egg_tray_counter is version 0.2.2, versionCode 5.
Opened MainActivity and started PID-filtered logcat capture into ignored
work/device-diagnostics/app-logcat-20260916.txt. Release package is not
 debuggable: run-as cannot read private cache/photos. No app data was cleared,
no APK installed, and no backend changes made during this connection check.
Requested user retry the failing three-photo scan while logging. Next: inspect
that attempt for upload/network errors; obtain exact input images and response
before attributing reported 2/2/25 counts to model or image processing. Live logs
may not include request details because the current APK has no such telemetry.

## 2026-09-16 — physical-device retry completed

After user reported done, directly inspected the connected phone result screen
(saved locally in ignored work/device-diagnostics/scan-screen.png). APK displays
Left 96 / Right 89 / Straight 98, model projec-mutta/2, processing 9127 ms,
COUNT NOT VERIFIED. This attempt completed upload/inference; the earlier
45-second send timeout did not reproduce. This does not establish a permanent
network fix or explain the earlier user-reported 2/2/25 result.

Against the user-stated 100 egg-containing trays per view, count differences
are -4/-11/-2, conditional on this retry depicting that same inventory. These
are count differences, not detection precision/recall: original inputs and
matched instance annotations are still unavailable. No band inference ran.
PID-filtered logcat captured camera lifecycle messages but no Flutter request,
response or timeout diagnostics. Camera frame warnings occurred during closure;
not evidence that they caused a failed scan. No retraining, code change, APK
installation or deployment occurred in this retry check.
Next: obtain the exact retry photos and corresponding detection boxes for
instance-level error analysis; keep the 100-tray truth outside inference.


## 2026-09-16 — MUTAA local 3D/band candidate checkpoint

User supplied a detailed research prompt and two sketches: complementary X/Y
views, per-stack Z evidence, shared corner counted once, egg-containing trays
only, explicit SOP constraints. No deployment, APK rebuild or immediate training
in this task. Starting branch codex/hybrid-cell-counting, HEAD bd8abb4b6ecc8c0fcfaff5e9661b5688e212d558.

Completed: recursively archived all 35 MUTAA originals with SHA-256, dimensions,
top-level EXIF and contact sheet (35 unique); preserved prompt/sketches. Fresh
unchanged projec-mutta/2 inference obtained for all 35 through current gateway,
confidence35/overlap50/class egg_tray. Saved gateway JSON, request mappings,
EXIF-oriented boxes, automatic stack polygons, beam hypotheses and 35 overlays.
Gateway does not expose full raw upstream RF JSON; this remains a limitation.
First pass hit HTTP503 Worker exceeded resource limits on batches05-12; later
retries and one-large-image/two-small-companion batches recovered all inputs.
Original images unchanged. This is not proof of the earlier phone timeout cause.

Implemented local POST /candidate/count-3d for images plus hash-bound saved RF
boxes (disabled for APP_ENV=production). Reuses existing localization and band
analysis, preserves RF/band/height disagreement, unknown occupancy and SOP
violations. SIFT/RANSAC proposes correspondences but never certifies identity.
Explicit-coordinate grid accounting deduplicates shared physical cells, handles
known gaps/unequal heights and blocks conflicts/unknown occupancy. Synthetic
fixtures validate 200/180 totals, shared-anchor dedup and harmonic abstention.

Real findings: image07 RF56, band candidates16/20/22/19/19 from five incomplete
proposals; image10 RF12 and only one partial ROI despite multiple visible stacks.
Image17 broken egg/shell falsely classified egg_tray; image24 empty tray also
uses generic egg_tray label. No accepted cross-view anchor for tentative07/10/11.
Real X/Y grid, physical totals and eligible totals remain unresolved. No audited
real-world98% accuracy claim. No MUTAA truth imported from the old100-tray scene.

Verification: 62 Python backend tests passed; targeted Ruff passed; TypeScript
compiled and12 Worker tests passed (prior compatibility changes included in
publication). Original/source hashes checked,35 results present. Existing AnyIO
deprecation and Node module-type warnings only. All current context docs updated.

Artifacts: reports/mutaa-20260916/README.md, RESULTS.md, scene-groups.json,
per-image-results.json, cross-view-prototype.json, raw/, analysis/, originals/,
design/. Architecture/SOP: docs/3D_BEAM_COUNTING_ARCHITECTURE.md.
APK stays0.2.2+5; latest recorded live Worker stays
ab67cd59-3f4e-4628-a0fa-d085f56a3fe8. No new deployment/retraining/APK.

Blockers/next: user physical totals and scene identity still pending. Review
stack-face/rim/corner/occupancy annotations; test a separate localized-crop V2
ablation and audited labels before training. Complete calibrated correspondence
and per-layer occupancy before claiming an image-to-3D exact count. Instrument
large multipart/base64 resource use separately; do not deploy as part of research.
Commit/push requested to codex/hybrid-cell-counting; verify remote ref after push.

## 2026-09-16 — verified publication and continuation handover

The MUTAA research checkpoint was committed and pushed as
`d5ddcc8d9fa8ed06052e14503ec1ce2a3a07b9ba` on
`origin/codex/hybrid-cell-counting`. A fresh `git ls-remote` check matched local
HEAD before this documentation update; the working tree was clean. This
supersedes the preceding entry's pending commit/push instruction.

Completed evidence: 35 unique originals preserved with hashes, fresh unchanged
V2 results for all 35, automatic stack/band overlays, tentative scene grouping,
local candidate endpoint and synthetic physical-grid accounting. Recorded checks
from that implementation session: 62 Python tests, 12 Worker tests, TypeScript
compile and targeted Ruff passed. These tests were not rerun for this docs-only
update; they do not establish real-image counting accuracy.

Exact counting remains unfinished. No reliable shared anchor was established
for the tested cross-view group; whole-stack coverage, physical rim endpoints,
hidden depth and per-layer egg occupancy remain unresolved. The broken-shell
false positive and empty-tray detection demonstrate why generic egg_tray boxes
cannot directly certify egg-containing inventory. The phone's 98/100 view is a
single count comparison, not an audited 98% real-world accuracy rate.

Continue from reports/mutaa-20260916/README.md and
 docs/3D_BEAM_COUNTING_ARCHITECTURE.md:
1. Obtain physical per-stack filled/empty counts and confirm unchanged scene
   grouping; do not transfer the old 100-tray truth to MUTAA.
2. Review full stack faces, rim endpoints, shared corners and occupancy labels.
3. Run a separately recorded localized-crop V2 comparison before deciding on
   retraining; keep expected totals outside inference.
4. Validate physical correspondence and occupancy before populating a trusted
   X/Y/Z inventory. Preserve unresolved states instead of filling hidden stock.
5. Investigate multipart/base64 resource use separately. Successful retries do
   not establish a permanent fix for the earlier phone upload timeout.

No new deployment, retraining or APK build. APK remains 0.2.2+5; latest recorded
Worker version remains ab67cd59-3f4e-4628-a0fa-d085f56a3fe8. The user's current
research scope prohibits replacing production or rebuilding Android yet.

## 2026-09-17 — regional quality and physical-grid candidate milestone

Continued from d5ddcc8 on codex/hybrid-cell-counting. Added source/view/layer
provenance to the existing X/Y/Z accounting core, stronger provisional mutual
SIFT + RANSAC + face-coverage/projected-overlap filtering, regional top/middle/
bottom diagnostics, explicit SOP/visibility declarations and structured targeted
recapture recommendations. Local candidate contract revision candidate-20260917
uses geometry/cells and lowercase statuses, rejects expected truth inputs and
string boolean flags, and cannot claim verified inventory. This is a local
research contract change, not a deployed mobile contract migration.

Verification: 65 backend tests passed; after final SOP/production-guard additions,
all 13 spatial candidate tests passed again. All 13 Worker tests, TypeScript,
targeted Ruff and Wrangler deploy --dry-run passed. Synthetic accounting gives
200/180/195, counts shared front/right and rear left/right stacks once, separates
201 physical from 200 eligible with an empty tray, and withholds totals for
unknown occupancy or unobserved rear positions. Harmonic and regional darkness
checks pass. These are synthetic correctness results, not camera accuracy.

Replayed 35 archived MUTAA originals with matching SHA-256 hashes: regional
analysis on 106 historical proposed faces; one bottom-dark warning (image05),
one possible top crop and eight possible base crops. Missing/incomplete ROIs
remain unassessed; unflagged regions are not certified. Thresholds are pilot
heuristics. Zero new RF calls, no training. Tentative 07/10/11 group still has
zero supported correspondence proposals; same-scene grouping and physical
truth remain unknown. See reports/candidate-20260917/README.md and JSON artifacts.

Worker source now uses native Buffer base64 (compile-time Node types added),
sequential hashing and existing sequential inference, with safe byte-size/stage
logs. Local 12,597,763-byte encoding benchmark: identical output in three runs;
median old 2295 ms versus native 10.93 ms. This does not measure Worker peak RAM
or prove a production resource-limit fix; multipart remains buffered. npm install
reported three high advisories in the dependency tree; no blanket dependency
upgrade was attempted in this counting milestone.

APK stays 0.2.2+5. No deployment, APK rebuild or model change. Latest recorded
Worker version stays ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 (historical, not refreshed).
OpenCV stays local. No hosted Python service or WebSocket integration was added.

Blockers and exact next steps:
1. Confirm one unchanged LEFT/STRAIGHT/RIGHT triplet and independent per-X/Y
   physical/filled/empty counts, including gaps. User confirmation remains pending.
2. Freeze truth separately; annotate complete faces/endpoints, shared corners and
   occupancy. Do not inherit old100-tray truth or correct predictions toward it.
3. Calibrate quality and identity gates on labeled examples; run crop-RF ablation
   before deciding on retraining. Validate per-layer occupancy and unseen coverage.
4. Only then integrate hosted Python with Cloudflare, run resource/load validation,
   and implement guided Android capture against the stabilized production contract.
5. Publish this checkpoint and verify the remote branch matches local HEAD.

## 2026-09-18 — production scope accepted; assigned-view demo executed

User's new production-architecture prompt supersedes the prior research-only
restriction. Requested next work: SceneSolver, deterministic SceneCertifier,
containerized Python, Cloudflare object/session integration and guided Android;
production promotion/APK still require the explicit live/device/truth gates.
User confirms no Python container host is available yet.

Immediate user-directed demonstration completed using supplied RIGHT, LEFT,
STRAIGHT files, despite user confirming they are separate arrangements/count
references. Exact originals/hashes and a pre-run tentative visual reference saved
in reports/production-20260918. Hashes match MUTAA image01/image02/image04; this
is not an unseen blind benchmark. No physical truth supplied.

Fresh unchanged projec-mutta/2 gateway request passed: RIGHT15 LEFT8 STRAIGHT34.
Local FastAPI candidate request passed: faces1/1/3; band candidates RIGHT14,
LEFT10, STRAIGHT8/11/16. Gateway15.17s plus local10.24s. No supported shared-stack
correspondence. X/Y, physical/eligible totals unresolved; verified=false and
recapture_required. No manual reference or expected totals fed into inference.
This is an attempted reconstruction, not a successfully reconstructed 3D scene.
The always-abstaining candidate cannot validate a production certifier. It also
did not establish an automatic unrelated-scene classification.

Saved gateway/candidate inputs and outputs, reconstruction.json, comparison.json,
demo-summary.json and report. Reproducible runner scripts/run_triplet_demo.py;
Ruff passed and live/local requests returned200 with result invariants checked.
No production logic changed; full automated suites were not rerun for this
report/runner-only change. No deployment, training or APK build. APK0.2.2+5.

Next: implement requested production solver/certifier/service/mobile work; obtain
an unchanged triplet and independent per-cell truth for valid 3D regression.
Prepare hosting only when a target is available. Do not replace unobservable
geometry/occupancy with a known-total correction or forced verification.

## 2026-09-18 — device enumeration and publication checkpoint

The user reported that the Android phone was connected and requested analysis.
Restarted the repository Android Debug Bridge daemon and ran `adb devices -l`;
the result contained no device or emulator serial. Therefore no APK log,
camera frame, upload timing, or live scan was analyzed in this checkpoint. A
connected USB cable alone is not evidence that ADB authorization or the device
transport is ready.

The two live-capture subtasks were interrupted before producing a tracked patch.
No live lighting/orientation code or preview endpoint was added or deployed
here. The latest implemented source remains the diagnostic candidate recorded
above; the 0.2.2+5 APK and Worker version
`ab67cd59-3f4e-4628-a0fa-d085f56a3fe8` remain historical artifacts, not a new
release. This documentation checkpoint does not claim retraining, exact 3D
reconstruction, or production readiness.

Future execution reference: `docs/COUNTING_EXECUTION_PLAN.md`, section “Live
capture pilot and device gate”. Reconnect the phone until `adb devices` shows
an authorized serial, reproduce one scan while collecting app-side logs, then
compare the exact uploaded files with the Worker response. Only after that
evidence should local lighting/sharpness/orientation gates and the small preview
contract be integrated, tested and built as a clearly labelled staging APK.
Keep the existing no-ID baseline route compatible and require an unchanged
three-view scene plus independently recorded per-stack occupancy truth before
enabling any accepted inventory total.

## 2026-09-18 — tools and MCP inventory

Added tools.md from the configured C:\Users\DELL\Downloads\config.toml.
It lists the configured MCP servers and enabled plugins, their local/runtime
prerequisites, whether account or device authentication is required, and the
smallest tool set needed for this repository. Credential values were not copied.
The configured APIFY_TOKEN is explicitly redacted in the document; no runtime
code, model, Worker deployment or APK changed.

Verification: reviewed the config sections for MCP servers/plugins and ran
git diff --check. This is documentation only; service authentication and
device availability remain runtime facts that require separate health/ADB
checks.

## 2026-09-18 — live capture constraint gate (local, deterministic)

Implemented the local capture gate the execution plan calls for, as three
layers with one responsibility each: `frame_evidence.dart` (measurement:
luma plane, guide geometry, 13 metrics, preview-to-still guide mapping),
`frame_preflight.dart` (judgement: pass/advisory/blocking checks, thresholds,
audit record), `live_frame_preflight.dart` (live loop: camera YUV plane plus
accelerometer, JPEG still decoding, raw-axis to device-pose conversion). The
capture pane shows the measured value, the limit and the repair action on the
viewfinder, turns the guide outline amber/red/green, locks the capture button
while any check blocks, stores a level reference in SettingsStore, re-runs every
check on the still that was actually written, and attaches the report to the
upload as `<view>_constraint_evidence` (additive field; the deployed Worker
ignores it and stays compatible). No count is produced, accepted or changed by
this code.

Verification: `flutter analyze` clean; `flutter test` 54 passing (16 before),
including synthetic-frame measurement, every blocking path, pose conversion,
JPEG decoding, the guide mapping, and a real-photo harness. The harness found a
real defect (guide reaching the image bottom read one row past the plane) which
is fixed and covered. Harness result over the ten labelled evaluation frames:
0/10 accepted under the app guide, 2/10 under a full-frame guide, i.e. the
frames behind the old 2/10-exact, MAE 22.9 baseline are evidence this gate
refuses on framing alone.

Staging APK: version 0.3.0+6, SHA-256
c8f2787146cc28568609b2a1d2a05a8d9a7a693627ca7f58e99090484b8e74e4, debug-key
signed as before, installed with `adb install -r` on the connected Redmi Note 9
Pro (Success, app launches, no crash in logcat). The live banner itself is not
yet verified on hardware: the phone is locked with a pattern, so no UI state can
be read or driven over ADB. Report: `reports/live-constraints-20260918.md`.

Authentication facts checked this session: `gh auth status` authenticated as
RAHUL-DevelopeRR; `wrangler whoami` not authenticated, so no Worker deploy is
possible from here; the deployed Worker answers `/health` 200 and `/ready` 200
with `provider: roboflow_serverless`, `model_reference: projec-mutta/2`, so the
Roboflow key is configured server-side. MCP OAuth cannot be completed from a
shell and nothing in this work depended on it.

## 2026-09-22 — live capture review and BlueStacks verification

Completed the existing capture pilot with orientation-aware Y-plane sampling,
independent sensor/frame timing, stale-frame rejection, still-image verification,
per-capture evidence replacement, and serialized camera lifecycle cleanup.
Image-edge framing checks are advisory: background edges cannot establish that
all trays are visible. Phone tilt is measured; left/right viewpoint is guidance,
not calibrated camera pose or 3D reconstruction.

Verification: full Flutter suite 59 passed; flutter analyze reported no issues.
The subsequent BlueStacks layout fix also passed both lifecycle widget tests.
The evaluation-photo replay passes quality checks on 10/10 frames; historical
count MAE remains 22.9. This supersedes the earlier interpretation that rejecting
those photos by edge heuristics demonstrated a useful accuracy improvement.
Fresh gateway smoke returned LEFT 8, RIGHT 15, STRAIGHT 34, accepted=false,
total_trays=null. The unrelated demo scenes cannot validate inventory accuracy.
No Worker deployment, model retraining or Python service deployment occurred.

Built 0.3.1+7 and installed on the phone before the user disconnected it.
Phone remained locked, so its live capture UI was not verified. At user request,
enabled BlueStacks ADB and started Pie64 (127.0.0.1:5555). APK installation and
launch succeeded; home showed SERVER REACHABLE. Live preview reported tilt 90
degrees and locked capture. Home/reopen succeeded. Emulator screenshot exposed
an overlapping guidance panel; moved it outside the preview to a full-width
scroll panel. Final artifact and screenshot verification: see
reports/live-capture-20260922/README.md.

Next: validate warnings using a real phone and controlled dim/bright/blur/tilt
conditions; collect unchanged LEFT/RIGHT/STRAIGHT scenes with independent filled
and empty counts per stack. Calibrate quality thresholds using those captures.
Only then evaluate count error and false acceptance. Stack visibility, true
viewpoint calibration and hidden occupancy remain unimplemented/unverified;
no exact-count or 100-percent accuracy claim is supported.
