###############################################################################
# Memorystore for Redis — semantic cache + session memory.
# STANDARD_HA gives an automatic-failover replica across zones.
###############################################################################

resource "google_redis_instance" "cache" {
  name           = "${var.name_prefix}-redis"
  project        = var.project_id
  region         = var.region
  tier           = var.tier
  memory_size_gb = var.memory_size_gb

  redis_version     = "REDIS_7_2"
  display_name      = "GenAI RAG semantic cache and session memory"
  reserved_ip_range = null

  authorized_network      = var.network_id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  auth_enabled            = true

  redis_configs = {
    # Eviction strategy tuned for cache-first workloads.
    "maxmemory-policy"       = "allkeys-lru"
    "notify-keyspace-events" = "Ex"
  }

  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "ONE_HOUR"
  }

  labels = var.labels

  lifecycle {
    # Replacement causes data loss; require explicit operator action.
    prevent_destroy = false
  }
}
