#!/usr/bin/env bash

#==============================================================================
# Script: 2-deploy-platform.sh
# Description: Deploy AI Platform services based on Script 1 configuration
# Version: 4.0.0 - Complete Deployment Implementation
# Purpose: Generate docker-compose services and deploy containers
# Flow: 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add-service
#
# CHANGELOG v4.0.0:
# - Complete rewrite from skeleton to functional deployment
# - Reads configuration from Script 1's .env file
# - Generates complete docker-compose.yml with actual services
# - Deploys services in tiered approach (infrastructure → AI → optional)
# - Implements health checks and wait logic
# - Provides access URLs on completion
#==============================================================================

set -euo pipefail

#==============================================================================
# SCRIPT LOCATION & USER DETECTION
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect real user (works with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="${SUDO_USER}"
    REAL_UID=$(id -u "${SUDO_USER}")
    REAL_GID=$(id -g "${SUDO_USER}")
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_USER="${USER}"
    REAL_UID=$(id -u)
    REAL_GID=$(id -g)
    REAL_HOME="${HOME}"
fi

#==============================================================================
# GLOBAL CONFIGURATION
#==============================================================================

# Must match Script 1
BASE_DIR="/opt/ai-platform"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOGS_DIR="${BASE_DIR}/logs"
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

# Logging
LOGFILE="${LOGS_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="${LOGS_DIR}/deploy-errors-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    local msg="$1"
    echo -e "${BLUE}ℹ${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}⚠${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$LOGFILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$ERROR_LOG" 2>/dev/null || true
}

log_phase() {
    local phase="$1"
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${phase}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PHASE: ${phase}" >> "$LOGFILE" 2>/dev/null || true
}

#==============================================================================
# BANNER
#==============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}          ${MAGENTA}AI PLATFORM AUTOMATION - DEPLOYMENT${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                      ${YELLOW}Version 4.0.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#==============================================================================
# PHASE 1: PREFLIGHT CHECKS
#==============================================================================

preflight_checks() {
    log_phase "PHASE 1: Preflight Checks"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at ${ENV_FILE}"
        log_error "Please run ./1-setup-system.sh first"
        exit 1
    fi
    
    log_success ".env file found"
    
    # Source the .env file
    log_info "Loading configuration from .env file..."
    set -a  # automatically export all variables
    source "$ENV_FILE"
    set +a
    
    log_success "Configuration loaded"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please run ./1-setup-system.sh first"
        exit 1
    fi
    
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon not running"
        exit 1
    fi
    
    log_success "Docker is running"
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose not found"
        exit 1
    fi
    
    log_success "Docker Compose available"
    
    # Check if Ollama is running (if enabled)
    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        if ! systemctl is-active --quiet ollama 2>/dev/null; then
            log_error "Ollama service not running but ENABLE_OLLAMA=true"
            log_error "Please run ./1-setup-system.sh to install Ollama"
            exit 1
        fi
        
        if ! curl -sf http://localhost:11434/api/tags &> /dev/null; then
            log_error "Ollama API not responding on port 11434"
            exit 1
        fi
        
        log_success "Ollama is running and responding"
    fi
    
    # Display configuration summary
    echo ""
    echo "Configuration Summary:"
    echo "  • Domain: ${BASE_DOMAIN}"
    echo "  • SSL: $([ "${USE_LETSENCRYPT}" = "true" ] && echo "Let's Encrypt" || echo "Self-signed")"
    echo "  • Hardware: ${HARDWARE_TYPE}"
    [ "${ENABLE_OLLAMA}" = "true" ] && echo "  • Ollama: Enabled"
    [ "${ENABLE_LITELLM}" = "true" ] && echo "  • LiteLLM: Enabled"
    [ "${ENABLE_OPENWEBUI}" = "true" ] && echo "  • Open WebUI: Enabled"
    [ "${ENABLE_DIFY}" = "true" ] && echo "  • Dify: Enabled"
    [ "${ENABLE_N8N}" = "true" ] && echo "  • n8n: Enabled"
    echo ""
    
    read -p "Proceed with deployment? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

#==============================================================================
# PHASE 2: GENERATE DOCKER COMPOSE FILE
#==============================================================================

generate_compose_file() {
    log_phase "PHASE 2: Generating Docker Compose Configuration"
    
    log_info "Creating docker-compose.yml with selected services..."
    
    # Start with base structure
    cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

networks:
  ai-platform:
    name: ai-platform
    external: true
  ai-platform-internal:
    name: ai-platform-internal
    external: true
  ai-platform-monitoring:
    name: ai-platform-monitoring
    external: true

volumes:
  postgres_data:
    name: aiplatform-postgres
  redis_data:
    name: aiplatform-redis
  ollama_data:
    name: aiplatform-ollama

services:

EOF

    # Add PostgreSQL (needed for LiteLLM or Dify)
    if [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  postgres:
    image: postgres:16-alpine
    container_name: aiplatform-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - ai-platform-internal
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=postgres"

EOF
    fi

    # Add Redis (needed for LiteLLM, Dify, n8n)
    if [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ] || [ "${ENABLE_N8N}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  redis:
    image: redis:7-alpine
    container_name: aiplatform-redis
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - ai-platform-internal
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 5s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=redis"

EOF
    fi

    # Add LiteLLM
    if [ "${ENABLE_LITELLM}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: aiplatform-litellm
    env_file:
      - ${BASE_DIR}/.env
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "4000:4000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "8"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=litellm"

EOF
    fi

    # Add Open WebUI
    if [ "${ENABLE_OPENWEBUI}" = "true" ]; then
        # Determine backend URL
        local backend_url="http://localhost:11434"
        if [ "${ENABLE_LITELLM}" = "true" ]; then
            backend_url="http://litellm:4000"
        fi
        
        cat >> "$COMPOSE_FILE" <<EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: aiplatform-openwebui
    environment:
      - OLLAMA_BASE_URL=${backend_url}
      - WEBUI_AUTH=false
      - WEBUI_NAME=AI Platform
    volumes:
      - ${DATA_DIR}/open-webui:/app/backend/data
    networks:
      - ai-platform
$([ "${ENABLE_LITELLM}" = "true" ] && echo "      - ai-platform-internal")
    ports:
      - "8080:8080"
$([ "${ENABLE_LITELLM}" = "true" ] && echo "    depends_on:
      litellm:
        condition: service_healthy")
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=open-webui"

EOF
    fi

    # Add Qdrant (vector database)
    if [ "${ENABLE_QDRANT}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  qdrant:
    image: qdrant/qdrant:latest
    container_name: aiplatform-qdrant
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
    networks:
      - ai-platform-internal
    ports:
      - "6333:6333"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=qdrant"

EOF
    fi

    # Add n8n
    if [ "${ENABLE_N8N}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  n8n:
    image: n8nio/n8n:latest
    container_name: aiplatform-n8n
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${ADMIN_PASSWORD}
      - N8N_HOST=${BASE_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://${BASE_DOMAIN}:5678/
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "5678:5678"
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=n8n"

EOF
    fi

    # Add Dify (if enabled)
    if [ "${ENABLE_DIFY}" = "true" ]; then
        # Dify requires multiple services
        cat >> "$COMPOSE_FILE" <<'EOF'
  # Dify API
  dify-api:
    image: langgenius/dify-api:latest
    container_name: aiplatform-dify-api
    env_file:
      - ${BASE_DIR}/.env
    environment:
      - MODE=api
      - SECRET_KEY=${ENCRYPTION_KEY}
      - DB_USERNAME=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${POSTGRES_DB}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    networks:
      - ai-platform-internal
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=dify-api"

  # Dify Worker
  dify-worker:
    image: langgenius/dify-api:latest
    container_name: aiplatform-dify-worker
    env_file:
      - ${BASE_DIR}/.env
    environment:
      - MODE=worker
      - SECRET_KEY=${ENCRYPTION_KEY}
      - DB_USERNAME=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${POSTGRES_DB}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    networks:
      - ai-platform-internal
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=dify-worker"

  # Dify Web
  dify-web:
    image: langgenius/dify-web:latest
    container_name: aiplatform-dify-web
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "3000:3000"
    depends_on:
      - dify-api
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=dify-web"

EOF
    fi

    # Add monitoring stack (if enabled)
    if [ "${ENABLE_MONITORING}" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: aiplatform-prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ${CONFIG_DIR}/prometheus:/etc/prometheus
      - ${DATA_DIR}/prometheus:/prometheus
    networks:
      - ai-platform-monitoring
    ports:
      - "9090:9090"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=prometheus"

  # Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: aiplatform-grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=
    volumes:
      - ${DATA_DIR}/grafana:/var/lib/grafana
    networks:
      - ai-platform
      - ai-platform-monitoring
    ports:
      - "3001:3000"
    depends_on:
      - prometheus
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=grafana"

EOF
    fi

    chmod 644 "$COMPOSE_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$COMPOSE_FILE"
    
    log_success "Docker Compose file generated: ${COMPOSE_FILE}"
}

#==============================================================================
# PHASE 3: DEPLOY INFRASTRUCTURE TIER
#==============================================================================

deploy_infrastructure() {
    log_phase "PHASE 3: Deploying Infrastructure Services"
    
    local services=()
    
    # Determine which infrastructure services to deploy
    if [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ]; then
        services+=("postgres")
    fi
    
    if [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ] || [ "${ENABLE_N8N}" = "true" ]; then
        services+=("redis")
    fi
    
    if [ ${#services[@]} -eq 0 ]; then
        log_info "No infrastructure services needed - skipping"
        return 0
    fi
    
    log_info "Deploying infrastructure: ${services[*]}"
    
    cd "$BASE_DIR"
    docker compose up -d "${services[@]}"
    
    # Wait for services to be healthy
    log_info "Waiting for infrastructure services to be healthy..."
    for service in "${services[@]}"; do
        wait_for_healthy "$service"
    done
    
    log_success "Infrastructure services deployed and healthy"
}

#==============================================================================
# PHASE 4: DEPLOY AI SERVICES
#==============================================================================

deploy_ai_services() {
    log_phase "PHASE 4: Deploying AI Services"
    
    local services=()
    
    # Determine which AI services to deploy
    [ "${ENABLE_LITELLM}" = "true" ] && services+=("litellm")
    [ "${ENABLE_OPENWEBUI}" = "true" ] && services+=("open-webui")
    [ "${ENABLE_QDRANT}" = "true" ] && services+=("qdrant")
    
    if [ ${#services[@]} -eq 0 ]; then
        log_info "No AI services selected - skipping"
        return 0
    fi
    
    log_info "Deploying AI services: ${services[*]}"
    
    cd "$BASE_DIR"
    docker compose up -d "${services[@]}"
    
    # Wait for services to be healthy
    log_info "Waiting for AI services to be healthy..."
    for service in "${services[@]}"; do
        wait_for_healthy "$service"
    done
    
    log_success "AI services deployed and healthy"
}

#==============================================================================
# PHASE 5: DEPLOY OPTIONAL SERVICES
#==============================================================================

deploy_optional_services() {
    log_phase "PHASE 5: Deploying Optional Services"
    
    local services=()
    
    # Determine which optional services to deploy
    [ "${ENABLE_N8N}" = "true" ] && services+=("n8n")
    [ "${ENABLE_DIFY}" = "true" ] && services+=("dify-api" "dify-worker" "dify-web")
    
    if [ ${#services[@]} -eq 0 ]; then
        log_info "No optional services selected - skipping"
        return 0
    fi
    
    log_info "Deploying optional services: ${services[*]}"
    
    cd "$BASE_DIR"
    docker compose up -d "${services[@]}"
    
    # Wait for services
    log_info "Waiting for optional services to start..."
    sleep 10
    
    log_success "Optional services deployed"
}

#==============================================================================
# PHASE 6: DEPLOY MONITORING
#==============================================================================

deploy_monitoring() {
    log_phase "PHASE 6: Deploying Monitoring Stack"
    
    if [ "${ENABLE_MONITORING}" != "true" ]; then
        log_info "Monitoring not enabled - skipping"
        return 0
    fi
    
    log_info "Deploying monitoring: prometheus grafana"
    
    cd "$BASE_DIR"
    docker compose up -d prometheus grafana
    
    # Wait for services
    log_info "Waiting for monitoring services to start..."
    sleep 10
    
    log_success "Monitoring stack deployed"
}

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

wait_for_healthy() {
    local service="$1"
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for ${service} to be healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "aiplatform-${service}" 2>/dev/null || echo "none")
        
        if [ "$health_status" = "healthy" ]; then
            log_success "${service} is healthy"
            return 0
        elif [ "$health_status" = "none" ]; then
            # Service doesn't have healthcheck, just check if it's running
            if docker ps --filter "name=aiplatform-${service}" --filter "status=running" | grep -q "${service}"; then
                log_success "${service} is running"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "${service}: attempt ${attempt}/${max_attempts}..."
        fi
        sleep 2
    done
    
    log_error "${service} did not become healthy after ${max_attempts} attempts"
    log_error "Check logs: docker logs aiplatform-${service}"
    return 1
}

#==============================================================================
# VERIFICATION
#==============================================================================

verify_deployment() {
    log_phase "VERIFICATION: Deployment Status"
    
    local errors=0
    
    echo "▶ Checking deployed services..."
    
    # Get all ai-platform containers
    local containers
    containers=$(docker ps --filter "label=ai-platform=true" --format "{{.Names}}" | sort)
    
    if [ -z "$containers" ]; then
        log_error "No AI Platform containers found running"
        errors=$((errors + 1))
    else
        echo ""
        echo "Running containers:"
        for container in $containers; do
            local status
            status=$(docker inspect --format='{{.State.Status}}' "$container")
            
            if [ "$status" = "running" ]; then
                log_success "$container"
            else
                log_error "$container (status: $status)"
                errors=$((errors + 1))
            fi
        done
        echo ""
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All services are running!"
        return 0
    else
        log_error "Deployment verification failed with ${errors} error(s)"
        return 1
    fi
}

#==============================================================================
# SUMMARY
#==============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${GREEN}✓ DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Deployment Summary"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "  Base URL: http://${BASE_DOMAIN}"
    echo ""
    echo "  Service Access URLs:"
    
    [ "${ENABLE_OLLAMA}" = "true" ] && echo "    • Ollama API:    http://localhost:11434"
    [ "${ENABLE_LITELLM}" = "true" ] && echo "    • LiteLLM API:   http://localhost:4000"
    [ "${ENABLE_OPENWEBUI}" = "true" ] && echo "    • Open WebUI:    http://localhost:8080"
    [ "${ENABLE_N8N}" = "true" ] && echo "    • n8n:           http://localhost:5678 (admin/${ADMIN_PASSWORD})"
    [ "${ENABLE_DIFY}" = "true" ] && echo "    • Dify:          http://localhost:3000"
    [ "${ENABLE_QDRANT}" = "true" ] && echo "    • Qdrant:        http://localhost:6333"
    [ "${ENABLE_MONITORING}" = "true" ] && echo "    • Grafana:       http://localhost:3001 (admin/${ADMIN_PASSWORD})"
    [ "${ENABLE_MONITORING}" = "true" ] && echo "    • Prometheus:    http://localhost:9090"
    
    echo ""
    echo "  Database Access:"
    [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ] && echo "    • PostgreSQL:    localhost:5432 (user: ${POSTGRES_USER})"
    [ "${ENABLE_LITELLM}" = "true" ] || [ "${ENABLE_DIFY}" = "true" ] || [ "${ENABLE_N8N}" = "true" ] && echo "    • Redis:         localhost:6379"
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "🚀 Next Steps:"
    echo ""
    echo "  1. Test Ollama (if enabled):"
    echo "     curl http://localhost:11434/api/tags"
    echo ""
    echo "  2. Test LiteLLM (if enabled):"
    echo "     curl http://localhost:4000/health"
    echo ""
    echo "  3. Access Open WebUI:"
    echo "     Open http://localhost:8080 in your browser"
    echo ""
    echo "  4. Configure services:"
    echo "     sudo ./3-configure-services.sh"
    echo ""
    echo "  5. View container logs:"
    echo "     docker compose -f ${COMPOSE_FILE} logs -f [service-name]"
    echo ""
    echo "  6. View all running services:"
    echo "     docker ps --filter label=ai-platform=true"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "📄 Important Commands:"
    echo "  • Stop all services:    cd ${BASE_DIR} && docker compose down"
    echo "  • Restart services:     cd ${BASE_DIR} && docker compose restart"
    echo "  • View logs:            cd ${BASE_DIR} && docker compose logs -f"
    echo "  • Check status:         docker ps --filter label=ai-platform=true"
    echo ""
    echo "📝 Log Files:"
    echo "  • Deployment log: ${LOGFILE}"
    echo "  • Error log:      ${ERROR_LOG}"
    echo ""
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    print_banner
    
    # Create log directory if needed
    mkdir -p "$LOGS_DIR"
    
    log_info "Starting AI Platform Deployment v4.0.0"
    log_info "Executed by: ${REAL_USER} (UID: ${REAL_UID})"
    
    # Execute deployment phases
    preflight_checks
    generate_compose_file
    deploy_infrastructure
    deploy_ai_services
    deploy_optional_services
    deploy_monitoring
    
    # Verification
    if verify_deployment; then
        print_summary
        
        log_success "Deployment completed successfully!"
        echo ""
        echo "You can now proceed with service configuration:"
        echo "  sudo ./3-configure-services.sh"
        echo ""
        exit 0
    else
        log_error "Deployment completed with errors - please review logs"
        echo ""
        echo "Log files:"
        echo "  • Full log: ${LOGFILE}"
        echo "  • Errors: ${ERROR_LOG}"
        echo ""
        echo "Troubleshooting:"
        echo "  • Check service logs: docker logs [container-name]"
        echo "  • View all containers: docker ps -a --filter label=ai-platform=true"
        echo ""
        exit 1
    fi
}

# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Run main function
main "$@"
