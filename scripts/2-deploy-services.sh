#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Deploy Services Script
# Version: 7.0 - MOLTBOT COMPLETE INTEGRATION
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
LOGFILE="${LOGS_DIR}/deploy-${TIMESTAMP}.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "\n${BLUE}[$1]${NC} $2" | tee -a "$LOGFILE"; }

error_handler() {
    log_error "Deployment failed at line $1"
    log_error "Check log: $LOGFILE"
    log_info "Run 'docker compose logs' to view service logs"
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
        log_error "Run ./1-setup-system.sh first"
        exit 1
    fi
    
    if [[ ! -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found"
        log_error "Run ./1-setup-system.sh first"
        exit 1
    fi
    
    source "${PROJECT_ROOT}/.env"
    log_success "Environment loaded"
    log_info "Network: ${NETWORK_NAME}"
}

# ============================================================================
# PULL IMAGES
# ============================================================================
pull_images() {
    log_step "2/6" "Pulling Docker images..."
    
    cd "$PROJECT_ROOT"
    
    local images=(
        "ollama/ollama:latest"
        "ghcr.io/berriai/litellm:main-latest"
        "mintplexlabs/anythingllm:latest"
        "postgres:15-alpine"
        "redis:7-alpine"
        "semitechnologies/weaviate:1.19.0"
        "langgenius/dify-api:latest"
        "langgenius/dify-web:latest"
        "n8nio/n8n:latest"
        "bbernhard/signal-cli-rest-api:latest"
        "moltbot/moltbot:latest"
        "rclone/rclone:latest"
        "nginx:alpine"
    )
    
    log_info "Pulling ${#images[@]} Docker images..."
    echo ""
    
    for image in "${images[@]}"; do
        log_info "Pulling ${image}..."
        if docker pull "$image" &>> "$LOGFILE"; then
            log_success "${image} ✓"
        else
            log_error "Failed to pull ${image}"
            exit 1
        fi
    done
    
    echo ""
    log_success "All images pulled successfully"
}

# ============================================================================
# START CORE SERVICES
# ============================================================================
start_core_services() {
    log_step "3/6" "Starting core infrastructure..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Starting databases..."
    docker compose up -d dify-db dify-redis dify-weaviate
    
    log_info "Waiting for databases to initialize (30s)..."
    for i in {1..30}; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    # Verify database health
    log_info "Verifying database health..."
    
    if docker exec dify-db pg_isready -U ${POSTGRES_USER} &>> "$LOGFILE"; then
        log_success "PostgreSQL ready"
    else
        log_warning "PostgreSQL still initializing..."
    fi
    
    if docker exec dify-redis redis-cli --no-auth-warning -a ${REDIS_PASSWORD} ping &>> "$LOGFILE"; then
        log_success "Redis ready"
    else
        log_warning "Redis still initializing..."
    fi
    
    log_success "Core infrastructure started"
}

# ============================================================================
# START AI SERVICES
# ============================================================================
start_ai_services() {
    log_step "4/6" "Starting AI services..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Starting Ollama..."
    docker compose up -d ollama
    sleep 15
    
    log_info "Starting LiteLLM..."
    docker compose up -d litellm
    sleep 15
    
    log_info "Starting AnythingLLM..."
    docker compose up -d anythingllm
    sleep 10
    
    log_success "AI services started"
}

# ============================================================================
# START APPLICATION SERVICES
# ============================================================================
start_app_services() {
    log_step "5/6" "Starting application services..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Starting Dify backend..."
    docker compose up -d dify-api dify-worker
    sleep 15
    
    log_info "Starting Dify frontend..."
    docker compose up -d dify-web
    sleep 10
    
    log_info "Starting n8n..."
    docker compose up -d n8n
    sleep 10
    
    log_info "Starting Signal API..."
    docker compose up -d signal-api
    sleep 10
    
    log_info "Starting ClawdBot (Moltbot)..."
    docker compose up -d clawdbot
    sleep 10
    
    log_info "Starting Google Drive sync..."
    docker compose up -d gdrive-sync
    sleep 5
    
    log_success "Application services started"
}

# ============================================================================
# START NGINX
# ============================================================================
start_nginx() {
    log_step "6/6" "Starting NGINX reverse proxy..."
    
    cd "$PROJECT_ROOT"
    
    log_info "Waiting for all services to be ready (20s)..."
    for i in {1..20}; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    log_info "Starting NGINX..."
    docker compose up -d nginx
    sleep 5
    
    log_success "NGINX started"
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================
verify_deployment() {
    echo ""
    log_info "Verifying deployment..."
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Show container status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # Check service health
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Service Health Checks:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    check_service_health "ollama" "11434" "/api/tags"
    check_service_health "litellm" "4000" "/health"
    check_service_health "anythingllm" "3001" "/api/ping"
    check_service_health "dify-web" "3000" "/"
    check_service_health "dify-api" "5001" "/health"
    check_service_health "n8n" "5678" "/healthz"
    check_service_health "signal-api" "8080" "/v1/health"
    check_service_health "clawdbot" "18789" "/health"
    check_service_health "nginx" "443" "/"
    
    echo ""
}

check_service_health() {
    local service=$1
    local port=$2
    local path=$3
    
    if docker exec "$service" wget --quiet --tries=1 --spider "http://localhost:${port}${path}" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${service} (port ${port}) - responding"
    else
        echo -e "  ${YELLOW}⚠${NC} ${service} (port ${port}) - starting up..."
    fi
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
show_summary() {
    source "${PROJECT_ROOT}/.env"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    log_success "✅ DEPLOYMENT COMPLETED SUCCESSFULLY!" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "🌐 ACCESS URLS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  Dashboard:     https://${TAILSCALE_IP}:${NGINX_PORT}/" | tee -a "$LOGFILE"
    echo "  AnythingLLM:   https://${TAILSCALE_IP}:${NGINX_PORT}/anythingllm/" | tee -a "$LOGFILE"
    echo "  Dify:          https://${TAILSCALE_IP}:${NGINX_PORT}/dify/" | tee -a "$LOGFILE"
    echo "  n8n:           https://${TAILSCALE_IP}:${NGINX_PORT}/n8n/" | tee -a "$LOGFILE"
    echo "  Signal:        https://${TAILSCALE_IP}:${NGINX_PORT}/signal/" | tee -a "$LOGFILE"
    echo "  ClawdBot:      http://${TAILSCALE_IP}:18789/" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "🔑 IMPORTANT CREDENTIALS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  LiteLLM Master Key:       ${LITELLM_MASTER_KEY}" | tee -a "$LOGFILE"
    echo "  ClawdBot Gateway Token:   ${CLAWDBOT_GATEWAY_TOKEN}" | tee -a "$LOGFILE"
    echo "  Database Password:        ${POSTGRES_PASSWORD}" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    echo "  💾 Saved in: ${PROJECT_ROOT}/.env" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "📋 NEXT STEPS:" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "  1. Configure services:  ./3-configure-services.sh" | tee -a "$LOGFILE"
    echo "  2. View logs:           docker compose logs -f [service]" | tee -a "$LOGFILE"
    echo "  3. Check status:        docker compose ps" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    log_info "📝 Deployment log: ${LOGFILE}" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║        AI Platform - Deploy Services v7                ║
║          MOLTBOT COMPLETE INTEGRATION                  ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    echo "Started: $(date)" | tee -a "$LOGFILE"
    echo ""
    
    check_environment
    pull_images
    start_core_services
    start_ai_services
    start_app_services
    start_nginx
    
    sleep 5
    verify_deployment
    show_summary
    
    log_success "Deployment completed at: $(date)" | tee -a "$LOGFILE"
}

main "$@"

