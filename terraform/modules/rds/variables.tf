# terraform/modules/rds/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "subnet_ids" {
  description = "List of private DB subnet IDs (minimum 2, spanning 2 AZs)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the RDS instance"
  type        = string
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "bmidb"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  default     = "bmi_user"
}

variable "db_password" {
  description = "Master database password — provided by Secrets Manager, never hardcoded"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "14.13"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ for high availability (recommended for prod)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Prevent accidental deletion. Set false for demo environments."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (true for dev/demo, false for prod)"
  type        = bool
  default     = true
}
