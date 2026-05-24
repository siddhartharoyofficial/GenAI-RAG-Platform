#!/usr/bin/env bash
# Run the AlloyDB Auth Proxy for local psql access.
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID must be set}"
REGION="${REGION:-us-central1}"
ENV="${ENV:-dev}"
CLUSTER="genai-rag-${ENV}-alloydb"

if ! command -v alloydb-auth-proxy >/dev/null 2>&1; then
  echo "Install alloydb-auth-proxy: https://cloud.google.com/alloydb/docs/auth-proxy/connect"
  exit 1
fi

INSTANCE_URI="projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER}/instances/${CLUSTER}-primary"

echo "==> Starting AlloyDB Auth Proxy on 127.0.0.1:5432 for ${INSTANCE_URI}"
exec alloydb-auth-proxy "${INSTANCE_URI}" --address 127.0.0.1 --port 5432
