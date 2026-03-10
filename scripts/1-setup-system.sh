#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v3.1
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# =============================================================================

set -euo pipefail

# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Script Globals ---
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Prerequisite Checks ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "This script must be run as root (use sudo)."
    fi
}

# --- Main Application Logic ---

# This function will be called at the end of the script
# It generates the Caddyfile based on the final, confirmed ENV vars.
write_caddyfile() {
    log "Generating Production Caddyfile..."
    
    local CADDYFILE_PATH="${DATA_ROOT}/Caddyfile"
    
    # Start with a clean file and the global config
    cat > "${CADDYFILE_PATH}" << EOF
# AI Platform Production Caddyfile
# Generated: $(date -u --iso-8601=seconds)
{
    email ${LETSENCRYPT_EMAIL}
}
EOF

    # --- Dynamically Append Service Blocks using CORRECT INTERNAL PORTS ---
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        echo "grafana.${DOMAIN} { reverse_proxy grafana:3000 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        echo "openwebui.${DOMAIN} { reverse_proxy openwebui:8080 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        echo "anythingllm.${DOMAIN} { reverse_proxy anythingllm:3001 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        echo "dify.${DOMAIN} { reverse_proxy dify-web:3000 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_FLOWISE}" == "true" ]]; then
        echo "flowise.${DOMAIN} { reverse_proxy flowise:3000 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        echo "n8n.${DOMAIN} { reverse_proxy n8n:5678 }" >> "${CADDYFILE_PATH}"
    fi
    if [[ "${ENABLE_AUTHENTIK}" == "true" ]]; then
        echo "auth.${DOMAIN} { reverse_proxy authentik-server:9000 }" >> "${CADDYFILE_PATH}"
    fi

    ok "Production Caddyfile generated with all enabled services."
}

write_env_file() {
    # This function is simplified to just write the collected variables
    # All logic for defaults and collection is handled elsewhere.
    log "Writing configuration to ${DATA_ROOT}/.env ..."
    
    # Create a temporary file
    local temp_env_file="${DATA_ROOT}/.env.tmp"

    # The heredoc contains ALL possible variables.
    # If a variable is empty, it will be written as `VAR=` which is harmless.
    cat > "${temp_env_file}" << EOF
# AI Platform Environment Configuration
# Generated: $(date -u --iso-8601=seconds)

# --- Platform Identity ---
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
DATA_ROOT=${DATA_ROOT}

# --- Tenant User ---
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}

# --- Service Flags ---
ENABLE_POSTGRES=${ENABLE_POSTGRES:-true}
ENABLE_REDIS=${ENABLE_REDIS:-true}
ENABLE_CADDY=true
ENABLE_OLLAMA=${ENABLE_OLLAMA:-false}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI:-false}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM:-false}
ENABLE_DIFY=${ENABLE_DIFY:-false}
ENABLE_N8N=${ENABLE_N8N:-false}
ENABLE_FLOWISE=${ENABLE_FLOWISE:-false}
ENABLE_LITELLM=${ENABLE_LITELLM:-false}
ENABLE_QDRANT=${ENABLE_QDRANT:-false}
ENABLE_GRAFANA=${ENABLE_GRAFANA:-false}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS:-false}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK:-false}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE:-false}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW:-false}
ENABLE_RCLONE=${ENABLE_RCLONE:-false}

# --- Project Naming ---
COMPOSE_PROJECT_NAME=ai-${TENANT_ID}
DOCKER_NETWORK=ai-${TENANT_ID}-net

# --- Secrets (Auto-generated) ---
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
N8N_USER=admin@${DOMAIN}
N8N_PASSWORD=${N8N_PASSWORD}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}

# --- Tailscale ---
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}

EOF

    # Atomically replace the old .env file
    mv "${temp_env_file}" "${DATA_ROOT}/.env"
    chmod 600 "${DATA_ROOT}/.env"
    ok "Configuration written to ${DATA_ROOT}/.env"
}

main() {
    check_root

    # --- Variable Collection ---
    # This is a simplified representation of the interactive collection process.
    # In a real run, these would be filled by `read` commands.
    
    log "Starting AI Platform Setup Wizard..."
    
    # Example of collecting variables
    TENANT_ID="datasquiz"
    DOMAIN="ai.datasquiz.net"
    LETSENCRYPT_EMAIL="joss.laine@gmail.com"
    DATA_ROOT="/mnt/data/${TENANT_ID}"

    # Get Tenant UID/GID
    TENANT_UID=${SUDO_UID:-$(id -u)}
    TENANT_GID=${SUDO_GID:-$(id -g)}

    # Service Selection (example)
    ENABLE_OLLAMA="true"
    ENABLE_OPENWEBUI="true"
    ENABLE_N8N="true"
    ENABLE_FLOWISE="true"
    ENABLE_LITELLM="true"
    ENABLE_QDRANT="true"
    ENABLE_GRAFANA="true"
    ENABLE_PROMETHEUS="true"
    ENABLE_TAILSCALE="true"

    # Secret Generation
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
    N8N_PASSWORD=$(openssl rand -hex 16)
    AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)

    # Placeholder for Tailscale key
    TAILSCALE_AUTH_KEY=""

    # --- Directory and File Creation ---
    log "Creating directory structure in ${DATA_ROOT}..."
    mkdir -p "${DATA_ROOT}/lib/tailscale"
    mkdir -p "${DATA_ROOT}/prometheus-data"
    mkdir -p "${DATA_ROOT}/caddy_data"
    mkdir -p "${DATA_ROOT}/postgres"
    mkdir -p "${DATA_ROOT}/redis"
    mkdir -p "${DATA_ROOT}/qdrant"
    mkdir -p "${DATA_ROOT}/ollama"
    mkdir -p "${DATA_ROOT}/openwebui"
    mkdir -p "${DATA_ROOT}/n8n"
    mkdir -p "${DATA_ROOT}/flowise"
    mkdir -p "${DATA_ROOT}/litellm"
    mkdir -p "${DATA_ROOT}/grafana"
    mkdir -p "${DATA_ROOT}/rclone"
    mkdir -p "${DATA_ROOT}/authentik/media"
    mkdir -p "${DATA_ROOT}/authentik/custom-templates"

    # Set Ownership
    log "Applying directory ownership..."
    chown -R ${TENANT_UID}:${TENANT_GID} "${DATA_ROOT}"
    # Apply exceptions for services that run as a different user internally
    chown -R 472:472 "${DATA_ROOT}/grafana"
    chown -R 1000:1000 "${DATA_ROOT}/qdrant"
    chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"
    ok "Directory structure and ownership configured."

    # --- Final Configuration File Generation ---
    write_env_file
    write_caddyfile
    
    # Prometheus Config
    cat > "${DATA_ROOT}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    ok "Setup complete. Ready to run script 2."
}

# Execute the main function
main "$@"