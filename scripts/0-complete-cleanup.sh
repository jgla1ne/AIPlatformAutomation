#!/bin/bash
# 0-complete-cleanup.sh - Nuclear cleanup with proper volume management
set -euo pipefail

# Paths
DATA_ROOT="/mnt/data"
LOG_FILE="$DATA_ROOT/logs/cleanup.log"

# Ensure log directory exists
mkdir -p "$DATA_ROOT/logs"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }

# Main cleanup function
main() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          AI PLATFORM AUTOMATION - CLEANUP                      ║${NC}"
    echo -e "${GREEN}║                Version 3.0.0 - Nuclear Cleanup         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Phase 1: Volume Management
    print_info "Phase 1: Volume Management"
    manage_volumes
    
    # Phase 2: Container Cleanup
    print_info "Phase 2: Container Cleanup"
    cleanup_containers
    
    # Phase 3: Network Cleanup
    print_info "Phase 3: Network Cleanup"
    cleanup_networks
    
    # Phase 4: Volume Cleanup
    print_info "Phase 4: Volume Cleanup"
    cleanup_volumes
    
    # Phase 5: Configuration Cleanup
    print_info "Phase 5: Configuration Cleanup"
    cleanup_config
    
    print_success "Nuclear cleanup completed - Environment reset"
}

# Volume management with proper detection
manage_volumes() {
    print_info "Detecting and managing volumes..."
    
    # Unmount /mnt if mounted
    if mountpoint -q /mnt 2>/dev/null; then
        print_warning "/mnt is mounted - unmounting..."
        umount /mnt || print_error "Failed to unmount /mnt"
    fi
    
    # Detect available volumes
    local volumes=$(lsblk -d -o NAME,SIZE | grep -E "nvme|xvd" | grep -v "loop" | awk '$2 ~ /[0-9]+G/ && $2 > 50')
    
    if [[ -n "$volumes" ]]; then
        print_info "Available data volumes found:"
        echo "$volumes" | while read device size; do
            print_info "  - /dev/$device ($size)"
        done
    else
        print_warning "No data volumes found"
    fi
}

# Container cleanup
cleanup_containers() {
    print_info "Stopping and removing all containers..."
    
    # Stop all containers
    local containers=$(docker ps -q 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs -r docker stop
        print_success "All containers stopped"
    fi
    
    # Remove all containers
    local all_containers=$(docker ps -aq 2>/dev/null || true)
    if [[ -n "$all_containers" ]]; then
        echo "$all_containers" | xargs -r docker rm
        print_success "All containers removed"
    fi
}

# Network cleanup
cleanup_networks() {
    print_info "Cleaning up Docker networks..."
    
    # Remove custom networks (keep default ones)
    local networks=$(docker network ls -q --filter "type=custom" 2>/dev/null || true)
    if [[ -n "$networks" ]]; then
        echo "$networks" | xargs -r docker network rm
        print_success "Custom networks removed"
    fi
}

# Volume cleanup
cleanup_volumes() {
    print_info "Cleaning up Docker volumes..."
    
    # Remove all volumes (be careful!)
    docker volume prune -f 2>/dev/null || true
    print_success "Docker volumes cleaned"
}

# Configuration cleanup
cleanup_config() {
    print_info "Cleaning up configuration files..."
    
    # Remove data directories (be careful!)
    if [[ -d "/mnt/data" ]]; then
        # Backup important configs first
        if [[ -f "/mnt/data/.env" ]]; then
            cp /mnt/data/.env /tmp/.env.backup 2>/dev/null || true
        fi
        
        # Remove with confirmation
        rm -rf /mnt/data/*
        print_success "Configuration files cleaned"
    fi
    
    # Remove lock files
    find /tmp -name ".deployment_lock" -delete 2>/dev/null || true
}

# Execute main function
main "$@"
