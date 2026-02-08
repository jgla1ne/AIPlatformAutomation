#!/bin/bash
################################################################################
# SCRIPT 0: NUCLEAR CLEANUP & RESET
# Version: v102.0.0
# Purpose: Complete system reset - removes ALL traces of AI Platform
# 
# This script performs a COMPLETE cleanup:
# - Stops and removes all Docker containers, networks, volumes
# - Removes all configuration files and data directories
# - Cleans up Docker images (optional)
# - Does NOT remove essential system packages (git, curl remain)
# - Resets system to pre-installation state
#
# WARNING: THIS IS DESTRUCTIVE AND IRREVERSIBLE!
#
# Reference: AI PLATFORM DEPLOYMENT v75.2.0
# Compatible with: Script 1 v102.0.0
################################################################################

set -euo pipefail

################################################################################
# SCRIPT METADATA
################################################################################

readonly SCRIPT_VERSION="v102.0.0"
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
    echo -e "${RED}║  ${GREEN}✓${NC}${RED} Essential packages (git, curl) will be preserved      ║${NC}"
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
    echo "This will PRESERVE:"
    echo "  • git, curl, wget (essential tools)"
    echo "  • Docker & Docker Compose"
    echo "  • System configuration"
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
    log_step "1" "9" "STOPPING ALL AI PLATFORM CONTAINERS"
    
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_info "No AI Platform containers found"
        return 0
    fi
    
    local container_count=$(echo "$containers" | wc -l)
    log_info "Found ${container_count} container(s) to stop"
    
    echo "$containers" | while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || echo "unknown")
            log_info "Stopping container: ${name} (${container_id:0:12})"
            docker stop "$container_id" >/dev/null 2>&1 || log_warning "Failed to stop ${container_id:0:12}"
        fi
    done
    
    log_success "All containers stopped"
}

remove_all_containers() {
    log_step "2" "9" "REMOVING ALL AI PLATFORM CONTAINERS"
    
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_info "No AI Platform containers to remove"
        return 0
    fi
    
    echo "$containers" | while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || echo "unknown")
            log_info "Removing container: ${name} (${container_id:0:12})"
            docker rm -f "$container_id" >/dev/null 2>&1 || log_warning "Failed to remove ${container_id:0:12}"
        fi
    done
    
    log_success "All containers removed"
}

remove_docker_networks() {
    log_step "3" "9" "REMOVING AI PLATFORM NETWORKS"
    
    local networks=("ai-platform-network" "aiplatform-network" "ai_platform_network")
    
    for network in "${networks[@]}"; do
        if docker network ls --format "{{.Name}}" | grep -q "^${network}$"; then
            log_info "Removing network: ${network}"
            docker network rm "$network" >/dev/null 2>&1 || log_warning "Failed to remove network: ${network}"
        fi
    done
    
    log_success "Networks removed"
}

remove_docker_volumes() {
    log_step "4" "9" "REMOVING AI PLATFORM VOLUMES"
    
    local volumes=$(docker volume ls --format "{{.Name}}" | grep -E "^aiplatform-|^ai-platform-|^ai_platform_" 2>/dev/null || true)
    
    if [[ -z "$volumes" ]]; then
        log_info "No AI Platform volumes found"
        return 0
    fi
    
    local volume_count=$(echo "$volumes" | wc -l)
    log_info "Found ${volume_count} volume(s) to remove"
    
    echo "$volumes" | while read -r volume; do
        if [[ -n "$volume" ]]; then
            log_info "Removing volume: ${volume}"
            docker volume rm "$volume" >/dev/null 2>&1 || log_warning "Failed to remove volume: ${volume}"
        fi
    done
    
    log_success "All volumes removed"
}

cleanup_docker_images() {
    log_step "5" "9" "CLEANING UP DOCKER IMAGES (OPTIONAL)"
    
    echo ""
    echo -e "${YELLOW}Docker images can consume significant disk space.${NC}"
    echo "Options:"
    echo "  1) Keep all images (default - recommended)"
    echo "  2) Remove AI Platform images only"
    echo "  3) Remove all unused images (prune)"
    echo ""
    
    read -p "Select option [1-3] (Enter for default): " image_option
    image_option=${image_option:-1}
    
    case $image_option in
        1)
            log_info "Keeping all Docker images"
            ;;
        2)
            log_info "Removing AI Platform specific images..."
            local images=(
                "ollama/ollama"
                "ghcr.io/open-webui/open-webui"
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
                "prom/prometheus"
                "grafana/grafana"
                "grafana/loki"
                "minio/minio"
                "portainer/portainer-ce"
                "caddy"
                "nginx"
            )
            
            for image in "${images[@]}"; do
                local found=$(docker images --format "{{.Repository}}" | grep -c "^${image}$" || true)
                if [[ $found -gt 0 ]]; then
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
        *)
            log_warning "Invalid option. Keeping all images."
            ;;
    esac
}

################################################################################
# FILESYSTEM CLEANUP FUNCTIONS
################################################################################

remove_data_directories() {
    log_step "6" "9" "REMOVING DATA DIRECTORIES"
    
    local base_dir="/opt/ai-platform"
    
    if [[ ! -d "$base_dir" ]]; then
        log_info "Data directory does not exist: ${base_dir}"
        return 0
    fi
    
    log_info "Data directory found: ${base_dir}"
    
    # Show directory size
    local dir_size=$(du -sh "$base_dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Directory size: ${dir_size}"
    
    # List subdirectories with sizes
    log_info "Contents:"
    if [[ -d "$base_dir" ]]; then
        find "$base_dir" -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
            if [[ "$dir" != "$base_dir" ]]; then
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "?")
                echo "  ${size}  $(basename "$dir")" | tee -a "$LOG_FILE"
            fi
        done
    fi
    
    echo ""
    log_warning "This will delete ALL data including models, databases, and configurations!"
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
    log_step "7" "9" "REMOVING CONFIGURATION FILES"
    
    local config_locations=(
        "/etc/ai-platform"
        "/etc/systemd/system/ai-platform-*.service"
        "/etc/docker/daemon.json.ai-platform-backup"
    )
    
    for location in "${config_locations[@]}"; do
        if [[ -e "$location" ]] || compgen -G "$location" > /dev/null 2>&1; then
            log_info "Removing: ${location}"
            rm -rf $location 2>/dev/null || log_warning "Failed to remove: ${location}"
        fi
    done
    
    # Check user home directory (but preserve other configs)
    if [[ -d "$HOME/.ai-platform" ]]; then
        log_info "Found user config: $HOME/.ai-platform"
        read -p "Remove user configuration directory? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.ai-platform"
            log_success "User configuration removed"
        else
            log_info "Skipped user configuration"
        fi
    fi
    
    log_success "Configuration files removed"
}

remove_log_files() {
    log_step "8" "9" "REMOVING LOG FILES"
    
    local log_patterns=(
        "/var/log/ai-platform*.log"
        "/var/log/ollama*.log"
        "/var/log/litellm*.log"
    )
    
    log_info "Searching for log files..."
    
    local found_logs=false
    for pattern in "${log_patterns[@]}"; do
        if compgen -G "$pattern" > /dev/null 2>&1; then
            found_logs=true
            for log in $pattern; do
                # Don't delete the current cleanup log
                if [[ "$log" != "$LOG_FILE" ]]; then
                    log_info "Removing: ${log}"
                    rm -f "$log" 2>/dev/null || log_warning "Failed to remove: ${log}"
                fi
            done
        fi
    done
    
    if [[ "$found_logs" == false ]]; then
        log_info "No AI Platform log files found"
    else
        log_success "Log files removed (current cleanup log preserved)"
    fi
}

################################################################################
# VERIFICATION & SUMMARY
################################################################################

verify_cleanup() {
    log_step "9" "9" "VERIFYING CLEANUP"
    
    local issues_found=false
    
    echo ""
    log_info "Checking cleanup status..."
    echo ""
    
    # Check Docker containers
    local containers=$(docker ps -a --filter "label=ai-platform" --format "{{.ID}}" 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        log_warning "Some containers still exist:"
        docker ps -a --filter "label=ai-platform" --format "  {{.Names}} ({{.ID}})" | tee -a "$LOG_FILE"
        issues_found=true
    else
        log_success "No AI Platform containers found"
    fi
    
    # Check Docker networks
    if docker network ls --format "{{.Name}}" | grep -qE "ai-platform|aiplatform"; then
        log_warning "Some networks still exist:"
        docker network ls --format "  {{.Name}}" | grep -E "ai-platform|aiplatform" | tee -a "$LOG_FILE"
        issues_found=true
    else
        log_success "No AI Platform networks found"
    fi
    
    # Check Docker volumes
    local volumes=$(docker volume ls --format "{{.Name}}" | grep -E "^aiplatform-|^ai-platform-" 2>/dev/null || true)
    if [[ -n "$volumes" ]]; then
        log_warning "Some volumes still exist:"
        echo "$volumes" | sed 's/^/  /' | tee -a "$LOG_FILE"
        issues_found=true
    else
        log_success "No AI Platform volumes found"
    fi
    
    # Check data directory
    if [[ -d "/opt/ai-platform" ]]; then
        log_warning "Data directory still exists: /opt/ai-platform"
        log_info "Size: $(du -sh /opt/ai-platform 2>/dev/null | cut -f1 || echo 'unknown')"
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
    
    # Verify essential tools are still present
    echo ""
    log_info "Verifying essential tools..."
    local essential_tools=("git" "curl" "wget" "docker")
    for tool in "${essential_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_success "${tool} is available"
        else
            log_warning "${tool} is NOT available (may need reinstall)"
        fi
    done
    
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
    echo "  ✓ Preserved essential packages (git, curl, wget, docker)"
    echo "  ✓ Verification completed"
    echo ""
    echo -e "${CYAN}Log file saved to: ${LOG_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Review the log file for any warnings"
    echo "  2. Reboot the system (optional but recommended):"
    echo "     ${CYAN}sudo reboot${NC}"
    echo ""
    echo "  3. After reboot, run Script 1 for fresh installation:"
    echo "     ${CYAN}cd ~/AIPlatformAutomation/scripts${NC}"
    echo "     ${CYAN}sudo ./1-setup-system.sh${NC}"
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
    
    # Log start
    echo "AI Platform Cleanup Log - $(date)" >> "$LOG_FILE"
    echo "Script Version: ${SCRIPT_VERSION}" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo ""
        echo "Usage: sudo bash $0"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        log_warning "Docker is not installed or not in PATH"
        log_info "Skipping Docker-related cleanup steps"
    fi
    
    # Show banner
    show_banner
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup steps
    if command -v docker &>/dev/null; then
        stop_all_containers
        remove_all_containers
        remove_docker_networks
        remove_docker_volumes
        cleanup_docker_images
    else
        log_warning "Skipping Docker cleanup (Docker not found)"
    fi
    
    remove_data_directories
    remove_configuration_files
    remove_log_files
    verify_cleanup
    
    # Show summary
    show_summary
    
    log_success "Script 0 v${SCRIPT_VERSION} completed"
    echo "" >> "$LOG_FILE"
    echo "Cleanup completed at: $(date)" >> "$LOG_FILE"
}

# Execute
main "$@"

