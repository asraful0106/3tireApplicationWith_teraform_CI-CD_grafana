# terraform/modules/security-group/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion. Use your IP: x.x.x.x/32"
  type        = string
}

variable "frontend_public_access" {
  description = <<-EOT
    Phase 1 (basic 3-tier): set to true  — frontend SG allows 80 from internet directly
    Phase 2 (production):   set to false — frontend SG allows 80 from ALB only
  EOT
  type        = bool
  default     = false
}
