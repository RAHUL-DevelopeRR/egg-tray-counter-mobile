# Orientation evidence, 2026-10-09

Question: does a photo taken with the phone held sideways count exactly like an upright one?

## How the measurement was made

`scripts/synth_phone_stills.py` builds the file a Redmi Note 9 Pro writes for a scene in each hand
position: 1920x1080 sensor pixels, EXIF Orientation 6 (the camera library tags every still for the
portrait display), the scene turned the way the sensor sees it when the phone is upright (r0),
turned counter-clockwise (r90) or clockwise (r270). The scenes are labelled photos 01 (99 trays,
stacks 20/20/20/20/19), 02 (80, 20x4), 19 (100, 20x5), 20 (60, 20x3) and 46 (one stack of 20).
`scripts/zz_e2e_orientation_tmp_test.dart` runs the app's real `prepareCapturedStill` on them
(copied into mobile/test only for the run; not part of the suite). `scripts/count_on_staging.py`
sends the uploads to the staging Worker (f5776f0d) next to the originals and old-app controls.

## Results (per-stack walk counts against the reference)

| file | what it shows |
|---|---|
| `app-uploads-vs-originals.json` | app uploads WITH the 20:9 screen trim (0.4.7): 19 exact both sides; 01 r90 one stack 19; 02 r90 one stack 19; 02 r270 two stacks 19. Old-app sideways files (raw, wrong tag) are refused with the sideways reason. |
| `trim-vs-no-trim.json` | app uploads WITHOUT the trim (0.4.8): 01 r90, 02 r90, 02 r270, 19 r90 all exact. Trim alone, no app processing: 02 misses the same two stacks, so the trim was the cause. |
| `upright-scenes-control.json` | the same padded scenes upright, no app: all exact. |
| `server-orientation-variants.csv` | Worker-side measurement: EXIF-tagged sideways pixels count like the upright file; untagged sideways pixels collapse (5-12 boxes, box aspect 1.1-2.6) and the old gate accepted 2 of 6; landscape 16:9 frames of 1-3-stack faces were rejected by the width rule. |
| `raw-vs-upright-contact-sheet.jpg` | left: the raw still as written for r270 (scene upside down, tag 6); middle: the app's upload; right: an upright upload. |

`scripts/sideways_rule.py` evaluates the sideways guard (median box width/height below 2.75) on the
39 tagged photos (lowest usable 3.09, img-9) and on every variant (highest sideways 2.64): it refuses
all 6 sideways frames and nothing else. `scripts/gate_rules.py` shows the full-height waiver (0.8)
changes no verdict on the 39 tagged photos and accepts the 7 landscape variants.

Not covered: real sideways captures from the phone (the phone cannot be turned from the laptop).
