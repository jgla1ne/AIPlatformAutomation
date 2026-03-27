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
    # Kill any running AI platform scripts to prevent race conditions
    log "Terminating any running platform scripts..."
    pkill -f "1-setup-system.sh" || true
    pkill -f "2-deploy-services.sh" || true
    pkill -f "3-configure-services.sh" || true
    sleep 2  # Let them terminate cleanly
    ok "Platform scripts terminated."
    
    # --- Tenant ID Validation ---
    if [[ -z "${1:-}" ]]; then
        echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
        exit 1
    fi
    
    TENANT_ID="$1"
    COMPOSE_PROJECT_NAME="ai-${TENANT_ID}" # Use the official Docker Compose project name
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    
    log "Starting TRUE NUCLEAR cleanup for tenant '${TENANT_ID}'..."

    # --- Load Environment for Dynamic Cleanup ---
    load_env_or_default() {
        local env_file="${DATA_ROOT}/.env"
        if [[ -f "${env_file}" ]]; then
            log "Loading environment from ${env_file}..."
            source "${env_file}"
        fi
        
        # Set defaults if not in .env
        TENANT="${TENANT:-${TENANT_ID}}"
        CONTAINER_PREFIX="${CONTAINER_PREFIX:-ai-${TENANT}}"
        DATA_ROOT="${DATA_ROOT:-/mnt/data/${TENANT}}"
        COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-ai-${TENANT}}"
        
        log "Using CONTAINER_PREFIX: ${CONTAINER_PREFIX}"
        log "Using DATA_ROOT: ${DATA_ROOT}"
    }
    
    # Load environment before cleanup
    load_env_or_default

    # --- 1. Dynamic Container Cleanup ---
    cleanup_containers() {
        log "Finding and stopping ALL AI platform containers..."
        
        # Find all containers with our prefix
        local containers
        containers=$(docker ps -aq --filter "name=${CONTAINER_PREFIX}")
        
        if [[ -n "${containers}" ]]; then
            log "Found containers: ${containers}"
            docker stop ${containers} 2>/dev/null || true
            docker rm ${containers} 2>/dev/null || true
            ok "All AI platform containers stopped and removed."
        else
            ok "No AI platform containers found."
        fi
        
        # Also check for the specific project
        log "Finding containers for project '${COMPOSE_PROJECT_NAME}'..."
        container_ids=$(docker ps -a --filter "name=${COMPOSE_PROJECT_NAME}" -q)
        if [[ -n "$container_ids" ]]; then
            docker stop $container_ids 2>/dev/null || true
            docker rm $container_ids 2>/dev/null || true
            ok "All containers for project '${COMPOSE_PROJECT_NAME}' stopped and removed."
        else
            ok "No containers for project '${COMPOSE_PROJECT_NAME}' found."
        fi
        
        # Legacy cleanup for any remaining hardcoded names
        docker rm -f litellm bifrost caddy 2>/dev/null || true
    }
    
    cleanup_containers
    
    # Kill ALL lingering Docker processes related to AI platform
    log "Killing ALL lingering Docker processes..."
    pkill -f "docker compose.*exec.*redis" || true
    pkill -f "docker compose.*down" || true
    pkill -f "docker.*compose.*${COMPOSE_PROJECT_NAME}" || true
    pkill -f "ai-${COMPOSE_PROJECT_NAME}" || true
    pkill -f "${COMPOSE_PROJECT_NAME}.*postgres" || true
    pkill -f "${COMPOSE_PROJECT_NAME}.*redis" || true
    ok "All lingering processes killed."

    # --- 2. Dynamic Volume Cleanup ---
    cleanup_volumes() {
        log "Finding and destroying ALL AI platform volumes..."
        
        # Remove all volumes with our prefix (if any exist)
        local volume_names
        volume_names=$(docker volume ls --filter "name=${CONTAINER_PREFIX}" -q)
        if [[ -n "$volume_names" ]]; then
            log "Found volumes: $volume_names"
            docker volume rm $volume_names 2>/dev/null || true
            ok "All AI platform volumes removed."
        else
            ok "No AI platform volumes found with prefix."
        fi
        
        # Also prune by project label (handles random-named volumes)
        docker volume prune -af --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}" 2>/dev/null || true
        ok "All Docker volumes for project '${COMPOSE_PROJECT_NAME}' have been destroyed."
        
        # Remove ALL remaining volumes (aggressive cleanup for "device busy" issues)
        log "Performing aggressive volume cleanup..."
        local all_volumes
        all_volumes=$(docker volume ls -q)
        if [[ -n "$all_volumes" ]]; then
            log "Found remaining volumes, removing all..."
            echo "$all_volumes" | xargs -r docker volume rm -f 2>/dev/null || true
            ok "All remaining volumes removed."
        fi
        
        # Dynamic named compose volumes based on environment (fallback)
        log "Explicitly removing named compose volumes..."
        for vol in postgres_data prometheus_data grafana_data bifrost_data bifrost_config qdrant_data ollama_data openwebui_data mem0_packages mem0_pip_cache; do
            local vol_name="${COMPOSE_PROJECT_NAME}_${vol}"
            if docker volume inspect "$vol_name" &>/dev/null; then
                docker volume rm "$vol_name" 2>/dev/null && ok "Removed volume: ${vol_name}" || warn "Could not remove ${vol_name} (may be in use)"
            fi
        done
        
        # Remove mem0-pip-cache volume (global, not project-specific)
        docker volume rm mem0-pip-cache 2>/dev/null || true
        
        # Final system prune to ensure clean state
        docker system prune -f --volumes 2>/dev/null || true
        ok "Final system prune completed."
    }
    
    cleanup_volumes

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
    
    # Clean router environment variables from .env if it exists
    if [[ -f "${DATA_ROOT}/.env" ]]; then
        log "Cleaning router variables from .env file..."
        sed -i '/^BIFROST_/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LLM_ROUTER/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LLM_ROUTER_CONTAINER/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LLM_ROUTER_PORT/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LLM_GATEWAY_/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LLM_MASTER_KEY/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^LITELLM_/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        sed -i '/^ENABLE_LITELLM/d' "${DATA_ROOT}/.env" 2>/dev/null || true
        ok "Router variables cleaned from .env."
    fi
    
    # Thorough cleanup: Remove ANY remaining postgres/redis data
    log "Performing thorough cleanup of ALL database remnants..."
    find /mnt -name "*postgres*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /mnt -name "*redis*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /mnt -name "*qdrant*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /var/lib -name "*postgres*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /var/lib -name "*redis*" -type d -exec rm -rf {} + 2>/dev/null || true
    ok "All database remnants removed."
    
    # COMPLETE WIPE: If requested, remove entire /mnt folder
    if [[ "${COMPLETE_WIPE:-false}" == "true" ]]; then
        log "PERFORMING COMPLETE WIPE OF /mnt FOLDER..."
        if [[ -d "/mnt" ]]; then
            # Backup /mnt/data structure for recreation
            rm -rf /mnt/* || true
            ok "Complete /mnt folder wiped."
        fi
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
