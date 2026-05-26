# terraform/output.tf
output "vpc_id" { value = module.vpc.vpc_id }
output "bastion_public_ip" { value = module.bastion.public_ip }
# output "db_endpoint" { value = module.rds.db_endpoint }


# ── Frontend ───────────────────────────────────────────────────────────────────

output "frontend_public_ip" {
  description = "Public IP of the frontend EC2"
  value       = module.frontend.public_ip
}

output "health_check" {
  description = "Frontend health check URL — hit this to verify Nginx is up"
  value       = "http://${module.frontend.public_ip}/health"
}

output "app_url" {
  description = "URL to open the 3-tier app in a browser"
  value       = "http://${module.frontend.public_ip}"
}

output "ssh_bastion" {
  value = "ssh -i ~/Desktop/devops/ubuntu_conf/ap.pem ubuntu@${module.bastion.public_ip}"
}

output "ssh_frontend_via_bastion" {
  value = "ssh -i ~/Desktop/devops/ubuntu_conf/ap.pem -J ubuntu@${module.bastion.public_ip} ubuntu@${module.frontend.private_ip}"
}


# ── Backend ────────────────────────────────────────────────────────────────────

output "backend_private_ip" {
  description = "Private IP of the backend EC2 (used by frontend Nginx proxy)"
  value       = module.backend.private_ip
}

output "api_health_check" {
  description = "Direct backend health check (reachable only from within VPC / bastion)"
  value       = "http://${module.backend.private_ip}:3000/api/health"
}

output "ssh_backend_via_bastion" {
  value = "ssh -i ~/Desktop/devops/ubuntu_conf/ap.pem -J ubuntu@${module.bastion.public_ip} ubuntu@${module.backend.private_ip}"
}

# ── Database EC2 ──────────────────────────────────────────────────────────────

output "db_host" {
  description = "Private IP of the PostgreSQL EC2 (passed to backend as DB_HOST)"
  value       = module.db_ec2.db_host
}

output "db_instance_id" {
  description = "EC2 instance ID of the DB server — use for SSM Session Manager"
  value       = module.db_ec2.instance_id
}

# Grafana
output "grafana_url" {
  description = "Grafana dashboard"
  value       = "http://${module.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus UI"
  value       = "http://${module.monitoring.public_ip}:9090"
}


# output "database_url_secret" {
#   value = module.secrets.database_url_secret_name
# } # with RDS

# ── Secrets ────────────────────────────────────────────────────────────────────

# output "db_password_secret_name" {
#   description = "Secrets Manager secret name holding the DB password"
#   value       = module.secrets.db_password_secret_name
# }