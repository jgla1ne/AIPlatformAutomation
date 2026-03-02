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

volumes:
COMPOSE_HEADER

    # ── Named Volumes (only for enabled services) ────────────
    echo "  ${COMPOSE_PROJECT_NAME}_postgres_data:" >> "${compose_file}"
    echo "  ${COMPOSE_PROJECT_NAME}_redis_data:" >> "${compose_file}"
    echo "  ${COMPOSE_PROJECT_NAME}_caddy_data:" >> "${compose_file}"
    [ "${ENABLE_MINIO}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_minio_data:" >> "${compose_file}"
    [ "${VECTOR_DB}" = "qdrant" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_qdrant_data:" >> "${compose_file}"
    [ "${ENABLE_LITELLM}" = "true" ] && \
        echo "  ${COMPOSE_PROJECT_NAME}_litellm_data:" >> "${compose_file}"

    echo "" >> "${compose_file}"
    echo "services:" >> "${compose_file}"

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

