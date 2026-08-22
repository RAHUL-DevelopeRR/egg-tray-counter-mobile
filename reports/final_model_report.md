# Final model report

Roboflow V2 training finished and produced
`rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1`. Direct hosted
`projec-mutta/2` inference succeeded on all 13 selected real local images.

Training-record metrics are mAP@50 67.75%, precision 81.1%, recall 61.3%.
The live model record separately reports mAP@50 69.28%, precision 79.7%, recall
67.3% and F1 73.0%. The API does not expose enough provenance to reconcile the
two surfaces, so they are not averaged or silently substituted.

Raw V2 detection counts exactly matched available annotation counts on 2/13
images, with MAE 14.46 detections/image. One zero-label image visibly contains
many trays, demonstrating that available labels also need review. This result is
not three-view exact-count accuracy.

The backend now supports V2 only behind the explicit
`ALLOW_EXPERIMENTAL_TRAY_BOX_BASELINE=true` switch. It assumes the operator has
framed exactly one physical stack; two quality-approved views must agree on a
positive count. Otherwise it returns `RESCAN REQUIRED`. Production continues to
require reviewed `stack_face` labels, a compatible model, linked triplet ground
truth and product-level false-accept/coverage evaluation.
