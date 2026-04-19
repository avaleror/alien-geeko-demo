# AI Cluster — EIB Image Definitions

Two independent standalone k3s single-node clusters.

| Node | Hardware | IP | Role |
|---|---|---|---|
| pi4-server | Raspberry Pi 4, 8 GB | 192.168.8.7 | Standalone k3s — no workloads |
| orin-server | NVIDIA Jetson Orin, 8 GB | 192.168.8.8 | Standalone k3s + NVIDIA stack + Ollama + Open WebUI |
| Open WebUI | — | http://192.168.8.8:30080 | Chat UI (NodePort on Orin) |

---

## Before you build — checklist

**1. Set encrypted passwords**

Replace `CHANGE-ME` in both `image-definition.yaml` files (root and suse-user):

```bash
openssl passwd -6 yourpassword
```

**2. Add your SSH public key**

Replace `CHANGE-ME` in the `sshKeys` field of both `image-definition.yaml` files:

```bash
cat ~/.ssh/id_ed25519.pub
```

**3. Add your SCC registration code**

Replace `CHANGE-ME` in the `sccRegistrationCode` field of both `image-definition.yaml` files.

**4. Verify your gateway IP**

Both `network/*.yaml` files assume gateway `192.168.8.1`. Change if different.

**5. Verify the base image filenames**

- Pi 4 base image: `SL-Micro.aarch64-6.2-RaspberryPi-GM.raw`
- Orin base image: `SL-Micro.aarch64-6.2-Default-GM.raw` (no Jetson-specific image in SL Micro 6.2)

---

## Directory structure

```
ai-cluster/
├── pi4-server/
│   ├── image-definition.yaml              ← standalone k3s server, no workloads
│   ├── base-images/                       ← place SL-Micro Pi 4 .raw here
│   ├── network/
│   │   └── pi4-server.yaml               ← DHCP + MAC reservation 192.168.8.7
│   ├── custom/
│   │   └── scripts/
│   │       └── 99-alias.sh               ← k=kubectl alias + KUBECONFIG
│   └── kubernetes/
│       └── config/
│           └── server.yaml               ← CNI (Cilium), selinux
└── orin-worker/
    ├── image-definition.yaml             ← standalone k3s server + NVIDIA + Helm charts
    ├── base-images/                      ← place SL-Micro aarch64 .raw here
    ├── network/
    │   └── orin-worker.yaml              ← DHCP + MAC reservation 192.168.8.8
    ├── kubernetes/
    │   ├── config/
    │   │   └── server.yaml               ← selinux, kubeconfig mode
    │   ├── manifests/
    │   │   ├── 01-nvidia-runtimeclass.yaml
    │   │   └── 02-nvidia-device-plugin.yaml
    │   └── helm/
    │       └── values/
    │           ├── ollama-values.yaml    ← GPU, model, ClusterIP service
    │           └── open-webui-values.yaml ← NodePort 30080, points to Ollama ClusterIP
    └── custom/
        └── scripts/
            └── 99-alias.sh              ← k=kubectl alias + KUBECONFIG
```

---

## Download base images

```bash
# Pi 4
cp SL-Micro.aarch64-6.2-RaspberryPi-GM.raw pi4-server/base-images/

# Orin — generic aarch64
cp SL-Micro.aarch64-6.2-Default-GM.raw orin-worker/base-images/
```

---

## Build the images

Pull EIB:

```bash
podman pull registry.suse.com/edge/3.5/edge-image-builder:1.3.2
```

Build Pi 4 image:

```bash
podman run --rm --privileged \
  -v ./pi4-server:/eib \
  registry.suse.com/edge/3.5/edge-image-builder:1.3.2 \
  build --definition-file image-definition.yaml
# Output: pi4-server/vessel-ai-pi4-server.raw
```

Build Orin image:

```bash
podman run --rm --privileged \
  -v ./orin-worker:/eib \
  registry.suse.com/edge/3.5/edge-image-builder:1.3.2 \
  build --definition-file image-definition.yaml
# Output: orin-worker/vessel-ai-orin-server.raw
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
sudo dd if=orin-worker/vessel-ai-orin-server.raw of=/dev/sdX bs=4M status=progress && sync
```

---

## Boot and verify

### Pi 4

```bash
ssh suse-user@192.168.8.7
kubectl get nodes
# Expect: pi4-server   Ready   control-plane
```

### Orin

```bash
ssh suse-user@192.168.8.8
kubectl get nodes
# Expect: orin-server   Ready   control-plane

# Verify GPU is schedulable
kubectl describe node orin-server | grep -A5 "Capacity"
# Should show: nvidia.com/gpu: 1
```

Wait for Ollama — first boot pulls phi3:mini (~2.3 GB):

```bash
kubectl get pods -n ollama -w
# Init → Running → Ready
```

Test the API:

```bash
curl http://192.168.8.8:11434/api/generate \
  -d '{"model":"phi3:mini","prompt":"Hello from the NVIDIA Orin!","stream":false}'
```

Open WebUI — open in browser:

```
http://192.168.8.8:30080
```

---

## GPU verification

```bash
# On Orin — verify GPU resource is advertised
kubectl describe node orin-server | grep -A5 "Capacity"
# nvidia.com/gpu: 1

# Direct Tegra GPU check on the host
ssh suse-user@192.168.8.8
tegrastats
```

---

## Troubleshooting

**GPU not detected by k3s**
```bash
ssh suse-user@192.168.8.8 rpm -q nvidia-container-toolkit
ssh suse-user@192.168.8.8 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep nvidia
```

**Ollama OOM / crash**
- Switch to a smaller model: change `phi3:mini` to `gemma2:2b` in `ollama-values.yaml` and rebuild
- Check available memory: `ssh suse-user@192.168.8.8 free -h`

**Open WebUI cannot reach Ollama**
```bash
kubectl get svc -n ollama
# Verify ollama service is ClusterIP on port 11434
kubectl get pods -n ollama
# Verify Ollama pod is Running and Ready
```
