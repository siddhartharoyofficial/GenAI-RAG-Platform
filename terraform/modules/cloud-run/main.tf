###############################################################################
# Cloud Run — used for the lightweight intent router (latency-sensitive,
# stateless, scales to zero off-peak).
###############################################################################

resource "google_cloud_run_v2_service" "service" {
  name     = "${var.name_prefix}-${var.service_name}"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.service_account

    scaling {
      min_instance_count = 1
      max_instance_count = 50
    }

    vpc_access {
      connector = var.vpc_connector
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "SERVICE_ROLE"
        value = "intent-router"
      }

      env {
        name  = "OTEL_EXPORTER"
        value = "gcp-trace"
      }

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get { path = "/healthz" }
        period_seconds        = 10
        initial_delay_seconds = 5
      }
      startup_probe {
        http_get { path = "/healthz" }
        period_seconds    = 5
        failure_threshold = 6
      }
    }

    timeout = "30s"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = var.labels
}
