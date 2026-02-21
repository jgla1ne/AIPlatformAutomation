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
    echo -e "${CYAN}╚══════════════════════════════━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╝${NC}\n"
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

# Stop all containers on the network
stop_containers() {
    print_header "Stopping Containers"
    
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
    
    # Remove unused networks
    print_info "Removing unused networks..."
    docker network prune -f
    
    print_success "Docker cleanup completed"
}

# Remove stack data and configuration
remove_stack_data() {
    print_header "Removing Stack Data"
    
    # Check if BASE_DIR exists
    if [[ ! -d "${BASE_DIR}" ]]; then
        print_info "Base directory ${BASE_DIR} not found"
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

# Show teardown summary
show_summary() {
    print_header "Teardown Summary"
    
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

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_banner
    
    # Always scan EBS volumes and prompt for selection
    scan_and_select_stack
}

# Scan EBS volumes and let user select stack to cleanup
scan_and_select_stack() {
    print_header "Scanning EBS Volumes for Stacks"
    
    echo "🔍 Scanning for mounted EBS volumes..."
    echo ""
    
    # List all mounted block devices (remove tree characters and filter)
    local mounted_volumes=($(findmnt -n -o SOURCE,TARGET | grep -E "/mnt|/tmp" | awk '{print $2}' | sed 's/^[├│└─]*//' | grep -v "^/$" | sort -u || true))
    
    if [[ ${#mounted_volumes[@]} -eq 0 ]]; then
        print_warning "No EBS volumes found mounted"
        echo ""
        echo "💡 This appears to be a nuclear purge scenario."
        echo "   Script 1 is responsible for .env creation and folder structure."
        echo "   If you want to clean everything, this will remove all AI Platform data."
        echo ""
        read -p "Proceed with nuclear cleanup of all AI Platform data? (y/N): " nuclear
        if [[ "$nuclear" =~ ^[Yy]$ ]]; then
            nuclear_cleanup
        else
            print_info "Cleanup cancelled"
            exit 0
        fi
        return
    fi
    
    echo "📋 Found EBS Volumes:"
    echo ""
    printf "%-5s %-20s %-15s %-20s %-15s\n" "NUM" "MOUNT POINT" "STACK" "DOMAIN" "STATUS"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    local stack_volumes=()
    local stack_count=0
    
    for i in "${!mounted_volumes[@]}"; do
        local volume="${mounted_volumes[$i]}"
        local env_file="$volume/config/.env"
        local stack_name="Not Found"
        local domain_name="Not Found"
        local status="No Config"
        
        if [[ -f "$env_file" ]]; then
            stack_name=$(grep "^DOMAIN_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
            domain_name=$(grep "^DOCKER_NETWORK=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
            status="Configured"
            stack_volumes+=("$volume")
            ((stack_count++))
        fi
        
        printf "%-5s %-20s %-15s %-20s %-15s\n" "$((i+1))" "$volume" "$stack_name" "$domain_name" "$status"
    done
    
    echo ""
    
    if [[ $stack_count -eq 0 ]]; then
        print_warning "No configured stacks found on EBS volumes"
        echo ""
        echo "💡 Available options:"
        echo "   1. Nuclear cleanup of all AI Platform data"
        echo "   2. Cancel and run Script 1 to create a stack first"
        echo ""
        
        while true; do
            read -p "Choose option (1-2): " choice
            if [[ "$choice" == "1" ]]; then
                nuclear_cleanup
                break
            elif [[ "$choice" == "2" ]]; then
                print_info "Cleanup cancelled"
                exit 0
            else
                print_warning "Invalid choice. Please enter 1 or 2"
            fi
        done
        return
    fi
    
    echo "📋 Configured Stacks Available for Cleanup:"
    for i in "${!stack_volumes[@]}"; do
        local volume="${stack_volumes[$i]}"
        local env_file="$volume/config/.env"
        local stack_name=$(grep "^DOMAIN_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
        echo "   $((i+1)). $stack_name (at $volume)"
    done
    echo ""
    
    while true; do
        read -p "Select stack to cleanup (1-$stack_count): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le $stack_count ]]; then
            local selected_volume="${stack_volumes[$((selection-1))]}"
            cleanup_selected_stack "$selected_volume"
            break
        else
            print_warning "Please enter a number between 1 and $stack_count"
        fi
    done
}

# Cleanup selected stack
cleanup_selected_stack() {
    local selected_volume="$1"
    local env_file="$selected_volume/config/.env"
    
    if [[ ! -f "$env_file" ]]; then
        print_error "No stack configuration found at $selected_volume"
        exit 1
    fi
    
    # Load stack configuration
    source "$env_file"
    
    print_header "Cleaning Up Stack: ${DOMAIN_NAME}"
    
    echo "📊 Stack Information:"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Base Directory: $selected_volume"
    echo ""
    echo "🔍 What will be removed:"
    echo "   • All containers on network ${DOCKER_NETWORK}"
    echo "   • Docker network ${DOCKER_NETWORK}"
    echo "   • AppArmor profiles for ${DOCKER_NETWORK}"
    echo "   • Stack data and configuration at $selected_volume"
    echo ""
    
    read -p "Are you sure you want to cleanup this stack? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    # Set BASE_DIR for cleanup functions
    BASE_DIR="$selected_volume"
    
    # Execute cleanup phases
    stop_containers
    remove_containers
    remove_network
    remove_apparmor_profiles
    cleanup_docker_resources
    remove_stack_data
    show_summary
}

# Nuclear cleanup - remove all AI Platform data
nuclear_cleanup() {
    print_header "Nuclear Cleanup - All AI Platform Data"
    
    echo "⚠️  WARNING: This will remove ALL AI Platform data from this system!"
    echo "   • All AI Platform containers"
    echo "   • All AI Platform Docker networks"
    echo "   • All AI Platform AppArmor profiles"
    echo "   • All data in /mnt/data* directories"
    echo "   • Will unmount EBS volumes"
    echo ""
    
    read -p "Are you absolutely sure? Type 'NUCLEAR' to confirm: " confirm
    if [[ "$confirm" != "NUCLEAR" ]]; then
        print_info "Nuclear cleanup cancelled"
        exit 0
    fi
    
    print_info "Starting nuclear cleanup..."
    
    # STEP 1: Stop all AI Platform containers
    print_info "Step 1: Stopping all AI Platform containers..."
    local ai_containers=($(docker ps --format "{{.Names}}" | grep -E "(n8n|dify|postgres|redis|qdrant|prometheus|grafana|caddy|openclaw|tailscale|anythingllm|litellm|minio|flowise|openwebui|ollama)" || true))
    for container in "${ai_containers[@]}"; do
        print_info "Stopping $container..."
        docker stop "$container" 2>/dev/null || true
    done
    
    # STEP 2: Remove all AI Platform containers
    print_info "Step 2: Removing all AI Platform containers..."
    local all_ai_containers=($(docker ps -a --format "{{.Names}}" | grep -E "(n8n|dify|postgres|redis|qdrant|prometheus|grafana|caddy|openclaw|tailscale|anythingllm|litellm|minio|flowise|openwebui|ollama)" || true))
    for container in "${all_ai_containers[@]}"; do
        print_info "Removing $container..."
        docker rm "$container" 2>/dev/null || true
    done
    
    # STEP 3: Remove all AI Platform networks
    print_info "Step 3: Removing all AI Platform networks..."
    local ai_networks=($(docker network ls --format "{{.Name}}" | grep -E "(ai_platform|ai-platform)" || true))
    for network in "${ai_networks[@]}"; do
        print_info "Removing network $network..."
        docker network rm "$network" 2>/dev/null || true
    done
    
    # STEP 4: Remove all AI Platform AppArmor profiles
    print_info "Step 4: Removing all AI Platform AppArmor profiles..."
    local ai_profiles=($(ls /etc/apparmor.d/ 2>/dev/null | grep -E "(ai_platform|ai-platform)" || true))
    for profile in "${ai_profiles[@]}"; do
        print_info "Removing AppArmor profile $profile..."
        apparmor_parser -R "/etc/apparmor.d/$profile" 2>/dev/null || true
        rm -f "/etc/apparmor.d/$profile"
    done
    
    # STEP 5: Delete data on EBS volumes
    print_info "Step 5: Deleting all AI Platform data on EBS volumes..."
    for dir in /mnt/data*; do
        if [[ -d "$dir" ]]; then
            print_info "Deleting AI Platform data at $dir..."
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    # Also clean the main /mnt/data if it exists
    if [[ -d "/mnt/data" ]]; then
        print_info "Deleting AI Platform data at /mnt/data..."
        rm -rf "/mnt/data" 2>/dev/null || true
    fi
    
    # STEP 6: Unmount EBS volumes
    print_info "Step 6: Unmounting EBS volumes..."
    local mounted_volumes=($(findmnt -n -o TARGET | grep -E "(/mnt|/tmp)" | grep -v "^/$" | sed 's/^[├│└─]*//' || true))
    for volume in "${mounted_volumes[@]}"; do
        if [[ "$volume" != "/" ]] && [[ "$volume" != "/boot" ]] && [[ "$volume" != "/home" ]]; then
            print_info "Unmounting $volume..."
            umount "$volume" 2>/dev/null || true
        fi
    done
    
    # STEP 7: Final cleanup
    print_info "Step 7: Final system cleanup..."
    docker system prune -f 2>/dev/null || true
    
    print_success "Nuclear cleanup completed!"
    print_info "All AI Platform data removed, volumes unmounted, and system cleaned."
}

# Run main function
main "$@"
