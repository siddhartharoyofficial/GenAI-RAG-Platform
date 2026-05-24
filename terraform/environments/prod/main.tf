###############################################################################
# Production environment composition.
#
# Initialize with:
#   terraform init \
#     -backend-config="bucket=tfstate-${PROJECT_ID}" \
#     -backend-config="prefix=genai-rag/prod"
###############################################################################

module "platform" {
  source = "../../"

  project_id  = var.project_id
  region      = var.region
  environment = "prod"

  redis_tier        = "STANDARD_HA"
  redis_memory_gb   = 10
  alloydb_cpu_count = 8

  api_image   = var.api_image
  domain_name = var.domain_name
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "api_image" { type = string }
variable "domain_name" { type = string }

terraform {
  required_version = ">= 1.7.0"

  backend "gcs" {}

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
