# RF-DETR count-model comparison

Both models were trained on frozen `projec-mutta/2` and evaluated on the exact same 10-image count benchmark at confidence 35% and overlap 50%.

| Metric | Medium | Large |
|---|---:|---:|
| Model ID | `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1` | `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-large-t2` |
| Training ID | not available | `9fd5202da865a4447708` |
| mAP@50 | 69.3% | 68.1% |
| Precision | 79.7% | 78.9% |
| Recall | 67.3% | 63.4% |
| F1 | 73.0% | 70.3% |
| Exact-count accuracy | 20% (2/10) | 10% (1/10) |
| MAE | 22.9 | 24.0 |
| Median absolute error | 19.5 | 22.5 |
| Maximum absolute error | 51 | 57 |
| Mean relative error | 41.57% | 47.203% |
| Mean count accuracy | 58.43% | 52.797% |
| Undercount / overcount frequency | 5 / 3 | 6 / 3 |
| Three-view exact consistency | 0% | 0% |
| Three-view prediction spread | 84 | 85 |

Large improved two near-straight examples (`32: 29→30`; `120: 124→122`) and the distant 76-tray frame (`25→42`), but it severely regressed side views (`9→3`, `12→4`), the elevated frame (`73→87`), and the previously exact 21-tray frame (`21→18`).

## Decision

**DO NOT DEPLOY RF-DETR Large.** It fails every promotion gate: lower detection metrics, lower exact accuracy, higher MAE, higher relative error, worse maximum error, and worse three-view spread.

Keep the Medium production endpoint unchanged at confidence 35% and overlap 50%. The next experiment is annotation correction plus scene grouping, not a larger architecture or threshold tuning.

## V3 policy-consistent Medium candidate

The 27 conflicted assets were removed from the project, and `V3 Policy-Consistent 72` was frozen with 51/16/5 train/valid/test images, Auto-Orient plus Fit within 640x640, and no augmentations. RF-DETR Medium training `0981ff81168f8d0f02da` used the V2 Medium checkpoint.

| Metric | Deployed V2 Medium | V3 Medium |
|---|---:|---:|
| Model ID | `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1` | `rahuls-workspace-l9ylz/projec-mutta-3-rfdetr-medium-t1` |
| mAP@50 | 69.3% | 74.3% |
| Precision | 79.7% | 84.3% |
| Recall | 67.3% | 67.5% |
| F1 | 73.0% | 75.0% |
| Exact-count accuracy | 20% (2/10) | 20% (2/10) |
| MAE | 22.9 | 20.7 |
| Mean relative error | 41.57% | 38.157% |
| Mean count accuracy | 58.43% | 61.843% |

**DO NOT DEPLOY V3.** It improves MAE and detector metrics, and it exactly counts the 120-tray benchmark image, but it does not strictly beat the required exact-match baseline (>2/10). The production V2 environment remains unchanged.
