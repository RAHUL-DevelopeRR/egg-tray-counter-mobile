# Reviewed-data follow-up and controlled CPU comparisons

Continued from verified local/remote `f6164c20ba876f0e9326eb2a4b75e25849a2298f`.
No production promotion. These are two-group development results; each validation
group also selects its checkpoint, so they are not unbiased test results.

## Data review completed

The previous frozen release remains unchanged. This separate release preserves
its seven reviewed faces and adds four literal source-image reviews: two five-layer
foreground faces in `image-06.jpg`, a seven-layer green foreground stack, and a
ten-layer orange foreground stack. Sources, original-coordinate center marks,
quadrilaterals, homographies, crop hashes, numbered QA and review notes are saved
in `dataset/`. Receding rows of eggs on one top tray count as one physical layer.
Partly occupied trays remain layer-existence references; occupancy is **unknown**.
Centers are approximate visual annotations, not calibrated physical measurements.
Covered background stacks are not approved by these crop reviews.

Result: **11 faces, 152 visible-layer references, two conservative leakage groups**.
All three faces from the September15 photo remain together. Both new canonical
TRAIN-source crops inherit the existing historical group. No original image or
historical acceptance benchmark was rewritten, and no new acceptance scene entered
training. The 72 V2 overview candidates still lack full-resolution box QA; recorded
V2 export paths checked in this continuation are unavailable. The V5 control
remains incomplete/ineligible, with no new detector-training result.

Visual triage found 36 unrelated résumé/editor screenshots in the September26
WhatsApp folder. They are excluded from this release; no screenshot contents are
published. The revised inventory has **915 paths, 495 unique contents, 127 candidate
near-duplicate links**, including four new derived crops. This corrects the earlier
947-path inventory's description as entirely egg imagery. Removing unrelated
contents does not relax a single retained leakage barrier. No additional physical
scene identity was asserted from a date or dHash alone.

Saved `.npy` targets are adaptive-width QA curves at640 positions. The trainer
regenerates fixed sigma3px targets from the same centers; it does not consume those
QA arrays. Hash checks enforce original source bytes and new crop bytes before
training; a parent source cannot appear in multiple leakage groups.

## Actual experiments

All arms use the same frozen manifest, leave one entire group out, seed20260928,
MobileNetV3 Small first four feature blocks, 640×192 input, positive-weight4 BCE,
Adam.003, brightness/contrast.9–1.1 only, peak threshold.5, peak distance8,
position tolerance6px, max30epochs and patience5. BN running statistics remain
frozen. `last-block` only unfreezes the final existing backbone block; inference
state-dict structure and old checkpoint loading remain compatible.

| Backbone / checkpoint criterion | Exact stacks | Exact groups | Count MAE | Missing positions | Spurious positions |
| --- | ---: | ---: | ---: | ---: | ---: |
| Frozen / BCE | 1/11 | 0/2 | 13.000 | 151 | 8 |
| Last block / BCE | 0/11 | 0/2 | 13.818 | 152 | 0 |
| Frozen / count | 3/11 | 0/2 | 5.091 | 114 | 70 |
| Last block / count | 2/11 | 0/2 | 4.818 | 108 | 71 |

`comparison.json` and each arm's two `run.json`, `comparison.json`, prediction QA
and aggregate `summary.json` contain full per-stack counts, histories, code hashes,
manifest hash and checkpoint hashes. Actual runner source bytes are archived under
`code-versions/` by their recorded SHA; the second runner adds criterion selection,
while the default BCE training behavior remains unchanged. Parent git commit records
the start commit; these runs also include then-uncommitted code identified by SHA.
Weights stay under ignored `work/`, referenced in each run, and are not deployed.

The BCE minimum suppresses all peaks in the thawed arm. Its validation loss improves
while useful counts disappear. The separate count criterion ranks checkpoints by
exact stacks, then MAE, then missing+spurious positions, then BCE. It changes only
development checkpoint selection, with no threshold tuning or truth-specific
correction. Improvements here reflect selection on these same development groups.

For frozen/count, the five original wide faces predict **5/5/15/20/23** against
20/20/20/20/19. The side predicts19, the added green/orange predict1/1 against7/10,
and September15 predicts7/6/6 against7/5/5. Even a correct scalar count often has
incorrect peak locations. At6px tolerance this arm has layer precision35.19% and
recall25.00%; the last-block/count arm has precision38.26% and recall28.95%.
Approximate centers add annotation uncertainty, but these failures are too large
to justify exact inventory. All solver variants still leave selected inventory
null because independent endpoint, quality, occupancy and physical-grid evidence
is unresolved. False accepted count0 is a consequence of withholding totals,
not a measured field-accuracy guarantee.

## Verification and reproduction

77 backend tests passed. Training checks cover backbone gradients, unchanged BN
buffers, old/new checkpoint loading, criterion ranking, rejected altered crops,
cross-group parent crops, nonfinite centers, unreviewed labels and acceptance
ingestion. Frozen dataset/source/crop hashes and all152 target peaks passed.
An actual new frozen/count checkpoint passed authenticated warmed route, hash
mismatch rejection, homography/band replay and null-inventory checks. A second
agent independently regenerated all four crops byte-for-byte and checked source
group inheritance. No APK, Cloudflare route or AWS resource was changed.

```powershell
$env:PYTHONPATH = "$PWD\work\vision-deps;$PWD\backend"
& .\work\heatmap-env\Scripts\python.exe model-improvement/stack-heatmap/expand_reviewed.py --check-only
& .\work\heatmap-env\Scripts\python.exe model-improvement/stack-heatmap/train_heatmap.py --manifest reports/stack-heatmap-followup-20260928/dataset/faces.json --output work/new-frozen-count --epochs 30 --mode loco --backbone-mode frozen --checkpoint-criterion count
```

Use separate output/checkpoint directories for each arm. Compare `frozen` against
`last-block` at a fixed criterion, or `bce` against `count` at a fixed backbone.
Do not rebuild this frozen release: create another release for label changes.

## Exact next steps

1. Recover missing original V2 label exports by content hash, then review complete
   full-resolution frames rather than approving an overview or crop's parent.
2. Review more existing complete faces with varied heights/colors/partial occupancy.
   Adjudicate whole scene/session lineage explicitly before adding independent
   development groups; do not split the current groups simply to enlarge validation.
3. Audit center definition and top/base geometry, and test preserving physical
   layer scale instead of resizing every stack to identical height. Freeze data
   and compare one representation change at a time with count and position metrics.
4. Evaluate/train physical-stack localization on reviewed whole faces independently
   of layer counts. Obtain separate occupancy supervision before counting filled
   trays; partial and unknown do not automatically mean full.
5. Finish eligible V5 control and compare on common reviewed scene groups. The
   current frozen control is not silently made eligible by these heatmap crops.
6. Prepared SageMaker/ECR training still needs explicit cost approval and verified
   account/roles/quotas/container. No billable cloud execution was performed.
   Production certification still requires new physically recounted, untouched
   warehouse scenes, cross-view identity and complete inventory/occupancy evidence.
