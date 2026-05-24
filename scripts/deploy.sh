#!/usr/bin/env bash
# End-to-end deploy: terraform apply -> docker build/push -> kubectl apply.
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID must be set}"
ENV="${ENV:-dev}"
REGION="${REGION:-us-central1}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/genai-rag/api:${IMAGE_TAG}"

echo "==> Deploying ${ENV} with image ${IMAGE}"

echo "==> Terraform apply"
pushd "terraform/environments/${ENV}" >/dev/null
terraform init -reconfigure \
  -backend-config="bucket=tfstate-${PROJECT_ID}" \
  -backend-config="prefix=genai-rag/${ENV}"
terraform apply \
  -var "project_id=${PROJECT_ID}" \
  -var "api_image=${IMAGE}" \
  -auto-approve
popd >/dev/null

echo "==> Docker build and push"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
docker build -t "${IMAGE}" -f docker/Dockerfile .
docker push "${IMAGE}"

echo "==> Kubernetes deploy"
gcloud container clusters get-credentials "genai-rag-${ENV}-gke" --region "${REGION}"

pushd "k8s/overlays/${ENV}" >/dev/null
kustomize edit set image "REPLACE_ME_WITH_IMAGE=${IMAGE}"
kubectl apply -k .
popd >/dev/null

kubectl -n genai-rag rollout status "deploy/${ENV}-api" --timeout=5m

echo "==> Done. Gateway URL:"
pushd "terraform/environments/${ENV}" >/dev/null
terraform output -raw gateway_url
popd >/dev/null
echo
