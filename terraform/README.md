# Terraform — GenAI RAG Platform infrastructure

This directory is the source of truth for everything we deploy to Google Cloud.

## Layout

```
terraform/
├── main.tf                 # Root composition; wires modules together
├── variables.tf            # Inputs for the root composition
├── outputs.tf              # Outputs exposed to environments
├── providers.tf            # Provider versions + auth
├── backend.tf              # GCS remote state config (filled in at init time)
├── environments/
│   ├── dev/main.tf         # Dev-specific overrides + backend config
│   ├── staging/main.tf
│   └── prod/main.tf
└── modules/
    ├── network/            # VPC, subnets, NAT, PSA, Serverless connector
    ├── gke/                # Autopilot cluster with Workload Identity
    ├── memorystore-redis/  # Semantic cache + session memory store
    ├── alloydb/            # pgvector + BM25 store, primary + replica
    ├── vertex-ai/          # Reranker endpoint + Artifact Registry
    ├── cloud-run/          # Intent router service
    ├── api-gateway/        # External LB + Cloud Armor WAF
    ├── monitoring/         # Alerts + dashboards
    ├── iam/                # Service accounts + Workload Identity bindings
    └── secrets/            # Secret Manager placeholders
```

## First-time setup

Before the first `terraform init`, run the bootstrap script. It creates the GCS bucket for remote state, enables the required APIs, and grants the deploy SA the right roles.

```bash
export PROJECT_ID="your-project"
./scripts/bootstrap.sh
```

## Deploying

Each environment has its own state prefix. Always initialize with explicit backend config so you don't accidentally point dev state at prod state.

```bash
cd environments/dev

terraform init \
  -backend-config="bucket=tfstate-${PROJECT_ID}" \
  -backend-config="prefix=genai-rag/dev"

terraform plan -var "project_id=${PROJECT_ID}" -out=tfplan
terraform apply tfplan
```

## Promotion model

`dev` → `staging` → `prod`. Every change goes through dev first. Staging exists to catch issues that only manifest under production sizing (HA Redis vs basic, AlloyDB replica behavior under read load, etc.). Prod is gated behind a manual approval step in the `deploy-prod` GitHub Actions workflow.

## Drift detection

`scripts/drift-check.sh` runs `terraform plan` against all three environments and reports any non-empty plan. Wire it into a daily GitHub Actions cron — drift is cheaper to catch early.

## Module conventions

- Every module takes `project_id`, `region`, `name_prefix`, and `labels`.
- Every module exports its primary resource id and any URLs/connection strings the application needs.
- Sensitive outputs are marked `sensitive = true`.
- No module reaches out of its scope — composition happens in `main.tf`.
