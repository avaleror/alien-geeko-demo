# AI Cluster — EIB Image Definitions

Two-node k3s cluster: Raspberry Pi 4 (server) + NVIDIA Jetson Orin (GPU worker).

| Node | Hardware | IP | Role |
|---|---|---|---|
| pi4-server | Raspberry Pi 4, 8 GB | 192.168.8.7 | k3s server (control-plane) + Open WebUI |
| orin-worker | NVIDIA Jetson Orin, 8 GB | 192.168.8.8 | k3s agent + Ollama (GPU) |
| MetalLB VIP | — | 192.168.8.9 | Ollama API (port 11434) |
| MetalLB VIP | — | 192.168.8.10 | Open WebUI chat UI (port 8080) |

---

## Before you build — checklist

**1. Set a shared cluster token**

Generate a strong token and replace `CHANGE-ME` in **both** files:
- `pi4-server/kubernetes/config/server.yaml` → `token:`
- `orin-worker/custom/scripts/99-k3s-agent-join.sh` → `token:`

```bash
openssl rand -hex 32
```

**2. Set encrypted passwords**

Replace `CHANGE-ME` in both `image-definition.yaml` files (root and suse-user):

```bash
openssl passwd -6 yourpassword
```

**3. Add your SSH public key**

Replace `CHANGE-ME` in the `sshKeys` field of both `image-definition.yaml` files:

```bash
cat ~/.ssh/id_ed25519.pub
```

**4. Add your SCC registration code**

Replace `CHANGE-ME` in the `sccRegistrationCode` field of both `image-definition.yaml` files.

**5. Verify your gateway IP**

Both `network/*.yaml` files assume gateway `192.168.8.1`. Change if different.

**6. Verify the Jetson Orin base image filename**

- Pi 4 base image: `SL-Micro.aarch64-6.2-RaspberryPi-GM.raw`
- Orin base image: `SL-Micro.aarch64-6.2-Default-GM.raw` (no Jetson-specific image in SL Micro 6.2)

---

## Directory structure

```
ai-cluster/
├── pi4-server/
│   ├── image-definition.yaml              ← k3s server, Pi 4 base image, Helm charts
│   ├── base-images/                       ← place SL-Micro Pi 4 .raw here
│   ├── network/
│   │   └── pi4-server.yaml               ← DHCP + MAC reservation 192.168.8.7
│   ├── custom/
│   │   └── scripts/
│   │       └── 99-alias.sh               ← k=kubectl alias + KUBECONFIG
│   └── kubernetes/
│       ├── config/
│       │   └── server.yaml               ← CNI (Cilium), selinux, cluster token
│       ├── manifests/
│       │   ├── 00-metallb-config.yaml    ← IPAddressPool .9-.10 + L2Advertisement
│       │   ├── 01-nvidia-runtimeclass.yaml
│       │   └── 02-nvidia-device-plugin.yaml  ← pinned to orin-worker
│       └── helm/
│           └── values/
│               ├── ollama-values.yaml    ← GPU, model, nodeSelector orin-worker
│               └── open-webui-values.yaml ← points to Ollama VIP, nodeSelector pi4-server
└── orin-worker/
    ├── image-definition.yaml             ← k3s agent, aarch64 base image, NVIDIA packages
    ├── base-images/                      ← place SL-Micro aarch64 .raw here
    ├── network/
    │   └── orin-worker.yaml              ← DHCP + MAC reservation 192.168.8.8
    └── custom/
        └── scripts/
            └── 99-k3s-agent-join.sh     ← writes k3s agent config (server URL + token)
```

---

## Download base images

```bash
# Pi 4
cp SL-Micro.aarch64-6.2-RaspberryPi-GM.raw pi4-server/base-images/

# Orin — generic aarch64 (no Jetson-specific image in SL Micro 6.2)
cp SL-Micro.aarch64-6.2-Default-GM.raw orin-worker/base-images/
```

---

## Build the images

Pull EIB:

```bash
podman pull registry.suse.com/edge/3.5/edge-image-builder:1.3.2
```

Build Pi 4 server image:

```bash
podman run --rm --privileged \
  -v ./pi4-server:/eib \
  registry.suse.com/edge/3.5/edge-image-builder:1.3.2 \
  build --definition-file image-definition.yaml
# Output: pi4-server/vessel-ai-pi4-server.raw
```

Build Orin worker image:

```bash
podman run --rm --privileged \
  -v ./orin-worker:/eib \
  registry.suse.com/edge/3.5/edge-image-builder:1.3.2 \
  build --definition-file image-definition.yaml
# Output: orin-worker/vessel-ai-orin-worker.raw
```

---

## Write images to storage

**Pi 4 — write to microSD:**

```bash
# macOS
diskutil unmountDisk /dev/diskN
sudo dd if=pi4-server/vessel-ai-pi4-server.raw of=/dev/rdiskN bs=4m status=progress && sync
diskutil eject /dev/diskN
```

**Orin — write to 256 GB NVMe (USB enclosure):**

```bash
# Linux
sudo dd if=orin-worker/vessel-ai-orin-worker.raw of=/dev/sdX bs=4M status=progress && sync
```

---

## Boot order

1. **Boot Pi 4 first.** Wait for k3s server to come up (~2 min).
   ```bash
   ssh suse-user@192.168.8.7 journalctl -fu k3s
   ```

2. **Boot Orin.** It reads `/etc/rancher/k3s/config.yaml` (written by combustion script)
   and joins the Pi 4 server at 192.168.8.7:6443.
   ```bash
   ssh suse-user@192.168.8.8 journalctl -fu k3s-agent
   ```

3. **Verify cluster from Pi 4:**
   ```bash
   ssh suse-user@192.168.8.7
   k get nodes -o wide
   # Expect: pi4-server (control-plane) + orin-worker (worker), both Ready
   ```

4. **Wait for Ollama.** First boot pulls phi3:mini (~2.3 GB) — takes a few minutes.
   ```bash
   k get pods -n ollama -w
   # Status: Init → Running → Ready
   ```

5. **Test the API:**
   ```bash
   curl http://192.168.8.9:11434/api/generate \
     -d '{"model":"phi3:mini","prompt":"Hello from the NVIDIA Orin!","stream":false}'
   ```

6. **Open WebUI:**
   ```
   http://192.168.8.10:8080
   ```

---

## GPU verification

```bash
# On Pi 4 — check GPU is advertised as a schedulable resource
k describe node orin-worker | grep -A5 "Capacity"
# Should show: nvidia.com/gpu: 1

# On Orin — direct GPU check
ssh suse-user@192.168.8.8
tegrastats
```

---

## Troubleshooting

**Orin not joining the cluster**
```bash
# On Orin: verify the env file was written correctly
cat /etc/systemd/system/k3s-agent.service.env
# K3S_TOKEN must match pi4-server/kubernetes/config/server.yaml token exactly

journalctl -fu k3s-agent
```

**GPU not detected by k3s**
```bash
# Verify toolkit is installed
ssh suse-user@192.168.8.8 rpm -q nvidia-container-toolkit

# Check k3s containerd picked up the nvidia runtime
ssh suse-user@192.168.8.8 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep nvidia
```

**Ollama OOM / crash**
- Switch to a smaller model: change `phi3:mini` to `gemma2:2b` in `ollama-values.yaml` and rebuild
- Check available memory: `ssh suse-user@192.168.8.8 free -h`
- Reduce `limits.memory` in `ollama-values.yaml` if needed

**MetalLB not assigning VIPs**
```bash
k get ipaddresspools -n metallb-system
k get l2advertisements -n metallb-system
k describe svc -n ollama
k describe svc -n open-webui
```
