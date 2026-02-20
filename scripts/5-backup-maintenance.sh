#!/bin/bash

#==============================================================================
# Script 5/5: Backup & Maintenance Operations
# Purpose: System backups, updates, and maintenance operations
# Architecture: 5-Script Framework (Setup → Deploy → Configure → Add → Backup)
# Version: 1.0.0 - Initial Release
#==============================================================================

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="/mnt/data/scripts"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manifest.sh"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# File paths
readonly DATA_ROOT="/mnt/data"
readonly BACKUP_DIR="${DATA_ROOT}/backups"
readonly LOG_DIR="${DATA_ROOT}/logs"
readonly METADATA_DIR="${DATA_ROOT}/metadata"

# Backup configuration
BACKUP_RETENTION_DAYS=30
COMPOSE_FILE="${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml"

#==============================================================================
# Backup Functions
#==============================================================================

create_backup_directory() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"
    
    mkdir -p "${backup_path}"
    mkdir -p "${backup_path}/config"
    mkdir -p "${backup_path}/data"
    mkdir -p "${backup_path}/logs"
    mkdir -p "${backup_path}/metadata"
    
    echo "${backup_path}"
}

backup_docker_volumes() {
    local backup_path="$1"
    log "INFO" "Backing up Docker volumes..."
    
    # Backup PostgreSQL
    if docker ps --format "table {{.Names}}" | grep -q postgres; then
        log "INFO" "Creating PostgreSQL backup..."
        docker exec postgres pg_dump -U "${POSTGRES_USER:-postgres}" "${POSTGRES_DB:-aiplatform}" > "${backup_path}/data/postgres_backup.sql"
    fi
    
    # Backup Redis
    if docker ps --format "table {{.Names}}" | grep -q redis; then
        log "INFO" "Creating Redis backup..."
        docker exec redis redis-cli BGSAVE
        sleep 5
        docker cp redis:/data/dump.rdb "${backup_path}/data/redis_backup.rdb"
    fi
    
    # Copy volume data
    local volumes=("postgres_data" "redis_data" "ollama_data" "caddy_data")
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "table {{.Name}}" | grep -q "^${volume}$"; then
            log "INFO" "Backing up volume: ${volume}"
            docker run --rm -v "${volume}:/source:ro" -v "${backup_path}/data:/backup" alpine tar czf "/backup/${volume}.tar.gz" -C /source .
        fi
    done
}

backup_configurations() {
    local backup_path="$1"
    log "INFO" "Backing up configurations..."
    
    # Backup environment files
    cp "${DATA_ROOT}/.env" "${backup_path}/config/" 2>/dev/null || true
    cp "${DATA_ROOT}/metadata/"* "${backup_path}/metadata/" 2>/dev/null || true
    
    # Backup Docker Compose
    cp "${COMPOSE_FILE}" "${backup_path}/config/docker-compose.yml" 2>/dev/null || true
    
    # Backup Caddy configuration
    cp -r "${DATA_ROOT}/caddy/" "${backup_path}/config/" 2>/dev/null || true
    
    # Backup service configurations
    cp -r "${DATA_ROOT}/config/" "${backup_path}/config/" 2>/dev/null || true
}

backup_logs() {
    local backup_path="$1"
    log "INFO" "Backing up logs..."
    
    if [ -d "${LOG_DIR}" ]; then
        cp -r "${LOG_DIR}/" "${backup_path}/logs/"
    fi
}

compress_backup() {
    local backup_path="$1"
    local archive_name=$(basename "${backup_path}")
    
    log "INFO" "Compressing backup..."
    cd "$(dirname "${backup_path}")"
    tar czf "${archive_name}.tar.gz" "$(basename "${backup_path}")"
    rm -rf "${backup_path}"
    
    echo "${backup_path}.tar.gz"
}

cleanup_old_backups() {
    log "INFO" "Cleaning up old backups (retention: ${BACKUP_RETENTION_DAYS} days)..."
    
    find "${BACKUP_DIR}" -name "backup_*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
    log "INFO" "Old backup cleanup completed"
}

#==============================================================================
# Maintenance Functions
#==============================================================================

update_system_packages() {
    log "INFO" "Updating system packages..."
    
    # Update package lists
    sudo apt update
    
    # Upgrade packages
    sudo apt upgrade -y
    
    # Clean up
    sudo apt autoremove -y
    sudo apt autoclean
    
    log "SUCCESS" "System packages updated"
}

update_docker_images() {
    log "INFO" "Updating Docker images..."
    
    if [ -f "${COMPOSE_FILE}" ]; then
        cd "$(dirname "${COMPOSE_FILE}")"
        docker compose pull
        log "SUCCESS" "Docker images updated"
    else
        log "WARNING" "Docker Compose file not found"
    fi
}

restart_services() {
    log "INFO" "Restarting services..."
    
    if [ -f "${COMPOSE_FILE}" ]; then
        cd "$(dirname "${COMPOSE_FILE}")"
        docker compose restart
        log "SUCCESS" "Services restarted"
    else
        log "WARNING" "Docker Compose file not found"
    fi
}

check_disk_space() {
    log "INFO" "Checking disk space..."
    
    df -h | grep -E "(Filesystem|/dev/)"
    
    # Check for low disk space warning
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "${usage}" -gt 80 ]; then
        log "WARNING" "Disk usage is ${usage}% - consider cleanup"
    fi
}

check_service_health() {
    log "INFO" "Checking service health..."
    
    if [ -f "${COMPOSE_FILE}" ]; then
        cd "$(dirname "${COMPOSE_FILE}")"
        docker compose ps
        
        local unhealthy=$(docker compose ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(unhealthy|exited)" | wc -l)
        if [ "${unhealthy}" -gt 0 ]; then
            log "WARNING" "${unhealthy} services are unhealthy"
        else
            log "SUCCESS" "All services are healthy"
        fi
    fi
}

#==============================================================================
# Menu Functions
#==============================================================================

show_backup_menu() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              BACKUP & MAINTENANCE OPERATIONS              ║${NC}"
    echo -e "${CYAN}║                   Script 5/5                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}📦 Backup Operations:${NC}"
    echo "  1) Create Full System Backup"
    echo "  2) Create Configuration Backup Only"
    echo "  3) Create Data Backup Only"
    echo "  4) List Available Backups"
    echo "  5) Restore from Backup"
    echo ""
    
    echo -e "${WHITE}🔧 Maintenance Operations:${NC}"
    echo "  6) Update System Packages"
    echo "  7) Update Docker Images"
    echo "  8) Restart All Services"
    echo "  9) Check Disk Space"
    echo " 10) Check Service Health"
    echo ""
    
    echo -e "${WHITE}⚙️  Configuration:${NC}"
    echo " 11) Set Backup Retention (Current: ${BACKUP_RETENTION_DAYS} days)"
    echo " 12) Schedule Automatic Backups"
    echo ""
    
    echo -e "${WHITE}🚪 Exit:${NC}"
    echo " 13) Return to Main Menu"
    echo ""
    
    echo -n -e "${YELLOW}Select option [1-13]: ${NC}"
}

handle_backup_choice() {
    local choice="$1"
    
    case "${choice}" in
        1) create_full_backup ;;
        2) create_config_backup ;;
        3) create_data_backup ;;
        4) list_backups ;;
        5) restore_backup ;;
        6) update_system_packages ;;
        7) update_docker_images ;;
        8) restart_services ;;
        9) check_disk_space ;;
        10) check_service_health ;;
        11) set_backup_retention ;;
        12) schedule_backups ;;
        13) exit 0 ;;
        *) log "ERROR" "Invalid option: ${choice}" ;;
    esac
}

#==============================================================================
# Backup Operation Functions
#==============================================================================

create_full_backup() {
    log "INFO" "Starting full system backup..."
    
    local backup_path=$(create_backup_directory)
    
    backup_docker_volumes "${backup_path}"
    backup_configurations "${backup_path}"
    backup_logs "${backup_path}"
    
    local archive=$(compress_backup "${backup_path}")
    
    log "SUCCESS" "Full backup completed: ${archive}"
    cleanup_old_backups
}

create_config_backup() {
    log "INFO" "Starting configuration backup..."
    
    local backup_path=$(create_backup_directory)
    backup_configurations "${backup_path}"
    
    local archive=$(compress_backup "${backup_path}")
    
    log "SUCCESS" "Configuration backup completed: ${archive}"
}

create_data_backup() {
    log "INFO" "Starting data backup..."
    
    local backup_path=$(create_backup_directory)
    backup_docker_volumes "${backup_path}"
    
    local archive=$(compress_backup "${backup_path}")
    
    log "SUCCESS" "Data backup completed: ${archive}"
}

list_backups() {
    log "INFO" "Available backups:"
    
    if [ -d "${BACKUP_DIR}" ]; then
        ls -lah "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null || echo "No backups found"
    else
        echo "Backup directory not found"
    fi
}

restore_backup() {
    echo "Restore functionality would be implemented here"
    echo "This would extract backup and restore services"
}

set_backup_retention() {
    echo -n "Enter backup retention days (current: ${BACKUP_RETENTION_DAYS}): "
    read -r new_retention
    
    if [[ "${new_retention}" =~ ^[0-9]+$ ]] && [ "${new_retention}" -gt 0 ]; then
        BACKUP_RETENTION_DAYS="${new_retention}"
        log "SUCCESS" "Backup retention set to ${BACKUP_RETENTION_DAYS} days"
    else
        log "ERROR" "Invalid retention period"
    fi
}

schedule_backups() {
    echo "Backup scheduling would be implemented here"
    echo "This would set up cron jobs for automatic backups"
}

#==============================================================================
# Main Function
#==============================================================================

main() {
    # Initialize
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${LOG_DIR}"
    
    # Main menu loop
    while true; do
        show_backup_menu
        read -r choice
        handle_backup_choice "${choice}"
        
        echo ""
        echo -n "${YELLOW}Press Enter to continue...${NC}"
        read -r
        clear
    done
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
