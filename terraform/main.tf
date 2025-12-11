provider "aws" {
  region = var.region
}

# Use specified AMI ID
locals {
  ami_id = "ami-0c19292331f6e3a5c"
}

data "aws_availability_zones" "azs" {}

# Create a stable map of public subnets so we can index AZs reliably
locals {
  subnet_map = { for idx, cidr in var.public_subnets : tostring(idx) => cidr }
  vpc_id     = var.existing_vpc_id != "" ? var.existing_vpc_id : (length(aws_vpc.main) > 0 ? aws_vpc.main[0].id : "")
}

# VPC
resource "aws_vpc" "main" {
  count                = var.existing_vpc_id == "" ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "lab-vpc" }
}

# Subnets
resource "aws_subnet" "public" {
  for_each = local.subnet_map

  vpc_id                  = local.vpc_id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.azs.names[tonumber(each.key) % length(data.aws_availability_zones.azs.names)]
  tags = { Name = "public-${each.value}" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  count = var.existing_vpc_id == "" ? 1 : 0
  vpc_id = local.vpc_id
}

# Route Table
resource "aws_route_table" "public" {
  count  = var.existing_vpc_id == "" ? 1 : 0
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
}

# Associations
resource "aws_route_table_association" "public_assoc" {
  for_each       = length(aws_route_table.public) > 0 ? aws_subnet.public : {}
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name   = "web-sg"
  vpc_id = local.vpc_id

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

# User Data
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

# Optionally create key pair from provided public key
resource "aws_key_pair" "default" {
  count = var.ssh_public_key != "" ? 1 : 0
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
}

# Launch Template
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
  vpc_id   = local.vpc_id

  health_check {
    path = "/"
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

# ASG
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

