#!/bin/bash

#
# AI Platform - Deploy Services Script (v2.2.0)
#
# This script dynamically generates and deploys the complete AI platform stack
# with strict non-root execution, zero-trust networking, and host bind mounts only
#
# CRITICAL: No data should ever be stored in /var/lib/docker/volumes
# ALL data must use host bind mounts to tenant directories
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# GLOBAL CONFIGURATION
# ─────────────────────────────────────────────────────────────

# Source tenant environment file FIRST to prevent unbound variable errors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-detect tenant configuration
DATA_BASE_PATH="/mnt/data"
if [[ -f "${DATA_BASE_PATH}/datasquiz/.env" ]]; then
    ENV_FILE="${DATA_BASE_PATH}/datasquiz/.env"
    TENANT_ID="datasquiz"
elif [[ -f "${PROJECT_ROOT}/.env" ]]; then
    ENV_FILE="${PROJECT_ROOT}/.env"
    TENANT_ID="$(basename "$PROJECT_ROOT")"
else
    echo "❌ ERROR: Cannot find tenant .env file"
    echo "Expected locations:"
    echo "  - ${DATA_BASE_PATH}/datasquiz/.env"
    echo "  - ${PROJECT_ROOT}/.env"
    exit 1
fi

# Source environment variables
if [[ -f "$ENV_FILE" ]]; then
    echo "[OK]    Using .env: $ENV_FILE"
    # shellcheck source=/dev/null
    source "$ENV_FILE"
else
    echo "❌ ERROR: .env file not found: $ENV_FILE"
    exit 1
fi

# Set derived variables
COMPOSE_PROJECT_NAME="${PROJECT_PREFIX}${TENANT_ID}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}-net"
DATA_ROOT="${TENANT_DIR:-${DATA_BASE_PATH}/${TENANT_ID}}"
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# ─────────────────────────────────────────────────────────────
# PHASE 1: VOLUME OWNERSHIP & DIRECTORY PRE-CREATION
# ─────────────────────────────────────────────────────────────

create_directories() {
    log "INFO" "Creating tenant directories with proper ownership..."
    
    local dirs=(
        "${DATA_ROOT}/compose"
        "${DATA_ROOT}/caddy"
        "${DATA_ROOT}/caddy/config"
        "${DATA_ROOT}/caddy/data"
        "${DATA_ROOT}/postgres"
        "${DATA_ROOT}/postgres/init"
        "${DATA_ROOT}/redis"
        "${DATA_ROOT}/ollama"
        "${DATA_ROOT}/n8n"
        "${DATA_ROOT}/flowise"
        "${DATA_ROOT}/anythingllm"
        "${DATA_ROOT}/qdrant"
        "${DATA_ROOT}/litellm"
        "${DATA_ROOT}/grafana"
        "${DATA_ROOT}/prometheus"
        "${DATA_ROOT}/authentik/media"
        "${DATA_ROOT}/authentik/certs"
        "${DATA_ROOT}/openwebui"
        "${DATA_ROOT}/signal-api"
        "${DATA_ROOT}/tailscale"
        "${DATA_ROOT}/rclone/config"
        "${DATA_ROOT}/gdrive"
        "${DATA_ROOT}/dify/api"
        "${DATA_ROOT}/dify/web"
        "${DATA_ROOT}/dify/sandbox"
    )

    # Create all directories
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "INFO" "Created directory: $dir"
        fi
    done

    # CRITICAL: Set tenant ownership for ALL directories before Docker starts
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    log "SUCCESS" "All directories created with tenant ownership (${TENANT_UID}:${TENANT_GID})"
    
    # Special handling for PostgreSQL data directory (must be owned by postgres user 70:70)
    if [[ -d "${DATA_ROOT}/postgres" ]]; then
        chown -R 70:70 "${DATA_ROOT}/postgres"
        log "INFO" "PostgreSQL directory ownership set to postgres user (70:70)"
    fi
    
    log "SUCCESS" "Directory setup complete"
}

# ─────────────────────────────────────────────────────────────
# PHASE 2: CONFIGURATION GENERATION
# ─────────────────────────────────────────────────────────────

generate_postgres_init() {
    local init_dir="${DATA_ROOT}/postgres/init"
    
    cat > "${init_dir}/01-create-databases.sql" << 'EOF'
-- Create databases for services
CREATE DATABASE n8n;
CREATE DATABASE grafana;
CREATE DATABASE anythingllm;
CREATE DATABASE dify;

-- Create users with proper permissions
CREATE USER n8n_user WITH PASSWORD 'n8n_password';
CREATE USER grafana_user WITH PASSWORD 'grafana_password';
CREATE USER anythingllm_user WITH PASSWORD 'anythingllm_password';
CREATE USER dify_user WITH PASSWORD 'dify_password';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana_user;
GRANT ALL PRIVILEGES ON DATABASE anythingllm TO anythingllm_user;
GRANT ALL PRIVILEGES ON DATABASE dify TO dify_user;
EOF

    log "SUCCESS" "PostgreSQL init scripts created"
}

generate_prometheus_config() {
    local prometheus_dir="${DATA_ROOT}/prometheus"
    
    cat > "${prometheus_dir}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker-containers'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 30s

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
    metrics_path: /metrics

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: /healthz
    scrape_interval: 30s

  - job_name: 'openwebui'
    static_configs:
      - targets: ['openwebui:8080']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'anythingllm'
    static_configs:
      - targets: ['anythingllm:3001']
    metrics_path: /api/health
    scrape_interval: 30s

  - job_name: 'flowise'
    static_configs:
      - targets: ['flowise:3000']
    metrics_path: /api/v1/health
    scrape_interval: 30s

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3002']
    metrics_path: /api/health
    scrape_interval: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    log "SUCCESS" "Prometheus config generated at ${prometheus_dir}/prometheus.yml"
}

generate_litellm_config() {
    local litellm_dir="${DATA_ROOT}/litellm"
    
    cat > "${litellm_dir}/config.yaml" << EOF
model_list:
  - model_name: ollama/llama3.2:1b
    litellm_params:
      model: ollama/llama3.2:1b
      api_base: http://ollama:11434
  - model_name: ollama/qwen2.5:7b
    litellm_params:
      model: ollama/qwen2.5:7b
      api_base: http://ollama:11434
  - model_name: ollama/llama3.1:8b
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: http://ollama:11434

general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:${POSTGRES_INTERNAL_PORT}/litellm"
  redis_url: "redis://redis:${REDIS_INTERNAL_PORT}"

router_settings:
  routing_strategy: "${LITELLM_ROUTING_STRATEGY}"
  model_group_alias:
    "gpt-3.5-turbo":
      - "ollama/llama3.2:1b"
      - "ollama/qwen2.5:7b"
    "gpt-4":
      - "ollama/llama3.1:8b"
      - "ollama/qwen2.5:7b"

litellm_settings:
  drop_params: true
  set_verbose: false
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]

security_settings:
  require_api_key: true
  api_key_cache_redis:
    redis_url: "redis://redis:${REDIS_INTERNAL_PORT}"
EOF

    log "SUCCESS" "LiteLLM config with routing strategy generated at ${litellm_dir}/config.yaml"
}

# ─────────────────────────────────────────────────────────────
# PHASE 3: DOCKER COMPOSE GENERATION (NO NAMED VOLUMES)
# ─────────────────────────────────────────────────────────────

generate_compose() {
    log "INFO" "Generating docker-compose.yml → ${COMPOSE_FILE}"
    
    # Create compose file with header
    cat > "${COMPOSE_FILE}" << EOF
version: '3.8'

services:
EOF

    # Add core services
    append_postgres
    append_redis
    append_ollama
    append_qdrant
    append_prometheus
    append_caddy

    # Add optional services based on configuration
    [[ "${ENABLE_OPENWEBUI}" = "true" ]] && append_openwebui
    [[ "${ENABLE_ANYTHINGLLM}" = "true" ]] && append_anythingllm
    [[ "${ENABLE_N8N}" = "true" ]] && append_n8n
    [[ "${ENABLE_FLOWISE}" = "true" ]] && append_flowise
    [[ "${ENABLE_LITELLM}" = "true" ]] && append_litellm
    [[ "${ENABLE_GRAFANA}" = "true" ]] && append_grafana
    [[ "${ENABLE_AUTHENTIK}" = "true" ]] && append_authentik
    [[ "${ENABLE_MINIO}" = "true" ]] && append_minio
    [[ "${ENABLE_SIGNAL}" = "true" ]] && append_signal
    [[ "${ENABLE_TAILSCALE}" = "true" ]] && append_tailscale
    [[ "${ENABLE_OPENCLAW}" = "true" ]] && append_openclaw
    [[ "${ENABLE_RCLONE}" = "true" ]] && append_rclone

    # Add network configuration
    cat >> "${COMPOSE_FILE}" << EOF

networks:
  ${DOCKER_NETWORK}:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

    # NOTE: NO NAMED VOLUMES DECLARATION - ALL HOST BIND MOUNTS ONLY
    log "SUCCESS" "Docker Compose generated with host bind mounts only"
}

# ─────────────────────────────────────────────────────────────
# SERVICE DEFINITIONS (PHASE 3: NON-ROOT EXECUTION)
# ─────────────────────────────────────────────────────────────

append_postgres() {
    cat >> "${COMPOSE_FILE}" << EOF

  postgres:
    image: postgres:15-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-postgres
    restart: unless-stopped
    # NOTE: PostgreSQL runs as default postgres user (UID 70) - no tenant user mapping
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
    volumes:
      - ${DATA_ROOT}/postgres:/var/lib/postgresql/data
      - ${DATA_ROOT}/postgres/init:/docker-entrypoint-initdb.d
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
EOF
}

append_redis() {
    cat >> "${COMPOSE_FILE}" << EOF

  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-redis
    restart: unless-stopped
    # NOTE: Redis runs as default redis user - no tenant user mapping
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${DATA_ROOT}/redis:/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
EOF
}

append_ollama() {
    cat >> "${COMPOSE_FILE}" << EOF

  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}-ollama
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_PORT=${OLLAMA_INTERNAL_PORT}
    volumes:
      - ${DATA_ROOT}/ollama:/root/.ollama
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${OLLAMA_INTERNAL_PORT}/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    # Add port mapping only if Tailscale IP is available
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
    ports:
      - "${TAILSCALE_IP}:${OLLAMA_PORT}:${OLLAMA_INTERNAL_PORT}"
EOF
    fi
}

append_qdrant() {
    cat >> "${COMPOSE_FILE}" << EOF

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${COMPOSE_PROJECT_NAME}-qdrant
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - QDRANT__SERVICE__HTTP_PORT=${QDRANT_INTERNAL_HTTP_PORT}
      - QDRANT__SERVICE__GRPC_PORT=${QDRANT_INTERNAL_PORT}
    volumes:
      - ${DATA_ROOT}/qdrant:/qdrant/storage
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:${QDRANT_INTERNAL_HTTP_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
}

append_prometheus() {
    cat >> "${COMPOSE_FILE}" << EOF

  prometheus:
    image: prom/prometheus:latest
    container_name: ${COMPOSE_PROJECT_NAME}-prometheus
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    volumes:
      - ${DATA_ROOT}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${DATA_ROOT}/prometheus:/prometheus
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
}

append_caddy() {
    cat >> "${COMPOSE_FILE}" << EOF

  caddy:
    image: caddy:2-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-caddy
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - CADDY_INGRESS_NETWORKS=${DOCKER_NETWORK}
    volumes:
      - ${DATA_ROOT}/caddy/config/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DATA_ROOT}/caddy/data:/data
      - ${DATA_ROOT}/caddy/logs:/var/log/caddy
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    # Add port mappings for reverse proxy
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
    ports:
      - "${TAILSCALE_IP}:${CADDY_HTTP_PORT}:${CADDY_INTERNAL_HTTP_PORT}"
      - "${TAILSCALE_IP}:${CADDY_HTTPS_PORT}:${CADDY_INTERNAL_HTTPS_PORT}"
      - "${TAILSCALE_IP}:2019:2019"
EOF
    fi
}

append_litellm() {
    cat >> "${COMPOSE_FILE}" << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${COMPOSE_PROJECT_NAME}-litellm
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - LITELLM_PORT=${LITELLM_INTERNAL_PORT}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:${POSTGRES_INTERNAL_PORT}/litellm
      - REDIS_URL=redis://redis:${REDIS_INTERNAL_PORT}
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
    volumes:
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_ROOT}/litellm/logs:/app/logs
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${LITELLM_INTERNAL_PORT}/health/v1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
}

append_openwebui() {
    cat >> "${COMPOSE_FILE}" << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}-openwebui
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - PORT=${OPENWEBUI_INTERNAL_PORT}
      - OLLAMA_BASE_URL=http://ollama:${OLLAMA_INTERNAL_PORT}
      - OPENAI_API_BASE_URL=http://litellm:${LITELLM_INTERNAL_PORT}
      - WEBUI_NAME=${COMPOSE_PROJECT_NAME}
      - DEFAULT_MODELS=ollama/llama3.2:1b,ollama/qwen2.5:7b,ollama/llama3.1:8b
    volumes:
      - ${DATA_ROOT}/openwebui:/app/backend/data
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      ollama:
        condition: service_healthy
      litellm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${OPENWEBUI_INTERNAL_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

append_anythingllm() {
    cat >> "${COMPOSE_FILE}" << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: ${COMPOSE_PROJECT_NAME}-anythingllm
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - PORT=${ANYTHINGLLM_INTERNAL_PORT}
      - OPEN_AI_API_KEY=${ANYTHINGLLM_API_KEY}
      - OPEN_AI_BASE_URL=http://litellm:${LITELLM_INTERNAL_PORT}
      - STORAGE_DIR=/app/server/storage
      - VECTOR_DB=qdrant
      - QDRANT_ENDPOINT=http://qdrant:${QDRANT_INTERNAL_HTTP_PORT}
      - QDRANT_API_KEY=${QDRANT_API_KEY}
    volumes:
      - ${DATA_ROOT}/anythingllm:/app/server/storage
      - ${DATA_ROOT}/anythingllm/documents:/app/server/storage/documents
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_healthy
      litellm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${ANYTHINGLLM_INTERNAL_PORT}/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

append_n8n() {
    cat >> "${COMPOSE_FILE}" << EOF

  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}-n8n
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - N8N_HOST=n8n
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://n8n:5678/
      - N8N_EDITOR_BASE_URL=http://n8n:5678/
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=${POSTGRES_INTERNAL_PORT}
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=${REDIS_INTERNAL_PORT}
      - OPEN_AI_API_KEY=${N8N_API_KEY}
      - OPEN_AI_BASE_URL=http://litellm:${LITELLM_INTERNAL_PORT}
    volumes:
      - ${DATA_ROOT}/n8n:/home/node/.n8n
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      litellm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
}

append_flowise() {
    cat >> "${COMPOSE_FILE}" << EOF

  flowise:
    image: flowiseai/flowise:latest
    container_name: ${COMPOSE_PROJECT_NAME}-flowise
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - PORT=${FLOWISE_INTERNAL_PORT}
      - DATABASE_PATH=/app/.flowise
      - DATABASE_TYPE=postgres
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=${POSTGRES_INTERNAL_PORT}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=flowise
      - OPENAI_API_KEY=${FLOWISE_SECRET_KEY}
      - OPENAI_BASE_URL=http://litellm:${LITELLM_INTERNAL_PORT}
      - QDRANT_URL=http://qdrant:${QDRANT_INTERNAL_HTTP_PORT}
      - QDRANT_API_KEY=${QDRANT_API_KEY}
    volumes:
      - ${DATA_ROOT}/flowise:/app/.flowise
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_healthy
      litellm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${FLOWISE_INTERNAL_PORT}/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

append_grafana() {
    cat >> "${COMPOSE_FILE}" << EOF

  grafana:
    image: grafana/grafana:latest
    container_name: ${COMPOSE_PROJECT_NAME}-grafana
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
      - GF_SERVER_ROOT_URL=http://grafana:${GRAFANA_INTERNAL_PORT}
      - GF_DATABASE_TYPE=postgres
      - GF_DATABASE_HOST=postgres:${POSTGRES_INTERNAL_PORT}
      - GF_DATABASE_NAME=grafana
      - GF_DATABASE_USER=${POSTGRES_USER}
      - GF_DATABASE_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ${DATA_ROOT}/grafana:/var/lib/grafana
      - ${DATA_ROOT}/grafana/logs:/var/log/grafana
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${GRAFANA_INTERNAL_PORT}/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

append_tailscale() {
    cat >> "${COMPOSE_FILE}" << EOF

  tailscale:
    image: tailscale/tailscale:latest
    container_name: ${COMPOSE_PROJECT_NAME}-tailscale
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_SOCKET=/var/run/tailscale/tailscaled.sock
    volumes:
      - ${DATA_ROOT}/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    networks:
      - ${DOCKER_NETWORK}
    command: tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock
EOF
}

append_openclaw() {
    # Check if OpenClaw image exists locally
    if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${OPENCLAW_IMAGE:-openclaw:latest}$"; then
        log "WARN" "OpenClaw image ${OPENCLAW_IMAGE:-openclaw:latest} not found locally — skipping OpenClaw service"
        log "INFO" "To deploy OpenClaw, build/pull image first or set OPENCLAW_IMAGE to available image"
        return
    fi

    cat >> "${COMPOSE_FILE}" << EOF

  openclaw:
    image: ${OPENCLAW_IMAGE:-openclaw:latest}
    container_name: ${COMPOSE_PROJECT_NAME}-openclaw
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - OPENCLAW_PORT=${OPENCLAW_INTERNAL_PORT}
      - OPENCLAW_PASSWORD=${OPENCLAW_PASSWORD}
      - OPENAI_API_KEY=${OPENCLAW_API_KEY}
      - OPENAI_BASE_URL=http://litellm:${LITELLM_INTERNAL_PORT}
    volumes:
      - ${DATA_ROOT}/openclaw:/app/data
      - ${DATA_ROOT}/openclaw/logs:/app/logs
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      litellm:
        condition: service_healthy
    # PHASE 3: ZERO-TRUST SANDBOX
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${OPENCLAW_INTERNAL_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    # Add Tailscale port mapping
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
    ports:
      - "${TAILSCALE_IP}:${OPENCLAW_PORT}:${OPENCLAW_INTERNAL_PORT}"
EOF
    fi
}

# Placeholder functions for other services
append_authentik() { :; }
append_minio() { :; }
append_signal() { :; }
append_rclone() { :; }

# ─────────────────────────────────────────────────────────────
# PHASE 4: CADDYFILE GENERATION
# ─────────────────────────────────────────────────────────────

generate_caddyfile() {
    local caddyfile="${DATA_ROOT}/caddy/config/Caddyfile"
    
    cat > "${caddyfile}" << EOF
{
    email ${ACME_EMAIL:-admin@${DOMAIN}}
    admin localhost:2019
}

# Global settings
{
    log {
        output file ${DATA_ROOT}/logs/caddy-global.log {
            roll_size 10mb
            roll_keep 5
        }
        level INFO
    }
}

# Reverse proxy configurations
EOF

    # Add service configurations based on enabled services
    if [[ "${ENABLE_OPENWEBUI}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
openwebui.${DOMAIN} {
    reverse_proxy openwebui:${OPENWEBUI_INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-openwebui.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    if [[ "${ENABLE_ANYTHINGLLM}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:${ANYTHINGLLM_INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-anythingllm.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    if [[ "${ENABLE_N8N}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
n8n.${DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        flush_interval -1
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-n8n.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    if [[ "${ENABLE_FLOWISE}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
flowise.${DOMAIN} {
    reverse_proxy flowise:${FLOWISE_INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-flowise.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    if [[ "${ENABLE_LITELLM}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:${LITELLM_INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-litellm.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    if [[ "${ENABLE_GRAFANA}" = "true" ]]; then
        cat >> "${caddyfile}" << EOF
grafana.${DOMAIN} {
    reverse_proxy grafana:${GRAFANA_INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-grafana.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    fi

    log "SUCCESS" "Caddyfile generated at ${caddyfile}"
}

# ─────────────────────────────────────────────────────────────
# DEPLOYMENT FUNCTIONS
# ─────────────────────────────────────────────────────────────

preflight_checks() {
    log "INFO" "Running pre-flight checks..."
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker not found"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Docker daemon not running"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose not found"
        exit 1
    fi
    
    # Check EBS volume mount
    if ! mountpoint -q "${DATA_BASE_PATH}" 2>/dev/null; then
        log "WARN" "EBS volume not mounted at ${DATA_BASE_PATH}"
    else
        log "SUCCESS" "EBS volume mounted at ${DATA_BASE_PATH}"
    fi
    
    log "SUCCESS" "Pre-flight checks passed"
}

teardown_existing() {
    log "INFO" "Tearing down existing ${COMPOSE_PROJECT_NAME} deployment..."
    
    cd "${DATA_ROOT}"
    
    if [[ -f "docker-compose.yml" ]]; then
        docker compose down --volumes --remove-orphans 2>/dev/null || true
        log "INFO" "Existing deployment stopped"
    fi
    
    # Remove any orphaned containers
    local orphaned_containers
    orphaned_containers=$(docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}-" 2>/dev/null || true)
    if [[ -n "$orphaned_containers" ]]; then
        docker rm -f $orphaned_containers 2>/dev/null || true
        log "INFO" "Orphaned containers removed"
    fi
    
    # Remove network if exists
    local network_exists
    network_exists=$(docker network ls -q --filter "name=${DOCKER_NETWORK}" 2>/dev/null || true)
    if [[ -n "$network_exists" ]]; then
        docker network rm "${DOCKER_NETWORK}" 2>/dev/null || true
        log "INFO" "Old network removed"
    fi
    
    log "SUCCESS" "Teardown complete"
}

deploy_stack() {
    log "INFO" "Starting deployment from ${COMPOSE_FILE}"
    
    cd "${DATA_ROOT}"
    
    # Pull images
    log "INFO" "Pulling images..."
    docker compose pull
    
    # Start services
    log "INFO" "Starting services..."
    docker compose up -d
    
    # Wait for health checks
    log "INFO" "Waiting for services to become healthy..."
    local max_wait=300
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local unhealthy_count
        unhealthy_count=$(docker compose ps --format "table {{.Service}} {{.Status}}" | grep -c "unhealthy\|starting" || true)
        
        if [[ $unhealthy_count -eq 0 ]]; then
            log "SUCCESS" "All services are healthy"
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        log "INFO" "Waiting for services... (${wait_time}s/${max_wait}s)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log "WARN" "Some services may not be healthy within timeout"
        docker compose ps
    fi
    
    log "SUCCESS" "Deployment complete"
}

# ─────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────

main() {
    log "INFO" "══════════════════════════════════════════════════════"
    log "INFO" "   AI Platform Deploy — Tenant: ${TENANT_ID}"
    log "INFO" "   Domain: ${DOMAIN}"
    log "INFO" "   Services: ${ENABLE_OPENWEBUI} ${ENABLE_ANYTHINGLLM} ${ENABLE_N8N} ${ENABLE_FLOWISE} ${ENABLE_OPENCLAW} ${ENABLE_LITELLM} ${ENABLE_OLLAMA} ${ENABLE_GRAFANA} ${ENABLE_TAILSCALE}"
    log "INFO" "══════════════════════════════════════════════════════"
    
    # Phase 1: Directory pre-creation and ownership
    create_directories
    
    # Phase 2: Configuration generation
    generate_postgres_init
    generate_prometheus_config
    generate_litellm_config
    
    # Phase 3: Docker Compose generation (no named volumes)
    generate_compose
    
    # Phase 4: Caddyfile generation
    generate_caddyfile
    
    # Deployment
    preflight_checks
    teardown_existing
    deploy_stack
    
    log "SUCCESS" "🎉 AI Platform deployment complete!"
    log "INFO" "Next: Run 'sudo bash scripts/3-configure-services.sh' for service configuration"
}

# Execute main function
main "$@"
