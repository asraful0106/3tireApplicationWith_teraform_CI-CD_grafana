# ==============================================================================
#
# Frontend EC2  â†’ PUBLIC subnet  (Nginx, port 80 open to internet)
# Backend EC2   â†’ PRIVATE app subnet (Node.js PM2 port 3000)
# RDS           â†’ PRIVATE db subnet  (PostgreSQL 14)
#
# Traffic flow:
#   Internet â†’ Frontend EC2 (public IP:80) â†’ Backend private IP:3000 â†’ RDS
#
# Bastion â†’ jump SSH to frontend and backend
# NAT GW  â†’ private subnets get outbound internet (for apt/npm/git)
# ==============================================================================

# terraform/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
#   profile = "ap-ostad"
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# VPC + all subnets
module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  environment  = var.environment
}

# Phase 1: frontend_public_access = true â€” frontend SG allows 80 from internet
module "security_groups" {
  source                 = "./modules/security-group"
  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  frontend_public_access = true # Phase 1 setting
}

# IAM role for backend â†’ Secrets Manager
# module "iam_backend" {
#   source       = "./modules/iam"
#   project_name = var.project_name
#   environment  = var.environment
#   aws_region   = var.aws_region
#   role_suffix  = "backend"
# }

# Without RDS
module "db_ec2" {
  source = "./modules/db_ec2"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # ── Networking (same values you passed to RDS) ──────────────────────────────
  db_subnet_id         = module.vpc.private_db_subnet_ids[0]
  db_security_group_id = module.security_groups.rds_sg_id
  #   db_security_group_id = module.vpc.db_security_group_id
  vpc_cidr = module.vpc.vpc_cidr

  # ── Database credentials ─────────────────────────────────────────────────────
  db_password_secret_arn = var.db_password
  db_username            = var.db_username
  db_name                = var.db_name

  # ── EC2 sizing ───────────────────────────────────────────────────────────────
  instance_type        = var.db_instance_type # same footprint as db.t3.micro RDS
  root_volume_size_gb  = 20
  key_name             = var.key_name
#   iam_instance_profile = module.iam_backend.instance_profile_name
}

# ---------

# # -------RDS PostgreSQL

# module "secrets" {
#   source       = "./modules/secrets"
#   project_name = var.project_name
#   environment  = var.environment

#   db_host     = module.db_ec2.db_host # was: module.rds.db_host
#   db_username = "ap_user"
#   db_name     = "threetiredb"
# }

# module "rds" {
#   source = "./modules/rds"
#   project_name      = var.project_name
#   environment       = var.environment
#   subnet_ids        = module.vpc.private_db_subnet_ids
#   security_group_id = module.security_groups.rds_sg_id
#   db_password       = module.secrets.db_password
#   instance_class    = var.db_instance_class
#   multi_az          = false
#   skip_final_snapshot = true
# }

# # Secrets Manager â€” create after RDS so db_host is available
# module "secrets" {
#   source = "./modules/secrets"
#   project_name = var.project_name
#   environment  = var.environment
#   db_host      = module.rds.db_host
#   depends_on   = [module.rds]
# }
# --------------

# Bastion host â€” SSH jump server in public subnet
module "bastion" {
  source             = "./modules/ec2"
  name               = "${var.project_name}-${var.environment}-bastion"
  role               = "bastion"
  instance_type      = "t3.micro"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.bastion_sg_id]
  key_name           = var.key_name
}

# Backend EC2 â€” PRIVATE app subnet
module "backend" {
  source               = "./modules/ec2"
  name                 = "${var.project_name}-${var.environment}-backend"
  role                 = "backend"
  instance_type        = var.backend_instance_type
  subnet_id            = module.vpc.private_app_subnet_ids[0]
  security_group_ids   = [module.security_groups.backend_sg_id]
  key_name             = var.key_name
#   iam_instance_profile = module.iam_backend.instance_profile_name

  #   user_data = templatefile("${path.module}/scripts/backend.sh", {
  #     database_url_secret_name = module.secrets.database_url_secret_name
  #     frontend_url             = "http://${module.frontend.public_ip}"
  #     environment              = var.environment
  #     aws_region               = var.aws_region
  #   })
  user_data = templatefile("${path.module}/modules/scripts/backend.sh", {
    # db_password_secret_name = module.secrets.db_password_secret_name
    db_password = var.db_password
    db_host     = module.db_ec2.db_host
    db_port     = 5432
    db_user     = var.db_username
    db_name     = var.db_name
    # frontend_url            = "http://${module.frontend.public_ip}"
    environment = var.environment
    aws_region  = var.aws_region
  })

  #   depends_on = [module.secrets, module.db_ec2]
  depends_on = [module.db_ec2]
}

# Frontend EC2 â€” PUBLIC subnet (Phase 1: directly internet-accessible)
module "frontend" {
  source             = "./modules/ec2"
  name               = "${var.project_name}-${var.environment}-frontend"
  role               = "frontend"
  instance_type      = var.frontend_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.frontend_sg_id]
  key_name           = var.key_name

  #   user_data = templatefile("${path.module}/scripts/frontend.sh", {
  #     backend_private_ip = module.backend.private_ip
  #     phase              = "basic"
  #   })
  user_data = templatefile("${path.module}/modules/scripts/frontend.sh", {
    backend_private_ip = module.backend.private_ip
    environment        = var.environment
  })

  depends_on = [module.backend]
}

# ── Monitoring EC2 — PUBLIC subnet ────────────────────────────────────────────
module "monitoring" {
  source = "./modules/ec2"

  name               = "${var.project_name}-${var.environment}-monitoring"
  role               = "monitoring"
  instance_type      = var.monitoring_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.frontend_sg_id]
  key_name           = var.key_name

  user_data = templatefile("${path.module}/modules/scripts/monitoring.sh", {
    frontend_private_ip    = module.frontend.private_ip
    backend_private_ip     = module.backend.private_ip
    db_private_ip          = module.db_ec2.db_host
    environment            = var.environment
    aws_region             = var.aws_region
    grafana_admin_password = var.grafana_admin_password
  })

  depends_on = [module.backend, module.frontend, module.db_ec2]
}
