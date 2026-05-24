output "network_id" {
  description = "VPC network resource id."
  value       = module.network.network_id
}

output "gke_cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint."
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "redis_host" {
  description = "Memorystore Redis primary endpoint."
  value       = module.memorystore_redis.host
  sensitive   = true
}

output "redis_port" {
  description = "Memorystore Redis port."
  value       = module.memorystore_redis.port
}

output "alloydb_primary_uri" {
  description = "AlloyDB primary connection URI."
  value       = module.alloydb.primary_uri
  sensitive   = true
}

output "vertex_endpoint_id" {
  description = "Vertex AI endpoint id hosting the reranker."
  value       = module.vertex_ai.reranker_endpoint_id
}

output "api_gateway_url" {
  description = "Public URL of the API Gateway."
  value       = module.api_gateway.gateway_url
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository for container images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/genai-rag"
}
