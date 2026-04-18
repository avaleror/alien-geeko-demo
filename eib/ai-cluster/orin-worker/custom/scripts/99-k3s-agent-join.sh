#!/bin/bash
# Combustion script — runs during first boot, BEFORE k3s starts.
# Writes the k3s agent config so the Orin joins the Pi 4 server on first start.
#
# ⚠️  CHANGE-ME: token must match pi4-server/kubernetes/config/server.yaml token
#
set -euo pipefail

mkdir -p /etc/rancher/k3s/

cat > /etc/rancher/k3s/config.yaml << 'EOF'
server: "https://192.168.8.7:6443"
token: "CHANGE-ME"    # openssl rand -hex 32 — must match pi4-server/kubernetes/config/server.yaml
EOF

chmod 600 /etc/rancher/k3s/config.yaml
echo "[combustion] k3s agent config written — will join https://192.168.8.7:6443"

# Verify Tegra GPU is visible on the host
if [ -c /dev/nvhost-ctrl ]; then
  echo "[combustion] Tegra GPU device found: /dev/nvhost-ctrl"
else
  echo "[combustion] WARNING: /dev/nvhost-ctrl not found — Jetson GPU may not be active"
fi

echo "[combustion] Orin worker setup complete"
