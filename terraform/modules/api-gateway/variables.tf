variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "backend_url" { type = string }
variable "domain_name" {
  type    = string
  default = ""
}
variable "labels" {
  type    = map(string)
  default = {}
}
