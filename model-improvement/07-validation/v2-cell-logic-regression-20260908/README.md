# V2 regression after local cell-identity fix — 2026-09-08

Unchanged ten-image benchmark: **2/10 exact, MAE 22.9**, matching the deployed baseline. The inference model and 35% confidence / 50% overlap settings did not change. This is a per-image counting regression test, not an end-to-end test of cell association. Raw responses and per-image counts are included.

The local Worker now requires operator-confirmed cell IDs for each photo, groups counts by cell, rejects missing identities before inference, and never compares or sums unrelated view totals. A lone observation of a cell cannot certify its count; unresolved cells keep overall totals null and route to manual recount. Low mean detection confidence (<0.8) and nonpositive counts veto automatic acceptance. This 0.8 guard is conservative and uncalibrated, not an accuracy claim; high confidence/agreement can still be wrong.

The mobile app asks for the painted ID on every capture, binds it to the photo, clears it when retaking, sends it with the image, and rejects servers that do not acknowledge the cell protocol/identities. Operator entry is not automated OCR or proof of physical identity. One entire cell must be framed, neighboring cells excluded. Three distinct images are still required; use a separate three-view scan per cell for automatic verification. Mixed-cell captures retain separate candidates and request recount/recapture, not a guessed aggregate.

Manual recount action explains physical recount and recording in the operator's inventory log; it does not pretend a manual observation is model-verified. No automated height measurement, wall calibration, partial-top-layer arithmetic, global inventory deduplication, or hidden-stack counting is implemented. Legacy Python FastAPI does not implement this protocol; the updated client fails closed against it.

Local verification: TypeScript compile; eight Worker unit/HTTP-stub tests passed; five Flutter tests passed; Flutter analyzer clean. No real Android camera/device test has been performed for this change. The Worker best-practice review used current Cloudflare documentation and worker types 5.20260908.1, without changing dependency versions.

**NOT DEPLOYED.** The user said any shipped change must strictly improve both count metrics. An identity-only safety fix ties those metrics, so independent release approval was requested. Until approved, source changes stay local and the current APK/Worker remain unchanged. This gating conflict is not a reason to retrain or relax the benchmark.

Reproduce count regression from the repository root with the key in the environment:

```powershell
.\.venv\Scripts\python.exe model-improvement/evaluate_count_model.py --model rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1 --confidence 35 --overlap 50 --output model-improvement/07-validation/v2-cell-logic-regression-20260908
```
