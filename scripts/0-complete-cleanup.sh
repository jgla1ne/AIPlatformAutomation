#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - Complete Cleanup Script v9.0
# Nuclear option: removes everything and returns to fresh state
# ============================================================================

readonly SCRIPT_VERSION="9.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_ROOT}/logs/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗ $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ $*${NC}" | tee -a "$LOG_FILE"; }

# ============================================================================
# Setup logging
# ============================================================================

setup_logging() {
    mkdir -p "${PROJECT_ROOT}/logs"
    echo "Cleanup started at $(date)" > "$LOG_FILE"
}

# ============================================================================
# Display Warning Banner
# ============================================================================

display_warning() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    ⚠  WARNING  ⚠                           ║"
    echo "║          COMPLETE PLATFORM CLEANUP v${SCRIPT_VERSION}                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    warn "This will PERMANENTLY DELETE:"
    echo "  • All Docker containers and images"
    echo "  • All data volumes and databases"
    echo "  • All configuration files"
    echo "  • All logs"
    echo "  • Docker networks"
    echo ""
    warn "This action CANNOT be undone!"
    echo ""
    read -p "Type 'YES' to confirm complete cleanup: " -r
    
    if [[ $REPLY != "YES" ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    info "Starting cleanup in 5 seconds... (Ctrl+C to abort)"
    sleep 5
}

# ============================================================================
# Stop and Remove All Containers
# ============================================================================

cleanup_containers() {
    info "[1/8] Stopping and removing all containers..."
    
    local containers=(
        "nginx"
        "gdrive-sync"
        "signal-api"
        "n8n"
        "dify-web"
        "dify-worker"
        "dify-api"
        "dify-weaviate"
        "dify-redis"
        "dify-db"
        "clawdbot"
        "anythingllm"
        "litellm"
        "ollama"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            info "Stopping and removing: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Remove any remaining containers on ai-platform network
    if docker network inspect ai-platform &>/dev/null; then
        local network_containers
        network_containers=$(docker network inspect ai-platform -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
        
        if [[ -n "$network_containers" ]]; then
            info "Removing remaining containers on ai-platform network..."
            for container in $network_containers; do
                docker stop "$container" 2>/dev/null || true
                docker rm -f "$container" 2>/dev/null || true
            done
        fi
    fi
    
    success "All containers removed"
}

# ============================================================================
# Remove Docker Compose Stacks
# ============================================================================

cleanup_stacks() {
    info "[2/8] Removing Docker Compose stacks..."
    
    local stacks=(
        "${PROJECT_ROOT}/stacks/nginx"
        "${PROJECT_ROOT}/stacks/gdrive"
        "${PROJECT_ROOT}/stacks/signal"
        "${PROJECT_ROOT}/stacks/n8n"
        "${PROJECT_ROOT}/stacks/dify"
        "${PROJECT_ROOT}/stacks/clawdbot"
        "${PROJECT_ROOT}/stacks/anythingllm"
        "${PROJECT_ROOT}/stacks/litellm"
        "${PROJECT_ROOT}/stacks/ollama"
    )
    
    for stack in "${stacks[@]}"; do
        if [[ -f "${stack}/docker-compose.yml" ]]; then
            info "Removing stack: $(basename "$stack")"
            cd "$stack" && docker compose down -v 2>/dev/null || true
        fi
    done
    
    success "Docker Compose stacks removed"
}

# ============================================================================
# Remove Docker Networks
# ============================================================================

cleanup_networks() {
    info "[3/8] Removing Docker networks..."
    
    if docker network ls --format '{{.Name}}' | grep -q "^ai-platform$"; then
        docker network rm ai-platform 2>/dev/null || true
        success "Docker network removed"
    else
        info "No Docker networks to remove"
    fi
}

# ============================================================================
# Remove Docker Images
# ============================================================================

cleanup_images() {
    info "[4/8] Removing Docker images..."
    
    local images=(
        "nginx:alpine"
        "controlol/gdrive-rclone-docker:latest"
        "bbernhard/signal-cli-rest-api:latest"
        "n8nio/n8n:latest"
        "langgenius/dify-web:latest"
        "langgenius/dify-api:latest"
        "semitechnologies/weaviate:latest"
        "redis:7-alpine"
        "postgres:15-alpine"
        "mintplexlabs/anythingllm:latest"
        "ghcr.io/berriai/litellm:main-latest"
        "ollama/ollama:latest"
    )
    
    for image in "${images[@]}"; do
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
            info "Removing image: $image"
            docker rmi -f "$image" 2>/dev/null || true
        fi
    done
    
    # Remove dangling images
    info "Removing dangling images..."
    docker image prune -f &>/dev/null || true
    
    success "Docker images removed"
}

# ============================================================================
# Remove Data Volumes
# ============================================================================

cleanup_data() {
    info "[5/8] Removing data volumes..."
    
    if [[ -d "${PROJECT_ROOT}/data" ]]; then
        warn "Removing all data in ${PROJECT_ROOT}/data"
        
        # Stop any processes that might be using the files
        sudo fuser -k "${PROJECT_ROOT}/data" 2>/dev/null || true
        
        # Remove data directory
        sudo rm -rf "${PROJECT_ROOT}/data"
        success "Data volumes removed"
    else
        info "No data volumes to remove"
    fi
}

# ============================================================================
# Remove Stack Configurations
# ============================================================================

cleanup_configs() {
    info "[6/8] Removing stack configurations..."
    
    if [[ -d "${PROJECT_ROOT}/stacks" ]]; then
        rm -rf "${PROJECT_ROOT}/stacks"
        success "Stack configurations removed"
    else
        info "No stack configurations to remove"
    fi
}

# ============================================================================
# Remove Environment File
# ============================================================================

cleanup_env() {
    info "[7/8] Removing environment configuration..."
    
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        # Backup before removing
        cp "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/.env.backup.$(date +%s)" 2>/dev/null || true
        rm -f "${PROJECT_ROOT}/.env"
        success "Environment file removed (backup created)"
    else
        info "No environment file to remove"
    fi
}

# ============================================================================
# Clean Docker System
# ============================================================================

cleanup_docker_system() {
    info "[8/8] Cleaning Docker system..."
    
    # Remove unused volumes
    docker volume prune -f &>/dev/null || true
    
    # Remove unused networks
    docker network prune -f &>/dev/null || true
    
    # Remove build cache
    docker builder prune -f &>/dev/null || true
    
    success "Docker system cleaned"
}

# ============================================================================
# Display Summary
# ============================================================================

display_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            CLEANUP COMPLETED SUCCESSFULLY!                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "System returned to fresh state"
    echo ""
    
    info "Cleanup log saved to: $LOG_FILE"
    echo ""
    
    info "What was removed:"
    echo "  ✓ All Docker containers"
    echo "  ✓ All Docker images"
    echo "  ✓ All Docker networks"
    echo "  ✓ All data volumes"
    echo "  ✓ All stack configurations"
    echo "  ✓ Environment configuration"
    echo ""
    
    info "What was preserved:"
    echo "  • Scripts directory"
    echo "  • Log files"
    echo "  • Environment backup (.env.backup.*)"
    echo ""
    
    info "Next steps:"
    echo "  1. Run: ./1-system-setup.sh"
    echo "  2. Run: ./2-deploy-services.sh"
    echo "  3. Run: ./3-configure-services.sh"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    setup_logging
    display_warning
    
    cleanup_containers
    cleanup_stacks
    cleanup_networks
    cleanup_images
    cleanup_data
    cleanup_configs
    cleanup_env
    cleanup_docker_system
    
    display_summary
}

main "$@"

