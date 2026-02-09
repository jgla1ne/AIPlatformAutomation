#!/usr/bin/env bash
#############################################################################
# Script 0 — Complete Nuclear Cleanup
# Safely remove all AIPlatformAutomation artifacts and reset environment
# Preserves /scripts/ folder
#############################################################################

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="/mnt/data"
CONFIG_DIR="$HOME/config"
LOG_DIR="$DATA_DIR/logs"
DEPLOY_LOG="$LOG_DIR/cleanup.log"

mkdir -p "$LOG_DIR"
touch "$DEPLOY_LOG"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$DEPLOY_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }

log "=== AIPlatformAutomation NUCLEAR CLEANUP START ==="

# --------------------------------------------------
# STEP 1 — Stop and remove all Docker containers, volumes, networks, images
# --------------------------------------------------
log "Stopping all Docker containers..."
docker ps -aq | xargs -r docker stop >> "$DEPLOY_LOG" 2>&1 || true

log "Removing all Docker containers..."
docker ps -aq | xargs -r docker rm -f >> "$DEPLOY_LOG" 2>&1 || true

log "Removing all Docker images..."
docker images -q | xargs -r docker rmi -f >> "$DEPLOY_LOG" 2>&1 || true

log "Removing all Docker volumes..."
docker volume ls -q | xargs -r docker volume rm >> "$DEPLOY_LOG" 2>&1 || true

log "Pruning Docker networks..."
docker network prune -f >> "$DEPLOY_LOG" 2>&1 || true

log "Docker cleanup complete."

# --------------------------------------------------
# STEP 2 — Remove systemd timers/services created by AIPlatformAutomation
# --------------------------------------------------
log "Removing systemd timers/services..."
SYSTEMD_SERVICES=("gdrive-sync.service" "gdrive-sync.timer" "openclaw-sync.service" "openclaw-sync.timer" "tailscale.service")
for svc in "${SYSTEMD_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "$svc"; then
        log "Stopping and disabling $svc..."
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        rm -f "/etc/systemd/system/$svc" 2>/dev/null || true
    fi
done
systemctl daemon-reload

# --------------------------------------------------
# STEP 3 — Remove configuration and credential files
# --------------------------------------------------
log "Removing $CONFIG_DIR (user config)..."
rm -rf "$CONFIG_DIR"

log "Removing AIPlatformAutomation data in $DATA_DIR..."
# Preserve /scripts/, remove everything else
shopt -s extglob
rm -rf "$DATA_DIR"/!(logs|scripts)
shopt -u extglob

# Fix ownership
log "Resetting ownership for $DATA_DIR..."
chown -R "$USER":"$USER" "$DATA_DIR" || true

# --------------------------------------------------
# STEP 4 — Remove APT packages installed by platform
# --------------------------------------------------
log "Removing APT packages..."
APT_PKGS=("nginx" "docker.io" "docker-compose" "python3-pip" "python3-venv")
apt-get remove --purge -y "${APT_PKGS[@]}" >> "$DEPLOY_LOG" 2>&1 || true
apt-get autoremove -y >> "$DEPLOY_LOG" 2>&1 || true

# --------------------------------------------------
# STEP 5 — Final cleanup
# --------------------------------------------------
log "Cleanup complete! System is now reset."
log "Reboot recommended to clear remaining mounts or sessions."
pause

log "=== NUCLEAR CLEANUP END ==="
