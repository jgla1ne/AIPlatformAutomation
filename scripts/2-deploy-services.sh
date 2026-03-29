#!/usr/bin/env bash
# =============================================================================
# Script 2: Deployment Engine Only - BULLETPROOF v4.2
# PURPOSE: Deploy services from .env configuration only
# USAGE:   sudo bash scripts/2-deploy-services.sh
# =============================================================================

set -euo pipefail
trap 'error_handler $LINENO' ERR

# Script Directory and Repository Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# Logging Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Error Handler
error_handler() {
    local exit_code=$?
    local line=$1
    echo ""
    echo -e "${RED}[ERROR]${NC} Script failed at line $line with exit code $exit_code"
    exit $exit_code
}

# --------------------------------------------------------------------------
# Load .env
# --------------------------------------------------------------------------
load_env() {
    # GUARD: Ensure Script 1 ran first
    if [[ ! -f "$ENV_FILE" ]]; then
        echo ""
        echo "  ERROR: .env not found - run Script 1 first"
        echo ""
        echo "  Run: bash scripts/1-setup-system.sh"
        echo ""
        exit 1
    fi
    
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    log "Loaded .env from $ENV_FILE"
    
    # Validate critical vars
    : "${MNT_BASE:?MNT_BASE not set in .env}"
    : "${BIFROST_SUBNET:?BIFROST_SUBNET not set in .env}"
    : "${BIFROST_GATEWAY:?BIFROST_GATEWAY not set in .env}"
    : "${BIFROST_MTU:?BIFROST_MTU not set in .env}"
}

# --------------------------------------------------------------------------
# Create Bifrost Network (idempotent)
# --------------------------------------------------------------------------
create_bifrost_network() {
    section "Creating Bifrost Network"
    
    if docker network ls --format '{{.Name}}' | grep -q "^bifrost$"; then
        log "Bifrost network already exists"
        
        # Validate existing network matches config
        local existing_subnet
        existing_subnet=$(docker network inspect bifrost \
            --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")
        
        if [[ "$existing_subnet" != "$BIFROST_SUBNET" ]]; then
            warn "Existing bifrost subnet ($existing_subnet) differs from config ($BIFROST_SUBNET)"
            warn "Run Script 0 to clean up, then re-run"
        else
            log "Bifrost network config matches: subnet=$existing_subnet"
        fi
        return 0
    fi
    
    log "Creating bifrost network..."
    log "  Subnet : $BIFROST_SUBNET"
    log "  Gateway: $BIFROST_GATEWAY"
    log "  MTU    : $BIFROST_MTU"
    
    docker network create \
        --driver bridge \
        --subnet "$BIFROST_SUBNET" \
        --gateway "$BIFROST_GATEWAY" \
        --opt "com.docker.network.driver.mtu=$BIFROST_MTU" \
        --label "ai-platform=true" \
        bifrost
    
    log "Bifrost network created ✓"
}

# --------------------------------------------------------------------------
# Wait for service health
# --------------------------------------------------------------------------
wait_for_healthy() {
    local container="$1"
    local max_wait="${2:-120}"
    local interval=5
    local elapsed=0
    
    log "Waiting for $container to be healthy (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
        
        case "$status" in
            "healthy")
                log "$container is healthy ✓"
                return 0
                ;;
            "unhealthy")
                warn "$container is unhealthy! Checking logs..."
                docker logs --tail=20 "$container" 2>&1 || true
                return 1
                ;;
            "not_found")
                # Container may not have healthcheck — check if running
                local running
                running=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "false")
                if [[ "$running" == "true" ]]; then
                    log "$container is running (no healthcheck defined)"
                    return 0
                fi
                ;;
            *)
                # starting or unknown
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log "  Waiting... ${elapsed}s / ${max_wait}s (status: $status)"
    done
    
    warn "$container did not become healthy within ${max_wait}s"
    return 1
}

# --------------------------------------------------------------------------
# Generate docker-compose.yml
# --------------------------------------------------------------------------
generate_compose() {
    section "Generating docker-compose.yml"
    
    local compose_file="${MNT_BASE}/docker-compose.yml"
    
    # Build GPU section for Ollama
    local ollama_deploy_section=""
    if [[ "$OLLAMA_RUNTIME" == "nvidia" ]]; then
        ollama_deploy_section='
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]'
    elif [[ "$OLLAMA_RUNTIME" == "amd" ]]; then
        ollama_deploy_section='
    devices:
      - /dev/kfd
      - /dev/dri'
    fi

    cat > "$compose_file" << COMPOSE_EOF
# =============================================================================
# AI Platform — Docker Compose
# Generated by Script 2 on $(date)
# DO NOT EDIT MANUALLY
# =============================================================================

networks:
  bifrost:
    external: true
    name: bifrost

# All volumes stored under ${MNT_BASE}/data/
volumes:
  portainer_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/portainer
    labels:
      ai-platform: "true"

  ollama_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/ollama
    labels:
      ai-platform: "true"

  open_webui_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/open-webui
    labels:
      ai-platform: "true"

  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/postgres
    labels:
      ai-platform: "true"

  redis_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/redis
    labels:
      ai-platform: "true"

  n8n_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/n8n
    labels:
      ai-platform: "true"

  searxng_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/searxng
    labels:
      ai-platform: "true"

  flowise_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MNT_BASE}/data/flowise
    labels:
      ai-platform: "true"

services:

  # ── Portainer — Mission Control ────────────────────────────────────────────
  portainer:
    image: portainer/portainer-ce:latest
    container_name: ${PORTAINER_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
      service: "mission-control"
    security_opt:
      - no-new-privileges:true
    ports:
      - "${PORTAINER_HTTP_PORT}:8000"
      - "${PORTAINER_PORT}:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "https://localhost:9443", "--no-check-certificate"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  # ── PostgreSQL — Shared Database ───────────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    container_name: ${POSTGRES_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT}:5432"
    networks:
      - bifrost
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  # ── Redis — Cache Layer ────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: ${REDIS_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --appendfilename appendonly.aof
      --save 60 1
      --loglevel warning
    volumes:
      - redis_data:/data
    ports:
      - "${REDIS_PORT}:6379"
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s

  # ── Ollama — LLM Engine ────────────────────────────────────────────────────
  ollama:
    image: ollama/ollama:latest
    container_name: ${OLLAMA_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - bifrost
    environment:
      OLLAMA_HOST: 0.0.0.0
      OLLAMA_KEEP_ALIVE: -1
      OLLAMA_NUM_PARALLEL: 2
      OLLAMA_MAX_QUEUE: 512${ollama_deploy_section}
    healthcheck:
      test: ["CMD", "sh", "-c", "exec 3<>/dev/tcp/localhost/11434"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

  # ── Open WebUI ─────────────────────────────────────────────────────────────
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${OPEN_WEBUI_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    ports:
      - "${OPEN_WEBUI_PORT}:8080"
    volumes:
      - open_webui_data:/app/backend/data
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  # ── n8n ────────────────────────────────────────────────────────────────
  n8n:
    image: n8nio/n8n:latest
    container_name: ${N8N_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    environment:
      N8N_BASIC_AUTH_ACTIVE: "false"
      N8N_HOST: "0.0.0.0"
      N8N_PORT: "5678"
      N8N_PROTOCOL: "http"
      WEBHOOK_URL: "${N8N_WEBHOOK_URL}"
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: "postgresdb"
      DB_POSTGRESDB_HOST: ${POSTGRES_CONTAINER_NAME}
      DB_POSTGRESDB_PORT: "5432"
      DB_POSTGRESDB_DATABASE: ${N8N_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_URL: "redis://:${REDIS_PASSWORD}@${REDIS_CONTAINER_NAME}:6379/0"
    volumes:
      - n8n_data:/home/node/.n8n
    ports:
      - "${N8N_PORT}:5678"
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  # ── SearXNG ────────────────────────────────────────────────────────────
  searxng:
    image: searxng/searxng:latest
    container_name: ${SEARXNG_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    volumes:
      - searxng_data:/etc/searxng
    ports:
      - "${SEARXNG_PORT}:8080"
    networks:
      - bifrost
    environment:
      SEARXNG_BASE_URL: "http://${SEARXNG_CONTAINER_NAME}:8080"
      SEARXNG_SECRET_KEY: ${SEARXNG_SECRET_KEY}
      REDIS_URL: "redis://:${REDIS_PASSWORD}@${REDIS_CONTAINER_NAME}:6379/0"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  # ── Flowise ────────────────────────────────────────────────────────────
  flowise:
    image: flowiseai/flowise:latest
    container_name: ${FLOWISE_CONTAINER_NAME}
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    environment:
      FLOWISE_USERNAME: ${FLOWISE_USERNAME}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      FLOWISE_SECRETKEY: ${FLOWISE_SECRET_KEY:-${FLOWISE_PASSWORD}}
      DATABASE_TYPE: "postgres"
      DATABASE_HOST: ${POSTGRES_CONTAINER_NAME}
      DATABASE_PORT: "5432"
      DATABASE_NAME: ${FLOWISE_DB}
      DATABASE_USER: ${POSTGRES_USER}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - flowise_data:/storage
    ports:
      - "${FLOWISE_PORT}:3000"
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  # ── Nginx (optional) ───────────────────────────────────────────────────
EOF

    # Add Nginx service if enabled
    if [[ "$ENABLE_NGINX" == "true" ]]; then
        cat >> "$compose_file" << NGINX_EOF

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    labels:
      ai-platform: "true"
    security_opt:
      - no-new-privileges:true
    ports:
      - "${NGINX_HTTP_PORT}:80"
      - "${NGINX_HTTPS_PORT}:443"
    volumes:
      - ${MNT_BASE}/configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - bifrost
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
NGINX_EOF
    fi

    log "docker-compose.yml generated at: $compose_file"
}

# --------------------------------------------------------------------------
# Initialize PostgreSQL databases
# --------------------------------------------------------------------------
init_postgres_databases() {
    section "Initializing PostgreSQL Databases"
    
    # Wait for PostgreSQL to be ready
    wait_for_healthy "${POSTGRES_CONTAINER_NAME}" 60
    
    # Create n8n database
    log "Creating n8n database..."
    docker exec "${POSTGRES_CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d postgres -c \
        "CREATE DATABASE ${N8N_DB};" 2>/dev/null || log "n8n database already exists"
    
    # Create Flowise database
    log "Creating Flowise database..."
    docker exec "${POSTGRES_CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d postgres -c \
        "CREATE DATABASE ${FLOWISE_DB};" 2>/dev/null || log "Flowise database already exists"
    
    log "PostgreSQL databases initialized ✓"
}

# --------------------------------------------------------------------------
# Pull Ollama model
# --------------------------------------------------------------------------
pull_ollama_model() {
    [[ "$OLLAMA_PULL_DEFAULT_MODEL" != "true" ]] && return
    
    [[ -z "$OLLAMA_DEFAULT_MODEL" ]] && return
    
    section "Pulling Ollama Model"
    
    # Wait for Ollama to be ready
    wait_for_healthy "${OLLAMA_CONTAINER_NAME}" 120
    
    log "Pulling model: $OLLAMA_DEFAULT_MODEL"
    if docker exec "${OLLAMA_CONTAINER_NAME}" ollama pull "$OLLAMA_DEFAULT_MODEL"; then
        log "Model $OLLAMA_DEFAULT_MODEL pulled successfully ✓"
    else
        warn "Failed to pull model $OLLAMA_DEFAULT_MODEL"
    fi
}

# --------------------------------------------------------------------------
# Deploy stack
# --------------------------------------------------------------------------
deploy_stack() {
    section "Deploying Service Stack"
    
    log "Starting services in dependency order..."
    
    # Phase 1: Infrastructure services
    log "Phase 1: Deploying infrastructure services..."
    docker compose -f "${MNT_BASE}/docker-compose.yml" up -d postgres redis
    wait_for_healthy "${POSTGRES_CONTAINER_NAME}" 60
    wait_for_healthy "${REDIS_CONTAINER_NAME}" 30
    
    # Initialize databases after PostgreSQL is healthy
    init_postgres_databases
    
    # Phase 2: Mission Control
    log "Phase 2: Deploying Mission Control..."
    docker compose -f "${MNT_BASE}/docker-compose.yml" up -d portainer
    wait_for_healthy "${PORTAINER_CONTAINER_NAME}" 90
    
    # Phase 3: Core AI services
    log "Phase 3: Deploying core AI services..."
    docker compose -f "${MNT_BASE}/docker-compose.yml" up -d ollama
    wait_for_healthy "${OLLAMA_CONTAINER_NAME}" 120
    
    docker compose -f "${MNT_BASE}/docker-compose.yml" up -d open-webui
    wait_for_healthy "${OPEN_WEBUI_CONTAINER_NAME}" 60
    
    # Phase 4: Application services (parallel)
    log "Phase 4: Deploying application services..."
    docker compose -f "${MNT_BASE}/docker-compose.yml" up -d searxng n8n flowise
    
    # Wait for all app services with shorter timeout
    for service in searxng n8n flowise; do
        wait_for_healthy "$service" 60 || warn "$service failed health check"
    done
    
    # Phase 5: Nginx (if enabled)
    if [[ "$ENABLE_NGINX" == "true" ]]; then
        log "Phase 5: Deploying Nginx reverse proxy..."
        docker compose -f "${MNT_BASE}/docker-compose.yml" up -d nginx
        wait_for_healthy nginx 60
    fi
    
    log "Service deployment completed ✓"
}

# --------------------------------------------------------------------------
# Print status
# --------------------------------------------------------------------------
print_status() {
    section "Deployment Status"
    
    echo ""
    echo "  Service Endpoints:"
    echo "  ┌──────────────────┬──────────────────────────────────────────┐"
    echo "  │ Service          │ URL                                      │"
    echo "  ├──────────────────┼──────────────────────────────────────────┤"
    printf "  │ %-16s │ %-40s │\n" "Mission Control" "https://${HOST_IP}:${PORTAINER_PORT}"
    printf "  │ %-16s │ %-40s │\n" "Ollama API" "http://${HOST_IP}:${OLLAMA_PORT}"
    printf "  │ %-16s │ %-40s │\n" "Open WebUI" "http://${HOST_IP}:${OPEN_WEBUI_PORT}"
    printf "  │ %-16s │ %-40s │\n" "n8n" "http://${HOST_IP}:${N8N_PORT}"
    printf "  │ %-16s │ %-40s │\n" "SearXNG" "http://${HOST_IP}:${SEARXNG_PORT}"
    printf "  │ %-16s │ %-40s │\n" "Flowise" "http://${HOST_IP}:${FLOWISE_PORT}"
    [[ "$ENABLE_NGINX" == "true" ]] && \
    printf "  │ %-16s │ %-40s │\n" "Nginx" "http://${HOST_IP}:${NGINX_HTTP_PORT}"
    echo "  └──────────────────┴──────────────────────────────────────────┘"
    echo ""
    echo "  Next step:"
    echo "  bash scripts/3-configure-services.sh"
    echo ""
}

# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------
main() {
    log "=== Script 2: Deployment Engine ==="
    
    load_env
    create_bifrost_network
    generate_compose
    deploy_stack
    pull_ollama_model
    print_status
}

main "$@"
