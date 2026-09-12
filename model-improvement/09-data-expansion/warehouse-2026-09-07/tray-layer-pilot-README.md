# Individual-tray pilot — 2026-09-07

**V4 TRAINING COMPLETED; BENCHMARK FAILED. DO NOT DEPLOY.** September 8 benchmark: **1/10 exact, MAE 21.4**. See [full evidence](../../07-validation/rfdetr-medium-v4-c35-o50/README.md).

The user explicitly approved public upload to `rahuls-workspace-l9ylz/projec-mutta` after the initial privacy block. All three crops uploaded (zero duplicates/errors); all 47 tray annotations were saved and added to the Dataset. The annotation approval check was resolved after verifying that the payload contained box geometry/class labels rather than a separate inventory report. Production remains unchanged.

Training ID: **`518b30dcad42a78a5d33`**, created **2026-09-07 15:50:29 UTC (21:20:29 IST)**, finished **21:56 IST** on Roboflow. Model `rahuls-workspace-l9ylz/projec-mutta-4-rfdetr-medium-t1`: mAP50 71.48%, precision 78.2%, recall 66.3%. These are detection metrics, not exact count accuracy. [View V4 training](https://app.roboflow.com/rahuls-workspace-l9ylz/projec-mutta/4). Credit consumption was not measured.

## Prepared locally

- Three full-height foreground crops from wh009, wh025, wh069 in the already supplied `Downloads/Photos` folder; originals unchanged.
- 47 explicit individual-tray boxes: 7 + 20 + 20. Codex opened each original and each numbered overlay. These are agent-reviewed visible-layer annotations, not independent human certification or hidden/whole-warehouse counts.
- No detector predictions were accepted as ground truth. Whole-stack annotations wh018/19/20 remain isolated and are not used here.
- Source and derived SHA-256, crop coordinates, and train-only scene grouping are recorded in `tray-layer-pilot-provenance.json`. Parent-image duplicate checks passed the previous dHash screen; that heuristic is not proof of scene independence. The three crops have not been designated acceptance images.
- JPEGs, YOLO labels, and numbered overlays are in `work/tray-layer-pilot/` (ignored by Git). Run `prepare_tray_layer_pilot.py` to reproduce them. Assertions check source hashes, duplicate flags, crop bounds, unique boxes, and counts.

## Frozen dataset and submitted run

Existing V3-only tag `v3-policy-consistent-72` resolves to 72 images with 51/16/5 splits. Do **not** select every asset with the legacy clean tag: that search currently returns 109 assets, some outside the intended frozen subset. The staged script requires exact IDs and dataset membership.

V4 combines the 72-image subset and three train-only crops: **75 images / 54 train / 16 valid / 5 test**, confirmed by `versions_get` after generation finished. It is an incremental pilot, not all 74 warehouse images. Full-frame annotation of the other images is still incomplete. The historical 72 were overview-policy-consistent candidates, not a newly completed full-resolution QA audit.

RF-DETR Medium only, checkpoint **`rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1`**, 100 epochs maximum; Auto-Orient + Fit within 640; no augmentation. The crop selection preserves entire foreground stack height; it is not random crop augmentation. The same-room photographs and crop-heavy pilot limit generalization claims.

`run_tray_layer_pilot.py` journals each stage and refuses duplicate generation/training requests. All stages through training submission and status verification have now executed. Do not rerun upload/generate/train. Use `training-status` to inspect the existing run with `ROBOFLOW_API_KEY` in the environment; never commit credentials.

API issues resolved without duplicate jobs: generation input requires `filter-tags: {tag: true}` even though version output uses nested `tags/require`; the rejected first generation created no version. The first training call triggered the required COCO export, which was polled until ready. A bare checkpoint slug was rejected; read-only REST inspection of the previous successful V3 run supplied the exact workspace-qualified checkpoint. Training began only after the export was ready and absence of existing V4 jobs was verified. The immediate generation response showed the unfiltered project count (390); the completed frozen version correctly contains 75. The journal preserves both snapshots.

## Evidence gate

Production V2 remains unchanged. The existing `evaluate_count_model.py` was run with identical ten files and manifest-based stale-extension resolution, confidence 35 / overlap 50. Promotion requires **exact >2/10 AND MAE <22.9**. V4: **1/10 exact, MAE 21.4; DO NOT DEPLOY**. Historical V3 remains 2/10 exact, MAE 20.7, also rejected. Two supplied warehouse originals scored V4 0/2 exact, MAE 2.0 versus V2 0/2 exact, MAE 1.5. A separate scene-independent warehouse acceptance test remains necessary; training crops cannot serve that role.

This run does not implement floor-cell capture, height calibration, or fix cross-view totals covering different physical tray sets.
