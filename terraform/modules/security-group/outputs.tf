# terraform/modules/security-group/outputs.tf
output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "bastion_sg_id" {
  description = "Security Group ID for the Bastion Host"
  value       = aws_security_group.bastion.id
}

output "frontend_sg_id" {
  description = "Security Group ID for the Frontend EC2"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "Security Group ID for the Backend EC2"
  value       = aws_security_group.backend.id
}

output "rds_sg_id" {
  description = "Security Group ID for RDS PostgreSQL"
  value       = aws_security_group.rds.id
}

output "monitoring_sg_id" {
  description = "Security Group ID for the Monitoring"
  value       = aws_security_group.monitoring.id
}