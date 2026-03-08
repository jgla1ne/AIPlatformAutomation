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
log() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

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
# CRITICAL FIX: Ensure log file is owned by tenant, not root
touch "${LOG_FILE}"
chown "${TENANT_UID}:${TENANT_GID}" "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1
log "All output is now logged to: ${LOG_FILE}"

# --- Docker Check ---
if ! docker info &>/dev/null; then
    fail "Docker is not running. Please start Docker and try again."
fi
ok "Docker is active."

# --- Generate Docker Compose ---
log "Generating docker-compose.yml for tenant '${TENANT_ID}'..."

# Initialize compose file
cat > "${COMPOSE_FILE}" << EOF
version: '3.8'

services:
EOF

# --- Service Generation Functions ---
add_postgres() {
    cat >> "${COMPOSE_FILE}" << EOF

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-\${TENANT_UID}}:\${POSTGRES_UID:-\${TENANT_GID}}"
    networks:
      - default
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
    networks:
      - default
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
    networks:
      - default
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
    networks:
      - default
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
    cat >> "${COMPOSE_FILE}" << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    user: "1000:1000" # Match the directory ownership
    networks:
      - default
    environment:
      - OLLAMA_BASE_URL=\${OLLAMA_BASE_URL}
      - WEBUI_NAME=\${TENANT_ID}
    volumes:
      - \${TENANT_DIR}/openwebui:/app/backend/data
    ports:
      - "\${OPENWEBUI_PORT:-8080}:8080"
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
    user: "\${N8N_UID:-\${TENANT_UID}}:\${N8N_UID:-\${TENANT_GID}}"
    networks:
      - default
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
    cat >> "${COMPOSE_FILE}" << EOF

  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    user: "1000:1000" # Match the directory ownership
    networks:
      - default
    environment:
      - HOME=/home/node # Keep this variable
      - PORT=\${FLOWISE_PORT}
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=\${POSTGRES_SERVICE_NAME:-postgres}
      - DATABASE_PORT=\${POSTGRES_PORT}
      - DATABASE_NAME=\${POSTGRES_DB}
      - DATABASE_USER=\${POSTGRES_USER}
      - DATABASE_PASSWORD=\${POSTGRES_PASSWORD}
      - APIKEY_PATH=/app/flowise-apikeys
    volumes:
      - \${TENANT_DIR}/flowise:/app/storage
    ports:
      - "\${FLOWISE_PORT:-3000}:3000"
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
    networks:
      - default
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
    image: ghcr.io/berriai/litellm:main
    restart: unless-stopped
    user: "\${TENANT_UID}:\${TENANT_GID}" # Ensure this is present
    networks:
      - default
    dns: # Keep the DNS fix
      - 8.8.8.8
      - 1.1.1.1
    # Add a command to fix cache permissions before starting
    command: >
      bash -c "mkdir -p /home/user/.cache/pip &&
               chown -R \${TENANT_UID}:\${TENANT_GID} /home/user/.cache &&
               /entrypoint.sh"
    environment:
      - DATABASE_URL=sqlite:///app/litellm.db
      - LITELM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - OPENAI_API_KEY=\${OPENAI_API_KEY}
      - GOOGLE_API_KEY=\${GOOGLE_API_KEY}
      - ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY}
      - OLLAMA_API_BASE=\${OLLAMA_INTERNAL_URL}
    volumes:
      - \${TENANT_DIR}/litellm:/app
    ports:
      - "\${LITELLM_PORT:-4000}:4000"

EOF
    ok "Added 'litellm' service."
}

add_grafana() {
    cat >> "${COMPOSE_FILE}" << EOF

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "\${GRAFANA_UID:-\${TENANT_UID}}:\${GRAFANA_UID:-\${TENANT_GID}}"
    networks:
      - default
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
    networks:
      - default
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
    networks:
      - default
    environment:
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}
      - AUTHENTIK_POSTGRESQL__HOST=\${POSTGRES_SERVICE_NAME:-postgres}
      - AUTHENTIK_POSTGRESQL__PORT=\${POSTGRES_PORT}
      - AUTHENTIK_POSTGRESQL__NAME=\${POSTGRES_DB}
      - AUTHENTIK_POSTGRESQL__USER=\${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - \${TENANT_DIR}/authentik/media:/media
      - \${TENANT_DIR}/authentik/custom-templates:/templates
    ports:
      - "\${AUTHENTIK_PORT:-9000}:9000"
    depends_on:
      - postgres

EOF
    ok "Added 'authentik-server' service."
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
[[ "${ENABLE_CADDY}" == "true" ]] && add_caddy

# --- Add Network Configuration ---
cat >> "${COMPOSE_FILE}" << EOF

networks:
  default:
    name: \${DOCKER_NETWORK}
    driver: bridge

EOF

# --- Deploy Services ---
log "Starting deployment with docker compose..."
cd "${TENANT_DIR}"

# CRITICAL FIX: Use docker compose with proper environment export
docker compose up -d

ok "Deployment initiated successfully. Please allow a few minutes for all services to start."
log "Run 'docker compose ps' in '${TENANT_DIR}' to check status."

# --- Wait and Test Services ---
log "Waiting 30 seconds for services to initialize..."
sleep 30

log "Testing service URLs to verify deployment..."

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
        
        # Capture ERROR and EXCEPTION filtered logs
        echo -e "\n🚨 ERROR & EXCEPTION FILTERED LOGS:\n" >> "${LOG_FILE}"
        docker logs "$container_id" 2>&1 | grep -i -E "(error|exception|failed|fatal|panic|critical|denied|permission|refused)" | tail -20 &>> "${LOG_FILE}" || echo "No errors found in logs" >> "${LOG_FILE}"
        
        # Get container status and health
        echo -e "\n📊 CONTAINER STATUS:\n" >> "${LOG_FILE}"
        docker inspect "$container_id" --format='Status: {{.State.Status}}, Health: {{.State.Health.Status}}, ExitCode: {{.State.ExitCode}}' &>> "${LOG_FILE}"
        
        # Get resource usage
        echo -e "\n💾 RESOURCE USAGE:\n" >> "${LOG_FILE}"
        docker stats "$container_id" --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}/{{.MemPerc}}" &>> "${LOG_FILE}"
        
    done
    ok "All Docker logs with error filtering have been appended to ${LOG_FILE}"
fi

echo ""
ok "SCRIPT 2 COMPLETED. FULL DIAGNOSTICS ARE AVAILABLE IN THE LOG FILE."
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
