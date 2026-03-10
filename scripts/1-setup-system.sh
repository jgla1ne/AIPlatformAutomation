#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v3.8 (INTERACTIVE & DYNAMIC)
# =============================================================================
# PURPOSE: Interactive, dynamic setup wizard for AI Platform.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES & SERVICE LIST ---
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
    # Dynamically add services based on the master list
    for SERVICE in "${AVAILABLE_SERVICES[@]}"; do
        local ENABLE_VAR="ENABLE_${SERVICE}"
        if [[ "${!ENABLE_VAR}" == "true" ]]; then
            case "$SERVICE" in
                "GRAFANA") echo "grafana.${DOMAIN} { reverse_proxy grafana:3000 }" >> "${CADDYFILE_PATH}" ;;
                "OPENWEBUI") echo "openwebui.${DOMAIN} { reverse_proxy openwebui:8080 }" >> "${CADDYFILE_PATH}" ;;
                "ANYTHINGLLM") echo "anythingllm.${DOMAIN} { reverse_proxy anythingllm:3001 }" >> "${CADDYFILE_PATH}" ;;
                "DIFY") echo "dify.${DOMAIN} { reverse_proxy dify-web:3000 }" >> "${CADDYFILE_PATH}" ;;
                "FLOWISE") echo "flowise.${DOMAIN} { reverse_proxy flowise:3000 }" >> "${CADDYFILE_PATH}" ;;
                "N8N") echo "n8n.${DOMAIN} { reverse_proxy n8n:5678 }" >> "${CADDYFILE_PATH}" ;;
                "AUTHENTIK") echo "auth.${DOMAIN} { reverse_proxy authentik-server:9000 }" >> "${CADDYFILE_PATH}" ;;
            esac
        fi
    done
    chmod 644 "${CADDYFILE_PATH}"
    chown "${TENANT_UID}:${TENANT_GID}" "${CADDYFILE_PATH}"
    ok "Production Caddyfile generated and secured."
}

write_env_file() {
    log "Writing configuration to ${DATA_ROOT}/.env ..."
    local temp_env_file="${DATA_ROOT}/.env.tmp"
    local final_env_file="${DATA_ROOT}/.env"
    
    # Begin writing the .env file
    {
        echo "# AI Platform Environment Configuration - Generated: $(date -u --iso-8601=seconds)"
        echo "TENANT_ID=${TENANT_ID}"
        echo "DOMAIN=${DOMAIN}"
        echo "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}"
        echo "DATA_ROOT=${DATA_ROOT}"
        echo "TENANT_UID=${TENANT_UID}"
        echo "TENANT_GID=${TENANT_GID}"
        echo "# --- Service Flags ---"
        # Dynamically write all service flags
        for SERVICE in "${AVAILABLE_SERVICES[@]}"; do
            local ENABLE_VAR="ENABLE_${SERVICE}"
            echo "${ENABLE_VAR}=${!ENABLE_VAR}"
        done
        # Add core, non-optional services
        echo "ENABLE_POSTGRES=true"
        echo "ENABLE_REDIS=true"
        echo "ENABLE_CADDY=true"
        echo "# --- Project Naming ---"
        echo "COMPOSE_PROJECT_NAME=ai-${TENANT_ID}"
        echo "DOCKER_NETWORK=ai-${TENANT_ID}-net"
        echo "# --- Secrets (Auto-generated) ---"
        echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
        echo "REDIS_PASSWORD=${REDIS_PASSWORD}"
        echo "LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}"
        echo "GRAFANA_ADMIN_USER=admin"
        echo "GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}"
        echo "N8N_USER=admin@${DOMAIN}"
        echo "N8N_PASSWORD=${N8N_PASSWORD}"
        echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}"
        echo "# --- Tailscale ---"
        echo "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}"
        echo "TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}"
    } > "${temp_env_file}"
    
    mv "${temp_env_file}" "${final_env_file}"
    chmod 600 "${final_env_file}"
    chown "${TENANT_UID}:${TENANT_GID}" "${final_env_file}"
    ok "Configuration written and secured: ${final_env_file}"
}

show_menu() {
    clear
    log "--- AI Platform Service Selection ---"
    echo "Domain: ${DOMAIN}" 
    echo "Data Root: ${DATA_ROOT}"
    echo "-------------------------------------"
    # Dynamically generate the menu from the master list
    for i in "${!AVAILABLE_SERVICES[@]}"; do
        local service_name="${AVAILABLE_SERVICES[$i]}"
        local enable_var="ENABLE_${service_name}"
        local status="${!enable_var}"
        printf "%2d. %-20s: %s\n" "$((i+1))" "${service_name}" "${status}"
    done
    echo "-------------------------------------"
    echo "C. Confirm and Continue"
    echo "Q. Quit"
    echo "-------------------------------------"
}

toggle_service() {
    local service_index=$(( $1 - 1 ))
    local service_name="${AVAILABLE_SERVICES[$service_index]}"
    local service_var_name="ENABLE_${service_name}"
    if [[ "${!service_var_name}" == "true" ]]; then
        declare -g "$service_var_name=false"
    else
        declare -g "$service_var_name=true"
    fi
}

main() {
    log "Starting AI Platform Setup Wizard..."
    
    # --- Step 1: Interactive Data Gathering ---
    read -p "Enter Tenant ID (e.g., datasquiz): " TENANT_ID
    read -p "Enter Domain (e.g., ai.datasquiz.net): " DOMAIN
    read -p "Enter Let's Encrypt Email: " LETSENCRYPT_EMAIL
    DATA_ROOT="/mnt/data/${TENANT_ID}"

    TENANT_UID=${SUDO_UID:-$(id -u)}
    TENANT_GID=${SUDO_GID:-$(id -g)}

    # --- Step 2: Initialize All Service Flags to false ---
    for SERVICE in "${AVAILABLE_SERVICES[@]}"; do
        declare -g "ENABLE_${SERVICE}=false"
    done

    # --- Step 3: Interactive Service Selection ---
    while true; do
        show_menu
        read -p "Enter your choice (1-${#AVAILABLE_SERVICES[@]}, C, or Q): " choice
        case $choice in
            [Qq]) fail "Setup aborted by user." ;;
            [Cc]) break ;; 
            *) 
                if [[ "$choice" -ge 1 && "$choice" -le ${#AVAILABLE_SERVICES[@]} ]]; then
                    toggle_service "$choice"
                else
                    warn "Invalid option. Please try again." ; sleep 1
                fi
            ;;
        esac
    done

    # --- Step 4: Generate Secrets ---
    log "Generating secrets..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
    N8N_PASSWORD=$(openssl rand -hex 16)
    AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)
    read -p "Enter your Tailscale Auth Key (or press Enter to skip): " TAILSCALE_AUTH_KEY

    # --- Step 5: Create Directory Structure & Ownership ---
    log "Creating directory structure in ${DATA_ROOT}..."
    mkdir -p "${DATA_ROOT}/lib/tailscale" "${DATA_ROOT}/prometheus-data" "${DATA_ROOT}/caddy_data" \
             "${DATA_ROOT}/postgres" "${DATA_ROOT}/redis" "${DATA_ROOT}/qdrant" "${DATA_ROOT}/ollama" \
             "${DATA_ROOT}/openwebui" "${DATA_ROOT}/n8n" "${DATA_ROOT}/flowise" "${DATA_ROOT}/litellm" \
             "${DATA_ROOT}/grafana" "${DATA_ROOT}/rclone" "${DATA_ROOT}/authentik/media" \
             "${DATA_ROOT}/authentik/custom-templates" "${DATA_ROOT}/dify-data"
    ok "Directory structure created."
    log "Applying directory ownership..."
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    ok "Base ownership applied."

    # --- Step 6: Generate Configuration Files ---
    write_env_file
    write_caddyfile
    
    # --- Step 7: Create Prometheus & Apply Overrides ---
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

    log "Applying service-specific ownership overrides..."
    [[ "${ENABLE_GRAFANA}" == "true" ]] && chown -R 472:472 "${DATA_ROOT}/grafana"
    [[ "${ENABLE_QDRANT}" == "true" ]] && chown -R 1000:1000 "${DATA_ROOT}/qdrant"
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"
    ok "Service-specific ownership configured."
    
    ok "Setup complete. All configurations generated and secured. Ready for script 2."
}

# Execute the main function
main "$@"
