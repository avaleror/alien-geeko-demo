#!/bin/bash
# Combustion script — runs during first boot, BEFORE k3s starts.
# Configures the k3s-agent systemd service to join the Pi 4 server.
#
# Equivalent to running:
#   K3S_TOKEN=SECRET k3s agent --server https://192.168.8.7:6443
#
# ⚠️  CHANGE-ME: K3S_TOKEN must match pi4-server/kubernetes/config/server.yaml token
#
set -euo pipefail

mkdir -p /etc/systemd/system/

cat > /etc/systemd/system/k3s-agent.service.env << 'EOF'
K3S_TOKEN=CHANGE-ME
K3S_URL=https://192.168.8.7:6443
EOF

chmod 600 /etc/systemd/system/k3s-agent.service.env
echo "[combustion] k3s-agent env written — will join https://192.168.8.7:6443"

# Verify Tegra GPU is visible on the host
if [ -c /dev/nvhost-ctrl ]; then
  echo "[combustion] Tegra GPU device found: /dev/nvhost-ctrl"
else
  echo "[combustion] WARNING: /dev/nvhost-ctrl not found — Jetson GPU may not be active"
fi

echo "[combustion] Orin worker setup complete"
