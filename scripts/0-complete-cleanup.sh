#!/usr/bin/env bash
# =============================================================================
# Script 0: Complete Cleanup & Reset
# =============================================================================
# PURPOSE: Complete tenant cleanup with confirmation and safety checks
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [--keep-data]
# =============================================================================

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Runtime vars ────────────────────────────────────────────────────────────────
TENANT_UID=$(id -u)
TENANT_ID="u${TENANT_UID}"
DATA_ROOT="/mnt/data/${TENANT_ID}"
COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"
KEEP_DATA=false

# Parse arguments
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
    local level="${1}" message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

# ─── UI Helpers ──────────────────────────────────────────────────────────────
print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}              AI Platform — Complete Cleanup                ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_warning() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}${BOLD}                        ⚠️  DESTRUCTION WARNING                 ${NC}${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── Safety Checks ───────────────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_tenant_exists() {
    if [ ! -d "${DATA_ROOT}" ] && [ "${KEEP_DATA}" = "false" ]; then
        log "WARN" "No data directory found for tenant ${TENANT_ID}"
        log "INFO" "Only container/network cleanup will be performed"
        DATA_ROOT=""
    fi
}

check_compose_file() {
    local compose_file="${DATA_ROOT}/docker-compose.yml"
    if [ -n "${DATA_ROOT}" ] && [ ! -f "${compose_file}" ]; then
        log "WARN" "No docker-compose.yml found at ${compose_file}"
        log "INFO" "Only running generic container cleanup"
        COMPOSE_FILE=""
    else
        COMPOSE_FILE="${compose_file}"
    fi
}

# ─── Cleanup Functions ───────────────────────────────────────────────────────────
cleanup_containers() {
    log "INFO" "Stopping and removing containers..."
    
    # Stop containers using compose file if it exists
    if [ -n "${COMPOSE_FILE:-}" ] && [ -f "${COMPOSE_FILE}" ]; then
        cd "${DATA_ROOT}"
        docker compose down --remove-orphans 2>/dev/null || true
        cd - > /dev/null
    fi
    
    # Force remove any remaining containers
    local containers
    containers=$(docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}" 2>/dev/null || true)
    if [ -n "${containers}" ]; then
        echo "${containers}" | xargs -r docker rm -f 2>/dev/null || true
        log "SUCCESS" "Containers removed"
    else
        log "INFO" "No containers to remove"
    fi
}

cleanup_networks() {
    log "INFO" "Removing Docker networks..."
    
    # Remove project networks
    local networks
    networks=$(docker network ls --filter "name=${DOCKER_NETWORK}" -q 2>/dev/null || true)
    if [ -n "${networks}" ]; then
        echo "${networks}" | xargs -r docker network rm 2>/dev/null || true
        log "SUCCESS" "Networks removed"
    else
        log "INFO" "No networks to remove"
    fi
    
    # Prune dangling networks (safe)
    docker network prune -f 2>/dev/null || true
}

cleanup_volumes() {
    log "INFO" "Removing Docker volumes..."
    
    # Remove named volumes matching project pattern
    local volumes
    volumes=$(docker volume ls --filter "name=${COMPOSE_PROJECT_NAME}" -q 2>/dev/null || true)
    if [ -n "${volumes}" ]; then
        echo "${volumes}" | xargs -r docker volume rm 2>/dev/null || true
        log "SUCCESS" "Project volumes removed"
    else
        log "INFO" "No project volumes to remove"
    fi
    
    # Remove any remaining AI platform related volumes
    local all_volumes
    all_volumes=$(docker volume ls -q 2>/dev/null | grep -E "(aip-|stack_|n8n_data|ollama-data|postgres-data|redis-data|qdrant-data|minio-data|dify-)" || true)
    if [ -n "${all_volumes}" ]; then
        log "INFO" "Removing additional AI platform volumes..."
        echo "${all_volumes}" | xargs -r docker volume rm 2>/dev/null || true
        log "SUCCESS" "Additional volumes removed"
    else
        log "INFO" "No additional volumes to remove"
    fi
}

cleanup_data() {
    if [ "${KEEP_DATA}" = "true" ]; then
        log "INFO" "Preserving data directory as requested"
        if [ -f "${DATA_ROOT}/docker-compose.yml" ]; then
            rm -f "${DATA_ROOT}/docker-compose.yml"
            log "SUCCESS" "Compose file removed (will be regenerated)"
        fi
    else
        log "INFO" "Unmounting EBS volumes and removing data directory..."
        
        # Unmount any EBS volumes mounted under /mnt/data
        if mountpoint -q /mnt/data 2>/dev/null; then
            log "INFO" "Unmounting /mnt/data..."
            umount /mnt/data 2>/dev/null || true
            log "SUCCESS" "/mnt/data unmounted"
        fi
        
        # Check for and unmount tenant-specific mount points
        if [ -n "${DATA_ROOT}" ] && mountpoint -q "${DATA_ROOT}" 2>/dev/null; then
            log "INFO" "Unmounting ${DATA_ROOT}..."
            umount "${DATA_ROOT}" 2>/dev/null || true
            log "SUCCESS" "${DATA_ROOT} unmounted"
        fi
        
        # Remove data directory
        if [ -d "${DATA_ROOT}" ]; then
            rm -rf "${DATA_ROOT}"
            log "SUCCESS" "Data directory removed: ${DATA_ROOT}"
        else
            log "INFO" "Data directory did not exist"
        fi
        
        # Complete Docker system prune
        log "INFO" "Running complete Docker system prune..."
        docker system prune -af --volumes 2>/dev/null || true
        log "SUCCESS" "Docker system pruned - all containers, images, networks, and volumes removed"
    fi
}

# ─── Confirmation ─────────────────────────────────────────────────────────────
confirm_destruction() {
    print_warning
    
    echo -e "${BOLD}Tenant to be destroyed:${NC} ${TENANT_ID}"
    echo -e "${BOLD}Data root:${NC}           ${DATA_ROOT:-"None (container/network cleanup only)"}"
    echo ""
    
    if [ "${KEEP_DATA}" = "true" ]; then
        echo -e "${YELLOW}🛡️  Data preservation mode enabled${NC}"
        echo -e "${DIM}Only containers, networks, volumes will be removed${NC}"
        echo -e "${DIM}Data directory will be preserved${NC}"
        echo ""
        echo -e "${BOLD}This will:${NC}"
        echo -e "  • Stop and remove all containers"
        echo -e "  • Remove all Docker networks"
        echo -e "  • Remove all named volumes"
        echo -e "  • Keep data intact${NC}"
        echo ""
    else
        echo -e "${RED}🔥  COMPLETE DESTRUCTION MODE${NC}"
        echo -e "${DIM}This will permanently delete:${NC}"
        echo ""
        echo -e "  ${BOLD}• All containers${NC}"
        echo -e "  ${BOLD}• All Docker networks${NC}"
        echo -e "  ${BOLD}• All named volumes${NC}"
        echo -e "  ${BOLD}• All data under ${DATA_ROOT}${NC}"
        echo -e "  ${BOLD}• All databases, models, uploads${NC}"
        echo -e "  ${BOLD}• All configuration files${NC}"
        echo ""
        echo -e "${RED}This action CANNOT be undone.${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Type '${BOLD}DELETE${NC}${YELLOW}' to confirm destruction of ${TENANT_ID}:${NC}"
    echo ""
    read -p "  ➤ Confirm: " confirm
    
    if [ "${confirm}" != "DELETE" ]; then
        log "INFO" "Aborted - no changes made"
        exit 0
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    check_root
    confirm_destruction
    check_tenant_exists
    check_compose_file
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ${BOLD}🧹  CLEANING IN PROGRESS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    cleanup_containers
    cleanup_networks
    cleanup_volumes
    cleanup_data
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅  CLEANUP COMPLETE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "${KEEP_DATA}" = "true" ]; then
        echo -e "${GREEN}✅  Tenant ${TENANT_ID} containers cleaned${NC}"
        echo -e "${DIM}Data preserved at ${DATA_ROOT}${NC}"
        echo ""
        echo -e "${BOLD}Next steps:${NC}"
        echo -e "  • Re-run setup: ${CYAN}sudo bash scripts/1-setup-system.sh${NC}"
        echo -e "  • Re-deploy:     ${CYAN}sudo bash scripts/2-deploy-services.sh${NC}"
    else
        echo -e "${GREEN}✅  Tenant ${TENANT_ID} completely destroyed${NC}"
        echo ""
        echo -e "${BOLD}Next steps:${NC}"
        echo -e "  • Fresh setup:   ${CYAN}sudo bash scripts/1-setup-system.sh${NC}"
        echo -e "  • Full deploy:    ${CYAN}sudo bash scripts/2-deploy-services.sh${NC}"
    fi
    echo ""
}

main "$@"
