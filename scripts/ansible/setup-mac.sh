#!/usr/bin/env bash
# One-time Mac setup — installs Ansible via Homebrew
set -euo pipefail

if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi

brew install ansible

echo ""
echo "Ansible installed. Run the playbook with:"
echo "  cd scripts/ansible"
echo "  ansible-playbook -i inventory.ini poweroff.yml"
echo ""
echo "Dry run (no changes):"
echo "  ansible-playbook -i inventory.ini poweroff.yml --check"
echo ""
echo "Override k8s distribution (default: k3s):"
echo "  ansible-playbook -i inventory.ini poweroff.yml -e k8s_distribution=rke2"
echo ""
echo "Single node only:"
echo "  ansible-playbook -i inventory.ini poweroff.yml --limit orin-server"
