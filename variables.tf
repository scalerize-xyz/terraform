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

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-central1"]
}

variable "database_password" {
  type = string
}

variable "ethereum_rpc_url" {
  type = string
}
