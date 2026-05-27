#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/db-init.log | logger -t db-init) 2>&1

echo "===== DB INIT START ====="
echo "Time: $(date)"

# ─────────────────────────────────────────────
# Wait for network
# ─────────────────────────────────────────────
echo "Waiting for network..."
for i in {1..12}; do
    if curl -sf --max-time 5 https://archive.ubuntu.com > /dev/null 2>&1; then
        echo "Network ready."; break
    fi
    echo "Not ready yet... ($i/12)"; sleep 10
done

# ─────────────────────────────────────────────
# Fix Apt Sources — HTTPS only
# ─────────────────────────────────────────────
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
sed -i 's|http://|https://|g' /etc/apt/sources.list
find /etc/apt/sources.list.d/ -name "*.list" \
    -exec sed -i 's|http://|https://|g' {} + 2>/dev/null || true

# ─────────────────────────────────────────────
# apt-get update with real error detection
# ─────────────────────────────────────────────
echo "Running apt update..."
for i in {1..5}; do
    APT_OUT=$(apt-get update -q 2>&1)
    echo "$APT_OUT"
    if ! echo "$APT_OUT" | grep -q "^Err:"; then
        echo "apt update successful."; break
    fi
    echo "Attempt $i failed, retrying in 15s..."; sleep 15
    [ "$i" -eq 5 ] && { echo "ERROR: apt update failed."; exit 1; }
done

# ─────────────────────────────────────────────
# Install Packages
# ─────────────────────────────────────────────
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl ca-certificates gnupg unzip \
    postgresql postgresql-contrib

# AWS CLI v2
if ! command -v aws &>/dev/null; then
    curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# ─────────────────────────────────────────────
# Start PostgreSQL + WAIT until it accepts connections
# ─────────────────────────────────────────────
echo "Starting PostgreSQL..."
systemctl enable --now postgresql

echo "Waiting for PostgreSQL cluster to be ready..."
for i in {1..30}; do
    if sudo -u postgres pg_isready -q; then
        echo "PostgreSQL is ready."; break
    fi
    echo "Not ready yet... ($i/30)"; sleep 2
    [ "$i" -eq 30 ] && {
        echo "ERROR: PostgreSQL did not become ready."
        systemctl status 'postgresql@*' --no-pager
        exit 1
    }
done

# ─────────────────────────────────────────────
# Create Role + Database  (fixed)
# ─────────────────────────────────────────────
DB_USER="${db_username}"
DB_NAME="${db_name}"
DB_PASS="${db_password}"

echo "Creating role..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
      CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS' CREATEDB;
      RAISE NOTICE 'Role $DB_USER created.';
   ELSE
      RAISE NOTICE 'Role $DB_USER already exists, skipping.';
   END IF;
END
\$\$;
SQL

# CREATE DATABASE cannot run inside DO $$ ... $$
# Must be a top-level statement — use shell-level guard instead
echo "Creating database..."
DB_EXISTS=$(sudo -u postgres psql -Atc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")
if [ "$DB_EXISTS" != "1" ]; then
    sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
    echo "Database $DB_NAME created."
else
    echo "Database $DB_NAME already exists, skipping."
fi

echo "Granting privileges..."
sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
    "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

echo "DB setup complete."

# ─────────────────────────────────────────────
# Configure Remote Access
# ─────────────────────────────────────────────
PG_CONF=$(sudo -u postgres psql -Atc "SHOW config_file;")
PG_HBA=$(sudo -u postgres psql -Atc "SHOW hba_file;")

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_CONF"
grep -q "^listen_addresses" "$PG_CONF" || echo "listen_addresses = '*'" >> "$PG_CONF"

cat > "$PG_HBA" <<EOF
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             ${vpc_cidr}             scram-sha-256
EOF

systemctl restart postgresql

# ─────────────────────────────────────────────
# Write SSM "ready" flag so backend knows DB is done
# ─────────────────────────────────────────────
aws ssm put-parameter \
    --region "${aws_region}" \
    --name "/${environment}/db/ready" \
    --value "true" \
    --type "String" \
    --overwrite

echo "===== DB INIT COMPLETE ====="
echo "Time: $(date)"