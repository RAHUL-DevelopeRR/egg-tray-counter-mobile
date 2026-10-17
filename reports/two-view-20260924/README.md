# Two-view reconstruction attempt — 2026-09-24

Actual supplied inputs preserved as input-1.jpg and input-2.jpg with SHA-256
in result.json. They are byte-identical to warehouse-20260923 images 1 and 4.
Historical model detections are therefore 76 and 19 (not fresh inference).
User reports the 19-tray count is correct; this does not label the wide scene.

Ran scripts/reconstruct_pair.py with OpenCV SIFT (6000 features per image),
mutual descriptor ratio checks, and RANSAC fundamental/homography diagnostics.

| Ratio threshold | Mutual candidates | Fundamental support | Planar support |
| --- | ---: | ---: | ---: |
| 0.65 | 2 | Not enough points | Not attempted |
| 0.75 | 8 | 7 | 4 |
| 0.85 | 52 | 11 | 5 |

Only two strict matches, insufficient for this camera estimation pipeline.
Relaxed matching gives mostly inconsistent candidates (11/52 epipolar support).
Neither strict match is a verified physical correspondence. See matches.jpg.
No camera pose, point cloud, deduplicated inventory or 3D count is accepted.
This is a failure of this tested method on this pair, not proof no method can
reconstruct any geometry from these images. Calibration and scene stability
are also unconfirmed. Image 2 clips the top of the stack.

The script includes pose/triangulation under explicitly assumed focal lengths
for future pairs passing strict correspondence, with positive-depth and
reprojection filters. That branch was not exercised by this real pair.
Its synthetic projection/triangulation self-check passed; this checks numerical
implementation only, not real counting or automated physical identity.

Next: record a continuous unchanged-scene front-to-side sweep with full top/base,
including intermediate corner views and physically counted stacks. Re-run
correspondence before any occupancy fusion. Do not sum 76+19 or multiply 19 by
the visible stack count. No production deployment or APK change in this step.

Reproduce (with the project's OpenCV/NumPy environment):

```powershell
python scripts/reconstruct_pair.py reports/two-view-20260924/input-1.jpg reports/two-view-20260924/input-2.jpg reports/two-view-20260924
```
