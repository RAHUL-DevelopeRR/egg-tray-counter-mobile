# Vision pipeline

## Stack-face model contract

The desired model is instance segmentation with one class: `stack_face` (or the
configured equivalent). It locates a useful visible counting face. Hosted model
coordinates are mapped to the original image before thin-rail analysis.

If a Roboflow model returns only `tray` boxes, the adapter raises an actionable
unsupported-output error. Those boxes are never summed into inventory.

## Layer counter

For every rectified face:

1. grayscale and mild Gaussian smoothing;
2. vertical Sobel derivative (`dy=1`) and absolute magnitude;
3. horizontal projection excluding side margins;
4. Gaussian 1-D smoothing and median/MAD normalization;
5. autocorrelation pitch estimation in configured bounds;
6. pitch-derived peak distance/prominence;
7. regular-lattice fitting and limited internal-gap inference;
8. quality score from periodicity, residuals, prominence, and inference penalty.

The algorithm can infer a supported internal rail between observed neighbors,
but never extrapolates trays beyond the observed top/bottom face.

## Matching and fusion

The initial marker-free matcher uses left-to-right order and normalized height,
with an explicit association-confidence threshold. Count mismatches in visible
physical stacks cause rescan. ArUco/lane IDs should replace order-only matching
in a production warehouse.

Fusion requires at least two high-quality views that agree exactly. `[18,18,17]`
can verify 18 when evidence thresholds pass; `[18,17,19]` rejects. Median and
average are not substitutes for agreement. One failed physical stack rejects the
whole scene.

## Debugging

Set `DEBUG_OVERLAYS=true` only in development. The backend writes prediction
polygons and rectified rail overlays under `backend/debug-output/<scan_id>/`.
Keep this directory out of production image-retention flows.

