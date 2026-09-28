# Warehouse counting: implementation and acceptance plan

Updated 2026-09-23 from the user's synthetic augmentation task.

## Target and current boundary

Count each physical tray containing eggs once across a warehouse. Partially
filled trays count as one egg-containing tray, with partial occupancy recorded
separately. Empty toppers do not count. Actual egg count cannot be computed by
multiplying all occupied trays by 30 when partial trays are allowed.

The APK currently calls the Cloudflare Worker using model_spatial_v1. Fresh
/health reports hybrid_ready=false; /ready reports projec-mutta/2. The Worker
calls Roboflow and returns unmatched detections and an unverified total. The
local Python /candidate/count-3d route analyzes bands and provisional matching,
but explicitly rejects production use. No hosted Python service is configured.
The capture lighting-band metric is not tray-layer band counting.

## Capture SOP

- Scan one identified block at a time; maintain a warehouse ledger of blocks to
  prevent recounting the same stock. Floor paint is optional; block identity is not.
- Keep stock unchanged during each triplet. Show complete tops and bases, leave
  image margins, keep the phone still and avoid glare and deep bottom shadows.
- Use LEFT/STRAIGHT/RIGHT views with measurable overlap. Angle labels alone do
  not supply camera pose. The proposed 35–45 degree side angles are a calibration
  trial; the current app's 25–35 degree guidance is not validated calibration.
- Use torch if useful, then re-evaluate exposure. A phone torch may illuminate
  the front while leaving distant or concealed trays dark. Use even room light
  where necessary; do not waive image checks when torch is on.
- For concealed interior stacks, either expose them in additional views or
  record their identities, layer counts and occupancy during loading. A checkbox
  for uniform stacking is an assumption, not measured concealed inventory.

## Implementation order and measurable exit criteria

1. **Capture controls.** Add torch toggle with unsupported-device feedback and
   fresh-frame checks after changes. Validate low light, bottom shadows, blur,
   tilt, glare and incomplete framing on real phones. Report local measurements
   separately from semantic visibility checks; image edges alone cannot certify
   full stacks.
2. **Physical reference set.** Record per-stack physical layer and occupancy
   counts for unchanged triplets, including partial and empty trays. Keep whole
   scenes in one dataset split. Keep the historic 100-filled + 1-empty scene
   frozen; do not tune on its total or add one to every band result.
3. **Band and model evidence.** Reuse stack_measurement.py: rectify each face,
   retain rim/egg-row alternatives and harmonic ambiguity, inspect endpoints,
   and compare per-layer model evidence across views. 19 brightness intervals
   can correspond to 20 boundaries, but only confirmed feature semantics justify
   that conversion. Bands alone do not classify occupancy.
4. **Synthetic training data.** Measure the real trays first. The pasted task's
   pulp material, 300x300x50 mm dimensions and 42 mm pitch are proposed values;
   supplied photos show plastic trays. Parameterize material and measured loaded
   versus nested-empty pitch. Render instance IDs, partial occupancy, masks,
   keypoints, visibility, K/R/t and physical coordinates from one scene graph.
   Synthetic augmentation trains a detector; it does not reconstruct a real scan.
   Include empty/partial/filled classification and retain visible versus amodal
   annotations separately. Assess on held-out real warehouse scenes.
5. **Metric geometry and deduplication.** Calibrate intrinsics/distortion and
   recover relative poses using robust, non-repetitive matches, with a scale
   reference. Reject weak-baseline/planar degeneracy. Match layers and stacks with
   reprojection, positive-depth and uncertainty checks. A shared corner must
   have one physical_stack_id. Do not sum per-view totals or multiply area by
   height without a verified occupancy grid.
6. **Host and integrate.** Run Python vision on a container/VM with adequate
   memory, keep Cloudflare as the gateway, and avoid repeatedly buffering full
   warehouse images in the Worker. Authenticate the service and bind detections
   to image hashes. Use per-image upload references and bounded jobs for large
   scans. A host is still required before production integration can be verified.
7. **Acceptance.** Test 20 versus 10/40 harmonic confusion, 100 occupied + 1 empty,
   partial layers, shared corners, missing centers and unknown interiors. Report
   exact scene match, MAE, occupancy precision/recall, false accepted totals and
   rescan rate on held-out physical references. Detection confidence 0.50 and an
   example confidence 0.992 do not establish inventory accuracy.

## Response meaning

Expose verified observed counts, assumed/extrapolated counts, unknown positions
and unknown occupancy separately. Preserve null totals when coverage or occupancy
is unresolved. A conditional SOP extrapolation can be useful but must not be
labelled physically verified ground truth. Sum warehouse blocks only after their
identities and coverage are reconciled.

## Cloudflare finding

The gateway buffers multipart images and base64-encodes each image for Roboflow.
This is a resource-pressure risk, not a proven diagnosis of every historic error.
Cloudflare documents 128 MB memory per isolate; Free CPU time is 10 ms/request;
Paid defaults to 30 seconds and permits up to 5 minutes. Network waiting does
not count as CPU time. Check invocation outcome exceededCpu versus exceededMemory
before attributing a resource failure. The app's 45-second send/receive timeouts
are separate. Account plan and current invocation-limit outcomes were not
verified in this checkpoint.

Source: https://developers.cloudflare.com/workers/platform/limits/
