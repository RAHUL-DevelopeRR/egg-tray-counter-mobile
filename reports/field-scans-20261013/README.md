# Field scans of 13 October 2026, phone state and backend on 14 October

Analysis session 2026-10-14 (Claude Code). Read-only on the phone and the backend; no
deployment, no APK build, no phone setting changed.

## Phone (Redmi Note 9 Pro, serial f76d5e20, over USB debugging)

- Installed: versionName 0.4.9, versionCode 20 (installed 2026-10-12 16:22). 0.4.10 is not installed.
- The phone rebooted at 18:53 on 13 Oct (uptime 14 h at 09:12 on 14 Oct). The log buffer starts there,
  and the egg app has not run since, so **no app log exists for the 13 Oct scans**. The only
  app-tagged lines are a MIUI monitor (`test##>>`) and this session's own adb commands.
- Camera roll: 4 photos at 13:44 and 3 at 13:52 on 13 Oct, consistent with the gallery scans below
  (uploads are resized to 1600 px, so the archive files are not byte-identical to the camera roll).
- Network today (Jio LTE): ping to the staging Worker host over **IPv6 50% loss, 251-278 ms;
  over IPv4 0% loss, 78-98 ms**. On 12 Oct IPv6 lost 40-66%. The lossy leg is IPv6 to the
  `*.workers.dev` addresses; IPv4 from the same phone is clean.
- Laptop: 15/15 `/health` succeeded in one burst, but two of six scan uploads in this session were
  reset during the TLS handshake (WinError 10054) and succeeded on retry. The fault from
  reports/network-20261012 is still present.

## Backend (14 Oct)

| piece | state |
|---|---|
| staging Worker `egg-tray-counter-api-staging` | version f5776f0d (deployed 2026-10-09 10:28 UTC), `/health` 200, `/ready` projec-mutta/2, block_model_v1 |
| production Worker `egg-tray-counter-api` | version 4c1480e6 (deployed 2026-09-23), `/health` 200, **no block model**, no reconstruct_v1 |
| R2 `egg-tray-scan-archive` | 311 objects, 102 scans; manual counts: only WH-99 and MECH-DONE (9 Oct) |
| AWS Lambda `egg-tray-vision-pilot` (ap-south-1) | `/health` 200 after a 4.9 s cold start, `diagnostic_only`, `inventory_verification_ready: false`; RIM_VERIFY is off, so counting does not call it. AWS session token expired; metrics not read. |

## The 13 Oct scans, replayed on staging f5776f0d today

Seven scans arrived 12:53-13:58 IST. Three (ffa2cafa, ecf634f0, 17d51cb3) carry exactly the photo hashes
of the 99-block scan 6fe33b1d: repeat tests, not new blocks. The four new ones (no manual count was
recorded for any of them, so **no accuracy can be scored**):

| scan | what the photos are | block | total | why |
|---|---|---|---|---|
| f81c04d7 | three different WhatsApp label photos (handwritten "40", "81"; straight is a letterboxed screenshot), not one block | 2 x 3 | withheld | LEFT/RIGHT depth disagree; corner heights 20 vs 4 |
| 30aca6a1 | a block shot from far back and from a corner, camera above the stacks | 4 x 3 | withheld | gate: all three faces refused (too far away / too narrow); LEFT span 16 vs walk 27 |
| ef823816 | a 5 x 4 block standing in a room corner (walls on two sides), with a lower step on one side | 5 x 4 | withheld | gate refused STRAIGHT and LEFT (too far away); 8 stacks flagged; 144 of 233 trays would be computed |
| 9b4c783e | close square-on faces, about 15 layers, a separate set-back stack visible at the right | 4 x 3 | **165** (105 observed + 60 computed) | all faces accepted, no conflicts; one missing corner cell; hazy back-lit RIGHT face |

Contact sheet: `contact-sheet.jpg`. Full responses: `replay/<scan>.json`.

Reading: the server gate did its job: it refused 6 of the 12 faces, and every refused face really was too
small or too narrow. The one scan that passed is plausible by eye (about 15 layers per stack) but is
unverified. The warehouse constraints visible here are blocks against walls and in corners, too little
room to step back, neighbouring stacks inside the frame, open-sided sheds with strong back-light, and
interior stacks that never appear on any face.

## Hand count of the photos versus the app's 3D block (added 2026-10-14)

Counted by eye on 2.4-4x crops of the archived uploads, one egg row at a time. These are **visual
counts from photos, not a physical recount**. Hidden cells are assumed. Image: `app-vs-hand-3d.png`.

Tray facts seen in every block: trays are **cross-stacked**, with alternate layers turned 90 degrees.
So the front rows alternate 5 and 6 eggs, and the gaps between stacks show only on the 5-egg rows.
Every row is one tray. Most full stacks carry an **empty cover tray** on top.

| scan | hand reading | app (staging f5776f0d) | difference |
|---|---|---|---|
| ef823816 (5 x 4, room corner) | front 20/20/20/20/13 (short front-right corner); right side 13/20/20/20; left and back faces against walls; top surface visible and flat. Seen 153 + 12 hidden x 20 = **393 filled** + 19 empty covers | front 10/rescan/18/10/12; total withheld; would be 89 + 144 = 233 | **-160 (-41%)**. Far, cross-stacked faces: the detector boxes mostly the 5-egg rows (median box 28 px, walk pitch 43 px, true pitch about 24 px), so layers read about half. LEFT and RIGHT are the **same right-side face** at two distances; the app placed one of them as the left face (27/22/16 there are invented). |
| 9b4c783e (4 x 3, close) | front 15/15/15, front-right cell empty; left side 15/15/15; set-back column 14 and 15. Seen 104 + 4 hidden x 15 = **164 filled** | 165 (105 + 60) | +1. Column (0,2) = 16 includes its empty cover tray. Observed stacks: 6/7 exact, 7/7 within 1. |
| 30aca6a1 | STRAIGHT is the same block as 9b4c783e from far away with the ultra-wide lens (15/15/15 + set-back 14). LEFT shows a stepped face, RIGHT a high corner view, not tied to that block | front 16/15/15; (0,1) = 27; withheld | Front within 1. The side views are other faces, so the block is meaningless; withholding was right. |
| f81c04d7 | LEFT = dataset img-50 (label 40, two stacks), RIGHT = img-41 (label 81); STRAIGHT a screenshot | LEFT 20 + 19 | img-50 off by one; mixed photos, so withholding was right. |

Confirmed on the current code (backend `block_model.py` / `layer_span.py`) the plan's B01
(opposite sides: 42, no conflict, fully observed), B02 (corner 20 vs 19 accepted) and B03
(gap bridged to 101). `/v1/manual-counts` answered this session without any credential (B12).

## Tooling note

`scripts/replay_field_scans.py` leaves an empty `manual-count.json` when a scan has no manual count
(wrangler creates the file before failing). A rerun then crashes on `json.load`. This session used a
scratch runner with retries instead. Fix: delete zero-byte targets in `r2_get` and retry the POST.
