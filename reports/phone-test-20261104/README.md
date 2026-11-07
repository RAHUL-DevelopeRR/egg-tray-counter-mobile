# Phone test: laptop photos scanned on the Redmi (4 Nov 2026)

**Request:** pick a three-photo set from the MUTAA repository, move it to the phone, scan it in the APK and show
the 3D result.

**Setup (measured).**
- Redmi Note 9 Pro (`f76d5e20`), app 0.6.0+29 (`egg-tray-counter-0.6.0-demo-staging.apk`), backend base URL staging.
- Staging Worker 0.5.0 (`52a1d5e8`), detector `projec-mutta/2`. Worker 0.6.0 is not deployed.
- Photos pushed with `adb push` to `/sdcard/Pictures/EggTrayTest/` (left on the phone for repeat tests) and chosen in
  the system photo picker's EggTrayTest album. "Gallery scans (testing only)" was switched on for the test and off
  again afterwards.
- "These photos show the same stacks" ticked; the block declaration skipped (no first-hand knowledge of the block).
- 2 scans, 6 detector calls.

## Results

| Set | Photos (STRAIGHT / LEFT / RIGHT) | Truth | Phone result | Screens |
|---|---|---|---|---|
| L-100 (MUTAA block set) | img-19 / img-21 / img-24 (`datasets/field-2026-10/labelled-20261007/originals`) | 100: 5 stacks × 20, handwritten label and two-counter manual count (tier V) | **RETAKE NEEDED, no total, no 3D model.** LEFT and RIGHT "show the same 5 stacks with the same heights as STRAIGHT, so it looks like the front face again". Per-photo detections (unmatched): Left 103, Right 100, Straight 101. Processing 9759 ms. | `01-L100-retake.png`, `02-L100-per-photo.png` |
| 99-tray row (MUTAA labelled photos) | img-01 / warehouse image-4 (`reports/warehouse-20260923/input`) / img-32 | 99: handwritten label (tier U) | **BLOCK ESTIMATE 99**, 3D grid model 5 wide × 1 deep, stacks 20, 20, 20, 20, 19. Counted 99 + Assumed 0. Seen by one photo only 99, by two photos 0. Note: corner (0,0) STRAIGHT 20 vs LEFT 19, 20 chosen. Processing 3588 ms. | `03-row99-3d-estimate.png`, `04-row99-details.png` |

`05-home-history.png`: both scans saved in the phone's history ("About 99 trays" ESTIMATE, "Rescan required" RETAKE).

## What this shows and does not show

- The phone path works end to end: picker, upload, server answer, 3D grid drawing and history, on the real device.
- Both answers repeat what the same server gave for the same photos before (L-100: `reports/mutaa-validation-0.5.0-20261101/raw/set-L-100.json`;
  99 row: staging 47cb2378, `reports/eval-20261015`). They are not new accuracy evidence.
- The 99 trio is a worked example, not a genuine block scan: img-01 was used while tuning the counter, and LEFT and
  RIGHT are the same free end photographed at different times (the true left end stands against the wall).
- No MUTAA block set gives a total from gallery photos on Worker 0.5.0: a deep block needs side photos the server can
  trust as sides (camera session), and L-100's side photos are front views. A 3D model with assumed (see-through)
  stacks needs a camera scan of a real deep block (under Worker 0.6.0, also the declared block size). Not tested here.
