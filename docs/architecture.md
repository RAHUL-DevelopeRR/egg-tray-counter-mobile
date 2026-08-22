# Architecture

```text
Flutter camera
  -> local blur/exposure/resolution gate
  -> one idempotent multipart scan (LEFT, RIGHT, STRAIGHT)
FastAPI
  -> decode + independent view quality
  -> InferenceProvider (Mock | Roboflow | future ONNX)
  -> original-coordinate stack-face polygons
  -> perspective-rectified high-resolution faces
  -> Sobel-Y projection + pitch + rail lattice
  -> order/height stack association
  -> exact-agreement fusion
  -> VERIFIED totals | RESCAN REQUIRED without totals
Flutter
  -> result/targeted retake + local SQLite metadata history
```

## Boundaries

- Mobile owns capture guidance, immediate local quality, progress, cancellation,
  result presentation, and local history.
- Backend owns credentials, authoritative validation, inference, CV, association,
  fusion, and response safety.
- Provider outputs are normalized before vision/business logic. Adding ONNX does
  not change fusion or the API contract.
- Storage is optional. The current in-memory repository exists for idempotency,
  not image retention.

## Deferred phases

Supabase, review dashboard, on-device ONNX, and controlled model rollout are
intentionally deferred until labeled scene triplets and a measured cloud MVP
exist. See `deployment.md`.
