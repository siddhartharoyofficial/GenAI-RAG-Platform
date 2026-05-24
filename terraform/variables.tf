variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "Primary GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev / staging / prod). Used as a label and name suffix."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "labels" {
  description = "Common labels applied to all resources that support them."
  type        = map(string)
  default = {
    project = "genai-rag-platform"
    owner   = "platform-eng"
  }
}

# --- Network ---
variable "network_cidr" {
  description = "Primary CIDR for the apps subnet."
  type        = string
  default     = "10.10.0.0/20"
}

variable "data_subnet_cidr" {
  description = "CIDR for the data plane subnet (AlloyDB, Memorystore PSC)."
  type        = string
  default     = "10.10.16.0/20"
}

variable "gke_pods_cidr" {
  description = "Secondary range for GKE pods."
  type        = string
  default     = "10.20.0.0/14"
}

variable "gke_services_cidr" {
  description = "Secondary range for GKE services."
  type        = string
  default     = "10.24.0.0/20"
}

# --- GKE ---
variable "gke_release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"
}

# --- Memorystore Redis ---
variable "redis_tier" {
  description = "Memorystore Redis service tier (BASIC or STANDARD_HA)."
  type        = string
  default     = "STANDARD_HA"
}

variable "redis_memory_gb" {
  description = "Memorystore Redis capacity in GB."
  type        = number
  default     = 5
}

# --- AlloyDB ---
variable "alloydb_cpu_count" {
  description = "vCPU count for AlloyDB primary instance."
  type        = number
  default     = 4
}

variable "alloydb_database_name" {
  description = "AlloyDB database name."
  type        = string
  default     = "ragdb"
}

# --- Vertex AI ---
variable "reranker_model_uri" {
  description = "GCS URI or Model Garden ID for the reranker model deployed to a Vertex AI endpoint."
  type        = string
  default     = "publishers/cohere/models/rerank-multilingual-v3.0"
}

# --- API / app ---
variable "api_image" {
  description = "Container image (with tag) for the API service."
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/genai-rag/api:latest"
}

variable "domain_name" {
  description = "Optional public hostname for the external load balancer. Empty means no managed cert."
  type        = string
  default     = ""
}
