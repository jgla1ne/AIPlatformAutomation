#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v4.2
# =============================================================================
# PURPOSE: A definitive, faithful reconstruction of the UI and prompts from 
#          commit 2a0ffd1, integrated with robust, validated backend logic.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL UTILITIES (Logging & Validation) ---
source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"

# --- Default Values ---
# All values are collected interactively. These are for safety.
TENANT_ID=""; DOMAIN=""; LETSENCRYPT_EMAIL=""; DATA_ROOT=""; TENANT_UID=""; TENANT_GID="";
ENABLE_POSTGRES="true"; ENABLE_REDIS="true"; ENABLE_CADDY="true";
ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false; ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false;
ENABLE_N8N=false; ENABLE_FLOWISE=false; ENABLE_LITELLM=false; ENABLE_QDRANT=false;
ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false; ENABLE_AUTHENTIK=false; ENABLE_TAILSCALE=false;
ENABLE_RCLONE=false; RCLONE_JSON=""; TAILSCALE_AUTH_KEY=""; POSTGRES_USER="platform"; POSTGRES_DB="platform";
LITELLM_ROUTING_STRATEGY="cost-optimized"; GDRIVE_AUTH_METHOD="";

# --- UI Helpers (from 2a0ffd1) ---
print_header() {
    clear; echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}        🚀  AI Platform — System Setup Wizard                 ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}
print_step() { echo -e "\n${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"; echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${1} of 7 ]${NC}  ${2}"; echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}\n"; }
ask_service() {
    local emoji="$1" name="$2" desc="$3" var="$4"
    local current_val; eval current_val=\"\"$`echo ${var}`\"\"
    local default_answer=$([ "${current_val}" == "true" ] && echo "y" || echo "n")
    local prompt_default=$([ "${default_answer}" == "y" ] && echo "[Y/n]" || echo "[y/N]")
    printf "  %s  %-20s - %-35s" "${emoji}" "${name}" "${desc}"
    read -p " ${prompt_default}: " answer; answer="${answer:-${default_answer}}"
    [[ "${answer,,}" == "y" ]] && declare -g "${var}=true" || declare -g "${var}=false"
}

# --- Step 1: Identity Collection ---
collect_identity() {
    print_step "1" "Identity & Domain"
    read -p "Enter Tenant ID (e.g., datasquiz): " TENANT_ID
    read -p "Enter Domain (e.g., ai.datasquiz.net): " DOMAIN
    read -p "Enter Admin Email (for Let's Encrypt): " LETSENCRYPT_EMAIL
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    TENANT_UID=${SUDO_UID:-$(id -u)}; TENANT_GID=${SUDO_GID:-$(id -g)}
}

# --- Step 2: Stack Selection ---
select_stack() {
    print_step "2" "Service Stack Selection"
    echo -e "  ${CYAN}1)${NC} ${BOLD}Minimal${NC}, ${CYAN}2)${NC} ${BOLD}Standard${NC}, ${CYAN}3)${NC} ${BOLD}Full${NC}, ${CYAN}4)${NC} ${BOLD}Custom${NC}"
    read -p "Select stack [2]: " stack_choice; stack_choice=${stack_choice:-2}
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
        ask_service "🔀" "LiteLLM" "LLM proxy" "ENABLE_LITELLM"
        ask_service "🗄️" "Qdrant" "Vector Database" "ENABLE_QDRANT"
        ask_service "🤖" "AnythingLLM" "RAG" "ENABLE_ANYTHINGLLM"
        ask_service "📈" "Grafana" "Dashboard" "ENABLE_GRAFANA"
        ask_service "🔭" "Prometheus" "Metrics" "ENABLE_PROMETHEUS"
        ask_service "🔑" "Authentik" "SSO" "ENABLE_AUTHENTIK"
        ask_service "🔒" "Tailscale" "VPN" "ENABLE_TAILSCALE"
    fi
}

# --- Step 3: LiteLLM Routing (from 2a0ffd1) ---
collect_litellm_routing() {
    if [[ "${ENABLE_LITELLM}" != "true" ]]; then return; fi
    print_step "3" "LiteLLM Routing Strategy"
    echo -e "  ${CYAN}1)${NC} Cost-Optimized, ${CYAN}2)${NC} Speed-Optimized, ${CYAN}3)${NC} Balanced, ${CYAN}4)${NC} Capability-Optimized"
    read -p "Select LiteLLM routing strategy [1]: " choice; choice=${choice:-1}
    case "$choice" in
        2) LITELLM_ROUTING_STRATEGY="speed-optimized" ;; 3) LITELLM_ROUTING_STRATEGY="balanced" ;; 
        4) LITELLM_ROUTING_STRATEGY="capability-optimized" ;; *) LITELLM_ROUTING_STRATEGY="cost-optimized" ;; 
    esac
    ok "LiteLLM routing strategy set to: ${LITELLM_ROUTING_STRATEGY}"
}

# --- Step 4: Network & Security (with robust validation) ---
collect_network_config() {
    print_step "4" "Network & Security"
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        while true; do
            read -p "Enter your Tailscale Auth Key: " TAILSCALE_AUTH_KEY
            if validate_tailscale_key "${TAILSCALE_AUTH_KEY}"; then ok "Tailscale key format is valid."; break; fi
        done
    fi
    read -p "Enable Rclone for cloud storage? [y/N]: " rclone; rclone=${rclone:-n}
    if [[ "${rclone,,}" == "y" ]]; then
        ENABLE_RCLONE=true
        echo "Choose Rclone auth method: ${CYAN}1)${NC} OAuth, ${CYAN}2)${NC} Service Account JSON"; read -p "[1]: " m; m=${m:-1}
        if [[ "$m" == "2" ]]; then
            GDRIVE_AUTH_METHOD="service_account"
            log "Paste Service Account JSON, then press CTRL+D on a new line."
            local json_input=""; while IFS= read -r line; do json_input+="$line\n"; done
            if validate_json "${json_input}"; then RCLONE_JSON="${json_input}"; ok "Rclone JSON is valid."; else fail "Invalid JSON. Aborting."; fi
        else
            GDRIVE_AUTH_METHOD="oauth"; read -p "Google Drive Client ID: " GDRIVE_CLIENT_ID; read -p "Google Drive Client Secret: " GDRIVE_CLIENT_SECRET
        fi
    fi
}

# --- Step 5: Database & Secrets (with persistence) ---
generate_secrets_and_db_config() {
    print_step "5" "Database & Secrets"
    read -p "PostgreSQL User [platform]: " u; POSTGRES_USER=${u:-platform}
    read -p "PostgreSQL DB [platform]: " d; POSTGRES_DB=${d:-platform}
    local env="${DATA_ROOT}/.env"; mkdir -p "${DATA_ROOT}"
    load_secret() { if [ -f "$env" ]; then grep "^$1=" "$env" | cut -d= -f2- || echo ""; else echo ""; fi; }
    POSTGRES_PASSWORD=$(load_secret "POSTGRES_PASSWORD" || openssl rand -base64 32)
    REDIS_PASSWORD=$(load_secret "REDIS_PASSWORD" || openssl rand -base64 32)
    ok "Database credentials and secrets are ready."
}

# --- Step 6: File Generation & Summary ---
write_files_and_summarize() {
    print_step "6" "File Generation & Summary"
    log "Creating directories and writing configurations..."
    mkdir -p "${DATA_ROOT}"/{lib/tailscale,prometheus-data,caddy_data,postgres,redis,qdrant,ollama,openwebui,n8n,flowise,litellm,grafana,rclone,authentik/media,authentik/custom-templates,dify-data}
    if [[ "${GDRIVE_AUTH_METHOD}" == "service_account" ]]; then echo "${RCLONE_JSON}" > "${DATA_ROOT}/rclone/google_sa.json"; fi
    local env="${DATA_ROOT}/.env"
    cat > "${env}" << EOF
# AI Platform Config - Generated: $(date -u --iso-8601=seconds)
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
DATA_ROOT=${DATA_ROOT}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
# Services
$(compgen -A variable | grep '^ENABLE_' | sed 's/$/=${\0}/')
# Project
COMPOSE_PROJECT_NAME=ai-${TENANT_ID}
DOCKER_NETWORK=ai-${TENANT_ID}-net
# Secrets
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
LITELLM_ROUTING_STRATEGY=${LITELLM_ROUTING_STRATEGY}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD:-}
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID:-}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET:-}
EOF
    chmod 600 "${env}"
    ok "Master .env file written to ${env}"
    
    echo -e "\n  ${BOLD}Configuration Summary:${NC}"
    printf "    ${CYAN}%-20s${NC} %s\n" "Tenant ID:" "${TENANT_ID}"
    printf "    ${CYAN}%-20s${NC} %s\n" "Domain:" "${DOMAIN}"
    printf "    ${CYAN}%-20s${NC} %s\n" "LiteLLM Routing:" "${LITELLM_ROUTING_STRATEGY}"
    echo -e "  ${BOLD}Enabled Services:${NC}"
    compgen -A variable | grep '^ENABLE_.*=true' | sed 's/ENABLE_//;s/=true//;s/^/    - /'
}

# --- Step 7: Finalize ---
finalize_setup() {
    print_step "7" "Finalize & Deploy"
    log "Applying final ownership rules..."
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    if [[ -d "${DATA_ROOT}/grafana" ]]; then chown -R 472:472 "${DATA_ROOT}/grafana"; fi
    if [[ -d "${DATA_ROOT}/prometheus-data" ]]; then chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"; fi
    ok "Ownership configured."
    read -p "Run script 2 (deploy services) now? [Y/n]: " run_next; run_next=${run_next:-y}
    if [[ "${run_next,,}" =~ ^y$ ]]; then
        log "Executing deployment script..."
        bash "$(dirname "${BASH_SOURCE[0]}")/2-deploy-services.sh"
    else
        log "Deployment skipped. Run script 2 when ready."
    fi
}

# --- Main Execution (Flow from 2a0ffd1) ---
main() {
    print_header
    collect_identity
    select_stack
    collect_litellm_routing
    collect_network_config
    generate_secrets_and_db_config
    write_files_and_summarize
    finalize_setup
}

main "$@"
