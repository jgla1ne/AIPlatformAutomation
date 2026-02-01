#!/bin/bash

# ============================================================================
# AI Platform - Complete Cleanup Script v3.2
# Removes all containers, networks, volumes, and data
# ============================================================================

readonly SCRIPT_VERSION="3.2"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Icons
CHECK_MARK="✓"
CROSS_MARK="✗"
WARN_MARK="⚠"
INFO_MARK="ℹ"

log() {
    echo "[$(date +'%Y-%m-%d %H:%:%S')] $*"
}

success() {
    echo -e "${GREEN}${CHECK_MARK} $*${NC}"
}

error() {
    echo -e "${RED}${CROSS_MARK} $*${NC}"
}

warn() {
    echo -e "${YELLOW}${WARN_MARK} $*${NC}"
}

info() {
    echo -e "${BLUE}${INFO_MARK} $*${NC}"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

confirm_cleanup() {
    echo ""
    echo "========================================"
    echo "AI Platform - Complete Cleanup v${SCRIPT_VERSION}"
    echo "========================================"
    echo ""
    warn "This will remove:"
    echo "  • All AI Platform Docker containers"
    echo "  • All AI Platform Docker networks"
    echo "  • All AI Platform Docker volumes"
    echo "  • All data in ~/AIPlatformAutomation/data/"
    echo ""
    
    read -p "Are you sure? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
}

stop_containers() {
    info "[1/6] Stopping all AI Platform containers..."
    
    # Get list of all containers (running or stopped) matching our patterns
    local containers
    containers=$(docker ps -aq --filter "name=caddy" \
                            --filter "name=litellm" \
                            --filter "name=ollama" \
                            --filter "name=dify" \
                            --filter "name=n8n" \
                            --filter "name=signal" 2>/dev/null || echo "")
    
    if [[ -z "$containers" ]]; then
        success "No containers to stop"
        return 0
    fi
    
    # Stop and remove all at once
    echo "$containers" | xargs -r docker stop 2>/dev/null || true
    echo "$containers" | xargs -r docker rm 2>/dev/null || true
    
    local count
    count=$(echo "$containers" | wc -w)
    success "Stopped and removed $count containers"
}

remove_networks() {
    info "[2/6] Removing Docker networks..."
    
    local networks
    networks=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E '(ai-platform|dify)' || echo "")
    
    if [[ -z "$networks" ]]; then
        success "No networks to remove"
        return 0
    fi
    
    local removed=0
    for network in $networks; do
        docker network rm "$network" 2>/dev/null && ((removed++)) || true
    done
    
    success "Removed $removed networks"
}

remove_volumes() {
    info "[3/6] Removing Docker volumes..."
    
    # Get volumes with our prefixes
    local volumes
    volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null | \
              grep -E '(ai-platform|dify|litellm|ollama|n8n|signal|caddy)' || echo "")
    
    if [[ -z "$volumes" ]]; then
        success "No volumes to remove"
        return 0
    fi
    
    local removed=0
    for volume in $volumes; do
        docker volume rm "$volume" 2>/dev/null && ((removed++)) || true
    done
    
    success "Removed $removed volumes"
}

remove_data_directory() {
    info "[4/6] Removing data directory..."
    
    local data_dir="${HOME}/AIPlatformAutomation/data"
    
    if [[ ! -d "$data_dir" ]]; then
        success "Data directory does not exist"
        return 0
    fi
    
    # Check if anything is mounted from data directory
    if mount | grep -q "$data_dir"; then
        warn "Found mounted filesystems, unmounting..."
        mount | grep "$data_dir" | awk '{print $3}' | xargs -r sudo umount -f 2>/dev/null || true
    fi
    
    # Remove directory
    rm -rf "$data_dir" 2>/dev/null || sudo rm -rf "$data_dir"
    success "Data directory removed"
}

remove_compose_files() {
    info "[5/6] Removing compose files..."
    
    local stacks_dir="${HOME}/AIPlatformAutomation/stacks"
    
    if [[ ! -d "$stacks_dir" ]]; then
        success "Stacks directory does not exist"
        return 0
    fi
    
    rm -rf "$stacks_dir"
    success "Compose files removed"
}

prune_docker() {
    info "[6/6] Pruning Docker system..."
    
    # Prune unused images
    docker image prune -af 2>/dev/null || true
    
    # Prune orphaned volumes
    docker volume prune -f 2>/dev/null || true
    
    # Prune unused networks
    docker network prune -f 2>/dev/null || true
    
    success "Docker system pruned"
}

verify_cleanup() {
    echo ""
    info "Verifying cleanup..."
    
    # Check for remaining containers
    local remaining_containers
    remaining_containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | \
                          grep -E '(caddy|litellm|ollama|dify|n8n|signal)' || echo "")
    
    if [[ -n "$remaining_containers" ]]; then
        warn "Some containers still exist:"
        echo "$remaining_containers"
    else
        success "All containers removed"
    fi
    
    # Check for remaining networks
    local remaining_networks
    remaining_networks=$(docker network ls --format '{{.Name}}' 2>/dev/null | \
                        grep -E '(ai-platform|dify)' || echo "")
    
    if [[ -n "$remaining_networks" ]]; then
        warn "Some networks still exist:"
        echo "$remaining_networks"
    else
        success "All networks removed"
    fi
    
    # Check data directory
    if [[ -d "${HOME}/AIPlatformAutomation/data" ]]; then
        warn "Data directory still exists"
    else
        success "Data directory removed"
    fi
    
    # Check stacks directory
    if [[ -d "${HOME}/AIPlatformAutomation/stacks" ]]; then
        warn "Stacks directory still exists"
    else
        success "Stacks directory removed"
    fi
}

display_summary() {
    echo ""
    echo "========================================"
    echo "Cleanup Complete"
    echo "========================================"
    echo ""
    success "All AI Platform components removed"
    echo ""
    info "To redeploy, run:"
    echo "  cd ~/AIPlatformAutomation/scripts"
    echo "  ./1-setup-system.sh"
    echo "  ./2-deploy-services.sh"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    confirm_cleanup
    
    stop_containers
    remove_networks
    remove_volumes
    remove_data_directory
    remove_compose_files
    prune_docker
    
    verify_cleanup
    display_summary
}

main "$@"
