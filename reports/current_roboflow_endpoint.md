# Current Roboflow endpoint state

Verified: 2026-08-21

## V2 hosted model

- Direct inference model reference: `projec-mutta/2`
- Trained model asset: `rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1`
- Serverless endpoint base: `https://serverless.roboflow.com/projec-mutta/2`
- Status: hosted inference verified on 13 local real images
- Authentication: required; keep `ROBOFLOW_API_KEY` in the backend environment and never in the APK or source control

The model is running on Roboflow's serverless infrastructure when the direct model endpoint is invoked. It is not embedded in the APK and this verification does not prove the current Flutter/FastAPI path calls it.

## Saved workflow

- Workspace: `rahuls-workspace-l9ylz`
- Workflow slug: `projec-mutta`
- Workflow route: `https://serverless.roboflow.com/rahuls-workspace-l9ylz/workflows/projec-mutta`
- Current published default `model_id`: `projec-mutta/1`
- V2 default promoted: **No**

The workflow was read and not changed. Its model input can be overridden at runtime, but its saved default remains V1. Promoting V2 would be a separate deployment mutation and is not justified by this smoke test alone.

## Compatibility warning

V2 predicts class `egg_tray`. The product backend's production contract expects stack-face detections for geometric tray-periodicity counting and three-view fusion. Therefore, a working hosted V2 endpoint is not yet a production-compatible counting endpoint.
