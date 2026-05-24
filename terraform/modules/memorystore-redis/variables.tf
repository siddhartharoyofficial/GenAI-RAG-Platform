variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "network_id" { type = string }

variable "tier" {
  type    = string
  default = "STANDARD_HA"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "tier must be BASIC or STANDARD_HA."
  }
}

variable "memory_size_gb" {
  type    = number
  default = 5
}

variable "labels" {
  type    = map(string)
  default = {}
}
