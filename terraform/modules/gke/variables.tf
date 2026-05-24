variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "network_id" { type = string }
variable "subnet_id" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "release_channel" {
  type    = string
  default = "REGULAR"
}
variable "service_account" {
  type        = string
  description = "Email of the GKE node service account (Autopilot uses this for any user-managed bindings)."
}
variable "environment_protection" {
  type    = bool
  default = false
}
variable "labels" {
  type    = map(string)
  default = {}
}
