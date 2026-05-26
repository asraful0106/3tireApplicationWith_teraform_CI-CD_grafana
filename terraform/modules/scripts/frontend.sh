#!/bin/bash
# ==============================================================================
# frontend.sh — Frontend EC2 User Data
#
# Repo layout (app/):
#   frontend/index.html  — plain static HTML+JS, NO React build step needed.
#                          API calls use a relative path (const API = '')
#                          so Nginx proxies /api/* to the backend EC2.
#
# What this script does:
#   1. Installs Nginx
#   2. Clones the repo
#   3. Copies app/frontend/ → /var/www/html/
#   4. Configures Nginx to:
#        • serve static files from /var/www/html/
#        • proxy /api/*  →  backend EC2 private IP:3000
#        • expose GET /health  (used by the Terraform health_check output)
#
# Template variables injected by Terraform templatefile():
#   ${backend_private_ip}  — private IP of the backend EC2
#   ${environment}         — dev / staging / prod
# ==============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t frontend-init) 2>&1

echo "============================================"
echo " Frontend User Data — $(date)"
echo "============================================"

# ── Terraform-injected variables ──────────────────────────
BACKEND_PRIVATE_IP="${backend_private_ip}"
ENVIRONMENT="${environment}"

REPO_URL="https://github.com/asraful0106/3tireApplicationWith_teraform_CI-CD_grafana.git"
APP_DIR="/home/ubuntu/app"

# ── 1. System packages ─────────────────────────────────────
apt-get update -y
apt-get install -y curl git nginx

# ── 2. Clone repo ──────────────────────────────────────────
git clone "$REPO_URL" "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

# ── 3. Deploy static files ────────────────────────────────
# Only the frontend/ directory is needed on this EC2.
rm -rf /var/www/html/*
cp -r "$APP_DIR/frontend/"* /var/www/html/

# ── 4. Nginx config ───────────────────────────────────────
# • /api/*   → proxied to backend EC2 (makes `const API = ''` in index.html work)
# • /health  → 200 OK (consumed by the Terraform health_check output)
# • /        → serves index.html (SPA-style catch-all)
cat > /etc/nginx/sites-available/app <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;
    server_name _;

    # ── Health check endpoint (for Terraform output + monitoring) ──
    location = /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    # ── API proxy → backend EC2 ────────────────────────────────────
    location /api/ {
        proxy_pass         http://$BACKEND_PRIVATE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout    30s;
    }

    # ── Static frontend ────────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX

# Activate the new config, remove the default
ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx


# ── node_exporter (scraped by Prometheus monitoring EC2) ──
NODE_EXPORTER_VER="1.7.0"
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
tar -xf "node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
install -m755 "node_exporter-${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
rm -rf "node_exporter-${NODE_EXPORTER_VER}.linux-amd64"*
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
echo " Frontend deployed."
echo " Static files : /var/www/html/"
echo " API proxy    : /api/* → $BACKEND_PRIVATE_IP:3000"
echo " Health check : http://<public-ip>/health"
echo " Environment  : $ENVIRONMENT"
echo "============================================"