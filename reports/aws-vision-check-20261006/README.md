# AWS vision deployment and saved-photo verification — 2026-10-06

## Hosted artifact

- Account: 608942062000; region: ap-south-1.
- Lambda: egg-tray-vision-pilot, Active; last update Successful.
- URL: https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/
- Public health: GET /health. Every candidate request requires the application bearer credential.
- Credential: SSM Standard SecureString /egg-tray-vision-pilot/service-token; never ship it in the APK.
- ECR image: egg-tray-vision-pilot:pilot-20261006.
- Immutable digest: sha256:f4843cebc73d1dbe15f717799cdb9361ef2deb0b5c57e82a0a92cfa3e7b9a472.
- Runtime: Python 3.12, AWS Lambda Web Adapter 1.1.0, x86_64; 2048 MB, 120-second timeout.
- Adapter integration follows the [official AWS Docker image instructions](https://github.com/aws/aws-lambda-web-adapter#docker-images).
- No provisioned concurrency or always-running service was created. Account concurrency limit observed: 10.

The initial Uvicorn connection limit of 2 rejected the first external health
request because the adapter readiness connection was still active. CloudWatch
showed HTTP 503 and “Exceeded concurrency limit.” The deployed ImageConfig now
overrides the image command with one worker and no Uvicorn connection limit.
backend/Dockerfile.vision-lambda contains the matching corrected command for
future builds. The image digest above refers to the originally built image;
the Lambda command override is part of the deployed artifact.

## Verification

scripts/probe_vision_host.py sent the retained warehouse photos and archived
Roboflow V2 boxes to the hosted candidate route. No new Roboflow inference
or model training was performed. View-slot assignments are recorded in
api-summary.json; calibrated pose and unchanged physical stock are unconfirmed.

| Check | Local diagnostic, Oct 5 | Hosted diagnostic, Oct 6 |
| --- | --- | --- |
| Health | HTTP 200 | HTTP 200 |
| Candidate without credential | Covered by host tests | HTTP 401 |
| Authenticated candidate | HTTP 200 | HTTP 200 |
| Status | recapture_required | recapture_required |
| Stack proposals | 16 | 16 |
| Accepted correspondences | 0 | 0 |
| Physical tray total | null | null |
| Eligible egg-filled total | null | null |
| Verified inventory | false | false |

Hosted client timings: health 3330 ms, candidate 14391 ms. These are individual
observations, not latency percentiles. A prior hosted candidate request took
11791 ms inside Lambda and peaked at 731 MB according to CloudWatch. After the
startup-command fix, the first health request completed successfully.

The six counting/correspondence summary fields above match the local replay.
Targeted host/spatial contract tests passed: 14 tests, one dependency deprecation
warning. These tests do not measure field accuracy.
This verifies deployment, authentication, multipart upload, and execution of the
existing diagnostic pipeline. It does not establish successful 3D reconstruction
or inventory accuracy. The strict two-view geometry check from Oct 5 still has
only two mutual SIFT matches, no accepted camera pose/point cloud, and null total.

## Build, cleanup and costs

CodeBuild refused StartBuild with AccountLimitExceededException: the account has
zero concurrent-build quota in both inspected regions. The unused project and
its role were deleted. A temporary t3.small builder produced the 188363399-byte
image, uploaded logs/status, and auto-terminated. EC2 instance i-085685badf81960c1
was directly confirmed terminated; its role, instance profile and no-ingress
security group were removed. Its root volume was configured DeleteOnTermination.

The remaining resources are the on-demand Lambda, its log-only role and seven-day
CloudWatch log group, the ECR image/repository, encrypted SSM parameter, and
private S3 staging bucket with seven-day object expiry. Storage, requests and
Lambda execution can incur charges; actual billing totals were not measured.
No image originals were uploaded to S3 during this session; the three photos
were transmitted directly to the authenticated Lambda endpoint for processing.

## Next steps

1. Keep the mobile production Worker/Roboflow V2 path until a separate diagnostic
   gateway route is implemented and verified. AWS hosting alone has not connected
   this endpoint to the APK, and it does not run a newly trained model.
2. Use the current reviewed scene groups to improve stack localization and tray
   layer centers/edges. The count and location failures of the existing heatmap
   development arms need correction before promotion.
3. Add calibrated camera poses and physical stack identities across overlapping
   views. Evaluate duplicate removal and missed layers on unchanged scenes.
4. Obtain independent physical filled/empty recounts for acceptance and report
   exact per-stack/scene matches, absolute error, and false acceptance. Hidden
   occupancy must remain unresolved where the input cannot establish it.
