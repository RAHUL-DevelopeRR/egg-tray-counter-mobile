# Phone end-to-end run — 9 October 2026 (Redmi Note 9 Pro, Android 12)

APK 0.4.0+11 (photo picker build, SHA-256 0c48ffeada0692a3…), staging Worker
versions 4ffa06e0 (manual-count route) then fa3a0a49 (latest.json), server
URL set in the app's Settings to the staging Worker.

Phone findings (not app bugs): the system Files picker (DocumentsUI) never
lists files on this phone for any app. Reverting its update to the factory
version and turning on the paused Work profile (Android Device Policy) did not
change that. The app now uses the Android Photo Picker (`image_picker` with
`useAndroidPhotoPicker`), which lists photos by date and works (01).

Run 1 — mechanics trio (three different blocks used as faces; not a real
block): picked from the Downloads album, uploaded, result in ~5 s (03): block
5 × 4 drawn, observed 180 + computed 180, total withheld — stacks (2,0) and
(0,3) flagged RESCAN because raw box count and span count disagreed by more
than one on the app's re-encoded JPEGs (the same files sent raw from the
laptop gave 400 with no flags: see ../scan-img19-30-02.json). Manual count
entered (block MECH-TEST, one stack edited, one marked unreachable) and sent:
"Sent to server: filled 399, empty 0".

Run 2 — the real 99-tray block (front img-01) with its 19-layer side photo as
RIGHT and the other 19-layer side photo as LEFT (no genuine left photo exists):
block 5 × 1 drawn, 101 observed (21/20/20/21/19), total withheld: "corner
height differs between STRAIGHT and LEFT (straight 21, left 19)" (04). Manual
count entered with the verified 20/20/20/20/19 (05, 06): "Sent to server:
filled 99, empty 0". Server object fetched back with wrangler:
`manual-count-WH-99.json` (scan d6d087ea-…), containing both the app layers
and the human count per stack.

What this proves: picker → upload → block model → 3D render → manual count →
server storage works on a real phone. What it does not prove: counting
accuracy on real blocks (no same-block STRAIGHT/LEFT/RIGHT set exists on the
laptop); that is today's field test.

## 0.4.1+12 — closing the loop (09:36)

After a successful send the form shows **DONE — NEXT BLOCK** (07); tapping it
returns to a fresh upload pane with empty slots (08), so the operator goes
block to block without hunting for Back. The send button becomes "SEND AGAIN
(CORRECTION)". Verified on the phone with a third scan (block MECH-DONE).
APK SHA-256 b6487aea0052bfa7…; staging Worker d70d6495 adds
GET /v1/scans/:id/archive (key names only) used by scripts/score_field_blocks.py.

## 0.4.5+16 — camera follows the phone (13:23)

User feedback on 0.4.4: the rotate button was wrong; the camera must not be
turned by a button, only the way the phone is held decides whether the
picture is portrait or landscape, and the picture must fill the screen.
0.4.5 removes the button. The capture screen has no app bar; the camera
frame is scaled to cover the whole screen (12, portrait, lens covered so the
frame is dark) with the close control, torch, view chips and the one-line
instruction laid over the top and the verdict strip plus CAPTURE button over
the bottom. Turning the phone past 60 degrees of roll switches the screen to
that landscape side (back under 30 degrees returns to portrait), using the
accelerometer, so it works with the system rotation lock on; in landscape
the CAPTURE button sits on the right and the verdict strip bottom-left. The
live checks are told the chosen rotation (roll measured relative to the
rotated screen, frames rotated by sensorOrientation minus display rotation),
so a phone held level sideways no longer reads as tilted. Landscape could
not be exercised from the desk (the phone cannot be rotated remotely); a
widget test at 1000x480 checks the frame covers the screen and the button
position, and the landscape side (roll +90 = landscapeLeft) follows the
Android accelerometer convention; if the first field try shows landscape
upside down, the sign in `_followOrientation` is the one-line fix. APK
SHA-256 34a0349a3e4b11d4…, installed and verified versionName 0.4.5.
