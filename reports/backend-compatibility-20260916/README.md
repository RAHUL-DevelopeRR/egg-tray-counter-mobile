# Installed APK compatibility repair — 2026-09-16

The reported screen says SERVER REACHABLE but rejects THREE-PHOTO SCAN with
FormatException before uploading. Live pre-fix health returned only status:ok;
readiness identified projec-mutta/2. The installed0.2.2 app requires
scan_contracts containing model_spatial_v1 and a matching response processing
mode. The intentional baseline rollback removed this capability declaration
and implementation. This was an API-generation mismatch, not a model crash.

User requested fixing the live error. This request supersedes the earlier
no-production-change instruction only for this compatibility repair. No model
training, experimental band integration or APK rebuild was performed.

Restored the model_spatial_v1 route already supported by local source. Added
backward-compatible routing for old requests with no scan_contract and no
cell-ID fields, preserving the original August baseline response/fusion from
git a2b1fd8. Explicit cell_identity_v1 requests still require IDs; partial ID
metadata does not silently downgrade to baseline. Unknown contracts are rejected.
The modern route accepts optional IDs and preserves model boxes, but correctly
returns unresolved inventory rather than certifying photo-count agreement.
Historical baseline response fields remain for compatibility, including their
known whole-photo counting and egg-capacity limitations; not exact hybrid proof.

Validation: TypeScript compilation, all12 Worker tests, deployment dry-run and
git diff whitespace check passed. A regression test covers app health preflight,
modern no-ID response, legacy no-ID request and unknown-contract rejection.

Wrangler OAuth remained usable after a transient connectivity failure. Retried
with system CA and IPv4-first DNS; deployed with --keep-vars, retaining existing
secrets/config. Version ab67cd59-3f4e-4628-a0fa-d085f56a3fe8 is now deployed at
https://egg-tray-counter-api.rahultech72216.workers.dev.
Live health.json advertises model_spatial_v1, cell_identity_v1 and hybrid_ready:false.
A new scan is necessary; prior scan records are unchanged. No actual phone
interaction was performed by the agent.


Live upload verification succeeded: HTTP200, model_spatial_v1, no cell IDs,
spatial detections/counts4/4/2, model processing7997ms, accepted:false and
inventory total:null. Used archived individual-photo images01/02/03 (third is
blurred); this is a compatibility smoke test, not exact-count evaluation or a
validated left/right/straight inventory capture. model-scan.json retains the
response. Initial curl TLS reset and default-httpx certificate failure were
resolved for this probe using Python ssl.create_default_context (Windows trust).
TLS verification stayed enabled. App preflight and result contract now match;
physical-device capture remains to be retried by the user.
