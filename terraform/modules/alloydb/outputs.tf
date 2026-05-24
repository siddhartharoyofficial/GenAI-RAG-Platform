output "cluster_name" {
  value = google_alloydb_cluster.primary.name
}

output "primary_uri" {
  value     = google_alloydb_instance.primary.ip_address
  sensitive = true
}

output "replica_uri" {
  value     = google_alloydb_instance.replica.ip_address
  sensitive = true
}

output "password_secret_id" {
  value = google_secret_manager_secret.alloydb_password.id
}
