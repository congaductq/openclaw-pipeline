output "instance_name" {
  description = "Lightsail instance name"
  value       = aws_lightsail_instance.openclaw.name
}

output "public_ip" {
  description = "Public IP address (static)"
  value       = aws_lightsail_static_ip.openclaw.ip_address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_lightsail_static_ip.openclaw.ip_address}"
}

output "dashboard_url" {
  description = "OpenClaw dashboard URL"
  value       = "http://${aws_lightsail_static_ip.openclaw.ip_address}:${var.gateway_port}"
}
