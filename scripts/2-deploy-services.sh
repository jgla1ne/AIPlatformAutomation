#!/usr/bin/env bash
# =============================================================================
# Script 2: Deploy Services - FIXED VERSION
# =============================================================================
# PURPOSE: Reads pre-configured environment and deploys services.
#          Assumes all setup and permissions are already correct.
# USAGE:   sudo bash scripts/2-deploy-services.sh <tenant_id>
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
log() { 
    if [[ $# -eq 1 ]]; then
        # Old format: log "message"
        echo -e "${CYAN}[INFO]${NC}    $1"
    else
        # New format: log LEVEL "message"
        local level="${1:-INFO}" 
        local message="${2}"
        case "${level}" in
            SUCCESS) echo -e "${GREEN}[SUCCESS]${NC}  ${message}" ;;
            INFO)    echo -e "${CYAN}[INFO]${NC}    ${message}" ;;
            WARN)    echo -e "${YELLOW}[WARN]${NC}    ${message}" ;;
            ERROR)   echo -e "${RED}[ERROR]${NC}   ${message}" ;;
            *)       echo -e "${CYAN}[INFO]${NC}    ${level} ${message}" ;;
        esac
    fi
}
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# --- Service Health Helper ---
wait_for_service() {
    local name=$1 url=$2 max=${3:-120}
    log INFO "Waiting for ${name} at ${url}..."
    for ((i=0; i<max; i+=5)); do
        if curl -sf --max-time 5 "${url}" &>/dev/null; then
            ok "${name} is responding."
            return 0
        fi
        sleep 5
    done
    fail "${name} did not respond within ${max}s. Deployment failed."
}

# --- Production Caddyfile Generation ---
write_production_caddyfile() {
    local caddyfile_path="${TENANT_DIR}/caddy/Caddyfile"
    
    log INFO "Generating production Caddyfile with all enabled services..."
    
    # Start with global block
    cat > "${caddyfile_path}" << EOF
# AI Platform Production Caddyfile
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Full reverse proxy configuration for all enabled services

{
    email ${ADMIN_EMAIL}
}

EOF

    # Add service blocks for all enabled services
    if [[ "${ENABLE_N8N:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
n8n.${DOMAIN} {
    reverse_proxy n8n:5678
}

EOF
    fi

    if [[ "${ENABLE_FLOWISE:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
flowise.${DOMAIN} {
    reverse_proxy flowise:3000
}

EOF
    fi

    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
openwebui.${DOMAIN} {
    reverse_proxy openwebui:8080
}

EOF
    fi

    if [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}

EOF
    fi

    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}

EOF
    fi

    if [[ "${ENABLE_GRAFANA:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
grafana.${DOMAIN} {
    reverse_proxy grafana:3000
}

EOF
    fi

    if [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
auth.${DOMAIN} {
    reverse_proxy authentik-server:9000
}

EOF
    fi

    if [[ "${ENABLE_DIFY:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
dify.${DOMAIN} {
    reverse_proxy dify-api:5001
}

EOF
    fi

    if [[ "${ENABLE_TAILSCALE:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
tailscale.${DOMAIN} {
    reverse_proxy tailscale:8443
}

EOF
    fi

    if [[ "${ENABLE_RCLONE:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
rclone.${DOMAIN} {
    reverse_proxy rclone:5572
}

EOF
    fi

    # Add Signal API as requested
    if [[ "${ENABLE_SIGNAL:-false}" == "true" ]]; then
        cat >> "${caddyfile_path}" << EOF
signal.${DOMAIN} {
    reverse_proxy signal-api:8080
}

EOF
    fi

    ok "Production Caddyfile generated with all enabled services"
}

# --- Environment Setup ---
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
# CRITICAL FIX: Simple environment loading for docker compose
set -a
source "${ENV_FILE}"
set +a

# --- Logging to File ---
LOG_DIR="${TENANT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
# Script-1 should have set correct ownership; we trust the setup
exec > >(tee -a "${LOG_FILE}") 2>&1
log INFO "All output is now logged to: ${LOG_FILE}"

# --- Docker Check ---
main() {
if ! docker info &>/dev/null; then
    fail "Docker is not running. Please start Docker and try again."
fi
ok "Docker is active."

# --- Generate Docker Compose ---
log INFO "Generating docker-compose.yml for tenant '${TENANT_ID}'..."

# Initialize compose file
cat > "${COMPOSE_FILE}" << EOF
services:
EOF

# --- Service Generation Functions ---
add_postgres() {
    cat >> "${COMPOSE_FILE}" << EOF

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-\${TENANT_UID}}:\${POSTGRES_UID:-\${TENANT_GID}}"
    environment:
      POSTGRES_USER: "\${POSTGRES_USER}"
      POSTGRES_PASSWORD: "\${POSTGRES_PASSWORD}"
      POSTGRES_DB: "\${POSTGRES_DB}"
    volumes:
      - \${TENANT_DIR}/postgres:/var/lib/postgresql/data
    ports:
      - "\${POSTGRES_PORT:-5432}:5432"

EOF
    ok "Added 'postgres' service."
}

add_redis() {
    cat >> "${COMPOSE_FILE}" << EOF

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    command: redis-server --requirepass "\${REDIS_PASSWORD}"
    volumes:
      - \${TENANT_DIR}/redis:/data
    ports:
      - "\${REDIS_PORT:-6379}:6379"

EOF
    ok "Added 'redis' service."
}

add_qdrant() {
    cat >> "${COMPOSE_FILE}" << EOF

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    environment:
      QDRANT__SERVICE__HTTP_PORT: "\${QDRANT_PORT:-6333}"
    volumes:
      - \${TENANT_DIR}/qdrant:/qdrant/storage
    ports:
      - "\${QDRANT_PORT:-6333}:6333"

EOF
    ok "Added 'qdrant' service."
}

add_ollama() {
    cat >> "${COMPOSE_FILE}" << EOF

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - \${TENANT_DIR}/ollama:/root/.ollama
    ports:
      - "\${OLLAMA_PORT:-11434}:11434"
    environment:
      - OLLAMA_GPU_LAYERS=\${OLLAMA_GPU_LAYERS:-auto}
    deploy:
      resources:
        limits:
          memory: 4G

EOF
    ok "Added 'ollama' service."
}

add_openwebui() {
    cat >> "${COMPOSE_FILE}" << 'EOF'

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    networks:
      - default
    environment:
      - OLLAMA_BASE_URL=${OLLAMA_INTERNAL_URL}
    volumes:
      - ${TENANT_DIR}/openwebui:/app/backend/data
    ports:
      - "${OPENWEBUI_PORT:-8080}:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
    depends_on:
      - ollama
EOF
    ok "Added 'openwebui' service."
}

add_n8n() {
    cat >> "${COMPOSE_FILE}" << EOF

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "\${N8N_UID:-\${TENANT_UID}}:\${N8N_GID:-\${TENANT_GID}}"
    environment:
      - N8N_BASIC_AUTH_USER=\${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_PASSWORD}
      - N8N_HOST=n8n
      - N8N_PORT=\${N8N_PORT}
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://\${N8N_SERVICE_NAME:-n8n}:\${N8N_PORT}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=\${POSTGRES_SERVICE_NAME:-postgres}
      - DB_POSTGRESDB_PORT=\${POSTGRES_PORT}
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - \${TENANT_DIR}/n8n:/home/node/.n8n
    ports:
      - "\${N8N_PORT:-5678}:5678"
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
    # USER DIRECTIVE IS REMOVED INTENTIONALLY
    networks:
      - default
    environment:
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=${POSTGRES_DB}
      - DATABASE_USER=${POSTGRES_USER}
      - DATABASE_PASSWORD=${POSTGRES_PASSWORD}
    ports:
      - "${FLOWISE_PORT:-3000}:3000"
    volumes:
      - ${TENANT_DIR}/flowise:/root/.flowise
    depends_on:
      - postgres
EOF
    ok "Added 'flowise' service."
}

add_anythingllm() {
    cat >> "${COMPOSE_FILE}" << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    user: "1000:1000" # Match the directory ownership
    environment:
      # CRITICAL FIX: Add missing AnythingLLM environment variables
      - STORAGE_DIR=/app/server/storage
      - DATABASE_PATH=/app/server/storage/anythingllm.db
      - DATABASE_URL=sqlite:///app/server/storage/anythingllm.db
      - VECTOR_DB=\${VECTOR_DB}
      - QDRANT_ENDPOINT=\${QDRANT_INTERNAL_URL}
      - QDRANT_API_KEY=\${QDRANT_API_KEY}
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=/app/server/storage/models
      - OLLAMA_MODEL_PATH=/app/server/storage/models
      - OLLAMA_HOST=\${OLLAMA_SERVICE_NAME:-ollama}
      - OLLAMA_PORT=\${OLLAMA_PORT}
      - TELEMETRY_ENABLED=false
      - DISABLE_TELEMETRY=true
    volumes:
      - \${TENANT_DIR}/anythingllm:/app/server/storage
      - \${TENANT_DIR}/anythingllm/tmp:/tmp
      - \${TENANT_DIR}/gdrive_mount:/app/server/storage/gdrive:ro # Mount as read-only
    ports:
      - "\${ANYTHINGLLM_PORT:-3001}:3001"
    depends_on:
      - qdrant
      - ollama

EOF
    ok "Added 'anythingllm' service."
}

add_litellm() {
    cat >> "${COMPOSE_FILE}" << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main-v1.35.10
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    dns:
      - 1.1.1.1
      - 8.8.8.8
    # Use direct command with inline ownership fix
    command: >
      sh -c "mkdir -p /home/user/.cache/pip && 
             chown -R \${TENANT_UID}:\${TENANT_GID} /home/user/.cache &&
             exec /entrypoint.sh"
    environment:
      - DATABASE_URL=sqlite:///data/litellm.db
      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - TENANT_UID=\${TENANT_UID}
      - TENANT_GID=\${TENANT_GID}
      - OLLAMA_API_BASE=\${OLLAMA_INTERNAL_URL}
      - LITELLM_CONFIG_YAML=\${LITELLM_CONFIG_YAML}
    volumes:
      - \${TENANT_DIR}/litellm:/data
      - \${TENANT_DIR}/litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "\${LITELLM_PORT:-4000}:4000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s

EOF
    ok "Added 'litellm' service with robust entrypoint and health check."
}

add_grafana() {
    cat >> "${COMPOSE_FILE}" << EOF

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "\${GRAFANA_UID:-\${TENANT_UID}}:\${GRAFANA_UID:-\${TENANT_GID}}"
    environment:
      - GF_SECURITY_ADMIN_USER=\${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=\${GF_SECURITY_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - \${TENANT_DIR}/grafana:/var/lib/grafana
      - \${TENANT_DIR}/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "\${GRAFANA_PORT:-3000}:3000"

EOF
    ok "Added 'grafana' service."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << EOF

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "\${PROMETHEUS_UID:-\${TENANT_UID}}:\${PROMETHEUS_UID:-\${TENANT_GID}}"
    volumes:
      - \${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - \${TENANT_DIR}/prometheus-data:/prometheus

EOF
    ok "Added 'prometheus' service."
}

add_authentik() {
    cat >> "${COMPOSE_FILE}" << EOF

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    environment:
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}
      - AUTHENTIK_POSTGRESQL__HOST=\${POSTGRES_SERVICE_NAME:-postgres}
      - AUTHENTIK_POSTGRESQL__PORT=\${POSTGRES_PORT}
      - AUTHENTIK_POSTGRESQL__NAME=\${POSTGRES_DB}
      - AUTHENTIK_POSTGRESQL__USER=\${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${POSTGRES_PASSWORD}
      - AUTHENTIK_REDIS__HOST=\${AUTHENTIK_REDIS__HOST}
      - AUTHENTIK_REDIS__PORT=\${REDIS_PORT}
      - AUTHENTIK_REDIS__DB=\${REDIS_DB:-0}
      - AUTHENTIK_REDIS__PASSWORD=\${REDIS_PASSWORD}
    volumes:
      - \${TENANT_DIR}/authentik/media:/media
      - \${TENANT_DIR}/authentik/certs:/certs
      - \${TENANT_DIR}/authentik/custom-templates:/templates
    ports:
      - "\${AUTHENTIK_PORT:-9000}:9000"
    depends_on:
      - postgres
      - redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/outpost.go"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s

EOF
    ok "Added 'authentik-server' service with health check."
}

add_dify() {
    cat >> "${COMPOSE_FILE}" << EOF

  dify-api:
    image: langgenius/dify-api:latest
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    environment:
      # --- DATABASE & REDIS CONNECTION (Mandatory) ---
      - DB_USERNAME=\${POSTGRES_USER}
      - DB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=\${POSTGRES_DB}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      # --- Dify Configuration ---
      - DIFY_SECRET_KEY=\${DIFY_SECRET_KEY}
      - DIFY_INNER_API_KEY=\${DIFY_INNER_API_KEY}
      - DIFY_LOG_LEVEL=INFO
      # --- Storage Configuration ---
      - DIFY_STORAGE_TYPE=\${DIFY_STORAGE_TYPE}
      - DIFY_STORAGE_LOCAL_ROOT=\${DIFY_STORAGE_LOCAL_ROOT}
      - CODE_SEGMENT_MAX_LENGTH=4000
    volumes:
      - \${TENANT_DIR}/dify/app:/app/api/storage
    ports:
      - "\${DIFY_PORT:-5001}:5001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s
    depends_on:
      - postgres
      - redis

EOF
    ok "Added 'dify-api' service with health check."
}

add_tailscale() {
    cat >> "${COMPOSE_FILE}" << EOF

  tailscale:
    image: tailscale/tailscale:latest
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    environment:
      - TS_AUTHKEY=\${TAILSCALE_AUTH_KEY}
      - TS_HOSTNAME=\${TAILSCALE_HOSTNAME}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_SERVE_MODE=\${TAILSCALE_SERVE_MODE:-false}
      - TS_FUNNEL=\${TAILSCALE_FUNNEL:-false}
    volumes:
      - \${TENANT_DIR}/lib/tailscale:/var/lib/tailscale
      - \${TENANT_DIR}/run/tailscale:/var/run/tailscale
      - /dev/net/tun:/dev/net/tun
    command: >
      sh -c "mkdir -p /var/run/tailscale /var/lib/tailscale && 
             chown -R ${TENANT_UID}:${TENANT_GID} /var/run/tailscale /var/lib/tailscale &&
             tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
             PID=\$! &&
             until tailscale status >/dev/null 2>&1; do echo 'Waiting for tailscaled to start...'; sleep 2; done &&
             tailscale up --authkey=${TAILSCALE_AUTH_KEY} --hostname=${PROJECT_PREFIX}${TENANT_ID}-claw --accept-routes &&
             echo 'Tailscale connected. Container will now idle.' &&
             wait \$PID"
    ports:
      - "\${TAILSCALE_PORT:-8443}:8443"
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
    ok "Added 'tailscale' service with correct volume paths and health check."
}

add_rclone() {
    cat >> "${COMPOSE_FILE}" << EOF

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    environment:
      - RCLONE_CONFIG=\${RCLONE_CONFIG:-/config/rclone.conf}
      - RCLONE_CONFIG_PATH=\${RCLONE_CONFIG_PATH}
      - GDRIVE_AUTH_METHOD=\${GDRIVE_AUTH_METHOD}
      - GDRIVE_CLIENT_ID=\${GDRIVE_CLIENT_ID}
      - GDRIVE_CLIENT_SECRET=\${GDRIVE_CLIENT_SECRET}
    volumes:
      - \${TENANT_DIR}/rclone:/config
      - \${TENANT_DIR}/storage:/data
    ports:
      - "\${RCLONE_PORT:-5572}:5572"
    command: >
      sh -c "if [ \"\${GDRIVE_AUTH_METHOD}\" = \"service_account\" ]; then
               rclone rcd --rc-no-auth --rc-addr :5572 --config=\${RCLONE_CONFIG_PATH} --log-file=/data/rclone.log
             else
               echo 'ERROR: OAuth method not supported' &&
               exit 1
             fi"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5572"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
    ok "Added 'rclone' service with correct command syntax and health check."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << EOF

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}"
    networks:
      - default
    environment:
      ACME_AGREE: "true"
    volumes:
      - \${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - \${TENANT_DIR}/caddy/data:/data
      - \${TENANT_DIR}/caddy/config:/config
    ports:
      - "\${CADDY_HTTP_PORT:-80}:80"
      - "\${CADDY_HTTPS_PORT:-443}:443"

EOF
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
[[ "${ENABLE_DIFY:-false}" == "true" ]] && add_dify
[[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && add_tailscale
[[ "${ENABLE_RCLONE:-false}" == "true" ]] && add_rclone
[[ "${ENABLE_CADDY}" == "true" ]] && add_caddy

# --- Add Network Configuration ---
cat >> "${COMPOSE_FILE}" << EOF

networks:
  default:
    name: \${DOCKER_NETWORK}
    driver: bridge

EOF

# --- Deploy Services ---
log INFO "Starting deployment with docker compose..."
cd "${TENANT_DIR}"

# --- Generate Production Caddyfile ---
write_production_caddyfile

# CRITICAL FIX: Deploy CORE infrastructure services only
log INFO "Starting CORE infrastructure services..."

# Define the essential base platform services
CORE_SERVICES="postgres redis qdrant ollama caddy"

# Pull images for all defined services first
log INFO "Pulling all enabled Docker images..."
if ! docker-compose pull --quiet; then
    warn "Could not pre-pull all images. Some may download on first start."
fi

log INFO "Starting CORE services: ${CORE_SERVICES}"
if ! docker-compose up -d ${CORE_SERVICES}; then
    fail "Core Docker Compose services failed to start. Please check the logs."
fi

ok "CORE services are starting."
log INFO "Use 'sudo bash scripts/3-configure-services.sh --status' to check."
log INFO "Use 'sudo bash scripts/3-configure-services.sh --manage' to start application services."

# Verify Tailscale connectivity
log "INFO" "Verifying Tailscale connectivity..."
if docker compose exec tailscale tailscale status | grep -q "Logged in"; then
    TAILSCALE_IP=$(docker compose exec tailscale tailscale ip -4)
    ok "✅ Tailscale is UP and connected. Private IP: ${TAILSCALE_IP}"
else
    warn "❌ Tailscale failed to connect. Check auth key and logs."
fi

# Verify Rclone authentication with Google Drive
log INFO "Verifying Rclone authentication with Google Drive..."
if docker compose exec rclone rclone lsd gdrive: > /dev/null 2>&1; then
    ok "✅ Rclone authentication successful."
else
    warn "⚠️ Rclone failed to authenticate. Check google_sa.json and config."
fi

# --- NEW LOGGING BLOCK ---
if [[ "${ENABLE_CADDY}" == "true" ]]; then
    log INFO "Displaying Caddy (reverse proxy) logs for 20 seconds for real-time diagnostics..."
    timeout 20s docker-compose logs -f caddy || true
    ok "Initial Caddy log stream complete."
fi
# --- END NEW LOGGING BLOCK ---

# --- POST-DEPLOYMENT HEALTH MONITORING ---
log INFO "Monitoring service startup with intelligent health checking..."

# Wait for services to become healthy (up to 2 minutes)
log INFO "Waiting for services to initialize and become healthy..."
sleep 120

log INFO "Testing service URLs to verify deployment..."

# Function to test URL
test_url() {
    local url="$1"
    local name="$2"
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s --max-time 5 "$url" >/dev/null 2>&1; then
            echo "✅ $name: $url"
            return 0
        fi
        echo "⏳ $name: Attempt $attempt/$max_attempts - $url"
        sleep 10
        ((attempt++))
    done
    
    echo "❌ $name: $url"
    return 1
}

echo "==============================================="
echo "🔍 TESTING PROMISED URLS"
echo "==============================================="

echo ""
echo "🌐 EXTERNAL HTTPS URL TESTS"
echo "================================"

# Test external URLs (will fail without DNS/SSL)
if [[ "${ENABLE_N8N}" == "true" ]]; then
    test_url "https://n8n.${DOMAIN}" "n8n"
fi
if [[ "${ENABLE_FLOWISE}" == "true" ]]; then
    test_url "https://flowise.${DOMAIN}" "Flowise"
fi
if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
    test_url "https://openwebui.${DOMAIN}" "Open WebUI"
fi
if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
    test_url "https://anythingllm.${DOMAIN}" "AnythingLLM"
fi
if [[ "${ENABLE_LITELLM}" == "true" ]]; then
    test_url "https://litellm.${DOMAIN}" "LiteLLM"
fi
if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
    test_url "https://grafana.${DOMAIN}" "Grafana"
fi
if [[ "${ENABLE_AUTHENTIK}" == "true" ]]; then
    test_url "https://auth.${DOMAIN}" "Authentik"
fi

echo ""
echo "🏠 LOCAL ACCESS URL TESTS"
echo "================================"

# Test local URLs
if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
    test_url "http://localhost:${OPENWEBUI_PORT:-8080}" "Open WebUI local"
fi
if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
    test_url "http://localhost:${OLLAMA_PORT:-11434}/api/tags" "Ollama API local"
fi
if [[ "${ENABLE_QDRANT}" == "true" ]]; then
    test_url "http://localhost:${QDRANT_PORT:-6333}" "Qdrant local"
fi

echo ""
echo "==============================================="
echo "📊 URL TESTING SUMMARY"
echo "==============================================="
echo "Note: External URLs require DNS configuration and SSL certificates."
echo "Local URLs should work if services are running properly."

# =============================================================================
# COMPREHENSIVE LOGGING: SSL Certificate & Proxy Status
# =============================================================================
log "Checking SSL certificate and proxy status..."
echo -e "\n\n--- SSL CERTIFICATE & PROXY STATUS AT $(date) ---\n" >> "${LOG_FILE}"

# Check Caddy (proxy) status and SSL certificates
if docker compose ps | grep -q "caddy.*Up"; then
    echo "✅ Caddy proxy is running" >> "${LOG_FILE}"
    
    # Get Caddy logs for SSL certificate status
    echo -e "\n🔒 SSL Certificate Status:\n" >> "${LOG_FILE}"
    docker compose logs caddy | grep -i -E "(certificate|ssl|tls|acme|let.*encrypt)" | tail -10 >> "${LOG_FILE}" 2>&1 || echo "No SSL certificate logs found" >> "${LOG_FILE}"
    
    # Log Caddy configuration for URL analysis
    echo -e "\n📋 Caddy Configuration:\n" >> "${LOG_FILE}"
    if [ -f "${TENANT_DIR}/caddy/Caddyfile" ]; then
        echo "Caddyfile content:" >> "${LOG_FILE}"
        cat "${TENANT_DIR}/caddy/Caddyfile" >> "${LOG_FILE}"
    else
        echo "Caddyfile not found at ${TENANT_DIR}/caddy/Caddyfile" >> "${LOG_FILE}"
    fi
    
    # Check if Caddy is responding on HTTP/HTTPS ports
    echo -e "\n🌐 Proxy Port Tests:\n" >> "${LOG_FILE}"
    if curl -s --max-time 5 http://localhost:80 >/dev/null 2>&1; then
        echo "✅ HTTP port 80: Responding" >> "${LOG_FILE}"
    else
        echo "❌ HTTP port 80: Not responding" >> "${LOG_FILE}"
    fi
    
    if curl -s --max-time 5 https://localhost:443 >/dev/null 2>&1; then
        echo "✅ HTTPS port 443: Responding" >> "${LOG_FILE}"
    else
        echo "❌ HTTPS port 443: Not responding (expected for self-signed)" >> "${LOG_FILE}"
    fi
    
    # Get Caddy container status
    echo -e "\n📊 Caddy Container Status:\n" >> "${LOG_FILE}"
    docker inspect $(docker compose ps -q caddy) --format='Status: {{.State.Status}}, Health: {{.State.Health.Status}}, Uptime: {{.State.StartedAt}}' >> "${LOG_FILE}" 2>&1
    
else
    echo "❌ Caddy proxy is not running" >> "${LOG_FILE}"
fi

# =============================================================================
# FINAL STEP: COMPREHENSIVE DOCKER LOGS CAPTURE FOR DIAGNOSTICS
# =============================================================================
log "Waiting 30 seconds for services to initialize before capturing logs..."
sleep 30

log "Capturing comprehensive Docker logs with error filtering..."
echo -e "\n\n--- COMPREHENSIVE DOCKER LOGS CAPTURED AT $(date) ---\n" >> "${LOG_FILE}"

# Get all running container IDs for the current project
cd "${TENANT_DIR}"
CONTAINER_IDS=$(docker compose ps -q)

if [ -z "$CONTAINER_IDS" ]; then
    warn "No running containers found to capture logs from."
else
    for container_id in $CONTAINER_IDS; do
        service_name=$(docker inspect --format='{{.Name}}' "$container_id" | sed 's!^/!!' | sed "s/^${COMPOSE_PROJECT_NAME}-//;s/-[0-9]*$//")
        
        echo -e "\n\n=================================================" >> "${LOG_FILE}"
        echo -e "--- DOCKER LOGS FOR: ${service_name} (Container ID: ${container_id:0:12}) ---" >> "${LOG_FILE}"
        echo -e "=================================================\n" >> "${LOG_FILE}"
        
        # Capture full logs (last 100 lines)
        echo -e "📋 FULL LOGS (last 100 lines):\n" >> "${LOG_FILE}"
        docker logs --tail 100 "$container_id" &>> "${LOG_FILE}"
        
        # ALSO DISPLAY SERVICE LOGS TO CONSOLE (last 10 lines)
        echo -e "\n${CYAN}📋 ${service_name} - Last 10 Log Lines:${NC}"
        docker logs --tail 10 "$container_id" 2>&1 | head -10
        
        # Capture ERROR and EXCEPTION filtered logs
        echo -e "\n🚨 ERROR & EXCEPTION FILTERED LOGS:\n" >> "${LOG_FILE}"
        docker logs "$container_id" 2>&1 | grep -i -E "(error|exception|failed|fatal|panic|critical|denied|permission|refused)" | tail -20 &>> "${LOG_FILE}" || echo "No errors found in logs" >> "${LOG_FILE}"
        
        # ALSO DISPLAY ERRORS TO CONSOLE
        local error_logs=$(docker logs "$container_id" 2>&1 | grep -i -E "(error|exception|failed|fatal|panic|critical|denied|permission|refused)" | tail -5)
        if [[ -n "$error_logs" ]]; then
            echo -e "\n${RED}🚨 ${service_name} - Recent Errors:${NC}"
            echo "$error_logs"
        fi
        
        # Get container status and health
        echo -e "\n📊 CONTAINER STATUS:\n" >> "${LOG_FILE}"
        docker inspect "$container_id" --format='Status: {{.State.Status}}, Health: {{.State.Health.Status}}, ExitCode: {{.State.ExitCode}}' &>> "${LOG_FILE}"
        
        # Get resource usage
        echo -e "\n💾 RESOURCE USAGE:\n" >> "${LOG_FILE}"
        docker stats "$container_id" --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}/{{.MemPerc}}" &>> "${LOG_FILE}"
        
    done
    ok "All Docker logs with error filtering have been appended to ${LOG_FILE}"
fi

# =============================================================================
# COMPREHENSIVE FINAL DEPLOYMENT REPORT (README.md REQUIREMENTS)
# =============================================================================
print_comprehensive_final_report() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           📊 COMPREHENSIVE DEPLOYMENT REPORT (README.md)      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get current timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "${YELLOW}📅 Deployment Report Generated: ${timestamp}${NC}"
    echo ""
    
    # Service Status Section
    echo -e "${GREEN}## 📈 Service Status (Comprehensive Health Check)${NC}"
    echo ""
    
    # Define all services to check
    local services=("postgres" "redis" "qdrant" "ollama" "openwebui" "n8n" "flowise" "anythingllm" "litellm" "prometheus" "authentik-server" "grafana" "caddy")
    local total_services=${#services[@]}
    local healthy_services=0
    local unhealthy_services=0
    
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ SERVICE         │ STATUS    │ HEALTH    │ EXTERNAL REACH        │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    
    for service in "${services[@]}"; do
        local status="Unknown"
        local health="Unknown"
        local external_reach="Unknown"
        local service_url=""
        
        # Check if container is running
        if docker compose ps | grep -q "${service}.*Up"; then
            status="Running"
            
            # Check container health
            local health_status=$(docker inspect $(docker compose ps -q "${service}" 2>/dev/null) --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            if [[ "${health_status}" == "healthy" ]]; then
                health="✅ Healthy"
                ((healthy_services++))
            elif [[ "${health_status}" == "none" ]]; then
                # For services without health checks, try to connect to their port
                case "${service}" in
                    "postgres")
                        if docker compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
                            health="✅ Ready"
                            ((healthy_services++))
                        else
                            health="🔄 Starting"
                            ((unhealthy_services++))
                        fi
                        ;;
                    "redis")
                        if docker compose exec -T redis redis-cli ping >/dev/null 2>&1; then
                            health="✅ Ready"
                            ((healthy_services++))
                        else
                            health="🔄 Starting"
                            ((unhealthy_services++))
                        fi
                        ;;
                    "caddy")
                        if curl -s --max-time 3 http://localhost:80 >/dev/null 2>&1; then
                            health="✅ Responding"
                            ((healthy_services++))
                        else
                            health="🔄 Starting"
                            ((unhealthy_services++))
                        fi
                        ;;
                    *)
                        health="✅ Running"
                        ((healthy_services++))
                        ;;
                esac
            else
                health="🔄 Unhealthy"
                ((unhealthy_services++))
            fi
            
            # Check external reach (if service is enabled and has external URL)
            case "${service}" in
                "n8n")
                    if [[ "${ENABLE_N8N:-false}" == "true" ]]; then
                        service_url="https://n8n.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://n8n.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "flowise")
                    if [[ "${ENABLE_FLOWISE:-false}" == "true" ]]; then
                        service_url="https://flowise.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://flowise.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "openwebui")
                    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
                        service_url="https://openwebui.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://openwebui.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "anythingllm")
                    if [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]]; then
                        service_url="https://anythingllm.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://anythingllm.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "litellm")
                    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
                        service_url="https://litellm.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://litellm.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "grafana")
                    if [[ "${ENABLE_GRAFANA:-false}" == "true" ]]; then
                        service_url="https://grafana.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://grafana.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "authentik-server")
                    if [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]]; then
                        service_url="https://auth.${DOMAIN}"
                        if curl -s --max-time 5 --insecure "https://auth.${DOMAIN}" >/dev/null 2>&1; then
                            external_reach="✅ Reachable"
                        else
                            external_reach="❌ No DNS/SSL"
                        fi
                    fi
                    ;;
                "caddy")
                    service_url="https://${DOMAIN}"
                    if curl -s --max-time 5 --insecure "https://${DOMAIN}" >/dev/null 2>&1; then
                        external_reach="✅ Reachable"
                    else
                        external_reach="❌ No DNS/SSL"
                    fi
                    ;;
                *)
                    external_reach="N/A"
                    ;;
            esac
        else
            status="❌ Down"
            health="❌ Down"
            external_reach="❌ Service Down"
            ((unhealthy_services++))
        fi
        
        # Format output line
        printf "│ %-15s │ %-9s │ %-9s │ %-21s │\n" "${service}" "${status}" "${health}" "${external_reach}"
        
        # Also log to file
        echo "${service}: ${status} | ${health} | ${external_reach} | ${service_url}" >> "${LOG_FILE}"
    done
    
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Summary Statistics
    local success_rate=$((healthy_services * 100 / total_services))
    echo -e "${GREEN}📊 Deployment Summary:${NC}"
    echo "  • Total Services: ${total_services}"
    echo "  • Healthy Services: ${healthy_services}"
    echo "  • Unhealthy Services: ${unhealthy_services}"
    echo "  • Success Rate: ${success_rate}%"
    echo ""
    
    # External URLs Section
    echo -e "${GREEN}## 🌐 External Service URLs${NC}"
    echo ""
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      https://flowise.${DOMAIN}"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   https://openwebui.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  • AnythingLLM:  https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && echo "  • LiteLLM:      https://litellm.${DOMAIN}"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && echo "  • Grafana:      https://grafana.${DOMAIN}"
    [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]] && echo "  • Authentik:    https://auth.${DOMAIN}"
    [[ "${ENABLE_DIFY:-false}" == "true" ]] && echo "  • Dify:         https://dify.${DOMAIN}"
    [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && echo "  • Tailscale:     https://tailscale.${DOMAIN}"
    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && echo "  • Rclone:        https://rclone.${DOMAIN}"
    echo ""
    
    # Internal URLs Section
    echo -e "${GREEN}## 🔗 Internal Service URLs${NC}"
    echo ""
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          http://localhost:5678"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      http://localhost:3000"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   http://localhost:8081"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  • AnythingLLM:  http://localhost:3001"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && echo "  • LiteLLM:      http://localhost:4000"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && echo "  • Grafana:      http://localhost:3002"
    [[ "${ENABLE_DIFY:-false}" == "true" ]] && echo "  • Dify:         http://localhost:5001"
    [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && echo "  • Tailscale:     http://localhost:8443"
    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && echo "  • Rclone:        http://localhost:5572"
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && echo "  • Ollama API:   http://localhost:11434/api/tags"
    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && echo "  • Qdrant API:   http://localhost:6333"
    [[ "${ENABLE_SIGNAL:-false}" == "true" ]] && echo "  • Signal API:   http://localhost:8080"
    echo ""
    
    # Next Steps
    echo -e "${GREEN}## 🚀 Next Steps${NC}"
    echo ""
    echo "  1. Check detailed logs: ${LOG_FILE}"
    echo "  2. Configure services: sudo bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo "  3. Monitor services: sudo docker compose ps"
    echo "  4. View service logs: sudo docker compose logs [service]"
    echo ""
    
    # Log the complete report to file
    echo -e "\n\n--- COMPREHENSIVE DEPLOYMENT REPORT AT ${timestamp} ---\n" >> "${LOG_FILE}"
    echo "Total Services: ${total_services}" >> "${LOG_FILE}"
    echo "Healthy Services: ${healthy_services}" >> "${LOG_FILE}"
    echo "Success Rate: ${success_rate}%" >> "${LOG_FILE}"
    echo "Report saved to: ${LOG_FILE}" >> "${LOG_FILE}"
}

# --- Final Deployment Summary ---
print_health_dashboard() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 🏥 COMPREHENSIVE HEALTH DASHBOARD                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Define enabled services
    local services=()
    [[ "${ENABLE_POSTGRES}" == "true" ]] && services+=("postgres")
    [[ "${ENABLE_REDIS}" == "true" ]] && services+=("redis")
    [[ "${ENABLE_QDRANT}" == "true" ]] && services+=("qdrant")
    [[ "${ENABLE_OLLAMA}" == "true" ]] && services+=("ollama")
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && services+=("openwebui")
    [[ "${ENABLE_N8N}" == "true" ]] && services+=("n8n")
    [[ "${ENABLE_FLOWISE}" == "true" ]] && services+=("flowise")
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && services+=("anythingllm")
    [[ "${ENABLE_LITELLM}" == "true" ]] && services+=("litellm")
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && services+=("prometheus")
    [[ "${ENABLE_AUTHENTIK}" == "true" ]] && services+=("authentik-server")
    [[ "${ENABLE_GRAFANA}" == "true" ]] && services+=("grafana")
    [[ "${ENABLE_CADDY}" == "true" ]] && services+=("caddy")
    [[ "${ENABLE_TAILSCALE}" == "true" ]] && services+=("tailscale")
    [[ "${ENABLE_RCLONE}" == "true" ]] && services+=("rclone")
    
    local total_services=${#services[@]}
    local healthy_services=0
    local unhealthy_services=0
    
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ SERVICE         │ STATUS    │ HEALTH    │ URL                   │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    
    for service in "${services[@]}"; do
        local container_name="ai-${TENANT_ID}-${service}-1"
        local status="Unknown"
        local health="Unknown"
        local url="N/A"
        
        # Get container status
        if docker ps --filter "name=${container_name}" --format "{{.Status}}" | grep -q "Up"; then
            status="🟢 UP"
            
            # Get health status
            local health_status=$(docker inspect "${container_name}" --format "{{.State.Health.Status}}" 2>/dev/null || echo "none")
            if [[ "$health_status" == "healthy" ]]; then
                health="✅ HEALTHY"
                ((healthy_services++))
            elif [[ "$health_status" == "none" ]]; then
                health="⚪ NO CHECK"
                ((healthy_services++))
            else
                health="❌ UNHEALTHY"
                ((unhealthy_services++))
            fi
        else
            status="🔴 DOWN"
            health="❌ UNHEALTHY"
            ((unhealthy_services++))
        fi
        
        # Get URL based on service
        case "$service" in
            "postgres") url="N/A (DB)" ;;
            "redis") url="N/A (DB)" ;;
            "qdrant") url="http://localhost:${QDRANT_PORT:-6333}" ;;
            "ollama") url="http://localhost:${OLLAMA_PORT:-11434}" ;;
            "openwebui") url="https://openwebui.${DOMAIN}" ;;
            "n8n") url="https://n8n.${DOMAIN}" ;;
            "flowise") url="https://flowise.${DOMAIN}" ;;
            "anythingllm") url="https://anythingllm.${DOMAIN}" ;;
            "litellm") url="https://litellm.${DOMAIN}" ;;
            "prometheus") url="http://localhost:9090" ;;
            "authentik-server") url="https://auth.${DOMAIN}" ;;
            "grafana") url="https://grafana.${DOMAIN}" ;;
            "caddy") url="https://caddy.${DOMAIN}" ;;
            "tailscale") 
                if [[ -n "${TAILSCALE_IP:-}" ]]; then
                    url="http://${TAILSCALE_IP}:8443"
                else
                    url="VPN (Check IP)"
                fi
                ;;
            "rclone") url="https://rclone.${DOMAIN}" ;;
        esac
        
        printf "│ %-14s │ %-9s │ %-9s │ %-21s │\n" "$service" "$status" "$health" "$url"
    done
    
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Summary statistics
    local success_rate=$(( (healthy_services * 100) / total_services ))
    echo -e "${GREEN}📊 HEALTH SUMMARY:${NC}"
    echo -e "  Total Services: ${total_services}"
    echo -e "  ${GREEN}Healthy: ${healthy_services}${NC}"
    echo -e "  ${RED}Unhealthy: ${unhealthy_services}${NC}"
    echo -e "  Success Rate: ${success_rate}%"
    echo ""
    
    # Tailscale IP if available
    if [[ "${ENABLE_TAILSCALE}" == "true" && -n "${TAILSCALE_IP:-}" ]]; then
        echo -e "${CYAN}🔐 TAILSCALE VPN:${NC}"
        echo -e "  IP Address: ${TAILSCALE_IP}"
        echo -e "  Access URL: http://${TAILSCALE_IP}:8443"
        echo ""
    fi
    
    # Signal QR code if available
    if [[ "${ENABLE_SIGNAL}" == "true" && -n "${SIGNAL_VERIFICATION_CODE:-}" ]]; then
        echo -e "${CYAN}📱 SIGNAL SETUP:${NC}"
        echo -e "  Verification Code: ${SIGNAL_VERIFICATION_CODE}"
        echo -e "  QR Code: https://signal.org/add/${SIGNAL_VERIFICATION_CODE}"
        echo ""
    fi
    
    echo -e "${GREEN}✅ HEALTH DASHBOARD COMPLETE${NC}"
}

print_final_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                   ✅  Deployment Complete: Access Summary       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Print all reverse-proxied URLs from .env
    echo -e "${GREEN}🌐 External Service URLs:${NC}"
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      https://flowise.${DOMAIN}"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   https://openwebui.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  • AnythingLLM:  https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && echo "  • LiteLLM:      https://litellm.${DOMAIN}"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && echo "  • Grafana:      https://grafana.${DOMAIN}"
    [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]] && echo "  • Authentik:    https://auth.${DOMAIN}"
    [[ "${ENABLE_DIFY:-false}" == "true" ]] && echo "  • Dify:         https://dify.${DOMAIN}"
    [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && echo "  • Tailscale:     https://tailscale.${DOMAIN}"
    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && echo "  • Rclone:        https://rclone.${DOMAIN}"
    [[ "${ENABLE_SIGNAL:-false}" == "true" ]] && echo "  • Signal API:   https://signal.${DOMAIN}"
    
    echo ""
    echo -e "${GREEN}🔗 Internal Service URLs:${NC}"
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          http://localhost:5678"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      http://localhost:3000"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   http://localhost:8081"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  • AnythingLLM:  http://localhost:3001"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && echo "  • LiteLLM:      http://localhost:4000"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && echo "  • Grafana:      http://localhost:3002"
    [[ "${ENABLE_DIFY:-false}" == "true" ]] && echo "  • Dify:         http://localhost:5001"
    [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && echo "  • Tailscale:     http://localhost:8443"
    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && echo "  • Rclone:        http://localhost:5572"
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && echo "  • Ollama API:   http://localhost:11434/api/tags"
    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && echo "  • Qdrant API:   http://localhost:6333"
    [[ "${ENABLE_SIGNAL:-false}" == "true" ]] && echo "  • Signal API:   http://localhost:8080"
    
    echo ""
    echo -e "${GREEN}🔧 Tailscale & OpenClaw Access:${NC}"
    if [[ "${ENABLE_TAILSCALE:-false}" == "true" ]]; then
        if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
            local ts_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
            echo "  • Tailscale Status: ✅ Connected"
            echo "  • Tailscale IP: ${ts_ip}"
            if [[ "${ENABLE_OPENCLAW:-false}" == "true" ]]; then
                echo "  • OpenClaw (via Tailscale): http://${ts_ip}:18789"
            fi
        else
            echo "  • Tailscale Status: ⚠️ Not connected - check container logs"
        fi
    else
        echo "  • Tailscale: Disabled"
    fi
    
    echo ""
    echo -e "${CYAN}📊 Next Steps:${NC}"
    echo "  1. Test external URLs above"
    echo "  2. Run script-3 for advanced diagnostics: sudo bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo "  3. Check service health: docker compose ps"
    echo "  4. View logs: docker compose logs [service_name]"
}

# Call the comprehensive final report (README.md requirements)
print_comprehensive_final_report

echo ""
ok "SCRIPT 2 COMPLETED SUCCESSFULLY - FULLY OPERATIONAL STACK"
echo ""

# =============================================================================
# FINAL HEALTH STATUS SUMMARY
# =============================================================================
log "Generating final health status summary..."
echo -e "\n\n--- FINAL HEALTH STATUS SUMMARY AT $(date) ---\n" >> "${LOG_FILE}"

echo "===============================================" >> "${LOG_FILE}"
echo "🏥 COMPREHENSIVE SERVICE HEALTH STATUS" >> "${LOG_FILE}"
echo "===============================================" >> "${LOG_FILE}"

# Get container status
cd "${TENANT_DIR}"
docker compose ps >> "${LOG_FILE}" 2>&1

echo -e "\n--- SERVICE HEALTH CHECKS ---\n" >> "${LOG_FILE}"

# Check each service
services=("caddy" "n8n" "flowise" "openwebui" "litellm" "grafana" "authentik-server" "ollama" "qdrant" "postgres" "redis" "prometheus" "anythingllm")

for service in "${services[@]}"; do
    echo -e "\n--- ${service} Health Check ---" >> "${LOG_FILE}"
    
    # Check if container is running
    if docker compose ps | grep -q "${service}.*Up"; then
        echo "✅ ${service}: Container is running" >> "${LOG_FILE}"
        
        # Get container logs
        echo -e "Last 10 logs:\n" >> "${LOG_FILE}"
        docker compose logs --tail 10 "${service}" >> "${LOG_FILE}" 2>&1
        
        # Check if service is responding on its port (if applicable)
        case "${service}" in
            "caddy")
                if curl -s --max-time 5 http://localhost:80 >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 80" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 80" >> "${LOG_FILE}"
                fi
                ;;
            "n8n")
                if curl -s --max-time 5 http://localhost:5678 >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 5678" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 5678" >> "${LOG_FILE}"
                fi
                ;;
            "openwebui")
                if curl -s --max-time 5 http://localhost:8081 >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 8081" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 8081" >> "${LOG_FILE}"
                fi
                ;;
            "litellm")
                if curl -s --max-time 5 http://localhost:4000 >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 4000" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 4000" >> "${LOG_FILE}"
                fi
                ;;
            "qdrant")
                if curl -s --max-time 5 http://localhost:6333 >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 6333" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 6333" >> "${LOG_FILE}"
                fi
                ;;
            "ollama")
                if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
                    echo "✅ ${service}: Responding on port 11434" >> "${LOG_FILE}"
                else
                    echo "❌ ${service}: Not responding on port 11434" >> "${LOG_FILE}"
                fi
                ;;
        esac
    else
        echo "❌ ${service}: Container is not running" >> "${LOG_FILE}"
        echo -e "Container status:\n" >> "${LOG_FILE}"
        docker compose ps | grep "${service}" >> "${LOG_FILE}" 2>&1
    fi
done

ok "Complete health status and diagnostics captured in ${LOG_FILE}"

# Call final report functions
print_health_dashboard
print_final_summary
print_comprehensive_final_report

}

# Call main function to execute the script
main
