#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Configure Services Script
# Version: 8.0 - COMPLETE WITH CLAWDBOT ONBOARDING
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
LOGFILE="${LOGS_DIR}/configure-${TIMESTAMP}.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "\n${CYAN}[$1]${NC} $2" | tee -a "$LOGFILE"; }

error_handler() {
    log_error "Configuration failed at line $1"
    log_error "Check log: $LOGFILE"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ============================================================================
# CHECK ENVIRONMENT
# ============================================================================
check_environment() {
    log_step "1/6" "Checking environment..."
    
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    
    source "${PROJECT_ROOT}/.env"
    
    cd "$PROJECT_ROOT"
    
    # Check if services are running
    local required_services=(
        "ollama"
        "litellm"
        "anythingllm"
        "dify-api"
        "n8n"
        "signal-api"
        "clawdbot"
    )
    
    for service in "${required_services[@]}"; do
        if ! docker compose ps "$service" | grep -q "Up"; then
            log_error "${service} is not running"
            log_error "Run ./2-deploy-services.sh first"
            exit 1
        fi
    done
    
    log_success "All required services are running"
}

# ============================================================================
# CONFIGURE OLLAMA
# ============================================================================
configure_ollama() {
    log_step "2/6" "Configuring Ollama..."
    
    echo ""
    log_info "Available Ollama models to download:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  1. llama3.2:latest      (Recommended - 4.7GB)"
    echo "  2. mistral:latest       (7.2GB)"
    echo "  3. codellama:latest     (3.8GB)"
    echo "  4. phi3:latest          (2.2GB)"
    echo "  5. qwen2.5:latest       (4.7GB)"
    echo "  6. Custom model"
    echo "  7. Skip model download"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "Select model to download (1-7): " model_choice
    
    case $model_choice in
        1) MODEL_NAME="llama3.2:latest" ;;
        2) MODEL_NAME="mistral:latest" ;;
        3) MODEL_NAME="codellama:latest" ;;
        4) MODEL_NAME="phi3:latest" ;;
        5) MODEL_NAME="qwen2.5:latest" ;;
        6) 
            read -p "Enter custom model name (e.g., llama3.2:3b): " MODEL_NAME
            ;;
        7)
            log_warning "Skipping model download"
            return 0
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac
    
    log_info "Downloading ${MODEL_NAME}... (this may take several minutes)"
    echo ""
    
    if docker exec ollama ollama pull "$MODEL_NAME" 2>&1 | tee -a "$LOGFILE"; then
        log_success "Model ${MODEL_NAME} downloaded successfully"
        
        # Test the model
        log_info "Testing model..."
        if docker exec ollama ollama run "$MODEL_NAME" "Hello" --verbose=false 2>&1 | tee -a "$LOGFILE"; then
            log_success "Model test successful"
        else
            log_warning "Model test failed, but model is downloaded"
        fi
    else
        log_error "Failed to download model"
        return 1
    fi
    
    echo ""
    log_info "To list all models: docker exec ollama ollama list"
    log_info "To download more models: docker exec ollama ollama pull <model-name>"
}

# ============================================================================
# CONFIGURE SIGNAL API
# ============================================================================
configure_signal() {
    log_step "3/6" "Configuring Signal API..."
    
    echo ""
    log_info "Signal API requires phone number registration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Do you want to register Signal now? (y/n): " register_signal
    
    if [[ "$register_signal" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "Enter phone number (with country code, e.g., +1234567890): " phone_number
        
        log_info "Registering ${phone_number}..."
        
        # Register with Signal
        local response=$(curl -s -X POST "http://localhost:8080/v1/register/${phone_number}" \
            -H "Content-Type: application/json" \
            -d '{"use_voice": false}')
        
        if echo "$response" | grep -q "error"; then
            log_error "Registration failed: $response"
            return 1
        fi
        
        log_success "Verification code sent to ${phone_number}"
        echo ""
        
        read -p "Enter verification code: " verification_code
        
        # Verify the code
        local verify_response=$(curl -s -X POST "http://localhost:8080/v1/register/${phone_number}/verify/${verification_code}")
        
        if echo "$verify_response" | grep -q "error"; then
            log_error "Verification failed: $verify_response"
            return 1
        fi
        
        log_success "Signal registration successful!"
        
        # Save phone number to .env
        echo "" >> "${PROJECT_ROOT}/.env"
        echo "SIGNAL_PHONE=${phone_number}" >> "${PROJECT_ROOT}/.env"
        
        log_info "Phone number saved to .env"
        
    else
        log_warning "Skipping Signal registration"
        log_info "You can register later with:"
        log_info "  curl -X POST http://localhost:8080/v1/register/+1234567890"
    fi
}

# ============================================================================
# CONFIGURE CLAWDBOT (MOLTBOT)
# ============================================================================
configure_clawdbot() {
    log_step "4/6" "Configuring ClawdBot (Moltbot)..."
    
    source "${PROJECT_ROOT}/.env"
    
    echo ""
    log_info "Starting ClawdBot onboarding process..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log_info "Gateway Token: ${CLAWDBOT_GATEWAY_TOKEN}"
    echo ""
    
    # Check if ClawdBot is responsive
    log_info "Checking ClawdBot service..."
    if docker exec clawdbot wget --quiet --tries=1 --spider http://localhost:18789/health 2>/dev/null; then
        log_success "ClawdBot is running"
    else
        log_error "ClawdBot is not responding"
        log_error "Check logs: docker compose logs clawdbot"
        return 1
    fi
    
    echo ""
    log_info "Running ClawdBot onboarding..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Run onboarding command
    if docker exec -it clawdbot node /app/dist/index.js onboard; then
        log_success "ClawdBot onboarding completed!"
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "ClawdBot Access Information:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Gateway URL:    http://${TAILSCALE_IP}:18789"
        echo "  Control Port:   http://${TAILSCALE_IP}:18790"
        echo "  Gateway Token:  ${CLAWDBOT_GATEWAY_TOKEN}"
        echo ""
        echo "  📝 Configuration saved in container at:"
        echo "     /home/node/.clawdbot/"
        echo ""
        echo "  📁 Workspace directory:"
        echo "     /home/node/clawd/"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
    else
        log_error "ClawdBot onboarding failed"
        log_info "You can run it manually with:"
        log_info "  docker exec -it clawdbot node /app/dist/index.js onboard"
        return 1
    fi
    
    echo ""
    log_info "Testing ClawdBot CLI..."
    if docker exec clawdbot node /app/dist/index.js --version 2>&1 | tee -a "$LOGFILE"; then
        log_success "ClawdBot CLI is working"
    else
        log_warning "ClawdBot CLI test failed"
    fi
}

# ============================================================================
# VERIFY LITELLM
# ============================================================================
verify_litellm() {
    log_step "5/6" "Verifying LiteLLM configuration..."
    
    source "${PROJECT_ROOT}/.env"
    
    echo ""
    log_info "Testing LiteLLM connection to Ollama..."
    
    # Test LiteLLM health
    local health_response=$(curl -s http://localhost:4000/health)
    
    if echo "$health_response" | grep -q "healthy"; then
        log_success "LiteLLM is healthy"
    else
        log_warning "LiteLLM health check returned: $health_response"
    fi
    
    echo ""
    log_info "LiteLLM Configuration:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  API Endpoint:  http://localhost:4000"
    echo "  Master Key:    ${LITELLM_MASTER_KEY}"
    echo "  Ollama Proxy:  http://ollama:11434"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# SHOW CONFIGURATION SUMMARY
# ============================================================================
show_summary() {
    log_step "6/6" "Configuration complete!"
    
    source "${PROJECT_ROOT}/.env"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗" | tee -a "$LOGFILE"
    echo "║            CONFIGURATION SUMMARY                       ║" | tee -a "$LOGFILE"
    echo "╚════════════════════════════════════════════════════════════╝" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "🌐 SERVICE ACCESS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  Main Dashboard:  https://${TAILSCALE_IP}:${NGINX_PORT}/" | tee -a "$LOGFILE"
    echo "  AnythingLLM:     https://${TAILSCALE_IP}:${NGINX_PORT}/anythingllm/" | tee -a "$LOGFILE"
    echo "  Dify:            https://${TAILSCALE_IP}:${NGINX_PORT}/dify/" | tee -a "$LOGFILE"
    echo "  n8n:             https://${TAILSCALE_IP}:${NGINX_PORT}/n8n/" | tee -a "$LOGFILE"
    echo "  Signal API:      https://${TAILSCALE_IP}:${NGINX_PORT}/signal/" | tee -a "$LOGFILE"
    echo "  ClawdBot:        http://${TAILSCALE_IP}:18789/" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "🔑 API KEYS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  LiteLLM Master:    ${LITELLM_MASTER_KEY}" | tee -a "$LOGFILE"
    echo "  ClawdBot Gateway:  ${CLAWDBOT_GATEWAY_TOKEN}" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "🤖 CLAWDBOT COMMANDS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  Run onboarding:   docker exec -it clawdbot node /app/dist/index.js onboard" | tee -a "$LOGFILE"
    echo "  Start session:    docker exec -it clawdbot node /app/dist/index.js" | tee -a "$LOGFILE"
    echo "  Check version:    docker exec clawdbot node /app/dist/index.js --version" | tee -a "$LOGFILE"
    echo "  View config:      docker exec clawdbot cat /home/node/.clawdbot/config.json" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "📊 USEFUL COMMANDS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  View all logs:         docker compose logs -f" | tee -a "$LOGFILE"
    echo "  View service logs:     docker compose logs -f [service]" | tee -a "$LOGFILE"
    echo "  Check status:          docker compose ps" | tee -a "$LOGFILE"
    echo "  Restart service:       docker compose restart [service]" | tee -a "$LOGFILE"
    echo "  Stop all:              docker compose down" | tee -a "$LOGFILE"
    echo "  List Ollama models:    docker exec ollama ollama list" | tee -a "$LOGFILE"
    echo "  Pull Ollama model:     docker exec ollama ollama pull <model>" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "📁 IMPORTANT PATHS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  Project Root:       ${PROJECT_ROOT}" | tee -a "$LOGFILE"
    echo "  Environment File:   ${PROJECT_ROOT}/.env" | tee -a "$LOGFILE"
    echo "  Docker Compose:     ${PROJECT_ROOT}/docker-compose.yml" | tee -a "$LOGFILE"
    echo "  Configuration Log:  ${LOGFILE}" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    log_success "✅ All services configured and ready to use!" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║       AI Platform - Configure Services v8              ║
║         WITH CLAWDBOT ONBOARDING                       ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    echo "Started: $(date)" | tee -a "$LOGFILE"
    echo ""
    
    check_environment
    configure_ollama
    configure_signal
    configure_clawdbot
    verify_litellm
    show_summary
    
    log_success "Configuration completed at: $(date)" | tee -a "$LOGFILE"
}

main "$@"
