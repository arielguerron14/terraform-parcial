variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 6
}

variable "asg_desired" {
  type    = number
  default = 6
}

variable "ssh_key_name" {
  type        = string
  default     = "recuperacion"
  description = "Nombre de key pair para acceso SSH a las instancias EC2. Si se crea a partir de 'ssh_public_key', se usará este nombre."
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "(Opcional) Clave pública SSH. Si se provee, Terraform creará un key pair con el nombre `ssh_key_name` usando esta clave pública."
}

variable "existing_vpc_id" {
  type        = string
  default     = ""
  description = "(Opcional) Si se proporciona, Terraform usará este VPC en lugar de crear uno nuevo."
}
