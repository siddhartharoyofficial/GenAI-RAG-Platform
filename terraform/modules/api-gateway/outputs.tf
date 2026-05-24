output "gateway_url" {
  value = var.domain_name == "" ? "http://${google_compute_global_address.ip.address}" : "https://${var.domain_name}"
}

output "gateway_ip" {
  value = google_compute_global_address.ip.address
}
