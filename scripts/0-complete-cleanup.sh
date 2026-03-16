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

    # --- 1. Brute Force Stop & Remove ALL AI Platform Containers ---
    log "Finding and stopping ALL AI platform containers..."
    # Find all containers with ai- prefix (any tenant)
    container_ids=$(docker ps -a --filter "name=ai-" -q)
    if [[ -n "$container_ids" ]]; then
        log "Found containers: $container_ids"
        docker stop $container_ids || true
        docker rm $container_ids || true
        ok "All AI platform containers stopped and removed."
    else
        ok "No AI platform containers found."
    fi
    
    # Also check for the specific tenant
    log "Finding and stopping all containers for project '${COMPOSE_PROJECT_NAME}'..."
    container_ids=$(docker ps -a --filter "name=${COMPOSE_PROJECT_NAME}" -q)
    if [[ -n "$container_ids" ]]; then
        docker stop $container_ids || true
        docker rm $container_ids || true
        ok "All containers for project '${COMPOSE_PROJECT_NAME}' stopped and removed."
    else
        ok "No containers found for project '${COMPOSE_PROJECT_NAME}'."
    fi

    # --- 2. Brute Force Destroy ALL AI Platform Volumes ---
    log "Finding and destroying ALL AI platform volumes..."
    # Remove all volumes with ai- prefix
    volume_names=$(docker volume ls --filter "name=ai-" -q)
    if [[ -n "$volume_names" ]]; then
        log "Found volumes: $volume_names"
        docker volume rm $volume_names || true
        ok "All AI platform volumes removed."
    else
        ok "No AI platform volumes found."
    fi
    
    # Also prune by project label
    docker volume prune -af --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}" || true
    ok "All Docker volumes for project '${COMPOSE_PROJECT_NAME}' have been destroyed."

    # --- 3. Nuclear Wipe of ALL Tenant Data ---
    log "Performing nuclear wipe of ALL tenant data in /mnt/data..."
    # Remove ALL directories in /mnt/data (except system directories)
    for dir in /mnt/data/*/; do
        if [[ -d "$dir" && "$(basename "$dir")" != "lost+found" ]]; then
            log "Removing: $dir"
            rm -rf "$dir" || true
        fi
    done
    ok "All tenant data in /mnt/data has been nuclear wiped."
    
    # Also ensure the specific tenant directory is gone
    if [[ -d "${DATA_ROOT}" ]]; then
        rm -rf "${DATA_ROOT}"
        ok "Specific tenant directory ${DATA_ROOT} removed."
    else
        ok "Tenant data directory did not exist."
    fi

    # --- 4. Global Docker System Prune (for dangling images) ---
    log "Performing global Docker system prune..."
    docker system prune -af
    ok "Docker system resources cleaned up."
    
    # --- 4.1. CRITICAL ENHANCEMENT: Prune system-level caches ---
    log "Pruning system-level package manager caches to prevent build failures..."
    
    # Clean pip cache (common cause of permission errors)
    if [[ -d "/root/.cache/pip" ]]; then
        rm -rf /root/.cache/pip
        ok "Pip cache pruned."
    fi
    
    # Clean npm cache (for Node.js services)
    if [[ -d "/root/.npm" ]]; then
        rm -rf /root/.npm
        ok "NPM cache pruned."
    fi
    
    # Clean user-level caches that might interfere
    if [[ -n "${SUDO_USER:-}" && -d "/home/${SUDO_USER}/.cache" ]]; then
        rm -rf "/home/${SUDO_USER}/.cache/pip" 2>/dev/null || true
        rm -rf "/home/${SUDO_USER}/.cache/npm" 2>/dev/null || true
        ok "User package caches pruned."
    fi
    
    ok "System-level package manager caches cleaned."
    
    # --- 5. Create Fresh Environment ---
    log "Creating fresh environment for tenant '${TENANT_ID}'..."
    mkdir -p "${DATA_ROOT}"
    chown "${SUDO_USER}:${SUDO_USER}" "${DATA_ROOT}"
    ok "Fresh tenant directory created."
    
    ok "TRUE NUCLEAR cleanup for tenant '${TENANT_ID}' is complete."
}

# Call main function
main "$@"
