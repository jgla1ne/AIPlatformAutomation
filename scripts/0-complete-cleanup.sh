#!/usr/bin/env bash
# =============================================================================
# Script 0: Complete Cleanup - STABLE v3.1
# =============================================================================
# PURPOSE: Wipes the tenant's environment for a clean deployment.
# USAGE:   sudo bash scripts/0-complete-cleanup.sh <tenant_id>
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES ---
# All logging and utility functions are now sourced from the central script.
# source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"

# --- Basic Logging Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]]; then
    fail "TENANT_ID is required. Usage: sudo bash $0 <tenant_id>"
fi
TENANT_ID="$1"
DATA_ROOT="/mnt/data/${TENANT_ID}"

log "Starting complete cleanup for tenant '${TENANT_ID}'..."

# --- 1. Stop and Remove All Containers ---
log "Stopping all running containers for tenant '${TENANT_ID}'..."
if [[ -f "${DATA_ROOT}/docker-compose.yml" ]]; then
    cd "${DATA_ROOT}"
    if docker compose ps -q | grep -q .; then
        docker compose down --remove-orphans -v
        ok "All containers for tenant stopped and removed."
    else
        ok "No containers were running for this tenant."
    fi
else
    warn "No docker-compose.yml found for tenant. Skipping container cleanup."
fi

# --- 2. Clean Up Docker Resources ---
# This is a global cleanup, use with caution if other Docker apps are running.
log "Performing global Docker system prune..."
docker system prune -af
ok "Docker system resources cleaned up."

# --- 3. Nuclear Cleanup - Remove ALL Data ---
log "Performing nuclear cleanup of ALL tenant data..."
if [ -d "/mnt/data" ]; then
    rm -rf /mnt/data/*
    ok "All tenant data in /mnt/data has been nuclear wiped."
else
    ok "No /mnt/data directory found. Creating clean environment."
fi

# --- 4. Create Fresh Environment ---
log "Creating fresh environment for tenant '${TENANT_ID}'..."
mkdir -p "/mnt/data/${TENANT_ID}"
ok "Fresh tenant directory created."

ok "Cleanup for tenant '${TENANT_ID}' is complete."
