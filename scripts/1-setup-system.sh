#!/usr/bin/env bash
# =============================================================================
# Script 1: Input Collector Only - BULLETPROOF v4.0
# =============================================================================
# PURPOSE: User interaction and .env generation only (NO operations)
# USAGE:   sudo bash scripts/1-setup-system.sh [tenant_id]
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

# Claude Audit: Generate random tokens
generate_token() {
    openssl rand -hex 16
}

main() {
    log "Starting input collection for tenant '${TENANT_ID}'..."
    
    # Claude Audit: /mnt writable check
    if [[ ! -w "/mnt" ]]; then
        fail "/mnt is not writable. Cannot proceed with deployment."
    fi
    
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    ENV_FILE="${DATA_ROOT}/.env"
    
    # Create directory structure
    log "Creating directory structure..."
    mkdir -p "${DATA_ROOT}/configs/bifrost"
    mkdir -p "${DATA_ROOT}/configs/mem0"
    mkdir -p "${DATA_ROOT}/configs/prometheus"
    mkdir -p "${DATA_ROOT}/data/n8n"
    mkdir -p "${DATA_ROOT}/data/flowise"
    mkdir -p "${DATA_ROOT}/data/bifrost"
    mkdir -p "${DATA_ROOT}/data/mem0"
    mkdir -p "${DATA_ROOT}/data/prometheus"
    mkdir -p "${DATA_ROOT}/data/grafana"
    mkdir -p "${DATA_ROOT}/data/qdrant"
    mkdir -p "${DATA_ROOT}/data/ollama"
    mkdir -p "${DATA_ROOT}/logs"
    
    # Claude Audit: Per-service chown (NOT blanket)
    log "Setting per-service ownership..."
    chown -R 1000:1000 "${DATA_ROOT}/data/n8n"
    chown -R 1000:1000 "${DATA_ROOT}/data/flowise"
    chown -R 1000:1000 "${DATA_ROOT}/data/bifrost"
    chown -R 1000:1000 "${DATA_ROOT}/data/mem0"
    chown -R 1000:1000 "${DATA_ROOT}/configs/"
    chown -R 65534:65534 "${DATA_ROOT}/data/prometheus"  # Prometheus runs as nobody
    chown -R 472:472 "${DATA_ROOT}/data/grafana"         # Grafana runs as grafana user
    chown -R 0:0 "${DATA_ROOT}/data/ollama"              # Ollama runs as root internally
    chown -R 1000:1000 "${DATA_ROOT}/data/qdrant"         # Qdrant runs as user 1000
    
    # Claude Audit: Generate all environment variables
    log "Generating environment variables..."
    
    # Core identity
    DOMAIN="${DOMAIN:-${TENANT_ID}.local}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN}}"
    
    # Service ports (no hardcoded values)
    BIFROST_HOST_PORT="${BIFROST_HOST_PORT:-7575}"
    BIFROST_CONTAINER_PORT="${BIFROST_CONTAINER_PORT:-7575}"
    OLLAMA_HOST_PORT="${OLLAMA_HOST_PORT:-11434}"
    OLLAMA_CONTAINER_PORT="${OLLAMA_CONTAINER_PORT:-11434}"
    MEM0_HOST_PORT="${MEM0_HOST_PORT:-8081}"
    MEM0_CONTAINER_PORT="${MEM0_CONTAINER_PORT:-8081}"
    FLOWISE_HOST_PORT="${FLOWISE_HOST_PORT:-3000}"
    FLOWISE_CONTAINER_PORT="${FLOWISE_CONTAINER_PORT:-3000}"
    N8N_HOST_PORT="${N8N_HOST_PORT:-5678}"
    N8N_CONTAINER_PORT="${N8N_CONTAINER_PORT:-5678}"
    GRAFANA_HOST_PORT="${GRAFANA_HOST_PORT:-3010}"
    GRAFANA_CONTAINER_PORT="${GRAFANA_CONTAINER_PORT:-3000}"
    PROMETHEUS_HOST_PORT="${PROMETHEUS_HOST_PORT:-9090}"
    PROMETHEUS_CONTAINER_PORT="${PROMETHEUS_CONTAINER_PORT:-9090}"
    QDRANT_HOST_PORT="${QDRANT_HOST_PORT:-6333}"
    QDRANT_CONTAINER_PORT="${QDRANT_CONTAINER_PORT:-6333}"
    
    # Container names
    DOCKER_NETWORK="ai-${TENANT_ID}"
    BIFROST_CONTAINER_NAME="ai-${TENANT_ID}-bifrost-1"
    OLLAMA_CONTAINER_NAME="ai-${TENANT_ID}-ollama-1"
    MEM0_CONTAINER_NAME="ai-${TENANT_ID}-mem0-1"
    QDRANT_CONTAINER_NAME="ai-${TENANT_ID}-qdrant-1"
    FLOWISE_CONTAINER_NAME="ai-${TENANT_ID}-flowise-1"
    N8N_CONTAINER_NAME="ai-${TENANT_ID}-n8n-1"
    GRAFANA_CONTAINER_NAME="ai-${TENANT_ID}-grafana-1"
    PROMETHEUS_CONTAINER_NAME="ai-${TENANT_ID}-prometheus-1"
    
    # Authentication tokens
    BIFROST_AUTH_TOKEN="${BIFROST_AUTH_TOKEN:-sk-$(generate_token)}"
    N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(generate_token)}"
    FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY:-$(generate_token)}"
    MEM0_API_KEY="${MEM0_API_KEY:-sk-$(generate_token)}"
    
    # Model configuration
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2}"
    
    # Claude Audit: Bifrost config via heredoc (NOT python yaml.dump)
    log "Generating Bifrost configuration..."
    cat > "${DATA_ROOT}/configs/bifrost/config.yaml" << EOF
server:
  port: ${BIFROST_CONTAINER_PORT}  # Claude Audit: from env, NOT hardcoded 8000
  
providers:
  - name: ollama
    api_key: "none"
    base_url: "http://${OLLAMA_CONTAINER_NAME}:${OLLAMA_CONTAINER_PORT}"
    models:
      - name: "${OLLAMA_DEFAULT_MODEL}"  # Bare name at provider level

auth:
  tokens:
    - token: "${BIFROST_AUTH_TOKEN}"
EOF
    
    # Claude Audit: Write .env file with ALL required variables
    log "Writing .env file..."
    cat > "${ENV_FILE}" << EOF
# Core Identity
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}

# Network Configuration
DOCKER_NETWORK=${DOCKER_NETWORK}

# Bifrost Configuration
BIFROST_HOST_PORT=${BIFROST_HOST_PORT}
BIFROST_CONTAINER_PORT=${BIFROST_CONTAINER_PORT}
BIFROST_CONTAINER_NAME=${BIFROST_CONTAINER_NAME}
BIFROST_AUTH_TOKEN=${BIFROST_AUTH_TOKEN}

# Ollama Configuration
OLLAMA_HOST_PORT=${OLLAMA_HOST_PORT}
OLLAMA_CONTAINER_PORT=${OLLAMA_CONTAINER_PORT}
OLLAMA_CONTAINER_NAME=${OLLAMA_CONTAINER_NAME}
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL}

# Mem0 Configuration
MEM0_HOST_PORT=${MEM0_HOST_PORT}
MEM0_CONTAINER_PORT=${MEM0_CONTAINER_PORT}
MEM0_CONTAINER_NAME=${MEM0_CONTAINER_NAME}
MEM0_API_KEY=${MEM0_API_KEY}

# Qdrant Configuration
QDRANT_HOST_PORT=${QDRANT_HOST_PORT}
QDRANT_CONTAINER_PORT=${QDRANT_CONTAINER_PORT}
QDRANT_CONTAINER_NAME=${QDRANT_CONTAINER_NAME}

# Flowise Configuration
FLOWISE_HOST_PORT=${FLOWISE_HOST_PORT}
FLOWISE_CONTAINER_PORT=${FLOWISE_CONTAINER_PORT}
FLOWISE_CONTAINER_NAME=${FLOWISE_CONTAINER_NAME}
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}

# N8N Configuration
N8N_HOST_PORT=${N8N_HOST_PORT}
N8N_CONTAINER_PORT=${N8N_CONTAINER_PORT}
N8N_CONTAINER_NAME=${N8N_CONTAINER_NAME}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Grafana Configuration
GRAFANA_HOST_PORT=${GRAFANA_HOST_PORT}
GRAFANA_CONTAINER_PORT=${GRAFANA_CONTAINER_PORT}
GRAFANA_CONTAINER_NAME=${GRAFANA_CONTAINER_NAME}

# Prometheus Configuration
PROMETHEUS_HOST_PORT=${PROMETHEUS_HOST_PORT}
PROMETHEUS_CONTAINER_PORT=${PROMETHEUS_CONTAINER_PORT}
PROMETHEUS_CONTAINER_NAME=${PROMETHEUS_CONTAINER_NAME}
EOF
    
    # Set .env file permissions
    chmod 600 "${ENV_FILE}"
    chown "${SUDO_USER}:${SUDO_USER}" "${ENV_FILE}" 2>/dev/null || chown 1000:1000 "${ENV_FILE}"
    
    ok "Input collection complete for tenant '${TENANT_ID}'"
    ok "Environment file written to: ${ENV_FILE}"
    ok "Bifrost config written to: ${DATA_ROOT}/configs/bifrost/config.yaml"
    log "Run 'sudo bash scripts/2-deploy-services.sh ${TENANT_ID}' to deploy services."
}

# Call main function
main "$@"
