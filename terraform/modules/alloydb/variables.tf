variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "network_id" { type = string }

variable "cpu_count" {
  type    = number
  default = 4
}

variable "database_name" {
  type    = string
  default = "ragdb"
}

variable "labels" {
  type    = map(string)
  default = {}
}
