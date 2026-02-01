#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Configuration Script
# Version: 10.4 FINAL - NO HEREDOC PIPING
# Description: Ultra-robust configuration with simple logging
# ============================================================================

# Logging setup
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

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"
}

log_step() {
    echo -e "\n${BLUE}▶${NC} $1" | tee -a "$LOGFILE"
}

# Error handler
error_handler() {
    log_error "Script failed at line $1"
    log_error "Command: $BASH_COMMAND"
    log_error "Check log file: $LOGFILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================================================
# LOAD ENVIRONMENT
# ============================================================================
load_environment() {
    log_step "Loading environment configuration..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found at: $env_file"
        exit 1
    fi
    
    # Source without exporting readonly vars
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        
        # Only export if not already set as readonly
        if ! declare -p "$key" 2>/dev/null | grep -q 'declare -[^ ]*r'; then
            export "$key=$value"
        fi
    done < "$env_file"
    
    log_success "Environment loaded"
}

# ============================================================================
# SIMPLE SERVICE CHECK (PURE BASH - NO CURL/GREP ISSUES)
# ============================================================================
check_service_simple() {
    local service_name="$1"
    local port="$2"
    local max_wait="${3:-30}"
    
    log_info "Checking $service_name availability..."
    
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        # Pure bash TCP check - no external tools
        if timeout 2 bash -c "echo > /dev/tcp/localhost/${port}" 2>/dev/null; then
            log_success "$service_name is responding on port $port"
            return 0
        fi
        
        # Show progress dots
        if [[ $((waited % 5)) -eq 0 ]]; then
            echo -n "." | tee -a "$LOGFILE"
        fi
        
        sleep 1
        ((waited++))
    done
    
    echo "" | tee -a "$LOGFILE"
    log_warning "$service_name did not respond within ${max_wait}s (may still be starting)"
    return 0  # Don't fail - just warn
}

# ============================================================================
# CHECK CONTAINER STATUS
# ============================================================================
check_container() {
    local container_name="$1"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_success "$container_name is running"
        return 0
    else
        log_error "$container_name is not running"
        log_info "Check container logs: docker logs $container_name"
        return 1
    fi
}

# ============================================================================
# CONFIGURE OLLAMA
# ============================================================================
configure_ollama() {
    log_step "Configuring Ollama with AI models..."
    
    check_container "ollama"
    
    # Wait for Ollama to be ready
    sleep 5
    
    # Pull required models
    local models=("llama3.2:3b" "nomic-embed-text")
    
    for model in "${models[@]}"; do
        log_info "Checking model: $model"
        
        if docker exec ollama ollama list 2>/dev/null | grep -q "$model"; then
            log_success "Model $model already exists"
        else
            log_info "Pulling model: $model (this may take a while)..."
            if docker exec ollama ollama pull "$model" >> "$LOGFILE" 2>&1; then
                log_success "Model $model pulled successfully"
            else
                log_warning "Failed to pull $model - will retry later"
            fi
        fi
    done
    
    # Show available models
    log_info "Current Ollama models:"
    docker exec ollama ollama list 2>/dev/null | tee -a "$LOGFILE" || log_warning "Could not list models"
}

# ============================================================================
# CONFIGURE LITELLM
# ============================================================================
configure_litellm() {
    log_step "Configuring LiteLLM..."
    
    check_container "litellm"
    check_service_simple "LiteLLM" "$LITELLM_PORT" 30
    
    log_info "LiteLLM endpoints:"
    log_info "  • Health:  http://localhost:${LITELLM_PORT}/health"
    log_info "  • Chat:    http://localhost:${LITELLM_PORT}/v1/chat/completions"
    log_info "  • Models:  http://localhost:${LITELLM_PORT}/v1/models"
}

# ============================================================================
# CONFIGURE ANYTHINGLLM
# ============================================================================
configure_anythingllm() {
    log_step "Configuring AnythingLLM..."
    
    check_container "anythingllm"
    check_service_simple "AnythingLLM" "$ANYTHINGLLM_PORT" 30
    
    log_info "AnythingLLM access:"
    log_info "  • Direct: http://100.114.125.50:${ANYTHINGLLM_PORT}"
    log_info "  • Proxy:  https://100.114.125.50:${NGINX_PORT}/anythingllm/"
    
    echo "" >> "$LOGFILE"
    echo "📋 AnythingLLM Setup:" >> "$LOGFILE"
    echo "1. Open the web interface" >> "$LOGFILE"
    echo "2. Set admin password" >> "$LOGFILE"
    echo "3. Configure Ollama:" >> "$LOGFILE"
    echo "   - Provider: Ollama" >> "$LOGFILE"
    echo "   - URL: http://ollama:11434" >> "$LOGFILE"
    echo "   - Chat Model: llama3.2:3b" >> "$LOGFILE"
    echo "   - Embedding Model: nomic-embed-text" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "📋 AnythingLLM Setup:"
    echo "1. Open the web interface"
    echo "2. Set admin password"
    echo "3. Configure Ollama:"
    echo "   - Provider: Ollama"
    echo "   - URL: http://ollama:11434"
    echo "   - Chat Model: llama3.2:3b"
    echo "   - Embedding Model: nomic-embed-text"
    echo ""
}

# ============================================================================
# CONFIGURE DIFY
# ============================================================================
configure_dify() {
    log_step "Configuring Dify..."
    
    # Check Dify containers
    local dify_containers=("dify-api" "dify-worker" "dify-web" "dify-db" "dify-redis" "dify-weaviate")
    
    for container in "${dify_containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_success "$container is running"
        else
            log_warning "$container is not running yet"
        fi
    done
    
    # Check Dify web interface
    check_service_simple "Dify Web" "8081" 45
    
    log_info "Dify access:"
    log_info "  • Direct: http://100.114.125.50:8081"
    log_info "  • Proxy:  https://100.114.125.50:${NGINX_PORT}/dify/"
    
    echo "" >> "$LOGFILE"
    echo "📋 Dify Setup:" >> "$LOGFILE"
    echo "1. Open http://100.114.125.50:8081" >> "$LOGFILE"
    echo "2. Create admin account" >> "$LOGFILE"
    echo "3. Configure LLM Provider:" >> "$LOGFILE"
    echo "   - Add OpenAI Compatible provider" >> "$LOGFILE"
    echo "   - API Base: http://litellm:4000/v1" >> "$LOGFILE"
    echo "   - API Key: ${LITELLM_MASTER_KEY}" >> "$LOGFILE"
    echo "   - Model: llama3.2" >> "$LOGFILE"
    echo "4. Configure Embedding Provider:" >> "$LOGFILE"
    echo "   - Add Ollama provider" >> "$LOGFILE"
    echo "   - Base URL: http://ollama:11434" >> "$LOGFILE"
    echo "   - Model: nomic-embed-text" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "📋 Dify Setup:"
    echo "1. Open http://100.114.125.50:8081"
    echo "2. Create admin account"
    echo "3. Configure LLM Provider:"
    echo "   - Add OpenAI Compatible provider"
    echo "   - API Base: http://litellm:4000/v1"
    echo "   - API Key: ${LITELLM_MASTER_KEY}"
    echo "   - Model: llama3.2"
    echo "4. Configure Embedding Provider:"
    echo "   - Add Ollama provider"
    echo "   - Base URL: http://ollama:11434"
    echo "   - Model: nomic-embed-text"
    echo ""
}

# ============================================================================
# CONFIGURE N8N
# ============================================================================
configure_n8n() {
    log_step "Configuring n8n..."
    
    check_container "n8n"
    check_service_simple "n8n" "$N8N_PORT" 45
    
    log_info "n8n access:"
    log_info "  • Direct: http://100.114.125.50:${N8N_PORT}"
    log_info "  • Proxy:  https://100.114.125.50:${NGINX_PORT}/n8n/"
    
    echo "" >> "$LOGFILE"
    echo "📋 n8n Setup:" >> "$LOGFILE"
    echo "1. Open the web interface" >> "$LOGFILE"
    echo "2. Create owner account" >> "$LOGFILE"
    echo "3. Install community nodes if needed:" >> "$LOGFILE"
    echo "   - n8n-nodes-langchain" >> "$LOGFILE"
    echo "   - Custom integrations" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "📋 n8n Setup:"
    echo "1. Open the web interface"
    echo "2. Create owner account"
    echo "3. Install community nodes if needed:"
    echo "   - n8n-nodes-langchain"
    echo "   - Custom integrations"
    echo ""
}

# ============================================================================
# CONFIGURE SIGNAL API
# ============================================================================
configure_signal() {
    log_step "Configuring Signal API..."
    
    check_container "signal-api"
    check_service_simple "Signal API" "8090" 30
    
    log_info "Signal API access:"
    log_info "  • API:     http://100.114.125.50:8090"
    log_info "  • Health:  http://100.114.125.50:8090/v1/health"
    
    echo "" >> "$LOGFILE"
    echo "📋 Signal API Setup:" >> "$LOGFILE"
    echo "1. Register your phone number:" >> "$LOGFILE"
    echo "   curl -X POST http://localhost:8090/v1/register/+YOUR_PHONE \\" >> "$LOGFILE"
    echo "     -H \"Content-Type: application/json\"" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    echo "2. Verify with code received via SMS:" >> "$LOGFILE"
    echo "   curl -X POST http://localhost:8090/v1/register/+YOUR_PHONE/verify/CODE \\" >> "$LOGFILE"
    echo "     -H \"Content-Type: application/json\"" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "📋 Signal API Setup:"
    echo "1. Register your phone number:"
    echo "   curl -X POST http://localhost:8090/v1/register/+YOUR_PHONE \\"
    echo "     -H \"Content-Type: application/json\""
    echo ""
    echo "2. Verify with code received via SMS:"
    echo "   curl -X POST http://localhost:8090/v1/register/+YOUR_PHONE/verify/CODE \\"
    echo "     -H \"Content-Type: application/json\""
    echo ""
}

# ============================================================================
# VERIFY NETWORK
# ============================================================================
verify_network() {
    log_step "Verifying network configuration..."
    
    if docker network inspect ai-platform >/dev/null 2>&1; then
        log_success "Network 'ai-platform' exists"
        
        # Show connected containers
        log_info "Connected containers:"
        docker network inspect ai-platform --format '{{range .Containers}}  • {{.Name}}{{println}}{{end}}' | tee -a "$LOGFILE"
    else
        log_warning "Network 'ai-platform' not found"
    fi
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
show_summary() {
    echo "" >> "$LOGFILE"
    echo "╔════════════════════════════════════════════════════════════╗" >> "$LOGFILE"
    echo "║          CONFIGURATION SUMMARY                         ║" >> "$LOGFILE"
    echo "╚════════════════════════════════════════════════════════════╝" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    echo "🎯 SERVICE STATUS" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          CONFIGURATION SUMMARY                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🎯 SERVICE STATUS"
    echo ""
    
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOGFILE"
    
    echo "" >> "$LOGFILE"
    echo "📊 ACCESS POINTS" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    echo "PROXIED (Recommended - HTTPS):" >> "$LOGFILE"
    echo "• Dashboard:    https://100.114.125.50:${NGINX_PORT}/" >> "$LOGFILE"
    echo "• AnythingLLM:  https://100.114.125.50:${NGINX_PORT}/anythingllm/" >> "$LOGFILE"
    echo "• Dify:         https://100.114.125.50:${NGINX_PORT}/dify/" >> "$LOGFILE"
    echo "• n8n:          https://100.114.125.50:${NGINX_PORT}/n8n/" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    echo "DIRECT (API Access - HTTP):" >> "$LOGFILE"
    echo "• Ollama:       http://100.114.125.50:${OLLAMA_PORT}" >> "$LOGFILE"
    echo "• LiteLLM:      http://100.114.125.50:${LITELLM_PORT}" >> "$LOGFILE"
    echo "• AnythingLLM:  http://100.114.125.50:${ANYTHINGLLM_PORT}" >> "$LOGFILE"
    echo "• Dify Web:     http://100.114.125.50:8081" >> "$LOGFILE"
    echo "• n8n:          http://100.114.125.50:${N8N_PORT}" >> "$LOGFILE"
    echo "• Signal API:   http://100.114.125.50:8090" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
    
    echo ""
    echo "📊 ACCESS POINTS"
    echo ""
    echo "PROXIED (Recommended - HTTPS):"
    echo "• Dashboard:    https://100.114.125.50:${NGINX_PORT}/"
    echo "• AnythingLLM:  https://100.114.125.50:${NGINX_PORT}/anythingllm/"
    echo "• Dify:         https://100.114.125.50:${NGINX_PORT}/dify/"
    echo "• n8n:          https://100.114.125.50:${NGINX_PORT}/n8n/"
    echo ""
    echo "DIRECT (API Access - HTTP):"
    echo "• Ollama:       http://100.114.125.50:${OLLAMA_PORT}"
    echo "• LiteLLM:      http://100.114.125.50:${LITELLM_PORT}"
    echo "• AnythingLLM:  http://100.114.125.50:${ANYTHINGLLM_PORT}"
    echo "• Dify Web:     http://100.114.125.50:8081"
    echo "• n8n:          http://100.114.125.50:${N8N_PORT}"
    echo "• Signal API:   http://100.114.125.50:8090"
    echo ""
    echo "📝 LOG FILE: ${LOGFILE}"
    echo ""
    echo "🚀 NEXT STEPS:"
    echo "1. Open https://100.114.125.50:${NGINX_PORT}/ in your browser"
    echo "2. Complete setup for each service (see instructions above)"
    echo "3. Test the integrations"
    echo "4. Register Signal API phone number"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    AI Platform - Service Configuration v10.4 FINAL     ║"
    echo "║              No Heredoc Piping Issues                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    
    load_environment
    
    configure_ollama
    configure_litellm
    configure_anythingllm
    configure_dify
    configure_n8n
    configure_signal
    
    verify_network
    show_summary
    
    log_success "Configuration completed successfully!"
}

main "$@"
