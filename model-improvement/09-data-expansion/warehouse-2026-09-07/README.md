# Warehouse intake checkpoint — 2026-09-07

**Latest update (2026-09-08): V4 Medium completed; DO NOT DEPLOY.** Unchanged ten-file benchmark: **1/10 exact, MAE 21.4**, failing the strict gate versus V2 (2/10, 22.9). Warehouse spot check: V4 0/2 exact, MAE 2.0 versus V2 0/2, MAE 1.5. See [benchmark evidence](../../07-validation/rfdetr-medium-v4-c35-o50/README.md). The stack-face checkpoint below records the earlier investigation, not the status of this tray-layer run.

## Completed

- Inventoried `C:\Users\dharani\Downloads\Photos`: 82 files, 74 SHA-256-unique images, eight byte duplicates. Originals are unchanged.
- Compared image dHashes against all 99 frozen V2 members (including the V3 subset) and the exact ten benchmark files. No candidate matched at Hamming distance <= 8. This is a duplicate-screening heuristic, not proof of scene independence.
- Visually triaged all 74 unique images using seven contact sheets. This is not completed annotation QA for all 74.
- Manually boxed and visually rechecked wh018, wh019, wh020: eight physical stack columns each, 24 boxes total. These three near-identical green-scene views add little independent diversity. The other 71 unique images are not accepted training annotations.
- Uploaded those three images and saved their labels in `projec-mutta`; see `upload-journal.json`. They stay together in train. Their labels use the active class `egg_tray` with explicit `stack_face` semantics.
- Removed the legacy `clean-manual-auto-reconciled-v2` tag from these three assets, retaining `warehouse-reviewed-20260907` and `stack-face-only-20260907`. No old asset or frozen version was changed.

## Critical contract mismatch

The historical `04-annotations/annotation-policy.md` and `01-dataset-audit/v2-visual-policy-audit.md` define V2/V3's `egg_tray` target as an **individual tray layer**, not a whole stack face. Earlier descriptions calling those 72 images stack-face-consistent were incorrect. Combining that dataset with these new stack-face boxes would reintroduce inconsistent supervision under the same class name.

For the requested stack-face pipeline, use a separately filtered, consistently reviewed dataset. Do not reuse the legacy clean tag or train the whole mutable project. Only three new images are labeled so far, all one scene; that is not a defensible new train/validation/test dataset.

## New-photo diagnostic evidence

These are development checks, not held-out accuracy estimates and not the ten-file promotion benchmark.

| Image | Manual stack-face boxes | V2 detections at confidence 35 / overlap 50 |
|---|---:|---:|
| wh018 | 8 | 81 |
| wh019 | 8 | 84 |
| wh020 | 8 | 74 |

The two columns use different units. These results demonstrate the target mismatch; they do **not** establish physical tray-count errors of 73/76/66. Physical scene totals remain unverified.

Bypassing detection and providing manually outlined foreground faces also exposes layer-counter failures:

| Image | Visually counted foreground trays | Existing Sobel/pitch result |
|---|---:|---:|
| wh009 | 7 | Rejected: no stable pitch |
| wh025 | 20 | 12 |
| wh069 | 20 | 11 |

Exact matches: **0/3**, including one rejection. No overall MAE is reported because that rejection is not a numeric estimate. Counts refer only to the visible foreground stack, not the full warehouse or hidden trays. A development-only saturation experiment returned 10/18/23 and also failed; it was not added to production.

## Benchmark and deployment

Last completed unchanged ten-file gate: V3 Medium **2/10 exact, MAE 20.7**; deployed V2 Medium **2/10 exact, MAE 22.9**. V3 did not strictly improve both metrics. Production configuration is unchanged.

The existing `evaluate_count_model.py` compares raw detection counts with tray totals. Preserve this historical test for reproducibility, but do not represent it as an end-to-end test of a stack-face-plus-layer-counter system. That system also needs a separate scene-grouped test with verified counts. No current evidence supports near-100% counting.

## APK

Built `egg-tray-counter-0.1.1-release.apk`, version 0.1.1 / code 2, package `com.dharani.eggtray.egg_tray_counter`, minimum Android API 24. APK signature verification passed. This is release-mode code using the existing **debug signing key**, not a Play Store production-signed artifact.

SHA-256: `390B60452938957FFA89547E6468B2C03C61C5E156655167262E6F119ABEC84A`.

The app still targets the existing Cloudflare endpoint and deployed V2 model; the rebuild is **not an accuracy improvement**. The Python perspective/Sobel pipeline is not hosted by that Worker. Elevated ADB started successfully and returned no connected devices/emulators; device installation and live scanning of this new APK are not verified. The configured ADB MCP itself failed with `spawn adb ENOENT`.

## Remaining work and reproduction

1. Complete stack-face annotation review of suitable new images; group every view of the same physical arrangement into one split. Do not random-split near-identical views or invent hidden counts.
2. Obtain physically verified per-arrangement tray totals and clarify whether nested empty trays count. The user does not need to resend these photos.
3. Fix and test layer counting on development scenes; leave separate acceptance scenes untouched.
4. Freeze a homogeneous stack-face version with Auto-Orient / Resize only; train RF-DETR Medium, never Large. Evaluate the historical gate unchanged and the complete counting pipeline separately. No deployment without evidence.

Local commands (from the repository root):

```powershell
.\.venv\Scripts\python.exe model-improvement/prepare_reviewed_warehouse.py
.\.venv\Scripts\python.exe model-improvement/check_warehouse_rois.py
# Requires ROBOFLOW_API_KEY in the environment, never committed:
.\.venv\Scripts\python.exe model-improvement/upload_reviewed_warehouse.py --verify
```

The earlier Codex approval-service usage block cleared on continuation. Roboflow confirmed all three annotation saves and isolation updates. The current training blocker is data/annotation validity, not an authentication failure.
