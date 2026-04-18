#!/bin/bash
# Combustion script — runs during first boot, BEFORE k3s starts.
# Two jobs:
#   1. Configure k3s agent to join the Pi 4 server cluster.
#   2. Wire nvidia-container-toolkit into k3s's containerd so GPU works in pods.
#
# ⚠️  CHANGE-ME: token must match pi4-server/image-definition.yaml clusterToken
#
set -euo pipefail

# ─── 1. k3s agent config ──────────────────────────────────────────────────────
mkdir -p /etc/rancher/k3s/

cat > /etc/rancher/k3s/config.yaml << 'EOF'
server: "https://192.168.8.7:6443"
token: "CHANGE-ME-USE-STRONG-RANDOM-TOKEN"
EOF

chmod 600 /etc/rancher/k3s/config.yaml
echo "[combustion] k3s agent config written — will join https://192.168.8.7:6443"

# ─── 2. NVIDIA container runtime — configure k3s containerd ──────────────────
# k3s uses its own containerd instance at /var/lib/rancher/k3s/agent/
# nvidia-container-toolkit's auto-config targets the system containerd.
# We pre-configure k3s containerd manually so GPU is available immediately
# when the agent starts for the first time.
#
# k3s reads /etc/rancher/k3s/config.yaml for extra containerd config path.
# The nvidia-ctk tool writes the correct stanzas to the target config file.

CONTAINERD_CONFIG_DIR="/var/lib/rancher/k3s/agent/etc/containerd"
mkdir -p "${CONTAINERD_CONFIG_DIR}"

# Generate nvidia runtime config for k3s containerd
# This runs if nvidia-container-toolkit was installed (layer 2 of the GPU stack)
if command -v nvidia-ctk &>/dev/null; then
  nvidia-ctk runtime configure \
    --runtime=containerd \
    --config="${CONTAINERD_CONFIG_DIR}/config.toml" \
    --set-as-default
  echo "[combustion] nvidia-container-runtime configured for k3s containerd"
else
  echo "[combustion] WARNING: nvidia-ctk not found — GPU passthrough will not work"
  echo "[combustion] Verify nvidia-container-toolkit was installed via EIB packages"
fi

# ─── 3. Verify Tegra GPU is visible on the host ──────────────────────────────
if [ -c /dev/nvhost-ctrl ]; then
  echo "[combustion] Tegra GPU device found: /dev/nvhost-ctrl"
else
  echo "[combustion] WARNING: /dev/nvhost-ctrl not found — Jetson GPU may not be active"
fi

echo "[combustion] Orin worker setup complete"
