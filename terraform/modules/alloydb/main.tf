###############################################################################
# AlloyDB for PostgreSQL — primary cluster with one read replica.
# Hosts pgvector (HNSW index) plus relational session memory and the BM25 FTS.
###############################################################################

resource "random_password" "alloydb" {
  length  = 24
  special = true
}

resource "google_secret_manager_secret" "alloydb_password" {
  secret_id = "${var.name_prefix}-alloydb-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "alloydb_password" {
  secret      = google_secret_manager_secret.alloydb_password.id
  secret_data = random_password.alloydb.result
}

resource "google_alloydb_cluster" "primary" {
  cluster_id = "${var.name_prefix}-alloydb"
  location   = var.region
  project    = var.project_id

  network_config {
    network = var.network_id
  }

  initial_user {
    user     = "postgres"
    password = random_password.alloydb.result
  }

  database_version = "POSTGRES_15"

  automated_backup_policy {
    location      = var.region
    backup_window = "1800s"
    enabled       = true
    weekly_schedule {
      days_of_week = ["MONDAY", "WEDNESDAY", "FRIDAY"]
      start_times {
        hours   = 4
        minutes = 0
      }
    }
    quantity_based_retention {
      count = 14
    }
  }

  labels = var.labels
}

resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.primary.name
  instance_id   = "${var.name_prefix}-alloydb-primary"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.cpu_count
  }

  database_flags = {
    "alloydb.iam_authentication" = "on"
    # Enable extensions on first start.
    "alloydb.enable_pgaudit" = "on"
  }

  labels = var.labels
}

resource "google_alloydb_instance" "replica" {
  cluster       = google_alloydb_cluster.primary.name
  instance_id   = "${var.name_prefix}-alloydb-replica"
  instance_type = "READ_POOL"

  read_pool_config {
    node_count = 1
  }

  machine_config {
    cpu_count = var.cpu_count
  }

  depends_on = [google_alloydb_instance.primary]

  labels = var.labels
}
