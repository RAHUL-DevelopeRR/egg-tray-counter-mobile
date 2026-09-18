# Physical tray counting: execution plan

## Target and current limits

Count the physical trays containing eggs in the captured scene using LEFT,
STRAIGHT and RIGHT images. Painted cell IDs are optional. When measured floor
and wall references exist, use them as additional geometric evidence. Otherwise
use model localization, tray-layer evidence and visual association. Agreement
between whole-photo counts is not the counting algorithm.

Target zero incorrect accepted inventory counts, and measure how often the system
can return a count. Universal 100% accuracy cannot be established from photographs
that hide the relevant trays or egg contents. Unresolved evidence requires a
targeted recapture or physical count; it must not silently become zero.

## Ordered implementation and release gates

1. Freeze reference truth before inference. Save image hashes, visible per-stack
   counts, whole-scene scope, who counted, whether counts were physical or visual,
   and ambiguous/hidden regions. Keep reference numbers outside inference inputs.
   Record this session's 32-tray image as a non-blind visual recount, not a new
   untouched test. Preserve the existing 10-image benchmark.
2. Run the unchanged V2 detector against those images. Retain original-coordinate
   boxes, confidence, model version and request settings. Clearly distinguish
   saved-response replay from fresh authenticated inference. Measure signed and
   absolute count error. Instance precision/recall requires separate validated
   tray annotations and one-to-one matching; a count ratio is not precision.
3. Identify complete physical stack faces and count visible tray rims/layers at
   original resolution after perspective correction. Do not treat one tray box
   as an entire stack face. Test missed/double rails, egg edges, clipped bases,
   different tray types, lighting and tightly nested empty trays. Manual ROI
   experiments must be labelled assisted and do not pass automatic deployment.
4. Associate physical stacks across LEFT/STRAIGHT/RIGHT using visual features and
   geometric consistency; use optional floor IDs as extra evidence. Handle
   repeated textures, reordered stacks and partial overlap. Reject ambiguous
   associations rather than sorting stacks by horizontal position alone.
5. With surveyed markers and matching camera calibration, recover pose/depth and
   support-to-rim height with uncertainty. Use a measured tray stacking profile;
   never use egg tips, an illustrative drawing or a floor homography alone.
   Missing markers select the model/layer path, not an invented calibration.
6. Establish egg occupancy per tray/layer. A generic egg_tray label or eggs visible
   on the top tray does not classify hidden layers. Annotate filled, partially
   filled, empty and occluded examples; train/evaluate occupancy evidence before
   certifying egg-containing inventory. Times 30 is capacity unless fullness is
   established.
7. Fuse spatial evidence into per-stack counts, retaining discrepancy and
   completeness information. Sum each physical stack once. Test RF-only,
   layer-only, calibrated-height and hybrid independently; never tune on the
   frozen evaluation set or use its truth to select a prediction.
8. Restore backend and Worker dependencies; verify browser and CLI/API access
   separately. Keep credentials server-side. Deploy an authenticated Python
   vision runtime behind the Cloudflare gateway; verify upload bounds, timeouts,
   retries, idempotency, contract compatibility and live authenticated inference.
9. Integrate one Android capture/result flow with optional markers, explain
   unresolved regions and preserve manual review. Run Flutter clean/pub get,
   analyze and tests; build the APK, verify package/version/signature/SHA-256,
   and test camera capture plus a real three-image scan on a device/emulator.
10. Release only with a held-out evaluation report. Split by physical scene and
    collection session, not adjacent video frames. Report scene/stack exact-match
    rate, MAE, error distribution, false acceptance, rescan rate and accepted-scan
    accuracy together. A single exact image or 100% rejection does not pass.

## Current execution state

The standalone calibrated fusion core has synthetic tests. The optional-marker
Worker path currently provides model boxes and diagnostic per-photo counts; it
does not claim spatial matching or a verified hybrid total. Automatic image-to-
hybrid integration, live inference evaluation and a new APK remain incomplete.

## Live capture pilot and device gate

The first device check is transport, not computer vision. Run adb devices -l
until the phone appears as device (not unauthorized or absent), record the
installed package/version, and collect one reproducible scan's app log with
the three exact uploaded files and request/response timing. If no serial
appears, do not infer anything about camera quality or backend behavior.

The pilot capture flow should provide immediate local feedback for frame
brightness, clipping, blur, orientation tilt and obvious frame-edge clipping.
It should pause capture when a hard quality gate fails and explain the repair.
Phone yaw is only guidance for LEFT/STRAIGHT/RIGHT; it is not a calibrated
camera pose or proof that a hidden stack is visible. A small, rate-limited JPEG
preview may ask the existing model for detection boxes near the image edge, but
the response must remain verified=false and must not certify coverage, occupancy
or a tray total. Keep preview requests bounded and preserve the existing no-ID
baseline contract.

After the pilot, evaluate the quality gates on labeled warehouse examples,
integrate only the checks that reduce rejected/incorrect scans, and build a
debug-signed staging APK. A production count still requires calibrated or
otherwise validated cross-view identity, per-layer filled/empty evidence and a
held-out same-scene evaluation with independent physical truth. A live camera
warning improves evidence collection; it cannot manufacture ground truth.

## Reusable execution prompt

Continue this repository; read AGENTS.md, PROGRESS.md, context.md and this plan.
Implement actual physical egg-containing tray counting, not voting between photo
totals. Use all three guided views. Treat floor IDs and calibrated height as
optional additional evidence; support model/layer processing when absent.
First freeze manually reviewed reference counts and hashes, then run inference
without feeding those counts into the algorithm. Preserve V2 and frozen tests.
Keep localization, layer counting, cross-view identity, occupancy and completeness
traceable. Report real errors, unavailable measurements and assistance explicitly.
Complete local checks, use authorized Cloudflare/Roboflow sessions without exposing
secrets, deploy only validated changes, and build/verify the Android APK. Never
claim an APK, deployment, 100% accuracy or hybrid integration before verification.
Update PROGRESS.md with completed work, exact results, artifact hashes and blockers.
