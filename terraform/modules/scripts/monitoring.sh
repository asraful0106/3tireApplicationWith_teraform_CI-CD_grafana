#!/bin/bash
# ==============================================================================
# monitoring.sh  —  scripts/monitoring.sh
#
# Installs on a PUBLIC subnet EC2 (via module "monitoring" in root main.tf):
#   • node_exporter  :9100  — host metrics for this EC2 itself
#   • Prometheus     :9090  — scrapes all 4 EC2s
#   • Grafana        :3000  — auto-loads grafana-dashboard.json from repo
#
# Prometheus scrape targets (all private IPs):
#   frontend  :9100   node_exporter
#   backend   :9100   node_exporter
#   backend   :3000   Node.js /metrics  (http_requests_total, duration histogram)
#   db_ec2    :9100   node_exporter
#   self      :9100   node_exporter (this monitoring EC2)
#
# templatefile() vars injected by root main.tf:
#   frontend_private_ip     backend_private_ip
#   db_private_ip           environment         aws_region
#   grafana_admin_password
# ==============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t monitoring-init) 2>&1

echo "============================================"
echo " Monitoring bootstrap — $(date)"
echo "============================================"

FRONTEND_IP="${frontend_private_ip}"
BACKEND_IP="${backend_private_ip}"
DB_IP="${db_private_ip}"
ENVIRONMENT="${environment}"
GRAFANA_PASS="${grafana_admin_password}"

PROMETHEUS_VER="2.51.2"
NODE_EXPORTER_VER="1.7.0"
REPO_URL="https://github.com/asraful0106/3tireApplicationWith_teraform_CI-CD_grafana.git"
APP_DIR="/opt/app"

# ── 1. Base packages ───────────────────────────────────────
apt-get update -y
apt-get install -y curl wget git gnupg2 apt-transport-https software-properties-common

# ── 2. Clone repo (to get monitoring/grafana-dashboard.json) ─
git clone "$REPO_URL" "$APP_DIR"

# ==========================================================
# NODE EXPORTER  (host metrics for this EC2 itself)
# ==========================================================
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

# ==========================================================
# PROMETHEUS
# ==========================================================
useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
mkdir -p /etc/prometheus /var/lib/prometheus

cd /tmp

wget -q "https://github.com/prometheus/prometheus/releases/download/v$${PROMETHEUS_VER}/prometheus-$${PROMETHEUS_VER}.linux-amd64.tar.gz"
tar -xf "prometheus-$${PROMETHEUS_VER}.linux-amd64.tar.gz"
cd "prometheus-$${PROMETHEUS_VER}.linux-amd64"
install -m755 prometheus promtool /usr/local/bin/
cp -r consoles console_libraries /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
cd /tmp && rm -rf "prometheus-$${PROMETHEUS_VER}.linux-amd64"*

# prometheus.yml ───────────────────────────────────────────
cat > /etc/prometheus/prometheus.yml <<PROM
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
    environment: '$${ENVIRONMENT}'

scrape_configs:

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'monitoring'
    static_configs:
      - targets: ['localhost:9100']
        labels: { role: 'monitoring' }

  - job_name: 'frontend'
    static_configs:
      - targets: ['$${FRONTEND_IP}:9100']
        labels: { role: 'frontend' }

  - job_name: 'backend'
    static_configs:
      - targets: ['$${BACKEND_IP}:9100']
        labels: { role: 'backend' }

  - job_name: 'backend_app'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['$${BACKEND_IP}:3000']
        labels: { role: 'backend' }

  - job_name: 'database'
    static_configs:
      - targets: ['$${DB_IP}:9100']
        labels: { role: 'database' }
PROM
chown prometheus:prometheus /etc/prometheus/prometheus.yml

cat > /etc/systemd/system/prometheus.service <<SVC
[Unit]
Description=Prometheus
After=network-online.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090
Restart=always
[Install]
WantedBy=multi-user.target
SVC

# ==========================================================
# GRAFANA
# ==========================================================
wget -q -O - https://apt.grafana.com/gpg.key \
  | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -y && apt-get install -y grafana

# Admin password + disable public sign-up
sed -i "s/^;admin_password =.*/admin_password = $${GRAFANA_PASS}/" /etc/grafana/grafana.ini
sed -i "s/^;allow_sign_up =.*/allow_sign_up = false/"              /etc/grafana/grafana.ini

# Auto-provision: Prometheus datasource
mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<DS
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
DS

# Auto-provision: dashboard from repo
mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards
cat > /etc/grafana/provisioning/dashboards/3tier.yml <<DASH
apiVersion: 1
providers:
  - name: '3tier'
    folder: '3-Tier App'
    type: file
    options:
      path: /var/lib/grafana/dashboards
DASH

cp "$APP_DIR/monitoring/grafana-dashboard.json" /var/lib/grafana/dashboards/
chown -R grafana:grafana /var/lib/grafana/dashboards

# ==========================================================
# Start everything
# ==========================================================
systemctl daemon-reload
systemctl enable --now node_exporter
systemctl enable --now prometheus
systemctl enable --now grafana-server

echo "============================================"
echo " Prometheus : http://<public-ip>:9090"
echo " Grafana    : http://<public-ip>:3000"
echo "============================================"
