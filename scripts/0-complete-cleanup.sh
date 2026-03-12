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

main() {
    # --- Tenant ID Validation ---
    if [[ -z "${1:-}" ]]; then
        echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
        exit 1
    fi
    
    TENANT_ID="$1"
    COMPOSE_PROJECT_NAME="ai-${TENANT_ID}" # Use the official Docker Compose project name
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    
    log "Starting TRUE NUCLEAR cleanup for tenant '${TENANT_ID}'..."

    # --- 1. Brute Force Stop & Remove All Tenant Containers ---
    log "Finding and stopping all containers for project '${COMPOSE_PROJECT_NAME}'..."
    # Find all containers (running or stopped) for this project
    container_ids=$(docker ps -a --filter "name=${COMPOSE_PROJECT_NAME}" -q)
    if [[ -n "$container_ids" ]]; then
        docker stop $container_ids
        docker rm $container_ids
        ok "All containers for project '${COMPOSE_PROJECT_NAME}' stopped and removed."
    else
        ok "No containers found for project '${COMPOSE_PROJECT_NAME}'."
    fi

    # --- 2. Brute Force Destroy All Tenant Volumes (This will get the Ollama models) ---
    log "Finding and destroying all volumes for project '${COMPOSE_PROJECT_NAME}'..."
    # The 'label' filter is the key to finding volumes created by docker-compose
    docker volume prune -af --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
    ok "All Docker volumes for project '${COMPOSE_PROJECT_NAME}' have been destroyed."

    # --- 3. Nuclear Wipe of Bind-Mounted Data ---
    log "Performing nuclear wipe of ALL tenant data in ${DATA_ROOT}..."
    if [[ -d "${DATA_ROOT}" ]]; then
        rm -rf "${DATA_ROOT}"
        ok "All tenant data in ${DATA_ROOT} has been nuclear wiped."
    else
        ok "Tenant data directory did not exist."
    fi

    # --- 4. Global Docker System Prune (for dangling images) ---
    log "Performing global Docker system prune..."
    docker system prune -af
    ok "Docker system resources cleaned up."
    
    # --- 5. Create Fresh Environment ---
    log "Creating fresh environment for tenant '${TENANT_ID}'..."
    mkdir -p "${DATA_ROOT}"
    chown "${SUDO_USER}:${SUDO_USER}" "${DATA_ROOT}"
    ok "Fresh tenant directory created."
    
    ok "TRUE NUCLEAR cleanup for tenant '${TENANT_ID}' is complete."
}

# Call main function
main "$@"
