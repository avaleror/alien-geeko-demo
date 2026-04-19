#!/bin/bash
# Combustion script — runs during first boot, BEFORE k3s starts.
# 1. Configures NVIDIA container runtime for k3s containerd
# 2. Creates a systemd service for Jetson performance mode (runs every boot)
#
# Combustion runs in a chroot — packages installed by EIB are already present.
set -euo pipefail

# ─── 1. Configure NVIDIA runtime for k3s containerd ──────────────────────────
# k3s uses a non-standard containerd config path. nvidia-ctk must write to it
# so the runtime is available when k3s starts for the first time.
K3S_CONTAINERD_CONFIG="/etc/rancher/k3s/config.d/nvidia-containerd.toml"
mkdir -p /etc/rancher/k3s/config.d

nvidia-ctk runtime configure \
  --runtime=containerd \
  --config "${K3S_CONTAINERD_CONFIG}" \
  --set-as-default

echo "[combustion] NVIDIA runtime configured at ${K3S_CONTAINERD_CONFIG}"

# ─── 2. Jetson performance mode systemd service ───────────────────────────────
# Runs at every boot — unlocks full Orin performance.
# Without this: GPU runs at ~611 MHz. With this: ~1007 MHz (+39%).
cat > /etc/systemd/system/jetson-performance.service << 'EOF'
[Unit]
Description=Jetson Orin maximum performance mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvpmodel -m 0
ExecStartPost=/usr/bin/jetson_clocks
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable jetson-performance.service
echo "[combustion] jetson-performance.service enabled (nvpmodel -m 0 + jetson_clocks)"

echo "[combustion] NVIDIA setup complete"
