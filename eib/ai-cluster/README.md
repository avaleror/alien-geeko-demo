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

Generate a strong token and replace `CHANGE-ME-USE-STRONG-RANDOM-TOKEN` in **both** files:
- `pi4-server/image-definition.yaml` → `kubernetes.clusterToken`
- `orin-worker/scripts/99-k3s-agent-join.sh` → `token:` field

```bash
openssl rand -hex 32
```

**2. Set an encrypted password**

Replace `$6$CHANGEME$CHANGEME` in both image-definition.yaml files:

```bash
openssl passwd -6 yourpassword
```

**3. Add your SSH public key**

Replace `ssh-ed25519 AAAA_CHANGE_ME your-key` in both files with your actual public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

**4. Verify your gateway IP**

Both `network/*.yaml` files assume gateway `192.168.8.1`. Change if different.

**5. Verify the Jetson Orin base image filename**

The Pi 4 image filename is well-established. The Orin filename needs verification:

- Pi 4 base image: `SL-Micro.aarch64-6.2-RaspberryPi-GM.raw`
- Orin base image: `SL-Micro.aarch64-6.2-Default-GM.raw` (no Jetson-specific image in 6.2)

---

## Directory structure

```
ai-cluster/
├── pi4-server/
│   ├── image-definition.yaml              ← k3s server, Pi 4 base image, Ollama Helm chart
│   ├── base-images/
│   │   └── SL-Micro.aarch64-6.2-...-Pi.raw.xz            ← download here
│   ├── network/
│   │   └── pi4-server.yaml                ← static IP 192.168.8.7
│   └── kubernetes/
│       ├── manifests/
│       │   ├── 00-metallb-config.yaml     ← IPAddressPool 192.168.8.9 + L2Advertisement
│       │   ├── 01-nvidia-runtimeclass.yaml
│       │   └── 02-nvidia-device-plugin.yaml
│       └── helm/
│           └── values/
│               └── ollama-values.yaml     ← GPU config, model, LoadBalancer, nodeSelector
└── orin-worker/
    ├── image-definition.yaml              ← k3s agent, Jetson base image, NVIDIA stack
    ├── base-images/
    │   └── SL-Micro.aarch64-6.1-...-Jetson.raw.xz        ← download here
    ├── network/
    │   └── orin-worker.yaml               ← static IP 192.168.8.8
    └── scripts/
        └── 99-k3s-agent-join.sh           ← k3s agent config + nvidia-ctk containerd setup
```

---

## Download base images

```bash
# Pi 4
cp SL-Micro.aarch64-6.2-RaspberryPi-GM.raw pi4-server/base-images/

# Orin — generic aarch64 image (no Jetson-specific in 6.2)
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

**Pi 4 — write to microSD or USB SSD:**

```bash
# macOS
diskutil unmountDisk /dev/diskN
sudo dd if=pi4-server/vessel-ai-pi4-server.raw of=/dev/rdiskN bs=4m status=progress && sync
diskutil eject /dev/diskN
```

**Orin — write to NVMe or eMMC via recovery mode:**

The Jetson Orin uses NVIDIA's `flash.sh` tool to write images via USB.
Alternatively, use `dd` to a NVMe drive connected externally, then boot from it.

```bash
# Linux (Orin NVMe in USB enclosure)
sudo dd if=orin-worker/vessel-ai-orin-worker.raw of=/dev/sdX bs=4M status=progress && sync
```

---

## Boot order

1. **Boot Pi 4 first.** Wait for k3s server to come up (~2 min).
   Watch progress: `ssh suse@192.168.8.7 journalctl -fu k3s`

2. **Boot Orin.** It reads `/etc/rancher/k3s/config.yaml` (written by combustion script)
   and joins the server at 192.168.8.7:6443.
   Watch: `ssh suse@192.168.8.8 journalctl -fu k3s-agent`

3. **Verify cluster from Pi 4:**
   ```bash
   ssh suse@192.168.8.7
   sudo k3s kubectl get nodes -o wide
   # Expect: pi4-server (control-plane) + orin-worker (worker)
   ```

4. **Wait for Ollama.** First boot pulls phi3:mini (~2.3 GB) — takes a few minutes.
   ```bash
   sudo k3s kubectl get pods -n ollama -w
   # Status: Init → Running → Ready
   ```

5. **Test the API:**
   ```bash
   curl http://192.168.8.9:11434/api/generate \
     -d '{"model":"phi3:mini","prompt":"Hello from the NVIDIA Orin!","stream":false}'
   ```

---

## GPU verification

Once the cluster is up, verify GPU is available to k3s:

```bash
# On Pi 4 (kubectl access)
sudo k3s kubectl describe node orin-worker | grep -A5 "Capacity"
# Should show: nvidia.com/gpu: 1

# Direct GPU check on Orin
ssh suse@192.168.8.8
nvidia-smi    # or: tegrastats
```

---

## Troubleshooting

**Orin not joining the cluster**
```bash
# On Orin: check the config was written correctly
cat /etc/rancher/k3s/config.yaml
# Verify: server URL and token match exactly

# Watch agent logs
journalctl -fu k3s-agent
```

**GPU not detected by k3s**
```bash
# Verify nvidia-container-toolkit is installed
ssh suse@192.168.8.8 rpm -q nvidia-container-toolkit

# Check containerd config was updated by toolkit
cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep nvidia
```

**Ollama OOM / crash**
- Reduce the model: edit `03-ollama.yaml` and change `phi3:mini` to `gemma2:2b`
- Check available memory: `ssh suse@192.168.8.8 free -h`
- Jetson Orin has unified CPU+GPU memory — reduce `limits.memory` if needed

**MetalLB not assigning VIP**
```bash
sudo k3s kubectl get ipaddresspools -n metallb-system
sudo k3s kubectl get l2advertisements -n metallb-system
sudo k3s kubectl describe svc ollama -n ollama
```
