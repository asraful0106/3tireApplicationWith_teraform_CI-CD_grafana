# terraform/modules/rds/outputs.tf
output "db_endpoint" {
  description = "RDS instance endpoint (hostname:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_host" {
  description = "RDS hostname only (without port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Database master username"
  value       = aws_db_instance.main.username
}

output "db_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}
# Note: db_password is intentionally NOT output — retrieve from Secrets Manager
