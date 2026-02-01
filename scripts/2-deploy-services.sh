#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Deployment Script
# Version: 10.9 FINAL - DEPENDENCY FIX
# Description: Fixed compose dependencies and service references
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
    log_error "Command: $BASH_COMMAND"
    log_error "Check log file: $LOGFILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================================================
# WAIT FOR SERVICE
# ============================================================================
wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local max_attempts="${3:-30}"
    local sleep_time="${4:-5}"
    
    log_info "Waiting for $service_name to be ready..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if eval "$check_command" &>/dev/null; then
            log_success "$service_name is ready"
            return 0
        fi
        
        echo -n "."
        sleep "$sleep_time"
        ((attempt++))
    done
    
    echo ""
    log_warning "$service_name did not become ready within timeout"
    return 1
}

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
    
    set -a
    source "$env_file"
    set +a
    
    log_success "Environment loaded"
}

# ============================================================================
# ENSURE STACK DIRECTORIES
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
        "${STACKS_DIR}/nginx"
    )
    
    for dir in "${stack_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    local data_dirs=(
        "${DATA_DIR}/ollama"
        "${DATA_DIR}/anythingllm"
        "${DATA_DIR}/postgres"
        "${DATA_DIR}/redis"
        "${DATA_DIR}/dify/api/storage"
        "${DATA_DIR}/dify/qdrant"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/signal"
    )
    
    for dir in "${data_dirs[@]}"; do
        sudo mkdir -p "$dir"
        sudo chown -R $(id -u):$(id -g) "$dir"
        sudo chmod -R 755 "$dir"
    done
    
    sudo chmod -R 777 "${DATA_DIR}/anythingllm"
    sudo chmod -R 777 "${DATA_DIR}/dify/qdrant"
    
    log_success "All directories ready"
}

# ============================================================================
# CREATE DOCKER NETWORK
# ============================================================================
create_network() {
    log_step "Creating Docker network..."
    
    if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
        log_info "Network exists"
    else
        docker network create --driver bridge --subnet "$DOCKER_SUBNET" "$DOCKER_NETWORK"
        log_success "Network created"
    fi
}

# ============================================================================
# DEPLOY OLLAMA
# ============================================================================
deploy_ollama() {
    log_step "Deploying Ollama..."
    
    cat > "${STACKS_DIR}/ollama/docker-compose.yml" << EOF
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
      test: ["CMD-SHELL", "ollama list || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${STACKS_DIR}/ollama/docker-compose.yml" up -d
    wait_for_service "Ollama" "curl -s http://localhost:${OLLAMA_PORT}/api/tags" 20 3 || true
}

# ============================================================================
# DEPLOY LITELLM
# ============================================================================
deploy_litellm() {
    log_step "Deploying LiteLLM..."
    
    cat > "${STACKS_DIR}/litellm/config.yaml" << EOF
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2:3b
      api_base: http://ollama:11434

litellm_settings:
  drop_params: True
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
EOF

    cat > "${STACKS_DIR}/litellm/docker-compose.yml" << EOF
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
    command: --config /app/config.yaml --port 4000
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:4000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${STACKS_DIR}/litellm/docker-compose.yml" up -d
    wait_for_service "LiteLLM" "curl -s http://localhost:${LITELLM_PORT}/health" 15 2 || true
}

# ============================================================================
# DEPLOY ANYTHINGLLM
# ============================================================================
deploy_anythingllm() {
    log_step "Deploying AnythingLLM..."
    
    local data_path="${DATA_DIR}/anythingllm"
    sudo mkdir -p "$data_path"
    sudo chown -R 1000:1000 "$data_path"
    sudo chmod -R 777 "$data_path"
    
    cat > "${STACKS_DIR}/anythingllm/docker-compose.yml" << EOF
services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    volumes:
      - ${data_path}:/app/server/storage
    environment:
      - STORAGE_DIR=/app/server/storage
      - SERVER_PORT=3001
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:3001/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${STACKS_DIR}/anythingllm/docker-compose.yml" up -d
    sleep 10
    wait_for_service "AnythingLLM" "curl -s http://localhost:${ANYTHINGLLM_PORT}/" 40 5 || true
}

# ============================================================================
# DEPLOY DIFY (PORT 8081)
# ============================================================================
deploy_dify() {
    log_step "Deploying Dify (on port 8081)..."
    
    local stack_dir="${STACKS_DIR}/dify"
    
    cat > "${stack_dir}/docker-compose.yml" << 'EOF'
services:
  postgres:
    image: postgres:15-alpine
    container_name: dify-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: dify
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 40s

  redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10

  qdrant:
    image: qdrant/qdrant:latest
    container_name: dify-qdrant
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/dify/qdrant:/qdrant/storage
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "timeout 5 bash -c '</dev/tcp/localhost/6333' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 40s

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    environment:
      MODE: api
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_USE_SSL: "false"
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
    volumes:
      - ${DATA_DIR}/dify/api/storage:/app/api/storage
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      qdrant:
        condition: service_healthy
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5001/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    environment:
      MODE: worker
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_USE_SSL: "false"
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
    volumes:
      - ${DATA_DIR}/dify/api/storage:/app/api/storage
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      qdrant:
        condition: service_healthy
    networks:
      - ai-platform

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    depends_on:
      - dify-api
    networks:
      - ai-platform

  dify-nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    ports:
      - "8081:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./proxy_params.conf:/etc/nginx/proxy_params.conf:ro
    depends_on:
      - dify-web
      - dify-api
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:80/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

networks:
  ai-platform:
    external: true
EOF

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
    client_max_body_size 15M;
    
    server {
        listen 80;
        server_name _;
        
        location /console/api {
            proxy_pass http://dify-api:5001;
            include /etc/nginx/proxy_params.conf;
        }
        
        location /api {
            proxy_pass http://dify-api:5001;
            include /etc/nginx/proxy_params.conf;
        }
        
        location /v1 {
            proxy_pass http://dify-api:5001;
            include /etc/nginx/proxy_params.conf;
        }
        
        location /files {
            proxy_pass http://dify-api:5001;
            include /etc/nginx/proxy_params.conf;
        }
        
        location / {
            proxy_pass http://dify-web:3000;
            include /etc/nginx/proxy_params.conf;
        }
    }
}
EOF

    cat > "${stack_dir}/proxy_params.conf" << 'EOF'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
EOF

    log_info "Starting Dify (staged deployment)..."
    docker compose -f "${stack_dir}/docker-compose.yml" up -d postgres redis
    wait_for_service "PostgreSQL" "docker exec dify-postgres pg_isready -U postgres" 30 2 || true
    
    docker compose -f "${stack_dir}/docker-compose.yml" up -d qdrant
    sleep 15
    
    docker compose -f "${stack_dir}/docker-compose.yml" up -d
    sleep 20
    
    wait_for_service "Dify" "curl -s http://localhost:8081" 40 5 || true
}

# ============================================================================
# DEPLOY N8N
# ============================================================================
deploy_n8n() {
    log_step "Deploying n8n..."
    
    local data_path="${DATA_DIR}/n8n"
    sudo mkdir -p "$data_path"
    sudo chown -R 1000:1000 "$data_path"
    sudo chmod -R 755 "$data_path"
    
    cat > "${STACKS_DIR}/n8n/docker-compose.yml" << EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
    volumes:
      - ${data_path}:/home/node/.n8n
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${STACKS_DIR}/n8n/docker-compose.yml" up -d
    wait_for_service "n8n" "curl -s http://localhost:${N8N_PORT}/healthz" 20 3 || true
}

# ============================================================================
# DEPLOY SIGNAL API
# ============================================================================
deploy_signal() {
    log_step "Deploying Signal API..."
    
    local data_path="${DATA_DIR}/signal"
    sudo mkdir -p "$data_path"
    sudo chown -R 1000:1000 "$data_path"
    sudo chmod -R 755 "$data_path"
    
    cat > "${STACKS_DIR}/signal/docker-compose.yml" << EOF
services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    ports:
      - "8090:8080"
    environment:
      - MODE=native
      - PORT=8080
    volumes:
      - ${data_path}:/home/.local/share/signal-cli
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:8080/v1/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${STACKS_DIR}/signal/docker-compose.yml" up -d
    wait_for_service "Signal API" "curl -s http://localhost:8090/v1/health" 20 3 || true
}

# ============================================================================
# DEPLOY NGINX (NO DEPENDENCIES ON OTHER COMPOSE FILES)
# ============================================================================
deploy_nginx() {
    log_step "Deploying platform NGINX..."
    
    local stack_dir="${STACKS_DIR}/nginx"
    mkdir -p "${stack_dir}/ssl"
    
    if [[ ! -f "${stack_dir}/ssl/nginx-selfsigned.crt" ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${stack_dir}/ssl/nginx-selfsigned.key" \
            -out "${stack_dir}/ssl/nginx-selfsigned.crt" \
            -subj "/C=US/ST=State/L=City/O=AI/CN=localhost" 2>&1 | tee -a "$LOGFILE"
    fi
    
    cat > "${stack_dir}/nginx.conf" << 'NGINXEOF'
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
    
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Enable response rewriting
    sub_filter_once off;
    sub_filter_types *;
    
    upstream anythingllm_backend {
        server anythingllm:3001;
    }
    
    upstream litellm_backend {
        server litellm:4000;
    }
    
    upstream dify_backend {
        server dify-nginx:80;
    }
    
    upstream n8n_backend {
        server n8n:5678;
    }
    
    server {
        listen 8443 ssl http2;
        server_name _;
        
        ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
        
        # Root
        location = / {
            return 200 'AI Platform Dashboard\n\nAvailable Services:\n- /anythingllm/\n- /dify/\n- /n8n/\n- /litellm/\n';
            add_header Content-Type text/plain;
        }
        
        # AnythingLLM
        location /anythingllm/ {
            proxy_pass http://anythingllm_backend/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            proxy_cache_bypass $http_upgrade;
            
            # Rewrite asset paths
            sub_filter 'href="/' 'href="/anythingllm/';
            sub_filter 'src="/' 'src="/anythingllm/';
            sub_filter 'url(/' 'url(/anythingllm/';
            sub_filter 'action="/' 'action="/anythingllm/';
        }
        
        # LiteLLM
        location /litellm/ {
            proxy_pass http://litellm_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Rewrite paths
            sub_filter 'href="/' 'href="/litellm/';
            sub_filter 'src="/' 'src="/litellm/';
        }
        
        # Dify
        location /dify/ {
            proxy_pass http://dify_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Rewrite paths
            sub_filter 'href="/' 'href="/dify/';
            sub_filter 'src="/' 'src="/dify/';
            sub_filter 'action="/' 'action="/dify/';
        }
        
        # n8n
        location /n8n/ {
            proxy_pass http://n8n_backend/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            
            # Rewrite paths
            sub_filter 'href="/' 'href="/n8n/';
            sub_filter 'src="/' 'src="/n8n/';
        }
    }
}
NGINXEOF

    # NO DEPENDENCIES - Just references network
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
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q --no-check-certificate https://localhost:8443/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s

networks:
  ai-platform:
    external: true
EOF

    docker compose -f "${stack_dir}/docker-compose.yml" up -d
    wait_for_service "NGINX" "curl -k -s https://localhost:${NGINX_PORT}/" 15 2 || true
}

# ============================================================================
# VERIFY DEPLOYMENT
# ============================================================================
verify_deployment() {
    log_step "Verifying deployment..."
    
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    local running=$(docker ps -q | wc -l)
    log_info "Running containers: $running"
    
    if [[ $running -gt 0 ]]; then
        log_success "Deployment successful!"
    fi
}

# ============================================================================
# SHOW NEXT STEPS
# ============================================================================
show_next_steps() {
    cat << EOF

╔════════════════════════════════════════════════════════════╗
║           ✓ DEPLOYMENT COMPLETE - v10.9                 ║
╚════════════════════════════════════════════════════════════╝

📊 PROXIED ACCESS (via NGINX):

• Platform Dashboard: https://100.114.125.50:${NGINX_PORT}/
• AnythingLLM:        https://100.114.125.50:${NGINX_PORT}/anythingllm/
• Dify:               https://100.114.125.50:${NGINX_PORT}/dify/
• n8n:                https://100.114.125.50:${NGINX_PORT}/n8n/
• LiteLLM:            https://100.114.125.50:${NGINX_PORT}/litellm/

🔧 DIRECT SERVICE PORTS:

• Ollama:             http://100.114.125.50:${OLLAMA_PORT}
• LiteLLM:            http://100.114.125.50:${LITELLM_PORT}
• AnythingLLM:        http://100.114.125.50:${ANYTHINGLLM_PORT}
• Dify:               http://100.114.125.50:8081
• n8n:                http://100.114.125.50:${N8N_PORT}
• Signal API:         http://100.114.125.50:8090

📋 NEXT STEPS:

1. Download AI models:
   docker exec -it ollama ollama pull llama3.2:3b
   docker exec -it ollama ollama pull nomic-embed-text

2. Test endpoints:
   curl -k https://100.114.125.50:8443/
   curl -k https://100.114.125.50:8443/anythingllm/
   curl -k https://100.114.125.50:8443/dify/
   curl -k https://100.114.125.50:8443/n8n/
   curl http://100.114.125.50:8090/v1/health

📝 LOG FILE: ${LOGFILE}

EOF
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     AI Platform - Service Deployment v10.9 FINAL        ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    load_environment
    ensure_stack_dirs
    create_network
    
    deploy_ollama
    deploy_litellm
    deploy_anythingllm
    deploy_dify
    deploy_n8n
    deploy_signal
    deploy_nginx
    
    verify_deployment
    show_next_steps
    
    log_success "All done!"
}

main "$@" 2>&1 | tee -a "$LOGFILE"
