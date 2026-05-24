variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "service_name" { type = string }
variable "image" { type = string }
variable "service_account" { type = string }
variable "vpc_connector" { type = string }

variable "labels" {
  type    = map(string)
  default = {}
}
