###############################################################################
# Dev environment composition.
#
# Initialize with:
#   terraform init \
#     -backend-config="bucket=tfstate-${PROJECT_ID}" \
#     -backend-config="prefix=genai-rag/dev"
###############################################################################

module "platform" {
  source = "../../"

  project_id  = var.project_id
  region      = var.region
  environment = "dev"

  # Dev sizing — smaller, fewer replicas.
  redis_tier        = "BASIC"
  redis_memory_gb   = 2
  alloydb_cpu_count = 2

  api_image = var.api_image
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "api_image" {
  type    = string
  default = "us-central1-docker.pkg.dev/REPLACE_ME/genai-rag/api:latest"
}

terraform {
  required_version = ">= 1.7.0"

  backend "gcs" {
    # bucket and prefix set via -backend-config at init time
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.10"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

output "gateway_url" {
  value = module.platform.api_gateway_url
}

output "artifact_registry_repo" {
  value = module.platform.artifact_registry_repo
}
