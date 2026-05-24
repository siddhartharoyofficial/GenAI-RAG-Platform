variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "reranker_model_uri" {
  type        = string
  description = "Model Garden publisher URI or GCS model URI to deploy as reranker."
}

variable "labels" {
  type    = map(string)
  default = {}
}
