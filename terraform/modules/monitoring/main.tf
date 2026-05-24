###############################################################################
# Observability — notification channel + alert policies + uptime check.
###############################################################################

resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.name_prefix} email channel"
  project      = var.project_id
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
  user_labels = var.labels
}

resource "google_monitoring_alert_policy" "high_latency" {
  display_name = "${var.name_prefix} — API p95 latency > 1.5s"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "API p95 latency"
    condition_threshold {
      filter          = "metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\" resource.type=\"https_lb_rule\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1500
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "API p95 latency has exceeded 1.5s for 5 minutes. Check semantic cache hit rate and LLM endpoint latency."
    mime_type = "text/markdown"
  }

  user_labels = var.labels
}

resource "google_monitoring_alert_policy" "low_cache_hit_rate" {
  display_name = "${var.name_prefix} — semantic cache hit rate < 20%"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Cache hit ratio"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/genai_rag/cache_hit_ratio\" resource.type=\"k8s_container\""
      duration        = "900s"
      comparison      = "COMPARISON_LT"
      threshold_value = 0.20
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "Cache hit ratio has dropped below 20% for 15 minutes. Suggests semantic drift or threshold misconfiguration."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_dashboard" "overview" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} — GenAI RAG overview"
    gridLayout = {
      widgets = [
        {
          title = "Request rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"loadbalancing.googleapis.com/https/request_count\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE" }
                }
              }
            }]
          }
        },
        {
          title = "p50 / p95 latency"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95" }
                }
              }
            }]
          }
        },
      ]
    }
  })
}
