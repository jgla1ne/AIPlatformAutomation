#!/bin/bash

#==============================================================================
# Script 0: Complete Platform Reset (Refactored)
# Purpose: Remove all containers, volumes, networks, and configurations
# WARNING: This will DELETE ALL DATA - Use with extreme caution!
# Version: 5.0.0 (Refactored)
#==============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Configuration
readonly DATA_ROOT="/mnt/data"
readonly COMPOSE_DIR="$DATA_ROOT/compose"

#------------------------------------------------------------------------------
# Output Structure (Per README)
#------------------------------------------------------------------------------
# ╔════════════════════════════════════════════════════════════╗
# ║           🚨 COMPLETE PLATFORM CLEANUP 🚨                  ║
# ╚════════════════════════════════════════════════════════════╝
# 
# [WARNING] This will:
#   • Stop all Docker containers
#   • Remove all Docker volumes
#   • Delete all AI platform networks
#   • Delete /mnt/data contents
#   • Reset all configurations
# 
# Type 'DELETE EVERYTHING' to proceed: _
#
# [1/6] 🛑 Stopping containers...
#   ✓ 8 containers stopped
# 
# [2/6] 🗑️  Removing containers...
#   ✓ 8 containers removed
# 
# [3/6] 💾 Cleaning volumes...
#   ✓ 12 volumes removed
# 
# [4/6] 🌐 Removing networks...
#   ✓ Network ai_platform removed
#   ✓ Network ai_platform_internal removed
#   ✓ Network ai_platform_monitoring removed
# 
# [5/6] 📝 Cleaning compose files...
#   ✓ 15 compose files removed
# 
# [6/6] 📁 Cleaning data directory...
#   ✓ /mnt/data cleaned (523GB freed)
# 
# ╔════════════════════════════════════════════════════════════╗
# ║              ✅ CLEANUP COMPLETE                           ║
# ╚════════════════════════════════════════════════════════════╝
# 
# Run ./scripts/1-setup-system-refactored.sh to start fresh
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║           🚨 COMPLETE PLATFORM CLEANUP 🚨                  ║"
    echo "║                      Version 5.0.0 (Refactored)              ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_warning_block() {
    echo ""
    echo -e "${YELLOW}[WARNING]${NC} This will:"
    echo "  • Stop all Docker containers"
    echo "  • Remove all Docker volumes"
    echo "  • Delete all AI platform networks"
    echo "  • Delete /mnt/data contents"
    echo "  • Reset all configurations"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local icon=$3
    local message=$4
    echo ""
    echo -e "${BLUE}[$step/$total] $icon $message${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

print_info() {
    echo -e "${CYAN}  ℹ️${NC} $1"
}

#------------------------------------------------------------------------------
# Cleanup Functions
#------------------------------------------------------------------------------

cleanup_containers() {
    print_step "1" "6" "🛑" "Stopping containers..."
    
    local container_count=0
    if docker ps -q | grep -q .; then
        container_count=$(docker ps -q | wc -l)
        print_info "Found $container_count running containers"
        docker stop $(docker ps -aq) 2>/dev/null || true
        sleep 2
    else
        print_info "No running containers found"
    fi
    print_success "$container_count containers stopped"
}

remove_containers() {
    print_step "2" "6" "🗑️ " "Removing containers..."
    
    local container_count=0
    if docker ps -aq | grep -q .; then
        container_count=$(docker ps -aq | wc -l)
        print_info "Found $container_count containers to remove"
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        sleep 2
    else
        print_info "No containers to remove"
    fi
    print_success "$container_count containers removed"
}

cleanup_volumes() {
    print_step "3" "6" "💾" "Cleaning volumes..."
    
    local volume_count=0
    if docker volume ls -q | grep -q .; then
        volume_count=$(docker volume ls -q | wc -l)
        print_info "Found $volume_count volumes to remove"
        docker volume rm $(docker volume ls -q) 2>/dev/null || true
        sleep 2
    else
        print_info "No volumes to remove"
    fi
    print_success "$volume_count volumes removed"
}

cleanup_networks() {
    print_step "4" "6" "🌐" "Removing networks..."
    
    # Define all AI platform networks
    local networks=("ai_platform" "ai_platform_internal" "ai_platform_monitoring")
    local removed_count=0
    
    for network in "${networks[@]}"; do
        if docker network ls -q --filter name="$network" | grep -q .; then
            print_info "Removing network: $network"
            docker network rm "$network" 2>/dev/null || true
            ((removed_count++))
        else
            print_info "Network not found: $network"
        fi
    done
    
    # Also remove any orphaned networks
    local orphaned_networks=$(docker network ls -q --filter "name=ai-platform" 2>/dev/null || true)
    if [[ -n "$orphaned_networks" ]]; then
        print_info "Removing orphaned ai-platform networks"
        echo "$orphaned_networks" | xargs -r docker network rm 2>/dev/null || true
        ((removed_count++))
    fi
    
    print_success "$removed_count AI platform networks removed"
}

cleanup_compose_files() {
    print_step "5" "6" "📝" "Cleaning compose files..."
    
    local compose_count=0
    
    if [[ -d "$COMPOSE_DIR" ]]; then
        # Count and remove compose files
        compose_count=$(find "$COMPOSE_DIR" -name "*.yml" -o -name "*.yaml" | wc -l)
        if [[ $compose_count -gt 0 ]]; then
            print_info "Found $compose_count compose files to remove"
            rm -rf "$COMPOSE_DIR"/* 2>/dev/null || true
        else
            print_info "No compose files found"
        fi
    else
        print_info "Compose directory not found"
    fi
    
    print_success "$compose_count compose files removed"
}

cleanup_data_directory() {
    print_step "6" "6" "📁" "Cleaning data directory..."
    
    # Get initial size
    local initial_size=$(du -sb "$DATA_ROOT" 2>/dev/null | awk '{print $1}' || echo "0")
    
    if mountpoint -q "$DATA_ROOT"; then
        print_info "Data directory is a mount point - cleaning contents only"
        
        # Kill processes using /mnt/data
        local processes=$(lsof +D "$DATA_ROOT" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
        if [[ -n "$processes" ]]; then
            print_info "Terminating processes using data directory"
            echo "$processes" | xargs -r kill -9 2>/dev/null || true
            sleep 2
        fi
        
        # Remove contents carefully
        cd "$DATA_ROOT"
        # Remove regular files and directories
        find . -maxdepth 1 -type f -delete 2>/dev/null || true
        find . -maxdepth 1 -type d ! -name "." -exec rm -rf {} + 2>/dev/null || true
        # Remove hidden files and directories except . and ..
        find . -maxdepth 1 -name ".*" ! -name "." ! -name ".." -exec rm -rf {} + 2>/dev/null || true
        cd - > /dev/null
    else
        print_info "Data directory is not a mount point - removing completely"
        rm -rf "$DATA_ROOT" 2>/dev/null || true
        mkdir -p "$DATA_ROOT" 2>/dev/null || true
    fi
    
    # Calculate freed space
    local freed_gb=$((initial_size / 1024 / 1024 / 1024))
    print_success "/mnt/data cleaned (${freed_gb}GB freed)"
}

docker_system_prune() {
    print_info "Running Docker system prune..."
    docker system prune -af --volumes 2>/dev/null || true
    print_success "Docker system prune completed"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

clear
print_header
print_warning_block

# Triple confirmation with enhanced warnings
echo -e "${YELLOW}Type 'DELETE EVERYTHING' to proceed:${NC} "
read -r confirm1
if [[ "$confirm1" != "DELETE EVERYTHING" ]]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Type 'I UNDERSTAND THIS IS PERMANENT':${NC} "
read -r confirm2
if [[ "$confirm2" != "I UNDERSTAND THIS IS PERMANENT" ]]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}${BOLD}Final confirmation - Type 'RESET NOW':${NC} "
read -r confirm3
if [[ "$confirm3" != "RESET NOW" ]]; then
    echo -e "${RED}Cleanup cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}${BOLD}Starting complete platform cleanup...${NC}"
echo ""

# Execute cleanup steps
cleanup_containers
remove_containers
cleanup_volumes
cleanup_networks
cleanup_compose_files
cleanup_data_directory

# Final Docker cleanup
docker_system_prune

# Final success message
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║              ✅ CLEANUP COMPLETE                           ║"
echo "║                      Version 5.0.0 (Refactored)              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Run ${BOLD}./scripts/1-setup-system-refactored.sh${NC} to start fresh"
echo ""

exit 0
