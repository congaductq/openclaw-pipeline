variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "bundle_id" {
  description = "Lightsail bundle (plan) ID"
  type        = string
  default     = "medium_3_0" # $20/mo — 4GB RAM, 2 vCPU, 80GB SSD
}

variable "blueprint_id" {
  description = "Lightsail blueprint (OS) ID"
  type        = string
  default     = "amazon_linux_2023"
}

variable "public_key_path" {
  description = "Path to SSH public key for Lightsail import"
  type        = string
  default     = "~/.ssh/openclaw-ls.pub"
}

variable "private_key_path" {
  description = "Path to SSH private key (for output reference)"
  type        = string
  default     = "~/.ssh/openclaw-ls"
}

variable "gateway_port" {
  description = "OpenClaw gateway port"
  type        = number
  default     = 18789
}

variable "deployment_name" {
  description = "Unique deployment name (e.g., 'main', 'claude', 'gemini', 'server')"
  type        = string
  default     = "main"
}
