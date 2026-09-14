# Previous context — 2026-09-14 checkpoint

Created at the user's request. This filename did not previously exist.
Existing conversation history remains in previous_chat.md; current requirements
remain in context.md and chronological evidence in PROGRESS.md.

## User objective

Count each physical tray containing eggs exactly once from LEFT, STRAIGHT and
RIGHT photos of the same group. Floor-cell IDs are optional. Combine model
detections, layer structure and calibrated height/markers when available.
Agreement between whole-photo totals is not the requested counting algorithm.
Retain manually counted references, measure errors and precision honestly,
deploy the backend/model and deliver an Android APK.

## Actual state

- Existing deployed Worker routes to Roboflow serverless projec-mutta/2. Fresh
  inference succeeded. It is the old cloudflare_roboflow_egg_tray_baseline, not
  the new hybrid service. Latest health is only status ok; ready identifies V2.
- Wrangler whoami still says unauthenticated on this machine. Previous OAuth
  device flows timed out. This prevents a new deployment, not operation of the
  already deployed Worker. Browser sign-in and CLI authorization are separate.
- Local Worker accepts model_spatial_v1 without floor IDs, preserves boxes,
  and returns unresolved per-photo evidence. It does not infer a scene total.
- Local mobile now captures without mandatory IDs and expects that new contract.
  Consequently the existing live deployment fails its preflight until updated.
- backend/app/vision/hybrid.py contains a tested height/fusion policy, but no
  image/API adapter calls it. The separate older Python layer pipeline uses
  spatial-order association; it is not the required robust identity solution.
- Missing: automatic physical stack association across angles, per-layer egg
  occupancy evidence, image-to-hybrid integration and deployed Python gateway.
  Fixing authentication does not complete these implementation tasks.

## Evaluation and artifact

The retained img04.jpg reference is 32 visible trays, 16 + 16. It was a non-blind
visual recount of an existing benchmark, not physical stock/hidden occupancy
verification. Image SHA-256:
38fac27c726aae28c7d31c177793772d0c3b4932a901bc13402848e21e4ed330.

Fresh V2 inference returned 29: error -3, absolute error 9.375%, count closeness
90.625%. This is not precision. Assisted layer-only returned 23; detector-guided
layer experiment was unresolved. The live evaluation submitted three separate
benchmark scenes to the endpoint's required upload slots, not a three-view
inventory scene. No exact hybrid accuracy or instance precision/recall exists.
Evidence is in reports/manual-reference-20260913/; preserve frozen labels.

Built local egg-tray-counter-0.2.2-hybrid.apk, version 0.2.2+5, 59,631,396 bytes.
SHA-256: 1ae72eb5fefab5ad695603b4cfaeb79d51e32a62c4a2a2224ae8ff042c8a7a4b.
Manifest, v2 signature and ZIP integrity passed. It is a development build;
its filename is not a claim of operational hybrid counting. Its debug signing
key differs from 0.2.1, preventing an in-place update. Preserve installed data.
No device/emulator was connected. See reports/APK_0.2.2_BUILD.md.

Flutter analysis was clean; 16 mobile, 44 backend and 11 Worker tests passed.
Worker compilation/dry-run and targeted Ruff passed. No model promotion or new
Cloudflare deployment occurred. APK is ignored locally, not a GitHub release.

## Resume in this order

1. Read AGENTS.md, PROGRESS.md and context.md; verify the actual checkout.
2. Establish deployment authorization via Wrangler OAuth or a scoped deployment
   token stored as a secret. Alternatively configure Cloudflare Workers Builds
   from GitHub. Never put private keys in chat, logs, source or APK.
3. Deploy the compatible optional-marker diagnostic contract and test it with
   the APK, clearly distinguishing diagnostics from an accepted inventory total.
4. Implement the missing image/identity/occupancy adapters and server-side Python
   gateway. Use model/layer evidence when markers are absent; calibrated geometry
   only when real calibration is available. Do not replace this with voting.
5. Obtain same-scene three-view data with checked per-stack/occupancy truth;
   measure exact-match rate, MAE, instance precision/recall and accepted coverage
   on held-out scenes. Do not tune or fabricate predictions from saved truth.
6. Rebuild after integration, recover the original signing key for an in-place
   upgrade, and perform actual device capture/inference tests before claiming
   production readiness. Update the handover with measured results.

Full plan and reusable prompt: docs/COUNTING_EXECUTION_PLAN.md.
This checkpoint publishes the actual unfinished source alongside its documents;
it must not repeat the older handover's mistake of claiming absent local code.
