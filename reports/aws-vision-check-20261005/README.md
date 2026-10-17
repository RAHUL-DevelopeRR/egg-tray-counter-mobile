# AWS vision deployment and reconstruction check — 2026-10-05

Historical checkpoint: deployment completed on 2026-10-06. See the adjacent
reports/aws-vision-check-20261006/ report for the hosted artifact and verification.

## Observed state

The AWS Core connection initially required reauthentication. After the user
reconnected, `sts:GetCallerIdentity` confirmed account 608942062000. In
ap-south-1, a private S3 staging bucket with public access blocked, AES256 and
seven-day object expiry was created, along with ECR repository
`egg-tray-vision-pilot`. AWS Core then required reauthentication again before
source upload or image build. There is no CodeBuild project, Lambda function,
service endpoint, or AWS real-photo response yet. No AWS CLI/profile or Docker
installation was found locally. Cloudflare V2 remains the production endpoint.

## Real-photo verification

Re-ran `scripts/reconstruct_pair.py` on the unchanged saved files
`reports/two-view-20260924/input-1.jpg` and `input-2.jpg`. It reproduced the
previous 2 strict mutual SIFT matches. At relaxed ratios, the 0.75 trial gave
8 candidates/7 fundamental inliers; the 0.85 trial gave 52 candidates/11
fundamental inliers. No camera pose or point cloud passed the strict branch.
`physical_trays` was null and `verified` false. The prior report and fresh
output are in `reports/two-view-20260924/result.json` and
`work/3d-recheck-20261005/result.json` respectively.

Used the local authenticated diagnostic host via FastAPI TestClient with the
saved warehouse photos 1, 2, and 3 plus their archived Roboflow V2 boxes.
The view slots are transport assignments only; calibration, camera pose, and
physical scene stability are unconfirmed. The host returned HTTP 200,
`mode: diagnostic_only`, `inventory_verification_ready: false`,
`status: recapture_required`, 16 stack *candidates*, zero accepted
correspondences, null `physical_trays`, null `eligible_egg_trays`, and
`verified: false`. The 16 proposals are not 16 confirmed physical stacks.
The full local response is `work/3d-recheck-20261005/candidate-response.json`.

Targeted host/spatial tests: 14 passed. These are contract tests, not a
field-accuracy result. No physical filled/empty tray recount was supplied.

## Deployment gate and next action

Once AWS Core is reconnected, upload the validated source ZIP, build the
`backend/Dockerfile.vision-lambda` image with CodeBuild, then create an on-demand
Lambda pilot with bounded concurrency and authenticated candidate requests.
Verify `/health` and an
authenticated candidate call against the same saved inputs. Do not route the
mobile app to it as an exact-count service: current output is explicitly
unverified. Next model work is scene-held-out, physically recounted stack
localization, tray-rim/layer detection, cross-view identity, and occupancy
evaluation. Hosting cannot turn the current insufficient correspondences into
a 3D inventory count.
