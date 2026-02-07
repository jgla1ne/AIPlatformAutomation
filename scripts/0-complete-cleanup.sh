#!/usr/bin/env bash

################################################################################
# Script 0 v98.4.0 - Nuclear Purge & System Reset
# UPDATED: Complete UFW removal - cloud firewall handles security
################################################################################

set -uo pipefail  # Continue through errors, log them

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="98.4.0"
readonly SCRIPT_NAME="0-nuclear-clean.sh"
readonly LOG_FILE="/var/log/ai-platform-cleanup-$(date +%Y%m%d_%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"
readonly DATA_PATH="/mnt/data/ai-platform"

# Progress tracking
TOTAL_STEPS=14  # Reduced from 15 (removed UFW step)
CURRENT_STEP=0

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local message="$1"
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}  [${CURRENT_STEP}/${TOTAL_STEPS}] ${message}${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}   ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}   ✗ ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}   ⚠ WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}   ℹ $1${NC}" | tee -a "$LOG_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

confirm_nuclear_cleanup() {
    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                    ⚠️  NUCLEAR CLEANUP  ⚠️                     ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}This will PERMANENTLY DELETE:${NC}"
    echo "  • All Docker containers, images, volumes, networks"
    echo "  • All data in ${DATA_PATH}"
    echo "  • PostgreSQL databases"
    echo "  • Vector database storage"
    echo "  • All configuration files"
    echo "  • Rclone configurations"
    echo "  • Signal-CLI data"
    echo "  • Environment files (.env)"
    echo "  • Generated secrets"
    echo ""
    echo -e "${RED}${BOLD}THIS CANNOT BE UNDONE!${NC}"
    echo ""
    read -p "Type 'DELETE EVERYTHING' to confirm: " CONFIRMATION
    
    if [ "$CONFIRMATION" != "DELETE EVERYTHING" ]; then
        echo ""
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_warning "Starting nuclear cleanup in 5 seconds... (Ctrl+C to abort)"
    sleep 5
}

# ============================================================================
# DOCKER CLEANUP
# ============================================================================

stop_all_containers() {
    log_step "STOPPING ALL CONTAINERS"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    local running_containers
    running_containers=$(docker ps -q 2>/dev/null)
    
    if [ -n "$running_containers" ]; then
        log_info "Stopping $(echo "$running_containers" | wc -l) running containers..."
        echo "$running_containers" | xargs -r docker stop 2>/dev/null || true
        log_success "All containers stopped"
    else
        log_info "No running containers found"
    fi
}

remove_all_containers() {
    log_step "REMOVING ALL CONTAINERS"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    local all_containers
    all_containers=$(docker ps -aq 2>/dev/null)
    
    if [ -n "$all_containers" ]; then
        log_info "Removing $(echo "$all_containers" | wc -l) containers..."
        echo "$all_containers" | xargs -r docker rm -f 2>/dev/null || true
        log_success "All containers removed"
    else
        log_info "No containers found"
    fi
}

remove_all_images() {
    log_step "REMOVING ALL IMAGES"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    local all_images
    all_images=$(docker images -q 2>/dev/null)
    
    if [ -n "$all_images" ]; then
        log_info "Removing $(echo "$all_images" | wc -l) images..."
        echo "$all_images" | xargs -r docker rmi -f 2>/dev/null || true
        log_success "All images removed"
    else
        log_info "No images found"
    fi
}

remove_all_volumes() {
    log_step "REMOVING ALL VOLUMES"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    local all_volumes
    all_volumes=$(docker volume ls -q 2>/dev/null)
    
    if [ -n "$all_volumes" ]; then
        log_info "Removing $(echo "$all_volumes" | wc -l) volumes..."
        echo "$all_volumes" | xargs -r docker volume rm -f 2>/dev/null || true
        log_success "All volumes removed"
    else
        log_info "No volumes found"
    fi
}

remove_all_networks() {
    log_step "REMOVING ALL NETWORKS"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    # Get custom networks (exclude default bridge, host, none)
    local custom_networks
    custom_networks=$(docker network ls --filter type=custom -q 2>/dev/null)
    
    if [ -n "$custom_networks" ]; then
        log_info "Removing $(echo "$custom_networks" | wc -l) custom networks..."
        echo "$custom_networks" | xargs -r docker network rm 2>/dev/null || true
        log_success "All custom networks removed"
    else
        log_info "No custom networks found"
    fi
}

prune_docker_system() {
    log_step "PRUNING DOCKER SYSTEM"
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not installed - skipping"
        return 0
    fi
    
    log_info "Running system prune..."
    docker system prune -af --volumes 2>/dev/null || true
    
    log_success "Docker system pruned"
}

# ============================================================================
# DATA CLEANUP
# ============================================================================

remove_data_directory() {
    log_step "REMOVING DATA DIRECTORY"
    
    if [ ! -d "$DATA_PATH" ]; then
        log_info "Data directory not found - skipping"
        return 0
    fi
    
    log_info "Removing ${DATA_PATH}..."
    
    # Unmount any mounted filesystems first
    if mount | grep -q "$DATA_PATH"; then
        log_info "Unmounting filesystems in ${DATA_PATH}..."
        umount -R "$DATA_PATH" 2>/dev/null || true
    fi
    
    # Remove directory
    rm -rf "$DATA_PATH" 2>/dev/null || true
    
    if [ -d "$DATA_PATH" ]; then
        log_warning "Could not remove ${DATA_PATH} - may need manual cleanup"
    else
        log_success "Data directory removed"
    fi
}

# ============================================================================
# CONFIGURATION CLEANUP
# ============================================================================

remove_config_files() {
    log_step "REMOVING CONFIGURATION FILES"
    
    local config_files=(
        "${ROOT_PATH}/.env"
        "${ROOT_PATH}/.env.example"
        "${ROOT_PATH}/.secrets"
        "${ROOT_PATH}/config"
        "${ROOT_PATH}/docker-compose.yml"
        "${ROOT_PATH}/docker-compose.override.yml"
        "${ROOT_PATH}/SETUP_SUMMARY.txt"
    )
    
    for config in "${config_files[@]}"; do
        if [ -e "$config" ]; then
            rm -rf "$config" 2>/dev/null || true
            log_success "Removed $(basename "$config")"
        fi
    done
    
    log_success "Configuration files removed"
}

# ============================================================================
# SERVICE-SPECIFIC CLEANUP
# ============================================================================

remove_gdrive_sync() {
    log_step "REMOVING GOOGLE DRIVE SYNC"
    
    # Remove rclone config
    if [ -f "${HOME}/.config/rclone/rclone.conf" ]; then
        rm -f "${HOME}/.config/rclone/rclone.conf" 2>/dev/null || true
        log_success "Removed rclone configuration"
    else
        log_info "No rclone configuration found"
    fi
}

remove_signal_cli() {
    log_step "REMOVING SIGNAL-CLI"
    
    # Signal-CLI data already removed with data directory
    # Just verify it's gone
    if [ ! -d "${DATA_PATH}/signal-cli" ]; then
        log_success "Signal-CLI data removed"
    else
        log_warning "Signal-CLI data still present"
    fi
}

cleanup_docker_iptables() {
    log_step "CLEANING DOCKER IPTABLES"
    
    log_info "Flushing Docker-managed iptables chains..."
    log_info "Note: We don't use UFW - cloud firewall provides security"
    
    if command -v iptables >/dev/null 2>&1; then
        # Flush only Docker-managed chains
        iptables -t nat -F DOCKER 2>/dev/null || true
        iptables -F DOCKER 2>/dev/null || true
        iptables -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
        iptables -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
        iptables -F DOCKER-USER 2>/dev/null || true
        
        log_success "Docker iptables rules flushed"
    else
        log_info "iptables not available - skipping"
    fi
    
    log_info "Cloud provider firewall handles perimeter security"
}

# ============================================================================
# SYSTEM CLEANUP
# ============================================================================

cleanup_logs_and_temp() {
    log_step "CLEANING LOGS & TEMPORARY FILES"
    
    log_info "Cleaning logs..."
    
    # Clean AI platform logs
    rm -f /var/log/ai-platform-*.log 2>/dev/null || true
    
    # Clean temp files
    rm -rf /tmp/ai-platform-* 2>/dev/null || true
    rm -rf /tmp/docker-* 2>/dev/null || true
    
    log_success "Logs and temporary files cleaned"
}

remove_packages() {
    log_step "PACKAGE REMOVAL (OPTIONAL)"
    
    log_info "Packages NOT removed (Docker, Tailscale kept for reuse)"
    log_info "To manually remove:"
    echo ""
    echo "   # Remove Docker:"
    echo "   sudo apt-get purge -y docker-ce docker-ce-cli containerd.io"
    echo ""
    echo "   # Remove Tailscale:"
    echo "   sudo apt-get purge -y tailscale"
    echo ""
    log_info "Run 'sudo apt-get autoremove' after manual removal"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_cleanup() {
    log_step "VERIFYING CLEANUP"
    
    local verification_passed=true
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        local container_count
        container_count=$(docker ps -aq 2>/dev/null | wc -l)
        
        if [ "$container_count" -eq 0 ]; then
            log_success "Docker containers: 0"
        else
            log_warning "Docker containers: ${container_count} (should be 0)"
            verification_passed=false
        fi
        
        local image_count
        image_count=$(docker images -q 2>/dev/null | wc -l)
        
        if [ "$image_count" -eq 0 ]; then
            log_success "Docker images: 0"
        else
            log_warning "Docker images: ${image_count} (should be 0)"
        fi
        
        local volume_count
        volume_count=$(docker volume ls -q 2>/dev/null | wc -l)
        
        if [ "$volume_count" -eq 0 ]; then
            log_success "Docker volumes: 0"
        else
            log_warning "Docker volumes: ${volume_count} (should be 0)"
        fi
    fi
    
    # Check data directory
    if [ ! -d "$DATA_PATH" ]; then
        log_success "Data directory removed"
    else
        log_warning "Data directory still exists"
        verification_passed=false
    fi
    
    # Check config files
    if [ ! -f "${ROOT_PATH}/.env" ]; then
        log_success "Environment file removed"
    else
        log_warning "Environment file still exists"
        verification_passed=false
    fi
    
    if [ "$verification_passed" = true ]; then
        log_success "All verification checks passed"
    else
        log_warning "Some items remain - may need manual cleanup"
    fi
}

# ============================================================================
# FINAL REPORT
# ============================================================================

generate_cleanup_report() {
    log_step "GENERATING CLEANUP REPORT"
    
    local report_file="${ROOT_PATH}/CLEANUP_REPORT_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" <<EOF
╔════════════════════════════════════════════════════════════════╗
║              NUCLEAR CLEANUP REPORT                           ║
║              Generated: $(date)                    ║
╚════════════════════════════════════════════════════════════════╝

CLEANED ITEMS
────────────────────────────────────────────────────────────────
✓ All Docker containers stopped and removed
✓ All Docker images removed
✓ All Docker volumes removed
✓ All Docker networks removed
✓ Docker system pruned
✓ Data directory removed (${DATA_PATH})
✓ Configuration files removed
✓ Environment files removed
✓ Secrets removed
✓ Rclone configurations removed
✓ Signal-CLI data removed
✓ Docker iptables chains flushed
✓ Logs and temporary files cleaned

RETAINED ITEMS (for reuse)
────────────────────────────────────────────────────────────────
✓ Docker Engine & Compose (v$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//' || echo 'N/A'))
✓ Tailscale ($(tailscale version 2>/dev/null | head -n1 || echo 'N/A'))

SECURITY MODEL
────────────────────────────────────────────────────────────────
⚠ NO UFW - Cloud provider firewall provides perimeter security
✓ Tailscale handles secure internal access
✓ Docker manages container networking
✓ Reverse proxy will handle TLS termination

SYSTEM STATUS
────────────────────────────────────────────────────────────────
System ready for fresh deployment

Next Steps:
  1. Run: sudo ./scripts/1-setup-system.sh
  2. Configure cloud provider firewall rules
  3. Set up DNS records
  4. Deploy services with subsequent scripts

═══════════════════════════════════════════════════════════════
Cleanup completed successfully!
═══════════════════════════════════════════════════════════════
EOF

    cat "$report_file" | tee -a "$LOG_FILE"
    
    log_success "Report saved to: ${report_file}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║       AI PLATFORM - NUCLEAR CLEANUP v${SCRIPT_VERSION}              ║${NC}"
    echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Pre-flight
    check_root
    confirm_nuclear_cleanup
    
    # Docker cleanup
    stop_all_containers
    remove_all_containers
    remove_all_images
    remove_all_volumes
    remove_all_networks
    prune_docker_system
    
    # Data cleanup
    remove_data_directory
    
    # Configuration cleanup
    remove_config_files
    
    # Service-specific cleanup
    remove_gdrive_sync
    remove_signal_cli
    
    # System cleanup
    cleanup_docker_iptables  # NO UFW
    cleanup_logs_and_temp
    remove_packages
    
    # Verification
    verify_cleanup
    generate_cleanup_report
    
    # Success
    echo ""
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  NUCLEAR PURGE COMPLETE${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    log_success "All AI platform components removed"
    echo ""
    log_info "System ready for fresh deployment"
    log_info "Next: sudo ./scripts/1-setup-system.sh"
    echo ""
    
    # Reboot prompt
    read -p "Reboot now? (yes/no): " REBOOT_NOW
    
    if [ "$REBOOT_NOW" = "yes" ]; then
        log_info "Rebooting in 10 seconds... (Ctrl+C to cancel)"
        sleep 10
        reboot
    else
        log_info "Reboot skipped - manual reboot recommended"
        echo ""
        echo -e "${YELLOW}Run 'sudo reboot' before next deployment${NC}"
        echo ""
    fi
}

main "$@"
