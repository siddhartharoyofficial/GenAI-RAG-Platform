###############################################################################
# External HTTPS Load Balancer + Cloud Armor in front of the Cloud Run service.
# (For a richer OpenAPI-style gateway, swap to google_api_gateway_gateway with
# an OpenAPI spec — left as a follow-up to keep this module tractable.)
###############################################################################

resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name                  = "${var.name_prefix}-cr-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = element(split("/", var.backend_url), length(split("/", var.backend_url)) - 1)
  }
}

resource "google_compute_backend_service" "backend" {
  name                  = "${var.name_prefix}-backend"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg.id
  }

  security_policy = google_compute_security_policy.armor.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "url_map" {
  name            = "${var.name_prefix}-urlmap"
  project         = var.project_id
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_managed_ssl_certificate" "cert" {
  count   = var.domain_name == "" ? 0 : 1
  name    = "${var.name_prefix}-cert"
  project = var.project_id

  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_target_https_proxy" "https" {
  count            = var.domain_name == "" ? 0 : 1
  name             = "${var.name_prefix}-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cert[0].id]
}

resource "google_compute_target_http_proxy" "http" {
  count   = var.domain_name == "" ? 1 : 0
  name    = "${var.name_prefix}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_address" "ip" {
  name    = "${var.name_prefix}-lb-ip"
  project = var.project_id
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain_name == "" ? 0 : 1
  name                  = "${var.name_prefix}-https-fr"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.https[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.ip.address
}

resource "google_compute_global_forwarding_rule" "http" {
  count                 = var.domain_name == "" ? 1 : 0
  name                  = "${var.name_prefix}-http-fr"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.http[0].id
  port_range            = "80"
  ip_address            = google_compute_global_address.ip.address
}

# Cloud Armor — baseline WAF: OWASP top 10 ruleset + per-IP rate limit.
resource "google_compute_security_policy" "armor" {
  name    = "${var.name_prefix}-armor"
  project = var.project_id

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQLi"
  }

  rule {
    action   = "rate_based_ban"
    priority = 2000
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Rate limit 100 rpm per IP"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
