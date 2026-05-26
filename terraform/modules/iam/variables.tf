variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used to scope secret ARN)"
  type        = string
  default     = "ap-south-1"
}

variable "role_suffix" {
  description = "Suffix for the IAM role name (e.g. backend, frontend)"
  type        = string
  default     = "backend"
}

variable "attach_cloudwatch_policy" {
  description = "Attach CloudWatchAgentServerPolicy to the role"
  type        = bool
  default     = false
}

variable "attach_ssm_policy" {
  description = "Attach AmazonSSMManagedInstanceCore (SSM Session Manager access)"
  type        = bool
  default     = true
}
