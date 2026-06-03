#!/bin/bash
# Writes the alien-geeko HelmChart CRD into the K3s auto-deploy manifests
# directory before K3s starts. K3s picks it up on first boot, fetches the
# chart from the Helm repo, and pulls the container image.
# Requires internet access on first boot (QEMU user network provides this).

mkdir -p /var/lib/rancher/k3s/server/manifests/

cat > /var/lib/rancher/k3s/server/manifests/alien-geeko.yaml << 'EOF'
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: alien-geeko
  namespace: kube-system
spec:
  chart: alien-geeko
  repo: https://avaleror.github.io/alien-geeko-demo
  version: 0.1.0
  targetNamespace: alien-geeko
  createNamespace: true
  valuesContent: |
    clusterName: "CLUSTER-ARM64"
    service:
      type: NodePort
      port: 80
      targetPort: 3000
      nodePort: 30080
    topologySpread:
      enabled: true
      maxSkew: 1
      whenUnsatisfiable: DoNotSchedule
EOF
