###############################################################################
# Vertex AI — endpoint for the cross-encoder reranker.
# The intent router and synthesis LLMs are called directly via the Vertex AI
# generative APIs; only the reranker needs a dedicated endpoint.
###############################################################################

resource "google_vertex_ai_endpoint" "reranker" {
  name         = "${var.name_prefix}-reranker"
  display_name = "Cross-encoder reranker (top 50 -> top 5)"
  location     = var.region
  project      = var.project_id
  labels       = var.labels

  network = null # Public access; restrict via service account auth.
}

# Note: Deploying a specific model to the endpoint is done out of band — either
# via Model Garden console for partner models (Cohere, Mistral) or via
# `gcloud ai endpoints deploy-model` for self-uploaded models. We expose the
# endpoint id so the application can target it.

# Artifact Registry repo for container images.
resource "google_artifact_registry_repository" "containers" {
  repository_id = "genai-rag"
  project       = var.project_id
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for the GenAI RAG platform"

  labels = var.labels

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }
}
