# Deployment

## Development

Use the mock provider, Windows run scripts, Android emulator URL
`http://10.0.2.2:8000`, and in-memory backend idempotency. Debug overlays may be
enabled locally.

## Cloud MVP

1. Confirm the correct private Roboflow workspace and explicit model version.
2. Set `INFERENCE_PROVIDER=roboflow`; inject `.env` through the deployment secret
   manager, never an image or source repository.
3. Run FastAPI behind TLS and an authenticated API gateway/load balancer.
4. Replace in-memory idempotency with Postgres/Supabase keyed by `scan_id`.
5. Use production CORS origins only; wildcard CORS is rejected by configuration.
6. Disable debug overlays and raw-image logs. Persist photos only under an
   approved consent/retention policy.
7. Monitor p50/p95 total and stage latencies, provider errors, verified/rescan
   coverage, and corrections after review.

Serverless Roboflow is the default initial host. Move to dedicated deployment for
predictable high throughput/latency, or self-hosted inference when data residency
or edge constraints justify the operational burden.

## Future edge phase

After the cloud MVP is validated, export a compatible model, verify prediction
parity, benchmark ONNX Runtime/NNAPI/Core ML, and add `OnnxInferenceProvider`.
Business logic remains unchanged. Cloud stays available as fallback until edge
quality and version rollout are controlled.

## Optional Supabase

`docs/supabase-schema.sql` defines the planned tables and RLS. The mobile client
does not receive a service-role key. Use backend-authenticated writes or a scoped
user session.

