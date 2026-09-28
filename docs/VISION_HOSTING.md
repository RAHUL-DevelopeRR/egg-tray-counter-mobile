# Hosting and scan archive checkpoint

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
