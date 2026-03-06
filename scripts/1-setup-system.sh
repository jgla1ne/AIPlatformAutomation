#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - FINAL CORRECTED VERSION
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# --- Colors ---
BOLD=\'\\033[1m\'
DIM=\'\\033[2m\'
RED=\'\\033[0;31m\'
GREEN=\'\\033[0;32m\'
YELLOW=\'\\033[1;33m\'
CYAN=\'\\033[0;36m\'
NC=\'\\033[0m\'

# --- Runtime ---
DATA_ROOT=""
ENV_FILE=""
COMPOSE_DIR=""
CADDY_DIR=""
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANT_USER="${SUDO_USER:-$(whoami)}"

# --- Logging ---
log() {
    local level="$1" message="$2"
    case "$level" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

# --- UI Helpers ---
print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}        🚀  AI Platform — System Setup Wizard                 ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\\n"
}

print_step() {
    local step="$1" total="$2" title="$3"
    echo -e "\\n${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${step} of ${total} ]${NC}  ${title}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}\\n"
}

# --- Prereqs ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root (use sudo)."
        exit 1
    fi
}

# --- Main functions ---
collect_identity() {
    print_step "1" "7" "Domain & Identity"

    read -p "  ➤ Domain name (e.g., ai.example.com): " DOMAIN
    DOMAIN="${DOMAIN,,}"

    read -p "  ➤ Tenant ID (e.g., my-org): " TENANT_ID
    TENANT_ID="${TENANT_ID,,}"
    export COMPOSE_PROJECT_NAME="ai-${TENANT_ID}"
    export DOCKER_NETWORK="ai-${TENANT_ID}-net"

    read -p "  ➤ Admin email address: " ADMIN_EMAIL
}

select_data_volume() {
    print_step "2" "7" "Data Volume & Paths"
    DATA_ROOT="/mnt/data/${TENANT_ID}"
    ENV_FILE="${DATA_ROOT}/.env"
    CADDY_DIR="${DATA_ROOT}/caddy"
    log "SUCCESS" "Data root set to: ${DATA_ROOT}"

    export TENANT_UID=$(id -u "${TENANT_USER}")
    export TENANT_GID=$(id -g "${TENANT_USER}")
    log "INFO" "Tenant ownership set to ${TENANT_USER} (${TENANT_UID}:${TENANT_GID})"
}

select_stack() {
    print_step "3" "7" "Service Stack Selection"
    echo -e "  ${CYAN}1)${NC} ${BOLD}Minimal${NC}     — Ollama, Open WebUI"
    echo -e "  ${CYAN}2)${NC} ${BOLD}Standard${NC}    — Minimal + n8n, Flowise, Qdrant, LiteLLM"
    echo -e "  ${CYAN}3)${NC} ${BOLD}Full${NC}        — Standard + AnythingLLM, Grafana, Prometheus, Authentik\\n"
    read -p "  ➤ Select stack [2]: " stack_choice
    stack_choice="${stack_choice:-2}"

    ENABLE_POSTGRES=false; ENABLE_REDIS=false; ENABLE_CADDY=true; ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false; ENABLE_ANYTHINGLLM=false; ENABLE_N8N=false; ENABLE_FLOWISE=false; ENABLE_LITELLM=false; ENABLE_QDRANT=false; ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false; ENABLE_AUTHENTIK=false

    case "$stack_choice" in
        1) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true ;; 
        2) ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true ;;            
        3) ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true; ENABLE_ANYTHINGLLM=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true; ENABLE_AUTHENTIK=true ;; 
    esac
    log "SUCCESS" "Stack selected."
}

determine_gpu() {
    print_step "4" "7" "Hardware Detection"
    if command -v nvidia-smi &>/dev/null; then export GPU_TYPE="nvidia"; log "SUCCESS" "NVIDIA GPU detected."; else export GPU_TYPE="cpu"; log "INFO" "No NVIDIA GPU detected. Using CPU mode."; fi
}

collect_llm_config() {
    print_step "5" "7" "LLM Configuration"
    read -p "  ➤ Default Ollama model to pull [llama3]: " OLLAMA_DEFAULT_MODEL
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3}"
}

generate_secrets() {
    print_step "6" "7" "Generating Secrets"
    load_or_gen_secret() { [ -f "$ENV_FILE" ] && grep -q "^$1=" "$ENV_FILE" && grep "^$1=" "$ENV_FILE" | cut -d= -f2- || openssl rand -hex 16; }
    POSTGRES_PASSWORD=$(load_or_gen_secret "POSTGRES_PASSWORD")
    REDIS_PASSWORD=$(load_or_gen_secret "REDIS_PASSWORD")
    N8N_ENCRYPTION_KEY=$(load_or_gen_secret "N8N_ENCRYPTION_KEY")
    FLOWISE_PASSWORD=$(load_or_gen_secret "FLOWISE_PASSWORD")
    LITELLM_MASTER_KEY=$(load_or_gen_secret "LITELLM_MASTER_KEY")
    ANYTHINGLLM_API_KEY=$(load_or_gen_secret "ANYTHINGLLM_API_KEY")
    QDRANT_API_KEY=$(load_or_gen_secret "QDRANT_API_KEY")
    GRAFANA_PASSWORD=$(load_or_gen_secret "GRAFANA_PASSWORD")
    AUTHENTIK_SECRET_KEY=$(load_or_gen_secret "AUTHENTIK_SECRET_KEY")
    AUTHENTIK_BOOTSTRAP_PASSWORD=$(load_or_gen_secret "AUTHENTIK_BOOTSTRAP_PASSWORD")
    log "SUCCESS" "Secrets generated/loaded."
}

finalize_and_write() {
    print_step "7" "7" "Finalizing Configuration"
    mkdir -p "${DATA_ROOT}" "${CADDY_DIR}/config" "${CADDY_DIR}/data"
    chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
    log "INFO" "Created and secured data directories."

    local CADDYFILE_PATH="${CADDY_DIR}/config/Caddyfile"
    cat > "${CADDYFILE_PATH}" << EOF
# AI Platform Caddyfile
{
    email ${ADMIN_EMAIL}
}
# --- Application Routing --- #
$([ "${ENABLE_OPENWEBUI}" = "true" ] && echo "chat.${DOMAIN} { reverse_proxy openwebui:8080 }")
$([ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo "docs.${DOMAIN} { reverse_proxy anythingllm:3001 }")
$([ "${ENABLE_N8N}" = "true" ] && echo "n8n.${DOMAIN} { reverse_proxy n8n:5678 }")
$([ "${ENABLE_FLOWISE}" = "true" ] && echo "flowise.${DOMAIN} { reverse_proxy flowise:3000 }")
$([ "${ENABLE_LITELLM}" = "true" ] && echo "litellm.${DOMAIN} { reverse_proxy litellm:4000 }")
$([ "${ENABLE_GRAFANA}" = "true" ] && echo "grafana.${DOMAIN} { reverse_proxy grafana:3000 }")
$([ "${ENABLE_AUTHENTIK}" = "true" ] && echo "auth.${DOMAIN} { reverse_proxy authentik:9000 }")
EOF
    chmod 644 "${CADDYFILE_PATH}"
    log "SUCCESS" "Caddyfile generated correctly."

    # --- Write .env file (FIXED: No backslashes on secrets) ---
    cat > "${ENV_FILE}" << EOF
# AI Platform Environment
# Generated: $(date)

# --- Identity ---
TENANT_ID=${TENANT_ID}
TENANT_USER=${TENANT_USER}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}

# --- Project ---
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
DOCKER_NETWORK=${DOCKER_NETWORK}
DATA_ROOT=${DATA_ROOT}

# --- Hardware ---
GPU_TYPE=${GPU_TYPE}

# --- Services ---
ENABLE_POSTGRES=${ENABLE_POSTGRES}
ENABLE_REDIS=${ENABLE_REDIS}
ENABLE_CADDY=${ENABLE_CADDY}
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK}

# --- Config & Secrets ---
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL}
POSTGRES_USER=postgres
POSTGRES_DB=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
VECTOR_DB=qdrant
QDRANT_API_KEY=${QDRANT_API_KEY}
OLLAMA_INTERNAL_URL=http://ollama:11434
QDRANT_INTERNAL_URL=http://qdrant:6333
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER=${ADMIN_EMAIL}
FLOWISE_USERNAME=${ADMIN_EMAIL}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
ANYTHINGLLM_API_KEY=${ANYTHINGLLM_API_KEY}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_BOOTSTRAP_PASSWORD=${AUTHENTIK_BOOTSTRAP_PASSWORD}
EOF
    chmod 600 "${ENV_FILE}"
    chown "${TENANT_UID}:${TENANT_GID}" "${ENV_FILE}"
    log "SUCCESS" ".env file written."
    
    echo -e "\\n${BOLD}Configuration complete. Ready to deploy.${NC}"
    read -p "  ➤ Run script 2 (deploy services) now? [Y/n]: " run_next
    if [[ "${run_next:-y}" =~ ^[Yy]$ ]]; then
        sudo bash "${SCRIPTS_DIR}/2-deploy-services.sh"
    else
        log "INFO" "Run script 2 when ready: sudo bash ${SCRIPTS_DIR}/2-deploy-services.sh"
    fi
}

# --- Main Execution Flow ---
main() {
    print_header
    check_root
    collect_identity
    select_data_volume
    select_stack
    determine_gpu
    collect_llm_config
    generate_secrets
    finalize_and_write
}

main "$@"
