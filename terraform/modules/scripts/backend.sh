#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t backend-init) 2>&1

echo "============================================"
echo " Backend User Data — $(date)"
echo "============================================"

# ── Terraform-injected variables ──────────────────────────
DB_PASSWORD="${db_password}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_USER="${db_user}"
DB_NAME="${db_name}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"

REPO_URL="https://github.com/asraful0106/3tireApplicationWith_teraform_CI-CD_grafana.git"

APP_DIR="/home/ubuntu/app"
BACKEND_DIR="$APP_DIR/app/backend"

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

# PM2
npm install -g pm2

# ── 2. Clone repo ──────────────────────────────────────────
rm -rf "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

# ── 3. Create .env ─────────────────────────────────────────
cat > "$BACKEND_DIR/.env" <<EOF
NODE_ENV=$ENVIRONMENT
APP_PORT=3000

DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
EOF

chmod 600 "$BACKEND_DIR/.env"
chown ubuntu:ubuntu "$BACKEND_DIR/.env"

# ── 4. Install dependencies ────────────────────────────────
cd "$BACKEND_DIR"
npm install --omit=dev

# ── 5. Start backend with PM2 ──────────────────────────────
sudo -u ubuntu bash -c "
  cd $BACKEND_DIR
  pm2 start server.js --name backend
  pm2 save
"

# ── PM2 startup (persistent reboot) ────────────────────────
env PATH="$PATH:/usr/bin" pm2 startup systemd -u ubuntu --hp /home/ubuntu
systemctl enable pm2-ubuntu

# ── 6. node_exporter ───────────────────────────────────────
NODE_EXPORTER_VER="1.7.0"

useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

cd /tmp

wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VER}/node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"

tar -xf "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"

install -m755 "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/node_exporter

rm -rf node_exporter-*.linux-amd64*

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

# ── Final logs ─────────────────────────────────────────────
echo "============================================"
echo " Backend running on http://0.0.0.0:3000"
echo " DB host : $DB_HOST:$DB_PORT/$DB_NAME"
echo " Environment : $ENVIRONMENT"
echo "============================================"