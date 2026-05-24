#!/usr/bin/env bash
# One-time project bootstrap: enable APIs, create state bucket, create deploy SA.
# Idempotent — safe to re-run.
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID must be set}"
REGION="${REGION:-us-central1}"
STATE_BUCKET="tfstate-${PROJECT_ID}"
DEPLOY_SA="github-deploy"

echo "==> Bootstrapping project ${PROJECT_ID} in ${REGION}"

gcloud config set project "${PROJECT_ID}"

echo "==> Enabling APIs"
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  alloydb.googleapis.com \
  servicenetworking.googleapis.com \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudtrace.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  certificatemanager.googleapis.com \
  apigateway.googleapis.com \
  servicecontrol.googleapis.com \
  servicemanagement.googleapis.com

echo "==> Creating GCS state bucket (if missing): gs://${STATE_BUCKET}"
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
else
  echo "    bucket already exists"
fi

echo "==> Creating deploy service account (if missing): ${DEPLOY_SA}"
if ! gcloud iam service-accounts describe "${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${DEPLOY_SA}" \
    --display-name="GitHub Actions deploy service account"
fi

DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Granting roles to deploy SA"
for role in \
  roles/compute.admin \
  roles/container.admin \
  roles/run.admin \
  roles/redis.admin \
  roles/alloydb.admin \
  roles/aiplatform.admin \
  roles/secretmanager.admin \
  roles/artifactregistry.admin \
  roles/iam.serviceAccountUser \
  roles/iam.workloadIdentityPoolAdmin \
  roles/serviceusage.serviceUsageAdmin \
  roles/storage.admin \
  roles/monitoring.admin \
  roles/logging.admin; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
done

echo "==> Bootstrap complete."
echo
echo "Next steps:"
echo "  1. cd terraform/environments/dev"
echo "  2. terraform init \\"
echo "       -backend-config=\"bucket=${STATE_BUCKET}\" \\"
echo "       -backend-config=\"prefix=genai-rag/dev\""
echo "  3. terraform plan -var \"project_id=${PROJECT_ID}\" -out=tfplan"
echo "  4. terraform apply tfplan"
