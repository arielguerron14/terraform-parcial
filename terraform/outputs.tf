output "alb_dns_name" {
	description = "DNS name of the Application Load Balancer"
	value       = aws_lb.alb.dns_name
}

output "vpc_id" {
	description = "ID of the created VPC"
	value       = aws_vpc.main.id
}

output "asg_name" {
	description = "Name of the Auto Scaling Group"
	value       = aws_autoscaling_group.asg.name
}
