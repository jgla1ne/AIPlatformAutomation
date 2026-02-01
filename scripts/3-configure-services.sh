#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Configuration Script
# Version: 11.0 FINAL - ALL SERVICES
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/configure-${TIMESTAMP}.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "\n${BLUE}▶${NC} $1" | tee -a "$LOGFILE"; }

error_handler() {
    log_error "Script failed at line $1"
    log_error "Command: $BASH_COMMAND"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ============================================================================
# LOAD ENVIRONMENT
# ============================================================================
load_environment() {
    log_step "Loading environment configuration..."
    
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        log_error ".env file not found!"
        exit 1
    fi
    
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
    
    log_success "Environment loaded"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
check_container() {
    local container_name=$1
    
    if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_success "${container_name} is running"
        return 0
    else
        log_error "${container_name} is not running"
        return 1
    fi
}

check_service_tcp() {
    local service_name=$1
    local port=$2
    local max_wait=${3:-60}
    local elapsed=0
    
    log_info "Checking ${service_name} on port ${port}..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        if timeout 2 bash -c "echo > /dev/tcp/localhost/${port}" 2>/dev/null; then
            log_success "${service_name} is responding on port ${port}"
            return 0
        fi
        
        if [[ $((elapsed % 10)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
            echo -n "."
        fi
        
        sleep 2
        ((elapsed+=2))
    done
    
    echo ""
    log_warning "${service_name} not responding after ${max_wait}s (may still be starting)"
    return 0
}

# ============================================================================
# CONFIGURE OLLAMA
# ============================================================================
configure_ollama() {
    log_step "Configuring Ollama..."
    
    check_container "ollama"
    check_service_tcp "Ollama" "$OLLAMA_PORT" 30
    
    log_info "Verifying Ollama models..."
    if docker exec ollama ollama list | grep -q "llama3.2:3b"; then
        log_success "llama3.2:3b model available"
    else
        log_warning "llama3.2:3b model not found, may need to pull"
    fi
    
    if docker exec ollama ollama list | grep -q "nomic-embed-text"; then
        log_success "nomic-embed-text model available"
    else
        log_warning "nomic-embed-text model not found, may need to pull"
    fi
    
    echo ""
    log_info "📋 Ollama is ready at:"
    log_info "  • API: http://${TAILSCALE_IP}:${OLLAMA_PORT}"
    log_info ""
    log_info "Test with:"
    log_info "  curl http://localhost:${OLLAMA_PORT}/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Hello!\"}'"
    echo ""
}

# ============================================================================
# CONFIGURE LITELLM
# ============================================================================
configure_litellm() {
    log_step "Configuring LiteLLM..."
    
    check_container "litellm"
    check_service_tcp "LiteLLM" "$LITELLM_PORT" 45
    
    log_info "LiteLLM Master Key: ${LITELLM_MASTER_KEY}"
    
    echo ""
    log_info "📋 LiteLLM is ready at:"
    log_info "  • API: http://${TAILSCALE_IP}:${LITELLM_PORT}"
    log_info "  • Proxy: https://${TAILSCALE_IP}:${NGINX_PORT}/litellm/"
    log_info ""
    log_info "Test with:"
    log_info "  curl http://localhost:${LITELLM_PORT}/health"
    echo ""
}

# ============================================================================
# CONFIGURE ANYTHINGLLM
# ============================================================================
configure_anythingllm() {
    log_step "Configuring AnythingLLM..."
    
    check_container "anythingllm"
    check_service_tcp "AnythingLLM" "$ANYTHINGLLM_PORT" 60
    
    echo ""
    log_info "📋 AnythingLLM Setup:"
    log_info "1. Open: https://${TAILSCALE_IP}:${NGINX_PORT}/anythingllm/"
    log_info "2. Create admin account on first access"
    log_info "3. Configure LLM provider:"
    log_info "   - Provider: Ollama"
    log_info "   - Base URL: http://ollama:11434"
    log_info "   - Model: llama3.2:3b"
    log_info "4. Configure embeddings:"
    log_info "   - Provider: Ollama"
    log_info "   - Model: nomic-embed-text"
    log_info "5. Configure vector database:"
    log_info "   - Type: LanceDB (default)"
    log_info ""
    log_info "Direct access: http://${TAILSCALE_IP}:${ANYTHINGLLM_PORT}"
    echo ""
}

# ============================================================================
# CONFIGURE DIFY
# ============================================================================
configure_dify() {
    log_step "Configuring Dify..."
    
    check_container "dify-web"
    check_container "dify-api"
    check_container "dify-db"
    check_container "dify-redis"
    
    check_service_tcp "Dify Web" "$DIFY_WEB_PORT" 60
    
    echo ""
    log_info "📋 Dify Setup:"
    log_info "1. Open: https://${TAILSCALE_IP}:${NGINX_PORT}/dify/"
    log_info "2. Create admin account"
    log_info "3. Configure model provider:"
    log_info "   - Add OpenAI-compatible provider"
    log_info "   - API Base: http://litellm:4000/v1"
    log_info "   - API Key: ${LITELLM_MASTER_KEY}"
    log_info "   - Model: llama3.2"
    log_info "4. Start building applications!"
    log_info ""
    log_info "Direct access: http://${TAILSCALE_IP}:${DIFY_WEB_PORT}"
    echo ""
}

# ============================================================================
# CONFIGURE N8N
# ============================================================================
configure_n8n() {
    log_step "Configuring n8n..."
    
    check_container "n8n"
    check_service_tcp "n8n" "$N8N_PORT" 45
    
    echo ""
    log_info "📋 n8n Setup:"
    log_info "1. Open: https://${TAILSCALE_IP}:${NGINX_PORT}/n8n/"
    log_info "2. Create owner account"
    log_info "3. Install community nodes (optional):"
    log_info "   - Settings > Community Nodes"
    log_info "   - Install: n8n-nodes-langchain"
    log_info "4. Configure credentials:"
    log_info "   - OpenAI API: Use LiteLLM endpoint"
    log_info "   - URL: http://litellm:4000/v1"
    log_info "   - API Key: ${LITELLM_MASTER_KEY}"
    log_info ""
    log_info "Webhook URL: ${WEBHOOK_URL}"
    log_info "Direct access: http://${TAILSCALE_IP}:${N8N_PORT}"
    echo ""
}

# ============================================================================
# CONFIGURE SIGNAL API
# ============================================================================
configure_signal() {
    log_step "Configuring Signal API..."
    
    check_container "signal-api"
    check_service_tcp "Signal API" "$SIGNAL_PORT" 30
    
    echo ""
    log_info "📋 Signal API Setup:"
    log_info ""
    log_info "METHOD 1 - QR Code Linking (Recommended):"
    log_info "1. Open in browser:"
    log_info "   https://${TAILSCALE_IP}:${NGINX_PORT}/signal/v1/qrcodelink?device_name=ai-platform"
    log_info "2. Scan QR code with Signal app:"
    log_info "   - Open Signal on your phone"
    log_info "   - Settings > Linked Devices > Link New Device"
    log_info "   - Scan the QR code displayed"
    log_info "3. Your phone number will be automatically registered"
    log_info ""
    log_info "METHOD 2 - Phone Number Registration:"
    log_info "1. Register phone number:"
    log_info "   curl -X POST http://${TAILSCALE_IP}:${SIGNAL_PORT}/v1/register/+YOUR_PHONE"
    log_info "2. Verify with SMS code:"
    log_info "   curl -X POST http://${TAILSCALE_IP}:${SIGNAL_PORT}/v1/register/+YOUR_PHONE/verify/CODE"
    log_info ""
    log_info "Access points:"
    log_info "  • Proxied: https://${TAILSCALE_IP}:${NGINX_PORT}/signal/"
    log_info "  • Direct:  http://${TAILSCALE_IP}:${SIGNAL_PORT}"
    log_info "  • Health:  http://${TAILSCALE_IP}:${SIGNAL_PORT}/v1/health"
    echo ""
}

# ============================================================================
# CONFIGURE CLAWDBOT
# ============================================================================
configure_clawdbot() {
    log_step "Configuring ClawdBot..."
    
    check_container "clawdbot"
    check_service_tcp "ClawdBot" "$CLAWDBOT_PORT" 30
    
    echo ""
    log_info "📋 ClawdBot Setup:"
    log_info "1. Ensure Signal is configured first (see above)"
    log_info "2. Register webhook with Signal:"
    log_info "   curl -X POST http://${TAILSCALE_IP}:${SIGNAL_PORT}/v1/configuration \\"
    log_info "     -H 'Content-Type: application/json' \\"
    log_info "     -d '{\"webhook_url\":\"http://clawdbot:8000/webhook/signal\"}'"
    log_info ""
    log_info "3. Test ClawdBot:"
    log_info "   - Send a message to your Signal number"
    log_info "   - ClawdBot should respond with AI-generated reply"
    log_info ""
    log_info "Admin panel: https://${TAILSCALE_IP}:${NGINX_PORT}/clawdbot/"
    log_info "Admin password: ${CLAWDBOT_ADMIN_PASSWORD}"
    log_info "Direct API: http://${TAILSCALE_IP}:${CLAWDBOT_PORT}"
    echo ""
}

# ============================================================================
# CONFIGURE GOOGLE DRIVE SYNC
# ============================================================================
configure_gdrive() {
    log_step "Configuring Google Drive Sync..."
    
    if check_container "gdrive-sync"; then
        echo ""
        log_info "📋 Google Drive Setup:"
        log_info "1. Configure rclone:"
        log_info "   docker exec -it gdrive-sync rclone config"
        log_info ""
        log_info "2. Follow prompts to add Google Drive:"
        log_info "   - Choose: n) New remote"
        log_info "   - Name: gdrive"
        log_info "   - Type: drive"
        log_info "   - Complete OAuth flow"
        log_info ""
        log_info "3. Test connection:"
        log_info "   docker exec gdrive-sync rclone lsd gdrive:"
        log_info ""
        log_info "4. Set up sync cron job:"
        log_info "   docker exec gdrive-sync rclone sync /data gdrive:AIPlatform --progress"
        log_info ""
    else
        log_warning "gdrive-sync container not running"
    fi
}

# ============================================================================
# VERIFY NETWORK
# ============================================================================
verify_network() {
    log_step "Verifying network connectivity..."
    
    log_info "Testing inter-service communication..."
    
    # Test Ollama from LiteLLM
    if docker exec litellm curl -s http://ollama:11434/api/tags >/dev/null 2>&1; then
        log_success "LiteLLM can reach Ollama"
    else
        log_warning "LiteLLM cannot reach Ollama"
    fi
    
    # Test LiteLLM from n8n
    if docker exec n8n wget -q -O- http://litellm:4000/health >/dev/null 2>&1; then
        log_success "n8n can reach LiteLLM"
    else
        log_warning "n8n cannot reach LiteLLM"
    fi
    
    # Test Signal from ClawdBot
    if docker exec clawdbot curl -s http://signal-api:8080/v1/health >/dev/null 2>&1; then
        log_success "ClawdBot can reach Signal API"
    else
        log_warning "ClawdBot cannot reach Signal API"
    fi
    
    log_success "Network verification complete"
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
show_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            CONFIGURATION COMPLETE                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 PRIMARY ACCESS (HTTPS - Recommended):"
    echo "   https://${TAILSCALE_IP}:${NGINX_PORT}/"
    echo ""
    echo "📱 WEB INTERFACES:"
    echo "   • Dashboard:    https://${TAILSCALE_IP}:${NGINX_PORT}/"
    echo "   • AnythingLLM:  https://${TAILSCALE_IP}:${NGINX_PORT}/anythingllm/"
    echo "   • Dify:         https://${TAILSCALE_IP}:${NGINX_PORT}/dify/"
    echo "   • n8n:          https://${TAILSCALE_IP}:${NGINX_PORT}/n8n/"
    echo "   • ClawdBot:     https://${TAILSCALE_IP}:${NGINX_PORT}/clawdbot/"
    echo ""
    echo "🔌 API ENDPOINTS (HTTP):"
    echo "   • Ollama:       http://${TAILSCALE_IP}:${OLLAMA_PORT}"
    echo "   • LiteLLM:      http://${TAILSCALE_IP}:${LITELLM_PORT}"
    echo "   • Signal:       http://${TAILSCALE_IP}:${SIGNAL_PORT}"
    echo ""
    echo "📱 SIGNAL QR CODE LINKING:"
    echo "   https://${TAILSCALE_IP}:${NGINX_PORT}/signal/v1/qrcodelink?device_name=ai-platform"
    echo ""
    echo "🔑 CREDENTIALS:"
    echo "   • LiteLLM API Key:      ${LITELLM_MASTER_KEY}"
    echo "   • ClawdBot Admin PWD:   ${CLAWDBOT_ADMIN_PASSWORD}"
    echo ""
    echo "📝 LOG FILE: ${LOGFILE}"
    echo ""
    echo "🎯 NEXT STEPS:"
    echo "1. Open the dashboard in your browser"
    echo "2. Complete setup for each service (create accounts)"
    echo "3. Link Signal device using QR code"
    echo "4. Configure ClawdBot webhook"
    echo "5. Set up Google Drive sync (optional)"
    echo ""
    echo "🔧 USEFUL COMMANDS:"
    echo "   • View logs:     docker compose logs -f [service]"
    echo "   • Restart:       docker compose restart [service]"
    echo "   • Stop all:      docker compose down"
    echo "   • Status:        docker compose ps"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║    AI Platform - Service Configuration v11 FINAL       ║
║              Complete Setup Guide                      ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    load_environment
    
    configure_ollama
    configure_litellm
    configure_anythingllm
    configure_dify
    configure_n8n
    configure_signal
    configure_clawdbot
    configure_gdrive
    
    verify_network
    show_summary
    
    log_success "Configuration completed successfully!"
}

main "$@" 2>&1 | tee -a "$LOGFILE"
