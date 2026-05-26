# terraform/variables.tf
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "ap"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "key_name" {
  type    = string
  default = "ap"
}

variable "allowed_ssh_cidr" {
  description = "Your IP: x.x.x.x/32"
  type        = string
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "backend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "monitoring_instance_type" {
  type    = string
  default = "t3.small"
}
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

# Without RDS
variable "db_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_password" {
  description = "Database password"
  type        = string
  default     = "db_password"
}

variable "db_username" {
  description = "Database username for the connection string"
  type        = string
  default     = "ap_user"
}

variable "db_name" {
  description = "Database name for the connection string"
  type        = string
  default     = "apthreetiredb"
}

# With RDS
# variable "db_instance_class" {
#   type    = string
#   default = "db.t3.micro"
# }
