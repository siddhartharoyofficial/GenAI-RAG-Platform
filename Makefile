# GenAI RAG Platform — Common dev targets
#
# Usage: make <target>
#
# Variables you can override:
#   PROJECT_ID  GCP project id
#   REGION      GCP region (default: us-central1)
#   ENV         Target environment (dev/staging/prod)

PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
REGION     ?= us-central1
ENV        ?= dev
IMAGE_TAG  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo latest)
IMAGE_REPO  = $(REGION)-docker.pkg.dev/$(PROJECT_ID)/genai-rag/api
TF_DIR      = terraform/environments/$(ENV)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# -----------------------------------------------------------------------------
# Python / application targets
# -----------------------------------------------------------------------------

.PHONY: install
install: ## Install Python dependencies
	pip install -r requirements/requirements.txt
	pip install -r requirements/requirements-dev.txt

.PHONY: lint
lint: ## Run linters (ruff, black --check, mypy)
	ruff check src tests
	black --check src tests
	mypy src

.PHONY: format
format: ## Auto-format Python code
	black src tests
	ruff check --fix src tests

.PHONY: test
test: ## Run unit and integration tests
	pytest tests/unit tests/integration -v

.PHONY: eval
eval: ## Run Ragas evaluation suite
	pytest tests/evaluation -v --no-header

# -----------------------------------------------------------------------------
# Terraform targets
# -----------------------------------------------------------------------------

.PHONY: tf-init
tf-init: ## terraform init for the selected environment
	cd $(TF_DIR) && terraform init -reconfigure

.PHONY: tf-fmt
tf-fmt: ## terraform fmt (recursive)
	terraform fmt -recursive terraform

.PHONY: tf-validate
tf-validate: ## terraform validate
	cd $(TF_DIR) && terraform validate

.PHONY: tf-plan
tf-plan: ## terraform plan
	cd $(TF_DIR) && terraform plan -out=tfplan

.PHONY: tf-apply
tf-apply: ## terraform apply (uses saved plan if present)
	cd $(TF_DIR) && terraform apply tfplan

.PHONY: tf-destroy
tf-destroy: ## terraform destroy (DANGEROUS — uses -auto-approve gate)
	cd $(TF_DIR) && terraform plan -destroy -out=tfplan-destroy
	@echo "Review the plan above. To proceed: cd $(TF_DIR) && terraform apply tfplan-destroy"

# -----------------------------------------------------------------------------
# Docker / image targets
# -----------------------------------------------------------------------------

.PHONY: docker-build
docker-build: ## Build the API container image
	docker build -t $(IMAGE_REPO):$(IMAGE_TAG) -f docker/Dockerfile .

.PHONY: docker-push
docker-push: docker-build ## Push image to Artifact Registry
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet
	docker push $(IMAGE_REPO):$(IMAGE_TAG)

# -----------------------------------------------------------------------------
# Kubernetes targets
# -----------------------------------------------------------------------------

.PHONY: k8s-deploy
k8s-deploy: ## Apply Kustomize overlay for $(ENV)
	kubectl apply -k k8s/overlays/$(ENV)

.PHONY: k8s-status
k8s-status: ## Show deployment status
	kubectl -n genai-rag get pods,svc,ingress

# -----------------------------------------------------------------------------
# Composite
# -----------------------------------------------------------------------------

.PHONY: ci
ci: lint test tf-fmt tf-validate ## Run everything CI runs

.PHONY: bootstrap
bootstrap: ## One-time bootstrap (state bucket, API enablement)
	./scripts/bootstrap.sh

.PHONY: deploy
deploy: tf-plan tf-apply docker-push k8s-deploy ## Full deploy for $(ENV)
