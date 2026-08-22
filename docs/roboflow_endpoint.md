# Roboflow endpoint

## Verified identifiers

- Workspace: `rahuls-workspace-l9ylz` (`RAHULs Workspace`)
- Project: `projec-mutta` (`PROJEC MUTTA`)
- Task/class: object detection, `egg_tray`
- Existing model: version 1, YOLOv11n
- Clean dataset version: version 2, 99 images (69 train, 22 validation, 8 test)
- Version 2 model: RF-DETR Medium, training ID `34b83955e7339d2ebeb6`, finished

## Endpoints

The tested version 2 direct Hosted API endpoint is:

```text
https://serverless.roboflow.com/projec-mutta/2
```

The existing workflow endpoint is:

```text
https://serverless.roboflow.com/rahuls-workspace-l9ylz/workflows/projec-mutta
```

Configure the backend with `ROBOFLOW_MODEL_ID=projec-mutta/2` and
`ROBOFLOW_VERSION=2`. It sends the API key server-side; the mobile app must never
contain that secret. The saved workflow still resolves to V1, so the experimental
V2 launcher uses the direct model endpoint.

## Promotion status

Hosted V2 inference succeeded on 13/13 selected local images. Training and model
records report different metric snapshots, retained separately in
`reports/final_model_report.md`. This proves endpoint operation, not product
exact-count accuracy.

V2 emits `egg_tray`, not the production `stack_face` contract. The backend's
experimental single-stack bridge must be enabled explicitly and requires two
accepted views to agree; it never adds view counts. Production still requires
human-reviewed stack-face labels and linked three-view exact-count evaluation.
