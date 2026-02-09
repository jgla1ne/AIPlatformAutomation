#!/usr/bin/env bash
set -euo pipefail

LOG="/tmp/complete-cleanup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== NUCLEAR CLEANUP STARTED ==="

# 1) Stop Docker if installed/running
if command -v docker >/dev/null 2>&1; then
  echo "[CLEANUP] Stopping any running containers..."
  docker ps -q | xargs -r docker stop || true
else
  echo "[CLEANUP] Docker not found, skipping container stop"
fi

# 2) Remove Docker artifacts if docker exists
if command -v docker >/dev/null 2>&1; then
  echo "[CLEANUP] Removing Docker containers..."
  docker ps -aq | xargs -r docker rm -f || true

  echo "[CLEANUP] Removing Docker images..."
  docker images -q | xargs -r docker rmi -f || true

  echo "[CLEANUP] Removing Docker volumes..."
  docker volume ls -q | xargs -r docker volume rm -f || true

  echo "[CLEANUP] Pruning Docker networks..."
  docker network prune -f || true
else
  echo "[CLEANUP] Docker not found, skipping Docker cleanup"
fi

# 3) Remove config directories
HOME_PATH="$(eval echo ~${SUDO_USER:-$USER})"
REPO_PATH="$HOME_PATH/AIPlatformAutomation"

echo "[CLEANUP] Removing user config folder: $HOME_PATH/config"
rm -rf "$HOME_PATH/config" || true

echo "[CLEANUP] Removing repo config folder: $REPO_PATH/config"
rm -rf "$REPO_PATH/config" || true

# 4) Unmount and remove /mnt/data
if mountpoint -q /mnt/data; then
  echo "[CLEANUP] Unmounting /mnt/data..."
  umount -lf /mnt/data || true
fi

echo "[CLEANUP] Removing /mnt/data..."
rm -rf /mnt/data || true

# 5) Leave scripts in place
echo "[CLEANUP] Preserving /scripts folder"

echo "=== NUCLEAR CLEANUP COMPLETE ==="
echo "Log: $LOG"

