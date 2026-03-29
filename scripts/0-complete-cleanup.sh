#!/usr/bin/env bash
# =============================================================================
# Script 0: Nuclear Cleanup - BULLETPROOF v4.0
# =============================================================================
# PURPOSE: Complete system wipe with container name fallbacks
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [tenant_id]
# =============================================================================

set -euo pipefail

# Claude Audit Fix 8: TENANT_ID fallback without circular dependency
TENANT_ID=${1:-"default"}

# Basic Logging Functions
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
    # Claude Audit: Container name variables with fallbacks (no .env dependency)
    DOCKER_NETWORK="ai-${TENANT_ID}"
    BIFROST_CONTAINER="${BIFROST_CONTAINER:-ai-${TENANT_ID}-bifrost-1}"
    OLLAMA_CONTAINER="${OLLAMA_CONTAINER:-ai-${TENANT_ID}-ollama-1}"
    MEM0_CONTAINER="${MEM0_CONTAINER:-ai-${TENANT_ID}-mem0-1}"
    QDRANT_CONTAINER="${QDRANT_CONTAINER:-ai-${TENANT_ID}-qdrant-1}"
    FLOWISE_CONTAINER="${FLOWISE_CONTAINER:-ai-${TENANT_ID}-flowise-1}"
    N8N_CONTAINER="${N8N_CONTAINER:-ai-${TENANT_ID}-n8n-1}"
    GRAFANA_CONTAINER="${GRAFANA_CONTAINER:-ai-${TENANT_ID}-grafana-1}"
    PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-ai-${TENANT_ID}-prometheus-1}"
    
    log "Starting nuclear cleanup for tenant '${TENANT_ID}'..."
    log "Docker network: ${DOCKER_NETWORK}"
    
    # Kill any running AI platform scripts to prevent race conditions
    pkill -f "1-setup-system.sh" || true
    pkill -f "2-deploy-services.sh" || true
    pkill -f "3-configure-services.sh" || true
    sleep 2
    ok "Platform scripts terminated."
    
    # Claude Audit: No .env file access in Script 0
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    
    # Claude Audit: Container cleanup with defined variables
    log "Stopping and removing AI platform containers..."
    
    # Stop containers by name using defined variables
    docker stop ${BIFROST_CONTAINER} ${OLLAMA_CONTAINER} ${MEM0_CONTAINER} ${QDRANT_CONTAINER} ${FLOWISE_CONTAINER} ${N8N_CONTAINER} ${GRAFANA_CONTAINER} ${PROMETHEUS_CONTAINER} 2>/dev/null || true
    docker rm ${BIFROST_CONTAINER} ${OLLAMA_CONTAINER} ${MEM0_CONTAINER} ${QDRANT_CONTAINER} ${FLOWISE_CONTAINER} ${N8N_CONTAINER} ${GRAFANA_CONTAINER} ${PROMETHEUS_CONTAINER} 2>/dev/null || true
    
    # Fallback: find containers by network prefix
    local containers
    containers=$(docker ps -aq --filter "name=ai-${TENANT_ID}")
    if [[ -n "${containers}" ]]; then
        docker stop ${containers} 2>/dev/null || true
        docker rm ${containers} 2>/dev/null || true
    fi
    
    ok "All AI platform containers stopped and removed."
    
    # Claude Audit: Network cleanup
    log "Removing Docker network ${DOCKER_NETWORK}..."
    docker network rm ${DOCKER_NETWORK} 2>/dev/null || true
    
    # Claude Audit: Volume cleanup with grep pattern
    log "Removing AI platform volumes..."
    local volumes
    volumes=$(docker volume ls --filter "name=ai-${TENANT_ID}" -q)
    if [[ -n "$volumes" ]]; then
        docker volume rm $volumes 2>/dev/null || true
    fi
    
    # Fallback: remove any remaining volumes with tenant prefix
    docker volume prune -af --filter "label=com.docker.compose.project=ai-${TENANT_ID}" 2>/dev/null || true
    
    # Claude Audit: Data directory cleanup
    log "Removing tenant data directory ${DATA_ROOT}..."
    if [[ -d "${DATA_ROOT}" ]]; then
        rm -rf "${DATA_ROOT}"
    fi
    
    # Final system prune
    docker system prune -af
    
    # Create fresh directory structure
    mkdir -p "${DATA_ROOT}"
    chown "${SUDO_USER}:${SUDO_USER}" "${DATA_ROOT}" 2>/dev/null || chown 1000:1000 "${DATA_ROOT}"
    
    ok "Nuclear cleanup for tenant '${TENANT_ID}' complete."
}

# Call main function
main "$@"
