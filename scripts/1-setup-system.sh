#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v3.5
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform, aligned with Mission Control.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES ---
# All logging and utility functions are now sourced from the central script.
source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"

# --- Main Application Logic ---

write_caddyfile() {
    log "Generating Production Caddyfile..."
    
    local CADDYFILE_PATH="${DATA_ROOT}/Caddyfile"
    
    cat > "${CADDYFILE_PATH}" << EOF
# AI Platform Production Caddyfile
# Generated: $(date -u --iso-8601=seconds)
{
    email ${LETSENCRYPT_EMAIL}
}
EOF

    # --- Dynamically Append Service Blocks ---
    [[ "${ENABLE_GRAFANA}" == "true" ]] && echo "grafana.${DOMAIN} { reverse_proxy grafana:3000 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && echo "openwebui.${DOMAIN} { reverse_proxy openwebui:8080 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && echo "anythingllm.${DOMAIN} { reverse_proxy anythingllm:3001 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_DIFY}" == "true" ]] && echo "dify.${DOMAIN} { reverse_proxy dify-web:3000 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_FLOWISE}" == "true" ]] && echo "flowise.${DOMAIN} { reverse_proxy flowise:3000 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_N8N}" == "true" ]] && echo "n8n.${DOMAIN} { reverse_proxy n8n:5678 }" >> "${CADDYFILE_PATH}"
    [[ "${ENABLE_AUTHENTIK}" == "true" ]] && echo "auth.${DOMAIN} { reverse_proxy authentik-server:9000 }" >> "${CADDYFILE_PATH}"

    chmod 644 "${CADDYFILE_PATH}"
    chown "${TENANT_UID}:${TENANT_GID}" "${CADDYFILE_PATH}"

    ok "Production Caddyfile generated and secured."
}

write_env_file() {
    log "Writing configuration to ${DATA_ROOT}/.env ..."
    
    local temp_env_file="${DATA_ROOT}/.env.tmp"
    local final_env_file="${DATA_ROOT}/.env"

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
ENABLE_POSTGRES=${ENABLE_POSTGRES}
ENABLE_REDIS=${ENABLE_REDIS}
ENABLE_CADDY=${ENABLE_CADDY}
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW}
ENABLE_RCLONE=${ENABLE_RCLONE}

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

    mv "${temp_env_file}" "${final_env_file}"
    chmod 600 "${final_env_file}"
    chown "${TENANT_UID}:${TENANT_GID}" "${final_env_file}"
    ok "Configuration written and secured: ${final_env_file}"
}

main() {
    log "Starting AI Platform Setup Wizard..."
    
    # --- Step 1: Define Identifiers ---
    TENANT_ID="datasquiz"
    DOMAIN="ai.datasquiz.net"
    LETSENCRYPT_EMAIL="joss.laine@gmail.com"
    DATA_ROOT="/mnt/data/${TENANT_ID}"

    TENANT_UID=${SUDO_UID:-$(id -u)}
    TENANT_GID=${SUDO_GID:-$(id -g)}

    # --- Step 2: Initialize All Service Flags to false ---
    # This prevents "unbound variable" errors.
    ENABLE_POSTGRES="true"
    ENABLE_REDIS="true"
    ENABLE_CADDY="true"
    ENABLE_OLLAMA="false"
    ENABLE_OPENWEBUI="false"
    ENABLE_ANYTHINGLLM="false"
    ENABLE_DIFY="false"
    ENABLE_N8N="false"
    ENABLE_FLOWISE="false"
    ENABLE_LITELLM="false"
    ENABLE_QDRANT="false"
    ENABLE_GRAFANA="false"
    ENABLE_PROMETHEUS="false"
    ENABLE_AUTHENTIK="false"
    ENABLE_TAILSCALE="false"
    ENABLE_OPENCLAW="false"
    ENABLE_RCLONE="false"

    # --- Step 3: Service Selection (Example) ---
    # Only enable the services needed for this specific test run.
    ENABLE_OLLAMA="true"
    ENABLE_OPENWEBUI="true"
    ENABLE_N8N="true"
    ENABLE_FLOWISE="true"
    ENABLE_LITELLM="true"
    ENABLE_QDRANT="true"
    ENABLE_GRAFANA="true"
    ENABLE_PROMETHEUS="true"
    ENABLE_TAILSCALE="true"

    # --- Step 4: Generate Secrets ---
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
    N8N_PASSWORD=$(openssl rand -hex 16)
    AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)
    TAILSCALE_AUTH_KEY=""

    # --- Step 5: Create Directory Structure ---
    log "Creating directory structure in ${DATA_ROOT}..."
    mkdir -p "${DATA_ROOT}/lib/tailscale" "${DATA_ROOT}/prometheus-data" "${DATA_ROOT}/caddy_data" \
             "${DATA_ROOT}/postgres" "${DATA_ROOT}/redis" "${DATA_ROOT}/qdrant" "${DATA_ROOT}/ollama" \
             "${DATA_ROOT}/openwebui" "${DATA_ROOT}/n8n" "${DATA_ROOT}/flowise" "${DATA_ROOT}/litellm" \
             "${DATA_ROOT}/grafana" "${DATA_ROOT}/rclone" "${DATA_ROOT}/authentik/media" \
             "${DATA_ROOT}/authentik/custom-templates"
    ok "Directory structure created."

    # --- Step 6: Set Ownership ---
    log "Applying base directory ownership..."
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    ok "Base ownership applied."

    # --- Step 7: Generate Configuration Files ---
    write_env_file
    write_caddyfile
    
    # --- Step 8: Create Prometheus Config ---
    PROMETHEUS_CONFIG_PATH="${DATA_ROOT}/prometheus.yml"
    cat > "${PROMETHEUS_CONFIG_PATH}" << EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    chmod 644 "${PROMETHEUS_CONFIG_PATH}"
    chown "${TENANT_UID}:${TENANT_GID}" "${PROMETHEUS_CONFIG_PATH}"
    ok "Prometheus configuration generated."

    # --- Step 9: Apply Service-Specific Ownership Exceptions ---
    log "Applying service-specific ownership overrides..."
    [[ "${ENABLE_GRAFANA}" == "true" ]] && chown -R 472:472 "${DATA_ROOT}/grafana"
    [[ "${ENABLE_QDRANT}" == "true" ]] && chown -R 1000:1000 "${DATA_ROOT}/qdrant"
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"
    ok "Service-specific ownership configured."
    
    ok "Setup complete. All configurations generated and secured. Ready for script 2."
}

# Execute the main function
main "$@"
