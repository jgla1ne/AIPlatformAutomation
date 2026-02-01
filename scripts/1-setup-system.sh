#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - System Setup Script
# Version: 19.0 - COMPLETE MOLTBOT INTEGRATION
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/setup-${TIMESTAMP}.log"

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
    log_error "Setup failed at line $1"
    log_error "Check log: $LOGFILE"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ============================================================================
# CHECK PREREQUISITES
# ============================================================================
check_prerequisites() {
    log_step "1/13" "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ============================================================================
# CLEAN OLD NETWORKS
# ============================================================================
clean_old_networks() {
    log_step "2/13" "Cleaning old Docker networks..."
    
    local network_patterns=(
        "ai-platform"
        "aiplatform"
        "ai_platform"
    )
    
    for pattern in "${network_patterns[@]}"; do
        local networks=$(docker network ls --filter "name=${pattern}" -q 2>/dev/null || true)
        
        if [[ -n "$networks" ]]; then
            log_info "Found networks matching '${pattern}'"
            
            for net_id in $networks; do
                local net_name=$(docker network inspect "$net_id" --format '{{.Name}}' 2>/dev/null || echo "unknown")
                
                # Disconnect all containers from this network
                local containers=$(docker network inspect "$net_id" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
                
                if [[ -n "$containers" ]]; then
                    log_info "Disconnecting containers from network ${net_name}..."
                    for container in $containers; do
                        docker network disconnect -f "$net_id" "$container" 2>/dev/null || true
                    done
                fi
                
                # Remove the network
                if docker network rm "$net_id" 2>/dev/null; then
                    log_success "Removed network: ${net_name}"
                else
                    log_warning "Could not remove network: ${net_name}"
                fi
            done
        fi
    done
    
    log_success "Old networks cleaned"
}

# ============================================================================
# COLLECT CONFIGURATION
# ============================================================================
collect_config() {
    log_step "3/13" "Collecting configuration..."
    
    # Detect Tailscale IP
    TAILSCALE_IP=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
    
    if [[ -z "$TAILSCALE_IP" ]]; then
        log_warning "Tailscale IP not detected automatically"
        read -p "Enter Tailscale IP: " TAILSCALE_IP
    else
        log_info "Detected Tailscale IP: $TAILSCALE_IP"
        read -p "Use this IP? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            read -p "Enter Tailscale IP: " TAILSCALE_IP
        fi
    fi
    
    # Get Google Drive configuration
    log_info "Google Drive configuration:"
    read -p "Enter Rclone remote name (e.g., gdrive): " RCLONE_REMOTE
    read -p "Enter Google Drive folder path: " GDRIVE_FOLDER
    
    # Get Signal configuration
    log_info "Signal configuration:"
    read -p "Enter Signal phone number (e.g., +1234567890): " SIGNAL_PHONE
    
    # Network configuration
    NETWORK_NAME="aiplatform_net_$(date +%s)"
    NGINX_PORT=8443
    
    log_success "Configuration collected"
    log_info "Network: ${NETWORK_NAME}"
    log_info "IP: ${TAILSCALE_IP}"
    log_info "Port: ${NGINX_PORT}"
}

# ============================================================================
# CREATE DIRECTORIES
# ============================================================================
create_directories() {
    log_step "4/13" "Creating directory structure..."
    
    local dirs=(
        "${PROJECT_ROOT}/configs"
        "${PROJECT_ROOT}/configs/nginx"
        "${PROJECT_ROOT}/configs/litellm"
        "${PROJECT_ROOT}/configs/clawdbot"
        "${PROJECT_ROOT}/configs/rclone"
        "${PROJECT_ROOT}/data"
        "${PROJECT_ROOT}/logs"
        "${PROJECT_ROOT}/certs"
        "${PROJECT_ROOT}/dashboard"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_success "Created: $dir"
    done
}

# ============================================================================
# GENERATE .ENV FILE
# ============================================================================
generate_env_file() {
    log_step "5/13" "Generating environment file..."
    
    # Generate secure passwords and tokens
    local POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    local REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    local SECRET_KEY=$(openssl rand -hex 32)
    local LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    local LITELLM_SALT_KEY=$(openssl rand -hex 16)
    local CLAWDBOT_GATEWAY_TOKEN=$(openssl rand -hex 32)
    
    cat > "${PROJECT_ROOT}/.env" << EOF
# ============================================================================
# AI Platform Environment Configuration
# Generated: $(date)
# ============================================================================

# Network Configuration
NETWORK_NAME=${NETWORK_NAME}
TAILSCALE_IP=${TAILSCALE_IP}
NGINX_PORT=${NGINX_PORT}

# Database Configuration
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=aiplatform

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}

# Security Keys
SECRET_KEY=${SECRET_KEY}

# LiteLLM Configuration
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_SALT_KEY=${LITELLM_SALT_KEY}

# Dify Configuration
DIFY_API_URL=http://dify-api:5001
DIFY_WEB_URL=http://dify-web:3000

# AnythingLLM Configuration
ANYTHINGLLM_URL=http://anythingllm:3001

# n8n Configuration
N8N_HOST=${TAILSCALE_IP}
N8N_PORT=5678
N8N_PROTOCOL=https

# Ollama Configuration
OLLAMA_HOST=http://ollama:11434

# Signal Configuration
SIGNAL_PHONE=${SIGNAL_PHONE}
SIGNAL_API_URL=http://signal-api:8080

# ClawdBot/Moltbot Configuration
CLAWDBOT_GATEWAY_TOKEN=${CLAWDBOT_GATEWAY_TOKEN}
CLAWDBOT_PORT=18789

# Google Drive Sync Configuration
RCLONE_REMOTE=${RCLONE_REMOTE}
GDRIVE_FOLDER=${GDRIVE_FOLDER}
SYNC_INTERVAL=3600

# Timezone
TZ=UTC

EOF
    
    chmod 600 "${PROJECT_ROOT}/.env"
    log_success "Environment file created"
    log_info "Credentials saved to: ${PROJECT_ROOT}/.env"
}

# ============================================================================
# GENERATE DOCKER COMPOSE
# ============================================================================
generate_docker_compose() {
    log_step "6/13" "Generating docker-compose.yml..."
    
    cat > "${PROJECT_ROOT}/docker-compose.yml" << 'EOF'
version: '3.8'

# ============================================================================
# AI PLATFORM - DOCKER COMPOSE CONFIGURATION
# ============================================================================

networks:
  default:
    name: ${NETWORK_NAME}
    driver: bridge

volumes:
  ollama_data:
  anythingllm_data:
  dify_postgres:
  dify_redis:
  dify_weaviate:
  dify_storage:
  n8n_data:
  signal_data:
  clawdbot_data:
  clawdbot_workspace:
  gdrive_data:

services:
  # ============================================================================
  # OLLAMA - Local LLM Engine
  # ============================================================================
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ============================================================================
  # LITELLM - Unified LLM Gateway
  # ============================================================================
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    volumes:
      - ./configs/litellm/config.yaml:/app/config.yaml:ro
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@dify-db:5432/${POSTGRES_DB}
    command: --config /app/config.yaml --port 4000
    depends_on:
      ollama:
        condition: service_healthy
      dify-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # ANYTHINGLLM - Document Chat Interface
  # ============================================================================
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - anythingllm_data:/app/server/storage
    environment:
      - STORAGE_DIR=/app/server/storage
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - EMBEDDING_ENGINE=ollama
      - EMBEDDING_BASE_PATH=http://ollama:11434
      - VECTOR_DB=lancedb
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # DIFY - AI Application Platform
  # ============================================================================
  dify-db:
    image: postgres:15-alpine
    container_name: dify-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - dify_postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  dify-redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - dify_redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

  dify-weaviate:
    image: semitechnologies/weaviate:1.19.0
    container_name: dify-weaviate
    restart: unless-stopped
    volumes:
      - dify_weaviate:/var/lib/weaviate
    environment:
      - QUERY_DEFAULTS_LIMIT=25
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - DEFAULT_VECTORIZER_MODULE=none
      - CLUSTER_HOSTNAME=node1
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    ports:
      - "5001:5001"
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=${SECRET_KEY}
      - DB_USERNAME=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=dify-db
      - DB_PORT=5432
      - DB_DATABASE=${POSTGRES_DB}
      - REDIS_HOST=dify-redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - REDIS_USE_SSL=false
      - REDIS_DB=0
      - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@dify-redis:6379/1
      - WEB_API_CORS_ALLOW_ORIGINS=*
      - CONSOLE_CORS_ALLOW_ORIGINS=*
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/storage
      - VECTOR_STORE=weaviate
      - WEAVIATE_ENDPOINT=http://dify-weaviate:8080
    volumes:
      - dify_storage:/app/storage
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy
      dify-weaviate:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=${SECRET_KEY}
      - DB_USERNAME=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_HOST=dify-db
      - DB_PORT=5432
      - DB_DATABASE=${POSTGRES_DB}
      - REDIS_HOST=dify-redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - REDIS_USE_SSL=false
      - REDIS_DB=0
      - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@dify-redis:6379/1
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/storage
      - VECTOR_STORE=weaviate
      - WEAVIATE_ENDPOINT=http://dify-weaviate:8080
    volumes:
      - dify_storage:/app/storage
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy
      dify-weaviate:
        condition: service_healthy

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001
    depends_on:
      dify-api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # N8N - Workflow Automation
  # ============================================================================
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=https://${N8N_HOST}:${NGINX_PORT}/n8n/
      - GENERIC_TIMEZONE=${TZ}
      - N8N_PATH=/n8n/
    volumes:
      - n8n_data:/home/node/.n8n
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # SIGNAL API - Messaging Gateway
  # ============================================================================
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - MODE=native
    volumes:
      - signal_data:/home/.local/share/signal-cli
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # CLAWDBOT (MOLTBOT) - AI Assistant Gateway
  # ============================================================================
  clawdbot:
    image: moltbot/moltbot:latest
    container_name: clawdbot
    restart: unless-stopped
    ports:
      - "18789:18789"
      - "18790:18790"
    environment:
      - CLAWDBOT_GATEWAY_TOKEN=${CLAWDBOT_GATEWAY_TOKEN}
    volumes:
      - clawdbot_data:/home/node/.clawdbot
      - clawdbot_workspace:/home/node/clawd
    depends_on:
      ollama:
        condition: service_healthy
      litellm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================================
  # RCLONE - Google Drive Sync
  # ============================================================================
  gdrive-sync:
    image: rclone/rclone:latest
    container_name: gdrive-sync
    restart: unless-stopped
    volumes:
      - ./configs/rclone/rclone.conf:/config/rclone/rclone.conf:ro
      - gdrive_data:/data
      - anythingllm_data:/sync/anythingllm:ro
      - dify_storage:/sync/dify:ro
      - n8n_data:/sync/n8n:ro
      - clawdbot_workspace:/sync/clawdbot:ro
    environment:
      - RCLONE_CONFIG=/config/rclone/rclone.conf
      - SYNC_INTERVAL=${SYNC_INTERVAL}
    command: >
      rcd
      --rc-addr=:5572
      --rc-web-gui
      --rc-web-gui-no-open-browser
      --rc-user=admin
      --rc-pass=admin
    healthcheck:
      test: ["CMD", "rclone", "version"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ============================================================================
  # NGINX - Reverse Proxy
  # ============================================================================
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "${NGINX_PORT}:443"
    volumes:
      - ./configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./configs/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certs:/etc/nginx/certs:ro
      - ./dashboard:/usr/share/nginx/html:ro
    depends_on:
      - ollama
      - litellm
      - anythingllm
      - dify-web
      - dify-api
      - n8n
      - signal-api
      - clawdbot
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    
    log_success "docker-compose.yml generated"
}

# ============================================================================
# GENERATE NGINX CONFIGURATION
# ============================================================================
generate_nginx_config() {
    log_step "7/13" "Generating NGINX configuration..."
    
    # Main nginx.conf
    cat > "${PROJECT_ROOT}/configs/nginx/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    mkdir -p "${PROJECT_ROOT}/configs/nginx/conf.d"
    
    # Default server configuration
    cat > "${PROJECT_ROOT}/configs/nginx/conf.d/default.conf" << 'EOF'
# ============================================================================
# AI Platform - NGINX Reverse Proxy Configuration
# ============================================================================

# Upstream definitions
upstream ollama {
    server ollama:11434;
}

upstream litellm {
    server litellm:4000;
}

upstream anythingllm {
    server anythingllm:3001;
}

upstream dify_web {
    server dify-web:3000;
}

upstream dify_api {
    server dify-api:5001;
}

upstream n8n {
    server n8n:5678;
}

upstream signal_api {
    server signal-api:8080;
}

upstream clawdbot {
    server clawdbot:18789;
}

# Main HTTPS server
server {
    listen 443 ssl http2 default_server;
    server_name _;
    
    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    root /usr/share/nginx/html;
    index index.html;
    
    # Dashboard
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Ollama API
    location /ollama/ {
        proxy_pass http://ollama/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
    
    # LiteLLM API
    location /litellm/ {
        proxy_pass http://litellm/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
    
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
    
    # Dify Web Interface
    location /dify/ {
        proxy_pass http://dify_web/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # Dify API
    location /dify/api/ {
        proxy_pass http://dify_api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
    
    # n8n Workflow Automation
    location /n8n/ {
        proxy_pass http://n8n/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
    
    # Signal API
    location /signal/ {
        proxy_pass http://signal_api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # ClawdBot API
    location /clawdbot/ {
        proxy_pass http://clawdbot/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    
    log_success "NGINX configuration generated"
}

# ============================================================================
# GENERATE SSL CERTIFICATES
# ============================================================================
generate_ssl_certs() {
    log_step "8/13" "Generating SSL certificates..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${PROJECT_ROOT}/certs/server.key" \
        -out "${PROJECT_ROOT}/certs/server.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${TAILSCALE_IP}" \
        &>> "$LOGFILE"
    
    chmod 600 "${PROJECT_ROOT}/certs/server.key"
    chmod 644 "${PROJECT_ROOT}/certs/server.crt"
    
    log_success "SSL certificates generated"
}

# ============================================================================
# GENERATE LITELLM CONFIG
# ============================================================================
generate_litellm_config() {
    log_step "9/13" "Generating LiteLLM configuration..."
    
    cat > "${PROJECT_ROOT}/configs/litellm/config.yaml" << 'EOF'
model_list:
  - model_name: ollama/llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434

  - model_name: ollama/qwen2.5-coder
    litellm_params:
      model: ollama/qwen2.5-coder
      api_base: http://ollama:11434

  - model_name: ollama/deepseek-r1
    litellm_params:
      model: ollama/deepseek-r1
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${DATABASE_URL}
EOF
    
    log_success "LiteLLM configuration generated"
}

# ============================================================================
# GENERATE CLAWDBOT TOKEN
# ============================================================================
generate_clawdbot_files() {
    log_step "10/13" "Generating ClawdBot configuration..."
    
    log_success "ClawdBot gateway token generated"
    log_info "Token will be available in .env file"
}

# ============================================================================
# GENERATE RCLONE CONFIG TEMPLATE
# ============================================================================
generate_rclone_config() {
    log_step "11/13" "Generating Rclone configuration template..."
    
    cat > "${PROJECT_ROOT}/configs/rclone/rclone.conf" << EOF
# Google Drive Configuration
# To configure:
# 1. docker exec -it gdrive-sync rclone config
# 2. Follow prompts to authenticate with Google Drive
# 3. Remote name: ${RCLONE_REMOTE}
# 4. Choose 'drive' as storage type
# 5. Follow OAuth flow

# After configuration, sync will run automatically every ${SYNC_INTERVAL} seconds
EOF
    
    log_success "Rclone configuration template generated"
    log_warning "Configure Rclone after deployment with: docker exec -it gdrive-sync rclone config"
}

# ============================================================================
# GENERATE DASHBOARD
# ============================================================================
generate_dashboard() {
    log_step "12/13" "Generating web dashboard..."
    
    cat > "${PROJECT_ROOT}/dashboard/index.html" << 'DASHBOARD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Platform Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }
        
        h1 {
            font-size: 3em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .service-card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            cursor: pointer;
        }
        
        .service-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.3);
        }
        
        .service-header {
            display: flex;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .service-icon {
            font-size: 2em;
            margin-right: 15px;
        }
        
        .service-title {
            font-size: 1.5em;
            color: #333;
        }
        
        .service-description {
            color: #666;
            margin-bottom: 15px;
            line-height: 1.6;
        }
        
        .service-link {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 10px 20px;
            border-radius: 25px;
            text-decoration: none;
            transition: opacity 0.3s ease;
        }
        
        .service-link:hover {
            opacity: 0.8;
        }
        
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #4CAF50;
            margin-left: 10px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .info-section {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .info-title {
            font-size: 1.5em;
            color: #333;
            margin-bottom: 15px;
        }
        
        .info-content {
            color: #666;
            line-height: 1.8;
        }
        
        code {
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🤖 AI Platform</h1>
            <p class="subtitle">Your Unified AI Development Environment</p>
        </header>
        
        <div class="services-grid">
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">🧠</span>
                    <h2 class="service-title">Ollama<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Local large language model engine. Run LLMs like Llama, Mistral, and more.
                </p>
                <a href="/ollama/api/tags" class="service-link">View Models →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">🔄</span>
                    <h2 class="service-title">LiteLLM<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Unified API gateway for all LLM providers with load balancing and fallbacks.
                </p>
                <a href="/litellm/" class="service-link">Open Gateway →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">💬</span>
                    <h2 class="service-title">AnythingLLM<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Document chat interface with RAG capabilities. Chat with your documents.
                </p>
                <a href="/anythingllm/" class="service-link">Start Chatting →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">🚀</span>
                    <h2 class="service-title">Dify<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    AI application development platform. Build and deploy AI applications.
                </p>
                <a href="/dify/" class="service-link">Build Apps →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">⚡</span>
                    <h2 class="service-title">n8n<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Workflow automation platform. Connect apps and automate tasks.
                </p>
                <a href="/n8n/" class="service-link">Create Workflows →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">📱</span>
                    <h2 class="service-title">Signal API<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Messaging gateway for Signal. Send and receive messages via API.
                </p>
                <a href="/signal/v1/about" class="service-link">API Docs →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">🦞</span>
                    <h2 class="service-title">ClawdBot<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    AI assistant gateway powered by Moltbot. Multi-channel AI automation.
                </p>
                <a href="/clawdbot/" class="service-link">Configure Bot →</a>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <span class="service-icon">☁️</span>
                    <h2 class="service-title">Google Drive<span class="status-indicator"></span></h2>
                </div>
                <p class="service-description">
                    Automatic backup and sync to Google Drive. Keep your data safe.
                </p>
                <a href="#" class="service-link" onclick="alert('Configure via rclone CLI'); return false;">Configure Sync →</a>
            </div>
        </div>
        
        <div class="info-section">
            <h2 class="info-title">🔧 System Information</h2>
            <div class="info-content">
                <p><strong>Network:</strong> All services are connected via isolated Docker network</p>
                <p><strong>Security:</strong> HTTPS enabled with self-signed certificates</p>
                <p><strong>Access:</strong> Available on Tailscale VPN only</p>
                <p><strong>Management:</strong> Use <code>./3-manage-services.sh</code> for service control</p>
            </div>
        </div>
    </div>
</body>
</html>
DASHBOARD
    
    log_success "Dashboard generated"
}

# ============================================================================
# MAKE SCRIPTS EXECUTABLE
# ============================================================================
make_scripts_executable() {
    log_step "13/13" "Making scripts executable..."
    chmod +x "${SCRIPT_DIR}"/*.sh
    log_success "Scripts are executable"
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
show_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    log_success "✅ SYSTEM SETUP COMPLETED!" | tee -a "$LOGFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    log_info "Configuration Summary:" | tee -a "$LOGFILE"
    echo "  Network: ${NETWORK_NAME}" | tee -a "$LOGFILE"
    echo "  IP: ${TAILSCALE_IP}" | tee -a "$LOGFILE"
    echo "  Port: ${NGINX_PORT}" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    log_info "📂 Files Generated:" | tee -a "$LOGFILE"
    echo "  ✓ .env" | tee -a "$LOGFILE"
    echo "  ✓ docker-compose.yml" | tee -a "$LOGFILE"
    echo "  ✓ configs/nginx/*.conf" | tee -a "$LOGFILE"
    echo "  ✓ configs/litellm/config.yaml" | tee -a "$LOGFILE"
    echo "  ✓ configs/rclone/rclone.conf" | tee -a "$LOGFILE"
    echo "  ✓ certs/server.{crt,key}" | tee -a "$LOGFILE"
    echo "  ✓ dashboard/index.html" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    log_info "🚀 NEXT STEP:" | tee -a "$LOGFILE"
    echo "  Run: ./2-deploy-services.sh" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║      AI Platform Setup v19 - MOLTBOT INTEGRATION       ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    echo "" | tee -a "$LOGFILE"
    echo "Started: $(date)" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    check_prerequisites
    clean_old_networks
    collect_config
    create_directories
    generate_env_file
    generate_docker_compose
    generate_nginx_config
    generate_ssl_certs
    generate_litellm_config
    generate_clawdbot_files
    generate_rclone_config
    generate_dashboard
    make_scripts_executable
    show_summary
    
    log_success "Setup completed: $(date)" | tee -a "$LOGFILE"
}

main "$@"
