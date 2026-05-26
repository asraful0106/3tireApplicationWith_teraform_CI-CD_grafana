# terraform/modules/db_ec2/variables.tf

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region — needed by aws-cli inside user_data to call Secrets Manager"
  type        = string
}

# ------------------------------------------------------------------------------
# Networking — pass the SAME values you were giving to the RDS module.
# Nothing in the VPC/subnet/SG/NAT setup needs to change.
# ------------------------------------------------------------------------------
variable "db_subnet_id" {
  description = "ID of the private subnet to place the DB EC2 in (one of the RDS subnet group subnets)"
  type        = string
}

variable "db_security_group_id" {
  description = "Security group ID that was attached to RDS — reused unchanged"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block written into pg_hba.conf to restrict DB access"
  type        = string
}

# ------------------------------------------------------------------------------
# Database
# ------------------------------------------------------------------------------
variable "db_username" {
  description = "PostgreSQL role to create"
  type        = string
  default     = "bmi_user"
}

variable "db_name" {
  description = "PostgreSQL database to create"
  type        = string
  default     = "bmidb"
}

variable "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret that holds the DB password (from secrets module)"
  type        = string
}

# ------------------------------------------------------------------------------
# EC2 sizing
# ------------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for the DB server (t3.micro is fine for dev)"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gb" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "EC2 key pair name for SSH access (same key used by other instances)"
  type        = string
}



variable "iam_instance_profile" {
  description = "IAM instance profile name (for Secrets Manager access)"
  type        = string
  default     = null
}
