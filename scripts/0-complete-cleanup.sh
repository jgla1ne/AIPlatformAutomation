#!/usr/bin/env bash

################################################################################
# SCRIPT 0 v98.8.0 - COMPLETE NUCLEAR CLEANUP
# Returns system to PRE-SCRIPT-1 state by:
#   1. Stopping all services
#   2. Removing Docker completely (packages + data + AppArmor)
#   3. Removing Tailscale completely
#   4. Removing Caddy completely
#   5. Cleaning all deployment artifacts
#   6. Resetting user permissions
#   7. Flushing iptables rules
#   8. Cleaning AppArmor profiles
#
# CRITICAL: This script NEVER deletes:
#   - $ROOT_PATH/scripts/ (deployment source)
#   - $ROOT_PATH/doc/ (documentation)
#   - $ROOT_PATH/changelog/ (version history)
################################################################################

set -euo pipefail

readonly SCRIPT_VERSION="98.8.0"
readonly SCRIPT_NAME="0-nuclear-cleanup.sh"
readonly LOG_DIR="$HOME/ai-platform-logs"
readonly LOG_FILE="${LOG_DIR}/nuclear-cleanup-$(date +%Y%m%d_%H%M%S).log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"

# ============================================================================
# LOGGING
# ============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    
    # Delete old logs (keep only last 5 cleanup logs)
    if [[ -d "$LOG_DIR" ]]; then
        cd "$LOG_DIR"
        ls -t nuclear-cleanup-*.log 2>/dev/null | tail -n +6 | xargs -r rm -- 2>/dev/null || true
        cd - > /dev/null
    fi
    
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
}

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}▶ $*${NC}\n"
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

print_header() {
    clear
    echo -e "${BOLD}${RED}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║        ☢️  NUCLEAR CLEANUP v${SCRIPT_VERSION}                      ║"
    echo "║                                                          ║"
    echo "║  WARNING: This will COMPLETELY REMOVE all components    ║"
    echo "║  installed by Script 1 and return to PRE-INSTALL state  ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

show_removal_scope() {
    echo -e "${RED}${BOLD}WILL REMOVE PACKAGES:${NC}"
    echo "  • Docker (docker-ce, containerd.io, docker-compose-plugin)"
    echo "  • Tailscale"
    echo "  • Caddy"
    echo ""
    
    echo -e "${RED}${BOLD}WILL DELETE DATA:${NC}"
    echo "  • /var/lib/docker/ (all Docker data)"
    echo "  • /var/lib/containerd/ (all container data)"
    echo "  • /etc/docker/ (Docker configs)"
    echo "  • /mnt/data/ai-platform/ (persistent data)"
    echo "  • ${ROOT_PATH}/logs/"
    echo "  • ${ROOT_PATH}/config/"
    echo "  • ${ROOT_PATH}/stack/"
    echo "  • ${ROOT_PATH}/.secrets/"
    echo ""
    
    echo -e "${RED}${BOLD}WILL CLEAN:${NC}"
    echo "  • Docker AppArmor profiles"
    echo "  • Docker iptables chains"
    echo "  • Systemd services (gdrive-sync, ai-platform)"
    echo "  • User docker group membership"
    echo ""
    
    echo -e "${GREEN}${BOLD}WILL PRESERVE:${NC}"
    echo "  • ${ROOT_PATH}/scripts/ (deployment source)"
    echo "  • ${ROOT_PATH}/doc/ (documentation)"
    echo "  • ${ROOT_PATH}/changelog/ (version history)"
    echo "  • ${ROOT_PATH}/.git/ (git repository)"
    echo "  • Base system packages (curl, git, jq, etc.)"
    echo ""
}

confirm_nuclear() {
    show_removal_scope
    
    echo -e "${MAGENTA}${BOLD}This is a DESTRUCTIVE operation!${NC}"
    echo -e "${MAGENTA}All Docker containers, images, volumes will be permanently deleted.${NC}"
    echo ""
    
    read -p "$(echo -e ${RED}❯${NC}) Type 'NUCLEAR' to confirm: " confirmation
    
    if [[ "$confirmation" != "NUCLEAR" ]]; then
        log_error "Nuclear cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_warning "Starting nuclear cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    echo ""
}

# ============================================================================
# DOCKER REMOVAL
# ============================================================================

stop_docker_completely() {
    log_step "STOPPING DOCKER SERVICES"
    
    # Stop all running containers first
    if command -v docker &> /dev/null; then
        log "Stopping all Docker containers..."
        docker ps -q | xargs -r docker stop 2>/dev/null || true
        log_success "All containers stopped"
        
        log "Removing all containers..."
        docker ps -aq | xargs -r docker rm -f 2>/dev/null || true
        log_success "All containers removed"
    fi
    
    # Stop Docker services
    log "Stopping Docker systemd services..."
    systemctl stop docker.socket 2>/dev/null || true
    systemctl stop docker.service 2>/dev/null || true
    systemctl stop containerd.service 2>/dev/null || true
    
    # Disable services
    systemctl disable docker.socket 2>/dev/null || true
    systemctl disable docker.service 2>/dev/null || true
    systemctl disable containerd.service 2>/dev/null || true
    
    log_success "Docker services stopped and disabled"
}

remove_docker_packages() {
    log_step "REMOVING DOCKER PACKAGES"
    
    # Full purge of Docker packages
    log "Purging Docker packages..."
    apt-get purge -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-ce-rootless-extras 2>/dev/null || true
    
    # Remove any remaining Docker packages
    apt-get autoremove -y --purge 2>/dev/null || true
    
    log_success "Docker packages purged"
}

remove_docker_data() {
    log_step "REMOVING DOCKER DATA DIRECTORIES"
    
    # Remove Docker data directories
    local dirs=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/etc/docker"
        "/var/run/docker.sock"
        "/var/run/docker"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -e "$dir" ]]; then
            rm -rf "$dir"
            log_success "Removed $dir"
        fi
    done
}

clean_docker_apparmor() {
    log_step "CLEANING DOCKER APPARMOR PROFILES"
    
    if ! command -v aa-status &> /dev/null; then
        log_warning "AppArmor not available, skipping"
        return 0
    fi
    
    # Unload all Docker-related AppArmor profiles
    log "Unloading Docker AppArmor profiles..."
    
    if command -v aa-teardown &> /dev/null; then
        aa-teardown 2>/dev/null || true
        log_success "Used aa-teardown to unload profiles"
    else
        # Manual unloading
        for profile in /etc/apparmor.d/docker-*; do
            if [[ -f "$profile" ]]; then
                apparmor_parser -R "$profile" 2>/dev/null || true
            fi
        done
        log_success "Manually unloaded Docker profiles"
    fi
    
    # Remove Docker AppArmor profile files
    rm -f /etc/apparmor.d/docker-* 2>/dev/null || true
    rm -f /etc/apparmor.d/cache/docker-* 2>/dev/null || true
    
    # Reload AppArmor (don't start, just enable for next boot)
    systemctl enable apparmor 2>/dev/null || true
    
    log_success "Docker AppArmor profiles cleaned"
}

clean_docker_iptables() {
    log_step "CLEANING DOCKER IPTABLES RULES"
    
    if ! command -v iptables &> /dev/null; then
        log_warning "iptables not available, skipping"
        return 0
    fi
    
    log "Flushing Docker iptables chains..."
    
    # Flush and delete DOCKER chains
    for chain in DOCKER DOCKER-ISOLATION-STAGE-1 DOCKER-ISOLATION-STAGE-2 DOCKER-USER; do
        iptables -t filter -F "$chain" 2>/dev/null || true
        iptables -t filter -X "$chain" 2>/dev/null || true
        iptables -t nat -F "$chain" 2>/dev/null || true
        iptables -t nat -X "$chain" 2>/dev/null || true
    done
    
    # Save rules if iptables-persistent is installed
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save 2>/dev/null || true
    fi
    
    log_success "Docker iptables rules cleaned"
}

remove_user_from_docker_group() {
    log_step "REMOVING USER FROM DOCKER GROUP"
    
    local actual_user="${SUDO_USER:-$USER}"
    
    if getent group docker &> /dev/null; then
        if id -nG "$actual_user" | grep -qw docker; then
            gpasswd -d "$actual_user" docker
            log_success "Removed $actual_user from docker group"
        else
            log_warning "$actual_user not in docker group"
        fi
        
        # Delete docker group
        groupdel docker 2>/dev/null || true
        log_success "Deleted docker group"
    else
        log_warning "Docker group does not exist"
    fi
}

# ============================================================================
# TAILSCALE REMOVAL
# ============================================================================

remove_tailscale() {
    log_step "REMOVING TAILSCALE"
    
    if ! command -v tailscale &> /dev/null; then
        log_warning "Tailscale not installed, skipping"
        return 0
    fi
    
    # Disconnect first
    log "Disconnecting Tailscale..."
    tailscale down 2>/dev/null || true
    
    # Stop and disable service
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true
    
    # Purge package
    log "Purging Tailscale package..."
    apt-get purge -y tailscale 2>/dev/null || true
    
    # Remove Tailscale data
    rm -rf /var/lib/tailscale
    rm -f /etc/systemd/system/tailscaled.service.d/*.conf
    
    log_success "Tailscale removed"
}

# ============================================================================
# CADDY REMOVAL
# ============================================================================

remove_caddy() {
    log_step "REMOVING CADDY"
    
    if ! command -v caddy &> /dev/null; then
        log_warning "Caddy not installed, skipping"
        return 0
    fi
    
    # Stop and disable service
    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    
    # Purge package
    log "Purging Caddy package..."
    apt-get purge -y caddy 2>/dev/null || true
    
    # Remove Caddy data
    rm -rf /etc/caddy
    rm -rf /var/lib/caddy
    rm -rf /usr/share/caddy
    
    log_success "Caddy removed"
}

# ============================================================================
# SYSTEMD SERVICES REMOVAL
# ============================================================================

remove_custom_systemd_services() {
    log_step "REMOVING CUSTOM SYSTEMD SERVICES"
    
    local services=(
        "gdrive-sync.service"
        "gdrive-sync.timer"
        "ai-platform.service"
        "ai-platform-health.service"
        "ai-platform-health.timer"
    )
    
    local removed=0
    
    for service in "${services[@]}"; do
        if [[ -f "/etc/systemd/system/$service" ]]; then
            log "Removing $service..."
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/$service"
            removed=$((removed + 1))
        fi
    done
    
    if [[ $removed -gt 0 ]]; then
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        log_success "Removed $removed systemd service(s)"
    else
        log_warning "No custom systemd services found"
    fi
}

# ============================================================================
# FILESYSTEM CLEANUP
# ============================================================================

remove_deployment_artifacts() {
    log_step "REMOVING DEPLOYMENT ARTIFACTS"
    
    cd "$ROOT_PATH" || exit 1
    
    # Remove generated directories
    local dirs=("logs" "config" "stack" ".secrets")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_success "Removed $dir/"
        fi
    done
    
    # Remove environment files
    rm -f .env platform.env
    log_success "Removed .env and platform.env"
    
    # Remove any docker-compose files in root
    rm -f docker-compose*.yml
    log_success "Removed compose files"
    
    # Verify protected folders still exist
    for protected_dir in scripts doc changelog; do
        if [[ ! -d "$protected_dir" ]]; then
            log_error "CRITICAL: ${protected_dir}/ was deleted! This should never happen!"
            log_error "Current directory: $(pwd)"
            log_error "Directory listing:"
            ls -la
            exit 1
        fi
    done
    
    log_success "Protected folders verified intact (scripts/, doc/, changelog/)"
}

remove_persistent_data() {
    log_step "REMOVING PERSISTENT DATA"
    
    if [[ -d "/mnt/data/ai-platform" ]]; then
        rm -rf /mnt/data/ai-platform
        log_success "Removed /mnt/data/ai-platform/"
    else
        log_warning "/mnt/data/ai-platform/ does not exist"
    fi
}

# ============================================================================
# LOG CLEANUP
# ============================================================================

clean_deployment_logs() {
    log_step "CLEANING DEPLOYMENT LOGS"
    
    if [[ ! -d "$LOG_DIR" ]]; then
        log_warning "No log directory found"
        return 0
    fi
    
    cd "$LOG_DIR" || return 0
    
    # Keep only last 5 of each log type
    for log_prefix in setup deploy nuclear-cleanup; do
        ls -t ${log_prefix}-*.log 2>/dev/null | tail -n +6 | xargs -r rm -- 2>/dev/null || true
    done
    
    log_success "Old logs cleaned (kept last 5 of each type)"
}

# ============================================================================
# FINAL VERIFICATION
# ============================================================================

verify_nuclear_cleanup() {
    log_step "VERIFYING NUCLEAR CLEANUP"
    
    local errors=0
    
    # Check Docker removed
    if command -v docker &> /dev/null; then
        log_error "Docker command still exists"
        errors=$((errors + 1))
    else
        log_success "Docker command removed"
    fi
    
    # Check Docker data removed
    if [[ -d "/var/lib/docker" ]]; then
        log_error "/var/lib/docker still exists"
        errors=$((errors + 1))
    else
        log_success "/var/lib/docker removed"
    fi
    
    # Check Tailscale removed
    if command -v tailscale &> /dev/null; then
        log_warning "Tailscale still installed (may be intentional)"
    else
        log_success "Tailscale removed"
    fi
    
    # Check Caddy removed
    if command -v caddy &> /dev/null; then
        log_warning "Caddy still installed (may be intentional)"
    else
        log_success "Caddy removed"
    fi
    
    # Check protected folders exist
    for protected_dir in scripts doc changelog; do
        if [[ -d "${ROOT_PATH}/${protected_dir}" ]]; then
            log_success "${protected_dir}/ preserved"
        else
            log_error "${protected_dir}/ missing!"
            errors=$((errors + 1))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_error "Nuclear cleanup completed with $errors error(s)"
        return 1
    else
        log_success "Nuclear cleanup verification passed"
        return 0
    fi
}

# ============================================================================
# FINAL STATUS
# ============================================================================

show_final_status() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                                                          ║${NC}"
    echo -e "${BOLD}${GREEN}║            ✅ NUCLEAR CLEANUP COMPLETE                   ║${NC}"
    echo -e "${BOLD}${GREEN}║                                                          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD}📦 Packages removed:${NC}"
    echo "  ✓ Docker (docker-ce, containerd.io)"
    echo "  ✓ Tailscale"
    echo "  ✓ Caddy"
    echo ""
    
    echo -e "${CYAN}${BOLD}🧹 Data cleaned:${NC}"
    echo "  ✓ /var/lib/docker/"
    echo "  ✓ /var/lib/containerd/"
    echo "  ✓ /mnt/data/ai-platform/"
    echo "  ✓ Docker AppArmor profiles"
    echo "  ✓ Docker iptables chains"
    echo ""
    
    echo -e "${CYAN}${BOLD}📁 Protected folders preserved:${NC}"
    ls -ld "${ROOT_PATH}/scripts" 2>/dev/null && echo "  ✓ scripts/"
    ls -ld "${ROOT_PATH}/doc" 2>/dev/null && echo "  ✓ doc/"
    ls -ld "${ROOT_PATH}/changelog" 2>/dev/null && echo "  ✓ changelog/"
    ls -f "${ROOT_PATH}/README.md" 2>/dev/null && echo "  ✓ README.md"
    echo ""
    
    echo -e "${YELLOW}${BOLD}⚠️  REBOOT REQUIRED${NC}"
    echo "  System must reboot to complete cleanup:"
    echo "  • Unload all kernel modules"
    echo "  • Reset network stack"
    echo "  • Clear user sessions"
    echo ""
    
    echo -e "${YELLOW}${BOLD}📝 After reboot:${NC}"
    echo "  1. Verify clean state: docker ps (should fail)"
    echo "  2. Update repository: git pull"
    echo "  3. Run fresh install: sudo bash scripts/1-setup-system.sh"
    echo ""
    
    echo -e "${CYAN}Log saved to: ${LOG_FILE}${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}❯${NC}) Reboot now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log "Rebooting system in 3 seconds..."
        sleep 3
        reboot
    else
        log_warning "Remember to reboot before running Script 1!"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Setup logging first
    setup_logging
    
    # Print header
    print_header
    
    # Root check
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Verify we're in the right directory
    if [[ ! -d "${ROOT_PATH}/scripts" ]] || [[ ! -d "${ROOT_PATH}/doc" ]]; then
        log_error "Cannot find scripts/ or doc/ directories"
        log_error "Expected location: ${ROOT_PATH}"
        log_error "Current listing:"
        ls -la "${ROOT_PATH}"
        exit 1
    fi
    
    # Confirm nuclear cleanup
    confirm_nuclear
    
    # Execute cleanup in order
    log "Starting nuclear cleanup..."
    echo ""
    
    # Docker removal (most critical)
    stop_docker_completely
    remove_docker_packages
    remove_docker_data
    clean_docker_apparmor
    clean_docker_iptables
    remove_user_from_docker_group
    
    # Other services
    remove_tailscale
    remove_caddy
    remove_custom_systemd_services
    
    # Filesystem cleanup
    remove_deployment_artifacts
    remove_persistent_data
    clean_deployment_logs
    
    # Final verification
    if ! verify_nuclear_cleanup; then
        log_error "Nuclear cleanup completed with errors (see above)"
        echo ""
        echo -e "${RED}Review the log: ${LOG_FILE}${NC}"
        exit 1
    fi
    
    # Show final status and reboot prompt
    show_final_status
}

# Execute
main "$@"
