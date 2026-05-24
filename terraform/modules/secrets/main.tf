###############################################################################
# Secret Manager — placeholders for runtime credentials.
# Values are populated out of band (CI/CD or a one-time bootstrap secret push).
###############################################################################

locals {
  secrets = {
    cohere_api_key   = "Cohere API key for reranker fallback"
    anthropic_api_key = "Anthropic API key for Claude (only if not using Vertex Model Garden)"
    openai_api_key    = "OpenAI API key for GPT-4o (optional fallback)"
    langsmith_api_key = "LangSmith API key for tracing"
  }
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secrets

  secret_id = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = merge(var.labels, {
    secret_purpose = each.key
  })
}
