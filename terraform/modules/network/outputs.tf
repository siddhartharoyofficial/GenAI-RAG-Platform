output "network_id" {
  value       = google_compute_network.vpc.id
  description = "VPC network id."
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "VPC network name."
}

output "apps_subnet_id" {
  value       = google_compute_subnetwork.apps.id
  description = "Apps subnet id."
}

output "data_subnet_id" {
  value       = google_compute_subnetwork.data.id
  description = "Data subnet id."
}

output "gke_pods_range_name" {
  value       = "${var.name_prefix}-gke-pods"
  description = "Secondary range name for GKE pods."
}

output "gke_services_range_name" {
  value       = "${var.name_prefix}-gke-services"
  description = "Secondary range name for GKE services."
}

output "serverless_connector_id" {
  value       = google_vpc_access_connector.connector.id
  description = "Serverless VPC Access connector id."
}

output "psa_connection" {
  value       = google_service_networking_connection.psa.id
  description = "Private Service Access connection id."
}
