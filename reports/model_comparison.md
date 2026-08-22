# Roboflow model comparison

| Item | Version 1 | Version 2 |
|---|---:|---:|
| Dataset images | 371 | 99 |
| Split (train/valid/test) | 260 / 74 / 37 | 69 / 22 / 8 |
| Architecture | YOLOv11n | RF-DETR Medium |
| Training status | Finished | Finished |
| mAP@50 | 12.02% | 67.75% training / 69.28% model record |
| Precision | 59.7% | 81.1% training / 79.7% model record |
| Recall | 12.5% | 61.3% training / 67.3% model record |
| F1 | 20.7% | 73.0% model record |
| Exact annotation-count match | Not measured | 2 / 13 real-image smoke samples |
| Three-view exact-scene accuracy | Not measured | Not measured |

The two V2 metric rows are retained separately because Roboflow's training and
model-list API surfaces return different values. Neither is an inventory metric.
At confidence 0.50, V2's 13-image count-agreement smoke test had MAE 14.46
detections per image. One supposedly empty label was visibly incomplete, so this
is dataset diagnostic evidence rather than a locked evaluation.

Both models emit `egg_tray`. V2 is the stronger detector baseline but does not
satisfy the final `stack_face` segmentation and three-view product contract.
