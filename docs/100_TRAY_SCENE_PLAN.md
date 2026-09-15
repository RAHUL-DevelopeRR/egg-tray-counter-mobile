# Plan for the user-reported 100-filled-tray scene

Date: 2026-09-15. Planning only; leave the rolled-back production baseline unchanged.

## Evidence and target

User supplied two photographs of the same-looking result screen and one annotated
scene photo. Screens show LEFT 84, RIGHT 90, STRAIGHT 87, model projec-mutta/2,
13,352 ms, count not verified. Treat as one reported scan, not two experiments.
Interpret the user's truth as 100 trays containing eggs plus one additional empty
tray: 101 physical trays, target eligible count 100. This is user-reported truth,
not an independent visual/physical recount by the assistant. It is a new scene;
do not overwrite the earlier 32-tray img04 reference.

Against target 100, absolute count errors are 16/10/13, respectively 16%/10%/13%.
Average per-view absolute error is 13 trays. Mean/median count 87 and max count 90
are all wrong; summing overlapping views is invalid. These are count errors, not
instance precision/recall. A false positive could cancel a miss. Screenshot OK
labels do not prove complete coverage, occupancy or accurate counting.

## Ordered implementation

1. Preserve the original three capture files (not screen photos or blue-marked
   derivatives), raw predictions/settings, scan ID and per-stack physical truth.
   Mark the location of the extra empty tray. Label visible tray instances and
   ambiguous/occluded regions. Do not infer hidden labels from the desired total.
2. Diagnose V2 overlays: missed trays, duplicate boxes, wrong class, merged layers,
   small resized objects, blur and occlusion. Sweep confidence/overlap settings
   on development data only; test full-resolution stack crops with crop-offset
   mapping and duplicate suppression. Do not apply 100/90 correction or loosen
   agreement thresholds to fabricate acceptance.
3. Build a per-stack evidence representation. Localize stack faces/corners and
   bases/tops; rectify each vertical face; detect tray rims and egg occupancy.
   Estimate layer spacing with uncertainty. Empty nested trays require a separate
   profile; a hidden empty tray cannot be excluded from images by assumption.
4. Collect a pilot of roughly 50-100 physically different arrangements with three
   angles each, including unequal heights, empty trays at different positions,
   partial filling, back rows, different trays, lighting and occlusion. This is a
   starting collection target, not enough by definition to guarantee accuracy.
   Split by arrangement/capture session so near-identical angles never leak
   across train/validation/test. Preserve an untouched final evaluation set.
5. Fine-tune a challenger with corrected dense-tray labels. Supervise tray presence
   separately from filled/empty/unknown occupancy; use face/keypoint annotations
   for geometric localization as needed. Compare V2, higher-resolution/crop V2,
   and fine-tuned detector before combining them with geometry. Do not promote a
   new model solely on mAP. Keep architecture changes secondary to failure audit.
6. Represent inventory as row/column/layer cells. Each occupied footprint has a
   variable layer count, and each layer has filled/empty/unknown state plus source
   observations. The total is the sum of unique egg-containing layers, not rows
   times columns times an assumed common height. A 3D drawing displays this
   evidence; it does not supply missing observations.
7. For marker-assisted scenes, survey footprint dimensions and add unique printed
   fiducials at visible positions plus a measured vertical reference. Calibrate
   camera intrinsics/lens distortion. Estimate camera pose from known marker
   geometry; project stack and layer candidates back into every original view.
   A floor homography alone cannot measure vertical stack height. Painted boxes
   localize bases; they neither count layers nor reveal empty trays. Read IDs
   automatically; no mandatory manual text entry.
8. For marker-free scenes, estimate relative poses and associate stack faces using
   overlap, landmarks and geometry, aided by a continuous guided capture sweep
   if three separate photos are insufficient. Repeated green trays make appearance
   alone ambiguous. Do not assign identity purely by left-to-right order. Unknown
   scale permits a relative map but not calibrated metric height. Request the
   particular missing angle/stack close-up when association is unresolved.
9. Fuse observations per physical stack/layer, preserve alternate count candidates
   where uncertainty spans multiple integers, and count each eligible layer once.
   Use independently calibrated evidence checks rather than weighted averaging
   of scene counts. Correlated detector and edge failures are not independent
   confirmation. Visualize filled, empty and unresolved layers separately; allow
   audited manual corrections without silently rewriting inference.
10. Integrate behind a separate candidate endpoint: Cloudflare -> authenticated
    Python/OpenCV service + Roboflow -> per-stack evidence/total -> APK. Keep the
    requested baseline live during development. Validate contract, capture flow,
    latency, retry handling and actual Android-device use before replacement.

## Validation gates

- This known scene must return eligible 100, empty 1, with per-stack explanation
  on repeated captures. Solving it alone is a regression check, not generalization.
- Compare detector-only, detector/layer and marker-assisted variants on identical
  held-out scenes; report exact scene match, MAE, signed bias, filled/empty errors,
  one-to-one matched instance precision/recall and accepted/recapture coverage.
- Proposed operational goal: at least 99% exact among automatically accepted
  scenes and at least 90% automatic coverage on the declared operating envelope;
  these are proposed gates, not measured performance. Report confidence bounds.
- Roughly 300 independent accepted scenes with zero errors are needed for a
  one-sided 95% binomial lower bound near 99%, subject to representative sampling.
  Repeated shots of one unchanged arrangement are not independent test scenes.
- Visible complete stock can be verified; completely hidden inventory/occupancy
  requires more observation or a physical/loading record. Do not promise universal
  100% from three photographs. Synthetic scenes supplement real validation only.

References:
- https://docs.roboflow.com/train/evaluate-trained-models
- https://roboflow.com/split-datasets/yolo
- https://docs.opencv.org/4.x/d5/dae/tutorial_aruco_detection.html
- https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html

Architecture: [current baseline, proposed hybrid and evaluation flow](COUNTING_ARCHITECTURE.md).
Evidence: [source images and layer overlays](../reports/user-100-tray-case-20260915/README.md).
