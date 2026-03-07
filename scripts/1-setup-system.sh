#!/usr/bin/env bash
# =============================================================================
# Script 1: Setup Tenant - v2.0 ARCHITECTURALLY COMPLIANT
# =============================================================================
# PURPOSE: Creates full directory structure, sets ALL directory ownership,
#          and generates complete .env file in one atomic operation.
# USAGE:   sudo bash scripts/1-setup-system.sh <tenant_id> <domain>
# =============================================================================

set -euo pipefail

# --- Arguments & Colors ---
if [[ "${#@}" -ne 2 ]]; then 
    echo "Usage: sudo bash $0 <tenant_id> <domain>" >&2
    exit 1
fi
TENANT_ID="$1"
DOMAIN="$2"

RED='\033[0;31m' GREEN='\033[0;32m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# --- Paths and User Info ---
TENANT_DIR="/mnt/data/${TENANT_ID}"
TENANT_USER="${TENANT_ID}"

# Check if tenant user exists, create if not
if ! id "${TENANT_USER}" &>/dev/null; then
    log "Creating tenant user '${TENANT_USER}'..."
    useradd -m -s /bin/bash "${TENANT_USER}"
    ok "Tenant user '${TENANT_USER}' created."
else
    ok "Tenant user '${TENANT_USER}' (UID: $(id -u ${TENANT_USER}), GID: $(id -g ${TENANT_USER})) found."
fi

TENANT_UID=$(id -u "${TENANT_USER}")
TENANT_GID=$(id -g "${TENANT_USER}")

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    log "Creating all service directories for tenant '${TENANT_ID}'..."
    
    # Define all directories to be created
    DIRECTORIES=(
        "postgres" "redis" "qdrant" "ollama" "openwebui" "n8n" "flowise" 
        "anythingllm" "anythingllm/tmp" "litellm" "authentik/media" 
        "authentik/custom-templates" "prometheus-data" "grafana/provisioning/datasources"
        "caddy"
    )

    for dir in "${DIRECTORIES[@]}"; do
        mkdir -p "${TENANT_DIR}/${dir}"
        ok "Created directory: ${TENANT_DIR}/${dir}"
    done

    log "Setting directory ownership..."

    # Default ownership for most services
    chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}"
    ok "Default ownership set to ${TENANT_UID}:${TENANT_GID} for all directories."

    # Define Service-Specific UIDs (as this is config, it lives here)
    N8N_UID=1000
    OPENWEBUI_UID=1000
    ANYTHINGLLM_UID=1000
    OLLAMA_UID=${TENANT_UID}
    PROMETHEUS_UID=65534

    # Apply specific ownership for services that run as their own internal user
    chown -R "${N8N_UID}:${N8N_UID}" "${TENANT_DIR}/n8n"
    ok "Set n8n directory ownership to ${N8N_UID}:${N8N_UID}"
    chown -R "${OPENWEBUI_UID}:${OPENWEBUI_UID}" "${TENANT_DIR}/openwebui"
    ok "Set openwebui directory ownership to ${OPENWEBUI_UID}:${OPENWEBUI_UID}"
    chown -R "${ANYTHINGLLM_UID}:${ANYTHINGLLM_UID}" "${TENANT_DIR}/anythingllm"
    ok "Set anythingllm directory ownership to ${ANYTHINGLLM_UID}:${ANYTHINGLLM_UID}"
    chown -R "${OLLAMA_UID}:${OLLAMA_UID}" "${TENANT_DIR}/ollama"
    ok "Set ollama directory ownership to ${OLLAMA_UID}:${OLLAMA_UID}"
    chown -R "${PROMETHEUS_UID}:${PROMETHEUS_UID}" "${TENANT_DIR}/prometheus-data"
    ok "Set prometheus directory ownership to ${PROMETHEUS_UID}:${PROMETHEUS_UID}"

    log "All directory permissions have been correctly set."

    # Define constants needed for both .env and Caddyfile
    ADMIN_EMAIL=hosting@datasquiz.net
    N8N_SERVICE_NAME=n8n
    FLOWISE_SERVICE_NAME=flowise
    OPENWEBUI_SERVICE_NAME=openwebui
    ANYTHINGLLM_SERVICE_NAME=anythingllm
    LITELLM_SERVICE_NAME=litellm
    GRAFANA_SERVICE_NAME=grafana
    AUTHENTIK_SERVICE_NAME=authentik-server

    # Generate random passwords
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    REDIS_PASSWORD=$(openssl rand -hex 16)
    GRAFANA_PASSWORD=$(openssl rand -hex 16)
    AUTHENTIK_SECRET_KEY=$(openssl rand -hex 16)

    log "Generating .env file at ${TENANT_DIR}/.env"

    cat > "${TENANT_DIR}/.env" << EOF
# ---------------- General ----------------
COMPOSE_PROJECT_NAME=${TENANT_ID}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
DOMAIN=${DOMAIN}
DATA_ROOT=${TENANT_DIR}
TENANT_DIR=${TENANT_DIR}
N8N_USER=admin
N8N_PASSWORD=admin123

# ---------------- Service Enablement ----------------
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_QDRANT=true
ENABLE_OLLAMA=true
ENABLE_OPENWEBUI=true
ENABLE_ANYTHINGLLM=true
ENABLE_N8N=true
ENABLE_FLOWISE=true
ENABLE_LITELLM=true
ENABLE_GRAFANA=true
ENABLE_PROMETHEUS=true
ENABLE_AUTHENTIK=true
ENABLE_CADDY=true

# ---------------- Service UIDs (for reference in script-2) ----------------
N8N_UID=${N8N_UID}
OPENWEBUI_UID=${OPENWEBUI_UID}
ANYTHINGLLM_UID=${ANYTHINGLLM_UID}
OLLAMA_UID=${OLLAMA_UID}
PROMETHEUS_UID=${PROMETHEUS_UID}

# ---------------- Passwords & Secrets ----------------
POSTGRES_USER=${TENANT_ID}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${TENANT_ID}
REDIS_PASSWORD=${REDIS_PASSWORD}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}

# ---------------- Service Configuration ----------------
POSTGRES_SERVICE_NAME=postgres
REDIS_SERVICE_NAME=redis
QDRANT_SERVICE_NAME=qdrant
OLLAMA_SERVICE_NAME=ollama
N8N_SERVICE_NAME=n8n
FLOWISE_SERVICE_NAME=flowise
OPENWEBUI_SERVICE_NAME=openwebui
ANYTHINGLLM_SERVICE_NAME=anythingllm
LITELLM_SERVICE_NAME=litellm
GRAFANA_SERVICE_NAME=grafana
PROMETHEUS_SERVICE_NAME=prometheus
AUTHENTIK_SERVICE_NAME=authentik-server

# ---------------- Port Configuration ----------------
POSTGRES_PORT=5432
REDIS_PORT=6379
QDRANT_PORT=6333
OLLAMA_PORT=11434
N8N_PORT=5678
FLOWISE_PORT=3000
OPENWEBUI_PORT=8080
ANYTHINGLLM_PORT=3001
LITELLM_PORT=4000
GRAFANA_PORT=3002
PROMETHEUS_PORT=9090
AUTHENTIK_PORT=9000
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443

# ---------------- SSL & Security ----------------
SSL_TYPE=acme
ADMIN_EMAIL=hosting@datasquiz.net
PROJECT_PREFIX=ai-

# ---------------- Vector DB & LLM Configuration ----------------
VECTOR_DB=qdrant
QDRANT_API_KEY=
LLM_PROVIDERS=local

# ---------------- Database Configuration ----------------
DATABASE_TYPE=postgres

EOF

    ok "Tenant setup complete. Environment is ready for deployment."

    log "Generating Caddyfile at ${TENANT_DIR}/caddy/Caddyfile"

    cat > "${TENANT_DIR}/caddy/Caddyfile" << EOF
{
  email ${ADMIN_EMAIL}
}

${DOMAIN} {
  handle /n8n* {
    reverse_proxy ${N8N_SERVICE_NAME}:${N8N_PORT:-5678}
  }
  
  handle /flowise* {
    reverse_proxy ${FLOWISE_SERVICE_NAME}:${FLOWISE_PORT:-3000}
  }
  
  handle /openwebui* {
    reverse_proxy ${OPENWEBUI_SERVICE_NAME}:${OPENWEBUI_PORT:-8080}
  }
  
  handle /anythingllm* {
    reverse_proxy ${ANYTHINGLLM_SERVICE_NAME}:${ANYTHINGLLM_PORT:-3001}
  }
  
  handle /litellm* {
    reverse_proxy ${LITELLM_SERVICE_NAME}:${LITELLM_PORT:-4000}
  }
  
  handle /grafana* {
    reverse_proxy ${GRAFANA_SERVICE_NAME}:${GRAFANA_PORT:-3002}
  }
  
  handle /auth* {
    reverse_proxy ${AUTHENTIK_SERVICE_NAME}:${AUTHENTIK_PORT:-9000}
  }
}

EOF

    ok "Caddyfile written."

    # Create prometheus.yml configuration file
    log "Generating prometheus.yml at ${TENANT_DIR}/prometheus.yml"
    
    cat > "${TENANT_DIR}/prometheus.yml" << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    ok "Prometheus configuration written."
}

# Execute main function
main "$@"
