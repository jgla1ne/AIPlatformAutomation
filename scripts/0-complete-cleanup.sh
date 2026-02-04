#!/bin/bash

#############################################################################
# Script 0: Pre-Installation Cleanup
# Version: 75.0.0
# Description: Complete cleanup and reset for fresh installation
# Last Updated: 2026-02-04
#############################################################################

set -euo pipefail

#############################################################################
# COLORS AND SYMBOLS
#############################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARNING_SIGN="⚠"
readonly BROOM="🧹"
readonly TRASH="🗑️"

#############################################################################
# LOGGING FUNCTIONS
#############################################################################

log_info() {
    echo -e "${BLUE}${CHECK_MARK}${NC} $(date '+%Y-%m-%d %H:%M:%S') -  $ *"
}

log_success() {
    echo -e " $ {GREEN}${CHECK_MARK}${NC} $(date '+%Y-%m-%d %H:%M:%S') -  $ *"
}

log_warn() {
    echo -e " $ {YELLOW}${WARNING_SIGN}${NC} $(date '+%Y-%m-%d %H:%M:%S') -  $ *"
}

log_error() {
    echo -e " $ {RED}${CROSS_MARK}${NC} $(date '+%Y-%m-%d %H:%M:%S') -  $ *"
}

log_section() {
    echo ""
    echo -e " $ {CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD} $ * $ {NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#############################################################################
# CONFIRMATION PROMPT
#############################################################################

confirm_cleanup() {
    log_section "${BROOM} AI Platform - Complete Cleanup"
    echo ""
    echo -e "${YELLOW}${BOLD}WARNING: This will remove:${NC}"
    echo -e "  ${TRASH} All Docker containers and images"
    echo -e "  ${TRASH} All Docker volumes and networks"
    echo -e "  ${TRASH} Installation directory: /opt/ai-platform"
    echo -e "  ${TRASH} Data directory: /var/lib/ai-platform"
    echo -e "  ${TRASH} Log directory: /var/log/ai-platform"
    echo -e "  ${TRASH} Backup directory: /var/backups/ai-platform"
    echo -e "  ${TRASH} All configuration files"
    echo ""
    echo -e "${RED}${BOLD}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Are you sure you want to proceed? Type ${BOLD}YES${NC}${YELLOW} to confirm: ${NC})" confirmation
    
    if [[ "${confirmation}" != "YES" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "$(echo -e ${RED}Final confirmation - Type ${BOLD}DELETE${NC}${RED} to proceed: ${NC})" final_confirmation
    
    if [[ "${final_confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warn "User confirmed cleanup - proceeding..."
}

#############################################################################
# DOCKER CLEANUP
#############################################################################

cleanup_docker() {
    log_section "${TRASH} Removing Docker Resources"
    
    if command -v docker &> /dev/null; then
        log_info "Stopping all running containers..."
        docker ps -q | xargs -r docker stop 2>/dev/null || true
        log_success "Containers stopped"
        
        log_info "Removing all containers..."
        docker ps -aq | xargs -r docker rm -f 2>/dev/null || true
        log_success "Containers removed"
        
        log_info "Removing all volumes..."
        docker volume ls -q | xargs -r docker volume rm -f 2>/dev/null || true
        log_success "Volumes removed"
        
        log_info "Removing all networks (except defaults)..."
        docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none) $ ' | xargs -r docker network rm 2>/dev/null || true
        log_success "Custom networks removed"
        
        log_info "Removing all images..."
        docker images -q | xargs -r docker rmi -f 2>/dev/null || true
        log_success "Images removed"
        
        log_info "Pruning Docker system..."
        docker system prune -af --volumes 2>/dev/null || true
        log_success "Docker system pruned"
    else
        log_warn "Docker not installed - skipping Docker cleanup"
    fi
}

#############################################################################
# DIRECTORY CLEANUP
#############################################################################

cleanup_directories() {
    log_section " $ {TRASH} Removing Installation Directories"
    
    local dirs=(
        "/opt/ai-platform"
        "/var/lib/ai-platform"
        "/var/log/ai-platform"
        "/var/backups/ai-platform"
        "/etc/ai-platform"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "Removing: ${dir}"
            rm -rf "${dir}"
            log_success "Removed: ${dir}"
        else
            log_info "Not found (already clean): ${dir}"
        fi
    done
}

#############################################################################
# CONFIGURATION CLEANUP
#############################################################################

cleanup_configuration() {
    log_section "${TRASH} Removing Configuration Files"
    
    # Remove systemd services
    if compgen -G "/etc/systemd/system/ai-platform*.service" > /dev/null 2>&1; then
        log_info "Removing systemd services..."
        rm -f /etc/systemd/system/ai-platform*.service
        systemctl daemon-reload 2>/dev/null || true
        log_success "Systemd services removed"
    else
        log_info "No systemd services found"
    fi
    
    # Remove cron jobs
    if compgen -G "/etc/cron.d/ai-platform*" > /dev/null 2>&1; then
        log_info "Removing cron jobs..."
        rm -f /etc/cron.d/ai-platform*
        log_success "Cron jobs removed"
    else
        log_info "No cron jobs found"
    fi
    
    # Remove user config files
    if compgen -G "/root/.ai-platform-*" > /dev/null 2>&1; then
        log_info "Removing user config files..."
        rm -f /root/.ai-platform-*
        log_success "User config files removed"
    else
        log_info "No user config files found"
    fi
}

#############################################################################
# USER AND GROUP CLEANUP
#############################################################################

cleanup_users() {
    log_section "${TRASH} Cleaning Up Users and Groups"
    
    if id "aiplatform" &>/dev/null; then
        log_info "Removing user: aiplatform"
        userdel -r aiplatform 2>/dev/null || userdel aiplatform 2>/dev/null || true
        log_success "User removed: aiplatform"
    else
        log_info "User not found: aiplatform"
    fi
    
    if getent group aiplatform &>/dev/null; then
        log_info "Removing group: aiplatform"
        groupdel aiplatform 2>/dev/null || true
        log_success "Group removed: aiplatform"
    else
        log_info "Group not found: aiplatform"
    fi
}

#############################################################################
# FIREWALL CLEANUP
#############################################################################

cleanup_firewall() {
    log_section "${TRASH} Cleaning Up Firewall Rules"
    
    if command -v ufw &> /dev/null; then
        log_info "Removing AI Platform UFW rules..."
        
        # Remove common AI platform ports
        local ports=(80 443 3000 5432 6379 8080 9000 9090 3001 8081 8082)
        
        for port in "${ports[@]}"; do
            ufw delete allow ${port}/tcp 2>/dev/null || true
        done
        
        log_success "UFW rules cleaned"
    else
        log_info "UFW not found - skipping firewall cleanup"
    fi
}

#############################################################################
# FINAL VERIFICATION
#############################################################################

verify_cleanup() {
    log_section "${CHECK_MARK} Verifying Cleanup"
    
    local all_clean=true
    
    # Check directories
    for dir in "/opt/ai-platform" "/var/lib/ai-platform" "/var/log/ai-platform"; do
        if [[ -d "${dir}" ]]; then
            log_error "Directory still exists: ${dir}"
            all_clean=false
        fi
    done
    
    # Check Docker
    if command -v docker &> /dev/null; then
        local container_count= $ (docker ps -a -q 2>/dev/null | wc -l)
        local volume_count= $ (docker volume ls -q 2>/dev/null | wc -l)
        
        if [[ ${container_count} -gt 0 ]]; then
            log_warn "Found ${container_count} Docker containers remaining"
        fi
        
        if [[ ${volume_count} -gt 0 ]]; then
            log_warn "Found ${volume_count} Docker volumes remaining"
        fi
    fi
    
    if [[ "${all_clean}" == true

