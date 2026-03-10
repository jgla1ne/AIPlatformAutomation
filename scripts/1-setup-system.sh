#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v4.0
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform, based on UI from 2a0ffd1
#          with modern backend functionality.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES ---
source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"

# --- Default Values (to prevent unbound variable errors) ---
# All service flags are initialized to false. The stack selection will enable them.
ENABLE_POSTGRES="false"
ENABLE_REDIS="false"
ENABLE_CADDY="false"
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
ENABLE_RCLONE="false"

# --- UI Helpers (from commit 2a0ffd1) ---
print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}        🚀  AI Platform — System Setup Wizard                 ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="${1}" total="${2}" title="${3}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${step} of ${total} ]${NC}  ${title}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

ask_service() {
    local emoji="$1" name="$2" desc="$3" var="$4" default="$5"
    local current_val
    eval current_val=\"$`echo ${var}`\"
    [ "${current_val}" = "true" ] && default="y" || default="n"
    local prompt_default
    [ "${default}" = "y" ] && prompt_default="[Y/n]" || prompt_default="[y/N]"

    printf "  %s  %-20s - %-35s" "${emoji}" "${name}" "${desc}"
    read -p " ${prompt_default}: " answer
    answer="${answer:-${default}}"

    if [[ "${answer,,}" == "y" ]]; then
        declare -g "${var}=true"
    else
        declare -g "${var}=false"
    fi
}

# --- Step 1: Identity Collection ---
collect_identity() {
    print_step "1" "5" "Domain & Identity"
    read -p "Enter Tenant ID (e.g., datasquiz): " TENANT_ID
    read -p "Enter Domain (e.g., ai.datasquiz.net): " DOMAIN
    read -p "Enter Let's Encrypt Email: " LETSENCRYPT_EMAIL
    DATA_ROOT="/mnt/data/${TENANT_ID}"

    TENANT_UID=${SUDO_UID:-$(id -u)}
    TENANT_GID=${SUDO_GID:-$(id -g)}
}

# --- Step 2: Stack Selection ---
select_stack() {
    print_step "2" "5" "Service Stack Selection"
    echo -e "  ${CYAN}1)${NC}  ${BOLD}Minimal${NC}       — Ollama + Open WebUI"
    echo -e "  ${CYAN}2)${NC}  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + LiteLLM"
    echo -e "  ${CYAN}3)${NC}  ${BOLD}Full${NC}          — Standard + AnythingLLM + Grafana + Prometheus + Authentik"
    echo -e "  ${CYAN}4)${NC}  ${BOLD}Custom${NC}        — Pick services individually"

    read -p "Select stack [2]: " stack_choice
    stack_choice=${stack_choice:-2}

    case "$stack_choice" in
        1) # Minimal
            ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true ;;
        2) # Standard
            ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true ;;
        3) # Full
            ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true; ENABLE_ANYTHINGLLM=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true; ENABLE_AUTHENTIK=true; ENABLE_TAILSCALE=true ;;
        4) # Custom - handled below
            ;;
    esac

    read -p "Customise service selection? [y/N]: " customise
    if [[ "${customise,,}" =~ ^y$ || "$stack_choice" == "4" ]]; then
        ask_service "🦙" "Ollama" "Local LLM engine" "ENABLE_OLLAMA" "y"
        ask_service "🌐" "Open WebUI" "Chat UI for Ollama" "ENABLE_OPENWEBUI" "y"
        ask_service "🔄" "n8n" "Workflow automation" "ENABLE_N8N" "n"
        ask_service "🌊" "Flowise" "AI flow builder" "ENABLE_FLOWISE" "n"
        ask_service "🔀" "LiteLLM" "LLM proxy gateway" "ENABLE_LITELLM" "n"
        ask_service "🗄️" "Qdrant" "Vector Database" "ENABLE_QDRANT" "n"
        ask_service "🤖" "AnythingLLM"   "AI assistant & RAG"         "ENABLE_ANYTHINGLLM"   "n"
        ask_service "📈" "Grafana"       "Metrics dashboard"           "ENABLE_GRAFANA"       "n"
        ask_service "🔭" "Prometheus"    "Metrics collection"          "ENABLE_PROMETHEUS"    "n"
        ask_service "🔑" "Authentik"     "SSO / identity provider"     "ENABLE_AUTHENTIK"     "n"
        ask_service "🔒" "Tailscale"     "VPN for secure access"       "ENABLE_TAILSCALE"     "n"
    fi
}

# --- Step 3: Network & Security ---
collect_network_config() {
    print_step "3" "5" "Network & Security"
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        while true; do
            read -p "Enter your Tailscale Auth Key: " TAILSCALE_AUTH_KEY
            if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then break; else echo "Tailscale key cannot be empty."; fi
        done
    else
        TAILSCALE_AUTH_KEY=""
    fi

    read -p "Enable Rclone for cloud storage? [y/N]: " enable_rclone
    if [[ "${enable_rclone,,}" =~ ^y$ ]]; then
        ENABLE_RCLONE=true
        echo "Paste your Rclone JSON configuration below, then press CTRL+D on a new line to finish:"
        RCLONE_JSON=$(cat)
        if ! echo "${RCLONE_JSON}" | python3 -m json.tool > /dev/null 2>&1; then
            fail "Invalid JSON provided for Rclone. Setup aborted."
        fi
    else
        ENABLE_RCLONE=false
        RCLONE_JSON=""
    fi
}

# --- Step 4: Generate Files & Directories ---
write_and_create_files() {
    print_step "4" "5" "File Generation"
    log "Creating directory structure in ${DATA_ROOT}..."
    mkdir -p "${DATA_ROOT}/lib/tailscale" "${DATA_ROOT}/prometheus-data" "${DATA_ROOT}/caddy_data" \
             "${DATA_ROOT}/postgres" "${DATA_ROOT}/redis" "${DATA_ROOT}/qdrant" "${DATA_ROOT}/ollama" \
             "${DATA_ROOT}/openwebui" "${DATA_ROOT}/n8n" "${DATA_ROOT}/flowise" "${DATA_ROOT}/litellm" \
             "${DATA_ROOT}/grafana" "${DATA_ROOT}/rclone" "${DATA_ROOT}/authentik/media" \
             "${DATA_ROOT}/authentik/custom-templates" "${DATA_ROOT}/dify-data"
    ok "Directory structure created."

    if [[ "${ENABLE_RCLONE}" == "true" && -n "${RCLONE_JSON}" ]]; then
        log "Writing Rclone configuration..."
        echo "${RCLONE_JSON}" > "${DATA_ROOT}/rclone/rclone.json"
        ok "Rclone configuration saved."
    fi

    log "Generating secrets..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
    N8N_PASSWORD=$(openssl rand -hex 16)
    AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)

    log "Writing configuration to ${DATA_ROOT}/.env ..."
    local final_env_file="${DATA_ROOT}/.env"
    cat > "${final_env_file}" << EOF
# AI Platform Environment Configuration
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
DATA_ROOT=${DATA_ROOT}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
# --- Service Flags ---
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_CADDY=true
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
ENABLE_RCLONE=${ENABLE_RCLONE}
# --- Project Naming ---
COMPOSE_PROJECT_NAME=ai-${TENANT_ID}
DOCKER_NETWORK=ai-${TENANT_ID}-net
# --- Secrets ---
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
N8N_USER=admin@${DOMAIN}
N8N_PASSWORD=${N8N_PASSWORD}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}
EOF
    chmod 600 "${final_env_file}"
    ok "Configuration written and secured: ${final_env_file}"
}

# --- Step 5: Final Ownership & Summary ---
finalize_setup() {
    print_step "5" "5" "Finalizing Setup"
    log "Applying directory ownership..."
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    [[ "${ENABLE_GRAFANA}" == "true" ]] && chown -R 472:472 "${DATA_ROOT}/grafana"
    [[ "${ENABLE_QDRANT}" == "true" ]] && chown -R 1000:1000 "${DATA_ROOT}/qdrant"
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"
    ok "Ownership configured."

    echo ""
    ok "Setup complete! You can now deploy your services."
    echo "Run the next script to deploy:"
    echo "sudo bash scripts/2-deploy-services.sh"
}

# --- Main Execution ---
main() {
    print_header
    collect_identity
    select_stack
    collect_network_config
    write_and_create_files
    finalize_setup
}

main "$@"
