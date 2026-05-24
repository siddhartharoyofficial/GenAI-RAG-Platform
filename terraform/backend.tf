# Remote state in GCS.
#
# The bucket itself is created by scripts/bootstrap.sh before this is applied.
# Each environment overrides the `prefix` via -backend-config during init.
terraform {
  backend "gcs" {
    # bucket = "tfstate-<project-id>"   # set by environment-specific backend config
    # prefix = "genai-rag/<env>"        # set by environment-specific backend config
  }
}
