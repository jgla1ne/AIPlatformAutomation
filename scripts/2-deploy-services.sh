#!/bin/bash
set -euo pipefail

# =============================================================================
# AI Platform - Service Deployment Script v5.4
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"
STACKS_DIR="${PROJECT_ROOT}/stacks"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# =============================================================================
# Load Environment
# =============================================================================

header "AI Platform - Service Deployment v5.4"
info "Location: ${PROJECT_ROOT}"
info "Started: $(date)"

info "[0/8] Loading environment..."
if [[ ! -f "${ENV_FILE}" ]]; then
    error "Configuration file not found: ${ENV_FILE}"
    error "Please run 1-setup-system.sh first"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a
log "Environment loaded"

# Verify critical variables
REQUIRED_VARS=(
    "DATA_DIR"
    "GPU_AVAILABLE"
    "LITELLM_MASTER_KEY"
    "DIFY_DB_USER"
    "DIFY_DB_PASSWORD"
    "POSTGRES_PASSWORD"
    "DIFY_SECRET_KEY"
    "TAILSCALE_IP"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required variable $var is not set in ${ENV_FILE}"
        exit 1
    fi
done

# Set defaults for optional variables
LITELLM_PORT=${LITELLM_PORT:-4000}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
DIFY_API_PORT=${DIFY_API_PORT:-5001}
DIFY_WEB_PORT=${DIFY_WEB_PORT:-3000}
N8N_PORT=${N8N_PORT:-5678}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_PORT=${REDIS_PORT:-6379}
WEAVIATE_PORT=${WEAVIATE_PORT:-8080}
NGINX_HTTP_PORT=${NGINX_HTTP_PORT:-80}
NGINX_HTTPS_PORT=${NGINX_HTTPS_PORT:-443}

# =============================================================================
# Ensure Permissions
# =============================================================================

info "[0/8] Ensuring script permissions..."
chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
log "All scripts are executable"

# =============================================================================
# Preflight Checks
# =============================================================================

info "[1/8] Running preflight checks..."

# Check Docker
if ! docker ps &> /dev/null; then
    error "Cannot connect to Docker daemon"
    error "Try: newgrp docker (or logout/login)"
    exit 1
fi
log "Docker running"

# Check Docker access
if ! docker info &> /dev/null; then
    error "Docker daemon not accessible"
    exit 1
fi
log "Docker access verified"

# Check data directory
if [[ ! -d "${DATA_DIR}" ]]; then
    error "Data directory not found: ${DATA_DIR}"
    exit 1
fi
log "Data directory exists"

# GPU status
if [[ "${GPU_AVAILABLE}" == "true" ]]; then
    log "GPU acceleration enabled"
else
    warn "Running in CPU-only mode"
fi

# =============================================================================
# Create Docker Networks
# =============================================================================

info "[2/8] Creating Docker networks..."
docker network create ai-platform 2>/dev/null || log "Network ai-platform exists"
docker network create dify-network 2>/dev/null || log "Network dify-network exists"
log "Networks ready"

# =============================================================================
# Create Stack Directory
# =============================================================================

info "[3/8] Preparing deployment files..."
rm -rf "${STACKS_DIR}"
mkdir -p "${STACKS_DIR}"

# =============================================================================
# Deploy LiteLLM
# =============================================================================

info "[4/8] Deploying LiteLLM proxy..."

cat > "${STACKS_DIR}/litellm-compose.yml" << 'EOF'
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "${LITELLM_PORT}:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_LOG=INFO
    volumes:
      - ${DATA_DIR}/litellm:/app/config
    networks:
      - ai-platform
    command: >
      --port 4000
      --detailed_debug

networks:
  ai-platform:
    external: true
EOF

docker compose -f "${STACKS_DIR}/litellm-compose.yml" up -d
log "LiteLLM deployed on port ${LITELLM_PORT}"

# =============================================================================
# Deploy Ollama
# =============================================================================

info "[5/8] Deploying Ollama..."

if [[ "${GPU_AVAILABLE}" == "true" ]]; then
    OLLAMA_RUNTIME="--gpus all"
else
    OLLAMA_RUNTIME=""
fi

cat > "${STACKS_DIR}/ollama-compose.yml" << 'EOF'
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
    networks:
      - ai-platform
EOF

if [[ "${GPU_AVAILABLE}" == "true" ]]; then
    cat >> "${STACKS_DIR}/ollama-compose.yml" << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
fi

cat >> "${STACKS_DIR}/ollama-compose.yml" << 'EOF'

networks:
  ai-platform:
    external: true
EOF

docker compose -f "${STACKS_DIR}/ollama-compose.yml" up -d
log "Ollama deployed on port ${OLLAMA_PORT}"

# =============================================================================
# Deploy Dify
# =============================================================================

info "[6/8] Deploying Dify platform..."

cat > "${STACKS_DIR}/dify-compose.yml" << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: dify-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-dify}
      POSTGRES_USER: ${DIFY_DB_USER}
      POSTGRES_PASSWORD: ${DIFY_DB_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - dify-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DIFY_DB_USER}"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - dify-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10

  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: dify-weaviate
    restart: unless-stopped
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      CLUSTER_HOSTNAME: 'node1'
    volumes:
      - ${DATA_DIR}/weaviate:/var/lib/weaviate
    networks:
      - dify-network

  sandbox:
    image: langgenius/dify-sandbox:latest
    container_name: dify-sandbox
    restart: unless-stopped
    environment:
      API_KEY: ${DIFY_SECRET_KEY}
      GIN_MODE: release
      WORKER_TIMEOUT: 15
    volumes:
      - ${DATA_DIR}/sandbox/dependencies:/dependencies
    networks:
      - dify-network
    cap_add:
      - SYS_ADMIN

  api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB:-dify}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://redis:6379/1
      BROKER_USE_SSL: 'false'
      WEB_API_CORS_ALLOW_ORIGINS: '*'
      CONSOLE_CORS_ALLOW_ORIGINS: '*'
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/storage
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      CODE_EXECUTION_ENDPOINT: http://sandbox:8194
      CODE_EXECUTION_API_KEY: ${DIFY_SECRET_KEY}
    volumes:
      - ${DATA_DIR}/storage:/app/storage
    networks:
      - dify-network
      - ai-platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    environment:
      MODE: worker
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB:-dify}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://redis:6379/1
      BROKER_USE_SSL: 'false'
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/storage
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      CODE_EXECUTION_ENDPOINT: http://sandbox:8194
      CODE_EXECUTION_API_KEY: ${DIFY_SECRET_KEY}
    volumes:
      - ${DATA_DIR}/storage:/app/storage
    networks:
      - dify-network
      - ai-platform
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: http://${TAILSCALE_IP}:${DIFY_API_PORT}
      APP_API_URL: http://${TAILSCALE_IP}:${DIFY_API_PORT}
    networks:
      - dify-network

  nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    ports:
      - "${DIFY_API_PORT}:80"
      - "${DIFY_WEB_PORT}:81"
    volumes:
      - ${STACKS_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - dify-network
    depends_on:
      - api
      - web

networks:
  dify-network:
    external: true
  ai-platform:
    external: true
EOF

# Create nginx config
cat > "${STACKS_DIR}/nginx.conf" << 'EOF'
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
    client_max_body_size 15M;

    # API Server
    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://api:5001;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
            proxy_buffering off;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }
    }

    # Web Frontend
    server {
        listen 81;
        server_name _;

        location / {
            proxy_pass http://web:3000;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

docker compose -f "${STACKS_DIR}/dify-compose.yml" up -d
log "Dify deployed (API: ${DIFY_API_PORT}, Web: ${DIFY_WEB_PORT})"

# =============================================================================
# Deploy n8n
# =============================================================================

info "[7/8] Deploying n8n workflow automation..."

cat > "${STACKS_DIR}/n8n-compose.yml" << 'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=${TAILSCALE_IP}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://${TAILSCALE_IP}:${N8N_PORT}/
      - GENERIC_TIMEZONE=UTC
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOF

docker compose -f "${STACKS_DIR}/n8n-compose.yml" up -d
log "n8n deployed on port ${N8N_PORT}"

# =============================================================================
# Deployment Summary
# =============================================================================

info "[8/8] Waiting for services to start..."
sleep 10

header "Deployment Complete!"
echo ""
echo "Service URLs:"
echo "  • LiteLLM:    http://${TAILSCALE_IP}:${LITELLM_PORT}"
echo "  • Ollama:     http://${TAILSCALE_IP}:${OLLAMA_PORT}"
echo "  • Dify API:   http://${TAILSCALE_IP}:${DIFY_API_PORT}"
echo "  • Dify Web:   http://${TAILSCALE_IP}:${DIFY_WEB_PORT}"
echo "  • n8n:        http://${TAILSCALE_IP}:${N8N_PORT}"
echo ""
echo "Credentials stored in: ${ENV_FILE}"
echo ""
echo "Check status: docker ps"
echo "View logs: docker compose -f ${STACKS_DIR}/<service>-compose.yml logs -f"
echo ""
log "All services deployed successfully!"
echo ""
