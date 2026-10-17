# Hosting and scan archive checkpoint

## Staging mobile relay checkpoint - 2026-10-07

The diagnostic is now reachable from APK 0.3.4+10 through
https://egg-tray-counter-api-staging.rahultech72216.workers.dev/v1/reconstruct.
Select this staging URL in Settings; the production default is unchanged.
Worker secret authentication stays server-side, and validated originals are
archived privately in R2. AWS image pilot-20261007-integration adds colored
sparse points, cameras and bounds. It does not run dense reconstruction or
tray-instance counting. Four API pairs matched direct Lambda; one positive
pair was displayed through the emulator. Full manual UI matrix remains pending.
See ../reports/reconstruct-integration-20261007/README.md
for digests and evidence. The earlier deployment notes below are historical.

## AWS camera geometry route — 2026-10-07

The existing Lambda now also exposes protected POST /candidate/reconstruct.
Multipart first/second originals must be distinct JPEG/PNG images of equal
size, at most 2 MB and 12 MP each. The result contains uncalibrated camera poses
and sparse point coordinates under three focal assumptions; physical_trays
remains null. Public health advertises two_view_sfm_diagnostic_v1.

Image pilot-20261007 has verified digest
sha256:4ef6034d8adb553478d86f73a131d6c8dff3ba943cf1d49a063b11315cda70fb.
Saved-photo replay and repeat succeeded: HTTP 200, 175 matches, 125 fundamental
inliers, 76/94/100 sparse points. Anonymous requests receive 401. Windows results
differ; points are not trays. All 15 local hosting/spatial tests passed.
Temporary EC2 builder, role/profile and security group were removed. Worker/APK
integration and calibrated inventory verification remain pending.

Evidence and PLY files: reports/aws-reconstruction-deploy-20261007/.
The following hosting notes preserve earlier deployment/provider checkpoints.

## Current AWS pilot — 2026-10-06

The authenticated Python diagnostic is deployed as Lambda egg-tray-vision-pilot
in ap-south-1, account 608942062000. Public health:
https://e3mkfxljv7ja42ygklbacg3fge0cibxg.lambda-url.ap-south-1.on.aws/health.
Candidate calls require the bearer credential retained in SSM SecureString
`/egg-tray-vision-pilot/service-token`; keep it server-side. No token is in the
APK, repository or report. The service is diagnostic_only and still returns
unresolved inventory for the saved-photo check. It is not integrated with the
Worker/APK yet. Full deployment state, latency observations, source hashes and
verification output: reports/aws-vision-check-20261006/.

CodeBuild quota zero required a temporary EC2 builder; it is terminated and
its role/profile/security group were removed. Lambda has no provisioned
concurrency; storage and execution remain metered. ECR image digest and the
Lambda command override are both required to reproduce the deployed artifact.
The override removes Uvicorn's limit 2, which rejected the first request while
the adapter's readiness connection remained active. The future Lambda Dockerfile
now matches the corrected command.

The provider notes below are historical checkpoints.

> 2026-10-05 status: AWS is now the user's requested vision host. AWS account
> 608942062000/ap-south-1 has a private S3 pilot bucket and ECR repository,
> but AWS Core requires reauthentication again before the source/image can be
> uploaded or built. No Lambda service or endpoint exists. The saved-photo
> diagnostic still returns null inventory; see `reports/aws-vision-check-20261005/`.
> Historical account/provider notes below describe the 2026-09-23 checkpoint.

Cloudflare Worker is deployed with private R2 binding SCAN_ARCHIVE pointing to
egg-tray-scan-archive. Version 4c1480e6-0136-4514-8640-b67b02eb98ac.
Validated, distinct image uploads are stored before inference at:

    scans/<scan UUID>/<left|right|straight>/<SHA-256>

Content type, view, hash and receive time are object metadata. No public bucket
or public download endpoint is enabled. Failed inference can leave a recoverable
set of originals; partial storage failures may leave a partial set. Repeated
identical submissions reuse the same keys. No automatic expiry is configured.
Retrieval currently requires authenticated Cloudflare operator access, using
R2 dashboard browsing by scan ID or this CLI command from cloudflare-worker:

    npx wrangler r2 object get egg-tray-scan-archive/scans/SCAN_ID/VIEW/HASH --remote --file saved-photo.jpg

Android Recent scans still contains metadata only. In-app photo retrieval needs
an authenticated ownership model and photo links; do not expose images by scan
UUID alone or embed operator credentials in the APK. Old scans cannot be restored
by creating this bucket. Storage is metered under the account's R2 allowances.

## Python diagnostic container

Prepared backend/Dockerfile.vision and app.vision_service:create_vision_app.
This entrypoint exposes only health and the candidate endpoint; it does not
expose mock counting. It requires VISION_SERVICE_TOKEN (at least 32 characters)
for every non-health request. Store it in host/Worker secrets, never the APK.
It continues to report unresolved counts; the ordinary production route remains
unchanged and hybrid_ready=false.

Build from repository root, on a Docker host:

    docker build -f backend/Dockerfile.vision -t egg-tray-vision backend
    docker run --rm -p 127.0.0.1:8000:8000 --env VISION_SERVICE_TOKEN egg-tray-vision

The container uses one worker, concurrency limit 2, non-root execution, and PORT
for managed-host compatibility. Hosting still requires ingress limits, TLS,
server-side secrets and benchmarked resource sizing. Candidate evidence is
hash-bound but caller supplied, so authentication does not make it ground truth.

No Oracle/Google account exists per user. No Docker runtime is installed here;
container build has not been tested. Python entrypoint tests pass locally.
Cloudflare Containers requires a paid Workers plan; no upgrade authorized or
performed. User is choosing Oracle free-account setup versus Cloudflare paid.
Do not claim this service is deployed or integrated into APK scans yet.
