# ==============================================================================
# Module: RDS PostgreSQL
# Creates a managed PostgreSQL 14 database in private subnets.
# No public access. Encrypted storage. Multi-AZ optional.
# ==============================================================================

# terraform/modules/rds/main.tf

# DB Subnet Group — must span at least 2 AZs
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "RDS subnet group for ${var.project_name} ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# PostgreSQL 14 Parameter Group with performance tuning
resource "aws_db_parameter_group" "postgres14" {
  name        = "${var.project_name}-${var.environment}-pg14"
  family      = "postgres14"
  description = "PostgreSQL 14 parameter group for ${var.project_name}"

  # Connection pooling tuning
  parameter {
    name  = "max_connections"
    value = "100"
  }

  # Memory tuning — match the values from database/setup-database.sh
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking > 1s
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-pg14-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage — gp3 is cheaper and faster than gp2
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2 # Auto-scaling up to 2x
  storage_type          = "gp3"
  storage_encrypted     = true # Always encrypt at rest

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false # NEVER publicly accessible

  # Parameter group
  parameter_group_name = aws_db_parameter_group.postgres14.name

  # Availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00" # UTC — 8:30-9:30 AM IST
  maintenance_window      = "sun:04:00-sun:05:00"

  # Deletion protection — set false for demo (destroy after class)
  deletion_protection = var.deletion_protection

  # Skip final snapshot for dev/demo (set to true for prod normally)
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot"

  # Performance Insights (free tier: 7 days retention)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}
