# Full-frame annotation checkpoint — 2026-09-08

User confirmed **count only egg-filled trays**. Active class `egg_tray` means one distinguishable egg-filled physical tray layer. Empty tightly nested stacks are non-targets. One tray seen from two faces gets one box enclosing its visible extent, not two detections. Partial/occluded targets require the policy's visibility check; no hidden-layer guessing. This convention applies to all 74 unique originals.

## Actual completion, not a training claim

- All 82 filenames inventoried; eight byte duplicates remain excluded. All 74 unique originals rechecked against their stored SHA-256.
- Seven existing contact sheets opened this turn: all 74 received overview triage, **not full-resolution box QA**. Many green views repeat one room/arrangement; orange/pulp scenes add material/framing variation but still need scene grouping.
- Full-resolution originals wh008, wh009, wh011, wh012 opened. wh008/009 have a clipped egg-filled tray at the right image boundary requiring a visibility decision; foreground-only annotations cannot certify the whole frame.
- Two original-sized drafts drawn for wh011 and wh012 (7 layers each), then numbered overlays inspected and perspective bounds corrected. These are local pre-annotations, not accepted ground truth. Original images were not cropped or changed. Nested empty background stacks are not annotated.
- `full-frame-review-queue.csv` lists every unique source with scope, hash, review status, conservative scene group, no guessed physical total, and `training_approved=False`. Two drafts need human review; the other 72 full-frame box sets are not completed. **Zero new training approvals, uploads, or training jobs.**
- Prior wh009/025/069 crop labels are not full-frame labels. The separate wh018/019/020 whole-stack-face uploads remain isolated and require replacement, not a class rename.

Reproduce artifacts from the repository root:

```powershell
.\.venv\Scripts\python.exe model-improvement/prepare_full_frame_review.py
```

It checks every source hash, unique counts, box bounds/counts, and writes full-image-normalized YOLO draft labels plus numbered overlays under ignored `work/full-frame-layer-review/`. `full-frame-layer-review.json` is the editable source of drafted coordinates. No prediction is automatically accepted as a label.

## Remaining work before retraining

Finish original-resolution annotation on all remaining images, review every foreground/background layer and edge fragment, reconcile the three historical stack-face uploads, and obtain annotation approval. Physical cell totals for count evaluation must be separately verified; visible labels alone cannot reveal hidden inventory. Keep related captures/crops together and leave final acceptance scenes untouched.

The requested no-retraining gates still apply. No several-fold collection push is launched or finalized while existing annotation review remains incomplete. Once complete, use the observed error categories to plan genuinely new full-scene warehouse captures, not more near-identical crops.
