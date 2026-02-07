#!/bin/bash

#############################################################################
# AI PLATFORM - SCRIPT 0: COMPLETE CLEANUP & PREPARATION
# Version: 75.0.0 (Hybrid - Reference + User Features)
# Description: Nuclear cleanup of all AI Platform resources and preparation
#              for fresh installation. Combines reference architecture with
#              user's proven features (config backup, comprehensive cleanup)
# 
# Features from Reference v75.2.0:
#   - GPU driver cleanup (nvidia-docker2)
#   - Systemd service removal
#   - Cron job cleanup
#   - Firewall rule cleanup
#   - Complete Docker resource cleanup
#   - Directory structure cleanup
#
# Features from User v74.0.0:
#   - Enhanced confirmation prompts
#   - Detailed logging
#   - Backup preservation option
#   - Resource usage reporting
#
# Last Updated: 2026-02-07
# WARNING: This script is DESTRUCTIVE. Use with extreme caution.
#############################################################################

set -euo pipefail

#############################################################################
# GLOBAL VARIABLES
#############################################################################

readonly SCRIPT_VERSION="75.0.0"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Storage paths (Reference architecture)
readonly CONFIG_ROOT="${HOME}/ai-platform"
readonly DATA_ROOT_DEFAULT="/mnt/data/ai-platform"
readonly DATA_ROOT_FALLBACK="${HOME}/ai-platform-data"

# Legacy paths to clean (from user's v74.0)
readonly LEGACY_PATHS=(
    "/opt/ai-platform"
    "/opt/ai-services"
    "/var/lib/ai-platform"
    "/var/log/ai-platform"
    "/var/backups/ai-platform"
    "/etc/ai-platform"
)

# Logging
readonly LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
readonly LOG_FILE="${LOG_DIR}/cleanup-$(date +%Y%m%d_%H%M%S).log"

#############################################################################
# COLORS & SYMBOLS
#############################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARNING_SIGN="⚠"
readonly BROOM="🧹"
readonly TRASH="🗑️"
readonly BACKUP="💾"
readonly ROCKET="🚀"

#############################################################################
# LOGGING FUNCTIONS
#############################################################################

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
    echo -e "${BLUE}${CHECK_MARK}${NC} $*"
    echo "$msg" >> "${LOG_FILE}"
}

log_success() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
    echo -e "${GREEN}${CHECK_MARK}${NC} $*"
    echo "$msg" >> "${LOG_FILE}"
}

log_warn() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*"
    echo -e "${YELLOW}${WARNING_SIGN}${NC} $*"
    echo "$msg" >> "${LOG_FILE}"
}

log_error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*"
    echo -e "${RED}${CROSS_MARK}${NC} $*"
    echo "$msg" >> "${LOG_FILE}"
}

log_section() {
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD} $*${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${NC}"
    echo ""
}

#############################################################################
# UTILITY FUNCTIONS
#############################################################################

# Detect data root location
detect_data_root() {
    if [[ -d "${DATA_ROOT_DEFAULT}" ]]; then
        echo "${DATA_ROOT_DEFAULT}"
    elif [[ -d "${DATA_ROOT_FALLBACK}" ]]; then
        echo "${DATA_ROOT_FALLBACK}"
    else
        # Return empty if neither exists (will be created by Script 1)
        echo ""
    fi
}

# Calculate directory size safely
get_dir_size() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        du -sh "${dir}" 2>/dev/null | awk '{print $1}' || echo "unknown"
    else
        echo "not found"
    fi
}

# Count files safely
count_files() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        find "${dir}" -type f 2>/dev/null | wc -l || echo "0"
    else
        echo "0"
    fi
}

#############################################################################
# BACKUP FUNCTIONS (User v36.0 Feature)
#############################################################################

backup_existing_config() {
    local backup_created=false
    local backup_dir="${HOME}/ai-platform-backup-$(date +%Y%m%d_%H%M%S)"
    
    log_section "${BACKUP} Checking for Existing Configuration to Backup"
    
    # Check for CONFIG_ROOT
    if [[ -d "${CONFIG_ROOT}" ]]; then
        log "Found existing configuration: ${CONFIG_ROOT}"
        
        read -p "$(echo -e ${YELLOW}Do you want to backup existing configuration before cleanup? [Y/n]:${NC} )" backup_choice
        backup_choice="${backup_choice:-Y}"
        
        if [[ "${backup_choice}" =~ ^[Yy]$ ]]; then
            log "Creating backup at: ${backup_dir}"
            mkdir -p "${backup_dir}"
            
            # Backup critical files
            if [[ -d "${CONFIG_ROOT}/deployment/.secrets" ]]; then
                cp -r "${CONFIG_ROOT}/deployment/.secrets" "${backup_dir}/" 2>/dev/null || true
                log_success "Backed up: .secrets/"
            fi
            
            if [[ -f "${CONFIG_ROOT}/deployment/stack/docker-compose.yml" ]]; then
                mkdir -p "${backup_dir}/stack"
                cp "${CONFIG_ROOT}/deployment/stack/docker-compose.yml" "${backup_dir}/stack/" 2>/dev/null || true
                log_success "Backed up: docker-compose.yml"
            fi
            
            if [[ -d "${CONFIG_ROOT}/deployment/configs" ]]; then
                cp -r "${CONFIG_ROOT}/deployment/configs" "${backup_dir}/" 2>/dev/null || true
                log_success "Backed up: configs/"
            fi
            
            backup_created=true
            log_success "Backup created: ${backup_dir}"
            echo ""
            echo -e "${GREEN}${BOLD}IMPORTANT:${NC} Backup location saved to: ${backup_dir}"
            echo -e "${GREEN}You can restore these files after running Script 1 if needed.${NC}"
            echo ""
        else
            log "Skipping configuration backup"
        fi
    else
        log "No existing configuration found to backup"
    fi
    
    return 0
}

#############################################################################
# CONFIRMATION FUNCTIONS
#############################################################################

show_warning() {
    clear
    echo -e "${RED}${BOLD}"
    cat << 'BANNER_EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║              🧹 AI PLATFORM - COMPLETE CLEANUP & RESET 🧹                 ║
║                          Version 75.0.0                                   ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
BANNER_EOF
    echo -e "${NC}"
    
    echo -e "${YELLOW}${BOLD}⚠️  WARNING: THIS SCRIPT WILL REMOVE:${NC}"
    echo ""
    echo -e "  ${TRASH} ${RED}All Docker containers, images, volumes, and networks${NC}"
    echo -e "  ${TRASH} ${RED}All AI Platform configuration files${NC}"
    echo -e "  ${TRASH} ${RED}All AI Platform data directories${NC}"
    echo -e "  ${TRASH} ${RED}GPU drivers (nvidia-docker2, if present)${NC}"
    echo -e "  ${TRASH} ${RED}Systemd services${NC}"
    echo -e "  ${TRASH} ${RED}Cron jobs${NC}"
    echo -e "  ${TRASH} ${RED}Firewall rules${NC}"
    echo ""
    echo -e "${RED}${BOLD}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    
    # Show what will be cleaned
    echo -e "${CYAN}Directories that will be removed:${NC}"
    echo -e "  • ${CONFIG_ROOT} ($(get_dir_size "${CONFIG_ROOT}"))"
    
    local data_root
    data_root=$(detect_data_root)
    if [[ -n "${data_root}" ]]; then
        echo -e "  • ${data_root} ($(get_dir_size "${data_root}"))"
    fi
    
    for path in "${LEGACY_PATHS[@]}"; do
        if [[ -d "${path}" ]]; then
            echo -e "  • ${path} ($(get_dir_size "${path}"))"
        fi
    done
    echo ""
    
    # Show Docker resources
    if command -v docker &> /dev/null; then
        local container_count
        local volume_count
        local image_count
        container_count=$(docker ps -aq 2>/dev/null | wc -l)
        volume_count=$(docker volume ls -q 2>/dev/null | wc -l)
        image_count=$(docker images -q 2>/dev/null | wc -l)
        
        echo -e "${CYAN}Docker resources that will be removed:${NC}"
        echo -e "  • Containers: ${container_count}"
        echo -e "  • Volumes: ${volume_count}"
        echo -e "  • Images: ${image_count}"
        echo ""
    fi
}

confirm_cleanup() {
    show_warning
    
    echo -e "${YELLOW}${BOLD}First Confirmation:${NC}"
    read -p "$(echo -e ${YELLOW}Are you absolutely sure you want to proceed? Type ${BOLD}YES${NC}${YELLOW} to confirm:${NC} )" first_confirmation
    
    if [[ "${first_confirmation}" != "YES" ]]; then
        log "Cleanup cancelled by user (first confirmation)"
        exit 0
    fi
    
    echo ""
    echo -e "${RED}${BOLD}Final Confirmation:${NC}"
    read -p "$(echo -e ${RED}This will DELETE everything. Type ${BOLD}DELETE${NC}${RED} to proceed:${NC} )" final_confirmation
    
    if [[ "${final_confirmation}" != "DELETE" ]]; then
        log "Cleanup cancelled by user (final confirmation)"
        exit 0
    fi
    
    log_warn "User confirmed cleanup - proceeding with nuclear reset"
    echo ""
}

#############################################################################
# CLEANUP FUNCTIONS
#############################################################################

cleanup_docker_resources() {
    log_section "${TRASH} Cleaning Docker Resources"
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not installed - skipping Docker cleanup"
        return 0
    fi
    
    # Stop all containers
    log "Stopping all Docker containers..."
    if docker ps -q | xargs -r docker stop 2>/dev/null; then
        log_success "All containers stopped"
    else
        log "No running containers found"
    fi
    
    # Remove all containers
    log "Removing all Docker containers..."
    if docker ps -aq | xargs -r docker rm -f 2>/dev/null; then
        log_success "All containers removed"
    else
        log "No containers to remove"
    fi
    
    # Remove all volumes
    log "Removing all Docker volumes..."
    local volume_count
    volume_count=$(docker volume ls -q 2>/dev/null | wc -l)
    if [[ ${volume_count} -gt 0 ]]; then
        docker volume ls -q | xargs -r docker volume rm -f 2>/dev/null || true
        log_success "Removed ${volume_count} Docker volumes"
    else
        log "No volumes to remove"
    fi
    
    # Remove all networks (except defaults)
    log "Removing custom Docker networks..."
    docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' | xargs -r docker network rm 2>/dev/null || true
    log_success "Custom networks removed"
    
    # Remove all images
    log "Removing all Docker images..."
    local image_count
    image_count=$(docker images -q 2>/dev/null | wc -l)
    if [[ ${image_count} -gt 0 ]]; then
        docker images -q | xargs -r docker rmi -f 2>/dev/null || true
        log_success "Removed ${image_count} Docker images"
    else
        log "No images to remove"
    fi
    
    # System prune
    log "Performing Docker system prune..."
    docker system prune -af --volumes 2>/dev/null || true
    log_success "Docker system pruned"
    
    log_success "Docker cleanup complete"
}

cleanup_directories() {
    log_section "${TRASH} Removing Installation Directories"
    
    local total_freed=0
    
    # Clean CONFIG_ROOT
    if [[ -d "${CONFIG_ROOT}" ]]; then
        local size_kb
        size_kb=$(du -sk "${CONFIG_ROOT}" 2>/dev/null | awk '{print $1}')
        log "Removing: ${CONFIG_ROOT}"
        rm -rf "${CONFIG_ROOT}"
        log_success "Removed: ${CONFIG_ROOT} (freed $(numfmt --to=iec-i --suffix=B $((size_kb * 1024)) 2>/dev/null || echo "${size_kb}KB"))"
        total_freed=$((total_freed + size_kb))
    else
        log "Not found: ${CONFIG_ROOT}"
    fi
    
    # Clean DATA_ROOT
    local data_root
    data_root=$(detect_data_root)
    if [[ -n "${data_root}" && -d "${data_root}" ]]; then
        local size_kb
        size_kb=$(du -sk "${data_root}" 2>/dev/null | awk '{print $1}')
        log "Removing: ${data_root}"
        rm -rf "${data_root}"
        log_success "Removed: ${data_root} (freed $(numfmt --to=iec-i --suffix=B $((size_kb * 1024)) 2>/dev/null || echo "${size_kb}KB"))"
        total_freed=$((total_freed + size_kb))
    fi
    
    # Clean legacy paths
    for path in "${LEGACY_PATHS[@]}"; do
        if [[ -d "${path}" ]]; then
            local size_kb
            size_kb=$(du -sk "${path}" 2>/dev/null | awk '{print $1}')
            log "Removing: ${path}"
            rm -rf "${path}"
            log_success "Removed: ${path} (freed $(numfmt --to=iec-i --suffix=B $((size_kb * 1024)) 2>/dev/null || echo "${size_kb}KB"))"
            total_freed=$((total_freed + size_kb))
        else
            log "Not found: ${path}"
        fi
    done
    
    # Clean old log files in script directory
    log "Cleaning old log files (>7 days) in ${LOG_DIR}..."
    find "${LOG_DIR}" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    log_success "Old log files cleaned"
    
    log_success "Total disk space freed: $(numfmt --to=iec-i --suffix=B $((total_freed * 1024)) 2>/dev/null || echo "${total_freed}KB")"
}

cleanup_systemd_services() {
    log_section "${TRASH} Removing Systemd Services"
    
    local services_found=false
    
    # Find and remove AI platform systemd services
    if compgen -G "/etc/systemd/system/ai-platform*.service" > /dev/null 2>&1; then
        log "Found systemd services, removing..."
        for service in /etc/systemd/system/ai-platform*.service; do
            local service_name
            service_name=$(basename "${service}")
            log "Stopping and disabling: ${service_name}"
            systemctl stop "${service_name}" 2>/dev/null || true
            systemctl disable "${service_name}" 2>/dev/null || true
            rm -f "${service}"
            log_success "Removed: ${service_name}"
            services_found=true
        done
        systemctl daemon-reload
        log_success "Systemd daemon reloaded"
    else
        log "No systemd services found"
    fi
}

cleanup_cron_jobs() {
    log_section "${TRASH} Removing Cron Jobs"
    
    # Remove system-wide cron jobs
    if compgen -G "/etc/cron.d/ai-platform*" > /dev/null 2>&1; then
        log "Removing system cron jobs..."
        rm -f /etc/cron.d/ai-platform*
        log_success "System cron jobs removed"
    else
        log "No system cron jobs found"
    fi
    
    # Check user crontab
    if crontab -l 2>/dev/null | grep -q "ai-platform"; then
        log "Found AI Platform entries in user crontab"
        log_warn "Please manually review and remove AI Platform entries from crontab"
        log_warn "Run: crontab -e"
    else
        log "No user crontab entries found"
    fi
}

cleanup_gpu_drivers() {
    log_section "${TRASH} Cleaning GPU Drivers (if present)"
    
    if command -v nvidia-smi &> /dev/null; then
        log "NVIDIA drivers detected"
        
        read -p "$(echo -e ${YELLOW}Remove nvidia-docker2 and nvidia-container-toolkit? [y/N]:${NC} )" remove_nvidia
        
        if [[ "${remove_nvidia}" =~ ^[Yy]$ ]]; then
            log "Removing nvidia-docker2 and nvidia-container-toolkit..."
            
            if command -v apt-get &> /dev/null; then
                apt-get purge -y nvidia-docker2 nvidia-container-toolkit 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
                log_success "NVIDIA Docker components removed"
            elif command -v yum &> /dev/null; then
                yum remove -y nvidia-docker2 nvidia-container-toolkit 2>/dev/null || true
                log_success "NVIDIA Docker components removed"
            else
                log_warn "Unknown package manager - please remove nvidia-docker2 manually"
            fi
        else
            log "Skipping NVIDIA Docker component removal"
        fi
    else
        log "No NVIDIA GPU detected - skipping GPU cleanup"
    fi
}

cleanup_firewall() {
    log_section "${TRASH} Cleaning Firewall Rules"
    
    if command -v ufw &> /dev/null; then
        log "Removing UFW rules for AI Platform..."
        
        # Common AI platform ports
        local ports=(80 443 3000 3001 3002 3003 3004 5432 6333 6379 8000 8080 8081 8082 9000 9001 9090 11434)
        
        for port in "${ports[@]}"; do
            ufw delete allow "${port}/tcp" 2>/dev/null || true
        done
        
        log_success "UFW rules cleaned"
    else
        log "UFW not found - skipping firewall cleanup"
    fi
}

cleanup_user_config() {
    log_section "${TRASH} Cleaning User Configuration Files"
    
    # Remove user config files
    if compgen -G "${HOME}/.ai-platform-*" > /dev/null 2>&1; then
        log "Removing user config files..."
        rm -f "${HOME}"/.ai-platform-*
        log_success "User config files removed"
    else
        log "No user config files found"
    fi
}

#############################################################################
# VALIDATION FUNCTIONS
#############################################################################

verify_cleanup() {
    log_section "${CHECK_MARK} Verifying Cleanup"
    
    local all_clean=true
    
    # Check directories
    log "Checking directories..."
    for dir in "${CONFIG_ROOT}" "$(detect_data_root)" "${LEGACY_PATHS[@]}"; do
        if [[ -n "${dir}" && -d "${dir}" ]]; then
            log_error "Directory still exists: ${dir}"
            all_clean=false
        fi
    done
    
    # Check Docker
    if command -v docker &> /dev/null; then
        log "Checking Docker resources..."
        local container_count
        local volume_count
        local image_count
        container_count=$(docker ps -a -q 2>/dev/null | wc -l)
        volume_count=$(docker volume ls -q 2>/dev/null | wc -l)
        image_count=$(docker images -q 2>/dev/null | wc -l)
        
        if [[ ${container_count} -gt 0 ]]; then
            log_warn "Found ${container_count} Docker containers remaining"
        fi
        
        if [[ ${volume_count} -gt 0 ]]; then
            log_warn "Found ${volume_count} Docker volumes remaining"
        fi
        
        if [[ ${image_count} -gt 0 ]]; then
            log_warn "Found ${image_count} Docker images remaining"
        fi
        
        if [[ ${container_count} -eq 0 && ${volume_count} -eq 0 && ${image_count} -eq 0 ]]; then
            log_success "Docker completely clean"
        fi
    fi
    
    # Check systemd
    if compgen -G "/etc/systemd/system/ai-platform*.service" > /dev/null 2>&1; then
        log_error "Systemd services still present"
        all_clean=false
    else
        log_success "No systemd services remaining"
    fi
    
    # Check cron
    if compgen -G "/etc/cron.d/ai-platform*" > /dev/null 2>&1; then
        log_error "Cron jobs still present"
        all_clean=false
    else
        log_success "No cron jobs remaining"
    fi
    
    if [[ "${all_clean}" == true ]]; then
        log_success "System is completely clean"
        return 0
    else
        log_warn "Some resources may remain - review errors above"
        return 1
    fi
}

#############################################################################
# MAIN EXECUTION
#############################################################################

main() {
    local start_time
    start_time=$(date +%s)
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Show warning and get confirmation
    confirm_cleanup
    
    # Backup existing config (user v36.0 feature)
    backup_existing_config
    
    # Execute cleanup phases
    cleanup_docker_resources
    cleanup_directories
    cleanup_systemd_services
    cleanup_cron_jobs
    cleanup_gpu_drivers
    cleanup_firewall
    cleanup_user_config
    
    # Verify cleanup
    verify_cleanup
    
    # Calculate duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Final summary
    echo ""
    log_section "${ROCKET} Cleanup Complete"
    echo ""
    log_success "AI Platform cleanup completed successfully!"
    log "Total execution time: ${duration} seconds"
    log "Log file: ${LOG_FILE}"
    echo ""
    echo -e "${GREEN}${BOLD}System is now ready for a fresh installation.${NC}"
    echo -e "${CYAN}Next step: Run ${BOLD}sudo ./1-setup-system.sh${NC}"
    echo ""
    
    return 0
}

# Execute main
main "$@"
exit $?
