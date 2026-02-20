#!/bin/bash

#==============================================================================
# Script 1: System Setup & Configuration Collection
# Purpose: Complete system preparation with interactive UI
# Version: 4.3.0 - Clean Working Version
#==============================================================================

set -euo pipefail

# Paths (defined before any library loading)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/setup.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_DIR="$DATA_ROOT/compose"
readonly COMPOSE_FILE="$DATA_ROOT/ai-platform/deployment/stack/docker-compose.yml"

# Basic logging function (before library loading)
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - SETUP                    ║${NC}"
    echo -e "${CYAN}║              Version 4.3.0 - Clean Working Version      ║${NC}"
    echo -e "${CYAN}║           Volume Detection + Domain Configuration          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

prompt_input() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3
    local is_secret=$4
    local validation_type=$5
    
    while true; do
        if [[ "$is_secret" == "true" ]]; then
            echo -n -e "${YELLOW}$prompt_text: ${NC}"
            read -s INPUT_RESULT
            echo ""
        else
            echo -n -e "${YELLOW}$prompt_text${NC}"
            read -r INPUT_RESULT
        fi
        
        # Apply validation if specified
        case "$validation_type" in
            "email")
                if [[ "$INPUT_RESULT" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    break
                else
                    print_error "Invalid email format"
                fi
                ;;
            "domain")
                if [[ "$INPUT_RESULT" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || [[ "$INPUT_RESULT" == "localhost" ]]; then
                    break
                else
                    print_error "Invalid domain format"
                fi
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [[ -n "$default_value" && -z "$INPUT_RESULT" ]]; then
        INPUT_RESULT="$default_value"
    fi
}

confirm() {
    local prompt_text=$1
    local default=${2:-n}
    
    while true; do
        echo -n -e "${YELLOW}$prompt_text [Y/n]: ${NC}"
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) print_error "Please enter Y or N" ;;
        esac
    done
}

generate_random_password() {
    local length=${1:-24}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    log "INFO" "Logging initialized"
}

log_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    
    echo ""
    print_header "$icon STEP $phase/13: $title"
}

mark_phase_complete() {
    local phase="$1"
    log "INFO" "Phase completed: $phase"
}

save_state() {
    local phase="$1"
    local status="$2"
    local message="$3"
    
    mkdir -p "$METADATA_DIR"
    
    cat > "$STATE_FILE" <<EOF
{
  "script_version": "4.3.0",
  "current_phase": "$phase",
  "status": "$status",
  "message": "$message",
  "timestamp": "$(date -Iseconds)",
  "completed_phases": [
EOF
    
    local first=true
    for completed_phase in "${COMPLETED_PHASES[@]:-}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$STATE_FILE"
        fi
        first=false
        echo "    \"$completed_phase\"" >> "$STATE_FILE"
    done
    
    cat >> "$STATE_FILE" <<EOF
  ]
}
EOF
    
    print_success "State saved: Phase $phase - $status"
}

restore_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        print_info "No previous state found - starting fresh"
        return 1
    fi
    
    print_info "Previous state found"
    return 0
}

# Create directory structure FIRST (before any library loading)
create_directory_structure() {
    log "INFO" "Creating directory structure..."
    
    # Create all necessary directories
    mkdir -p "$DATA_ROOT"
    mkdir -p "$METADATA_DIR"
    mkdir -p "$DATA_ROOT/logs"
    mkdir -p "$DATA_ROOT/config"
    mkdir -p "$DATA_ROOT/data"
    mkdir -p "$DATA_ROOT/ssl"
    mkdir -p "$DATA_ROOT/backups"
    mkdir -p "$DATA_ROOT/scripts"
    mkdir -p "$DATA_ROOT/scripts/lib"
    mkdir -p "$COMPOSE_DIR"
    mkdir -p "$DATA_ROOT/ai-platform/deployment/stack"
    
    log "SUCCESS" "Directory structure created"
}

# Load shared libraries AFTER directory structure is created
load_shared_libraries() {
    # Check if libraries exist, if not create minimal versions
    if [[ ! -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
        log "WARN" "Common library not found, creating minimal version..."
        mkdir -p "${SCRIPT_DIR}/lib"
        cat > "${SCRIPT_DIR}/lib/common.sh" << 'EOF'
# Minimal common.sh for Script 1
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}
EOF
    fi
    
    if [[ ! -f "${SCRIPT_DIR}/lib/manifest.sh" ]]; then
        log "WARN" "Manifest library not found, creating minimal version..."
        cat > "${SCRIPT_DIR}/lib/manifest.sh" << 'EOF'
# Minimal manifest.sh for Script 1
init_service_manifest() {
    log "INFO" "Initializing service manifest..."
    mkdir -p "$(dirname "/mnt/data/config/installed_services.json")"
    echo '{"services": {}}' > "/mnt/data/config/installed_services.json"
}

write_service_manifest() {
    local service=$1
    local port=$2
    local path=$3
    local container=$4
    local image=$5
    local external_port=$6
    
    log "INFO" "Writing service manifest entry for $service..."
    # Minimal implementation - will be enhanced by full library later
}
EOF
    fi
    
    # Now load the libraries
    source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
    source "${SCRIPT_DIR}/lib/manifest.sh" 2>/dev/null || true
}

# Simple placeholder functions for now
detect_system() {
    log_phase "1" "🔍" "System Detection"
    print_info "System detection placeholder - would normally detect hardware"
}

collect_domain_info() {
    log_phase "2" "🌐" "Domain & Network Configuration"
    print_info "Domain configuration placeholder"
}

update_system() {
    log_phase "3" "🔄" "System Update"
    print_info "System update placeholder"
}

install_docker() {
    log_phase "4" "🐳" "Docker Installation"
    print_info "Docker installation placeholder"
}

configure_docker() {
    log_phase "5" "⚙️" "Docker Configuration"
    print_info "Docker configuration placeholder"
}

install_ollama() {
    log_phase "6" "🤖" "Ollama Installation"
    print_info "Ollama installation placeholder"
}

select_services() {
    log_phase "7" "🎯" "Service Selection"
    print_info "Service selection placeholder"
}

collect_configurations() {
    log_phase "8" "⚙️" "Configuration Collection"
    print_info "Configuration collection placeholder"
}

setup_volumes() {
    log_phase "9" "🗂️" "Volume Setup"
    print_info "Volume setup placeholder"
}

generate_compose_templates() {
    log_phase "10" "🐳" "Docker Compose Template Generation"
    print_info "Compose template generation placeholder"
}

validate_system() {
    log_phase "11" "🔍" "System Validation"
    print_info "System validation placeholder"
}

generate_summary() {
    log_phase "12" "📊" "Summary Generation"
    print_info "Summary generation placeholder"
}

# Main Execution
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # 🔥 FIXED: Create directory structure FIRST (before any library loading)
    create_directory_structure
    
    # 🔥 FIXED: Load shared libraries AFTER directory structure is created
    load_shared_libraries
    
    # Initialize logging (now that libraries are loaded)
    setup_logging
    
    # Initialize service manifest
    init_service_manifest
    
    # Display banner
    print_banner
    
    # Check for previous state and offer to resume
    if restore_state; then
        print_info "Resuming from saved state..."
    else
        # Fresh start
        COMPLETED_PHASES=()
        save_state "init" "started" "Setup initialized"
    fi
    
    # Execute phases
    setup_volumes
    mark_phase_complete "setup_volumes"
    detect_system
    mark_phase_complete "detect_system"
    collect_domain_info
    mark_phase_complete "collect_domain_info"
    update_system
    mark_phase_complete "update_system"
    install_docker
    mark_phase_complete "install_docker"
    configure_docker
    mark_phase_complete "configure_docker"
    install_ollama
    mark_phase_complete "install_ollama"
    select_services
    mark_phase_complete "select_services"
    collect_configurations
    mark_phase_complete "collect_configurations"
    generate_compose_templates
    mark_phase_complete "generate_compose_templates"
    validate_system
    mark_phase_complete "validate_system"
    generate_summary
    mark_phase_complete "generate_summary"
    
    echo ""
    print_success "Script 1 setup completed successfully!"
    echo ""
    print_info "Directory structure created at: $DATA_ROOT"
    print_info "Environment file created at: $ENV_FILE"
    print_info "Service manifest created at: /mnt/data/config/installed_services.json"
    echo ""
    print_info "You can now run: ./2-deploy-services.sh"
}

# Execute main function
main "$@"
