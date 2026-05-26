# terraform/modules/secrets/variables.tf
variable "project_name" {
  description = "Project name for secret naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "db_username" {
  description = "Database username for the connection string"
  type        = string
  default     = "ap_user"
}

variable "db_name" {
  description = "Database name for the connection string"
  type        = string
  default     = "apthreetire"
}

variable "db_host" {
  description = "RDS hostname (from rds module output: db_host)"
  type        = string
}

variable "recovery_window_days" {
  description = "Days before permanent deletion after secret is deleted (0 = immediate)"
  type        = number
  default     = 0 # 0 for demo environments so terraform destroy is clean
}
