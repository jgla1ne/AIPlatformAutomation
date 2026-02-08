#!/bin/bash
################################################################################
# SCRIPT 0: NUCLEAR CLEANUP & RESET
# Version: v101.0.0
# Purpose: Complete system reset - removes ALL traces of AI Platform
# 
# This script performs a COMPLETE cleanup:
# - Stops and removes all Docker containers, networks, volumes
# - Removes all configuration files and data directories
# - Cleans up Docker images (optional)
# - Removes installed dependencies (optional)
# - Resets system to pre-installation state
#
# WARNING: THIS IS DESTRUCTIVE AND IRREVERSIBLE!
#
# Reference: AI PLATFORM DEPLOYMENT v75.2.0
# Compatible with: Script 1 v101.0.0
################################################################################

set -euo pipefail

################################################################################
# SCRIPT METADATA
################################################################################

readonly SCRIPT_VERSION="v101.0.0"
readonly SCRIPT_NAME="Nuclear Cleanup & Reset"
readonly TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
readonly LOG_FILE="/var/log/ai-platform-cleanup-${TIMESTAMP}.log"

################################################################################
# COLOR CODES
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    local message="$1"
    echo -e "${BLUE}ℹ${NC} ${message}" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} ${message}" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠${NC} ${message}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}✗${NC} ${message}" | tee -a "$LOG_FILE"
}

log_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  STEP ${step}/${total}: ${message}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

################################################################################
# BANNER
################################################################################

show_banner() {
    clear
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}║              ${BOLD}⚠  NUCLEAR CLEANUP WARNING  ⚠${NC}${RED}               ║${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}║         This will COMPLETELY REMOVE all traces of:           ║${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}║  • All Docker containers, networks, and volumes              ║${NC}"
    echo -e "${RED}║  • All AI Platform configuration files                       ║${NC}"
    echo -e "${RED}║  • All data directories and databases                        ║${NC}"
    echo -e "${RED}║  • All downloaded models and embeddings                      ║${NC}"
    echo -e "${RED}║  • All logs and temporary files                              ║${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}║            ${BOLD}THIS ACTION IS IRREVERSIBLE!${NC}${RED}                  ║${NC}"
    echo -e "${RED}║                                                               ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Script Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}Log File: ${LOG_FILE}${NC}"
    echo ""
}

################################################################################
# CONFIRMATION PROMPTS
################################################################################

confirm_cleanup() {
    echo -e "${YELLOW}${BOLD}FINAL WARNING:${NC} You are about to perform a complete system cleanup."
    echo ""
    echo "This will remove:"
    echo "  • /opt/ai-platform/ (if exists)"
    echo "  • Docker containers with label: ai-platform"
    echo "  • Docker networks: ai-platform-network"
    echo "  • Docker volumes starting with: aiplatform-*"
    echo ""
    
    read -p "Type 'DELETE EVERYTHING' to confirm (case-sensitive): " confirmation
    
    if [[ "$confirmation" != "DELETE EVERYTHING" ]]; then
        log_error "Confirmation failed. Cleanup aborted."
        echo ""
        echo -e "${GREEN}No changes were made to your system.${NC}"
        exit 0
    fi
    
    echo ""
    log_warning "Confirmation received. Beginning cleanup in 5 seconds..."
    log_warning "Press Ctrl+C NOW to abort!"
    echo ""
    
    for i in {5..1}; do
        echo -ne "${RED}${BOLD}Cleanup starting in ${i}...${NC}\r"
        sleep 1
    done
    
    echo ""
    echo ""
}

################################################################################
# DOCKER CLEANUP FUNCTIONS
################################################################################

stop_all_containers() {
    log_step "1" "10" "STOPPING ALL AI PLATFORM CONTAINERS"
    
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_info "No AI Platform containers found"
        return 0
    fi
    
    local container_count=$(echo "$containers" | wc -l)
    log_info "Found ${container_count} container(s) to stop"
    
    echo "$containers" | while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.\///' || echo "unknown")
            log_info "Stopping container: ${name} (${container_id:0:12})"
            docker stop "$container_id" 2>/dev/null || log_warning "Failed to stop ${container_id:0:12}"
        fi
    done
    
    log_success "All containers stopped"
}

remove_all_containers() {
    log_step "2" "10" "REMOVING ALL AI PLATFORM CONTAINERS"
    
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_info "No AI Platform containers to remove"
        return 0
    fi
    
    echo "$containers" | while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.\///' || echo "unknown")
            log_info "Removing container: ${name} (${container_id:0:12})"
            docker rm -f "$container_id" 2>/dev/null || log_warning "Failed to remove ${container_id:0:12}"
        fi
    done
    
    log_success "All containers removed"
}

remove_docker_networks() {
    log_step "3" "10" "REMOVING AI PLATFORM NETWORKS"
    
    local networks=("ai-platform-network" "aiplatform-network" "ai_platform_network")
    
    for network in "${networks[@]}"; do
        if docker network ls --format "{{.Name}}" | grep -q "^${network}$"; then
            log_info "Removing network: ${network}"
            docker network rm "$network" 2>/dev/null || log_warning "Failed to remove network: ${network}"
        fi
    done
    
    log_success "Networks removed"
}

remove_docker_volumes() {
    log_step "4" "10" "REMOVING AI PLATFORM VOLUMES"
    
    local volumes=$(docker volume ls --format "{{.Name}}" | grep -E "^aiplatform-|^ai-platform-|^ai_platform_" || true)
    
    if [[ -z "$volumes" ]]; then
        log_info "No AI Platform volumes found"
        return 0
    fi
    
    local volume_count=$(echo "$volumes" | wc -l)
    log_info "Found ${volume_count} volume(s) to remove"
    
    echo "$volumes" | while read -r volume; do
        if [[ -n "$volume" ]]; then
            log_info "Removing volume: ${volume}"
            docker volume rm "$volume" 2>/dev/null || log_warning "Failed to remove volume: ${volume}"
        fi
    done
    
    log_success "All volumes removed"
}

cleanup_docker_images() {
    log_step "5" "10" "CLEANING UP DOCKER IMAGES (OPTIONAL)"
    
    echo ""
    echo -e "${YELLOW}Docker images can consume significant disk space.${NC}"
    echo "Options:"
    echo "  1) Keep all images (default)"
    echo "  2) Remove AI Platform images only"
    echo "  3) Remove all unused images (prune)"
    echo "  4) Remove ALL images (nuclear)"
    echo ""
    
    read -p "Select option [1-4]: " image_option
    image_option=${image_option:-1}
    
    case $image_option in
        1)
            log_info "Keeping all Docker images"
            ;;
        2)
            log_info "Removing AI Platform specific images..."
            local images=(
                "ollama/ollama"
                "open-webui/open-webui"
                "ghcr.io/berriai/litellm"
                "langfuse/langfuse"
                "postgres"
                "redis"
                "qdrant/qdrant"
                "semitechnologies/weaviate"
                "chromadb/chroma"
                "milvusdb/milvus"
                "langgenius/dify-api"
                "langgenius/dify-web"
                "n8nio/n8n"
                "prometheus/prometheus"
                "grafana/grafana"
                "grafana/loki"
                "minio/minio"
                "portainer/portainer-ce"
                "caddy"
                "nginx"
            )
            
            for image in "${images[@]}"; do
                if docker images --format "{{.Repository}}" | grep -q "^${image}$"; then
                    log_info "Removing image: ${image}"
                    docker rmi -f $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${image}") 2>/dev/null || true
                fi
            done
            log_success "AI Platform images removed"
            ;;
        3)
            log_info "Pruning unused Docker images..."
            docker image prune -a -f
            log_success "Unused images pruned"
            ;;
        4)
            log_warning "Removing ALL Docker images..."
            read -p "Are you SURE? This removes all images on the system [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                docker rmi -f $(docker images -q) 2>/dev/null || true
                log_success "All images removed"
            else
                log_info "Skipped removing all images"
            fi
            ;;
        *)
            log_warning "Invalid option. Keeping all images."
            ;;
    esac
}

################################################################################
# FILESYSTEM CLEANUP FUNCTIONS
################################################################################

remove_data_directories() {
    log_step "6" "10" "REMOVING DATA DIRECTORIES"
    
    local base_dir="/opt/ai-platform"
    
    if [[ ! -d "$base_dir" ]]; then
        log_info "Data directory does not exist: ${base_dir}"
        return 0
    fi
    
    log_info "Data directory found: ${base_dir}"
    
    # Show directory size
    local dir_size=$(du -sh "$base_dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Directory size: ${dir_size}"
    
    # List subdirectories
    log_info "Contents:"
    find "$base_dir" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | sed 's/^/  /' || true
    
    echo ""
    read -p "Remove ${base_dir} and ALL contents? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_warning "Removing ${base_dir}..."
        rm -rf "$base_dir"
        log_success "Data directory removed"
    else
        log_info "Skipped removing data directory"
    fi
}

remove_configuration_files() {
    log_step "7" "10" "REMOVING CONFIGURATION FILES"
    
    local config_locations=(
        "/etc/ai-platform"
        "/etc/systemd/system/ai-platform-*.service"
        "/etc/docker/daemon.json.ai-platform-backup"
        "$HOME/.ai-platform"
    )
    
    for location in "${config_locations[@]}"; do
        if [[ -e "$location" ]] || compgen -G "$location" > /dev/null 2>&1; then
            log_info "Removing: ${location}"
            rm -rf $location 2>/dev/null || log_warning "Failed to remove: ${location}"
        fi
    done
    
    log_success "Configuration files removed"
}

remove_log_files() {
    log_step "8" "10" "REMOVING LOG FILES"
    
    local log_patterns=(
        "/var/log/ai-platform*.log"
        "/var/log/ollama*.log"
        "/var/log/litellm*.log"
        "/var/log/docker-compose-ai-platform*.log"
    )
    
    log_info "Searching for log files..."
    
    local found_logs=false
    for pattern in "${log_patterns[@]}"; do
        if compgen -G "$pattern" > /dev/null 2>&1; then
            found_logs=true
            for log in $pattern; do
                log_info "Removing: ${log}"
                rm -f "$log" 2>/dev/null || log_warning "Failed to remove: ${log}"
            done
        fi
    done
    
    if [[ "$found_logs" == false ]]; then
        log_info "No AI Platform log files found"
    else
        log_success "Log files removed"
    fi
}

cleanup_dependencies() {
    log_step "9" "10" "CLEANING UP DEPENDENCIES (OPTIONAL)"
    
    echo ""
    echo -e "${YELLOW}Remove packages installed by Script 1?${NC}"
    echo "This includes: curl, git, jq, wget, net-tools, dnsutils, etc."
    echo ""
    read -p "Remove dependencies? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Keeping installed dependencies"
        return 0
    fi
    
    log_info "Removing dependencies..."
    
    local packages=(
        "curl"
        "git"
        "jq"
        "wget"
        "net-tools"
        "dnsutils"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )
    
    # Detect OS
    if command -v apt-get &>/dev/null; then
        log_info "Removing packages (apt)..."
        apt-get remove -y "${packages[@]}" 2>/dev/null || true
        apt-get autoremove -y
    elif command -v yum &>/dev/null; then
        log_info "Removing packages (yum)..."
        yum remove -y "${packages[@]}" 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        log_info "Removing packages (dnf)..."
        dnf remove -y "${packages[@]}" 2>/dev/null || true
    elif command -v pacman &>/dev/null; then
        log_info "Removing packages (pacman)..."
        pacman -Rs --noconfirm "${packages[@]}" 2>/dev/null || true
    fi
    
    log_success "Dependencies removed"
}

################################################################################
# VERIFICATION & SUMMARY
################################################################################

verify_cleanup() {
    log_step "10" "10" "VERIFYING CLEANUP"
    
    local issues_found=false
    
    # Check Docker containers
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        log_warning "Some containers still exist"
        issues_found=true
    else
        log_success "No AI Platform containers found"
    fi
    
    # Check Docker networks
    if docker network ls --format "{{.Name}}" | grep -qE "ai-platform|aiplatform"; then
        log_warning "Some networks still exist"
        issues_found=true
    else
        log_success "No AI Platform networks found"
    fi
    
    # Check Docker volumes
    local volumes=$(docker volume ls --format "{{.Name}}" | grep -E "^aiplatform-|^ai-platform-" || true)
    if [[ -n "$volumes" ]]; then
        log_warning "Some volumes still exist"
        issues_found=true
    else
        log_success "No AI Platform volumes found"
    fi
    
    # Check data directory
    if [[ -d "/opt/ai-platform" ]]; then
        log_warning "Data directory still exists: /opt/ai-platform"
        issues_found=true
    else
        log_success "Data directory removed"
    fi
    
    # Check configuration
    if [[ -d "/etc/ai-platform" ]]; then
        log_warning "Configuration directory still exists: /etc/ai-platform"
        issues_found=true
    else
        log_success "Configuration directory removed"
    fi
    
    echo ""
    if [[ "$issues_found" == true ]]; then
        log_warning "Some cleanup issues detected. Check warnings above."
        log_info "You may need to manually remove remaining items."
    else
        log_success "Cleanup verification passed!"
    fi
}

show_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              CLEANUP COMPLETED${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Summary of actions:"
    echo "  ✓ Stopped all AI Platform containers"
    echo "  ✓ Removed all AI Platform containers"
    echo "  ✓ Removed Docker networks"
    echo "  ✓ Removed Docker volumes"
    echo "  ✓ Cleaned up Docker images (if selected)"
    echo "  ✓ Removed data directories (if confirmed)"
    echo "  ✓ Removed configuration files"
    echo "  ✓ Removed log files"
    echo "  ✓ Removed dependencies (if selected)"
    echo "  ✓ Verification completed"
    echo ""
    echo -e "${CYAN}Log file saved to: ${LOG_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Review the log file for any warnings"
    echo "  2. Reboot the system (recommended): sudo reboot"
    echo "  3. Run Script 1 for fresh installation:"
    echo "     ${CYAN}sudo bash /path/to/script1-system-config.sh${NC}"
    echo ""
    echo -e "${GREEN}System is ready for fresh AI Platform installation!${NC}"
    echo ""
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Usage: sudo bash $0"
        exit 1
    fi
    
    # Show banner
    show_banner
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup steps
    stop_all_containers
    remove_all_containers
    remove_docker_networks
    remove_docker_volumes
    cleanup_docker_images
    remove_data_directories
    remove_configuration_files
    remove_log_files
    cleanup_dependencies
    verify_cleanup
    
    # Show summary
    show_summary
    
    log_success "Script 0 v${SCRIPT_VERSION} completed"
}

# Execute
main "$@"
