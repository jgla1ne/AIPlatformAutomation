#!/bin/bash
# Script 2: Deploy Services - Final Version with Full Integration and Health Checks

set -euo pipefail

# --- Colors for Clean Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"; }
error(){ echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${CYAN}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

# --- Find and Load Environment ---
ENV_FILE=$(find /mnt/data -name ".env" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
if [[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]]; then
    error "Cannot find a .env file in /mnt/data. Run script 1 (setup) first."
    exit 1
fi
log "Using environment file: ${ENV_FILE}"
set -a
source "${ENV_FILE}"
set +a

# --- Essential Variables ---
TENANT_DIR=$(dirname "${ENV_FILE}")
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"

# --- Root and Docker Checks ---
if [[ $EUID -ne 0 ]]; then error "This script must be run as root (sudo)." && exit 1; fi
log "Ensuring Docker is running..."
if ! systemctl is-active --quiet docker; then systemctl start docker; sleep 3; fi
if ! docker info &>/dev/null; then error "Docker is not responding. Check: systemctl status docker" && exit 1; fi
log "Docker is active."

# --- Directory and Permission Setup ---
log "Creating and configuring directories..."
declare -a DIRS=(
    "${TENANT_DIR}/caddy/data" "${TENANT_DIR}/postgres" "${TENANT_DIR}/redis" "${TENANT_DIR}/ollama" 
    "${TENANT_DIR}/qdrant" "${TENANT_DIR}/prometheus/data" "${TENANT_DIR}/grafana" "${TENANT_DIR}/n8n" 
    "${TENANT_DIR}/flowise" "${TENANT_DIR}/openwebui" "${TENANT_DIR}/anythingllm" "${TENANT_DIR}/litellm" 
    "${TENANT_DIR}/authentik/media" "${TENANT_DIR}/authentik/custom-templates" "${TENANT_DIR}/dify" "${TENANT_DIR}/minio"
    "${TENANT_DIR}/tailscale" "${TENANT_DIR}/openclaw"
)
for dir in "${DIRS[@]}"; do mkdir -p "${dir}"; done

log "Setting directory ownership..."
chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}"

# Critical ownership exceptions
if [ -d "${TENANT_DIR}/postgres" ]; then chown -R 70:70 "${TENANT_DIR}/postgres"; log "Set ownership for PostgreSQL."; fi
chmod -R 755 "${TENANT_DIR}"
log "Directories are ready."

# --- Dynamic Docker Compose Generation ---
log "Generating docker-compose.yml -> ${COMPOSE_FILE}"

# Start with the network definition
cat > "${COMPOSE_FILE}" << EOF
version: '3.8'

networks:
  ${DOCKER_NETWORK}:
    driver: bridge
    name: ${DOCKER_NETWORK}

services:
EOF

# Append services conditionally
if [[ "${ENABLE_POSTGRES:-true}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  postgres:
    image: postgres:15-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - ${TENANT_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s
EOF
fi

if [[ "${ENABLE_REDIS:-true}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-redis
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${TENANT_DIR}/redis:/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "\${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
EOF
fi

if [[ "${ENABLE_CADDY:-true}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  caddy:
    image: caddy:2-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-caddy
    restart: unless-stopped
    ports:
      - "\${CADDY_HTTP_PORT:-80}:80"
      - "\${CADDY_HTTPS_PORT:-443}:443"
      - "\${CADDY_HTTPS_PORT:-443}:443/udp"
    volumes:
      - ${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${TENANT_DIR}/caddy/data:/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 60s
      timeout: 10s
      retries: 3
EOF
fi

if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}-ollama
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "\${OLLAMA_PORT}:11434"
    volumes:
      - ${TENANT_DIR}/ollama:/root/.ollama
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s
EOF
if [[ "${GPU_TYPE}" == "nvidia" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
fi
fi

if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  tailscale:
    image: tailscale/tailscale:latest
    container_name: ${COMPOSE_PROJECT_NAME}-tailscale
    hostname: \${TAILSCALE_HOSTNAME}
    network_mode: "host"
    privileged: true
    restart: unless-stopped
    volumes:
      - /var/lib:/var/lib
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      - TS_AUTHKEY=\${TAILSCALE_AUTH_KEY}
      - TS_EXTRA_ARGS=--advertise-tags=tag:ai-platform --accept-routes
EOF
fi

if [[ "${ENABLE_OPENCLAW}" == "true" ]]; then
cat >> "${COMPOSE_FILE}" << EOF
  openclaw:
    image: openclaw/openclaw:latest
    container_name: ${COMPOSE_PROJECT_NAME}-openclaw
    restart: unless-stopped
    network_mode: "service:tailscale"
    depends_on:
      - tailscale
    volumes:
      - ${TENANT_DIR}/openclaw:/app/data
    environment:
      - OPENCLAW_ADMIN_USER=admin
      - OPENCLAW_ADMIN_PASSWORD=\${OPENCLAW_PASSWORD}
EOF
fi

log "Docker Compose file generated."

# --- Validate and Deploy ---
log "Validating Docker Compose configuration..."
cd "${TENANT_DIR}"
if ! docker compose config --quiet; then
    error "Docker Compose file is invalid. Please check the generated ${COMPOSE_FILE}."
    docker compose config # Print the invalid config for debugging
    cd - > /dev/null
    exit 1
fi
log "Configuration is valid."

log "Deploying stack '${COMPOSE_PROJECT_NAME}'..."
docker compose --project-name "${COMPOSE_PROJECT_NAME}" down --remove-orphans 2>/dev/null || true
docker compose --project-name "${COMPOSE_PROJECT_NAME}" up -d --remove-orphans

cd - > /dev/null
log "Deployment initiated. Waiting 60 seconds for services to stabilize..."
sleep 60

# --- Comprehensive Health Check ---
info "Verifying deployment with container and URL health checks..."
echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "  ${BOLD}AI Platform - Live Deployment Health Check${NC}"
echo -e "${BLUE}=============================================${NC}"

FAILED_SERVICES=()
SERVICES=$(docker compose --project-name "${COMPOSE_PROJECT_NAME}" -f "${COMPOSE_FILE}" config --services)

# 1. Container Health Check
info "Checking container health status..."
for service in ${SERVICES}; do
    container_name="${COMPOSE_PROJECT_NAME}-${service}"
    if ! docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"; then
        echo -e "  ${RED}❌ ${service}: NOT RUNNING${NC}"
        FAILED_SERVICES+=("${service}")
        continue
    fi
    
    health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "${container_name}" 2>/dev/null)
    case "${health_status}" in
        "healthy")   echo -e "  ${GREEN}✅ ${service}: running and healthy${NC}" ;;
        "unhealthy") echo -e "  ${RED}❌ ${service}: running but UNHEALTHY${NC}"; FAILED_SERVICES+=("${service}") ;;
        "starting")  echo -e "  ${YELLOW}⏳ ${service}: running but still starting...${NC}"; FAILED_SERVICES+=("${service}") ;;
        *)           echo -e "  ${GREEN}✅ ${service}: running${NC}" ;;
    esac
done
echo ""

# 2. Public URL Health Check
info "Checking public service URLs..."
for service in ${SERVICES}; do
    # Check only services that should be public
    if [[ " caddy postgres redis ollama qdrant tailscale openclaw " =~ " ${service} " ]]; then continue; fi
    
    URL="https://$(echo "$service" | tr '[:upper:]' '[:lower:]').${DOMAIN}"
    status_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${URL}" || echo "000")

    if [[ "${status_code}" -ge 200 && "${status_code}" -lt 400 ]]; then
        echo -e "  ${GREEN}✅ ${URL} is accessible (Status: ${status_code})${NC}"
    elif [[ "${status_code}" -eq 502 ]]; then
        echo -e "  ${YELLOW}⏳ ${URL} is starting up (Status: ${status_code})${NC}"
    else
        echo -e "  ${RED}❌ ${URL} is NOT accessible (Status: ${status_code})${NC}"
        if ! [[ " ${FAILED_SERVICES[*]} " =~ " ${service} " ]]; then FAILED_SERVICES+=("${service}"); fi
    fi
done

echo -e "${BLUE}=============================================${NC}"
if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    log "🎉 Success! All services are running and accessible."
    info "You can now proceed to script 3 to finalize the configuration."
    echo -e "  ${CYAN}sudo bash scripts/3-configure-services.sh${NC}"
else
    error "⚠️ ${#FAILED_SERVICES[@]} services have issues: ${FAILED_SERVICES[*]}"
    error "Please check the logs for the failed services:"
    for failed in "${FAILED_SERVICES[@]}"; do
        echo "  sudo docker logs ${COMPOSE_PROJECT_NAME}-${failed}"
    done
    exit 1
fi
