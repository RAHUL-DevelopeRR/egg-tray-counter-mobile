# Hybrid evidence contract — development component

Updated 2026-09-13. `backend/app/vision/hybrid.py` is a server-internal
measurement/fusion component. It is **not connected to the API or mobile app**.
It does not implement image-based geometry, occupancy detection or a deployable
hybrid service. Do not advertise a hybrid scan contract on its strength alone.

## Evidence needed to connect the component

- A surveyed scan scope: stable floor-cell/column IDs and their physical bounds.
  A floor cell can contain more than one vertical column. Each column must be
  associated spatially across views, not by left-to-right order or photo totals.
- Measured floor/wall reference coordinates, camera intrinsics and distortion,
  capture resolution/orientation, recovered pose and an uncertainty estimate.
  A floor-only homography or an illustration does not establish vertical height.
- A matching tray/stacking profile: support-to-top-rim heights for 1, 5, 10 and
  a taller manually counted stack, with measurement uncertainties. Reference
  pitch must represent actual loading and compression. Mixed nested empty and
  loaded trays may violate a single-pitch model; do not reuse an incompatible
  profile. No extrapolation above the tallest reference is accepted.
- Spatially assigned Roboflow tray evidence from the retained V2 model, plus
  optional independent layer evidence. One unexplained discrepancy rejects a
  column; no one-tray tolerance or correction multiplier has been validated.
- Occupancy evidence covering every layer. `egg_tray` labels and eggs visible
  only on the top tray cannot establish occupancy of the hidden layers.
  Unknown occupancy must remain unknown. Do not populate `filled_trays` by
  copying `detected_trays`.

The fusion requires three distinct guided photographs and at least two complete,
geometrically separated observations of each scoped column. A third occluded
observation may be unusable; disagreement in a usable observation is not ignored.
The default 15-degree separation is an unvalidated capture gate. Geometry and
identity validity flags must include quality, calibration and association checks
performed by a trusted server adapter, never client-supplied assertions.

The height solver returns all counts compatible with measurement intervals; it
never rounds to a nearest count. Fusion requires one height candidate and exact
agreement with tray evidence. It sums egg-containing trays once per column and
withholds the entire inventory total when any scoped column remains unresolved.
It does not yet certify an entirely empty floor column: absence of detections
cannot prove emptiness. Such columns currently require review.

## Counting definition

The latest request concerns trays containing eggs. Empty trays are excluded.
A partially filled tray is one egg-containing tray, but does not imply 30 eggs.
The existing app's trays-times-30 convention remains unchanged; the new core
does not produce an egg total. Future UI integration must label this as capacity
unless full 30-egg occupancy is established.

## Verification and accuracy

From `backend/`, run `py -3 -m unittest tests.test_hybrid_core -v`.
These synthetic unit tests check policy and arithmetic, not detection accuracy.
Keep the historical warehouse benchmark untouched. Collect a separate measured
three-view benchmark with column IDs, tray counts, layer occupancy and calibration
metadata. Separate warehouse scenes between development and held-out evaluation.

Report exact scene count rate, exact column count rate, MAE, rejected/rescan rate,
and accuracy among accepted scans together. A system rejecting every scan cannot
claim near-100% counting performance. Report RF-only, height-only and hybrid
results separately, and count missing evidence as unavailable rather than making
up a score.
