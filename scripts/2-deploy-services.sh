#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Deployment Script
# Version: 10.2 FINAL
# Description: Deploys all Docker services in correct order
# ============================================================================

# Logging setup
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
        log_error "Run ./1-system-setup.sh first"
        exit 1
    fi
    
    # Source environment file
    set -a
    source "$env_file"
    set +a
    
    log_success "Environment loaded from .env"
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ROOT"
        "STACKS_DIR"
        "DATA_DIR"
        "DOCKER_NETWORK"
        "OLLAMA_PORT"
        "LITELLM_PORT"
        "ANYTHINGLLM_PORT"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
    )
    
    local missing=0
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not set in .env"
            ((missing++))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "$missing required variable(s) missing"
        exit 1
    fi
    
    log_success "All required variables validated"
}

# ============================================================================
# ENSURE STACK DIRECTORIES EXIST
# ============================================================================
ensure_stack_dirs() {
    log_step "Ensuring stack directories exist..."
    
    local stack_dirs=(
        "${STACKS_DIR}/ollama"
        "${STACKS_DIR}/litellm"
        "${STACKS_DIR}/anythingllm"
        "${STACKS_DIR}/dify"
        "${STACKS_DIR}/n8n"
        "${STACKS_DIR}/signal"
        "${STACKS_DIR}/clawdbot"
        "${STACKS_DIR}/nginx"
    )
    
    for dir in "${stack_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created: $dir"
        fi
    done
    
    log_success "All stack directories ready"
}

# ============================================================================
# CREATE DOCKER NETWORK
# ============================================================================
create_network() {
    log_step "Creating Docker network..."
    
    if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
        log_info "Network '$DOCKER_NETWORK' already exists"
    else
        docker network create \
            --driver bridge \
            --subnet "$DOCKER_SUBNET" \
            "$DOCKER_NETWORK" >> "$LOGFILE" 2>&1
        log_success "Created network: $DOCKER_NETWORK ($DOCKER_SUBNET)"
    fi
}

# ============================================================================
# DEPLOY OLLAMA
# ============================================================================
deploy_ollama() {
    log_step "Deploying Ollama (Local AI Models)..."
    
    local stack_dir="${STACKS_DIR}/ollama"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting Ollama..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for Ollama to be ready..."
    sleep 20
    
    if curl -s http://localhost:${OLLAMA_PORT}/api/tags > /dev/null; then
        log_success "Ollama deployed and healthy"
    else
        log_warning "Ollama may not be fully ready yet"
    fi
}

# ============================================================================
# DEPLOY LITELLM
# ============================================================================
deploy_litellm() {
    log_step "Deploying LiteLLM (AI Gateway)..."
    
    local stack_dir="${STACKS_DIR}/litellm"
    mkdir -p "$stack_dir"
    
    # Create LiteLLM config
    cat > "${stack_dir}/config.yaml" << EOF
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2:3b
      api_base: http://ollama:11434
  
  - model_name: qwen2.5
    litellm_params:
      model: ollama/qwen2.5:7b
      api_base: http://ollama:11434
  
  - model_name: deepseek-r1
    litellm_params:
      model: ollama/deepseek-r1:7b
      api_base: http://ollama:11434

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: null
EOF

    # Create docker-compose
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "${LITELLM_PORT}:4000"
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_LOG=INFO
    command: --config /app/config.yaml --port 4000
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting LiteLLM..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for LiteLLM to be ready..."
    sleep 15
    
    if curl -s http://localhost:${LITELLM_PORT}/health > /dev/null; then
        log_success "LiteLLM deployed and healthy"
    else
        log_warning "LiteLLM may not be fully ready yet"
    fi
}

# ============================================================================
# DEPLOY ANYTHINGLLM
# ============================================================================
deploy_anythingllm() {
    log_step "Deploying AnythingLLM (Vector Database & RAG)..."
    
    local stack_dir="${STACKS_DIR}/anythingllm"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    cap_add:
      - SYS_ADMIN
    environment:
      - STORAGE_DIR=/app/server/storage
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - EMBEDDING_ENGINE=ollama
      - EMBEDDING_BASE_PATH=http://ollama:11434
      - EMBEDDING_MODEL_PREF=nomic-embed-text:latest
      - VECTOR_DB=lancedb
    volumes:
      - ${ANYTHINGLLM_STORAGE}:/app/server/storage
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting AnythingLLM..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for AnythingLLM to be ready..."
    sleep 30
    
    if curl -s http://localhost:${ANYTHINGLLM_PORT}/api/ping > /dev/null; then
        log_success "AnythingLLM deployed and healthy"
    else
        log_warning "AnythingLLM may not be fully ready yet"
    fi
}

# ============================================================================
# DEPLOY DIFY
# ============================================================================
deploy_dify() {
    log_step "Deploying Dify (AI Application Platform)..."
    
    local stack_dir="${STACKS_DIR}/dify"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << 'EOF'
services:
  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    container_name: dify-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Dify API Server
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    environment:
      # Core
      SECRET_KEY: ${DIFY_SECRET_KEY}
      LOG_LEVEL: INFO
      
      # Database
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB}
      
      # Redis
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_USE_SSL: "false"
      
      # Celery
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      
      # Storage
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage
      
      # Vector Database
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
      
      # Model Providers
      OPENAI_API_BASE: http://litellm:4000
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
    volumes:
      - ${DATA_DIR}/dify/api/storage:/app/api/storage
    networks:
      - ai-platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  # Dify Worker
  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    environment:
      # Core
      SECRET_KEY: ${DIFY_SECRET_KEY}
      LOG_LEVEL: INFO
      
      # Database
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB}
      
      # Redis
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_USE_SSL: "false"
      
      # Celery
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
    command: celery -A app.celery worker -P gevent -c 1 --loglevel INFO
    networks:
      - ai-platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  # Dify Web UI
  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: ${DIFY_API_BASE_URL}
      APP_API_URL: ${DIFY_API_BASE_URL}
    networks:
      - ai-platform
    depends_on:
      - dify-api

  # Nginx for Dify
  dify-nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - ai-platform
    depends_on:
      - dify-api
      - dify-web

  # Qdrant Vector Database
  qdrant:
    image: qdrant/qdrant:latest
    container_name: dify-qdrant
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/dify/qdrant:/qdrant/storage
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF

    # Create Nginx config for Dify
    cat > "${stack_dir}/nginx.conf" << 'EOF'
user  nginx;
worker_processes  auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log  /var/log/nginx/access.log  main;
    
    sendfile        on;
    keepalive_timeout  65;
    client_max_body_size 15M;
    
    server {
        listen 80;
        server_name _;
        
        location /console/api {
            proxy_pass http://dify-api:5001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /api {
            proxy_pass http://dify-api:5001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /v1 {
            proxy_pass http://dify-api:5001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /files {
            proxy_pass http://dify-api:5001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location / {
            proxy_pass http://dify-web:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

    log_info "Starting Dify stack..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for services to be ready..."
    log_info "  - PostgreSQL (30s)..."
    sleep 30
    log_info "  - Redis (10s)..."
    sleep 10
    log_info "  - Dify API (40s)..."
    sleep 40
    
    if curl -s http://localhost:8080 > /dev/null; then
        log_success "Dify deployed and healthy"
        log_info "Access Dify at: http://localhost:8080"
    else
        log_warning "Dify may not be fully ready yet (can take 2-3 minutes)"
    fi
}

# ============================================================================
# DEPLOY N8N
# ============================================================================
deploy_n8n() {
    log_step "Deploying n8n (Workflow Automation)..."
    
    local stack_dir="${STACKS_DIR}/n8n"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost:${N8N_PORT}/
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting n8n..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for n8n to be ready..."
    sleep 20
    
    if curl -s http://localhost:${N8N_PORT}/healthz > /dev/null; then
        log_success "n8n deployed and healthy"
        log_info "Access n8n at: http://localhost:${N8N_PORT}"
    else
        log_warning "n8n may not be fully ready yet"
    fi
}

# ============================================================================
# DEPLOY SIGNAL API
# ============================================================================
deploy_signal() {
    log_step "Deploying Signal API (Messaging)..."
    
    local stack_dir="${STACKS_DIR}/signal"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    ports:
      - "8090:8080"
    environment:
      - MODE=native
    volumes:
      - ${DATA_DIR}/signal:/home/.local/share/signal-cli
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting Signal API..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for Signal API to be ready..."
    sleep 15
    
    if curl -s http://localhost:8090/v1/health > /dev/null; then
        log_success "Signal API deployed and healthy"
        log_warning "Remember to link Signal account: curl -X POST http://localhost:8090/v1/register/[number]"
    else
        log_warning "Signal API may not be fully ready yet"
    fi
}

# ============================================================================
# DEPLOY CLAWDBOT
# ============================================================================
deploy_clawdbot() {
    log_step "Deploying Clawdbot (AI Agent)..."
    
    local stack_dir="${STACKS_DIR}/clawdbot"
    mkdir -p "$stack_dir"
    
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  clawdbot:
    image: ghcr.io/username/clawdbot:latest  # Replace with actual image
    container_name: clawdbot
    restart: unless-stopped
    ports:
      - "${CLAWDBOT_PORT}:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${DATA_DIR}/clawdbot:/app/data
      - ${PROJECT_ROOT}/logs:/app/logs:ro
    environment:
      - LITELLM_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
      - ANYTHINGLLM_URL=http://anythingllm:3001
      - SIGNAL_NUMBER=${SIGNAL_PRIMARY_NUMBER}
      - LOG_LEVEL=info
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting Clawdbot..."
    log_warning "Using placeholder image - update with actual Clawdbot image"
    
    # Only deploy if image exists
    if docker image inspect ghcr.io/username/clawdbot:latest &>/dev/null; then
        docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
        log_success "Clawdbot deployed"
    else
        log_warning "Clawdbot image not found - skipping deployment"
        log_info "Update image name in: ${stack_dir}/docker-compose.yml"
    fi
}

# ============================================================================
# DEPLOY NGINX REVERSE PROXY
# ============================================================================
deploy_nginx() {
    log_step "Deploying NGINX (Reverse Proxy)..."
    
    local stack_dir="${STACKS_DIR}/nginx"
    mkdir -p "${stack_dir}/ssl"
    
    # Generate self-signed certificate
    log_info "Generating SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${stack_dir}/ssl/nginx-selfsigned.key" \
        -out "${stack_dir}/ssl/nginx-selfsigned.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
        >> "$LOGFILE" 2>&1
    
    # Create Nginx config
    cat > "${stack_dir}/nginx.conf" << 'EOF'
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
                    '"$http_user_agent"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 50M;
    
    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Main HTTPS server
    server {
        listen 8443 ssl;
        server_name _;
        
        ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
        
        # AnythingLLM
        location /anythingllm/ {
            proxy_pass http://anythingllm:3001/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Dify
        location /dify/ {
            proxy_pass http://dify-nginx:80/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # n8n
        location /n8n/ {
            proxy_pass http://n8n:5678/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # LiteLLM
        location /litellm/ {
            proxy_pass http://litellm:4000/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Default route
        location / {
            return 200 'AI Platform - All systems operational\n';
            add_header Content-Type text/plain;
        }
    }
}
EOF

    # Create docker-compose
    cat > "${stack_dir}/docker-compose.yml" << EOF
services:
  nginx:
    image: nginx:alpine
    container_name: platform-nginx
    restart: unless-stopped
    ports:
      - "${NGINX_PORT}:8443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ${LOGS_DIR}/nginx:/var/log/nginx
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "--no-check-certificate", "https://localhost:8443/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s

networks:
  ai-platform:
    external: true
EOF

    log_info "Starting NGINX..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d >> "$LOGFILE" 2>&1
    
    log_info "Waiting for NGINX to be ready..."
    sleep 10
    
    if curl -k -s https://localhost:${NGINX_PORT}/ > /dev/null; then
        log_success "NGINX deployed and healthy"
        log_info "Access platform at: https://localhost:${NGINX_PORT}/"
    else
        log_warning "NGINX may not be fully ready yet"
    fi
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================
verify_deployment() {
    log_step "Verifying deployment..."
    
    local services=(
        "ollama:Ollama (AI Models)"
        "litellm:LiteLLM (AI Gateway)"
        "anythingllm:AnythingLLM (Vector DB)"
        "dify-postgres:Dify PostgreSQL"
        "dify-redis:Dify Redis"
        "dify-api:Dify API"
        "dify-worker:Dify Worker"
        "dify-web:Dify Web"
        "dify-nginx:Dify Nginx"
        "dify-qdrant:Dify Qdrant"
        "n8n:n8n Automation"
        "signal-api:Signal API"
        "platform-nginx:Platform Nginx"
    )
    
    local running=0
    local total=${#services[@]}
    
    echo ""
    for service in "${services[@]}"; do
        IFS=':' read -r container name <<< "$service"
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_success "$name - Running"
            ((running++))
        else
            log_warning "$name - Not running"
        fi
    done
    
    echo ""
    log_info "Deployment summary: $running/$total services running"
    
    if [[ $running -eq $total ]]; then
        log_success "All services deployed successfully!"
    elif [[ $running -gt 0 ]]; then
        log_warning "Partial deployment - some services may still be starting"
    else
        log_error "No services running - deployment failed"
        return 1
    fi
}

# ============================================================================
# DISPLAY NEXT STEPS
# ============================================================================
show_next_steps() {
    cat << EOF

╔════════════════════════════════════════════════════════════╗
║              ✓ SERVICES DEPLOYED SUCCESSFULLY            ║
╚════════════════════════════════════════════════════════════╝

📊 ACCESS POINTS:

• Platform Dashboard: https://localhost:${NGINX_PORT}/
• AnythingLLM:        https://localhost:${NGINX_PORT}/anythingllm/
• Dify:               https://localhost:${NGINX_PORT}/dify/
• n8n:                https://localhost:${NGINX_PORT}/n8n/
• LiteLLM:            https://localhost:${NGINX_PORT}/litellm/

🔧 DIRECT SERVICE PORTS:

• Ollama:             http://localhost:${OLLAMA_PORT}
• LiteLLM:            http://localhost:${LITELLM_PORT}
• AnythingLLM:        http://localhost:${ANYTHINGLLM_PORT}
• Dify:               http://localhost:8080
• n8n:                http://localhost:${N8N_PORT}
• Signal API:         http://localhost:8090

📋 NEXT STEPS:

1. Download AI models:
   docker exec -it ollama ollama pull llama3.2:3b
   docker exec -it ollama ollama pull qwen2.5:7b

2. Configure services:
   cd ~/AIPlatformAutomation/scripts
   ./3-configure-services.sh

3. Set up Tailscale access:
   sudo tailscale serve https / proxy https://localhost:${NGINX_PORT}

4. Link Signal account:
   curl -X POST http://localhost:8090/v1/register/${SIGNAL_PRIMARY_NUMBER}

5. Enable autostart:
   ./4-systemd-setup.sh

⚠️  IMPORTANT:

• All services use self-signed SSL certificates
• Accept certificate warnings in your browser
• Keep your .env file secure (contains secrets)
• Check logs if services aren't responding: docker logs [container-name]

📊 RESOURCE USAGE:

• Running containers: $(docker ps -q | wc -l)
• Disk usage: $(du -sh ${DATA_DIR} 2>/dev/null | cut -f1)

📝 LOG FILE: ${LOGFILE}

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    echo "ℹ Log file: $LOGFILE"
    echo ""
    
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     AI Platform - Service Deployment v10.2 FINAL        ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    
    # Load and validate environment
    load_environment
    
    # Ensure all stack directories exist
    ensure_stack_dirs
    
    # Create Docker network
    create_network
    
    # Deploy services in order
    deploy_ollama
    deploy_litellm
    deploy_anythingllm
    deploy_dify
    deploy_n8n
    deploy_signal
    deploy_clawdbot
    deploy_nginx
    
    # Verify and show results
    verify_deployment
    show_next_steps
    
    log_success "Service deployment completed!"
}

# Run main function and log everything
main "$@" 2>&1 | tee -a "$LOGFILE"
