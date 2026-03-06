#!/usr/bin/env bash
# =============================================================================
# Script 0: Complete System Prune - ROBUST VERSION
# =============================================================================
# PURPOSE: To completely and forcefully wipe all Docker assets and data volumes
#          to ensure a pristine state for the next deployment.
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [--keep-data]
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging ---
log() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }

# --- Configuration ---
KEEP_DATA=false
if [[ "${1:-}" == "--keep-data" ]]; then
    KEEP_DATA=true
fi

# --- Main Execution ---
main() {
    log "Starting complete system prune..."

    # -------------------------------------------------------------------------
    # STEP 1: Forcefully stop and remove ALL Docker containers.
    # This is the most critical change. It doesn't rely on names or labels.
    # It finds all running containers and stops them, then removes all containers.
    # -------------------------------------------------------------------------
    log "Forcefully stopping all running Docker containers..."
    RUNNING_CONTAINERS=$(docker ps -q)
    if [ -n "$RUNNING_CONTAINERS" ]; then
        # The `xargs` command handles the case where there are no containers
        docker stop $RUNNING_CONTAINERS
        ok "All running containers stopped."
    else
        ok "No running containers to stop."
    fi

    log "Removing all Docker containers..."
    ALL_CONTAINERS=$(docker ps -a -q)
    if [ -n "$ALL_CONTAINERS" ]; then
        docker rm -f $ALL_CONTAINERS
        ok "All containers removed."
    else
        ok "No containers to remove."
    fi

    # -------------------------------------------------------------------------
    # STEP 2: Prune other Docker assets.
    # This removes unused networks, images, and the build cache.
    # -------------------------------------------------------------------------
    log "Pruning Docker system (networks, images, build cache)..."
    docker system prune -af
    ok "Docker system pruned."

    # -------------------------------------------------------------------------
    # STEP 3: Handle data volumes.
    # This part respects the --keep-data flag.
    # -------------------------------------------------------------------------
    if [ "$KEEP_DATA" = true ]; then
        warn "Skipping data volume deletion due to --keep-data flag."
        log "Manual cleanup of /mnt/data may still be required if issues persist."
    else
        warn "DELETING ALL TENANT DATA in /mnt/data..."
        if [ -d "/mnt/data" ]; then
            # Recreate the directory to ensure it's empty and permissions are clean
            rm -rf /mnt/data
            mkdir -p /mnt/data
            # Set permissions to be world-writable but with sticky bit to prevent users deleting others' files
            chmod 777 /mnt/data
            chmod +t /mnt/data
            ok "Data volumes at /mnt/data have been wiped."
        else
            ok "/mnt/data directory did not exist."
        fi
    fi

    echo ""
    ok "System cleanup is complete. The environment is ready for a fresh deployment."
}

# --- Root Check & Execution ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root (use sudo).${NC}"
    exit 1
fi

main
