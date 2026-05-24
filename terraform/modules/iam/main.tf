###############################################################################
# IAM — service accounts with least-privilege bindings + Workload Identity glue.
###############################################################################

# GKE node service account (Autopilot still respects bindings on this SA).
resource "google_service_account" "gke_node" {
  account_id   = "${var.name_prefix}-gke-node"
  display_name = "GKE node service account"
  project      = var.project_id
}

# Cloud Run service account for the intent router.
resource "google_service_account" "cloud_run" {
  account_id   = "${var.name_prefix}-cloud-run"
  display_name = "Cloud Run intent router"
  project      = var.project_id
}

# Application service account used by the API workload via Workload Identity.
resource "google_service_account" "app" {
  account_id   = "${var.name_prefix}-app"
  display_name = "GenAI RAG application identity"
  project      = var.project_id
}

# --- Application SA bindings ---
locals {
  app_roles = [
    "roles/aiplatform.user",
    "roles/secretmanager.secretAccessor",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/redis.editor",
    "roles/alloydb.databaseUser",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "app_bindings" {
  for_each = toset(local.app_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.app.email}"
}

# Workload Identity: allow the KSA `genai-rag/api` to impersonate the GSA.
resource "google_service_account_iam_member" "wi_binding" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[genai-rag/api]"
}

# --- Cloud Run SA: lighter footprint ---
resource "google_project_iam_member" "cloud_run_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}
