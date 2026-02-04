#!/bin/bash

#############################################################################
# AI PLATFORM ADD SERVICE SCRIPT v68.0.0
# Extensibility framework for adding new services
#############################################################################

set -euo pipefail

SCRIPT_VERSION="68.0.0"
INSTALL_DIR="/opt/ai-services"
LOG_FILE="${INSTALL_DIR}/logs/4-add-service.log"
ENV_FILE="${INSTALL_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#############################################################################
# LOGGING
#############################################################################

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
    echo -e "${BLUE}[INFO]${NC} $*"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*"
    echo -e "${RED}[ERROR]${NC} $*"
    echo "$msg" >> "$LOG_FILE"
}

#############################################################################
# INITIALIZATION
#############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

source_environment() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$ENV_FILE"
}

#############################################################################
# PRE-CONFIGURED SERVICES
#############################################################################

add_open_webui() {
    log "Adding Open WebUI..."
    
    read -p "Port for Open WebUI [default: 8080]: " port
    port=${port:-8080}
    
    docker run -d \
        --name open-webui \
        --network ai-network \
        -p "${port}:8080" \
        -v /mnt/data/open-webui:/app/backend/data \
        -e OLLAMA_BASE_URL=http://ollama:11434 \
        --restart unless-stopped \
        --label ai-platform=true \
        ghcr.io/open-webui/open-webui:main
    
    log_success "Open WebUI deployed on port ${port}"
}

add_flowise() {
    log "Adding Flowise..."
    
    read -p "Port for Flowise [default: 3002]: " port
    port=${port:-3002}
    
    docker run -d \
        --name flowise \
        --network ai-network \
        -p "${port}:3000" \
        -v /mnt/data/flowise:/root/.flowise \
        -e FLOWISE_USERNAME=admin \
        -e FLOWISE_PASSWORD=admin123 \
        --restart unless-stopped \
        --label ai-platform=true \
        flowiseai/flowise:latest
    
    log_success "Flowise deployed on port ${port}"
}

add_langflow() {
    log "Adding Langflow..."
    
    read -p "Port for Langflow [default: 7860]: " port
    port=${port:-7860}
    
    docker run -d \
        --name langflow \
        --network ai-network \
        -p "${port}:7860" \
        -v /mnt/data/langflow:/app/langflow \
        --restart unless-stopped \
        --label ai-platform=true \
        logspace/langflow:latest
    
    log_success "Langflow deployed on port ${port}"
}

add_custom_service() {
    echo ""
    log "Adding custom Docker service..."
    echo ""
    
    read -p "Service name: " service_name
    read -p "Docker image: " docker_image
    read -p "Port (host:container): " port_mapping
    read -p "Volume mount (host:container): " volume_mount
    read -p "Additional environment variables (KEY=VALUE, comma-separated): " env_vars
    
    local docker_args=(
        --name "$service_name"
        --network ai-network
        -p "$port_mapping"
        --restart unless-stopped
        --label ai-platform=true
    )
    
    if [ -n "$volume_mount" ]; then
        docker_args+=(-v "$volume_mount")
    fi
    
    if [ -n "$env_vars" ]; then
        IFS=',' read -ra ENV_ARRAY <<< "$env_vars"
        for env in "${ENV_ARRAY[@]}"; do
            docker_args+=(-e "$env")
        done
    fi
    
    docker run -d "${docker_args[@]}" "$docker_image"
    
    log_success "Custom service '${service_name}' deployed"
}

#############################################################################
# MAIN MENU
#############################################################################

show_menu() {
    clear
    echo "========================================="
    echo "ADD SERVICE TO AI PLATFORM v${SCRIPT_VERSION}"
    echo "========================================="
    echo ""
    echo "Pre-configured Services:"
    echo "  1) Open WebUI (Ollama web interface)"
    echo "  2) Flowise (Visual LLM workflow builder)"
    echo "  3) Langflow (AI flow builder)"
    echo ""
    echo "Custom:"
    echo "  4) Add custom Docker service"
    echo ""
    echo "  5) Exit"
    echo ""
    read -p "Select option [1-5]: " choice
    
    case $choice in
        1) add_open_webui ;;
        2) add_flowise ;;
        3) add_langflow ;;
        4) add_custom_service ;;
        5) exit 0 ;;
        *) log_error "Invalid option" ;;
    esac
    
    echo ""
    read -p "Add another service? (y/N): " again
    if [[ "$again" =~ ^[Yy]$ ]]; then
        show_menu
    fi
}

#############################################################################
# MAIN
#############################################################################

main() {
    log "Add Service Script v${SCRIPT_VERSION}"
    check_root
    source_environment
    show_menu
}

mkdir -p "${INSTALL_DIR}/logs"
main
