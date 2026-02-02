#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Complete Cleanup Script
# Version: 19.0 - PERMISSION FIX
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}[$1]${NC} $2"
}

show_banner() {
    clear
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║          AI PLATFORM - COMPLETE CLEANUP v19.0              ║
║                                                            ║
║  ⚠️  WARNING: This will remove ALL data and configs!      ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

EOF
}

confirm_cleanup() {
    echo -e "${RED}This operation will:${NC}"
    echo "  • Stop all running containers"
    echo "  • Remove all Docker containers and volumes"
    echo "  • Delete all data directories"
    echo "  • Remove all configuration files"
    echo "  • Delete Docker networks"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo ""
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DELETE EVERYTHING' to proceed: " final_confirm
    
    if [[ "$final_confirm" != "DELETE EVERYTHING" ]]; then
        echo ""
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_warning "Starting cleanup in 3 seconds..."
    sleep 3
}

stop_all_containers() {
    log_step "1/10" "Stopping all AI Platform containers"
    
    local containers=$(docker ps -a --filter "name=ai-" -q)
    if [[ -n "$containers" ]]; then
        log_info "Stopping containers..."
        docker stop $containers 2>/dev/null || true
        log_success "All containers stopped"
    else
        log_info "No containers to stop"
    fi
}

remove_all_containers() {
    log_step "2/10" "Removing all AI Platform containers"
    
    local containers=$(docker ps -a --filter "name=ai-" -q)
    if [[ -n "$containers" ]]; then
        log_info "Removing containers..."
        docker rm -f $containers 2>/dev/null || true
        log_success "All containers removed"
    else
        log_info "No containers to remove"
    fi
}

remove_docker_volumes() {
    log_step "3/10" "Removing Docker volumes"
    
    local volumes=$(docker volume ls --filter "name=ai-" -q)
    if [[ -n "$volumes" ]]; then
        log_info "Removing volumes..."
        docker volume rm -f $volumes 2>/dev/null || true
        log_success "All volumes removed"
    else
        log_info "No volumes to remove"
    fi
}

remove_docker_network() {
    log_step "4/10" "Removing Docker network"
    
    if docker network inspect ai-network &>/dev/null; then
        log_info "Removing ai-network..."
        docker network rm ai-network 2>/dev/null || true
        log_success "Network removed"
    else
        log_info "Network doesn't exist"
    fi
}

cleanup_docker_compose() {
    log_step "5/10" "Cleaning up Docker Compose stacks"
    
    if [[ -d "${PROJECT_ROOT}/stacks" ]]; then
        log_info "Running docker compose down on all stacks..."
        
        for stack_dir in "${PROJECT_ROOT}/stacks"/*; do
            if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
                stack_name=$(basename "$stack_dir")
                log_info "Cleaning up ${stack_name}..."
                (cd "$stack_dir" && docker compose down -v --remove-orphans 2>/dev/null) || true
            fi
        done
        
        log_success "All stacks cleaned"
    else
        log_info "No stacks directory found"
    fi
}

remove_project_files() {
    log_step "6/10" "Removing project files"
    
    # Remove stacks directory
    if [[ -d "${PROJECT_ROOT}/stacks" ]]; then
        log_info "Removing stacks directory..."
        rm -rf "${PROJECT_ROOT}/stacks"
        log_success "Stacks removed"
    fi
    
    # Remove .env file
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        log_info "Removing .env file..."
        rm -f "${PROJECT_ROOT}/.env"
        log_success ".env removed"
    fi
    
    # Remove backup .env files
    if ls "${PROJECT_ROOT}/.env.backup."* 1> /dev/null 2>&1; then
        log_info "Removing backup .env files..."
        rm -f "${PROJECT_ROOT}/.env.backup."*
        log_success "Backup files removed"
    fi
    
    # Remove logs directory
    if [[ -d "${PROJECT_ROOT}/logs" ]]; then
        log_info "Removing logs directory..."
        rm -rf "${PROJECT_ROOT}/logs"
        log_success "Logs removed"
    fi
    
    # Remove data directory with proper permissions
    if [[ -d "${PROJECT_ROOT}/data" ]]; then
        log_info "Removing data directory..."
        log_warning "This may require sudo for some directories..."
        
        # Try normal removal first
        if ! rm -rf "${PROJECT_ROOT}/data" 2>/dev/null; then
            # If failed, use sudo
            log_warning "Using sudo to remove protected directories..."
            sudo rm -rf "${PROJECT_ROOT}/data"
        fi
        
        log_success "Data directory removed"
    fi
}

remove_generated_docs() {
    log_step "7/10" "Removing generated documentation"
    
    local docs_to_remove=(
        "QUICK_START.md"
        "SERVICE_URLS.md"
        "CREDENTIALS.md"
    )
    
    for doc in "${docs_to_remove[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${doc}" ]]; then
            log_info "Removing ${doc}..."
            rm -f "${PROJECT_ROOT}/${doc}"
        fi
    done
    
    log_success "Generated docs removed"
}

cleanup_docker_images() {
    log_step "8/10" "Cleaning up Docker images (optional)"
    
    read -p "Remove all pulled Docker images? (y/N): " remove_images
    
    if [[ "$remove_images" =~ ^[Yy]$ ]]; then
        log_info "Removing dangling images..."
        docker image prune -f 2>/dev/null || true
        
        log_info "Listing AI Platform images..."
        docker images | grep -E "ollama|litellm|dify|n8n|weaviate|qdrant|milvus|flowise|anythingllm" || true
        
        read -p "Remove these images? (y/N): " confirm_images
        if [[ "$confirm_images" =~ ^[Yy]$ ]]; then
            docker images | grep -E "ollama|litellm|dify|n8n|weaviate|qdrant|milvus|flowise|anythingllm" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
            log_success "Images removed"
        fi
    else
        log_info "Skipping image removal"
    fi
}

verify_cleanup() {
    log_step "9/10" "Verifying cleanup"
    
    local issues=0
    
    # Check containers
    local remaining_containers=$(docker ps -a --filter "name=ai-" -q | wc -l)
    if [[ $remaining_containers -gt 0 ]]; then
        log_warning "Found ${remaining_containers} remaining container(s)"
        ((issues++))
    else
        log_success "No containers remaining"
    fi
    
    # Check volumes
    local remaining_volumes=$(docker volume ls --filter "name=ai-" -q | wc -l)
    if [[ $remaining_volumes -gt 0 ]]; then
        log_warning "Found ${remaining_volumes} remaining volume(s)"
        ((issues++))
    else
        log_success "No volumes remaining"
    fi
    
    # Check network
    if docker network inspect ai-network &>/dev/null; then
        log_warning "Network still exists"
        ((issues++))
    else
        log_success "Network removed"
    fi
    
    # Check directories
    if [[ -d "${PROJECT_ROOT}/data" ]]; then
        log_warning "Data directory still exists"
        ((issues++))
    else
        log_success "Data directory removed"
    fi
    
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        log_warning ".env file still exists"
        ((issues++))
    else
        log_success ".env file removed"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Cleanup completed with ${issues} issue(s)"
    fi
}

show_summary() {
    log_step "10/10" "Cleanup Summary"
    
    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ CLEANUP COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${CYAN}What was cleaned:${NC}
  ✓ All Docker containers stopped and removed
  ✓ All Docker volumes removed
  ✓ Docker network removed
  ✓ All data directories removed
  ✓ Configuration files removed
  ✓ Generated documentation removed

${CYAN}Next steps:${NC}
  • Run ./scripts/1-setup-system.sh to start fresh
  • Or manually reconfigure your setup

${YELLOW}Note:${NC} Docker images were preserved unless you chose to remove them.

EOF
}

main() {
    show_banner
    confirm_cleanup
    stop_all_containers
    remove_all_containers
    remove_docker_volumes
    remove_docker_network
    cleanup_docker_compose
    remove_project_files
    remove_generated_docs
    cleanup_docker_images
    verify_cleanup
    show_summary
}

main "$@"
