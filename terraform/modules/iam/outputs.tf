output "gke_node_service_account" {
  value = google_service_account.gke_node.email
}

output "cloud_run_service_account" {
  value = google_service_account.cloud_run.email
}

output "app_service_account" {
  value = google_service_account.app.email
}
