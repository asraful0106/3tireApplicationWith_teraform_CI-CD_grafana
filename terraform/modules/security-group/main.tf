# ==============================================================================
# Module: Security Groups
# Creates security groups for each tier with least-privilege rules.
#
# SG hierarchy:
#   alb-sg       → receives internet traffic (80, 443)
#   bastion-sg   → receives SSH from allowed_ssh_cidr only
#   frontend-sg  → receives 80 from alb-sg, 22 from bastion-sg
#   backend-sg   → receives 3000 from alb-sg, 22 from bastion-sg
#   rds-sg       → receives 5432 from backend-sg only
# ==============================================================================

# ------------------------------------------------------------------------------
# ALB Security Group — internet-facing
# ------------------------------------------------------------------------------
# terraform/modules/security-group/main.tf
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB: allow HTTP and HTTPS from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# ------------------------------------------------------------------------------
# Bastion Security Group — restricted SSH access
# ------------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Bastion: SSH only from allowed CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound (to reach private instances)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  }
}
# ------------------------------------------------------------------------------
# Monitoring Security Group — restricted SSH access
# ------------------------------------------------------------------------------

resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-monitoring-sg"
  description = "Monitoring EC2: Grafana :3000, Prometheus :9090, node_exporter :9100"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # node_exporter self-scrape (Prometheus → localhost:9100 on this same EC2)
  ingress {
    description = "node_exporter self-scrape"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to VPC targets + internet (GitHub, APT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-monitoring-sg" }
}

# ------------------------------------------------------------------------------
# Frontend Security Group
# Phase 1 (basic): 80/443 from 0.0.0.0/0
# Phase 2 (production): 80 from alb-sg only
# Controlled by var.frontend_public_access
# ------------------------------------------------------------------------------
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-${var.environment}-frontend-sg"
  description = "Frontend EC2: HTTP from ALB (or internet in basic mode)"
  vpc_id      = var.vpc_id

  # SSH from bastion only
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-sg"
  }
}

# HTTP from internet (Phase 1 — basic: frontend in public subnet)
resource "aws_security_group_rule" "frontend_http_public" {
  count             = var.frontend_public_access ? 1 : 0
  type              = "ingress"
  description       = "HTTP from internet (Phase 1: frontend in public subnet)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.frontend.id
}

# HTTP from ALB only (Phase 2 — production: frontend in private subnet)
resource "aws_security_group_rule" "frontend_http_alb" {
  count                    = var.frontend_public_access ? 0 : 1
  type                     = "ingress"
  description              = "HTTP from ALB only (Phase 2: frontend in private subnet)"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.frontend.id
}

# ------------------------------------------------------------------------------
# Backend Security Group
# Port 3000 from ALB only (never directly from internet)
# ------------------------------------------------------------------------------
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend-sg"
  description = "Backend EC2: port 3000 from ALB, SSH from bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Node.js API from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound (RDS, Secrets Manager, NAT GW)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-sg"
  }
}

# Phase 1 extra rule: backend also reachable from frontend EC2 directly
resource "aws_security_group_rule" "backend_from_frontend" {
  count                    = var.frontend_public_access ? 1 : 0
  type                     = "ingress"
  description              = "Node.js API from frontend EC2 (Phase 1)"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
  security_group_id        = aws_security_group.backend.id
}

# ------------------------------------------------------------------------------
# RDS Security Group — database tier, private only
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "RDS PostgreSQL: port 5432 from backend EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}
