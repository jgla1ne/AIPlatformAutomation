#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="0-complete-cleanup"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_PATH="$ROOT_DIR"
CONFIG_DIR="$HOME_PATH/config"
LOG_DIR="/mnt/data/logs"
DATA_DIR="/mnt/data"

mkdir -p "$LOG_DIR"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() { local prompt="$1"; local default="${2:-y}"; local choice; while true; do read -rp "$prompt [y/n] (default: $default): " choice; choice="${choice:-$default}"; case "$choice" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }

require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

log "STEP 0 — Confirm Nuclear Cleanup"
if ! prompt_yn "This will remove ALL previous data, config, docker containers, images, volumes, apt packages for AI Platform. Proceed?"; then
    log "Cleanup cancelled by user."
    exit 0
fi

# -----------------------------
# STEP 1 — Stop all running containers
# -----------------------------
log "Stopping all Docker containers..."
docker ps -q | xargs -r docker stop
docker ps -aq | xargs -r docker rm
log "All containers stopped and removed."

# -----------------------------
# STEP 2 — Remove Docker images/volumes/networks
# -----------------------------
log "Removing Docker images..."
docker images -q | xargs -r docker rmi -f || true
log "Removing Docker volumes..."
docker volume ls -q | xargs -r docker volume rm || true
log "Removing Docker networks..."
docker network ls -q | xargs -r docker network rm || true

# -----------------------------
# STEP 3 — Clean apt / snap / cached packages (optional)
# -----------------------------
log "Cleaning up apt and snap packages..."
apt-get autoremove -y
apt-get purge -y docker docker-engine docker.io containerd runc || true
apt-get clean

# -----------------------------
# STEP 4 — Remove configuration folder
# -----------------------------
if [ -d "$CONFIG_DIR" ]; then
    log "Removing previous configuration: $CONFIG_DIR"
    rm -rf "$CONFIG_DIR"
fi

# -----------------------------
# STEP 5 — Remove /mnt/data safely (but keep scripts folder)
# -----------------------------
if [ -d "$DATA_DIR" ]; then
    log "Removing previous data in $DATA_DIR..."
    # preserve scripts if accidentally mounted inside /mnt/data
    find "$DATA_DIR" -mindepth 1 -maxdepth 1 ! -name 'scripts' -exec rm -rf {} +
fi

# -----------------------------
# STEP 6 — Re-create directory structure
# -----------------------------
log "Re-creating necessary directory structure..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR/logs"
mkdir -p "$DATA_DIR/volumes"
mkdir -p "$DATA_DIR/backups"
mkdir -p "$DATA_DIR/tmp"

# Ensure proper permissions
chmod -R 755 "$DATA_DIR"
chmod -R 755 "$CONFIG_DIR"

# -----------------------------
# STEP 7 — Reboot if desired
# -----------------------------
if prompt_yn "Cleanup complete. Do you want to reboot now?"; then
    log "Rebooting system..."
    reboot
else
    log "Reboot skipped. You can now run Script 1 to set up the system."
fi

log "Nuclear cleanup complete."

