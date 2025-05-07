variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID"
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key"
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

variable "elastic_ip_allocation_ids" {
  type        = list(string)
}

variable "elastic_ip_allocation_ids_cidr" {
  type        = list(string)
  description = "List of CIDR blocks for Elastic IPs"
}