#!/bin/bash

#############################################
# Script 0: Complete System Cleanup
# Purpose: Remove all Docker resources and reset system state
# Usage: ./0-complete-cleanup.sh
#############################################

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

#############################################
# Configuration
#############################################

readonly CLEANUP_TIMEOUT=30
readonly FORCE_REMOVAL=true

#############################################
# Cleanup Functions
#############################################

cleanup_docker_containers() {
    log_info "Stopping and removing all Docker containers..."
    
    local containers
    containers=$(docker ps -aq 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        log_info "Found containers to remove"
        docker stop $containers 2>/dev/null || true
        docker rm -f $containers 2>/dev/null || true
        log_success "Containers removed"
    else
        log_info "No containers to remove"
    fi
}

cleanup_docker_networks() {
    log_info "Removing Docker networks..."
    
    local networks
    networks=$(docker network ls --filter "name=ai_platform" -q 2>/dev/null || true)
    
    if [[ -n "$networks" ]]; then
        log_info "Found networks to remove"
        docker network rm $networks 2>/dev/null || true
        log_success "Networks removed"
    else
        log_info "No custom networks to remove"
    fi
}

cleanup_docker_volumes() {
    log_info "Removing Docker volumes..."
    
    if confirm_action "Remove all Docker volumes? (This will delete all data)"; then
        local volumes
        volumes=$(docker volume ls -q 2>/dev/null || true)
        
        if [[ -n "$volumes" ]]; then
            log_info "Found volumes to remove"
            docker volume rm $volumes 2>/dev/null || true
            log_success "Volumes removed"
        else
            log_info "No volumes to remove"
        fi
    else
        log_warning "Skipping volume removal"
    fi
}

cleanup_docker_images() {
    log_info "Removing Docker images..."
    
    if confirm_action "Remove all Docker images?"; then
        local images
        images=$(docker images -q 2>/dev/null || true)
        
        if [[ -n "$images" ]]; then
            log_info "Found images to remove"
            docker rmi -f $images 2>/dev/null || true
            log_success "Images removed"
        else
            log_info "No images to remove"
        fi
    else
        log_warning "Skipping image removal"
    fi
}

cleanup_project_files() {
    log_info "Cleaning up project files..."
    
    local project_root="${SCRIPT_DIR}/.."
    
    # Remove generated configuration files
    if [[ -f "${project_root}/.env" ]]; then
        log_info "Removing .env file"
        rm -f "${project_root}/.env"
    fi
    
    # Remove log files
    if [[ -d "${project_root}/logs" ]]; then
        log_info "Removing log files"
        rm -rf "${project_root}/logs"
    fi
    
    # Remove temporary files
    find "${project_root}" -type f -name "*.tmp" -delete 2>/dev/null || true
    find "${project_root}" -type f -name "*.log" -delete 2>/dev/null || true
    
    log_success "Project files cleaned"
}

prune_docker_system() {
    log_info "Pruning Docker system..."
    
    docker system prune -af --volumes 2>/dev/null || true
    
    log_success "Docker system pruned"
}

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local containers
    local networks
    local volumes
    local images
    
    containers=$(docker ps -aq 2>/dev/null | wc -l)
    networks=$(docker network ls --filter "name=ai_platform" -q 2>/dev/null | wc -l)
    volumes=$(docker volume ls -q 2>/dev/null | wc -l)
    images=$(docker images -q 2>/dev/null | wc -l)
    
    log_info "Remaining resources:"
    log_info "  Containers: $containers"
    log_info "  Networks: $networks"
    log_info "  Volumes: $volumes"
    log_info "  Images: $images"
    
    if [[ $containers -eq 0 && $networks -eq 0 ]]; then
        log_success "Cleanup verified successfully"
        return 0
    else
        log_warning "Some resources may still remain"
        return 1
    fi
}

#############################################
# Main Execution
#############################################

main() {
    log_header "AI Platform - Complete Cleanup"
    
    # Verify Docker is available
    if ! check_docker; then
        log_error "Docker is not available"
        exit 1
    fi
    
    # Confirm cleanup
    log_warning "This will remove ALL Docker resources and project data!"
    if ! confirm_action "Continue with complete cleanup?"; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    # Execute cleanup steps
    cleanup_docker_containers
    cleanup_docker_networks
    cleanup_docker_volumes
    cleanup_docker_images
    cleanup_project_files
    prune_docker_system
    
    # Verify cleanup
    verify_cleanup
    
    log_success "Complete cleanup finished"
    log_info "System is ready for fresh installation"
}

# Execute main function
main "$@"

