#!/usr/bin/env bash
# =============================================================================
# Script 2: Deployment Engine Only - BULLETPROOF v4.0
# =============================================================================
# PURPOSE: Deploy services from .env configuration only
# USAGE:   sudo bash scripts/2-deploy-services.sh [tenant_id]
# =============================================================================

set -euo pipefail

# Claude Audit Fix 8: TENANT_ID fallback
TENANT_ID=${1:-"default"}

# Basic Logging Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# Claude Audit: Load environment from .env
load_env() {
    local env_file="/mnt/data/${TENANT_ID}/.env"
    if [[ ! -f "${env_file}" ]]; then
        fail "Environment file not found: ${env_file}. Run Script 1 first."
    fi
    
    log "Loading environment from ${env_file}..."
    source "${env_file}"
    
    # Verify critical variables
    if [[ -z "${DOCKER_NETWORK:-}" || -z "${BIFROST_CONTAINER_NAME:-}" ]]; then
        fail "Critical environment variables missing in ${env_file}"
    fi
}

# Claude Audit: Deploy Qdrant first (Mem0 dependency)
deploy_qdrant() {
    log "Deploying Qdrant vector database..."
    
    docker run -d \
        --name "${QDRANT_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -v "/mnt/data/${TENANT_ID}/data/qdrant:/qdrant/storage" \
        -p "${QDRANT_HOST_PORT}:${QDRANT_CONTAINER_PORT}" \
        qdrant/qdrant:latest
    
    ok "Qdrant deployed as ${QDRANT_CONTAINER_NAME}"
}

# Claude Audit: Deploy Bifrost with correct image and CMD flag
deploy_bifrost() {
    log "Deploying Bifrost LLM proxy..."
    
    docker run -d \
        --name "${BIFROST_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -p "${BIFROST_HOST_PORT}:${BIFROST_CONTAINER_PORT}" \
        -v "/mnt/data/${TENANT_ID}/configs/bifrost:/config:ro" \
        ghcr.io/maximhq/bifrost:latest \
        --config /config/config.yaml  # Claude Audit: CMD argument, NOT env var
    
    ok "Bifrost deployed as ${BIFROST_CONTAINER_NAME}"
}

# Claude Audit: Deploy Ollama without --user flag
deploy_ollama() {
    log "Deploying Ollama LLM inference..."
    
    docker run -d \
        --name "${OLLAMA_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -v "/mnt/data/${TENANT_ID}/data/ollama:/root/.ollama" \
        -p "${OLLAMA_HOST_PORT}:${OLLAMA_CONTAINER_PORT}" \
        --gpus all \
        ghcr.io/ollama/ollama:latest
    
    ok "Ollama deployed as ${OLLAMA_CONTAINER_NAME}"
}

# Claude Audit: Deploy Mem0 with Qdrant configuration
deploy_mem0() {
    log "Deploying Mem0 memory layer..."
    
    docker run -d \
        --name "${MEM0_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e MEM0_VECTOR_STORE_PROVIDER=qdrant \
        -e MEM0_QDRANT_HOST="${QDRANT_CONTAINER_NAME}" \
        -e MEM0_QDRANT_PORT="${QDRANT_CONTAINER_PORT}" \
        -e MEM0_API_KEY="${MEM0_API_KEY}" \
        -p "${MEM0_HOST_PORT}:${MEM0_CONTAINER_PORT}" \
        mem0ai/mem0:latest
    
    ok "Mem0 deployed as ${MEM0_CONTAINER_NAME}"
}

# Claude Audit: Deploy Flowise with correct healthcheck
deploy_flowise() {
    log "Deploying Flowise AI workflow builder..."
    
    docker run -d \
        --name "${FLOWISE_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY}" \
        -p "${FLOWISE_HOST_PORT}:${FLOWISE_CONTAINER_PORT}" \
        --health-cmd="curl -sf http://localhost:${FLOWISE_CONTAINER_PORT}/api/v1/version || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        flowiseai/flowise:latest
    
    ok "Flowise deployed as ${FLOWISE_CONTAINER_NAME}"
}

# Claude Audit: Deploy N8N with proper configuration
deploy_n8n() {
    log "Deploying N8N workflow automation..."
    
    docker run -d \
        --name "${N8N_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -e N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}" \
        -e WEBHOOK_URL="http://${N8N_CONTAINER_NAME}:${N8N_CONTAINER_PORT}" \
        -p "${N8N_HOST_PORT}:${N8N_CONTAINER_PORT}" \
        --health-cmd="curl -sf http://localhost:${N8N_CONTAINER_PORT}/healthz || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        n8nio/n8n:latest
    
    ok "N8N deployed as ${N8N_CONTAINER_NAME}"
}

# Claude Audit: Deploy Grafana with correct user
deploy_grafana() {
    log "Deploying Grafana monitoring..."
    
    docker run -d \
        --name "${GRAFANA_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "472:472" \
        -v "/mnt/data/${TENANT_ID}/data/grafana:/var/lib/grafana" \
        -p "${GRAFANA_HOST_PORT}:${GRAFANA_CONTAINER_PORT}" \
        --health-cmd="curl -sf http://localhost:${GRAFANA_CONTAINER_PORT}/api/health || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        grafana/grafana:latest
    
    ok "Grafana deployed as ${GRAFANA_CONTAINER_NAME}"
}

# Claude Audit: Deploy Prometheus without --user flag
deploy_prometheus() {
    log "Deploying Prometheus metrics collection..."
    
    docker run -d \
        --name "${PROMETHEUS_CONTAINER_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -v "/mnt/data/${TENANT_ID}/data/prometheus:/prometheus" \
        -p "${PROMETHEUS_HOST_PORT}:${PROMETHEUS_CONTAINER_PORT}" \
        --health-cmd="curl -sf http://localhost:${PROMETHEUS_CONTAINER_PORT}/-/healthy || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        prom/prometheus:latest
    
    ok "Prometheus deployed as ${PROMETHEUS_CONTAINER_NAME}"
}

main() {
    log "Starting service deployment for tenant '${TENANT_ID}'..."
    
    # Load environment variables
    load_env
    
    # Claude Audit: Create Docker network FIRST
    log "Creating Docker network ${DOCKER_NETWORK}..."
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || ok "Network ${DOCKER_NETWORK} already exists"
    
    # Deploy in dependency order
    deploy_qdrant      # Mem0 dependency
    deploy_ollama       # Bifrost dependency  
    deploy_bifrost      # LLM proxy
    deploy_mem0         # Memory layer (needs Qdrant)
    deploy_flowise      # AI workflows
    deploy_n8n          # Workflow automation
    deploy_grafana      # Monitoring
    deploy_prometheus    # Metrics collection
    
    ok "All services deployed successfully for tenant '${TENANT_ID}'"
    log "Run 'sudo bash scripts/3-configure-services.sh ${TENANT_ID}' for verification and model pulls."
}

# Call main function
main "$@"
