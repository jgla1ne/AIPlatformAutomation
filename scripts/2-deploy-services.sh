#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - Service Deployment Script v8.2
# Deploys all services including Google Drive sync
# ============================================================================

readonly SCRIPT_VERSION="8.2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Icons
CHECK_MARK="✓"
CROSS_MARK="✗"
WARN_MARK="⚠"
INFO_MARK="ℹ"

success() { echo -e "${GREEN}${CHECK_MARK} $*${NC}"; }
error() { echo -e "${RED}${CROSS_MARK} $*${NC}"; }
warn() { echo -e "${YELLOW}${WARN_MARK} $*${NC}"; }
info() { echo -e "${BLUE}${INFO_MARK} $*${NC}"; }

# ============================================================================
# Display Banner
# ============================================================================

display_banner() {
    echo ""
    echo "========================================"
    echo "AI Platform - Service Deployment v${SCRIPT_VERSION}"
    echo "========================================"
    echo ""
}

# ============================================================================
# Load Environment
# ============================================================================

load_environment() {
    info "Loading environment configuration..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file"
        error "Please run 1-setup-system.sh first"
        exit 1
    fi
    
    set -a
    source "$env_file"
    set +a
    
    success "Environment loaded"
}

# ============================================================================
# Verify Docker Access
# ============================================================================

verify_docker_access() {
    info "Verifying Docker access..."
    
    if ! docker info &>/dev/null; then
        error "Cannot connect to Docker daemon"
        error "Please ensure Docker is running and you have proper permissions"
        exit 1
    fi
    
    success "Docker access verified"
}

# ============================================================================
# Preflight Checks
# ============================================================================

run_preflight_checks() {
    info "Running preflight checks..."
    
    local checks_passed=true
    
    # Check required directories
    local required_dirs=(
        "${DATA_DIR}/ollama"
        "${DATA_DIR}/litellm"
        "${DATA_DIR}/anythingllm"
        "${DATA_DIR}/clawdbot"
        "${DATA_DIR}/dify"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/signal"
        "${DATA_DIR}/gdrive"
        "${DATA_DIR}/nginx"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error "Required directory missing: $dir"
            checks_passed=false
        fi
    done
    
    # Check required environment variables
    local required_vars=(
        "OLLAMA_PORT"
        "LITELLM_PORT"
        "ANYTHINGLLM_PORT"
        "CLAWDBOT_PORT"
        "DIFY_WEB_PORT"
        "N8N_PORT"
        "SIGNAL_API_PORT"
        "GDRIVE_SYNC_DIR"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable missing: $var"
            checks_passed=false
        fi
    done
    
    if [[ "$checks_passed" == "false" ]]; then
        error "Preflight checks failed"
        exit 1
    fi
    
    success "Preflight checks passed"
}

# ============================================================================
# Network Creation
# ============================================================================

create_networks() {
    info "Creating Docker networks..."
    
    docker network create ai-platform 2>/dev/null || true
    
    success "Networks created"
}

# ============================================================================
# Helper Functions
# ============================================================================

wait_for_container() {
    local container_name=$1
    local max_wait=${2:-30}
    local count=0
    
    while [ $count -lt $max_wait ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
            if [ "$status" = "running" ]; then
                return 0
            fi
        fi
        echo -n "."
        sleep 2
        ((count+=2))
    done
    
    return 1
}

wait_for_health() {
    local container_name=$1
    local max_wait=${2:-60}
    local count=0
    
    while [ $count -lt $max_wait ]; do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
        
        if [ "$health" = "healthy" ]; then
            return 0
        elif [ "$health" = "none" ]; then
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((count+=2))
    done
    
    return 1
}

# ============================================================================
# Deploy Ollama
# ============================================================================

deploy_ollama() {
    info "[1/9] Deploying Ollama..."
    
    cat > "${STACKS_DIR}/ollama/docker-compose.yml" << EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST}:11434
    networks:
      - ai-platform
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/ollama"
    docker compose up -d
    
    if wait_for_container "ollama" 30; then
        success "Ollama deployed"
    else
        error "Ollama failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy LiteLLM
# ============================================================================

deploy_litellm() {
    info "[2/9] Deploying LiteLLM..."
    
    cat > "${DATA_DIR}/litellm/config.yaml" << EOF
model_list:
  - model_name: ollama/*
    litellm_params:
      model: ollama/*
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  success_callback: ["langfuse"]
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: null
EOF
    
    cat > "${STACKS_DIR}/litellm/docker-compose.yml" << EOF
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "${LITELLM_PORT}:4000"
    volumes:
      - ${DATA_DIR}/litellm/config.yaml:/app/config.yaml
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
    command: --config /app/config.yaml --port 4000 --num_workers 4
    networks:
      - ai-platform
    depends_on:
      - ollama

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/litellm"
    docker compose up -d
    
    if wait_for_container "litellm" 30; then
        success "LiteLLM deployed"
    else
        warn "LiteLLM may still be starting"
    fi
}

# ============================================================================
# Deploy AnythingLLM
# ============================================================================

deploy_anythingllm() {
    info "[3/9] Deploying AnythingLLM..."
    
    cat > "${STACKS_DIR}/anythingllm/docker-compose.yml" << EOF
version: '3.8'

services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    volumes:
      - ${ANYTHINGLLM_STORAGE_DIR}:/app/server/storage
      - ${DATA_DIR}/anythingllm/vector-cache:/app/server/storage/vector-cache
      - ${DATA_DIR}/gdrive/sync:/app/collector/hotdir/gdrive:ro
    environment:
      - STORAGE_DIR=/app/server/storage
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
      - VECTOR_DB=${ANYTHINGLLM_VECTOR_DB}
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - EMBEDDING_PROVIDER=ollama
      - EMBEDDING_MODEL_PREF=nomic-embed-text:latest
      - OLLAMA_EMBEDDING_BASE_PATH=http://ollama:11434
    networks:
      - ai-platform
    depends_on:
      - ollama
      - litellm

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/anythingllm"
    docker compose up -d
    
    if wait_for_container "anythingllm" 30; then
        success "AnythingLLM deployed"
    else
        error "AnythingLLM failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy Clawdbot
# ============================================================================

deploy_clawdbot() {
    info "[4/9] Deploying Clawdbot..."
    
    cat > "${DATA_DIR}/clawdbot/config.yml" << EOF
gateway:
  mode: local
  bind: lan
  port: 18789
  controlUi:
    enabled: true
    allowInsecureAuth: true
  auth:
    mode: token
    token: ${CLAWDBOT_SECRET}

agents:
  defaults:
    workspace: /root/clawd
    llm:
      provider: litellm
      baseUrl: http://litellm:4000
      apiKey: ${LITELLM_MASTER_KEY}
      model: ollama/qwen2.5:latest

signal:
  enabled: true
  apiUrl: http://signal-api:8080
  number: ${CLAWDBOT_SIGNAL_NUMBER}
  adminNumbers: ${CLAWDBOT_ADMIN_NUMBERS}
EOF
    
    cat > "${STACKS_DIR}/clawdbot/docker-compose.yml" << EOF
version: '3.8'

services:
  clawdbot:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: clawdbot
    restart: unless-stopped
    ports:
      - "${CLAWDBOT_PORT}:18789"
    volumes:
      - ${DATA_DIR}/clawdbot:/root/clawd
      - ${DATA_DIR}/clawdbot/config.yml:/root/.config/clawdbot/config.yml
      - ${DATA_DIR}/anythingllm/storage:/vectordb:ro
      - ${DATA_DIR}/gdrive/sync:/gdrive:ro
    environment:
      - CLAWD_CONFIG=/root/.config/clawdbot/config.yml
    networks:
      - ai-platform
    depends_on:
      - litellm
      - anythingllm

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/clawdbot"
    docker compose up -d
    
    if wait_for_container "clawdbot" 30; then
        success "Clawdbot deployed"
    else
        error "Clawdbot failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy Dify
# ============================================================================

deploy_dify() {
    info "[5/9] Deploying Dify platform..."
    
    cat > "${STACKS_DIR}/dify/.env" << EOF
# Application
SECRET_KEY=${DIFY_SECRET_KEY}
CONSOLE_API_URL=http://localhost:${DIFY_API_PORT}
CONSOLE_WEB_URL=http://localhost:${DIFY_WEB_PORT}
SERVICE_API_URL=http://localhost:${DIFY_API_PORT}
APP_WEB_URL=http://localhost:${DIFY_WEB_PORT}

# Database
DB_USERNAME=${DIFY_DB_USER}
DB_PASSWORD=${DIFY_DB_PASSWORD}
DB_HOST=dify-db
DB_PORT=5432
DB_DATABASE=${DIFY_DB_NAME}

# Redis
REDIS_HOST=dify-redis
REDIS_PORT=6379
REDIS_PASSWORD=${DIFY_REDIS_PASSWORD}
REDIS_USE_SSL=false
REDIS_DB=0

# Storage
STORAGE_TYPE=local
STORAGE_LOCAL_PATH=/app/api/storage

# Vector Store
VECTOR_STORE=weaviate
WEAVIATE_ENDPOINT=http://weaviate:8080
WEAVIATE_API_KEY=WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih

# LLM
OLLAMA_API_BASE_URL=http://ollama:11434
EOF
    
    cat > "${STACKS_DIR}/dify/docker-compose.yml" << EOF
version: '3.8'

services:
  dify-db:
    image: postgres:15-alpine
    container_name: dify-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DIFY_DB_USER}
      POSTGRES_PASSWORD: ${DIFY_DB_PASSWORD}
      POSTGRES_DB: ${DIFY_DB_NAME}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/dify/postgres:/var/lib/postgresql/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DIFY_DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  dify-redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --requirepass ${DIFY_REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/dify/redis:/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: dify-weaviate
    restart: unless-stopped
    environment:
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: 'WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      QUERY_DEFAULTS_LIMIT: 25
      DEFAULT_VECTORIZER_MODULE: 'none'
      CLUSTER_HOSTNAME: 'node1'
    volumes:
      - ${DATA_DIR}/dify/weaviate:/var/lib/weaviate
    networks:
      - ai-platform

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ${DATA_DIR}/dify/api:/app/api/storage
      - ${DATA_DIR}/gdrive/sync:/app/api/storage/gdrive:ro
    networks:
      - ai-platform
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy
      weaviate:
        condition: service_started

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    env_file:
      - .env
    command: celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail
    volumes:
      - ${DATA_DIR}/dify/api:/app/api/storage
    networks:
      - ai-platform
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    ports:
      - "${DIFY_WEB_PORT}:3000"
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    networks:
      - ai-platform
    depends_on:
      - dify-api

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/dify"
    docker compose up -d
    
    info "Waiting for Dify services..."
    sleep 15
    
    if wait_for_container "dify-web" 30; then
        success "Dify deployed"
    else
        warn "Dify may still be initializing"
    fi
}

# ============================================================================
# Deploy n8n
# ============================================================================

deploy_n8n() {
    info "[6/9] Deploying n8n..."
    
    cat > "${STACKS_DIR}/n8n/docker-compose.yml" << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
      - ${DATA_DIR}/gdrive/sync:/files/gdrive:ro
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_PATH=/n8n/
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - GENERIC_TIMEZONE=America/New_York
    networks:
      - ai-platform
    depends_on:
      - ollama
      - litellm

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/n8n"
    docker compose up -d
    
    if wait_for_container "n8n" 30; then
        success "n8n deployed"
    else
        error "n8n failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy Signal API
# ============================================================================

deploy_signal() {
    info "[7/9] Deploying Signal API..."
    
    cat > "${STACKS_DIR}/signal/docker-compose.yml" << EOF
version: '3.8'

services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    ports:
      - "${SIGNAL_API_PORT}:8080"
    volumes:
      - ${DATA_DIR}/signal:/home/.local/share/signal-cli
    environment:
      - MODE=json-rpc
      - AUTO_RECEIVE_SCHEDULE=${SIGNAL_AUTO_RECEIVE}
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/signal"
    docker compose up -d
    
    if wait_for_container "signal-api" 30; then
        success "Signal API deployed"
    else
        error "Signal API failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy Google Drive Sync
# ============================================================================

deploy_gdrive() {
    info "[8/9] Deploying Google Drive sync..."
    
    cat > "${STACKS_DIR}/gdrive/docker-compose.yml" << EOF
version: '3.8'

services:
  gdrive-sync:
    image: controlol/gdrive-rclone-docker:latest
    container_name: gdrive-sync
    restart: unless-stopped
    volumes:
      - ${GDRIVE_CONFIG_DIR}:/config
      - ${GDRIVE_SYNC_DIR}:/data
      - ${GDRIVE_LOG_DIR}:/logs
    environment:
      - RCLONE_CONFIG=/config/rclone.conf
      - SYNC_INTERVAL=${GDRIVE_SYNC_INTERVAL}
      - RCLONE_CONFIG_PASS=${GDRIVE_RCLONE_CONFIG_PASS}
      - SYNC_SRC=${GDRIVE_REMOTE_NAME}:${GDRIVE_REMOTE_PATH}
      - SYNC_DEST=/data
      - TZ=America/New_York
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/fuse
    security_opt:
      - apparmor:unconfined
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/gdrive"
    docker compose up -d
    
    if wait_for_container "gdrive-sync" 30; then
        success "Google Drive sync deployed"
        warn "You need to configure Google Drive access"
        info "Run: ${SCRIPT_DIR}/configure-gdrive.sh"
    else
        error "Google Drive sync failed to start"
        return 1
    fi
}

# ============================================================================
# Deploy NGINX
# ============================================================================

deploy_nginx() {
    info "[9/9] Deploying NGINX reverse proxy..."
    
    cat > "${DATA_DIR}/nginx/conf.d/default.conf" << 'EOF'
# Upstream definitions
upstream anythingllm {
    server anythingllm:3001;
}

upstream clawdbot {
    server clawdbot:18789;
}

upstream dify {
    server dify-web:3000;
}

upstream n8n {
    server n8n:5678;
}

upstream ollama {
    server ollama:11434;
}

upstream litellm {
    server litellm:4000;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name _;
    
    return 301 https://$host$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name _;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    client_max_body_size 500M;
    
    # AnythingLLM
    location /anythingllm/ {
        proxy_pass http://anythingllm/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # Clawdbot
    location /clawdbot/ {
        proxy_pass http://clawdbot/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # Dify
    location /dify/ {
        proxy_pass http://dify/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # n8n
    location /n8n/ {
        proxy_pass http://n8n/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
    
    # Ollama
    location /ollama/ {
        proxy_pass http://ollama/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # LiteLLM
    location /litellm/ {
        proxy_pass http://litellm/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Root redirect
    location = / {
        return 302 /anythingllm/;
    }
}
EOF
    
    cat > "${STACKS_DIR}/nginx/docker-compose.yml" << EOF
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "${NGINX_HTTP_PORT}:80"
      - "${NGINX_HTTPS_PORT}:443"
    volumes:
      - ${DATA_DIR}/nginx/conf.d:/etc/nginx/conf.d:ro
      - ${DATA_DIR}/nginx/ssl:/etc/nginx/ssl:ro
    networks:
      - ai-platform
    depends_on:
      - anythingllm
      - clawdbot
      - dify-web
      - n8n
      - ollama
      - litellm

networks:
  ai-platform:
    external: true
EOF
    
    cd "${STACKS_DIR}/nginx"
    docker compose up -d
    
    if wait_for_container "nginx" 20; then
        success "NGINX deployed"
    else
        error "NGINX failed to start"
        return 1
    fi
}

# ============================================================================
# Configure Tailscale Serve
# ============================================================================

configure_tailscale_serve() {
    info "[10/10] Configuring Tailscale HTTPS serve..."
    
    # Wait for NGINX to be fully ready
    sleep 5
    
    # Check if Tailscale is running
    if ! tailscale status &>/dev/null; then
        warn "Tailscale not running. Skipping serve configuration."
        warn "Run manually: sudo tailscale serve https:8443 / https://127.0.0.1:443"
        return 1
    fi
    
    # Configure Tailscale to serve HTTPS on port 8443
    info "Setting up Tailscale serve on port 8443..."
    
    if sudo tailscale serve https:8443 / https://127.0.0.1:443; then
        success "Tailscale serve configured on port 8443"
        
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4)
        
        echo ""
        success "Services accessible via Tailscale:"
        echo "  https://${tailscale_ip}:8443/anythingllm"
        echo "  https://${tailscale_ip}:8443/clawdbot"
        echo "  https://${tailscale_ip}:8443/dify"
        echo "  https://${tailscale_ip}:8443/n8n"
        echo ""
    else
        warn "Could not configure Tailscale serve automatically"
        warn "Run manually: sudo tailscale serve https:8443 / https://127.0.0.1:443"
    fi
}

# ============================================================================
# Display Summary
# ============================================================================

display_summary() {
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           DEPLOYMENT COMPLETED SUCCESSFULLY!              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "All services deployed successfully!"
    echo ""
    
    info "═══════════════════════════════════════════════════════════"
    info "SERVICE STATUS"
    info "═══════════════════════════════════════════════════════════"
    
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "network=ai-platform"
    
    echo ""
    info "═══════════════════════════════════════════════════════════"
    info "ACCESS URLS (via Tailscale)"
    info "═══════════════════════════════════════════════════════════"
    echo "  • AnythingLLM:    https://${tailscale_ip}:8443/anythingllm"
    echo "  • Clawdbot:       https://${tailscale_ip}:8443/clawdbot"
    echo "  • Dify:           https://${tailscale_ip}:8443/dify"
    echo "  • n8n:            https://${tailscale_ip}:8443/n8n"
    echo "  • Ollama:         http://${tailscale_ip}:11434"
    echo "  • LiteLLM:        http://${tailscale_ip}:4000"
    echo ""
    
    info "═══════════════════════════════════════════════════════════"
    info "NEXT STEPS"
    info "═══════════════════════════════════════════════════════════"
    echo "  1. Configure Google Drive:"
    echo "     ${SCRIPT_DIR}/configure-gdrive.sh"
    echo ""
    echo "  2. Link Signal device:"
    echo "     ${SCRIPT_DIR}/link-signal-device.sh"
    echo ""
    echo "  3. Download Ollama models:"
    echo "     docker exec -it ollama ollama pull qwen2.5:latest"
    echo "     docker exec -it ollama ollama pull nomic-embed-text:latest"
    echo ""
    
    info "═══════════════════════════════════════════════════════════"
    info "GOOGLE DRIVE SYNC"
    info "═══════════════════════════════════════════════════════════"
    echo "  • Sync directory: ${GDRIVE_SYNC_DIR}"
    echo "  • Mounted in AnythingLLM: /app/collector/hotdir/gdrive"
    echo "  • Mounted in Clawdbot: /gdrive"
    echo "  • Mounted in Dify: /app/api/storage/gdrive"
    echo "  • Mounted in n8n: /files/gdrive"
    echo ""
    
    info "═══════════════════════════════════════════════════════════"
    info "TROUBLESHOOTING"
    info "═══════════════════════════════════════════════════════════"
    echo "  • View logs:      docker logs -f <container-name>"
    echo "  • Check status:   docker ps -a"
    echo "  • Restart:        docker restart <container-name>"
    echo "  • Clean up:       ${SCRIPT_DIR}/0-complete-cleanup.sh"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    display_banner
    
    load_environment
    verify_docker_access
    
    run_preflight_checks
    create_networks
    
    deploy_ollama
    deploy_litellm
    deploy_anythingllm
    deploy_clawdbot
    deploy_dify
    deploy_n8n
    deploy_signal
    deploy_gdrive
    deploy_nginx
    
    configure_tailscale_serve
    
    display_summary
}

main "$@"

