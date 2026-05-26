# ==============================================================================
# Module: db_ec2 (FIXED & ROBUST)
# PostgreSQL 15 on EC2 replacement for RDS
# ==============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/db-init.log | logger -t db-init) 2>&1

echo "===== DB INIT START ====="

# ── Install PostgreSQL ─────────────────────────────
dnf install -y postgresql15 postgresql15-server aws-cli

# ── Init DB cluster ────────────────────────────────
postgresql-setup --initdb
systemctl enable --now postgresql

# ── Fetch secret ───────────────────────────────────
REGION="${var.aws_region}"
SECRET_ARN="${var.db_password_secret_arn}"

DB_PASS=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)

# ── Create DB + user ───────────────────────────────
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO
$$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${var.db_username}') THEN
      CREATE ROLE ${var.db_username} WITH LOGIN PASSWORD '$DB_PASS';
   END IF;
END
$$;

CREATE DATABASE ${var.db_name} OWNER ${var.db_username};
GRANT ALL PRIVILEGES ON DATABASE ${var.db_name} TO ${var.db_username};
SQL

# ── CONFIG FIX (IMPORTANT) ─────────────────────────
PG_CONF=$(sudo -u postgres psql -Atc "SHOW config_file;")

grep -q "^listen_addresses" "$PG_CONF" && \
  sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$PG_CONF" || \
  echo "listen_addresses = '*'" >> "$PG_CONF"

# ── Fix pg_hba (safe overwrite) ─────────────────────
PG_HBA=$(sudo -u postgres psql -Atc "SHOW hba_file;")

cat > "$PG_HBA" <<HBA
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ${var.vpc_cidr}         scram-sha-256
HBA

# ── Restart (IMPORTANT) ────────────────────────────
systemctl restart postgresql

# ── Verification (CRITICAL DEBUG) ──────────────────
echo "===== POSTGRES STATUS ====="
systemctl status postgresql --no-pager || true

echo "===== LISTEN PORT ====="
ss -tulnp | grep 5432 || echo "5432 NOT LISTENING"

echo "===== CONFIG CHECK ====="
sudo -u postgres psql -c "SHOW listen_addresses;"

echo "===== DB INIT COMPLETE ====="
EOF
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.db_subnet_id
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
    encrypted             = true
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-${var.environment}-db-ec2"
    Role = "database"
  }
}