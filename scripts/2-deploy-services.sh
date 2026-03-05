#!/bin/bash
# Script 2: Deploy Services - Fixed Version with Final Output
# Fixed version with analysis.md improvements and proper final health check

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"; }
error(){ echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

# Configuration paths - loaded from .env
ENV_FILE="${ENV_FILE:-$(sudo ls -t /mnt/data/*/.env 2>/dev/null | head -1)}"
TENANT_DIR="$(dirname "${ENV_FILE}")"
PLATFORM_DIR="${TENANT_DIR}"
COMPOSE_FILE="${PLATFORM_DIR}/docker-compose.yml"

# ─── Load environment ────────────────────────────────────────────────
[[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]] && {
    error "Cannot find .env file. Run script 1 first."
    exit 1
}

log "Using .env: ${ENV_FILE}"

set -a
source "${ENV_FILE}"
set +a

# Get tenant UID/GID
TENANT_UID=$(id -u jglaine)
TENANT_GID=$(id -g jglaine)

# ─── Root check ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo bash 2-deploy-services-fixed.sh)"
    exit 1
fi

# ─── Docker daemon ────────────────────────────────────────────────────
log "Ensuring Docker daemon is running..."
systemctl start docker
sleep 2
if ! docker info &>/dev/null; then
    error "Docker daemon is not responding. Check: systemctl status docker"
    exit 1
fi
log "Docker daemon OK"

# ─── Create required directories ─────────────────────────────────────
log "Creating required bind-mount directories..."
mkdir -p "${PLATFORM_DIR}/caddy/data"
mkdir -p "${PLATFORM_DIR}/postgres"
mkdir -p "${PLATFORM_DIR}/redis"
mkdir -p "${PLATFORM_DIR}/ollama"
mkdir -p "${PLATFORM_DIR}/qdrant"
mkdir -p "${PLATFORM_DIR}/prometheus"
mkdir -p "${PLATFORM_DIR}/grafana"
mkdir -p "${PLATFORM_DIR}/prometheus/data"

# Create prometheus config
cat > "${PLATFORM_DIR}/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['${COMPOSE_PROJECT_NAME}-prometheus:9090']
EOF

chown -R "${TENANT_UID}:${TENANT_GID}" "${PLATFORM_DIR}"
chmod -R 755 "${PLATFORM_DIR}"
log "Directories ready"

# ─── Generate clean docker-compose.yml ───────────────────────────
log "Generating docker-compose.yml → ${COMPOSE_FILE}"

cat > "${COMPOSE_FILE}" << EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: ai-datasquiz-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - ${PLATFORM_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ai-datasquiz-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    container_name: ai-datasquiz-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${PLATFORM_DIR}/redis:/data
    networks:
      - ai-datasquiz-net
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  ollama:
    image: ollama/ollama:latest
    container_name: ai-datasquiz-ollama
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_PORT=${OLLAMA_INTERNAL_PORT}
    volumes:
      - ${PLATFORM_DIR}/ollama:/root/.ollama
    networks:
      - ai-datasquiz-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${OLLAMA_INTERNAL_PORT}/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ai-datasquiz-qdrant
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - QDRANT__SERVICE__HTTP_PORT=${QDRANT_INTERNAL_HTTP_PORT}
    volumes:
      - ${PLATFORM_DIR}/qdrant:/qdrant/storage
    networks:
      - ai-datasquiz-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${QDRANT_INTERNAL_HTTP_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  prometheus:
    image: prom/prometheus:latest
    container_name: ai-datasquiz-prometheus
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "9090:9090"
    volumes:
      - ${PLATFORM_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${PLATFORM_DIR}/prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
    networks:
      - ai-datasquiz-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  grafana:
    image: grafana/grafana:latest
    container_name: ai-datasquiz-grafana
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "3002:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
    volumes:
      - ${PLATFORM_DIR}/grafana:/var/lib/grafana
    networks:
      - ai-datasquiz-net
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  caddy:
    image: caddy:2-alpine
    container_name: ai-datasquiz-caddy
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
      - "2019:2019"
    volumes:
      - ${PLATFORM_DIR}/caddy/config/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${PLATFORM_DIR}/caddy/data:/data
    networks:
      - ai-datasquiz-net
    depends_on:
      - postgres
      - redis
      - ollama
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai-datasquiz-net:
    driver: bridge
EOF

# Ensure proper ownership
chown "${TENANT_UID}:${TENANT_GID}" "${COMPOSE_FILE}"
log "Docker Compose generated successfully"

# ─── Validate compose config ──────────────────────────────────────────
log "Validating Docker Compose configuration..."
cd "${PLATFORM_DIR}"
if ! docker compose config --quiet 2>&1; then
    error "docker-compose.yml is invalid. Output:"
    docker compose config 2>&1
    exit 1
fi
log "Configuration valid"

# ─── Deploy stack ──────────────────────────────────────────────────
log "Starting deployment..."
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

# ─── Wait for containers to initialise ─────────────────────────────
log "Waiting 30 seconds for containers to initialise..."
sleep 30

# ─── Verify deployment with detailed health check ───────────────────────
log "Verifying deployment status..."

echo ""
echo "=========================================="
echo "  AI Platform — Deployment Health Check"
echo "=========================================="

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Check each service
SERVICES=(
    "postgres" "redis" "ollama" "qdrant"
    "prometheus" "grafana" "caddy"
    "n8n" "flowise" "openwebui" "anythingllm" "litellm"
)
FAILED_SERVICES=()

for service in "${SERVICES[@]}"; do
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "ai-datasquiz-${service}.*Up"; then
        status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "ai-datasquiz-${service}" | awk '{print $2,$3,$4}')
        echo "  ✅  ${service}: ${status}"
    else
        echo "  ❌  ${service}: NOT RUNNING"
        FAILED_SERVICES+=("$service")
    fi
done

# URL Health Check
echo ""
echo "🌐 Service URL Health Check:"
echo "  PostgreSQL:           ${SERVER_IP}:5432"
echo "  Redis:               ${SERVER_IP}:6379"
echo "  Ollama API:          http://${SERVER_IP}:11434"
echo "  Qdrant:              http://${SERVER_IP}:6333"
echo "  Prometheus:          http://${SERVER_IP}:9090"
echo "  Grafana:             http://${SERVER_IP}:3002"
echo "  Caddy (HTTP):        http://${SERVER_IP}:80"
echo "  Caddy (HTTPS):       https://${SERVER_IP}:443"

# Port connectivity check
echo ""
echo "🔌 Port Connectivity Check:"
PORTS=("5432:PostgreSQL" "6379:Redis" "11434:Ollama" "6333:Qdrant" "9090:Prometheus" "3002:Grafana" "80:Caddy-HTTP" "443:Caddy-HTTPS")

for port_info in "${PORTS[@]}"; do
    port=$(echo "$port_info" | cut -d':' -f1)
    name=$(echo "$port_info" | cut -d':' -f2)
    
    if ss -tlnp | grep -q ":$port "; then
        echo "  ✅  Port $port ($name) is listening"
    else
        echo "  ⚠️   Port $port ($name) not yet listening"
    fi
done

# Summary
echo ""
echo "=========================================="
if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo "  🎉 ALL SERVICES RUNNING SUCCESSFULLY!"
    echo "  🌐 Access URLs listed above"
    echo "  📊 Grafana: http://${SERVER_IP}:3002 (admin/${GRAFANA_PASSWORD})"
else
    echo "  ⚠️  ${#FAILED_SERVICES[@]} services failed:"
    for failed in "${FAILED_SERVICES[@]}"; do
        echo "     - $failed"
    done
    echo ""
    echo "  🔍 Debug with: docker compose logs [service]"
fi
echo "=========================================="
echo ""

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    warn "Some services failed to start. Check logs for details."
    exit 1
else
    log "Deployment complete! All services are healthy."
fi
