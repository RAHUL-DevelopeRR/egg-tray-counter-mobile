# Roboflow V2 real-image smoke test

Run date: 2026-08-21  
Hosted model reference: `projec-mutta/2`  
Model asset: `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1`  
Task/class: object detection / `egg_tray`  
Inference settings: confidence `0.50`, overlap `0.50`

## Outcome

Hosted serverless inference succeeded for all 13 selected real images. The images cover every local `test` image and every local `valid` image, with YOLO annotation counts ranging from 0 to 131.

| Measure | Result |
|---|---:|
| Successful images | 13 / 13 |
| Exact annotation-count matches | 2 / 13 (15.4%) |
| Ground-truth annotation sum | 699 |
| Prediction sum | 629 |
| Net count error | -70 |
| Mean absolute error | 14.46 detections/image |
| Root mean square error | 24.16 detections/image |
| Mean absolute percentage error | 21.72% (12 non-zero images) |
| Mean reported model time | 52.54 ms/image |
| Median reported model time | 52.20 ms/image |
| Mean observed MCP wall time | 16.11 s/request |
| Median observed MCP wall time | 15.21 s/request |

The model service is operational, but raw detection count is not reliable enough to serve as the product's tray total. The largest miss was `64` predictions versus `131` annotations. One image with an empty YOLO label produced 44 predictions; that case requires human label review before it can be treated as a verified false-positive result.

## Interpretation limits

- This is an endpoint and count-agreement smoke test, not a controlled model evaluation. These source splits may overlap data used to build Roboflow Version 2.
- A YOLO annotation line counts an `egg_tray` object. It is not three-photo scene ground truth and does not test cross-view deduplication.
- Reported model time is Roboflow compute time. MCP wall time includes transport, authentication, queueing, tool orchestration, and parallel-request contention; it is not expected mobile latency.
- A first parallel request for the 1-object video frame failed transiently, then succeeded on immediate serial retry. The final CSV records the successful retry. This suggests application-level timeout/retry handling remains necessary.
- Thirteen debug overlays were persisted under `reports/debug/v2` with actual V2 boxes, confidence labels, and prediction-versus-annotation counts. Source photos and labels were not modified.

## Roboflow metric records

Roboflow exposes two metric records for this trained model. They are preserved separately because they come from different API reporting surfaces and should not be silently merged:

| Surface | mAP@50 | Precision | Recall | F1 |
|---|---:|---:|---:|---:|
| Training record (`trainings_get`) | 67.75% | 81.1% | 61.3% | Not reported |
| Model record (`models_list`) | 69.28% | 79.7% | 67.3% | 73.0% |

Both records support the same conclusion: V2 is materially better as an `egg_tray` detector than V1, but these detector metrics do not establish product-level exact counting.

Detailed evidence is in `v2_real_image_smoke_test.csv`.
