# Controlled development checkpoint — 2026-09-28

Started from verified local/remote5967ce82cd76ef9d2c11c1050f347b14a71f3200 on
codex/hybrid-cell-counting, initially clean. Existing source originals/frozen
benchmarks/server secrets were preserved. No production model, APK or AWS host
was deployed.

## Data actually available

947 egg-image paths /527 unique byte contents,138 near-duplicate candidate links,
two conservative leakage groups; two unrelated design images excluded with hashes.
Generated reviewed crops have known parents; some legacy assets lack reliable
parent/session/view metadata and stay quarantined under conservative barriers.
The inventory does not claim to have recovered every historical augmentation.

The capture-day grouping can overmerge
distinct arrangements and is not proof of physical stock identity. Historic
canonical137 sources resolved by hash; wh009/025/069 original hashes did not.
72 overview audit candidates remain pending full-resolution label QA.

Seven visually reviewed development faces provide125 centers: five wide faces
20/20/20/20/19, side19, and one newly reviewed small foreground stack7 from an
existing individual-tray photo. Its seven rows were reviewed on an enlarged crop;
it has blur, approximate centers and uncalibrated endpoints. All are assistant
visual references, not physically certified filled-tray inventory. The side photo
and wide arrangement must not be summed;125 is the number of target annotations.

Frozen V5-CLEAN-CONTROL subset remains six TRAIN crops/118 boxes, zero VALID/TEST,
explicit training_release_eligible=false. No full-frame V5 model was trained.
The grouped-development extra is excluded from this frozen control snapshot.
Targets, QA board, source availability and frozen checksums are under dataset/.

## Results, including the failed generalization

| Method / scope | Counts on five wide faces | Exact faces | MAE | Mean signed error |
|---|---|---:|---:|---:|
| V2 archived full image |76 total vs99 visible reference; stack metrics unavailable |—|—|−23 total|
| V2 archived manually rectified |19/22/20/22/17 |1/5|1.4|+0.2|
| Archived band best |12/11/19/19/10 |0/5|5.6|−5.6|
| New heatmap, six-face training fit only |20/20/20/20/19 |5/5|0|0|
| New heatmap, group held out |2/2/4/6/11 |0/5|14.8|−14.8|
| V5 clean full frame |Not trained; incomplete approved control |—|—|—|

Twenty-epoch CPU smoke fit on the original six faces returned6/6 raw counts exact,
MAE0. It still missed19 labeled positions and had19 unmatched/spurious peaks at
fixed6px tolerance (17/17 for the five wide faces). Count agreement hides position
errors, even on training examples. Its supervised loss fell1.1590→0.7781. The
smoke folder preserves this training-only run; it is not a performance claim.

Two actual leave-one-group-out runs used the seven-face manifest. Fold0 trained
on the7-layer face, held out all six original faces; validation-best epoch13,
stopped18. Fold1 trained on all six original faces, held out the7-layer face;
validation-best epoch1, stopped6. No threshold sweep or truth-specific correction.

Held-out counts:2/2/4/6/11/16 versus20/20/20/20/19/19, and15 versus7.
Aggregate **0/7 exact**, **0/2 groups exact**, **MAE12.142857**, mean signed
error−9.857143. At fixed6px center tolerance:103 missing labeled positions,
34 unmatched/spurious peaks. Heatmap forward latency averaged12.21ms per face
on an earlier CPU replay; final recorded rerun48.80ms (excludes upload,
localization, rectification and bands). Single probes vary with system load,
so these are not a deployment latency benchmark.
Tiny training groups and approximate visual annotations limit these statistics;
they are development diagnostics, not an untouched warehouse acceptance set.

Heatmap-only, heatmap+bands and heatmap+bands+archived RF all returned unresolved
selected Z on all seven held-out faces because independent endpoint/quality/
occupancy/grid evidence is missing. Rejection100%; false accepted inventory0;
accepted-scan accuracy undefined. This does not demonstrate calibrated rejection
performance in the field. Raw predictions are retained for error analysis.

Historical frozen full-frame V2:2/10 exact MAE22.9; V3:2/10 MAE20.7; V4:1/10
MAE21.4. These are older diagnostic benchmarks with known training duplicates;
they are neither directly comparable to this tiny face CV nor remeasured here.

## Localization and backend

Actual localization replay:5 reviewed faces→8proposals. At polygonIoU.5,
3/5 match (mean matchedIoU.61054),3 physical faces fragment across proposals,
0 merges,0 wholly unassociated reviewed faces;2 faces fail one-to-oneIoU matching.
See localization/spatial-mapping.jpg. Manual rectification supplies geometry for
the heatmap experiment; no automatic localizer accuracy improvement is claimed.

Authenticated `/candidate/stack-heatmap` loads a trusted checkpoint once,
reuses native rectification/rim analysis, maps optional RF centers into heatmap
coordinates, and returns per-stack polygon/homography/peaks/rims/quality/sequence.
Quality diagnostics describe image blur/exposure/resolution; complete stock scope,
endpoints and occupancy remain unknown. Always inventory_total=null, grid=null,
verified=false. Real-checkpoint HTTP/auth/hash-mismatch tests passed. No actual
SceneCertifier, occupancy learner or cross-view grid was manufactured by this work.

## Checks and artifacts

- All77 backend tests pass, including11 sequence cases and auth host regression.
- Training self-check passes: output shape, frozen backbone, Gaussian peaks,
  incomplete control gate and rejection of placeholder AWS requests.
- Dataset lineage/source/frozen-content/125-target checks pass.
- Local AWS bundle stages18 manifest dependency files; no S3 write.
- Local resume test restores the best model after its output file is moved
  aside; before/after SHA matches. This is not an AWS Spot execution test.
- Actual CPU smoke and two grouped-CV jobs completed; metrics/checkpoint hashes
  and epoch histories are saved in smoke/ and cv/. Weights stay under ignored
  work/stack-heatmap-recorded-smoke-20260928 and
  work/stack-heatmap-recorded-cv-20260928. Earlier experimental runs remain local.
- AWS Docker/request/Spot checkpoint paths prepared; Docker/AWS CLI unavailable
  on this host, so container/cloud execution is unverified. No billable actions.

## Next steps

1. Review more existing full-resolution stack faces with varied layer counts,
   poses, illumination and tray types. Manually adjudicate provisional near-match
   links into genuine scene/session groups; preserve all lineage and holdouts.
   Resolve missing wh009/025/069 sources or exclude them permanently.
2. Complete the V5 full-frame label control and independent development groups,
   then freeze the same640/RF-DETR Medium/threshold baseline before training.
3. Audit heatmap location failures and pitch-scale variation; compare a small
   trainable backbone block and mild realistic scale/JPEG/blur augmentation under
   grouped validation. Do not optimize against the99 total or acceptance data.
4. Train/evaluate a physical stack-face localizer separately; reduce the measured
   fragmentation before end-to-end count claims. Label occupancy separately.
5. Only after explicit cost approval, verify the AWS image/IAM/quota and run the
   frozen experiment using the prepared request. Capture new physically counted
   warehouse scenes before final acceptance; this gate does not block development.

Implementation/reproduction: model-improvement/stack-heatmap/README.md.
