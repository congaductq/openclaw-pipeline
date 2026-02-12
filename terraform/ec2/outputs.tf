output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "public_ip" {
  description = "Public IP address"
  value       = var.use_elastic_ip ? aws_eip.openclaw[0].public_ip : aws_instance.openclaw.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_instance.openclaw.public_dns
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${var.use_elastic_ip ? aws_eip.openclaw[0].public_ip : aws_instance.openclaw.public_ip}"
}

output "dashboard_url" {
  description = "OpenClaw dashboard URL"
  value       = "http://${var.use_elastic_ip ? aws_eip.openclaw[0].public_ip : aws_instance.openclaw.public_ip}:${var.gateway_port}"
}
