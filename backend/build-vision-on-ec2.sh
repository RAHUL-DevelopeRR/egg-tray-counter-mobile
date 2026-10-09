#!/bin/bash
set -euo pipefail
export AWS_DEFAULT_REGION=ap-south-1
bucket=egg-tray-vision-pilot-608942062000-ap-south-1
registry=608942062000.dkr.ecr.ap-south-1.amazonaws.com
repository=egg-tray-vision-pilot
tag=pilot-20261007-integration
log=/var/log/egg-tray-vision-build.log
exec > >(tee -a "$log") 2>&1
finish() {
    status=$?
    trap - EXIT
    printf '{"exit_code":%s}\n' "$status" > /tmp/vision-build-status.json
    aws s3 cp "$log" "s3://$bucket/build/20261007-integration/build.log" || true
    aws s3 cp /tmp/vision-build-status.json "s3://$bucket/build/20261007-integration/status.json" || true
    shutdown -h now
}
trap finish EXIT
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"
docker build -f Dockerfile.vision-lambda -t "$registry/$repository:$tag" .
docker push "$registry/$repository:$tag"
aws ecr describe-images --repository-name "$repository" --image-ids "imageTag=$tag" > /tmp/vision-image.json
aws s3 cp /tmp/vision-image.json "s3://$bucket/build/20261007-integration/image.json"
