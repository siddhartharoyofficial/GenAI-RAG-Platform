variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "network_cidr" { type = string }
variable "data_subnet_cidr" { type = string }
variable "gke_pods_cidr" { type = string }
variable "gke_services_cidr" { type = string }

variable "labels" {
  type    = map(string)
  default = {}
}
