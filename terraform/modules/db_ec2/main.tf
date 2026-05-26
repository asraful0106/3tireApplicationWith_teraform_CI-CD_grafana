# ==============================================================================
# Module: db_ec2
# Provisions a PostgreSQL 15 database running on an EC2 instance.
# This is a drop-in replacement for an aws_db_instance (RDS) resource.
#
# What stays UNCHANGED from the RDS setup:
#   - VPC, subnets, NAT gateway
#   - Security group passed in via var.db_security_group_id
#   - Secrets Manager secrets (managed by the `secrets` module)
#
# Outputs mirror the RDS module so callers need zero refactoring:
#   db_host   → private IP of this EC2 (was: RDS endpoint)
#   db_port   → 5432
#   db_name   → var.db_name
# ==============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ------------------------------------------------------------------------------
# user_data script — kept well under the 16 KB AWS hard limit.
# Strategy: install PostgreSQL via yum (AL2023 ships pg15 in extras),
#           pull the password from Secrets Manager at boot,
#           create the DB role + database, then lock down pg_hba.conf.
# ------------------------------------------------------------------------------
locals {
  user_data = <<-SHELL
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/db-init.log | logger -t db-init) 2>&1

### 1. Install PostgreSQL 15
dnf install -y postgresql15 postgresql15-server aws-cli

### 2. Initialise the cluster
postgresql-setup --initdb
systemctl enable --now postgresql

### 3. Fetch password from Secrets Manager
REGION="${var.aws_region}"
SECRET_ARN="${var.db_password_secret_arn}"
DB_PASS=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)

### 4. Create role + database
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE ${var.db_username} WITH LOGIN PASSWORD '$DB_PASS';
CREATE DATABASE ${var.db_name} OWNER ${var.db_username};
GRANT ALL PRIVILEGES ON DATABASE ${var.db_name} TO ${var.db_username};
SQL

### 5. Allow password auth from VPC CIDR only
PG_HBA=$(sudo -u postgres psql -Atc "SHOW hba_file;")
cat > "$PG_HBA" <<HBA
local   all             postgres                                peer
local   all             all                                     peer
host    ${var.db_name}  ${var.db_username}  ${var.vpc_cidr}   scram-sha-256
host    all             all                 127.0.0.1/32       scram-sha-256
HBA

### 6. Listen on all interfaces (security group limits access)
PG_CONF=$(sudo -u postgres psql -Atc "SHOW config_file;")
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

### 7. Reload
systemctl reload postgresql
echo "DB init complete."
SHELL
}

# ------------------------------------------------------------------------------
# EC2 instance — placed in the same private subnet(s) RDS used
# ------------------------------------------------------------------------------
resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.db_subnet_id # first private DB subnet
  vpc_security_group_ids = [var.db_security_group_id]
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name

  # Root volume — enough space for a small-to-medium dev database
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    encrypted             = true
  }

  user_data                   = local.user_data
  user_data_replace_on_change = false # avoid accidental data loss on re-apply

  tags = {
    Name = "${var.project_name}-${var.environment}-db-ec2"
    Role = "database"
  }
}
