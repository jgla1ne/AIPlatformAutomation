#!/usr/bin/env bash
# =============================================================================
# Script 2: Deploy Services - STABLE v3.1
# =============================================================================
# PURPOSE: Reads pre-configured environment and deploys services.
#          This script's ONLY job is to generate a valid docker-compose.yml
#          and run `docker compose up -d`. It does not configure or verify.
# =============================================================================

set -euo pipefail

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi
TENANT_ID="$1"

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

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
set -a
source "${ENV_FILE}"
set +a

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
fi
ok "Docker is active."

# --- Generate Docker Compose ---
log "Generating docker-compose.yml for tenant '${TENANT_ID}'..."

# Initialize compose file
cat > "${COMPOSE_FILE}" << 'EOF'
services:
EOF

# --- Service Generation Functions (Simplified & Hardened) ---
add_postgres() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "${POSTGRES_UID:-${TENANT_UID}}:${POSTGRES_UID:-${TENANT_GID}}"
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
    user: "${REDIS_UID:-999}:${REDIS_GID:-1000}"
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
    user: "${QDRANT_UID:-1000}:${QDRANT_UID:-1000}"
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/qdrant:/qdrant/storage
EOF
    ok "Added 'qdrant' service."
}

add_ollama() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    user: "${OLLAMA_UID:-1001}:${OLLAMA_UID:-1001}"
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
    user: "${OPENWEBUI_UID:-1000}:${OPENWEBUI_UID:-1000}"
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
    user: "${N8N_UID:-1000}:${N8N_UID:-1000}"
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
    user: "${FLOWISE_UID:-1000}:${FLOWISE_UID:-1000}"
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
    user: "${ANYTHINGLLM_UID:-1000}:${ANYTHINGLLM_UID:-1000}"
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
    user: "${LITELLM_UID:-1000}:${LITELLM_UID:-1000}"
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

add_grafana() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "${GRAFANA_UID:-472}:${GRAFANA_UID:-472}"
    networks:
      - default
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
    volumes:
      - ${TENANT_DIR}/grafana:/var/lib/grafana
EOF
    ok "Added 'grafana' service."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "${PROMETHEUS_UID:-65534}:${PROMETHEUS_UID:-65534}"
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - ${TENANT_DIR}/prometheus-data:/prometheus
EOF
    ok "Added 'prometheus' service."
}

add_authentik() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "${AUTHENTIK_UID:-1000}:${AUTHENTIK_UID:-1000}"
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
    user: "${TAILSCALE_UID:-1001}:${TAILSCALE_UID:-1001}"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - ${TENANT_DIR}/run/tailscale:/var/run/tailscale
      - ${TENANT_DIR}/lib/tailscale:/var/lib/tailscale
    environment:
      # We ONLY provide the auth key. Configuration happens in script-3.
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
EOF
    ok "Added STABLE 'tailscale' service. Configuration will be applied by script-3."
}

add_rclone() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
    user: "${RCLONE_UID:-1001}:${RCLONE_UID:-1001}"
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/rclone:/config
      - ${TENANT_DIR}/storage:/data
    command: rcd --rc-no-auth --rc-addr :5572 --config=/config/rclone.conf
EOF
    ok "Added 'rclone' service."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "${CADDY_UID:-1001}:${CADDY_UID:-1001}"
    networks:
      - default
    volumes:
      - ${TENANT_DIR}/Caddyfile:/etc/caddy/Caddyfile
      - ${TENANT_DIR}/caddy_data:/data
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
EOF
    ok "Added 'caddy' service."
}
    ok "Added 'caddy' service."
}

# --- Generate All Services ---
[[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
[[ "${ENABLE_REDIS}" == "true" ]] && add_redis
[[ "${ENABLE_OLLAMA}" == "true" ]] && add_ollama
[[ "${ENABLE_OPENWEBUI}" == "true" ]] && add_openwebui
[[ "${ENABLE_N8N}" == "true" ]] && add_n8n
[[ "${ENABLE_FLOWISE}" == "true" ]] && add_flowise
[[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && add_anythingllm
[[ "${ENABLE_LITELLM}" == "true" ]] && add_litellm
[[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
[[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
[[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
[[ "${ENABLE_AUTHENTIK}" == "true" ]] && add_authentik
[[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && add_tailscale
[[ "${ENABLE_RCLONE:-false}" == "true" ]] && add_rclone
add_caddy # Caddy is always added

# --- Add Network Configuration ---
cat >> "${COMPOSE_FILE}" << 'EOF'

networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge
EOF

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
