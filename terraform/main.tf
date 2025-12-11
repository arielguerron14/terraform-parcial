provider "aws" {
  region = var.region
}

# Use specified AMI ID instead of searching
locals {
  ami_id = "ami-0c19292331f6e3a5c"
  # Hardcoded AZs for us-east-1 to avoid permission errors with DescribeAvailabilityZones
  availability_zones = ["us-east-1a", "us-east-1b"]
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "lab-vpc" }
}

# Subnets
resource "aws_subnet" "public" {
  # Use a map with indexes so we can assign different AZs to each subnet
  for_each = { for idx, cidr in var.public_subnets : tostring(idx) => cidr }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  # Assign one AZ per subnet using the index key
  availability_zone       = local.availability_zones[tonumber(each.key)]
  tags = { Name = "public-${each.value}" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associations
resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# User Data simple
locals {
  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd
systemctl enable httpd
systemctl start httpd
echo "<h1>Hola desde EC2 $(hostname)</h1>" > /var/www/html/index.html
EOF
}

# Launch Template sin IAM
resource "aws_launch_template" "lt" {
  name_prefix   = "lab-lt-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data = base64encode(local.user_data)

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }
}

# Load Balancer
resource "aws_lb" "alb" {
  name               = "lab-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "lab-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ASG sin IAM
resource "aws_autoscaling_group" "asg" {
  name               = "lab-asg"
  max_size           = var.asg_max
  min_size           = var.asg_min
  desired_capacity   = var.asg_desired
  vpc_zone_identifier = [for s in aws_subnet.public : s.id]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]
}
