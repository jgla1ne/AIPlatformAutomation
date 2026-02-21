#!/bin/bash
# Script 0: Stack Teardown
#
# NOTE: This script runs as root (required for Docker, AppArmor cleanup)

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM - COMPLETE STACK TEARDOWN           ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           Safe Removal with AppArmor Cleanup                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Auto-detect stack from current directory or environment
detect_stack() {
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
        print_success "Stack detected: ${DOMAIN_NAME}"
        return 0
    else
        # Only exit if not running list command
        if [[ "${1:-}" != "--list" ]]; then
            print_error "No stack configuration found. Run from stack directory or set BASE_DIR."
            exit 1
        fi
        return 1
    fi
}

# Confirm teardown action
confirm_teardown() {
    print_header "Teardown Confirmation"
    
    # Only detect stack if not doing --list
    if [[ "${1:-}" != "--list" ]]; then
        detect_stack
    fi
    
    echo "⚠️  WARNING: This will completely remove the AI Platform stack:"
    echo ""
    echo "📊 Stack Information:"
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        echo "   Domain: ${DOMAIN_NAME}"
        echo "   Network: ${DOCKER_NETWORK}"
        echo "   Base Directory: ${BASE_DIR}"
    else
        echo "   No stack detected - will scan for all stacks"
    fi
    echo ""
    echo "🔍 What will be removed:"
    if [[ -n "${DOCKER_NETWORK:-}" ]]; then
        echo "   • All containers on network ${DOCKER_NETWORK}"
        echo "   • Docker network ${DOCKER_NETWORK}"
        echo "   • AppArmor profiles for ${DOCKER_NETWORK}"
    else
        echo "   • All containers on all stack networks"
        echo "   • All stack Docker networks"
        echo "   • All stack AppArmor profiles"
    fi
    echo ""
    echo "   • Optionally: All stack data and configuration"
    echo ""
    
    read -p "Are you sure you want to teardown this stack? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Teardown cancelled"
        exit 0
    fi
}

# Stop all containers on the network
stop_containers() {
    print_header "Stopping Containers"
    
    detect_stack
    
    local containers=($(docker ps --filter "network=${DOCKER_NETWORK}" --format "{{.Names}}"))
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        print_info "No running containers found on network ${DOCKER_NETWORK}"
        return
    fi
    
    print_info "Stopping ${#containers[@]} containers..."
    
    for container in "${containers[@]}"; do
        print_info "Stopping $container..."
        docker stop "$container" 2>/dev/null || true
    done
    
    print_success "All containers stopped"
}

# Remove all containers on the network
remove_containers() {
    print_header "Removing Containers"
    
    detect_stack
    
    local containers=($(docker ps -a --filter "network=${DOCKER_NETWORK}" --format "{{.Names}}"))
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        print_info "No containers found on network ${DOCKER_NETWORK}"
        return
    fi
    
    print_info "Removing ${#containers[@]} containers..."
    
    for container in "${containers[@]}"; do
        print_info "Removing $container..."
        docker rm "$container" 2>/dev/null || true
    done
    
    print_success "All containers removed"
}

# Remove Docker network
remove_network() {
    print_header "Removing Docker Network"
    
    detect_stack
    
    if docker network ls --format "{{.Name}}" | grep -q "^${DOCKER_NETWORK}$"; then
        print_info "Removing network ${DOCKER_NETWORK}..."
        docker network rm "${DOCKER_NETWORK}" 2>/dev/null || true
        print_success "Docker network removed"
    else
        print_info "Network ${DOCKER_NETWORK} not found"
    fi
}

# Remove AppArmor profiles
remove_apparmor_profiles() {
    print_header "Removing AppArmor Profiles"
    
    detect_stack
    
    local profiles=($(ls /etc/apparmor.d/ 2>/dev/null | grep "^${DOCKER_NETWORK}-" || true))
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        print_info "No AppArmor profiles found for ${DOCKER_NETWORK}"
        return
    fi
    
    print_info "Removing ${#profiles[@]} AppArmor profiles..."
    
    for profile in "${profiles[@]}"; do
        print_info "Removing profile $profile..."
        apparmor_parser -R "/etc/apparmor.d/$profile" 2>/dev/null || true
        rm -f "/etc/apparmor.d/$profile"
    done
    
    print_success "AppArmor profiles removed"
}

# Clean up Docker resources
cleanup_docker_resources() {
    print_header "Cleaning Up Docker Resources"
    
    # Remove stopped containers
    print_info "Removing stopped containers..."
    docker container prune -f
    
    # Remove unused images
    print_info "Removing unused images..."
    docker image prune -f
    
    # Remove unused volumes (be careful with this)
    read -p "Remove unused Docker volumes? (y/N): " remove_volumes
    if [[ "$remove_volumes" =~ ^[Yy]$ ]]; then
        print_warning "This will remove ALL unused volumes, not just stack volumes"
        read -p "Are you sure? (y/N): " confirm_volumes
        if [[ "$confirm_volumes" =~ ^[Yy]$ ]]; then
            docker volume prune -f
            print_success "Unused volumes removed"
        fi
    fi
    
    # Remove unused networks (excluding any that might be in use by other stacks)
    print_info "Removing unused networks..."
    docker network prune -f
    
    print_success "Docker cleanup completed"
}

# Remove stack data and configuration
remove_stack_data() {
    print_header "Removing Stack Data"
    
    # Only detect stack if not doing --list
    if [[ "${1:-}" != "--list" ]]; then
        detect_stack
    fi
    
    # Check if BASE_DIR exists
    if [[ ! -d "${BASE_DIR:-}" ]]; then
        print_info "Base directory ${BASE_DIR:-not set} not found"
        return
    fi
    
    # Show what will be removed
    echo "📁 Data to be removed:"
    if [[ -d "${BASE_DIR}/data" ]]; then
        echo "   • Data directory: $(du -sh "${BASE_DIR}/data" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
    if [[ -d "${BASE_DIR}/logs" ]]; then
        echo "   • Logs directory: $(du -sh "${BASE_DIR}/logs" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
    if [[ -d "${BASE_DIR}/config" ]]; then
        echo "   • Configuration directory: $(du -sh "${BASE_DIR}/config" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
    if [[ -d "${BASE_DIR}/apparmor" ]]; then
        echo "   • AppArmor templates: $(du -sh "${BASE_DIR}/apparmor" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
    if [[ -d "${BASE_DIR}/caddy" ]]; then
        echo "   • Caddy configuration: $(du -sh "${BASE_DIR}/caddy" 2>/dev/null | cut -f1 || echo "unknown")"
    fi
    echo ""
    
    read -p "Remove all stack data from ${BASE_DIR}? (y/N): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        print_info "Removing stack data..."
        rm -rf "${BASE_DIR}"
        print_success "Stack data removed"
    else
        print_warning "Stack data preserved in ${BASE_DIR}"
    fi
}

# Create backup before teardown
create_backup() {
    print_header "Creating Backup"
    
    # Only detect stack if not doing --list
    if [[ "${1:-}" != "--list" ]]; then
        detect_stack
    fi
    
    local backup_dir="${BASE_DIR:-}/../backup-$(date +%Y%m%d_%H%M%S)-${DOMAIN_NAME:-all-stacks}"
    
    print_info "Creating backup in ${backup_dir}..."
    
    mkdir -p "$backup_dir"
    
    # Backup configuration
    if [[ -f "${BASE_DIR}/config/.env" ]]; then
        cp "${BASE_DIR}/config/.env" "$backup_dir/"
        print_success "Configuration backed up"
    fi
    
    # Backup AppArmor templates
    if [[ -d "${BASE_DIR}/apparmor" ]]; then
        cp -r "${BASE_DIR}/apparmor" "$backup_dir/"
        print_success "AppArmor templates backed up"
    fi
    
    # Backup Caddy configuration
    if [[ -d "${BASE_DIR}/caddy" ]]; then
        cp -r "${BASE_DIR}/caddy" "$backup_dir/"
        print_success "Caddy configuration backed up"
    fi
    
    # Export container configurations
    mkdir -p "$backup_dir/containers"
    local containers=($(docker ps -a --filter "network=${DOCKER_NETWORK}" --format "{{.Names}}" 2>/dev/null || true))
    for container in "${containers[@]}"; do
        docker inspect "$container" > "$backup_dir/containers/${container}.json" 2>/dev/null || true
    done
    
    if [[ ${#containers[@]} -gt 0 ]]; then
        print_success "Container configurations exported"
    fi
    
    print_success "Backup created: $backup_dir"
}

# Show teardown summary
show_summary() {
    print_header "Teardown Summary"
    
    detect_stack
    
    echo "📊 Stack Information:"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Base Directory: ${BASE_DIR}"
    echo ""
    echo "✅ Teardown Actions Completed:"
    echo "   • All containers stopped and removed"
    echo "   • Docker network removed"
    echo "   • AppArmor profiles removed"
    echo "   • Docker resources cleaned up"
    echo ""
    
    if [[ -d "${BASE_DIR}" ]]; then
        echo "⚠️  Stack data preserved in ${BASE_DIR}"
        echo "   To remove data manually: rm -rf ${BASE_DIR}"
    else
        echo "✅ Stack data removed"
    fi
    
    echo ""
    print_success "Stack teardown completed successfully!"
}

# List all available stacks
list_stacks() {
    print_header "Available Stacks"
    
    echo "📊 Stacks found on this system:"
    echo ""
    
    local found_stacks=0
    
    # Look for .env files in common locations
    for dir in /mnt/data*; do
        if [[ -f "$dir/config/.env" ]]; then
            local domain_name=$(grep "^DOMAIN_NAME=" "$dir/config/.env" | cut -d'=' -f2)
            local network_name=$(grep "^DOCKER_NETWORK=" "$dir/config/.env" | cut -d'=' -f2)
            local user_uid=$(grep "^STACK_USER_UID=" "$dir/config/.env" | cut -d'=' -f2)
            
            echo "🔧 Stack: $domain_name"
            echo "   Base Directory: $dir"
            echo "   Network: $network_name"
            echo "   User UID: $user_uid"
            echo ""
            
            ((found_stacks++))
        fi
    done
    
    if [[ $found_stacks -eq 0 ]]; then
        print_warning "No stacks found"
    else
        print_info "Found $found_stacks stack(s)"
        echo ""
        echo "💡 To teardown a specific stack:"
        echo "   cd /path/to/stack && $0"
        echo "   BASE_DIR=/path/to/stack $0"
    fi
}

# Show help
show_help() {
    print_header "Teardown Help"
    
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --backup, -b        Create backup before teardown"
    echo "  --list, -l          List all available stacks"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  Teardown current stack"
    echo "  $0 --backup         Teardown with backup"
    echo "  $0 --list           List all stacks"
    echo ""
    echo "Environment Variables:"
    echo "  BASE_DIR            Stack base directory (auto-detected)"
    echo ""
    echo "What gets removed:"
    echo "  • All containers on the stack network"
    echo "  • Docker network for the stack"
    echo "  • AppArmor profiles for the stack"
    echo "  • Optionally: All stack data and configuration"
}

# Main teardown function
teardown_stack() {
    local create_backup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup|-b)
                create_backup=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_banner
    
    # Create backup if requested
    if [[ "$create_backup" == true ]]; then
        create_backup
    fi
    
    # Execute teardown phases
    confirm_teardown
    stop_containers
    remove_containers
    remove_network
    remove_apparmor_profiles
    cleanup_docker_resources
    remove_stack_data
    show_summary
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Handle special commands
    case "${1:-}" in
        --list|-l)
            list_stacks
            return
            ;;
        --help|-h)
            show_help
            return
            ;;
    esac
    
    # Run teardown
    teardown_stack "$@"
}

# Run main function
main "$@"
