terraform {
  required_version = ">= 1.0"
  
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "staging"
}

variable "region" {
  description = "Cloud region"
  type        = string
  default     = "nyc3"
}

variable "instance_size" {
  description = "Droplet/instance size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "ssh_key_id" {
  description = "SSH key ID for server access"
  type        = string
}

variable "anthropic_api_key" {
  description = "Anthropic API key"
  type        = string
  sensitive   = true
}

variable "openclaw_gateway_token" {
  description = "OpenClaw gateway token"
  type        = string
  sensitive   = true
}

# DigitalOcean Deployment
provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "openclaw" {
  count  = var.cloud_provider == "digitalocean" ? 1 : 0
  
  name   = "openclaw-${var.environment}"
  region = var.region
  size   = var.instance_size
  image  = "ubuntu-24-04-x64"
  
  ssh_keys = [var.ssh_key_id]
  
  tags = [
    "openclaw",
    "environment:${var.environment}",
    "managed-by:terraform"
  ]
  
  user_data = templatefile("${path.module}/cloud-init.yml", {
    anthropic_api_key      = var.anthropic_api_key
    gateway_token          = var.openclaw_gateway_token
    environment            = var.environment
  })
  
  monitoring = true
  ipv6       = true
  
  lifecycle {
    create_before_destroy = true
  }
}

# Firewall rules
resource "digitalocean_firewall" "openclaw" {
  count = var.cloud_provider == "digitalocean" ? 1 : 0
  
  name = "openclaw-${var.environment}"
  
  droplet_ids = [digitalocean_droplet.openclaw[0].id]
  
  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_ips
  }
  
  # OpenClaw Gateway (restricted)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "18789"
    source_addresses = var.allowed_ips
  }
  
  # Allow all outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Volume for persistent storage
resource "digitalocean_volume" "openclaw_data" {
  count = var.cloud_provider == "digitalocean" ? 1 : 0
  
  region                  = var.region
  name                    = "openclaw-data-${var.environment}"
  size                    = 50
  initial_filesystem_type = "ext4"
  description             = "OpenClaw persistent data storage"
}

resource "digitalocean_volume_attachment" "openclaw_data" {
  count = var.cloud_provider == "digitalocean" ? 1 : 0
  
  droplet_id = digitalocean_droplet.openclaw[0].id
  volume_id  = digitalocean_volume.openclaw_data[0].id
}

# AWS Deployment (alternative)
provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "openclaw" {
  count = var.cloud_provider == "aws" ? 1 : 0
  
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  key_name = var.aws_key_name
  
  vpc_security_group_ids = [aws_security_group.openclaw[0].id]
  subnet_id              = var.subnet_id
  
  user_data = templatefile("${path.module}/cloud-init.yml", {
    anthropic_api_key = var.anthropic_api_key
    gateway_token     = var.openclaw_gateway_token
    environment       = var.environment
  })
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }
  
  tags = {
    Name        = "openclaw-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  
  monitoring = true
  
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-24.04-amd64-server-*"]
  }
}

resource "aws_security_group" "openclaw" {
  count = var.cloud_provider == "aws" ? 1 : 0
  
  name        = "openclaw-${var.environment}"
  description = "Security group for OpenClaw"
  vpc_id      = var.vpc_id
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ips
  }
  
  ingress {
    description = "OpenClaw Gateway"
    from_port   = 18789
    to_port     = 18789
    protocol    = "tcp"
    cidr_blocks = var.allowed_ips
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "openclaw-${var.environment}"
  }
}

# Elastic IP for stable addressing
resource "aws_eip" "openclaw" {
  count = var.cloud_provider == "aws" ? 1 : 0
  
  instance = aws_instance.openclaw[0].id
  domain   = "vpc"
  
  tags = {
    Name = "openclaw-${var.environment}"
  }
}

# CloudWatch monitoring
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.cloud_provider == "aws" ? 1 : 0
  
  alarm_name          = "openclaw-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  
  dimensions = {
    InstanceId = aws_instance.openclaw[0].id
  }
}

# Outputs
output "server_ip" {
  description = "Server public IP address"
  value = var.cloud_provider == "digitalocean" ? (
    digitalocean_droplet.openclaw[0].ipv4_address
  ) : (
    aws_eip.openclaw[0].public_ip
  )
}

output "gateway_url" {
  description = "OpenClaw gateway URL"
  value       = "http://${var.cloud_provider == "digitalocean" ? digitalocean_droplet.openclaw[0].ipv4_address : aws_eip.openclaw[0].public_ip}:18789"
}

output "ssh_connection" {
  description = "SSH connection command"
  value = var.cloud_provider == "digitalocean" ? (
    "ssh root@${digitalocean_droplet.openclaw[0].ipv4_address}"
  ) : (
    "ssh ubuntu@${aws_eip.openclaw[0].public_ip}"
  )
}
