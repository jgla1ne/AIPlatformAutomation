#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v4.1
# =============================================================================
# PURPOSE: A faithful recreation of the UI and prompts from commit 2a0ffd1,
#          integrated with modern, robust backend functionality.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES ---
source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"

# --- Default Values (to prevent unbound variable errors) ---
# These are placeholders. The script will collect all values interactively.
TENANT_ID=""; DOMAIN=""; LETSENCRYPT_EMAIL=""; DATA_ROOT=""; TENANT_UID=""; TENANT_GID="";
ENABLE_POSTGRES="true"; ENABLE_REDIS="true"; ENABLE_CADDY="true";
ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false; ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false;
ENABLE_N8N=false; ENABLE_FLOWISE=false; ENABLE_LITELLM=false; ENABLE_QDRANT=false;
ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false; ENABLE_AUTHENTIK=false; ENABLE_TAILSCALE=false;
ENABLE_RCLONE=false; RCLONE_JSON=""; TAILSCALE_AUTH_KEY="";
POSTGRES_PASSWORD=""; REDIS_PASSWORD=""; LITELLM_MASTER_KEY=""; GRAFANA_ADMIN_PASSWORD="";
N8N_PASSWORD=""; AUTHENTIK_SECRET_KEY=""; POSTGRES_USER="platform"; POSTGRES_DB="platform";

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
    local emoji="$1" name="$2" desc="$3" var="$4"
    local current_val; eval current_val=\"\"$`echo ${var}`\"\"
    local default_answer=$([ "${current_val}" == "true" ] && echo "y" || echo "n")
    local prompt_default=$([ "${default_answer}" == "y" ] && echo "[Y/n]" || echo "[y/N]")

    printf "  %s  %-20s - %-35s" "${emoji}" "${name}" "${desc}"
    read -p " ${prompt_default}: " answer
    answer="${answer:-${default_answer}}"

    if [[ "${answer,,}" == "y" ]]; then
        declare -g "${var}=true"
    else
        declare -g "${var}=false"
    fi
}

# --- Step 1: Identity Collection (from 2a0ffd1) ---
collect_identity() {
    print_step "1" "6" "Domain & Identity"
    read -p "Enter Tenant ID (e.g., datasquiz): " TENANT_ID
    read -p "Enter Domain (e.g., ai.datasquiz.net): " DOMAIN
    read -p "Enter Admin Email (for Let's Encrypt): " LETSENCRYPT_EMAIL
    DATA_ROOT="/mnt/data/${TENANT_ID}"

    TENANT_UID=${SUDO_UID:-$(id -u)}
    TENANT_GID=${SUDO_GID:-$(id -g)}
}

# --- Step 2: Stack Selection (from 2a0ffd1) ---
select_stack() {
    print_step "2" "6" "Service Stack Selection"
    echo -e "  ${CYAN}1)${NC}  ${BOLD}Minimal${NC}       — Ollama + Open WebUI"
    echo -e "  ${CYAN}2)${NC}  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + LiteLLM"
    echo -e "  ${CYAN}3)${NC}  ${BOLD}Full${NC}          — Standard + AnythingLLM + Grafana + Prometheus + Authentik + Tailscale"
    echo -e "  ${CYAN}4)${NC}  ${BOLD}Custom${NC}        — Pick services individually"

    read -p "Select stack [2]: " stack_choice
    stack_choice=${stack_choice:-2}

    # Apply presets based on stack choice
    case "$stack_choice" in
        1) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true ;; 
        2) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true ;; 
        3) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true; ENABLE_ANYTHINGLLM=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true; ENABLE_AUTHENTIK=true; ENABLE_TAILSCALE=true ;; 
    esac

    read -p "Customise service selection? [y/N]: " customise
    if [[ "${customise,,}" =~ ^y$ || "$stack_choice" == "4" ]]; then
        ask_service "🦙" "Ollama" "Local LLM engine" "ENABLE_OLLAMA"
        ask_service "🌐" "Open WebUI" "Chat UI for Ollama" "ENABLE_OPENWEBUI"
        ask_service "🔄" "n8n" "Workflow automation" "ENABLE_N8N"
        ask_service "🌊" "Flowise" "AI flow builder" "ENABLE_FLOWISE"
        ask_service "🔀" "LiteLLM" "LLM proxy gateway" "ENABLE_LITELLM"
        ask_service "🗄️" "Qdrant" "Vector Database" "ENABLE_QDRANT"
        ask_service "🤖" "AnythingLLM" "AI assistant & RAG" "ENABLE_ANYTHINGLLM"
        ask_service "📈" "Grafana" "Metrics dashboard" "ENABLE_GRAFANA"
        ask_service "🔭" "Prometheus" "Metrics collection" "ENABLE_PROMETHEUS"
        ask_service "🔑" "Authentik" "SSO / identity provider" "ENABLE_AUTHENTIK"
        ask_service "🔒" "Tailscale" "VPN for secure access" "ENABLE_TAILSCALE"
    fi
}

# --- Step 3: Database Configuration (from 2a0ffd1) ---
collect_database_config() {
    print_step "3" "6" "Database Configuration"
    read -p "Enter PostgreSQL Username [platform]: " POSTGRES_USER_INPUT
    POSTGRES_USER=${POSTGRES_USER_INPUT:-platform}
    read -p "Enter PostgreSQL Database Name [platform]: " POSTGRES_DB_INPUT
    POSTGRES_DB=${POSTGRES_DB_INPUT:-platform}
    log "Postgres will be configured for user '${POSTGRES_USER}' on database '${POSTGRES_DB}'."
}

# --- Step 4: Network & Security (from 2a0ffd1 with robust logic) ---
collect_network_config() {
    print_step "4" "6" "Network & Security"
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        while true; do
            read -p "Enter your Tailscale Auth Key: " TAILSCALE_AUTH_KEY
            if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then break; else echo "Tailscale key cannot be empty when Tailscale is enabled."; fi
        done
    fi

    read -p "Enable Rclone for cloud storage? [y/N]: " enable_rclone
    if [[ "${enable_rclone,,}" =~ ^y$ ]]; then
        ENABLE_RCLONE=true
        echo "Choose Rclone authentication method:"
        echo "  1) OAuth Client Credentials (Interactive setup required later)"
        echo "  2) Service Account JSON (Paste JSON now)"
        read -p "Select method [1]: " auth_method
        auth_method=${auth_method:-1}

        if [[ "$auth_method" == "2" ]]; then
            GDRIVE_AUTH_METHOD="service_account"
            log "Paste the complete Service Account JSON below."
            log "Press CTRL+D on a new empty line when you are finished."
            RCLONE_JSON=$(cat)
            if ! echo "${RCLONE_JSON}" | python3 -m json.tool > /dev/null 2>&1; then
                fail "Invalid JSON provided for Rclone. Setup cannot continue."
            fi
            ok "Rclone Service Account JSON captured."
        else
            GDRIVE_AUTH_METHOD="oauth"
            read -p "Enter Google Drive Client ID (optional): " GDRIVE_CLIENT_ID
            read -p "Enter Google Drive Client Secret (optional): " GDRIVE_CLIENT_SECRET
            ok "Rclone will be configured for OAuth."
        fi
    fi
}

# --- Step 5: Secrets & File Generation (with persistence) ---
generate_files() {
    print_step "5" "6" "Generating Secrets & Files"
    
    local env_file_path="${DATA_ROOT}/.env"
    load_existing_secret() {
        local key="${1}" default="${2}"
        if [ -f "${env_file_path}" ]; then
            local val=$(grep "^${key}=" "${env_file_path}" 2>/dev/null | cut -d= -f2- || echo "")
            [ -n "${val}" ] && echo "${val}" && return
        fi
        echo "${default}"
    }

    log "Generating secrets (will preserve existing secrets on re-run)..."
    POSTGRES_PASSWORD=$(load_existing_secret "POSTGRES_PASSWORD" "$(openssl rand -base64 32)")
    REDIS_PASSWORD=$(load_existing_secret "REDIS_PASSWORD" "$(openssl rand -base64 32)")
    LITELLM_MASTER_KEY=$(load_existing_secret "LITELLM_MASTER_KEY" "$(openssl rand -hex 32)")
    GRAFANA_ADMIN_PASSWORD=$(load_existing_secret "GRAFANA_ADMIN_PASSWORD" "$(openssl rand -hex 16)")
    N8N_PASSWORD=$(load_existing_secret "N8N_PASSWORD" "$(openssl rand -hex 16)")
    AUTHENTIK_SECRET_KEY=$(load_existing_secret "AUTHENTIK_SECRET_KEY" "$(openssl rand -hex 32)")
    ok "Secrets generated and ready."

    log "Creating directory structure in ${DATA_ROOT}..."
    mkdir -p "${DATA_ROOT}/lib/tailscale" "${DATA_ROOT}/prometheus-data" "${DATA_ROOT}/caddy_data" \
             "${DATA_ROOT}/postgres" "${DATA_ROOT}/redis" "${DATA_ROOT}/qdrant" "${DATA_ROOT}/ollama" \
             "${DATA_ROOT}/openwebui" "${DATA_ROOT}/n8n" "${DATA_ROOT}/flowise" "${DATA_ROOT}/litellm" \
             "${DATA_ROOT}/grafana" "${DATA_ROOT}/rclone" "${DATA_ROOT}/authentik/media" \
             "${DATA_ROOT}/authentik/custom-templates" "${DATA_ROOT}/dify-data"
    ok "Directory structure created."

    if [[ "${ENABLE_RCLONE}" == "true" && "${GDRIVE_AUTH_METHOD}" == "service_account" && -n "${RCLONE_JSON}" ]]; then
        log "Writing Rclone Service Account JSON..."
        echo "${RCLONE_JSON}" > "${DATA_ROOT}/rclone/google_sa.json"
        ok "Rclone configuration saved."
    fi

    log "Writing master .env file..."
    cat > "${env_file_path}" << EOF
# AI Platform Environment Configuration - Generated: $(date -u --iso-8601=seconds)
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
# --- Secrets & Credentials ---
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
N8N_USER=admin@${DOMAIN}
N8N_PASSWORD=${N8N_PASSWORD}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD:-}
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID:-}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET:-}
EOF
    chmod 600 "${env_file_path}"
    ok "Master .env file written and secured."
}

# --- Step 6: Final Ownership & Summary ---
finalize_setup() {
    print_step "6" "6" "Finalizing Setup"
    log "Applying directory ownership rules..."
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    if [[ -d "${DATA_ROOT}/grafana" && "${ENABLE_GRAFANA}" == "true" ]]; then chown -R 472:472 "${DATA_ROOT}/grafana"; fi
    if [[ -d "${DATA_ROOT}/qdrant" && "${ENABLE_QDRANT}" == "true" ]]; then chown -R 1000:1000 "${DATA_ROOT}/qdrant"; fi
    if [[ -d "${DATA_ROOT}/prometheus-data" && "${ENABLE_PROMETHEUS}" == "true" ]]; then chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"; fi
    ok "Ownership configured based on service requirements."

    echo ""
    ok "Setup is complete!"
    echo "You can now deploy your services by running the next script:"
    echo -e "  ${BOLD}sudo bash scripts/2-deploy-services.sh${NC}"
    echo ""
    read -p "Run script 2 (deploy services) now? [Y/n]: " run_next
    run_next=${run_next:-y}
    if [[ "${run_next,,}" =~ ^y$ ]]; then
        log "Executing script 2..."
        bash "$(dirname "${BASH_SOURCE[0]}")/2-deploy-services.sh"
    else
        log "Deployment skipped. Run script 2 when you are ready."
    fi
}

# --- Main Execution (conforms to 2a0ffd1 flow) ---
main() {
    print_header
    collect_identity
    select_stack
    collect_database_config
    collect_network_config
    generate_files
    finalize_setup
}

main "$@"
