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
# Dynamic configuration paths
DATA_BASE_PATH="/mnt/data"
COMPOSE_FILENAME="docker-compose.yml"
PLATFORM_LABEL="com.ai-platform"
# Read PROJECT_PREFIX from environment or use default
PROJECT_PREFIX="${PROJECT_PREFIX:-aip-}"
# Dynamic volume patterns for AI services
VOLUME_PATTERNS="(${PROJECT_PREFIX}|stack_|n8n_data|ollama-data|postgres-data|redis-data|qdrant-data|minio-data|dify-)"

# Auto-detect tenant directories
detect_tenants() {
    local tenants=()
    if [ -d "${DATA_BASE_PATH}" ]; then
        for dir in ${DATA_BASE_PATH}/*/; do
            if [ -d "$dir" ]; then
                local tenant_name=$(basename "$dir")
                tenants+=("$tenant_name")
            fi
        done
    fi
    # Also check /mnt directly for legacy support
    for dir in /mnt/*/; do
        if [ -d "$dir" ] && [[ ! "$(basename "$dir")" =~ ^(data|lost\+found)$ ]]; then
            local tenant_name=$(basename "$dir")
            # Avoid duplicates
            if [[ ! " ${tenants[@]} " =~ " ${tenant_name} " ]]; then
                tenants+=("$tenant_name")
            fi
        fi
    done
    echo "${tenants[@]}"
}

TENANT_ID=""
DATA_ROOT=""
COMPOSE_PROJECT_NAME=""
DOCKER_NETWORK=""
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
    local compose_file="${DATA_ROOT}/${COMPOSE_FILENAME}"
    if [ -n "${DATA_ROOT}" ] && [ ! -f "${compose_file}" ]; then
        log "WARN" "No ${COMPOSE_FILENAME} found at ${compose_file}"
        log "INFO" "Only running generic container cleanup"
        DATA_ROOT=""
    fi
    
    if [ -n "${DATA_ROOT}" ] && [ -f "${compose_file}" ]; then
        COMPOSE_FILE="${compose_file}"
        log "INFO" "Using compose file: ${compose_file}"
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
    
    # Force remove any remaining AI Platform containers (all tenants)
    local containers
    containers=$(docker ps -aq --filter "label=${PLATFORM_LABEL}" 2>/dev/null || true)
    if [ -n "${containers}" ]; then
        echo "${containers}" | xargs -r docker rm -f 2>/dev/null || true
        log "SUCCESS" "AI Platform containers removed"
    else
        log "INFO" "No AI Platform containers to remove"
    fi
    
    # Also remove any containers with project prefix (legacy naming)
    containers=$(docker ps -aq --filter "name=${PROJECT_PREFIX}" 2>/dev/null || true)
    if [ -n "${containers}" ]; then
        echo "${containers}" | xargs -r docker rm -f 2>/dev/null || true
        log "SUCCESS" "Legacy ${PROJECT_PREFIX} containers removed"
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
    all_volumes=$(docker volume ls -q 2>/dev/null | grep -E "${VOLUME_PATTERNS}" || true)
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
        if [ -f "${DATA_ROOT}/${COMPOSE_FILENAME}" ]; then
            rm -f "${DATA_ROOT}/${COMPOSE_FILENAME}"
            log "SUCCESS" "Compose file removed (will be regenerated)"
        fi
    else
        log "INFO" "Unmounting EBS volumes and removing data directory..."
        
        # Unmount any EBS volumes mounted under data base path
        if mountpoint -q "${DATA_BASE_PATH}" 2>/dev/null; then
            log "INFO" "Unmounting ${DATA_BASE_PATH}..."
            umount "${DATA_BASE_PATH}" 2>/dev/null || true
            log "SUCCESS" "${DATA_BASE_PATH} unmounted"
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
    
    # Detect tenants locally for confirmation
    local tenants=($(detect_tenants))
    
    echo -e "${BOLD}Tenant to be destroyed:${NC} ${TENANT_ID}"
    echo -e "${BOLD}Data root:${NC}           ${DATA_ROOT:-"None (container/network cleanup only)"}"
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                        ⚠️  DESTRUCTION WARNING                 ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ${#tenants[@]} -eq 0 ]; then
        echo -e "${YELLOW}No tenant directories found${NC}"
        echo -e "${DIM}Only generic container/network cleanup will be performed${NC}"
    else
        echo -e "${YELLOW}Tenants to be destroyed: ${tenants[*]}${NC}"
        for tenant in "${tenants[@]}"; do
            local data_root="${DATA_BASE_PATH}/${tenant}"
            if [ ! -d "${data_root}" ]; then
                data_root="/mnt/${tenant}"
            fi
            echo -e "${DIM}Data root:           ${data_root}${NC}"
        done
    fi
    
    echo ""
    echo -e "${RED}🔥  COMPLETE DESTRUCTION MODE${NC}"
    echo -e "${DIM}This will permanently delete:${NC}"
    echo ""
    echo -e "${DIM}  • All containers${NC}"
    echo -e "${DIM}  • All Docker networks${NC}"
    echo -e "${DIM}  • All named volumes${NC}"
    if [ ${#tenants[@]} -gt 0 ]; then
        echo -e "${DIM}  • All data under tenant directories${NC}"
        echo -e "${DIM}  • All databases, models, uploads${NC}"
        echo -e "${DIM}  • All configuration files${NC}"
    fi
    echo ""
    echo -e "${RED}This action CANNOT be undone.${NC}"
    echo ""
    
    if [ ${#tenants[@]} -eq 0 ]; then
        read -p "  ➤ Continue with generic cleanup? [y/N]: " confirm
        [[ "${confirm,,}" == "y" ]] || exit 0
    else
        echo -e "Type 'DELETE' to confirm destruction of ${tenants[*]}:"
        echo ""
        read -p "  ➤ Confirm: " confirm
        if [ "${confirm}" != "DELETE" ]; then
            log "INFO" "Aborted - no changes made"
            exit 0
        fi
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    check_root
    
    # Detect all tenants
    local tenants=($(detect_tenants))
    
    if [ ${#tenants[@]} -eq 0 ]; then
        log "INFO" "No tenant directories found"
        log "INFO" "Only generic container cleanup will be performed"
        TENANT_ID=""
        DATA_ROOT=""
    else
        log "INFO" "Found ${#tenants[@]} tenant(s): ${tenants[*]}"
        # Clean up each tenant
        for tenant in "${tenants[@]}"; do
            log "INFO" "Cleaning up tenant: ${tenant}"
            TENANT_ID="${tenant}"
            DATA_ROOT="${DATA_BASE_PATH}/${tenant}"
            if [ ! -d "${DATA_ROOT}" ]; then
                DATA_ROOT="/mnt/${tenant}"
            fi
            
            # Read PROJECT_PREFIX from tenant's .env file if exists
            if [ -f "${DATA_ROOT}/.env" ]; then
                # Source the .env file to get PROJECT_PREFIX
                set -a
                . "${DATA_ROOT}/.env"
                set +a
                log "INFO" "Using PROJECT_PREFIX from .env: ${PROJECT_PREFIX:-aip-}"
            else
                PROJECT_PREFIX="${PROJECT_PREFIX:-aip-}"
                log "INFO" "Using default PROJECT_PREFIX: ${PROJECT_PREFIX}"
            fi
            
            COMPOSE_PROJECT_NAME="${PROJECT_PREFIX}${tenant}"
            DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"
            
            cleanup_containers
            cleanup_networks
            cleanup_volumes
            cleanup_data
        done
    fi
    
    confirm_destruction
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ${BOLD}🧹  CLEANING IN PROGRESS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Final cleanup
    cleanup_containers
    cleanup_networks
    cleanup_volumes
    
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
