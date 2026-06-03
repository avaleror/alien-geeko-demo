#!/bin/bash
# Build an alien-geeko EIB image.
# Usage: ./scripts/eib-build.sh <target>
# Targets: pi4-k3s | x86-k3s
#
# Prerequisites:
#   1. Drop the SL Micro base image into eib/<target>/base-images/
#   2. Fill in all CHANGE-ME values in eib/<target>/image-definition.yaml
#      and eib/<target>/kubernetes/config/server.yaml
#   3. Fill in your MAC address / gateway in eib/<target>/network/*.yaml
#   4. The alien-geeko Helm chart must be published to GitHub Pages
#      (merge feat/helm-chart to main — GitHub Actions handles the publish).
#
# The script tries podman first, falls back to docker.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EIB_IMAGE="registry.suse.com/edge/3.6/edge-image-builder:1.3.3.1"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target>"
  echo "Available targets: pi4-k3s | x86-k3s"
  exit 1
fi

EIB_DIR="${REPO_ROOT}/eib/${TARGET}"

if [[ ! -d "$EIB_DIR" ]]; then
  echo "Error: EIB config directory not found: ${EIB_DIR}"
  exit 1
fi

if [[ -z "$(ls "${EIB_DIR}/base-images/"*.{iso,raw} 2>/dev/null)" ]]; then
  echo "Error: no base image found in ${EIB_DIR}/base-images/"
  echo "Download the SL Micro 6.2 image from SUSE Customer Center and place it there."
  exit 1
fi

if command -v podman &>/dev/null; then
  RUNTIME="podman"
else
  RUNTIME="docker"
fi

echo "Building EIB image for target: ${TARGET}"
echo "Runtime: ${RUNTIME}"
echo "EIB dir: ${EIB_DIR}"
echo ""

"$RUNTIME" run --rm -it \
  --privileged \
  -v "${EIB_DIR}:/eib-mount" \
  "$EIB_IMAGE" \
  build --definition-file image-definition.yaml

echo ""
echo "Done. Output image: ${EIB_DIR}/$(grep outputImageName "${EIB_DIR}/image-definition.yaml" | awk '{print $2}')"
