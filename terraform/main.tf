###############################################################################
# Root composition — wires the platform modules together for one environment.
###############################################################################

locals {
  name_prefix = "genai-rag-${var.environment}"

  common_labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
  })

  required_services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "run.googleapis.com",
    "redis.googleapis.com",
    "alloydb.googleapis.com",
    "servicenetworking.googleapis.com",
    "aiplatform.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudtrace.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "apigateway.googleapis.com",
    "servicecontrol.googleapis.com",
    "servicemanagement.googleapis.com",
    "certificatemanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each           = toset(local.required_services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

###############################################################################
# Foundational modules
###############################################################################

module "network" {
  source = "./modules/network"

  project_id        = var.project_id
  region            = var.region
  name_prefix       = local.name_prefix
  network_cidr      = var.network_cidr
  data_subnet_cidr  = var.data_subnet_cidr
  gke_pods_cidr     = var.gke_pods_cidr
  gke_services_cidr = var.gke_services_cidr
  labels            = local.common_labels

  depends_on = [google_project_service.required]
}

module "iam" {
  source = "./modules/iam"

  project_id  = var.project_id
  name_prefix = local.name_prefix

  depends_on = [google_project_service.required]
}

module "secrets" {
  source = "./modules/secrets"

  project_id  = var.project_id
  name_prefix = local.name_prefix
  labels      = local.common_labels

  depends_on = [google_project_service.required]
}

###############################################################################
# Data plane
###############################################################################

module "memorystore_redis" {
  source = "./modules/memorystore-redis"

  project_id     = var.project_id
  region         = var.region
  name_prefix    = local.name_prefix
  network_id     = module.network.network_id
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_gb
  labels         = local.common_labels
}

module "alloydb" {
  source = "./modules/alloydb"

  project_id    = var.project_id
  region        = var.region
  name_prefix   = local.name_prefix
  network_id    = module.network.network_id
  cpu_count     = var.alloydb_cpu_count
  database_name = var.alloydb_database_name
  labels        = local.common_labels
}

###############################################################################
# Model plane
###############################################################################

module "vertex_ai" {
  source = "./modules/vertex-ai"

  project_id         = var.project_id
  region             = var.region
  name_prefix        = local.name_prefix
  reranker_model_uri = var.reranker_model_uri
  labels             = local.common_labels
}

###############################################################################
# Compute plane
###############################################################################

module "gke" {
  source = "./modules/gke"

  project_id          = var.project_id
  region              = var.region
  name_prefix         = local.name_prefix
  network_id          = module.network.network_id
  subnet_id           = module.network.apps_subnet_id
  pods_range_name     = module.network.gke_pods_range_name
  services_range_name = module.network.gke_services_range_name
  release_channel     = var.gke_release_channel
  service_account     = module.iam.gke_node_service_account
  labels              = local.common_labels
}

module "cloud_run_router" {
  source = "./modules/cloud-run"

  project_id      = var.project_id
  region          = var.region
  name_prefix     = local.name_prefix
  service_name    = "intent-router"
  image           = var.api_image
  service_account = module.iam.cloud_run_service_account
  vpc_connector   = module.network.serverless_connector_id
  labels          = local.common_labels
}

module "api_gateway" {
  source = "./modules/api-gateway"

  project_id  = var.project_id
  region      = var.region
  name_prefix = local.name_prefix
  backend_url = module.cloud_run_router.service_url
  domain_name = var.domain_name
  labels      = local.common_labels
}

###############################################################################
# Observability
###############################################################################

module "monitoring" {
  source = "./modules/monitoring"

  project_id         = var.project_id
  name_prefix        = local.name_prefix
  notification_email = "platform-oncall@example.com"
  labels             = local.common_labels
}
