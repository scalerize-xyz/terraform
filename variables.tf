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

variable "rpc_url" {
  type        = string
  description = "RPC URL for the Ethereum node"
  default     = "http://localhost:8545"
}

variable "private_key" {
  type        = string
  description = "Private key for the faucet"
  sensitive   = true
  default     = "b4f6c92d12dcaa5dde866306ba3bf13ee6a2f93579b9b5659df84e55043473cc"
}

variable "faucet_amount" {
  type        = number
  description = "Amount to send from the faucet"
  default     = 0.1
}