#!/usr/bin/env bash
# 2-deploy-services.sh
# Reads .env → generates docker-compose.yml → tears down old network → deploys
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ── Load Environment ───────────────────────────────────────────────
# Priority 1: TENANT_DIR environment variable
# Priority 2: Search under /mnt/data for most recent .env
# Priority 3: Search under /opt/ai-platform
if [[ -n "${TENANT_DIR:-}" && -f "${TENANT_DIR}/.env" ]]; then
  ENV_FILE="${TENANT_DIR}/.env"
else
  ENV_FILE="$(sudo ls -t /mnt/data/*/.env 2>/dev/null | head -1)"
fi

[[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]] && \
  fail "Cannot find .env file. Run script 1 first."

ok "Using .env: ${ENV_FILE}"

# ── Load environment — must happen before functions are defined ─────────────
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

# Set defaults for all service flags to prevent unbound variable errors
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
ENABLE_DIFY="${ENABLE_DIFY:-false}"
ENABLE_N8N="${ENABLE_N8N:-false}"
ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
ENABLE_SIGNAL="${ENABLE_SIGNAL:-false}"
ENABLE_TAILSCALE="${ENABLE_TAILSCALE:-false}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
ENABLE_RCLONE="${ENABLE_RCLONE:-false}"
ENABLE_MINIO="${ENABLE_MINIO:-false}"

# Set project name based on tenant ID
COMPOSE_PROJECT_NAME="aip-${TENANT_ID:-aip-default}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"

# Set tenant UID/GID for non-root containers
TENANT_UID=$(id -u)
TENANT_GID=$(id -g)

# Set default database credentials
POSTGRES_USER="${POSTGRES_USER:-platform}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_DB="${POSTGRES_DB:-platform}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
LITELLM_SALT_KEY="${LITELLM_SALT_KEY:-}"
ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY:-}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY:-}"

# ── Critical Validations ───────────────────────────────────────────────
if [ "${DOMAIN}" = "localhost" ] || [ -z "${DOMAIN}" ]; then
    fail "DOMAIN is '${DOMAIN}'. Set DOMAIN_NAME in .env and re-run script 1 first."
fi

log "Domain: ${DOMAIN}"

check_tailscale_auth() {
    TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        warn "TAILSCALE_AUTH_KEY not set in .env"
        warn "Tailscale will start but NOT authenticate"
        warn "Get a key: https://login.tailscale.com/admin/settings/keys"
        warn "Add to .env: TAILSCALE_AUTH_KEY=tskey-auth-xxxxx"
        warn "Then re-run: sudo bash scripts/2-deploy-services.sh"
    else
        log "Tailscale auth key found — will auto-authenticate"
    fi
}
check_tailscale_auth

# ── Structured Logging Setup ───────────────────────────────────────
LOG_DIR="${DATA_ROOT}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/script-2-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# ── Teardown Block (replaces need to run script 0 + 1 on reruns) ─────
teardown_existing() {
    log "Tearing down existing ${COMPOSE_PROJECT_NAME} deployment..."
    
    local compose_file="${DATA_ROOT}/docker-compose.yml"

    # If prior compose file exists, use it to bring down cleanly
    if [ -f "${compose_file}" ]; then
        docker compose \
            --project-name "${COMPOSE_PROJECT_NAME}" \
            -f "${compose_file}" \
            down --remove-orphans --timeout 30 2>/dev/null || true
    fi

    # Belt-and-suspenders: force-remove any lingering containers
    docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}" | \
        xargs -r docker rm -f 2>/dev/null || true

    # NOW safe to remove network
    docker network ls --filter "name=${COMPOSE_PROJECT_NAME}" -q | \
        xargs -r docker network rm 2>/dev/null || true

    # Prune dangling networks
    docker network prune -f 2>/dev/null || true

    log "Teardown complete"
}

# ── Pre-flight Checks ───────────────────────────────────────────────
preflight_checks() {
    log "INFO" "Running pre-flight checks..."

    # Check ports 80 and 443 are not already bound
    for port in 80 443; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            log "ERROR" "Port ${port} already in use — Caddy cannot start"
            log "ERROR" "Run: sudo ss -tlnp | grep :${port} to identify process"
            exit 1
        fi
    done

    # Check DNS resolves to this machine (warn only, not fail)
    local public_ip
    public_ip=$(curl -sf --max-time 5 https://api.ipify.org || \
                curl -sf --max-time 5 http://checkip.amazonaws.com || \
                echo "unknown")

    if [ "${public_ip}" != "unknown" ]; then
        log "INFO" "Public IP: ${public_ip}"
        log "WARN" "Ensure DNS A records point to ${public_ip} before Caddy starts"
        log "WARN" "Ensure EC2 security group allows inbound port 80 and 443"
    fi

    # Check Docker daemon is running
    if ! docker info &>/dev/null; then
        log "ERROR" "Docker daemon not running"
        exit 1
    fi

    # Check EBS mount - look for /mnt/data (mounted EBS) or /mnt (legacy)
    if ! mountpoint -q /mnt/data && ! mountpoint -q /mnt; then
        log "ERROR" "No EBS volume mounted at /mnt/data or /mnt — EBS not attached"
        log "INFO" "Available block devices:"
        sudo lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "^nvme|^xvd|^sd" || true
        exit 1
    fi
    
    if mountpoint -q /mnt/data; then
        log "SUCCESS" "EBS volume mounted at /mnt/data"
    elif mountpoint -q /mnt; then
        log "SUCCESS" "EBS volume mounted at /mnt"
    fi

    log "SUCCESS" "Pre-flight checks passed"
}

# ── Directory Setup ───────────────────────────────────────────────
setup_directories() {
    local dirs=(
        "${DATA_ROOT}/postgres"
        "${DATA_ROOT}/redis"
        "${DATA_ROOT}/caddy/config"
        "${DATA_ROOT}/caddy/data"
        "${DATA_ROOT}/prometheus"
        "${DATA_ROOT}/minio"
        "${DATA_ROOT}/litellm"
        "${DATA_ROOT}/logs"
    )

    [ "${ENABLE_QDRANT}" = "true" ] && dirs+=("${DATA_ROOT}/qdrant")
    [ "${ENABLE_OLLAMA}" = "true" ] && dirs+=("${DATA_ROOT}/ollama")
    [ "${ENABLE_N8N}" = "true" ] && dirs+=("${DATA_ROOT}/n8n")
    [ "${ENABLE_FLOWISE}" = "true" ] && dirs+=("${DATA_ROOT}/flowise")
    [ "${ENABLE_DIFY}" = "true" ] && \
        dirs+=("${DATA_ROOT}/dify/storage" "${DATA_ROOT}/dify/logs")
    [ "${ENABLE_SIGNAL}" = "true" ] && dirs+=("${DATA_ROOT}/signal-api")
    [ "${ENABLE_TAILSCALE}" = "true" ] && dirs+=("${DATA_ROOT}/tailscale")
    [ "${ENABLE_RCLONE}" = "true" ] && \
        dirs+=("${DATA_ROOT}/rclone/config" "${DATA_ROOT}/gdrive")
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && dirs+=("${DATA_ROOT}/anythingllm")
    [ "${ENABLE_OPENCLAW}" = "true" ] && dirs+=("${DATA_ROOT}/openclaw")

    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done

    # Set ownership for all data dirs
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"

    # Special cases — services that run as their own UID
    # Grafana runs as 472
    [ "${ENABLE_GRAFANA}" = "true" ] && {
        mkdir -p "${DATA_ROOT}/grafana"
        chown -R 472:472 "${DATA_ROOT}/grafana"
    }
    # Prometheus runs as 65534
    mkdir -p "${DATA_ROOT}/prometheus/data"
    chown -R 65534:65534 "${DATA_ROOT}/prometheus/data"

    log "SUCCESS" "Directories created and ownership set"
}

# ── Compose Generator (the key function) ────────────────────────
generate_compose() {
    local compose_file="${DATA_ROOT}/docker-compose.yml"
    
    log "Generating docker-compose.yml → ${compose_file}"
    
    # ── Header ─────────────────────────────────────────
    cat > "${compose_file}" << COMPOSE_HEADER
# Generated by 2-deploy-services.sh
# Tenant: ${TENANT_ID} | Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT EDIT — re-run scripts/2-deploy-services.sh

networks:
  ${DOCKER_NETWORK}:
    name: ${DOCKER_NETWORK}
    driver: bridge

services:
COMPOSE_HEADER

    # ── Core Services (always deployed) ────────────────────────
    append_postgres
    append_redis
    append_caddy

    # ── Vector Database ─────────────────────────────────────────
    case "${VECTOR_DB}" in
        qdrant) append_qdrant ;;
        chroma) append_chroma ;;
        weaviate) append_weaviate ;;
    esac

    # ── Optional Services ───────────────────────────────────────
    [ "${ENABLE_MINIO}" = "true" ] && append_minio
    [ "${ENABLE_OLLAMA}" = "true" ] && append_ollama
    [ "${ENABLE_LITELLM}" = "true" ] && append_litellm
    [ "${ENABLE_OPENWEBUI}" = "true" ] && append_openwebui
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && append_anythingllm
    [ "${ENABLE_DIFY}" = "true" ] && { append_dify_api; append_dify_web; append_dify_sandbox; }
    [ "${ENABLE_N8N}" = "true" ] && append_n8n
    [ "${ENABLE_FLOWISE}" = "true" ] && append_flowise
    [ "${ENABLE_OPENCLAW}" = "true" ] && append_openclaw
    [ "${ENABLE_GRAFANA}" = "true" ] && { append_prometheus; append_grafana; }
    [ "${ENABLE_SIGNAL}" = "true" ] && append_signal
    [ "${ENABLE_TAILSCALE}" = "true" ] && append_tailscale
    [ "${ENABLE_RCLONE}" = "true" ] && append_rclone

    # ── Named Volumes (must be after all services) ────────────────
    cat >> "${compose_file}" << VOLUMES_EOF

volumes:
  ${COMPOSE_PROJECT_NAME}_postgres_data:
  ${COMPOSE_PROJECT_NAME}_redis_data:
  ${COMPOSE_PROJECT_NAME}_caddy_data:
VOLUMES_EOF

    [ "${ENABLE_MINIO}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_minio_data:" >> "${compose_file}"
    [ "${VECTOR_DB}" = "qdrant" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_qdrant_data:" >> "${compose_file}"
    [ "${ENABLE_LITELLM}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_litellm_data:" >> "${compose_file}"
    [ "${ENABLE_OLLAMA}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_ollama_data:" >> "${compose_file}"
    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_openwebui_data:" >> "${compose_file}"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_anythingllm_data:" >> "${compose_file}"
    [ "${ENABLE_N8N}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_n8n_data:" >> "${compose_file}"
    [ "${ENABLE_FLOWISE}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_flowise_data:" >> "${compose_file}"
    [ "${ENABLE_DIFY}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_dify_storage:" >> "${compose_file}"
    [ "${ENABLE_GRAFANA}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_grafana_data:" >> "${compose_file}"
    [ "${ENABLE_PROMETHEUS}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_prometheus_data:" >> "${compose_file}"
    [ "${ENABLE_SIGNAL}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_signal_data:" >> "${compose_file}"
    [ "${ENABLE_TAILSCALE}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_tailscale_data:" >> "${compose_file}"
    [ "${ENABLE_OPENCLAW}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_openclaw_data:" >> "${compose_file}"

    # Validate generated file
    docker compose -f "${compose_file}" config --quiet 2>/dev/null && {
        log "docker-compose.yml validated"
    } || {
        log "ERROR: Generated docker-compose.yml failed validation"
        log "ERROR: Run: docker compose -f ${compose_file} config"
        exit 1
    }
}

# Helper to append to compose file
compose_append() { 
    cat >> "${DATA_ROOT}/docker-compose.yml"; 
}

# ─────────────────────────────────────────────────────────────
# POSTGRES
# ─────────────────────────────────────────────────────────────
append_postgres() {
    compose_append << EOF

  postgres:
    image: postgres:15-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-postgres
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - ${COMPOSE_PROJECT_NAME}_postgres_data:/var/lib/postgresql/data
      - ${DATA_ROOT}/postgres/init:/docker-entrypoint-initdb.d:ro
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# REDIS
# ─────────────────────────────────────────────────────────────
append_redis() {
    compose_append << EOF

  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${COMPOSE_PROJECT_NAME}_redis_data:/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s
EOF
}

# ─────────────────────────────────────────────────────────────
# CADDY
# ─────────────────────────────────────────────────────────────
append_caddy() {
    # Write base caddy service
    compose_append << EOF

  caddy:
    image: caddy:2-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-caddy
    restart: unless-stopped
    ports:
      - "${CADDY_HTTP_PORT}:80"
      - "${CADDY_HTTPS_PORT}:443"
      - "443:443/udp"
      - "2019:2019"
    volumes:
      - ${DATA_ROOT}/caddy/config/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DATA_ROOT}/caddy/data:/data
      - ${COMPOSE_PROJECT_NAME}_caddy_data:/config
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF

    # Append optional service dependencies — each as a proper YAML block
    [ "${ENABLE_OPENWEBUI}" = "true" ] && compose_append << EOF
      openwebui:
        condition: service_healthy
EOF
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && compose_append << EOF
      anythingllm:
        condition: service_healthy
EOF
    [ "${ENABLE_N8N}" = "true" ] && compose_append << EOF
      n8n:
        condition: service_healthy
EOF
    [ "${ENABLE_DIFY}" = "true" ] && compose_append << EOF
      dify-api:
        condition: service_healthy
EOF
    [ "${ENABLE_FLOWISE}" = "true" ] && compose_append << EOF
      flowise:
        condition: service_healthy
EOF
    [ "${ENABLE_LITELLM}" = "true" ] && compose_append << EOF
      litellm:
        condition: service_healthy
EOF
    [ "${ENABLE_GRAFANA}" = "true" ] && compose_append << EOF
      grafana:
        condition: service_healthy
EOF

    # Append healthcheck block
    compose_append << EOF
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

# ─────────────────────────────────────────────────────────────
# QDRANT
# ─────────────────────────────────────────────────────────────
append_qdrant() {
    compose_append << EOF

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${COMPOSE_PROJECT_NAME}-qdrant
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${QDRANT_PORT}:6333"
      - "6334:6334"
    volumes:
      - ${COMPOSE_PROJECT_NAME}_qdrant_data:/qdrant/storage
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:6333/"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 20s
EOF
}

# ─────────────────────────────────────────────────────────────
# OLLAMA — GPU-aware
# ─────────────────────────────────────────────────────────────
append_ollama() {
    # Base service definition
    compose_append << EOF

  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}-ollama
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ${DATA_ROOT}/ollama:/root/.ollama
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 20s
      retries: 5
      start_period: 60s
EOF

    # Append GPU config if detected
    if [ "${GPU_TYPE}" = "nvidia" ]; then
        compose_append << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
        labels:
    com.ai-platform: "true"
EOF/a
i

  node-exporter:
    image: prom/node-exporter:latest
    container_name: ${COMPOSE_PROJECT_NAME}-node-exporter
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK}
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)"
    labels:
      com.ai-platform: "true"
EOF
      com.ai-platform: "true"
EOF
  node-exporter:
    image: prom/node-exporter:latest
    container_name: ${COMPOSE_PROJECT_NAME}-node-exporter
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK}
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    labels:
    com.ai-platform: "true"
EOF/a
i

  node-exporter:
    image: prom/node-exporter:latest
    container_name: ${COMPOSE_PROJECT_NAME}-node-exporter
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK}
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)"
    labels:
      com.ai-platform: "true"
EOF
      com.ai-platform: "true"
EOF
    elif [ "${GPU_TYPE}" = "amd" ]; then
        compose_append << EOF
    devices:
      - ${GPU_DEVICE}:/dev/dri/renderD128
    group_add:
      - video
EOF
    fi
}

# ─────────────────────────────────────────────────────────────
# ── PostgreSQL Init Script Generator ────────────────────────────────
generate_postgres_init() {
    local init_dir="${DATA_ROOT}/postgres/init"
    mkdir -p "${init_dir}"

    # Write using PostgreSQL-compatible syntax with existence checks
    cat > "${init_dir}/01-create-databases.sql" << 'EOF'
SELECT 'CREATE DATABASE litellm' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec
SELECT 'CREATE DATABASE dify' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dify')\gexec
SELECT 'CREATE DATABASE openwebui' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'openwebui')\gexec
SELECT 'CREATE DATABASE flowise' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'flowise')\gexec
SELECT 'CREATE DATABASE authentik' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\gexec
EOF

    chmod 644 "${init_dir}/01-create-databases.sql"
    chown -R "${TENANT_UID}:${TENANT_GID}" "${init_dir}"
    log "SUCCESS" "Postgres init scripts created"
    log "INFO" "NOTE: Init scripts only run on first Postgres start with empty data dir"
    log "INFO" "If re-deploying with existing data, databases already exist — this is fine"
}

# ─────────────────────────────────────────────────────────────
# LITELM CONFIG GENERATOR
# ─────────────────────────────────────────────────────────────
generate_litellm_config() {
    [ "${ENABLE_LITELLM}" = "true" ] || return 0
    local litellm_dir="${DATA_ROOT}/litellm"
    mkdir -p "${litellm_dir}"

    cat > "${litellm_dir}/config.yaml" << EOF
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm

litellm_settings:
  drop_params: true
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: ${REDIS_PASSWORD}

model_list:
EOF

    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        cat >> "${litellm_dir}/config.yaml" << EOF
  - model_name: ${OLLAMA_DEFAULT_MODEL}
    litellm_params:
      model: ollama/${OLLAMA_DEFAULT_MODEL}
      api_base: http://ollama:11434
EOF
    fi

    [ -n "${OPENAI_API_KEY:-}" ] && cat >> "${litellm_dir}/config.yaml" << EOF
  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: ${OPENAI_API_KEY}
EOF

    [ -n "${GOOGLE_API_KEY:-}" ] && cat >> "${litellm_dir}/config.yaml" << EOF
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash-exp
      api_key: ${GOOGLE_API_KEY}
EOF

    chown -R "${TENANT_UID}:${TENANT_GID}" "${litellm_dir}"
    log "SUCCESS" "LiteLLM config generated at ${litellm_dir}/config.yaml"
}

# ─────────────────────────────────────────────────────────────
# LITELLM
# ─────────────────────────────────────────────────────────────
append_litellm() {
    compose_append << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${COMPOSE_PROJECT_NAME}-litellm
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${LITELLM_PORT}:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm
      - STORE_MODEL_IN_DB=True
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
EOF

    # Add API keys only if set
    [ -n "${OPENAI_API_KEY:-}" ] && \
        echo "      - OPENAI_API_KEY=${OPENAI_API_KEY}" >> "${DATA_ROOT}/docker-compose.yml"
    [ -n "${GOOGLE_API_KEY:-}" ] && \
        echo "      - VERTEX_PROJECT=${GOOGLE_API_KEY}" >> "${DATA_ROOT}/docker-compose.yml"
    [ -n "${GROQ_API_KEY:-}" ] && \
        echo "      - GROQ_API_KEY=${GROQ_API_KEY}" >> "${DATA_ROOT}/docker-compose.yml"
    [ -n "${OPENROUTER_API_KEY:-}" ] && \
        echo "      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}" >> "${DATA_ROOT}/docker-compose.yml"

    compose_append << EOF
    volumes:
      - ${COMPOSE_PROJECT_NAME}_litellm_data:/app/data
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:4000/health/readiness"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 60s
EOF
}

# ─────────────────────────────────────────────────────────────
# OPENWEBUI
# ─────────────────────────────────────────────────────────────
append_openwebui() {
    local ollama_url=""
    [ "${ENABLE_OLLAMA}" = "true" ] && ollama_url="http://ollama:11434"
    
    compose_append << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}-openwebui
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${OPENWEBUI_PORT}:8080"
    environment:
      - OLLAMA_BASE_URL=${ollama_url}
      - OPENAI_API_BASE_URL=http://litellm:4000/v1
      - OPENAI_API_KEY=${LITELLM_MASTER_KEY}
      - WEBUI_SECRET_KEY=${ANYTHINGLLM_JWT_SECRET}
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
      # Vector DB connection
      - VECTOR_DB=qdrant
      - QDRANT_URI=http://qdrant:6333
      - QDRANT_API_KEY=${QDRANT_API_KEY:-}
      - OLLAMA_BASE_URL=${ollama_url}
      - ENABLE_SIGNUP=false
      - DEFAULT_USER_ROLE=user
    volumes:
      - ${DATA_ROOT}/openwebui:/app/backend/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 35
      start_period: 60s
EOF
}

# ─────────────────────────────────────────────────────────────
# ANYTHINGLLM
# ─────────────────────────────────────────────────────────────
append_anythingllm() {
    compose_append << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: ${COMPOSE_PROJECT_NAME}-anythingllm
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${ANYTHINGLLM_PORT}:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - SERVER_PORT=3001
      - UID=${TENANT_UID}
      - GID=${TENANT_GID}
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
      # Vector DB connection
      - VECTOR_DB=${VECTOR_DB}
      - QDRANT_ENDPOINT=http://qdrant:6333
      - QDRANT_API_KEY=${QDRANT_API_KEY:-}
      # LLM connection via LiteLLM
      - LLM_PROVIDER=litellm
      - LITELLM_BASE_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
      - LITE_LLM_MODEL_PREF=${OLLAMA_DEFAULT_MODEL}
      # Auth
      - AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN}
      - EMBEDDING_ENGINE=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - EMBEDDING_MODEL_PREF=nomic-embed-text:latest
      - DISABLE_TELEMETRY=true
    volumes:
      - ${DATA_ROOT}/anythingllm:/app/server/storage
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
EOF
}

# ─────────────────────────────────────────────────────────────
# N8N
# ─────────────────────────────────────────────────────────────
append_n8n() {
    # Set network-aware configuration
    local n8n_protocol="https"
    local n8n_host="n8n.${DOMAIN}"
    local n8n_webhook_url="https://n8n.${DOMAIN}/"
    local n8n_editor_url="https://n8n.${DOMAIN}/"
    
    if [[ "${PROXY_TYPE}" != "caddy" && "${PROXY_TYPE}" != "nginx" && "${PROXY_TYPE}" != "traefik" ]]; then
        n8n_protocol="http"
        n8n_host="localhost"
        n8n_webhook_url="http://localhost:${N8N_PORT}/"
        n8n_editor_url="http://localhost:${N8N_PORT}/"
    fi
    
    compose_append << EOF

  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}-n8n
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=${n8n_host}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${n8n_protocol}
      - WEBHOOK_URL=${n8n_webhook_url}
      - N8N_EDITOR_BASE_URL=${n8n_editor_url}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - ${DATA_ROOT}/n8n:/home/node/.n8n
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s
EOF
}

# ─────────────────────────────────────────────────────────────
# FLOWISE
# ─────────────────────────────────────────────────────────────
append_flowise() {
    compose_append << EOF

  flowise:
    image: flowiseai/flowise:latest
    container_name: ${COMPOSE_PROJECT_NAME}-flowise
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${FLOWISE_PORT}:3000"
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=${FLOWISE_USERNAME}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
      - DATABASE_PATH=/data/flowise
      - APIKEY_PATH=/data/flowise
      - SECRETKEY_PATH=/data/flowise
      - LOG_PATH=/data/flowise/logs
      - BLOB_STORAGE_PATH=/data/flowise/storage
    volumes:
      - ${DATA_ROOT}/flowise:/data/flowise
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# DIFY (DISABLED - requires multi-container setup)
# ─────────────────────────────────────────────────────────────
append_dify_api() {
    [[ "${ENABLE_DIFY:-false}" != "true" ]] && return
    warn "Dify requires multi-container setup (api + worker + web + sandbox) — not yet fully implemented. Skipping."
    warn "Set ENABLE_DIFY=false in .env to suppress this warning."
}

append_dify_web() {
    [[ "${ENABLE_DIFY:-false}" != "true" ]] && return
    # No-op - handled in append_dify_api
}

append_dify_sandbox() {
    [[ "${ENABLE_DIFY:-false}" != "true" ]] && return
    # No-op - handled in append_dify_api
}

# ─────────────────────────────────────────────────────────────
# OPENCLAW (image must be verified — placeholder shown)
# ─────────────────────────────────────────────────────────────
append_openclaw() {
    [[ "${ENABLE_OPENCLAW:-false}" != "true" ]] && return
    
    if [[ -z "${OPENCLAW_IMAGE:-}" ]]; then
        log "WARN" "OPENCLAW_IMAGE not set in .env — skipping OpenClaw service"
        return
    fi
    
    log "WARN" "OpenClaw: ensure image ${OPENCLAW_IMAGE} exists locally before deploying"
    # Use configurable image name from .env
    local image="${OPENCLAW_IMAGE:-openclaw:latest}"
    
    compose_append << EOF

  openclaw:
    image: ${image}
    container_name: ${COMPOSE_PROJECT_NAME}-openclaw
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${OPENCLAW_PORT}:8082"
    environment:
      - PORT=8082
      - HOST=0.0.0.0
      - LOG_LEVEL=${OPENCLAW_LOG_LEVEL:-info}
      - QDRANT_URL=${VECTOR_DB_URL}
      - LITELLM_BASE_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
      - N8N_WEBHOOK_URL=http://n8n:5678
      - ADMIN_USER=${OPENCLAW_ADMIN_USER}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - DATA_PATH=/data
      - CONFIG_PATH=/config
      - SECRET=${OPENCLAW_SECRET}
    volumes:
      - ${DATA_ROOT}/openclaw/data:/data
      - ${DATA_ROOT}/openclaw/config:/config
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
EOF
}

# ─────────────────────────────────────────────────────────────
# PROMETHEUS CONFIG GENERATOR
# ─────────────────────────────────────────────────────────────
generate_prometheus_config() {
    [ "${ENABLE_GRAFANA}" = "true" ] || return 0
    local prom_dir="${DATA_ROOT}/prometheus"
    mkdir -p "${prom_dir}"

    cat > "${prom_dir}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
EOF

    # Add per-enabled-service scrape targets
    [ "${ENABLE_LITELLM}" = "true" ] && cat >> "${prom_dir}/prometheus.yml" << EOF

  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
EOF

    [ "${ENABLE_N8N}" = "true" ] && cat >> "${prom_dir}/prometheus.yml" << EOF

  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
EOF

    chown -R "${TENANT_UID}:${TENANT_GID}" "${prom_dir}"
    log "SUCCESS" "Prometheus config generated at ${prom_dir}/prometheus.yml"
}

# ─────────────────────────────────────────────────────────────
# PROMETHEUS + GRAFANA
# ─────────────────────────────────────────────────────────────
append_prometheus() {
    # Generate prometheus.yml first
    mkdir -p "${DATA_ROOT}/prometheus"
    cat > "${DATA_ROOT}/prometheus/prometheus.yml" << PROM
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
PROM
    chown "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}/prometheus/prometheus.yml"
    mkdir -p "${DATA_ROOT}/prometheus/data"
    chown "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}/prometheus/data"

    compose_append << EOF

  prometheus:
    image: prom/prometheus:latest
    container_name: ${COMPOSE_PROJECT_NAME}-prometheus
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ${DATA_ROOT}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${DATA_ROOT}/prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
}

append_grafana() {
    # Set network-aware configuration
    local grafana_root_url="https://grafana.${DOMAIN}"
    
    if [[ "${PROXY_TYPE}" != "caddy" && "${PROXY_TYPE}" != "nginx" && "${PROXY_TYPE}" != "traefik" ]]; then
        grafana_root_url="http://localhost:${GRAFANA_PORT}"
    fi
    
    compose_append << EOF

  grafana:
    image: grafana/grafana:latest
    container_name: ${COMPOSE_PROJECT_NAME}-grafana
    restart: unless-stopped
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
      - GF_SERVER_ROOT_URL=${grafana_root_url}
    volumes:
      - ${DATA_ROOT}/grafana:/var/lib/grafana
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# MINIO
# ─────────────────────────────────────────────────────────────
append_minio() {
    compose_append << EOF

  minio:
    image: minio/minio:latest
    container_name: ${COMPOSE_PROJECT_NAME}-minio
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${MINIO_PORT}:9000"
      - "${MINIO_CONSOLE_PORT}:9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
    volumes:
      - ${COMPOSE_PROJECT_NAME}_minio_data:/data
    command: server /data --console-address ":9001"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# TAILSCALE
# ─────────────────────────────────────────────────────────────
append_tailscale() {
    local tun_device=""
    local userspace_extra=""
    
    if [ -c "/dev/net/tun" ]; then
        tun_device="      - /dev/net/tun:/dev/net/tun"
        log "INFO" "TUN device found — Tailscale kernel mode enabled"
    else
        log "WARN" "/dev/net/tun not found — Tailscale will use userspace mode"
        # Switch to userspace mode
        userspace_extra="      - TS_USERSPACE=true"
    fi
    
    compose_append << EOF

  tailscale:
    image: tailscale/tailscale:latest
    container_name: ${COMPOSE_PROJECT_NAME}-tailscale
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - NET_RAW
    ports:
      - "8443:443"  # Alternative HTTPS port for OpenClaw integration
    volumes:
      - ${DATA_ROOT}/tailscale:/var/lib/tailscale
${tun_device}
    environment:
      - TS_AUTHKEY=\${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_HOSTNAME=${TAILSCALE_HOSTNAME}
      - TS_USERSPACE=false
      - TS_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS}
${userspace_extra}
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# SIGNAL
# ─────────────────────────────────────────────────────────────
append_signal() {
    compose_append << EOF

  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: ${COMPOSE_PROJECT_NAME}-signal-api
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${SIGNAL_PORT}:8080"   # ALWAYS 8080 internal - never ${SIGNAL_PORT}:${SIGNAL_PORT}
    environment:
      - MODE=native
      - AUTO_RECEIVE_SCHEDULE=0 * * * *
    volumes:
      - ${DATA_ROOT}/signal-api:/home/.local/share/signal-cli
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/about"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
}

# ─────────────────────────────────────────────────────────────
# RCLONE
# ─────────────────────────────────────────────────────────────
append_rclone() {
    compose_append << EOF

  rclone:
    image: rclone/rclone:latest
    container_name: ${COMPOSE_PROJECT_NAME}-rclone
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - RCLONE_CONFIG=/config/rclone.conf
    volumes:
      - ${DATA_ROOT}/rclone/config:/config
      - ${DATA_ROOT}/gdrive:/mnt/gdrive
    command: >
      sync
      gdrive:/
      /mnt/gdrive
      --transfers=4
      --checkers=8
      --contimeout=60s
      --timeout=300s
      --retries=3
      --low-level-retries=10
      --log-level=INFO
      --log-file=/config/rclone.log
    networks:
      - ${DOCKER_NETWORK}
EOF
}

# ─────────────────────────────────────────────────────────────
# VOLUMES + NETWORKS FOOTER
# ─────────────────────────────────────────────────────────────
append_footer() {
    # Build volume list dynamically based on enabled services
    compose_append << EOF

volumes:
  ${COMPOSE_PROJECT_NAME}_postgres_data:
    name: ${COMPOSE_PROJECT_NAME}_postgres_data
  ${COMPOSE_PROJECT_NAME}_redis_data:
    name: ${COMPOSE_PROJECT_NAME}_redis_data
  ${COMPOSE_PROJECT_NAME}_caddy_data:
    name: ${COMPOSE_PROJECT_NAME}_caddy_data
  ${COMPOSE_PROJECT_NAME}_minio_data:
    name: ${COMPOSE_PROJECT_NAME}_minio_data
  ${COMPOSE_PROJECT_NAME}_litellm_data:
    name: ${COMPOSE_PROJECT_NAME}_litellm_data
EOF

    [ "${VECTOR_DB}" = "qdrant" ] && compose_append << EOF
  ${COMPOSE_PROJECT_NAME}_qdrant_data:
    name: ${COMPOSE_PROJECT_NAME}_qdrant_data
EOF

    compose_append << EOF

networks:
  ${DOCKER_NETWORK}:
    name: ${DOCKER_NETWORK}
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF
}

# ─────────────────────────────────────────────────────────────
# CADDYFILE GENERATOR
# Generates AFTER compose so it knows which services are active
# ─────────────────────────────────────────────────────────────
generate_caddyfile() {
    local caddy_dir="${DATA_ROOT}/caddy/config"
    mkdir -p "${caddy_dir}"
    local cf="${caddy_dir}/Caddyfile"

    # Global options
    cat > "${cf}" << EOF
{
    email ${SSL_EMAIL}
    admin 0.0.0.0:2019
    log {
        level INFO
    }
}

EOF

    # Helper — write one reverse proxy block
    # Usage: caddy_proxy <subdomain> <upstream_host> <upstream_port>
    caddy_proxy() {
        local subdomain=$1
        local upstream=$2
        local port=$3
        cat >> "${cf}" << EOF
${subdomain}.${DOMAIN} {
    reverse_proxy ${upstream}:${port} {
        flush_interval -1
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-${subdomain}.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    }

    # Core services always present
    # Caddy admin UI accessible at caddy.DOMAIN (optional)
    # caddy_proxy "caddy" "localhost" "2019"

    # Services — only add if enabled
    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        caddy_proxy "openwebui" "openwebui" "8080"

    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        caddy_proxy "anythingllm" "anythingllm" "3001"

    [ "${ENABLE_LITELLM}" = "true" ] && \
        caddy_proxy "litellm" "litellm" "4000"

    [ "${ENABLE_N8N}" = "true" ] && {
        # n8n needs websocket support
        cat >> "${cf}" << EOF
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
    }

    [ "${ENABLE_FLOWISE}" = "true" ] && \
        caddy_proxy "flowise" "flowise" "3000"

    [ "${ENABLE_DIFY}" = "true" ] && {
        # Dify needs specific routing for api vs web
        cat >> "${cf}" << EOF
dify.${DOMAIN} {
    # API routes
    handle /console/api/* {
        reverse_proxy dify-api:5001
    }
    handle /api/* {
        reverse_proxy dify-api:5001
    }
    handle /v1/* {
        reverse_proxy dify-api:5001
    }
    handle /files/* {
        reverse_proxy dify-api:5001
    }
    # Web UI (catch-all)
    handle {
        reverse_proxy dify-web:3000
    }
    log {
        output file ${DATA_ROOT}/logs/caddy-dify.log {
            roll_size 10mb
            roll_keep 5
        }
    }
    encode gzip
}

EOF
    }

    [ "${ENABLE_OPENCLAW}" = "true" ] && \
        caddy_proxy "openclaw" "openclaw" "8082"

    [ "${ENABLE_GRAFANA}" = "true" ] && \
        caddy_proxy "grafana" "grafana" "3000"

    # Minio console always useful
    caddy_proxy "minio" "minio" "9001"
    caddy_proxy "s3" "minio" "9000"

    [ "${ENABLE_OLLAMA}" = "true" ] && \
        caddy_proxy "ollama" "ollama" "11434"

    [ "${ENABLE_SIGNAL}" = "true" ] && \
        caddy_proxy "signal" "signal-api" "8080"

    chown "${TENANT_UID}:${TENANT_GID}" "${cf}"
    log "Caddyfile generated at ${cf}"

    # Validate
    docker run --rm -v "${cf}:/etc/caddy/Caddyfile:ro" caddy:2-alpine \
        caddy validate --config /etc/caddy/Caddyfile 2>&1 && \
        log "Caddyfile validation passed" || \
        log "WARN: Caddyfile validation had warnings — check manually"
}

# ─────────────────────────────────────────────────────────────
# DEPLOY
# ─────────────────────────────────────────────────────────────
deploy_stack() {
    local compose_file="${DATA_ROOT}/docker-compose.yml"

    log "Starting deployment from ${compose_file}"

    # Pull images first (fail fast before any containers start)
    log "Pulling images..."
    docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        -f "${compose_file}" \
        --env-file "${ENV_FILE}" \
        pull --ignore-pull-failures --quiet 2>&1 | tee -a "${LOG_FILE}" || {
        log "WARN: Some images failed to pull — attempting deploy anyway"
    }

    # Deploy
    docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        -f "${compose_file}" \
        --env-file "${ENV_FILE}" \
        up -d \
        --remove-orphans \
        --timeout 120 \
        2>&1 | tee -a "${LOG_FILE}"

    log "Stack deployed"
}

# ─────────────────────────────────────────────────────────────
# ── Tailscale IP Output ───────────────────────────────────────────────
output_tailscale_info() {
    [ "${ENABLE_TAILSCALE}" = "true" ] || return 0

    log "INFO" "Waiting for Tailscale to authenticate..."
    local max_wait=60
    local elapsed=0

    while [ ${elapsed} -lt ${max_wait} ]; do
        local ts_ip
        ts_ip=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
            tailscale ip -4 2>/dev/null || echo "")

        if [ -n "${ts_ip}" ] && [ "${ts_ip}" != "127.0.0.1" ]; then
            log "SUCCESS" "Tailscale IP: ${ts_ip}"

            # Write to .env for script 3 and 4 to use
            if grep -q "^TAILSCALE_IP=" "${ENV_FILE}"; then
                sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${ts_ip}|" "${ENV_FILE}"
            else
                echo "TAILSCALE_IP=${ts_ip}" >> "${ENV_FILE}"
            fi

            # Print access URLs
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo " TAILSCALE ACCESS URLS"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            [ "${ENABLE_OPENCLAW}" = "true" ] && \
                echo " OpenClaw  : http://${ts_ip}:${OPENCLAW_PORT}"
            [ "${ENABLE_OPENWEBUI}" = "true" ] && \
                echo " OpenWebUI : http://${ts_ip}:${OPENWEBUI_PORT}"
            [ "${ENABLE_N8N}" = "true" ] && \
                echo " n8n       : http://${ts_ip}:${N8N_PORT}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            
            # Export for subsequent functions
            export TAILSCALE_IP="${ts_ip}"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        log "INFO" "Waiting for Tailscale IP... (${elapsed}s/${max_wait}s)"
    done

    log "WARN" "Tailscale did not authenticate within ${max_wait}s"
    log "WARN" "Check auth key: docker logs ${COMPOSE_PROJECT_NAME}-tailscale"
    log "WARN" "Manual check: docker exec ${COMPOSE_PROJECT_NAME}-tailscale tailscale ip -4"
}

# ─────────────────────────────────────────────────────────────
# DEPLOYMENT VERIFICATION
# ─────────────────────────────────────────────────────────────
verify_deployment() {
    log "INFO" "Verifying deployment health..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-12s %-12s %s\n" "SERVICE" "DOCKER" "HTTP" "URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for services to stabilise
    log "INFO" "Waiting 30s for services to stabilise..."
    sleep 30

    check_service() {
        local name=$1        # display name
        local container=$2   # docker container name
        local url=$3         # http url to check (empty = skip)
        local internal_url=$4 # internal docker network url (empty = skip)

        # Docker health status
        local docker_status
        docker_status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "${container}" 2>/dev/null || echo "missing")

        # If no healthcheck defined, use running state
        if [ "${docker_status}" = "" ] || [ "${docker_status}" = "<nil>" ]; then
            docker_status=$(docker inspect \
                --format='{{.State.Status}}' \
                "${container}" 2>/dev/null || echo "missing")
        fi

        # HTTP check (external via Caddy)
        local http_status="skip"
        if [ -n "${url}" ]; then
            http_status=$(curl -so /dev/null \
                -w "%{http_code}" \
                --max-time 10 \
                --retry 2 \
                "${url}" 2>/dev/null || echo "fail")
        fi

        # Colour coding
        local docker_display http_display
        case "${docker_status}" in
            healthy|running) docker_display="✅ ${docker_status}" ;;
            starting)        docker_display="⏳ starting" ;;
            *)               docker_display="❌ ${docker_status}" ;;
        esac

        case "${http_status}" in
            200|301|302|303) http_display="✅ ${http_status}" ;;
            skip)            http_display="➖ skip" ;;
            *)               http_display="❌ ${http_status}" ;;
        esac

        printf "%-30s %-20s %-20s %s\n" \
            "${name}" "${docker_display}" "${http_display}" "${url:-internal}"
    }

    local p="${COMPOSE_PROJECT_NAME}"

    # Infrastructure always present
    check_service "PostgreSQL"   "${p}-postgres"  "" ""
    check_service "Redis"        "${p}-redis"     "" ""
    check_service "MinIO"        "${p}-minio"     "" ""
    check_service "Caddy"        "${p}-caddy"     "https://${DOMAIN}" ""

    # Optional services
    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        check_service "OpenWebUI" "${p}-open-webui" \
            "https://chat.${DOMAIN}" ""
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        check_service "AnythingLLM" "${p}-anythingllm" \
            "https://anythingllm.${DOMAIN}" ""
    [ "${ENABLE_N8N}" = "true" ] && \
        check_service "n8n" "${p}-n8n" \
            "https://n8n.${DOMAIN}" ""
    [ "${ENABLE_DIFY}" = "true" ] && \
        check_service "Dify API" "${p}-dify-api" \
            "https://dify.${DOMAIN}" ""
    [ "${ENABLE_FLOWISE}" = "true" ] && \
        check_service "Flowise" "${p}-flowise" \
            "https://flowise.${DOMAIN}" ""
    [ "${ENABLE_LITELLM}" = "true" ] && \
        check_service "LiteLLM" "${p}-litellm" \
            "https://litellm.${DOMAIN}" ""
    [ "${ENABLE_OLLAMA}" = "true" ] && \
        check_service "Ollama" "${p}-ollama" "" ""
    [ "${ENABLE_QDRANT}" = "true" ] && \
        check_service "Qdrant" "${p}-qdrant" "" ""
    [ "${ENABLE_GRAFANA}" = "true" ] && \
        check_service "Grafana" "${p}-grafana" \
            "https://grafana.${DOMAIN}" ""
    [ "${ENABLE_SIGNAL}" = "true" ] && \
        check_service "Signal API" "${p}-signal-api" "" ""
    [ "${ENABLE_TAILSCALE}" = "true" ] && \
        check_service "Tailscale" "${p}-tailscale" "" ""
    [ "${ENABLE_OPENCLAW}" = "true" ] && \
        check_service "OpenClaw" "${p}-openclaw" "" ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Print any containers in unhealthy/exited state
    local unhealthy
    unhealthy=$(docker ps -a \
        --filter "name=${p}" \
        --filter "status=exited" \
        --format "{{.Names}}" 2>/dev/null)

    if [ -n "${unhealthy}" ]; then
        log "WARN" "The following containers have exited:"
        echo "${unhealthy}" | while read -r c; do
            echo "  → ${c}"
            echo "    Last 10 log lines:"
            docker logs --tail 10 "${c}" 2>&1 | sed 's/^/    | /'
        done
    fi
}

# ─────────────────────────────────────────────────────────────
# CAPTURE TAILSCALE IP POST-STARTUP
# ─────────────────────────────────────────────────────────────
capture_tailscale_ip() {
    if [ "${ENABLE_TAILSCALE}" = "true" ]; then
        log "Waiting for Tailscale to authenticate..."
        local attempts=0
        local ts_ip=""

        while [ ${attempts} -lt 30 ]; do
            ts_ip=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
                tailscale ip -4 2>/dev/null || echo "")

            if [ -n "${ts_ip}" ] && [ "${ts_ip}" != "" ]; then
                log "SUCCESS: Tailscale IP: ${ts_ip}"
                # Update .env
                sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${ts_ip}/" "${ENV_FILE}"
                break
            fi

            attempts=$(( attempts + 1 ))
            sleep 5
        done

    fi
}

# ── WAIT FOR HEALTHY
# ─────────────────────────────────────────────────────────────
wait_for_healthy() {
    log "Waiting for services to become healthy (max 5 min)..."
    local deadline=$(( $(date +%s) + 300 ))

    while [ "$(date +%s)" -lt "${deadline}" ]; do
        local unhealthy
        unhealthy=$(docker ps \
            --filter "name=${COMPOSE_PROJECT_NAME}" \
            --filter "health=unhealthy" \
            --format "{{.Names}}" | wc -l)

        local starting
        starting=$(docker ps \
            --filter "name=${COMPOSE_PROJECT_NAME}" \
            --filter "health=starting" \
            --format "{{.Names}}" | wc -l)

        [ "${unhealthy}" -eq 0 ] && [ "${starting}" -eq 0 ] && {
            log "SUCCESS: All services healthy"
            return 0
        }

        log "  Waiting... (${unhealthy} unhealthy, ${starting} starting)"
        sleep 15
    done

    log "WARN: Timeout reached — some services may still be starting"
    docker ps \
        --filter "name=${COMPOSE_PROJECT_NAME}" \
        --format "table {{.Names}}\t{{.Status}}" | tee -a "${LOG_FILE}"
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
main() {
    log "═══════════════════════════════════════════════════════"
    log "  AI Platform Deploy — Tenant: ${TENANT_ID}"
    log "  Domain: ${DOMAIN}"
    log "  Services: $(get_enabled_services)"
    log "═══════════════════════════════════════════════════════"

    # Guards
    check_tailscale_auth

    # Pre-flight checks (ports, DNS, Docker, EBS)
    preflight_checks

    # Teardown (idempotent)
    teardown_existing

    # Setup directories with proper ownership
    setup_directories

    # Generate configs
    generate_postgres_init
    generate_prometheus_config
    generate_litellm_config
    generate_compose
    generate_caddyfile

    # Deploy
    deploy_stack

    # Post-startup tasks
    output_tailscale_info   # Must be BEFORE print_access_urls
    verify_deployment       # Health table
    wait_for_healthy

    # Print summary
    print_dashboard
}

get_enabled_services() {
    local services=""
    [ "${ENABLE_OPENWEBUI}" = "true" ] && services="${services} openwebui"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && services="${services} anythingllm"
    [ "${ENABLE_DIFY}" = "true" ] && services="${services} dify"
    [ "${ENABLE_N8N}" = "true" ] && services="${services} n8n"
    [ "${ENABLE_FLOWISE}" = "true" ] && services="${services} flowise"
    [ "${ENABLE_OPENCLAW}" = "true" ] && services="${services} openclaw"
    [ "${ENABLE_LITELLM}" = "true" ] && services="${services} litellm"
    [ "${ENABLE_OLLAMA}" = "true" ] && services="${services} ollama"
    [ "${ENABLE_GRAFANA}" = "true" ] && services="${services} grafana"
    [ "${ENABLE_SIGNAL}" = "true" ] && services="${services} signal"
    [ "${ENABLE_TAILSCALE}" = "true" ] && services="${services} tailscale"

        while [ "$(date +%s)" -lt "${deadline}" ]; do
            local unhealthy
            unhealthy=$(docker ps \
                --filter "name=${COMPOSE_PROJECT_NAME}" \
                --filter "health=unhealthy" \
                --format "{{.Names}}" | wc -l)

            local starting
            starting=$(docker ps \
                --filter "name=${COMPOSE_PROJECT_NAME}" \
                --filter "health=starting" \
                --format "{{.Names}}" | wc -l)

            [ "${unhealthy}" -eq 0 ] && [ "${starting}" -eq 0 ] && {
                log "SUCCESS: All services healthy"
                return 0
            }

            log "  Waiting... (${unhealthy} unhealthy, ${starting} starting)"
            sleep 15
        done

        log "WARN: Timeout reached — some services may still be starting"
        docker ps \
            --filter "name=${COMPOSE_PROJECT_NAME}" \
            --format "table {{.Names}}\t{{.Status}}" | tee -a "${LOG_FILE}"
    }

    # ─────────────────────────────────────────────────────────────
    # MAIN
    # ─────────────────────────────────────────────────────────────
    main() {
        log "═══════════════════════════════════════════════════════"
        log "  AI Platform Deploy — Tenant: ${TENANT_ID}"
        log "  Domain: ${DOMAIN}"
        log "  Services: $(get_enabled_services)"
        log "═══════════════════════════════════════════════════════"

        # Guards
        check_tailscale_auth

        # Pre-flight checks (ports, DNS, Docker, EBS)
        preflight_checks

        # Teardown (idempotent)
        teardown_existing

        # Setup directories with proper ownership
        setup_directories

        # Generate configs
        generate_postgres_init
        generate_prometheus_config
        generate_litellm_config
        generate_compose
        generate_caddyfile

        # Deploy
        deploy_stack

        # Post-startup tasks
        output_tailscale_info   # Must be BEFORE print_access_urls
        verify_deployment       # Health table
        wait_for_healthy

        # Print summary
        print_dashboard
    }

    get_enabled_services() {
        local services=""
        [ "${ENABLE_OPENWEBUI}" = "true" ] && services="${services} openwebui"
        [ "${ENABLE_ANYTHINGLLM}" = "true" ] && services="${services} anythingllm"
        [ "${ENABLE_DIFY}" = "true" ] && services="${services} dify"
        [ "${ENABLE_N8N}" = "true" ] && services="${services} n8n"
        [ "${ENABLE_FLOWISE}" = "true" ] && services="${services} flowise"
        [ "${ENABLE_OPENCLAW}" = "true" ] && services="${services} openclaw"
        [ "${ENABLE_LITELLM}" = "true" ] && services="${services} litellm"
        [ "${ENABLE_OLLAMA}" = "true" ] && services="${services} ollama"
        [ "${ENABLE_GRAFANA}" = "true" ] && services="${services} grafana"
        [ "${ENABLE_SIGNAL}" = "true" ] && services="${services} signal"
        [ "${ENABLE_TAILSCALE}" = "true" ] && services="${services} tailscale"
        [ "${ENABLE_RCLONE}" = "true" ] && services="${services} rclone"
        echo "${services}"
    }

    print_dashboard() {
        local border="═══════════════════════════════════════════════════════"
        echo ""
        echo "${border}"
        echo "  AI Platform Ready — ${TENANT_ID}"
        echo "${border}"
        echo ""
        
        # External URLs (via Caddy + SSL)
        echo "  🌐 External URLs:"
        echo "  ───────────────────────────────────────────────────────────"
        [ "${ENABLE_OPENWEBUI}" = "true" ] && \
            echo "    Chat UI        → https://openwebui.${DOMAIN}"
        [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
            echo "    AnythingLLM    → https://anythingllm.${DOMAIN}"
        [ "${ENABLE_DIFY}" = "true" ] && \
            echo "    Dify           → https://dify.${DOMAIN}"
        [ "${ENABLE_N8N}" = "true" ] && \
            echo "    n8n            → https://n8n.${DOMAIN}"
        [ "${ENABLE_FLOWISE}" = "true" ] && \
            echo "    Flowise        → https://flowise.${DOMAIN}"
        [ "${ENABLE_OPENCLAW}" = "true" ] && \
            echo "    OpenClaw       → https://openclaw.${DOMAIN}"
        [ "${ENABLE_GRAFANA}" = "true" ] && \
            echo "    Grafana        → https://grafana.${DOMAIN}"
        echo "    MinIO          → https://minio.${DOMAIN}"
        echo ""
        
        # Tailscale URLs (if enabled)
        if [ -n "${TAILSCALE_IP:-}" ] && [ "${TAILSCALE_IP}" != "127.0.0.1" ]; then
            echo "  🔒 Tailscale URLs:"
            echo "  ───────────────────────────────────────────────────────────"
            [ "${ENABLE_OPENWEBUI}" = "true" ] && \
                printf "    %-20s http://%s:%s\n" "Chat UI (TS)" "${TAILSCALE_IP}" "${OPENWEBUI_PORT}"
            [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
                printf "    %-20s http://%s:%s\n" "AnythingLLM (TS)" "${TAILSCALE_IP}" "${ANYTHINGLLM_PORT}"
            [ "${ENABLE_N8N}" = "true" ] && \
                printf "    %-20s http://%s:%s\n" "n8n (TS)" "${TAILSCALE_IP}" "${N8N_PORT}"
            [ "${ENABLE_OPENCLAW}" = "true" ] && \
                printf "    %-20s http://%s:%s\n" "OpenClaw (TS)" "${TAILSCALE_IP}" "${OPENCLAW_PORT}"
            echo "  ───────────────────────────────────────────────────────────"
        else
            echo "  🔒 Tailscale: Not available or not authenticated"
        fi
        echo ""
        
        # Local access URLs
        echo "  🏠 Local URLs:"
        echo "  ───────────────────────────────────────────────────────────"
        [ "${ENABLE_OLLAMA}" = "true" ] && \
            echo "    Ollama API     → http://localhost:${OLLAMA_PORT:-11434}/api/tags"
        [ "${ENABLE_QDRANT}" = "true" ] && \
            echo "    Qdrant API     → http://localhost:${QDRANT_PORT:-6333}"
        echo ""
        
        # Credentials
        echo "  🔐 Credentials:"
        echo "  ───────────────────────────────────────────────────────────"
        echo "    Admin password:  ${ADMIN_PASSWORD}"
        echo "    LiteLLM key:     ${LITELLM_MASTER_KEY}"
        echo "    Config file:       ${ENV_FILE}"
        echo ""
        
        echo "  📊 Logs:"
        echo "    docker compose -f ${COMPOSE_FILE} logs -f"
        echo "${border}"
        echo ""
    }

    main "$@"
