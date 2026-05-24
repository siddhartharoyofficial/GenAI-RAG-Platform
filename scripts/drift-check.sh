#!/usr/bin/env bash
# Detect drift between Terraform state and live GCP resources across envs.
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID must be set}"
DRIFT_FOUND=0

for ENV in dev staging prod; do
  echo "==> Checking drift in ${ENV}"
  pushd "terraform/environments/${ENV}" >/dev/null

  terraform init -reconfigure \
    -backend-config="bucket=tfstate-${PROJECT_ID}" \
    -backend-config="prefix=genai-rag/${ENV}" >/dev/null

  if ! terraform plan -detailed-exitcode -var "project_id=${PROJECT_ID}" -out=/tmp/drift-${ENV}.plan >/dev/null; then
    ec=$?
    if [ $ec -eq 2 ]; then
      echo "    DRIFT DETECTED in ${ENV}"
      DRIFT_FOUND=1
    else
      echo "    plan failed in ${ENV}"
      exit $ec
    fi
  else
    echo "    no drift"
  fi

  popd >/dev/null
done

exit $DRIFT_FOUND
