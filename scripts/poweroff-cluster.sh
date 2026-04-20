#!/usr/bin/env bash
# Gracefully powers off all cluster nodes.
# All nodes except 192.168.8.99 are shut down first (in parallel),
# then 192.168.8.99 is shut down last.
set -euo pipefail

SSH_USER="${SSH_USER:-suse-user}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

FIRST_NODES=(
  "192.168.8.7"
  "192.168.8.8"
)
LAST_NODE="192.168.8.99"

poweroff_node() {
  local host="$1"
  echo "[$(date +%T)] Sending poweroff to ${host}..."

  # Ignore exit code — the connection will drop mid-command on success
  ssh ${SSH_OPTS} "${SSH_USER}@${host}" "sudo poweroff" 2>/dev/null || true

  echo "[$(date +%T)] Waiting for ${host} to go down..."
  local retries=30
  while (( retries-- > 0 )); do
    if ! ssh ${SSH_OPTS} -o ConnectTimeout=3 "${SSH_USER}@${host}" "exit" 2>/dev/null; then
      echo "[$(date +%T)] ${host} is down."
      return 0
    fi
    sleep 3
  done

  echo "[$(date +%T)] WARNING: ${host} did not respond after 90s — may still be up."
}

# ── Phase 1: shut down all non-last nodes in parallel ────────────────────────
echo "==> Phase 1: powering off ${FIRST_NODES[*]}"
pids=()
for host in "${FIRST_NODES[@]}"; do
  poweroff_node "$host" &
  pids+=($!)
done

# Wait for all background jobs to finish
for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "==> Phase 1 complete."

# ── Phase 2: shut down the last node ─────────────────────────────────────────
echo "==> Phase 2: powering off ${LAST_NODE}"
poweroff_node "${LAST_NODE}"

echo "==> All nodes are down."
