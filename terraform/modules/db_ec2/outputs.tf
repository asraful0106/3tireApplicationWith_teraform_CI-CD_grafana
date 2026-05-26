# terraform/modules/db_ec2/outputs.tf
# Output names are intentionally identical to the RDS module so that the
# `secrets` module and any other callers need zero changes.

output "db_host" {
  description = "Private IP of the DB EC2 instance (replaces RDS endpoint)"
  value       = aws_instance.db.private_ip
}

output "db_port" {
  description = "PostgreSQL port"
  value       = 5432
}

output "db_name" {
  description = "Name of the PostgreSQL database"
  value       = var.db_name
}

output "db_username" {
  description = "PostgreSQL role / username"
  value       = var.db_username
}

output "instance_id" {
  description = "EC2 instance ID — useful for SSM Session Manager or debugging"
  value       = aws_instance.db.id
}

output "private_ip" {
  description = "Private IP address (same as db_host — exposed separately for convenience)"
  value       = aws_instance.db.private_ip
}
