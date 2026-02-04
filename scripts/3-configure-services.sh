#!/bin/bash

#############################################################################
# AI PLATFORM CONFIGURATION SCRIPT v68.0.0
# Service-specific configuration and optimization
#############################################################################

set -euo pipefail

SCRIPT_VERSION="68.0.0"
INSTALL_DIR="/opt/ai-services"
LOG_FILE="${INSTALL_DIR}/logs/3-configure.log"
ENV_FILE="${INSTALL_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_warn() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*"
    echo -e "${YELLOW}[WARN]${NC} $*"
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
        log_error "Environment file not found: ${ENV_FILE}"
        exit 1
    fi
    
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    log_success "Environment loaded"
}

check_services_running() {
    log "Checking service status..."
    
    local required_services=(
        "ollama"
        "litellm"
        "qdrant"
        "anythingllm"
    )
    
    local missing_services=()
    
    for service in "${required_services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            missing_services+=("$service")
        fi
    done
    
    if [ ${#missing_services[@]} -gt 0 ]; then
        log_error "Required services not running: ${missing_services[*]}"
        echo "Please run: sudo ./2-deploy-services.sh first"
        exit 1
    fi
    
    log_success "All required services are running"
}

#############################################################################
# OLLAMA MODEL MANAGEMENT
#############################################################################

configure_ollama_models() {
    echo ""
    log "========================================="
    log "OLLAMA MODEL CONFIGURATION"
    log "========================================="
    echo ""
    
    echo "Current model from setup: ${OLLAMA_MODEL}"
    echo ""
    echo "Options:"
    echo "  1) Pull default model (${OLLAMA_MODEL})"
    echo "  2) Pull additional models"
    echo "  3) List available models"
    echo "  4) Skip"
    echo ""
    read -p "Select [1-4]: " choice
    
    case $choice in
        1)
            log "Pulling model: ${OLLAMA_MODEL}..."
            docker exec ollama ollama pull "${OLLAMA_MODEL}"
            log_success "Model pulled successfully"
            
            # Also pull embedding model for AnythingLLM
            log "Pulling embedding model: nomic-embed-text..."
            docker exec ollama ollama pull nomic-embed-text
            log_success "Embedding model pulled"
            ;;
        2)
            echo ""
            echo "Popular models:"
            echo "  - llama3.2:1b (1GB, fastest)"
            echo "  - llama3.2:3b (3GB, balanced)"
            echo "  - mistral:7b (7GB, powerful)"
            echo "  - codellama:7b (7GB, coding)"
            echo ""
            read -p "Enter model name to pull: " model_name
            
            if [ -n "$model_name" ]; then
                log "Pulling model: ${model_name}..."
                docker exec ollama ollama pull "$model_name"
                log_success "Model pulled successfully"
            fi
            ;;
        3)
            docker exec ollama ollama list
            ;;
        4)
            log "Skipping model configuration"
            ;;
    esac
}

#############################################################################
# LITELLM ROUTING CONFIGURATION
#############################################################################

configure_litellm_routing() {
    echo ""
    log "========================================="
    log "LITELLM ROUTING CONFIGURATION"
    log "========================================="
    echo ""
    
    echo "Current routing: Simple queries → Ollama, Complex → Cloud (if configured)"
    echo ""
    echo "Options:"
    echo "  1) Update routing rules"
    echo "  2) Test routing"
    echo "  3) View configuration"
    echo "  4) Skip"
    echo ""
    read -p "Select [1-4]: " choice
    
    case $choice in
        1)
            log "Opening LiteLLM configuration..."
            nano "${INSTALL_DIR}/config/litellm/config.yaml"
            
            log "Restarting LiteLLM to apply changes..."
            docker restart litellm
            sleep 5
            log_success "LiteLLM restarted with new configuration"
            ;;
        2)
            echo ""
            echo "Testing LiteLLM endpoint..."
            curl -X POST "http://localhost:${LITELLM_PORT}/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer sk-1234" \
                -d '{
                    "model": "local-llm",
                    "messages": [{"role": "user", "content": "Say hello!"}]
                }' | jq .
            ;;
        3)
            cat "${INSTALL_DIR}/config/litellm/config.yaml"
            ;;
        4)
            log "Skipping LiteLLM configuration"
            ;;
    esac
}

#############################################################################
# ANYTHINGLLM CONFIGURATION
#############################################################################

configure_anythingllm() {
    echo ""
    log "========================================="
    log "ANYTHINGLLM CONFIGURATION"
    log "========================================="
    echo ""
    
    log "AnythingLLM is already configured to use:"
    echo "  - LLM: Ollama (${OLLAMA_MODEL})"
    echo "  - Vector DB: Qdrant"
    echo "  - Embeddings: nomic-embed-text"
    echo ""
    
    echo "Options:"
    echo "  1) View current configuration"
    echo "  2) Access web interface"
    echo "  3) Restart service"
    echo "  4) Skip"
    echo ""
    read -p "Select [1-4]: " choice
    
    case $choice in
        1)
            docker exec anythingllm cat /app/server/storage/settings.json 2>/dev/null || echo "No configuration file yet"
            ;;
        2)
            echo ""
            echo "Access AnythingLLM at: https://${DOMAIN_NAME}/anythingllm"
            echo "Complete initial setup in the web interface"
            ;;
        3)
            docker restart anythingllm
            log_success "AnythingLLM restarted"
            ;;
        4)
            log "Skipping AnythingLLM configuration"
            ;;
    esac
}

#############################################################################
# OPENCLAW CONFIGURATION
#############################################################################

configure_openclaw() {
    echo ""
    log "========================================="
    log "OPENCLAW CONFIGURATION"
    log "========================================="
    echo ""
    
    echo "OpenClaw Configuration:"
    echo "  - Access via Tailscale: https://${TAILSCALE_IP:-<pending>}:${OPENCLAW_PORT}"
    echo "  - Using Ollama: ${OLLAMA_MODEL}"
    echo "  - Vector DB: Qdrant"
    echo ""
    
    echo "Options:"
    echo "  1) Link to AnythingLLM workspace"
    echo "  2) Configure Signal integration"
    echo "  3) View logs"
    echo "  4) Restart service"
    echo "  5) Skip"
    echo ""
    read -p "Select [1-5]: " choice
    
    case $choice in
        1)
            log "To link OpenClaw to AnythingLLM:"
            echo "  1. Create a workspace in AnythingLLM"
            echo "  2. Get the workspace API key"
            echo "  3. Configure OpenClaw to use that workspace"
            echo ""
            read -p "Do you want to update OpenClaw config now? (y/N): " update
            
            if [[ "$update" =~ ^[Yy]$ ]]; then
                nano /mnt/data/openclaw/config.json
                docker restart openclaw
                log_success "OpenClaw configuration updated"
            fi
            ;;
        2)
            log "Signal integration setup:"
            echo "  1. Install Signal CLI in OpenClaw container"
            echo "  2. Link your phone number"
            echo "  3. Configure message handlers"
            echo ""
            echo "Run in OpenClaw container:"
            echo "  docker exec -it openclaw bash"
            ;;
        3)
            docker logs --tail 50 openclaw
            ;;
        4)
            docker restart openclaw
            log_success "OpenClaw restarted"
            ;;
        5)
            log "Skipping OpenClaw configuration"
            ;;
    esac
}

#############################################################################
# GOOGLE DRIVE SYNC
#############################################################################

configure_gdrive_sync() {
    echo ""
    log "========================================="
    log "GOOGLE DRIVE SYNC CONFIGURATION"
    log "========================================="
    echo ""
    
    if [ -z "${GDRIVE_TOKEN:-}" ]; then
        log_warn "Google Drive token not configured"
        echo "Set GDRIVE_TOKEN in ${ENV_FILE} to enable sync"
        return 0
    fi
    
    echo "Options:"
    echo "  1) Set up rclone sync"
    echo "  2) Test sync"
    echo "  3) Skip"
    echo ""
    read -p "Select [1-3]: " choice
    
    case $choice in
        1)
            log "Installing rclone..."
            if ! command -v rclone &> /dev/null; then
                curl https://rclone.org/install.sh | bash
            fi
            
            log "Configuring rclone for Google Drive..."
            mkdir -p ~/.config/rclone
            
            cat > ~/.config/rclone/rclone.conf << EOF
[gdrive]
type = drive
token = ${GDRIVE_TOKEN}
EOF
            
            log "Creating systemd timer for periodic sync..."
            cat > /etc/systemd/system/gdrive-sync.service << EOF
[Unit]
Description=Google Drive Sync
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/rclone sync gdrive: /mnt/data/gdrive --verbose
User=root

[Install]
WantedBy=multi-user.target
EOF

            cat > /etc/systemd/system/gdrive-sync.timer << EOF
[Unit]
Description=Google Drive Sync Timer
Requires=gdrive-sync.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
EOF

            systemctl daemon-reload
            systemctl enable gdrive-sync.timer
            systemctl start gdrive-sync.timer
            
            log_success "Google Drive sync configured"
            ;;
        2)
            log "Testing sync..."
            rclone ls gdrive: --max-depth 1
            ;;
        3)
            log "Skipping Google Drive sync"
            ;;
    esac
}

#############################################################################
# SYSTEMD AUTO-START
#############################################################################

configure_autostart() {
    echo ""
    log "========================================="
    log "AUTO-START CONFIGURATION"
    log "========================================="
    echo ""
    
    echo "Configure services to auto-start on reboot?"
    echo ""
    read -p "Enable auto-start? (Y/n): " enable
    enable=${enable:-Y}
    
    if [[ ! "$enable" =~ ^[Yy]$ ]]; then
        log "Skipping auto-start configuration"
        return 0
    fi
    
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/ai-platform.service << 'EOF'
[Unit]
Description=AI Platform Docker Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDir=/opt/ai-services
ExecStart=/bin/bash -c 'for container in $(docker ps -aq --filter "label=ai-platform=true"); do docker start $container; done'
ExecStop=/bin/bash -c 'for container in $(docker ps -aq --filter "label=ai-platform=true"); do docker stop $container; done'

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ai-platform.service
    
    log_success "Auto-start configured"
    echo ""
    echo "Services will now start automatically on reboot"
}

#############################################################################
# SERVICE HEALTH CHECKS
#############################################################################

run_health_checks() {
    echo ""
    log "========================================="
    log "SERVICE HEALTH CHECKS"
    log "========================================="
    echo ""
    
    local services=(
        "ollama:http://localhost:${OLLAMA_PORT}/api/tags"
        "litellm:http://localhost:${LITELLM_PORT}/health"
        "qdrant:http://localhost:${QDRANT_PORT}/collections"
        "anythingllm:http://localhost:${ANYTHINGLLM_PORT}/api/ping"
        "dify:http://localhost:${DIFY_PORT}"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service url <<< "$service_info"
        
        echo -n "Checking ${service}... "
        if curl -sf "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Healthy${NC}"
        else
            echo -e "${RED}✗ Unhealthy${NC}"
        fi
    done
    
    echo ""
    echo "Container status:"
    docker ps --filter "label=ai-platform=true" --format "table {{.Names}}\t{{.Status}}"
}

#############################################################################
# MAIN MENU
#############################################################################

show_menu() {
    clear
    echo "========================================="
    echo "AI PLATFORM CONFIGURATION MENU v${SCRIPT_VERSION}"
    echo "========================================="
    echo ""
    echo "1) Configure Ollama Models"
    echo "2) Configure LiteLLM Routing"
    echo "3) Configure AnythingLLM"
    echo "4) Configure OpenClaw"
    echo "5) Configure Google Drive Sync"
    echo "6) Configure Auto-Start on Reboot"
    echo "7) Run Health Checks"
    echo "8) Configure All Services"
    echo "9) Exit"
    echo ""
    read -p "Select option [1-9]: " menu_choice
    
    case $menu_choice in
        1) configure_ollama_models ;;
        2) configure_litellm_routing ;;
        3) configure_anythingllm ;;
        4) configure_openclaw ;;
        5) configure_gdrive_sync ;;
        6) configure_autostart ;;
        7) run_health_checks ;;
        8) configure_all ;;
        9) exit 0 ;;
        *) log_error "Invalid option" ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_menu
}

configure_all() {
    configure_ollama_models
    configure_litellm_routing
    configure_anythingllm
    configure_openclaw
    configure_gdrive_sync
    configure_autostart
    run_health_checks
    
    echo ""
    log_success "========================================="
    log_success "ALL SERVICES CONFIGURED"
    log_success "========================================="
    echo ""
    echo "Your AI platform is ready to use!"
    echo ""
    echo "Access URLs:"
    echo "  - AnythingLLM: https://${DOMAIN_NAME}/anythingllm"
    echo "  - Dify: https://${DOMAIN_NAME}/dify"
    echo "  - n8n: https://${DOMAIN_NAME}/n8n"
    echo "  - OpenClaw: https://${TAILSCALE_IP:-<pending>}:${OPENCLAW_PORT}"
    echo ""
}

#############################################################################
# MAIN EXECUTION
#############################################################################

main() {
    log "========================================="
    log "AI Platform Configuration Script v${SCRIPT_VERSION}"
    log "========================================="
    
    check_root
    source_environment
    check_services_running
    
    show_menu
}

mkdir -p "${INSTALL_DIR}/logs"
main
