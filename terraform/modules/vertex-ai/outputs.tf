output "reranker_endpoint_id" {
  value = google_vertex_ai_endpoint.reranker.name
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.containers.id
}
