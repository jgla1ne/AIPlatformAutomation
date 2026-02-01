#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Deployment Script
# Version: 11.0 FINAL - ALL SERVICES INCLUDED
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/deploy-${TIMESTAMP}.log"

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
        log_error ".env file not found. Run 1-generate-configs.sh first!"
        exit 1
    fi
    
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
    
    log_success "Environment loaded"
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================
preflight_checks() {
    log_step "Running preflight checks..."
    
    # Check Docker
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        exit 1
    fi
    log_success "Docker is running"
    
    # Check docker-compose file
    if [[ ! -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found. Run 1-generate-configs.sh first!"
        exit 1
    fi
    log_success "docker-compose.yml found"
    
    # Check data directories
    if [[ ! -d "${PROJECT_ROOT}/data" ]]; then
        log_error "Data directory not found"
        exit 1
    fi
    log_success "Data directory exists"
    
    # GPU check (optional)
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        log_success "GPU support available"
        export GPU_AVAILABLE=true
    else
        log_warning "Running in CPU-only mode"
        export GPU_AVAILABLE=false
    fi
}

# ============================================================================
# STOP EXISTING SERVICES
# ============================================================================
stop_existing_services() {
    log_step "Stopping existing services..."
    
    cd "$PROJECT_ROOT"
    
    if docker compose ps --quiet 2>/dev/null | grep -q .; then
        log_info "Stopping running containers..."
        docker compose down --remove-orphans >> "$LOGFILE" 2>&1
        log_success "Existing services stopped"
    else
        log_info "No running services found"
    fi
}

# ============================================================================
# PULL IMAGES
# ============================================================================
pull_images() {
    log_step "Pulling Docker images..."
    
    cd "$PROJECT_ROOT"
    
    log_info "This may take several minutes..."
    docker compose pull >> "$LOGFILE" 2>&1
    
    log_success "Docker images pulled"
}

# ============================================================================
# BUILD CUSTOM IMAGES
# ============================================================================
build_custom_images() {
    log_step "Building custom images..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Building ClawdBot..."
    docker compose build clawdbot >> "$LOGFILE" 2>&1
    
    log_success "Custom images built"
}

# ============================================================================
# START SERVICES
# ============================================================================
start_services() {
    log_step "Starting services..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Starting infrastructure services..."
    docker compose up -d nginx dify-db dify-redis dify-weaviate >> "$LOGFILE" 2>&1
    sleep 10
    
    log_info "Starting AI services..."
    docker compose up -d ollama litellm >> "$LOGFILE" 2>&1
    sleep 10
    
    log_info "Starting application services..."
    docker compose up -d anythingllm dify-api dify-worker dify-web n8n >> "$LOGFILE" 2>&1
    sleep 10
    
    log_info "Starting messaging services..."
    docker compose up -d signal-api clawdbot >> "$LOGFILE" 2>&1
    sleep 5
    
    log_info "Starting sync services..."
    docker compose up -d gdrive-sync >> "$LOGFILE" 2>&1 || log_warning "gdrive-sync needs configuration"
    
    log_success "All services started"
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================
verify_deployment() {
    log_step "Verifying deployment..."
    
    local max_wait=120
    local elapsed=0
    
    log_info "Waiting for services to be healthy (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        local total_count=0
        
        while IFS= read -r line; do
            ((total_count++))
            if echo "$line" | grep -q "(healthy)"; then
                ((healthy_count++))
            fi
        done < <(docker compose ps --format "{{.Name}} {{.Status}}")
        
        if [[ $total_count -gt 0 ]]; then
            log_info "Healthy services: ${healthy_count}/${total_count}"
            
            if [[ $healthy_count -ge 8 ]]; then
                log_success "Services are healthy"
                return 0
            fi
        fi
        
        sleep 10
        ((elapsed+=10))
    done
    
    log_warning "Some services may still be starting up"
}

# ============================================================================
# SETUP OLLAMA MODELS
# ============================================================================
setup_ollama_models() {
    log_step "Setting up Ollama models..."
    
    log_info "Pulling llama3.2:3b..."
    docker exec ollama ollama pull llama3.2:3b >> "$LOGFILE" 2>&1
    
    log_info "Pulling nomic-embed-text..."
    docker exec ollama ollama pull nomic-embed-text >> "$LOGFILE" 2>&1
    
    log_success "Ollama models ready"
}

# ============================================================================
# SHOW STATUS
# ============================================================================
show_status() {
    log_step "Deployment Status"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              CONTAINER STATUS                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              ACCESS POINTS                              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 WEB INTERFACES (HTTPS - Proxied):"
    echo "   Dashboard:    https://${TAILSCALE_IP}:${NGINX_PORT}/"
    echo "   AnythingLLM:  https://${TAILSCALE_IP}:${NGINX_PORT}/anythingllm/"
    echo "   Dify:         https://${TAILSCALE_IP}:${NGINX_PORT}/dify/"
    echo "   n8n:          https://${TAILSCALE_IP}:${NGINX_PORT}/n8n/"
    echo "   ClawdBot:     https://${TAILSCALE_IP}:${NGINX_PORT}/clawdbot/"
    echo "   Signal API:   https://${TAILSCALE_IP}:${NGINX_PORT}/signal/"
    echo ""
    echo "🔌 API ENDPOINTS (HTTP - Direct):"
    echo "   Ollama:       http://${TAILSCALE_IP}:${OLLAMA_PORT}"
    echo "   LiteLLM:      http://${TAILSCALE_IP}:${LITELLM_PORT}"
    echo "   AnythingLLM:  http://${TAILSCALE_IP}:${ANYTHINGLLM_PORT}"
    echo "   Dify Web:     http://${TAILSCALE_IP}:${DIFY_WEB_PORT}"
    echo "   n8n:          http://${TAILSCALE_IP}:${N8N_PORT}"
    echo "   Signal:       http://${TAILSCALE_IP}:${SIGNAL_PORT}"
    echo "   ClawdBot:     http://${TAILSCALE_IP}:${CLAWDBOT_PORT}"
    echo ""
    echo "📝 LOG FILE: ${LOGFILE}"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║      AI Platform - Service Deployment v11 FINAL        ║
║            All Services Included                       ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    load_environment
    preflight_checks
    stop_existing_services
    pull_images
    build_custom_images
    start_services
    verify_deployment
    setup_ollama_models
    show_status
    
    echo ""
    log_success "Deployment completed successfully!"
    echo ""
    log_info "🚀 Next step: Run ./3-configure-services.sh"
    echo ""
}

main "$@" 2>&1 | tee -a "$LOGFILE"
