#!/bin/bash
# ==============================================================================
# backend.sh — Backend EC2 User Data
#
# Repo layout (app/):
#   backend/   → server.js  (Express + pg, reads DB_HOST/PORT/USER/PASSWORD/NAME)
#   frontend/  → index.html (served as static files by this same Node.js server)
#
# What this script does:
#   1. Installs Node.js 18, PM2, AWS CLI
#   2. Clones the repo
#   3. Pulls DB credentials from Secrets Manager (individual vars, NOT DATABASE_URL)
#   4. Writes .env  →  DB_HOST / DB_PORT / DB_USER / DB_PASSWORD / DB_NAME
#   5. npm install --production
#   6. Starts server.js with PM2
#
# Template variables injected by Terraform templatefile():
#   ${db_password_secret_name}  — name of the Secrets Manager secret (password only)
#   ${db_host}                  — private IP of the db_ec2 instance
#   ${db_port}                  — 5432
#   ${db_user}                  — e.g. bmi_user
#   ${db_name}                  — e.g. bmidb
#   ${environment}              — dev / staging / prod
#   ${aws_region}               — ap-southeast-2
# ==============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t backend-init) 2>&1

echo "============================================"
echo " Backend User Data — $(date)"
echo "============================================"

# ── Terraform-injected variables ──────────────────────────
DB_PASSWORD_SECRET="${db_password_secret_name}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_USER="${db_user}"
DB_NAME="${db_name}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"

REPO_URL="https://github.com/asraful0106/3tireApplicationWith_teraform_CI-CD_grafana.git"
APP_DIR="/home/ubuntu/app"

# ── 1. System packages ─────────────────────────────────────
apt-get update -y
apt-get install -y curl git unzip

# AWS CLI v2
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi

# Node.js 18 LTS
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# PM2 — process manager
npm install -g pm2

# ── 2. Clone repo ──────────────────────────────────────────
git clone "$REPO_URL" "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

# ── 3. Fetch DB password from Secrets Manager ──────────────
echo "Fetching DB password from Secrets Manager..."
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$DB_PASSWORD_SECRET" \
  --query SecretString \
  --output text)

if [ -z "$DB_PASSWORD" ]; then
  echo "ERROR: Failed to retrieve DB password from Secrets Manager"
  exit 1
fi
echo "DB password retrieved."

# ── 4. Write .env  (matches server.js env var names exactly) ──
cat > "$APP_DIR/backend/.env" <<EOF
NODE_ENV=$ENVIRONMENT
APP_PORT=3000

DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
EOF
chmod 600 "$APP_DIR/backend/.env"
chown ubuntu:ubuntu "$APP_DIR/backend/.env"

# ── 5. Install production dependencies ────────────────────
cd "$APP_DIR/backend"
npm install --production --omit=dev

# ── 6. Start with PM2 ─────────────────────────────────────
# server.js serves both /api/* routes AND the static frontend/index.html
sudo -u ubuntu bash -c "
  cd $APP_DIR/backend
  pm2 start server.js --name backend --env production
  pm2 save
"

# Enable PM2 to survive reboots
env PATH="$PATH:/usr/bin" pm2 startup systemd -u ubuntu --hp /home/ubuntu
systemctl enable pm2-ubuntu


# ── node_exporter (scraped by Prometheus monitoring EC2) ──

NODE_EXPORTER_VER="1.7.0"
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
cd /tmp


wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VER}/node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
tar -xf "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
install -m755 "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
rm -rf "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64"*


cat > /etc/systemd/system/node_exporter.service <<SVC
[Unit]
Description=Node Exporter
After=network-online.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now node_exporter
echo "[node_exporter] running on :9100"


echo "============================================"
echo " Backend running on http://0.0.0.0:3000"
echo " DB host : $DB_HOST:$DB_PORT/$DB_NAME"
echo " Env     : $ENVIRONMENT"
echo "============================================"