output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.devopsai.id
}

output "public_ip" {
  description = "Static public IP (Elastic IP) — use this for GoDaddy A record"
  value       = aws_eip.devopsai_eip.public_ip
}

output "public_dns" {
  description = "Public DNS of the instance"
  value       = aws_instance.devopsai.public_dns
}
