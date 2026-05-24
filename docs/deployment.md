# Deployment Guide

Step-by-step instructions for standing the platform up from scratch in a brand-new GCP project.

## Prerequisites

- A GCP project with billing enabled and Owner permissions on the project.
- `gcloud` CLI authenticated: `gcloud auth login` and `gcloud auth application-default login`.
- Terraform `>= 1.7`.
- Docker.
- `kubectl` and `kustomize`.

## 1. Bootstrap

The bootstrap step is one-time per project. It creates the GCS bucket for Terraform state, enables the required APIs, and creates the deploy service account for CI/CD.

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

./scripts/bootstrap.sh
```

What it does:

1. Sets the active project: `gcloud config set project $PROJECT_ID`.
2. Enables the APIs Terraform will need (Compute, Container, AlloyDB, Memorystore, Vertex AI, Cloud Run, Secret Manager, Artifact Registry, Cloud Build, Service Networking, IAM Credentials, certificate-manager, monitoring, logging, trace).
3. Creates a GCS bucket `tfstate-$PROJECT_ID` with versioning enabled.
4. Creates the `github-deploy` service account and binds it to the roles needed for `terraform apply` (compute admin, container admin, alloydb admin, redis admin, artifact registry admin, service account user, etc.).
5. Optionally configures a Workload Identity Federation pool for GitHub Actions.

## 2. Provision infrastructure

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=tfstate-${PROJECT_ID}" \
  -backend-config="prefix=genai-rag/dev"

terraform plan -var "project_id=${PROJECT_ID}" -out=tfplan
terraform apply tfplan
```

This takes 15–20 minutes the first time. The slowest pieces are AlloyDB and the GKE Autopilot control plane.

Outputs of interest:

```
gateway_url             = "http://34.x.x.x"
artifact_registry_repo  = "us-central1-docker.pkg.dev/your-project/genai-rag"
```

## 3. Deploy the reranker model

The reranker endpoint exists; you still need to deploy a model to it. For Cohere Rerank 3 multilingual via Model Garden:

```bash
gcloud ai endpoints deploy-model "$(terraform output -raw vertex_endpoint_id)" \
  --region="${REGION}" \
  --model="publishers/cohere/models/rerank-multilingual-v3.0" \
  --display-name=reranker-v1 \
  --machine-type=n1-standard-4 \
  --min-replica-count=1 \
  --max-replica-count=4
```

Self-hosted alternative (BGE-Reranker-v2-m3): build a Vertex AI custom prediction container and deploy it the same way.

## 4. Build and push the API image

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD)
export IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/genai-rag/api:${IMAGE_TAG}"

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
docker build -t "$IMAGE" -f docker/Dockerfile .
docker push "$IMAGE"
```

## 5. Apply schema migrations to AlloyDB

```bash
# Connect via the AlloyDB Auth Proxy.
./scripts/alloydb-proxy.sh &
psql "host=127.0.0.1 user=postgres dbname=ragdb" -f scripts/sql/init.sql
```

`scripts/sql/init.sql` enables the `vector` extension, creates the documents/parent_chunks/chunks/session_turns tables, and builds the HNSW + FTS indices.

## 6. Deploy the application to GKE

```bash
# Pull cluster credentials.
gcloud container clusters get-credentials genai-rag-dev-gke --region "$REGION"

# Patch the image reference in the overlay.
cd k8s/overlays/dev
kustomize edit set image REPLACE_ME_WITH_IMAGE="$IMAGE"
kubectl apply -k .

# Wait for rollout.
kubectl -n genai-rag rollout status deploy/dev-api --timeout=5m
```

## 7. Smoke test

```bash
GATEWAY_URL=$(cd terraform/environments/dev && terraform output -raw gateway_url)

curl -sS "${GATEWAY_URL}/healthz"
# {"status":"ok"}

curl -sS -X POST "${GATEWAY_URL}/v1/query" \
  -H 'content-type: application/json' \
  -d '{"query": "What is hybrid search and why does it improve recall?"}' | jq
```

## 8. Promote to staging / prod

The pattern is identical to dev — switch the working directory and backend prefix, then `terraform plan` and `terraform apply`. The `deploy.yml` GitHub Actions workflow does this with `environment: prod` so it requires a manual approval before the apply step.

## Teardown

```bash
cd terraform/environments/dev
terraform destroy -var "project_id=${PROJECT_ID}"
```

Note: AlloyDB clusters have a 7-day post-deletion retention by default. If you need to delete state during retention, contact GCP support or use `gcloud alloydb clusters delete --force`.

## Troubleshooting

**`Error: googleapi: Error 403: Cloud Resource Manager API has not been used in project`**
You skipped step 1. Re-run `./scripts/bootstrap.sh`.

**Pods stuck in `ImagePullBackOff`**
The pod's KSA isn't bound to a GSA with `roles/artifactregistry.reader`. Check the Workload Identity annotation on the `api` ServiceAccount.

**`FT.CREATE` index error on Redis**
The instance is provisioned but you haven't run the index init job. Apply `k8s/jobs/redis-index-init.yaml` (deferred file in this skeleton).

**AlloyDB connection refused**
Confirm the Private Service Access connection in the network module applied successfully — `terraform state list | grep psa`.
