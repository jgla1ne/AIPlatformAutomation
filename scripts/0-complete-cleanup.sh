#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Script 0 — Complete Nuclear Cleanup
# Prepares system for a fresh Script 1 run
# =====================================================

SCRIPT_NAME="0-complete-cleanup"
LOG_DIR="/mnt/data/logs/cleanup"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
mkdir -p "$LOG_DIR"
touch "$SCRIPT_LOG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }

log "Starting nuclear cleanup for AI Platform Automation"
prompt_yn() {
  local prompt="$1"
  local default="${2:-y}"
  local choice
  while true; do
    read -rp "$prompt [y/n] (default: $default): " choice
    choice="${choice:-$default}"
    case "$choice" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}
# -----------------------------
# Stop and remove all containers
# -----------------------------
log "Stopping all Docker containers..."
docker ps -aq | xargs -r docker stop 2>/dev/null || true

log "Removing all Docker containers..."
docker ps -aq | xargs -r docker rm -f 2>/dev/null || true

# -----------------------------
# Remove Docker volumes and networks
# -----------------------------
log "Removing all Docker volumes..."
docker volume ls -q | xargs -r docker volume rm -f 2>/dev/null || true

log "Removing all Docker networks..."
docker network ls -q | grep -v "bridge\|host\|none" | xargs -r docker network rm 2>/dev/null || true

# -----------------------------
# Purge Docker completely
# -----------------------------
if prompt_yn "Do you want to completely purge Docker (images, packages, binaries)?"; then
  log "Purging Docker packages and images..."
  sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo rm -rf /var/lib/docker /var/lib/containerd
  log "Docker purge completed."
else
  log "Skipping Docker purge."
fi

# -----------------------------
# Purge APT cache and unused packages
# -----------------------------
log "Cleaning up APT packages and cache..."
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean -y
log "APT cleanup completed."

# -----------------------------
# Remove AI Platform data, models, logs (except /scripts)
# -----------------------------
DATA_DIRS=("/mnt/data/config" "/mnt/data/models" "/mnt/data/logs/deploy")
for dir in "${DATA_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    log "Removing $dir ..."
    rm -rf "$dir"/*
  fi
done

# Logs will remain in /mnt/data/logs/cleanup for this script
log "Preserving /scripts/ directory; not removing any scripts"

# -----------------------------
# Optional: remove old system logs
# -----------------------------
log "Cleaning old system logs..."
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
sudo rm -rf /var/log/*.log || true

# -----------------------------
# Final message & auto-reboot
# -----------------------------
log "Nuclear cleanup complete."
if prompt_yn "Do you want to automatically reboot the system now to start fresh?"; then
  log "System will reboot in 5 seconds..."
  sleep 5
  sudo reboot
else
  log "Reboot skipped. You can run Script 1 now."
fi

