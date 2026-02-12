variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM - good for OpenClaw
}

variable "key_name" {
  description = "SSH key pair name (must exist in AWS)"
  type        = string
}

variable "gateway_port" {
  description = "OpenClaw gateway port"
  type        = number
  default     = 18789
}

variable "volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 30  # Amazon Linux 2023 requires minimum 30GB
}

variable "deployment_name" {
  description = "Unique deployment name (e.g., 'claude', 'gemini', 'prod')"
  type        = string
  default     = "main"
}

variable "use_elastic_ip" {
  description = "Allocate Elastic IP (static IP)"
  type        = bool
  default     = true
}
