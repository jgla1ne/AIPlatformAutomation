#!/bin/bash

#==============================================================================
# Script 0: Complete Platform Reset
# Purpose: Remove all containers, volumes, networks, and configurations
# WARNING: This will DELETE ALL DATA - Use with extreme caution!
#==============================================================================

set -euo pipefail

# Color definitions (matching script 1)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (matching script 1)
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/cleanup.log"

# UI Functions (matching script 1)
print_banner() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║            🚨 COMPLETE PLATFORM CLEANUP 🚨                      ║"
    echo "║                      Version 4.0.0                               ║"
    echo "║                Full System Reset Script                           ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete:${NC}"
    echo ""
    echo "  🐳 All Docker containers and images"
    echo "  💾 All Docker volumes and data"
    echo "  🌐 All Docker networks"
    echo "  📁 All data in $DATA_ROOT"
    echo "  ⚙️  All configuration files"
    echo "  🔄 All setup state and metadata"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local total="$2"
    local icon="$3"
    local message="$4"
    echo -e "${BLUE}🔍 STEP $step/$total: $icon $message${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  ⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}  ❌ $1${NC}"
}

confirm() {
    local message="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n -e "${YELLOW}$message [Y/n]:${NC} "
        else
            echo -n -e "${YELLOW}$message [y/N]:${NC} "
        fi
        
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please enter y or n" ;;
        esac
    done
}

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

cleanup_state() {
    print_step "1" "7" "🔄" "Cleaning setup state..."
    
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        print_success "Setup state file removed"
    else
        print_warn "No setup state file found"
    fi
    
    # Remove any script 1 temporary files
    rm -f "$DATA_ROOT/.setup_in_progress" 2>/dev/null || true
    rm -f "$DATA_ROOT/.selected_services" 2>/dev/null || true
}

stop_services() {
    print_step "2" "7" "🛑" "Stopping all services..."
    
    local container_count=0
    if docker ps -q | grep -q . 2>/dev/null; then
        container_count=$(docker ps -q | wc -l)
        
        # Graceful shutdown first
        docker stop $(docker ps -q) 2>/dev/null || true
        sleep 5
        
        # Force kill any remaining
        docker kill $(docker ps -q) 2>/dev/null || true
        print_success "$container_count containers stopped"
    else
        print_success "No running containers found"
    fi
}

remove_containers() {
    print_step "3" "7" "🗑️ " "Removing all containers..."
    
    local container_count=0
    if docker ps -aq | grep -q . 2>/dev/null; then
        container_count=$(docker ps -aq | wc -l)
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        print_success "$container_count containers removed"
    else
        print_success "No containers found"
    fi
}

clean_volumes() {
    print_step "4" "7" "💾" "Cleaning Docker volumes..."
    
    local volume_count=0
    if docker volume ls -q | grep -q . 2>/dev/null; then
        volume_count=$(docker volume ls -q | wc -l)
        docker volume rm -f $(docker volume ls -q) 2>/dev/null || true
        print_success "$volume_count volumes removed"
    else
        print_success "No volumes found"
    fi
}

clean_networks() {
    print_step "5" "7" "🌐" "Cleaning Docker networks..."
    
    # Remove AI platform networks
    local networks=("ai-platform" "ai-platform-internal" "ai-platform-monitoring" "homelab")
    local removed_count=0
    
    for network in "${networks[@]}"; do
        if docker network ls -q --filter name="$network" | grep -q . 2>/dev/null; then
            docker network rm "$network" 2>/dev/null || true
            ((removed_count++))
        fi
    done
    
    # Remove all custom networks
    local all_networks=$(docker network ls -q --filter driver=bridge 2>/dev/null || echo "")
    if [[ -n "$all_networks" ]]; then
        for network in $all_networks; do
            docker network rm "$network" 2>/dev/null || true
            ((removed_count++))
        done
    fi
    
    print_success "$removed_count networks removed"
}

clean_images() {
    print_step "6" "7" "🖼️ " "Cleaning Docker images..."
    
    local image_count=0
    if docker images -q | grep -q . 2>/dev/null; then
        image_count=$(docker images -q | wc -l)
        docker rmi -f $(docker images -q) 2>/dev/null || true
        print_success "$image_count images removed"
    else
        print_success "No images found"
    fi
}

clean_data_directory() {
    print_step "7" "7" "📁" "Cleaning data directory..."
    
    # Get initial size
    local initial_size=0
    if [[ -d "$DATA_ROOT" ]]; then
        initial_size=$(du -sb "$DATA_ROOT" 2>/dev/null | awk '{print $1}' || echo "0")
    fi
    
    # Kill processes using the directory
    if [[ -d "$DATA_ROOT" ]]; then
        lsof +D "$DATA_ROOT" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
        sleep 2
    fi
    
    # Remove contents (preserve mount point)
    if mountpoint -q "$DATA_ROOT" 2>/dev/null; then
        cd "$DATA_ROOT"
        rm -rf ./* 2>/dev/null || true
        rm -rf ./.[!.]* 2>/dev/null || true
        cd - > /dev/null
    else
        rm -rf "$DATA_ROOT" 2>/dev/null || true
    fi
    
    # Calculate freed space
    local freed_gb=$((initial_size / 1024 / 1024 / 1024))
    print_success "Data directory cleaned (${freed_gb}GB freed)"
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
#───────────────────────────────────────────────────────────────────────────────

main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Setup logging
    setup_logging
    
    # Display banner
    print_banner
    
    # Check if setup is in progress
    if [[ -f "$DATA_ROOT/.setup_in_progress" ]]; then
        print_warn "Setup script appears to be in progress"
        if ! confirm "Continue with cleanup anyway?"; then
            echo "Cleanup cancelled."
            exit 0
        fi
    fi
    
    # Multiple confirmations for safety
    echo ""
    if ! confirm "Do you understand this will delete ALL data?"; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    echo ""
    if ! confirm "This includes databases, configurations, and all user data - continue?"; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    echo ""
    echo -e "${RED}${BOLD}FINAL WARNING: Type 'DELETE EVERYTHING' to proceed:${NC} "
    read -r confirm_text
    if [[ "$confirm_text" != "DELETE EVERYTHING" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    echo ""
    print_header "🧹 PERFORMING COMPLETE CLEANUP"
    
    # Execute cleanup steps
    cleanup_state
    stop_services
    remove_containers
    clean_volumes
    clean_networks
    clean_images
    clean_data_directory
    
    # Final Docker cleanup
    echo ""
    print_header "🧹 FINAL DOCKER CLEANUP"
    docker system prune -af --volumes 2>/dev/null || true
    print_success "Docker system cleanup completed"
    
    # Success message
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ CLEANUP COMPLETE                           ║"
    echo "║              System is ready for fresh install                   ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Run: ${BOLD}sudo bash scripts/1-setup-system.sh${NC}"
    echo "  2. Follow the interactive setup wizard"
    echo "  3. Then run: ${BOLD}sudo bash scripts/2-deploy-services.sh${NC}"
    echo ""
    echo -e "${YELLOW}Cleanup log saved to: $LOG_FILE${NC}"
    echo ""
    
    exit 0
}

# Execute main function
main "$@"
