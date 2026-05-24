###############################################################################
# GKE Autopilot — regional, private, Workload Identity enabled.
# Autopilot removes node pool management; nodes are provisioned by GKE.
###############################################################################

resource "google_container_cluster" "autopilot" {
  provider = google-beta

  name             = "${var.name_prefix}-gke"
  project          = var.project_id
  location         = var.region
  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all-internet"
    }
  }

  # Autopilot manages logging/monitoring by default — keep it explicit.
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "STORAGE",
      "POD",
      "DEPLOYMENT",
    ]
    managed_prometheus { enabled = true }
  }

  resource_labels = var.labels

  deletion_protection = var.environment_protection
}
