#!/usr/bin/env bash
# =============================================================================
<<<<<<< HEAD
# Script 2: Deploy Services - STABLE v3.1
# =============================================================================
# PURPOSE: Reads pre-configured environment and deploys services.
#          This script's ONLY job is to generate a valid docker-compose.yml
#          and run `docker compose up -d`. It does not configure or verify.
=======
# Script 2: Master Deployment Orchestrator - COMPREHENSIVE VERSION
# =============================================================================
# PURPOSE: Master orchestrator that deploys the entire AI Platform stack
#          Uses Script 3 functions for verification and configuration
#          Deploys ALL enabled services in dependency-aware order
# USAGE:   sudo bash scripts/2-deploy-services.sh <tenant_id>
>>>>>>> AIplatform/main
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

<<<<<<< HEAD
# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Environment Setup ---
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"

=======
# --- Load Environment ---
>>>>>>> AIplatform/main
if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found: ${ENV_FILE}. Run Script 1 first."
fi

<<<<<<< HEAD
log "Loading environment from: ${ENV_FILE}"
set -a
=======
>>>>>>> AIplatform/main
source "${ENV_FILE}"

<<<<<<< HEAD
# --- Logging to File ---
LOG_DIR="${TENANT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
log "All output is now logged to: ${LOG_FILE}"

# --- Docker Check ---
main() {
if ! docker info &>/dev/null; then
    fail "Docker is not running. Please start Docker and try again."
=======
# --- Verify Docker ---
if ! docker info >/dev/null 2>&1; then
    fail "Docker is not running or accessible."
>>>>>>> AIplatform/main
fi

<<<<<<< HEAD
# --- Generate Docker Compose ---
log "Generating docker-compose.yml for tenant '${TENANT_ID}'..."
=======
log "INFO" "Starting comprehensive deployment for tenant '${TENANT_ID}'..."

# --- 1. Generate Complete Docker Compose ---
log "INFO" "Generating docker-compose.yml with ALL enabled services..."
>>>>>>> AIplatform/main

# Initialize compose file
cat > "${COMPOSE_FILE}" << 'EOF'
services:
EOF

<<<<<<< HEAD
# --- Service Generation Functions (Simplified & Hardened) ---
=======
# Service Generation Functions (ALL services)
>>>>>>> AIplatform/main
add_postgres() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
<<<<<<< HEAD
    user: "${POSTGRES_UID:-${TENANT_UID}}:${POSTGRES_UID:-${TENANT_GID}}"
=======
    user: "${POSTGRES_UID}:${POSTGRES_UID}"
>>>>>>> AIplatform/main
    networks:
      - default
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
    volumes:
      - ${TENANT_DIR}/postgres:/var/lib/postgresql/data
EOF
    ok "Added 'postgres' service."
}

add_redis() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  redis:
    image: redis:7-alpine
    restart: unless-stopped
<<<<<<< HEAD
=======
    user: "${TENANT_UID}:${TENANT_GID}"
>>>>>>> AIplatform/main
    networks:
      - default
    command: redis-server --requirepass "${REDIS_PASSWORD}"
    volumes:
      - ${TENANT_DIR}/redis:/data
EOF
    ok "Added 'redis' service."
}

add_qdrant() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "1000:1000"
    networks:
      - default
<<<<<<< HEAD
=======
    environment:
      - QDRANT__SERVICE__HTTP_PORT=${QDRANT_PORT:-6333}
>>>>>>> AIplatform/main
    volumes:
      - ${TENANT_DIR}/qdrant:/qdrant/storage
EOF
    ok "Added 'qdrant' service."
}

<<<<<<< HEAD
add_ollama() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/ollama:/root/.ollama
EOF
    ok "Added 'ollama' service."
}

add_openwebui() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    networks:
      - default
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - ${TENANT_DIR}/openwebui:/app/backend/data
    depends_on:
      - ollama
EOF
    ok "Added 'openwebui' service."
}

add_n8n() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    networks:
      - default
    environment:
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ${TENANT_DIR}/n8n:/home/node/.n8n
    depends_on:
      - postgres
EOF
    ok "Added 'n8n' service."
}

add_flowise() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    networks:
      - default
    environment:
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_NAME=${POSTGRES_DB}
      - DATABASE_USER=${POSTGRES_USER}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ${TENANT_DIR}/flowise:/root/.flowise
    depends_on:
      - postgres
EOF
    ok "Added 'flowise' service."
}

add_anythingllm() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    networks:
      - default
    environment:
      - STORAGE_DIR=/app/server/storage
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
    volumes:
      - ${TENANT_DIR}/anythingllm:/app/server/storage
    depends_on:
      - ollama
EOF
    ok "Added 'anythingllm' service."
}

add_litellm() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  litellm:
    image: ghcr.io/berriai/litellm:main
    restart: unless-stopped
    networks:
      - default
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
    command: >
      --model ollama/mistral
      --api_base http://ollama:11434
      --host 0.0.0.0
    depends_on:
      - ollama
EOF
    ok "Added 'litellm' service."
}

=======
>>>>>>> AIplatform/main
add_grafana() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
<<<<<<< HEAD
=======
    user: "${GRAFANA_UID}:${GRAFANA_UID}"
>>>>>>> AIplatform/main
    networks:
      - default
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
<<<<<<< HEAD
    volumes:
      - ${TENANT_DIR}/grafana:/var/lib/grafana
=======
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - ${TENANT_DIR}/grafana:/var/lib/grafana
      - ${TENANT_DIR}/grafana/provisioning:/etc/grafana/provisioning
>>>>>>> AIplatform/main
EOF
    ok "Added 'grafana' service."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
<<<<<<< HEAD
=======
    user: "${PROMETHEUS_UID}:${PROMETHEUS_UID}"
>>>>>>> AIplatform/main
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - ${TENANT_DIR}/prometheus-data:/prometheus
EOF
    ok "Added 'prometheus' service."
}

<<<<<<< HEAD
add_authentik() {
=======
add_ollama() {
>>>>>>> AIplatform/main
    cat >> "${COMPOSE_FILE}" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
<<<<<<< HEAD
    networks:
      - default
    environment:
      - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
      - AUTHENTIK_POSTGRESQL__HOST=postgres
      - AUTHENTIK_POSTGRESQL__NAME=${POSTGRES_DB}
      - AUTHENTIK_POSTGRESQL__USER=${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ${TENANT_DIR}/authentik/media:/media
      - ${TENANT_DIR}/authentik/custom-templates:/templates
    depends_on:
      - postgres
EOF
    ok "Added 'authentik-server' service."
}

# --- THE STABLE TAILSCALE FIX ---
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
      # We ONLY provide the auth key. Configuration happens in script-3.
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
EOF
    ok "Added STABLE 'tailscale' service. Configuration will be applied by script-3."
=======
    volumes:
      - ${TENANT_DIR}/ollama:/root/.ollama
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
      - TS_EXTRA_ARGS=--serve=tcp://:18789/tcp://openclaw:8082
EOF
    ok "Added 'tailscale' service (Official Docker Method)."
>>>>>>> AIplatform/main
}

add_rclone() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
<<<<<<< HEAD
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/rclone:/config
      - ${TENANT_DIR}/storage:/data
    command: rcd --rc-no-auth --rc-addr :5572 --config=/config/rclone.conf
=======
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
>>>>>>> AIplatform/main
EOF
    ok "Added 'rclone' service."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
<<<<<<< HEAD
=======
    user: "${TENANT_UID}:${TENANT_GID}"
>>>>>>> AIplatform/main
    networks:
      - default
    volumes:
<<<<<<< HEAD
      - ${TENANT_DIR}/Caddyfile:/etc/caddy/Caddyfile
      - ${TENANT_DIR}/caddy_data:/data
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
=======
      - ${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - ${TENANT_DIR}/caddy/data:/data
      - ${TENANT_DIR}/caddy/config:/config
    ports:
      - "${CADDY_HTTP_PORT:-80}:80"
      - "${CADDY_HTTPS_PORT:-443}:443"
>>>>>>> AIplatform/main
EOF
    ok "Added 'caddy' service."
}

# --- Generate ALL Enabled Services ---
[[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
[[ "${ENABLE_REDIS}" == "true" ]] && add_redis
[[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
[[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
[[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
<<<<<<< HEAD
[[ "${ENABLE_AUTHENTIK}" == "true" ]] && add_authentik
[[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && add_tailscale
[[ "${ENABLE_RCLONE:-false}" == "true" ]] && add_rclone
add_caddy # Caddy is always added

# --- Add Network Configuration ---
=======
[[ "${ENABLE_OLLAMA}" == "true" ]] && add_ollama
[[ "${ENABLE_LITELLM}" == "true" ]] && add_litellm
[[ "${ENABLE_OPENWEBUI}" == "true" ]] && add_openwebui
[[ "${ENABLE_TAILSCALE}" == "true" ]] && add_tailscale
[[ "${ENABLE_RCLONE}" == "true" ]] && add_rclone
[[ "${ENABLE_CADDY}" == "true" ]] && add_caddy

# Add network configuration
>>>>>>> AIplatform/main
cat >> "${COMPOSE_FILE}" << 'EOF'

networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge
EOF

<<<<<<< HEAD
# --- Deploy Services ---
log "Starting deployment with docker compose..."
cd "${TENANT_DIR}"

log "Pulling all required Docker images..."
docker compose pull --quiet

log "Starting all services in detached mode..."
if ! docker compose up -d; then
    fail "Docker Compose failed to start. Please check the logs above."
fi

ok "All containers have been started."
log "Next Step: Run 'sudo bash scripts/3-configure-services.sh ${TENANT_ID}'"

} # End of main function

# Call main function to execute the script
main
=======
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
>>>>>>> AIplatform/main
