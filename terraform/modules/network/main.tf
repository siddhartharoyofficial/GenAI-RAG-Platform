###############################################################################
# Network module — VPC, subnets, secondary ranges, NAT, Service Connect range,
# Serverless VPC Access connector for Cloud Run.
###############################################################################

resource "google_compute_network" "vpc" {
  name                            = "${var.name_prefix}-vpc"
  project                         = var.project_id
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "apps" {
  name          = "${var.name_prefix}-apps"
  project       = var.project_id
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = var.network_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.name_prefix}-gke-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name_prefix}-gke-services"
    ip_cidr_range = var.gke_services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "data" {
  name                     = "${var.name_prefix}-data"
  project                  = var.project_id
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.data_subnet_cidr
  private_ip_google_access = true
}

# Private Service Connect range for AlloyDB / Memorystore.
resource "google_compute_global_address" "psa_range" {
  name          = "${var.name_prefix}-psa-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
}

# Cloud NAT for egress from private nodes.
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Serverless VPC Access connector — lets Cloud Run reach private resources.
resource "google_vpc_access_connector" "connector" {
  name          = substr("${var.name_prefix}-conn", 0, 25)
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 5
  machine_type  = "e2-micro"
}

# Allow internal traffic between subnets.
resource "google_compute_firewall" "allow_internal" {
  name      = "${var.name_prefix}-allow-internal"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    var.network_cidr,
    var.data_subnet_cidr,
    var.gke_pods_cidr,
    var.gke_services_cidr,
  ]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}
