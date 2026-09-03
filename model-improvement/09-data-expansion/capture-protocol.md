# Real egg-tray capture protocol

Real warehouse triplets are the primary data source. They match the production camera, tray design, lighting, and occlusion patterns; Universe data is supplementary and must not replace them.

## Capture target

Capture **30 new physical scenes / 90 photos** as the minimum meaningful bump: one LEFT, one STRAIGHT, and one RIGHT photo per scene. V3 has only 72 images (at most 24 complete triplets), so 30 new scenes more than doubles the maximum scene diversity while still being practical to review. Keep collecting toward 60 scenes if the first retrain still fails the fixed count benchmark.

Prioritize:

| Scenes | Condition |
|---:|---|
| 12 | two or more stacks partially occluding or overlapping each other |
| 6 | strongly compressed left/right perspective |
| 4 | elevated angle with visible tray tops (hard negatives) |
| 4 | distant or darker warehouse stacks |
| 4 | clear ordinary stacks retained as controls |

This mix targets the observed failures: severe left/right undercount, elevated-view overcount, distant/dark undercount, and repeated-pattern straight-view overcount. The referenced `occlusion-gap-analysis.md` is not present; the evidence used here is `07-validation/failure-analysis.md` and `07-validation/error-analysis.md`.

## Before each scene

1. Assign the next immutable scene ID: `scene_YYYYMMDD_NNN`.
2. Obtain the tray count from a physical warehouse count or inventory record. Never infer a hidden tray count from the photo.
3. Keep the stacks unchanged until all three views are captured.
4. Record `tray_count_gt` only when the physical count is known; otherwise leave it blank and mark `needs_manual_count`.

## Capture each triplet

1. Hold the phone in landscape orientation at approximately the vertical midpoint of the stacks.
2. Fill most of the frame with the complete stack group while keeping every outer edge visible. Do not crop the top, bottom, or side faces.
3. Capture STRAIGHT with the camera approximately perpendicular to the central stack face.
4. Move left and capture LEFT at roughly 25–40 degrees from straight.
5. Move right and capture RIGHT at roughly 25–40 degrees from straight.
6. Keep distance and zoom approximately constant across the triplet. Use the native camera resolution; do not use digital zoom, portrait mode, filters, or screenshots.
7. Let the app's local blur, exposure, and resolution checks pass. Retake motion-blurred, crushed-black, blown-highlight, or low-resolution frames.
8. Use diffuse warehouse lighting where possible. Avoid glare across the horizontal rails, strong backlight, and a phone shadow covering the stack face.
9. For the occlusion subset, preserve real overlap but move enough that LEFT and RIGHT reveal complementary boundaries. Do not rearrange trays merely to make annotation easy.

## Naming convention

Use lowercase names that map directly to `scene_id` and `view`:

```text
scene_YYYYMMDD_NNN__left.jpg
scene_YYYYMMDD_NNN__straight.jpg
scene_YYYYMMDD_NNN__right.jpg
```

Example:

```text
scene_20260902_001__left.jpg
scene_20260902_001__straight.jpg
scene_20260902_001__right.jpg
```

The metadata row uses `scene_id=scene_20260902_001` and `view=left|straight|right`. Never encode an unverified count in the filename.

## Scene acceptance checklist

A triplet enters the review queue only when all answers are yes:

- Exactly three files exist with one shared scene ID and distinct LEFT/STRAIGHT/RIGHT views.
- The physical arrangement did not change between views.
- Image edges do not clip any stack face needed for counting.
- Blur, exposure, and resolution are acceptable.
- At least one frame clearly establishes each visible stack boundary.
- `tray_count_gt` comes from a physical/manual count, or is blank and flagged `needs_manual_count`.
- No AI-generated, downloaded, filtered, or screenshot image is included.

## Handoff

Place accepted triplets in a new review batch; do not add them to a training version yet. Annotation suggestions remain drafts until a reviewer passes edge clipping, occluded-extent, and one-box-per-visible-face checks.
