#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/db-init.log | logger -t db-init) 2>&1

echo "===== DB INIT START ====="

# ─────────────────────────────────────────────
# 1. Install dependencies (Ubuntu correct way)
# ─────────────────────────────────────────────
apt-get update -y
apt-get install -y curl ca-certificates gnupg lsb-release awscli postgresql postgresql-contrib

# ─────────────────────────────────────────────
# 2. Start PostgreSQL
# ─────────────────────────────────────────────
systemctl enable postgresql
systemctl start postgresql

# ─────────────────────────────────────────────
# 3. Database credentials (CURRENT: Terraform variables)
# ─────────────────────────────────────────────
DB_USER="${db_username}"
DB_NAME="${db_name}"
DB_PASS="${db_password}"

# ─────────────────────────────────────────────
# 4. FUTURE: AWS Secrets Manager (commented for now)
# ─────────────────────────────────────────────
: '
REGION="${aws_region}"
SECRET_ARN="${db_password_secret_arn}"

DB_PASS=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)
'

# ─────────────────────────────────────────────
# 5. Create DB + user (idempotent safe)
# ─────────────────────────────────────────────
sudo -u postgres psql <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
      CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
      CREATE DATABASE $DB_NAME OWNER $DB_USER;
   END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
SQL

# ─────────────────────────────────────────────
# 6. Configure PostgreSQL networking
# ─────────────────────────────────────────────
PG_CONF=$(sudo -u postgres psql -Atc "SHOW config_file;")
PG_HBA=$(sudo -u postgres psql -Atc "SHOW hba_file;")

# Listen on all interfaces (required for backend EC2 access)
grep -q "^listen_addresses" "$PG_CONF" && \
  sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$PG_CONF" || \
  echo "listen_addresses = '*'" >> "$PG_CONF"

# Allow VPC access only
cat > "$PG_HBA" <<EOF
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ${vpc_cidr}             scram-sha-256
EOF

# ─────────────────────────────────────────────
# 7. Restart PostgreSQL
# ─────────────────────────────────────────────
systemctl restart postgresql

# ─────────────────────────────────────────────
# 8. Verification (IMPORTANT DEBUG)
# ─────────────────────────────────────────────
echo "===== POSTGRES STATUS ====="
systemctl status postgresql --no-pager || true

echo "===== LISTEN PORT ====="
ss -tulnp | grep 5432 || echo "5432 NOT LISTENING"

echo "===== LISTEN CONFIG ====="
sudo -u postgres psql -c "SHOW listen_addresses;"

echo "===== DB INIT COMPLETE ====="