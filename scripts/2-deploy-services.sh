#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - Service Deployment Script v6.1
# ============================================================================

readonly SCRIPT_VERSION="6.1"

# ============================================================================
# Utility Functions (defined before loading environment)
# ============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Icons
CHECK_MARK="✓"
CROSS_MARK="✗"
INFO_MARK="ℹ"
WARN_MARK="⚠"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo -e "${GREEN}${CHECK_MARK} $*${NC}"
}

error() {
    echo -e "${RED}${CROSS_MARK} $*${NC}"
}

warn() {
    echo -e "${YELLOW}${WARN_MARK} $*${NC}"
}

info() {
    echo -e "${BLUE}${INFO_MARK} $*${NC}"
}

command_exists() {
    command -v "$1" &> /dev/null
}

wait_for_service() {
    local service_name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    info "Waiting for $service_name to be ready..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            success "$service_name is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    warn "$service_name did not become ready in time"
    return 1
}

# ============================================================================
# Load Environment (without readonly conflicts)
# ============================================================================

load_environment() {
    info "[0/8] Loading environment..."
    
    # Determine paths
    local detected_project_root="${HOME}/AIPlatformAutomation"
    local detected_env_file="${detected_project_root}/.env"
    
    if [[ ! -f "$detected_env_file" ]]; then
        error "Environment file not found: $detected_env_file"
        error "Please run 1-setup-system.sh first"
        exit 1
    fi
    
    # Load environment file
    set -a
    source "$detected_env_file"
    set +a
    
    # Set derived variables (using values from .env)
    LOG_DIR="${PROJECT_ROOT}/logs"
    LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
    
    # Create log directory if needed
    mkdir -p "$LOG_DIR"
    
    # Verify critical variables
    local required_vars=(
        "PROJECT_ROOT"
        "STACKS_DIR"
        "DATA_DIR"
        "LITELLM_MASTER_KEY"
        "DIFY_SECRET_KEY"
        "GPU_AVAILABLE"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required variables: ${missing_vars[*]}"
        error "Please run 1-setup-system.sh to regenerate .env"
        exit 1
    fi
    
    success "Environment loaded"
}

# ============================================================================
# Script Permissions
# ============================================================================

ensure_script_permissions() {
    info "[0/8] Ensuring script permissions..."
    
    if [[ -d "$SCRIPT_DIR" ]]; then
        chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
        success "All scripts are executable"
    fi
}

# ============================================================================
# Preflight Checks
# ============================================================================

preflight_checks() {
    info "[1/8] Running preflight checks..."
    
    # Check Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running"
        exit 1
    fi
    success "Docker running"
    
    # Check Docker access
    if ! docker ps > /dev/null 2>&1; then
        error "Cannot access Docker - you may need to log out and back in"
        error "Or run: newgrp docker"
        exit 1
    fi
    success "Docker access verified"
    
    # Check data directory
    if [[ ! -d "$DATA_DIR" ]]; then
        error "Data directory does not exist: $DATA_DIR"
        exit 1
    fi
    success "Data directory exists"
    
    # Check compose files exist
    local compose_files=(
        "${STACKS_DIR}/litellm-compose.yml"
        "${STACKS_DIR}/ollama-compose.yml"
        "${STACKS_DIR}/dify-compose.yml"
        "${STACKS_DIR}/n8n-compose.yml"
        "${STACKS_DIR}/signal-compose.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [[ ! -f "$compose_file" ]]; then
            error "Compose file missing: $compose_file"
            error "Please run 1-setup-system.sh first"
            exit 1
        fi
    done
    success "All compose files exist"
    
    # GPU check
    if [[ "${GPU_AVAILABLE}" == "true" ]]; then
        success "GPU detected and will be used"
    else
        warn "Running in CPU-only mode"
    fi
}

# ============================================================================
# Network Setup
# ============================================================================

setup_networks() {
    info "[2/8] Creating Docker networks..."
    
    # Create main network
    if ! docker network inspect ai-platform-network > /dev/null 2>&1; then
        docker network create ai-platform-network
    fi
    
    success "Networks ready"
}

# ============================================================================
# Service Deployment Functions
# ============================================================================

deploy_litellm() {
    info "[4/8] Deploying LiteLLM proxy..."
    
    docker-compose \
        --env-file "$ENV_FILE" \
        -f "${STACKS_DIR}/litellm-compose.yml" \
        up -d --remove-orphans
    
    success "LiteLLM deployed on port ${LITELLM_PORT:-4000}"
}

deploy_ollama() {
    info "[5/8] Deploying Ollama..."
    
    if [[ "${GPU_AVAILABLE}" == "true" ]]; then
        docker-compose \
            --env-file "$ENV_FILE" \
            -f "${STACKS_DIR}/ollama-compose.yml" \
            --profile gpu \
            up -d --remove-orphans
    else
        # CPU-only deployment (remove GPU requirements)
        docker run -d \
            --name ollama \
            --restart unless-stopped \
            -p "${OLLAMA_PORT:-11434}:11434" \
            -v "${DATA_DIR}/ollama:/root/.ollama" \
            -e OLLAMA_HOST=0.0.0.0 \
            --network ai-platform-network \
            ollama/ollama:latest
    fi
    
    success "Ollama deployed on port ${OLLAMA_PORT:-11434}"
}

deploy_dify() {
    info "[6/8] Deploying Dify platform..."
    
    docker-compose \
        --env-file "$ENV_FILE" \
        -f "${STACKS_DIR}/dify-compose.yml" \
        up -d --remove-orphans
    
    success "Dify deployed on port ${DIFY_WEB_PORT:-3000}"
}

deploy_n8n() {
    info "[7/8] Deploying n8n workflow automation..."
    
    docker-compose \
        --env-file "$ENV_FILE" \
        -f "${STACKS_DIR}/n8n-compose.yml" \
        up -d --remove-orphans
    
    success "n8n deployed on port ${N8N_PORT:-5678}"
}

deploy_signal() {
    info "[8/8] Deploying Signal API..."
    
    docker-compose \
        --env-file "$ENV_FILE" \
        -f "${STACKS_DIR}/signal-compose.yml" \
        up -d --remove-orphans
    
    success "Signal API deployed on port ${SIGNAL_API_PORT:-8080}"
}

# ============================================================================
# Verification
# ============================================================================

verify_deployment() {
    info "Verifying deployment..."
    
    echo ""
    echo "Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(litellm|ollama|dify|n8n|signal)" || true
    
    echo ""
    info "Checking service health..."
    
    # Give services time to start
    sleep 5
    
    # Check LiteLLM
    if wait_for_service "LiteLLM" "http://localhost:${LITELLM_PORT:-4000}/health" 10; then
        success "LiteLLM is healthy"
    fi
    
    # Check Ollama
    if wait_for_service "Ollama" "http://localhost:${OLLAMA_PORT:-11434}" 10; then
        success "Ollama is healthy"
    fi
    
    # Check Dify (may take longer)
    if wait_for_service "Dify" "http://localhost:${DIFY_WEB_PORT:-3000}" 30; then
        success "Dify is healthy"
    fi
    
    echo ""
    success "Deployment verification complete"
}

# ============================================================================
# Display Access Information
# ============================================================================

display_access_info() {
    echo ""
    echo "========================================"
    echo "Deployment Complete!"
    echo "========================================"
    echo ""
    echo "Service URLs (localhost):"
    echo "  • LiteLLM Proxy:  http://localhost:${LITELLM_PORT:-4000}"
    echo "  • Ollama:         http://localhost:${OLLAMA_PORT:-11434}"
    echo "  • Dify Platform:  http://localhost:${DIFY_WEB_PORT:-3000}"
    echo "  • n8n Workflows:  http://localhost:${N8N_PORT:-5678}"
    echo "  • Signal API:     http://localhost:${SIGNAL_API_PORT:-8080}"
    
    if [[ -n "${TAILSCALE_IP:-}" && "${TAILSCALE_IP}" != "127.0.0.1" ]]; then
        echo ""
        echo "Tailscale URLs:"
        echo "  • LiteLLM:  http://${TAILSCALE_IP}:${LITELLM_PORT:-4000}"
        echo "  • Dify:     http://${TAILSCALE_IP}:${DIFY_WEB_PORT:-3000}"
        echo "  • n8n:      http://${TAILSCALE_IP}:${N8N_PORT:-5678}"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "  1. Access Dify at http://localhost:${DIFY_WEB_PORT:-3000}"
    echo "  2. Create your admin account"
    echo "  3. Pull Ollama models: docker exec ollama ollama pull llama3.2"
    echo "  4. Configure LiteLLM to use Ollama"
    echo ""
    echo "Logs: $LOG_FILE"
    echo "========================================"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "AI Platform - Service Deployment v${SCRIPT_VERSION}"
    echo "========================================"
    echo ""
    
    # Load environment FIRST (before setting readonly variables)
    load_environment
    
    info "Location: $PROJECT_ROOT"
    info "Started: $(date)"
    
    ensure_script_permissions
    preflight_checks
    setup_networks
    
    info "[3/8] Using existing compose files"
    success "All compose files ready"
    
    deploy_litellm
    deploy_ollama
    deploy_dify
    deploy_n8n
    deploy_signal
    
    verify_deployment
    display_access_info
    
    success "Deployment complete!"
    info "Log file: $LOG_FILE"
}

main "$@"
