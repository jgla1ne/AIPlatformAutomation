#!/usr/bin/env bash
# =============================================================================
# Script 2: Master Deployment Orchestrator - COMPREHENSIVE VERSION
# =============================================================================
# PURPOSE: Master orchestrator that deploys the entire AI Platform stack
#          Uses Script 3 functions for verification and configuration
#          Deploys ALL enabled services in dependency-aware order
# USAGE:   sudo bash scripts/2-deploy-services.sh <tenant_id>
# =============================================================================

set -euo pipefail

# --- Source the toolbox (Script 3 functions) ---
source "$(dirname "$0")/3-configure-services.sh"

# --- Color Definitions ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi

TENANT_ID="$1"
DATA_ROOT="/mnt/data/datasquiz"
ENV_FILE="${DATA_ROOT}/.env"
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"

# --- Load Environment ---
if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found: ${ENV_FILE}. Run Script 1 first."
fi

source "${ENV_FILE}"

# --- Verify Docker ---
if ! docker info >/dev/null 2>&1; then
    fail "Docker is not running or accessible."
fi

log "INFO" "Starting comprehensive deployment for tenant '${TENANT_ID}'..."

# --- 1. Generate Complete Docker Compose ---
log "INFO" "Generating docker-compose.yml with ALL enabled services..."

# Initialize compose file
cat > "${COMPOSE_FILE}" << EOF
services:
EOF

# Service Generation Functions (ALL services)
add_postgres() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "${POSTGRES_UID}:${POSTGRES_UID}"
    networks:
      - default
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
    volumes:
      - ${TENANT_DIR}/postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
EOF
    ok "Added 'postgres' service."
}

add_redis() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    networks:
      - default
    command: redis-server --requirepass "${REDIS_PASSWORD}"
    volumes:
      - ${TENANT_DIR}/redis:/data
    ports:
      - "${REDIS_PORT:-6379}:6379"
EOF
    ok "Added 'redis' service."
}

add_qdrant() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    networks:
      - default
    environment:
      - QDRANT__SERVICE__HTTP_PORT=${QDRANT_PORT:-6333}
    volumes:
      - ${TENANT_DIR}/qdrant:/qdrant/storage
    ports:
      - "${QDRANT_PORT:-6333}:6333"
EOF
    ok "Added 'qdrant' service."
}

add_grafana() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "${GRAFANA_UID}:${GRAFANA_UID}"
    networks:
      - default
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - ${TENANT_DIR}/grafana:/var/lib/grafana
      - ${TENANT_DIR}/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "${GRAFANA_PORT:-3000}:3000"
EOF
    ok "Added 'grafana' service."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "${PROMETHEUS_UID}:${PROMETHEUS_UID}"
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - ${TENANT_DIR}/prometheus-data:/prometheus
EOF
    ok "Added 'prometheus' service."
}

add_ollama() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - ${TENANT_DIR}/ollama:/root/.ollama
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
    environment:
      - OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS:-auto}
EOF
    ok "Added 'ollama' service."
}

add_litellm() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  litellm:
    image: ghcr.io/berriai/litellm:main-v1.35.10
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - DATABASE_URL=sqlite:///data/litellm.db
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - OLLAMA_API_BASE=${OLLAMA_INTERNAL_URL}
    volumes:
      - ${TENANT_DIR}/litellm:/data
      - ${TENANT_DIR}/litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF
    ok "Added 'litellm' service."
}

add_openwebui() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    environment:
      - OLLAMA_API_BASE_URL=${OLLAMA_INTERNAL_URL}
      - WEBUI_NAME=${OPENWEBUI_NAME:-Open WebUI}
    volumes:
      - ${TENANT_DIR}/openwebui:/app/backend/data
    ports:
      - "${OPENWEBUI_PORT:-3001}:8080"
EOF
    ok "Added 'openwebui' service."
}

add_tailscale() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  tailscale:
    image: tailscale/tailscale:latest
    hostname: ${TAILSCALE_HOSTNAME}
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - ${TENANT_DIR}/lib/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    environment:
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--accept-routes
EOF
    ok "Added 'tailscale' service (Official Docker Method)."
}

add_rclone() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    entrypoint: ["rclone"]
    command: ["rcd", "--rc-no-auth", "--rc-addr", ":5572", "--config=${RCLONE_CONFIG_PATH}", "--log-file=/data/rclone.log"]
    environment:
      - RCLONE_CONFIG=${RCLONE_CONFIG:-/config/rclone.conf}
      - RCLONE_CONFIG_PATH=${RCLONE_CONFIG_PATH}
      - GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD}
      - GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID}
      - GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET}
      - GDRIVE_TOKEN=${GDRIVE_TOKEN}
    volumes:
      - ${TENANT_DIR}/rclone:/config
      - ${TENANT_DIR}/storage:/data
    ports:
      - "${RCLONE_PORT:-5572}:5572"
EOF
    ok "Added 'rclone' service."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    networks:
      - default
    environment:
      ACME_AGREE: "true"
    volumes:
      - ${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - ${TENANT_DIR}/caddy/data:/data
      - ${TENANT_DIR}/caddy/config:/config
    ports:
      - "${CADDY_HTTP_PORT:-80}:80"
      - "${CADDY_HTTPS_PORT:-443}:443"
EOF
    ok "Added 'caddy' service."
}

# --- Generate ALL Enabled Services ---
[[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
[[ "${ENABLE_REDIS}" == "true" ]] && add_redis
[[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
[[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
[[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
[[ "${ENABLE_OLLAMA}" == "true" ]] && add_ollama
[[ "${ENABLE_LITELLM}" == "true" ]] && add_litellm
[[ "${ENABLE_OPENWEBUI}" == "true" ]] && add_openwebui
[[ "${ENABLE_TAILSCALE}" == "true" ]] && add_tailscale
[[ "${ENABLE_RCLONE}" == "true" ]] && add_rclone
[[ "${ENABLE_CADDY}" == "true" ]] && add_caddy

# Add network configuration
cat >> "${COMPOSE_FILE}" << 'EOF'

networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge
EOF

ok "Docker Compose generation complete with ALL enabled services."

# --- 2. Pre-pull All Images ---
log "INFO" "Pre-pulling all required Docker images..."
if ! docker compose -f "${COMPOSE_FILE}" pull --ignore-buildable --quiet; then
    warn "Could not pre-pull all images. Some may download on first start."
fi

# --- 3. Start ALL Services ---
log "INFO" "Starting the entire AI Platform stack..."
cd "${DATA_ROOT}"
if ! docker compose up -d; then
    fail "The stack failed to start. Please check 'docker compose logs'."
fi
ok "All containers have been started."

# --- 4. Perform Health Checks & Configuration in Dependency-Aware Order ---
log "INFO" "Verifying and Configuring Stack..."

# Tier 1: Core Dependencies (Databases & Proxy)
log "INFO" "Tier 1: Verifying Core Dependencies..."
if [[ "${ENABLE_POSTGRES}" == "true" ]]; then
    log "INFO" "Waiting for PostgreSQL to be ready..."
    timeout 60s bash -c "until docker compose exec -T postgres pg_isready -U ${POSTGRES_USER} >/dev/null 2>&1; do sleep 2; done" || warn "PostgreSQL not ready after 60s"
    ok "✅ PostgreSQL is ready"
fi

if [[ "${ENABLE_REDIS}" == "true" ]]; then
    log "INFO" "Waiting for Redis to be ready..."
    timeout 30s bash -c "until docker compose exec -T redis redis-cli ping >/dev/null 2>&1; do sleep 2; done" || warn "Redis not ready after 30s"
    ok "✅ Redis is ready"
fi

if [[ "${ENABLE_CADDY}" == "true" ]]; then
    healthcheck_verify_url "Caddy" "http://localhost:80"
fi

# Tier 2: Core AI Infrastructure (Must be up before apps)
log "INFO" "Tier 2: Verifying Core AI Infrastructure..."
if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
    healthcheck_verify_url "Ollama" "http://localhost:${OLLAMA_PORT:-11434}"
fi

if [[ "${ENABLE_LITELLM}" == "true" ]]; then
    healthcheck_verify_url "LiteLLM" "http://localhost:${LITELLM_PORT:-4000}"
    # Now that LiteLLM is up, configure its models
    configure_litellm_models
fi

# Tier 3: Application Services (Now they can be checked via Caddy)
log "INFO" "Tier 3: Verifying Application Services..."
if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
    healthcheck_verify_url "OpenWebUI" "https://openwebui.${DOMAIN}"
fi

if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
    healthcheck_verify_url "Grafana" "https://grafana.${DOMAIN}"
fi

# Tier 4: Final external-facing configurations
log "INFO" "Tier 4: Finalizing External Configurations..."
configure_tailscale
configure_rclone

# --- 5. Final Success Output ---
print_final_summary
ok "Deployment complete. The AI Platform is now operational."

log "INFO" "Use 'sudo bash scripts/3-configure-services.sh ${TENANT_ID} --status' for detailed health monitoring."
log "INFO" "Use 'sudo bash scripts/3-configure-services.sh ${TENANT_ID} --manage' for service management."
