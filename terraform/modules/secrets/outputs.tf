# terraform/modules/secrets/outputs.tf
output "db_password" {
  description = "Generated database password (sensitive)"
  value       = random_password.db.result
  sensitive   = true
}

output "db_password_secret_arn" {
  description = "ARN of the db-password secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "db_password_secret_name" {
  description = "Name of the db-password secret"
  value       = aws_secretsmanager_secret.db_password.name
}

output "database_url_secret_arn" {
  description = "ARN of the database-url secret in Secrets Manager"
  value       = aws_secretsmanager_secret.database_url.arn
}

output "database_url_secret_name" {
  description = "Name of the database-url secret (used by backend EC2 at boot)"
  value       = aws_secretsmanager_secret.database_url.name
}
