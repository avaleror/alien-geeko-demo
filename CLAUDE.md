# SUSE Edge KubeCon Demo — Project Handoff
## Claude Code Context Document

This file captures all relevant context, decisions, architecture, and current
state from the Claude.ai session that produced this project. Read this before
starting any work.

---

## Project Overview

**What this is:** A KubeCon booth demo for SUSE Edge 3.5 targeting Technical
Architects and Practitioners. The demo follows a "Mission Control" narrative
where the x86 NUC is Mission Control and the Raspberry Pi boards are vessels
in a fleet. The app (`alien-geeko`) is the crew manifest transmitted to all vessels.

**Demo format:** Problem → Solution → Live Demo  
**Narrative theme:** Mission Control — "Ground Control to All Ships"  
**Target audience:** KubeCon + CloudNativeCon Technical Architects / Practitioners

---

## Repositories

**App repo:** `https://github.com/SUSE-Technical-Marketing/Alien-Geeko`  
**Branch:** `main`  
**License:** Apache 2.0  
**Copyright:** 2025 SUSE LLC

---

## Demo Hardware

| Role | Hardware | OS | Provisioning |
|---|---|---|---|
| Mission Control | x86 NUC | Any Linux | Manual — runs k3s + Rancher + Fleet + Elemental |
| Vessel Alpha | Raspberry Pi 4 | SL Micro 6.2 | EIB (Edge Image Builder) |
| Vessel Beta | Raspberry Pi 4 (spare) | SL Micro 6.2 | Elemental (phone-home) |
| Vessel Delta | Raspberry Pi 5 (×N) | openSUSE MicroOS or any k3s | Rancher Import |
| Standby | x86 Spare NUC | Any | EIB or Import |

**Critical hardware note:** Raspberry Pi 5 is NOT supported in SL Micro 6.2.
SL Micro 6.2 only supports BCM2711 (Pi 4) and BCM2837 (Pi 3). Pi 5 uses BCM2712.
SUSE delivered U-Boot support for Pi 5 in November 2025 for openSUSE Tumbleweed/MicroOS only.
Full SL Micro support is planned for 6.3 (late 2026).
Therefore Pi 5 boards run k3s independently and are IMPORTED into Rancher,
not provisioned via EIB or Elemental.

---

## The alien-geeko App

### What it does
A Node.js web app that renders a Nostromo CRT terminal UI in the browser
showing live Kubernetes cluster vitals — node count, K8s version, architecture,
OS image, distribution (k3s/RKE2), node role, memory, CPU, load average.

### How it gets data
- Queries K8s API directly at runtime using the mounted service account token
- `GET /version` → K8s version + distribution detection
- `GET /api/v1/nodes` → node count, arch, OS image, node role
- Downward API env vars → pod/node metadata (always available, no API needed)
- Results cached 60 seconds to avoid hammering the API on resource-constrained Pi nodes

### k3s / RKE2 specific behaviour
- **Projected token rotation:** k3s and RKE2 rotate service account tokens every ~1 hour.
  `server.js` re-reads the token from disk on EVERY API call — never cached at module level.
- **5s timeout** on all K8s API requests — Pi 5 under load can be slow.
- **Distribution detection** from `gitVersion`: `+k3s1` → k3s, `+rke2r1` → RKE2
- **Node role detection** from labels: `control-plane`, `master` (older k3s), `etcd` (RKE2)
- **PSA labels** on Namespace required for RKE2 (`pod-security.kubernetes.io/enforce: baseline`)
- **seccompProfile: RuntimeDefault** — required for restricted PSA, supported by containerd

### API endpoints
- `GET /` → serves `index.html` (Nostromo terminal UI)
- `GET /api/info` → JSON cluster info (60s cache)
- `GET /health` → `200 OK` (liveness/readiness probe)

### Container image
- Base: `registry.suse.com/bci/nodejs:20` (SUSE BCI, NOT Alpine)
- User: `geeko` with explicit `--uid 1000 --gid 1000`
- **CRITICAL:** `runAsUser: 1000` in deployment MUST match the UID in Dockerfile.
  The original bug was `--system` flag giving UID in 100-999 range → EACCES on /app/server.js
- Multi-arch: `linux/amd64` + `linux/arm64`
- Registry: `ghcr.io/suse-edge/alien-geeko:latest`

### Build commands
```bash
# Multi-arch (recommended)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/suse-edge/alien-geeko:1.0.1 --push .

# Per-arch separately (for native builds on Pi)
docker build --platform linux/amd64 -t REGISTRY/alien-geeko:1.0.1-amd64 --push .
docker build --platform linux/arm64 -t REGISTRY/alien-geeko:1.0.1-arm64 --push .
docker manifest create REGISTRY/alien-geeko:1.0.1 \
  REGISTRY/alien-geeko:1.0.1-amd64 REGISTRY/alien-geeko:1.0.1-arm64
docker manifest push REGISTRY/alien-geeko:1.0.1
```

---

## Repository Structure

```
alien-geeko/
├── fleet.yaml                           ← Fleet Helm bundle definition
├── chart/
│   └── alien-geeko/
│       ├── Chart.yaml                   ← Helm chart metadata v1.0.1
│       ├── values.yaml                  ← All defaults, per-cluster overrides here
│       └── templates/
│           ├── _helpers.tpl             ← name/label helpers
│           ├── namespace.yaml           ← PSA labels + Helm ownership metadata
│           ├── serviceaccount.yaml
│           ├── rbac.yaml                ← ClusterRole + ClusterRoleBinding
│           ├── configmap.yaml           ← CLUSTER_NAME display name
│           ├── deployment.yaml
│           └── service.yaml             ← NodePort/LoadBalancer toggle
├── app/
│   ├── server.js                        ← Node.js server + K8s API client
│   └── index.html                       ← Nostromo CRT terminal UI (self-contained)
├── Dockerfile                           ← BCI Node.js 20, geeko uid/gid 1000
├── LICENSE                              ← Apache 2.0
├── NOTICE                               ← SUSE LLC copyright
└── README.md                            ← Full documentation
```

---

## Helm Chart

The app is deployed via a Helm chart managed by Fleet.
The chart lives at `chart/alien-geeko/` in the repo root.

### Key values (values.yaml)
```yaml
clusterName: "EDGE-CLUSTER"        # Override per cluster via fleet.yaml
image:
  repository: ghcr.io/suse-edge/alien-geeko
  tag: "latest"
service:
  type: NodePort
  nodePort: 30080                   # Access: http://<NODE_IP>:30080
  loadBalancer:
    enabled: false                  # Set true for MetalLB clusters
    metalLBPool: "default"
securityContext:
  runAsUser: 1000                   # Must match Dockerfile --uid 1000
  runAsGroup: 1000                  # Must match Dockerfile --gid 1000
```

### Per-cluster name override
In `fleet.yaml` targets:
```yaml
helm:
  values:
    clusterName: "PI-CLUSTER-MADRID-01"
```

---

## Fleet Configuration

### fleet.yaml structure
```yaml
defaultNamespace: alien-geeko       # NOT 'namespace' — allows cluster-scoped resources
helm:
  chart: chart/alien-geeko
  releaseName: alien-geeko
targets:
  - name: pi-arm-cluster
    clusterSelector:
      matchLabels:
        demo: "true"                # REQUIRED on ALL targets — no demo=true = nothing deployed
        edge-type: pi-cluster
        kubernetes.io/arch: arm64
    helm:
      values:
        clusterName: "PI-CLUSTER-ARM64"
  - name: x86-cluster
    clusterSelector:
      matchLabels:
        demo: "true"
        edge-type: x86-cluster
    helm:
      values:
        clusterName: "X86-EDGE-NODE"
  - name: all-demo-clusters         # Fallback for demo=true clusters without edge-type
    clusterSelector:
      matchLabels:
        demo: "true"
  # NO clusterSelector: {} — clusters without demo=true get nothing
```

### Cluster labels to set in Rancher
| Cluster | Labels |
|---|---|
| Pi 4 (EIB) | `demo=true`, `edge-type=pi-cluster`, `kubernetes.io/arch=arm64` |
| Pi 4 (Elemental) | `demo=true`, `edge-type=pi-cluster`, `kubernetes.io/arch=arm64` |
| Pi 5 (Imported) | `demo=true`, `edge-type=pi5-imported`, `kubernetes.io/arch=arm64` |
| x86 NUC | `demo=true`, `edge-type=x86-cluster` |

### Fleet GitRepo setup in Rancher
- **Continuous Delivery → Git Repos → Add Repository**
- URL: `https://github.com/SUSE-Technical-Marketing/Alien-Geeko`
- Branch: `main`
- Target: **"All clusters in the workspace"** (label filtering handled by fleet.yaml)

### Known Fleet errors and fixes

**"invalid cluster scoped object found"**
- Cause: `namespace:` used instead of `defaultNamespace:` in fleet.yaml
- Fix: Change to `defaultNamespace: alien-geeko`

**"namespace already exists / invalid ownership metadata"**
- Cause: Namespace pre-existed without Helm ownership labels
- Fix: `kubectl label ns alien-geeko app.kubernetes.io/managed-by=Helm --overwrite`
  and `kubectl annotate ns alien-geeko meta.helm.sh/release-name=alien-geeko meta.helm.sh/release-namespace=alien-geeko --overwrite`

**"EOF" on git clone**
- Cause: Cluster cannot reach GitHub (firewall/proxy/DNS)
- Fix: Check egress, or use local Gitea on the NUC for air-gapped/venue demos

**Node count shows "?"**
- Cause: ClusterRoleBinding deployed to wrong namespace (subjects.namespace was wrong)
- Fix: Verify with `kubectl auth can-i list nodes --as=system:serviceaccount:alien-geeko:alien-geeko`
  Must return `yes`. Re-apply manifest if not.

---

## RBAC

```yaml
ClusterRole: alien-geeko-reader
  - nodes: get, list
  - /version nonResourceURL: get

ClusterRoleBinding: alien-geeko-reader
  subjects:
    - ServiceAccount: alien-geeko
      namespace: alien-geeko      # MUST match actual deployment namespace
```

**The namespace in subjects MUST be correct.** This was the root cause of
node count showing "?" — the binding pointed at the wrong namespace so the
service account had no permissions to list nodes.

---

## Accessing the App

| Method | Command / URL |
|---|---|
| Port-forward (any cluster) | `kubectl port-forward svc/alien-geeko 8080:80 -n alien-geeko` → `http://localhost:8080` |
| NodePort (physical cluster) | `http://<NODE_IP>:30080` |
| Rancher Desktop | Port-forward only — NodePort addresses VM internal network |
| Via Rancher UI | Cluster → Service Discovery → Services → alien-geeko |

---

## Presentation Deck

**Final deck:** `SUSE-Edge-MissionControl.pptx` (18 slides)  
**Design system:** Nostromo terminal theme  
**Generator script:** `generate-mission-control.js` (PptxGenJS + sharp + react-icons)

### Colour palette
```
bgDeep:  #050F0A    bgMid:   #0A1F14    bgPanel: #0D2318
suse:    #73BE44    suseDark:#4A8A28    suseDeep:#1E4A10
teal:    #17B3A3    amber:   #FFB000    purple:  #9B59B6
red:     #FF3D2E    textPri: #E8F5E0    textSec: #8DB890
```

### Fonts
- `SUSE` (Google Fonts) — headings and body
- `Courier New` — monospace terminal labels

### Deck structure (18 slides)
1. Title — "Ground Control to All Ships"
2. Market Reality — $350B edge market, 15% skills gap
3. The Problem — heterogeneous hardware
4. Three Scenarios — EIB / Elemental / Rancher Import
5. SUSE Edge 3.5 platform intro
6. EIB deep-dive — "Pre-Program the Flight"
7. Elemental deep-dive — "Signal Acquired"
8. EIB vs Elemental comparison table
9. Rancher + Fleet — "Mission Control to 1M clusters"
10. Vessel In Orbit Detected — Rancher Import how-it-works
11. Hybrid Arch — all hardware on one slide
12. THIS IS NOT A DRILL — all 5 physical devices
13. Follow the Fleet — 4 demo steps
14. Built Open. Built for Deep Space.
15. Use Cases
16. CTA — "Mission Control is Ready"
17. Mission Debrief — conclusions
18. SUSE ending slide with chameleon logo

### Mission Control narrative
- Clusters → vessels/ships
- Provisioning → launch profiles
- Management plane → Mission Control
- Deploy → transmit/uplink
- Rancher Import → hailing frequencies / establish comms
- Footer ID: `MISSION-CONTROL//SYS`
- Footer status: `UPLINK.NOMINAL`
- Vessel names: Alpha (EIB Pi 4), Beta (Elemental Pi 4), Delta (imported Pi 5)

---

## EIB (Edge Image Builder)

- Runs as a container via Podman
- Produces raw disk images (NOT ISO) for Raspberry Pi
- **Must use `imageType: raw`** for Pi — ISOs don't boot on Pi
- **Do NOT use Raspberry Pi Imager** to write EIB images — it reformats the partition table
- **Use `dd` directly:**
  ```bash
  # macOS (use rdisk for speed)
  diskutil unmountDisk /dev/diskN
  sudo dd if=image.raw of=/dev/rdiskN bs=4m status=progress && sync
  diskutil eject /dev/diskN
  ```
- EIB version: 1.3.2
- Registry: `registry.suse.com/edge/3.5/edge-image-builder:1.3.2`
- SL Micro 6.2 Raspberry Pi image: `SL-Micro.aarch64-6.2-Default-GM-Raspberry-Pi.raw.xz`

### Pi 4 EIB config skeleton
```yaml
apiVersion: 1.0
image:
  imageType: raw
  arch: aarch64
  baseImage: SL-Micro.aarch64-6.2-Default-GM-Raspberry-Pi.raw.xz
  outputImageName: vessel-alpha.raw
operatingSystem:
  users:
    - username: suse
      password: YOUR_PASSWORD
  ssh:
    enabled: true
    authorizedKeys:
      - "ssh-ed25519 AAAA..."
kubernetes:
  version: v1.29.3+k3s1
  nodes:
    - hostname: pi4-vessel-alpha
      type: server
```

---

## Elemental

- Phone-home onboarding for unknown hardware
- Node boots, acquires signal, calls back to Rancher Elemental endpoint
- EIB builds the image with Elemental registration config pre-baked
- Node appears in Rancher → Elemental inventory after boot
- Cluster assigned in Rancher UI post-registration
- Fleet delivers alien-geeko within seconds of cluster assignment

---

## Pi Hardware Notes

### Pi 4 (SL Micro 6.2 — fully supported)
- BCM2711 SoC — supported in SL Micro 6.2
- Boot from microSD or USB SSD
- No EEPROM changes needed for microSD boot

### Pi 5 (NOT supported in SL Micro 6.2)
- BCM2712 SoC — NOT in SL Micro 6.2 supported list
- Use openSUSE MicroOS or Tumbleweed instead
- EEPROM must be updated for NVMe boot: `BOOT_ORDER=0xf416`
- PCIe must be enabled in config.txt: `dtparam=pciex1` + `[pi5] dtparam=pciex1_gen=3`
- Auto-suspend fix (GDM issue): `systemctl mask sleep.target suspend.target hibernate.target`
- Fan check: `sensors` → look for `pwmfan-isa-0000`, `cat /sys/class/thermal/cooling_device0/cur_state`
- SL Micro 6.3 (late 2026) will add Pi 5 support

### Raspberry Pi OS vs SUSE boot
- Raspberry Pi OS: firmware in EEPROM directly runs vendor kernel — no bootloader
- SUSE: uses U-Boot → GRUB2 → kernel (requires UEFI firmware interfaces)
- SUSE delivered U-Boot support for Pi 5 in November 2025

---

## Presentation Generator

The deck is generated programmatically with Node.js. To regenerate:

```bash
# Install deps (from suse-nostromo working dir)
npm install pptxgenjs sharp react react-dom react-icons

# Generate final Mission Control deck
node generate-mission-control.js
# Output: SUSE-Edge-MissionControl.pptx

# QA: convert to PDF and render as JPEGs
python soffice.py --headless --convert-to pdf SUSE-Edge-MissionControl.pptx
pdftoppm -jpeg -r 150 SUSE-Edge-MissionControl.pdf slide
```

The generator is a single-file Node.js script. All slides are self-contained —
images embedded as base64, no external dependencies at render time.

---

## Assets

| File | Description |
|---|---|
| `suse_logo_transparent.png` | SUSE chameleon, black bg removed, green on transparent |
| `suse-mission-control-logo.png` | 1040×1040 Mission Control logo card |
| `telco_icon.png` | 400×400 cell tower icon, SUSE green on #050F0A |
| `cncf_logo.png` | CNCF hex+pinwheel card in presentation style |

---

## Pending / Known Issues

- [ ] Update image tag in `chart/alien-geeko/values.yaml` from `latest` to `1.0.1` before demo
- [ ] Set meaningful `clusterName` per cluster in `fleet.yaml` targets before demo
- [ ] Pi 5 Pi Imager issue — do NOT use Pi Imager for EIB raw images, use `dd`
- [ ] GDM auto-suspend on Pi — disable with `systemctl mask sleep.target suspend.target`
- [ ] Fleet EOF error — if venue network blocks GitHub, run local Gitea on x86 NUC
- [ ] `alien-geeko-manifest.yaml` must be applied on each cluster BEFORE Fleet reconciles

---

## Key Technical Decisions Made

1. **No init container** — server.js queries K8s API directly at runtime.
   Init container approach was abandoned because it wrote to a volume that the
   main container never read, and kubectl version --short was removed in k3s 1.28.

2. **BCI not Alpine** — base image is `registry.suse.com/bci/nodejs:20`.
   `groupadd`/`useradd` (not Alpine's `addgroup`/`adduser`), curl available by default.

3. **Explicit UID/GID 1000** in Dockerfile — `--system` flag gives UID in 100-999
   range which doesn't match `runAsUser: 1000` in deployment → EACCES.

4. **`defaultNamespace` not `namespace` in fleet.yaml** — `namespace` blocks
   cluster-scoped resources (Namespace, ClusterRole, ClusterRoleBinding).

5. **Helm chart over raw YAML + kustomize** — per-cluster values via `helm.values`
   in fleet.yaml targets, no overlay files needed, Helm ownership metadata
   prevents "invalid ownership metadata" errors on pre-existing namespaces.

6. **demo=true on ALL Fleet targets** — if any target lacks the label,
   clusters matching only that target's other labels get the bundle unexpectedly.

7. **Pi 5 = Rancher Import** — not EIB, not Elemental, because SL Micro 6.2
   doesn't support BCM2712. Pi 5 runs k3s natively and is imported via Rancher
   cluster agent manifest (kubectl apply -f <rancher-import-url>).
