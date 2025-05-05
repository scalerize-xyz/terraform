variable "credential_path" {
  type = string
}

variable "user" {
  type = string
}

variable "no_of_nodes" {
  type = number
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-central1"]
}

variable "external_ips" {
  type = list(string)
}