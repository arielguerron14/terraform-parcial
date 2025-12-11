output "security_group_id" {
  value       = aws_security_group.web_sg.id
  description = "Security Group ID for web traffic. Use this SG when launching EC2 instances."
}

output "security_group_name" {
  value       = aws_security_group.web_sg.name
  description = "Security Group name"
}

