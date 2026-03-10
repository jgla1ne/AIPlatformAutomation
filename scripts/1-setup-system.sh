#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - STABLE v5.1 (Final Correction)
# =============================================================================
# PURPOSE: A definitive, faithful reconstruction of the UI and logic from 
#          commit 2a0ffd1, including all previously missing features like 
#          proxy/vectorDB selection, port configuration, and model prompts.
# =============================================================================

set -euo pipefail

# --- Script Globals ---
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- SOURCE MISSION CONTROL UTILITIES (Logging & Validation) ---
source "${SCRIPTS_DIR}/3-configure-services.sh"

# --- Source Script 3 for Modular Infrastructure ---
# This provides access to verification functions for Tailscale and Rclone
source "${SCRIPTS_DIR}/3-configure-services.sh"

# --- Default Values ---
# All values are collected interactively. These are for safety and clarity.
TENANT_ID=""; DOMAIN=""; LETSENCRYPT_EMAIL=""; DATA_ROOT=""; TENANT_UID=""; TENANT_GID="";
ENABLE_CADDY=false; ENABLE_TRAEFIK=false; ENABLE_POSTGRES="true"; ENABLE_REDIS="true";
ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false; ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false;
ENABLE_N8N=false; ENABLE_FLOWISE=false; ENABLE_LITELLM=false; ENABLE_QDRANT=false;
ENABLE_MILVUS=false; ENABLE_CHROMA=false; ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false;
ENABLE_AUTHENTIK=false; ENABLE_TAILSCALE=false; ENABLE_RCLONE=false; ENABLE_OPENCLAW=false;
RCLONE_JSON=""; TAILSCALE_AUTH_KEY=""; POSTGRES_USER="platform"; POSTGRES_DB="platform";
LITELLM_ROUTING_STRATEGY="cost-optimized"; GDRIVE_AUTH_METHOD=""; OLLAMA_MODELS="llama3";
POSTGRES_PORT=5432; REDIS_PORT=6379; OLLAMA_PORT=11434; QDRANT_PORT=6333; TAILSCALE_PORT=8443;
TAILSCALE_EXTRA_ARGS="--advertise-routes=10.0.0.0/8,192.168.0.0/16"

# --- UI Helpers (from 2a0ffd1) ---
print_header() { clear; echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"; echo -e "${CYAN}║${NC}${BOLD}        🚀  AI Platform — System Setup Wizard                 ${NC}${CYAN}║${NC}"; echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"; }
print_step() { echo -e "\n${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"; echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${1} of 9 ]${NC}  ${2}"; echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}\n"; }
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
collect_identity() { print_step "1" "Identity & Domain"; read -p "Enter Tenant ID: " TENANT_ID; read -p "Enter Domain: " DOMAIN; read -p "Enter Admin Email (Let's Encrypt): " LETSENCRYPT_EMAIL; DATA_ROOT="/mnt/data/${TENANT_ID}"; TENANT_UID=${SUDO_UID:-$(id -u)}; TENANT_GID=${SUDO_GID:-$(id -g)}; }

# --- Step 2: Reverse Proxy Selection ---
collect_proxy_choice() { print_step "2" "Reverse Proxy Selection"; echo -e "  ${CYAN}1)${NC} Caddy (Recommended), ${CYAN}2)${NC} Traefik, ${CYAN}3)${NC} None"; read -p "Select Reverse Proxy [1]: " p; p=${p:-1}; if [[ "$p" == 1 ]]; then ENABLE_CADDY=true; fi; if [[ "$p" == 2 ]]; then ENABLE_TRAEFIK=true; fi; ok "Proxy selected."; }

# --- Step 3: Stack Selection ---
select_stack() {
    print_step "3" "Service Stack Selection"
    echo -e "  ${CYAN}1)${NC} Min, ${CYAN}2)${NC} Standard, ${CYAN}3)${NC} Full, ${CYAN}4)${NC} Custom"
    read -p "Select stack [2]: " choice; choice=${choice:-2}
    case "$choice" in
        1) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true ;; 
        2) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true ;; 
        3) ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true; ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true; ENABLE_QDRANT=true; ENABLE_ANYTHINGLLM=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true; ENABLE_AUTHENTIK=true; ENABLE_TAILSCALE=true; ENABLE_OPENCLAW=true ;; 
    esac
    read -p "Customise service selection? [y/N]: " customise
    if [[ "${customise,,}" =~ ^y$ || "$choice" == "4" ]]; then
        ask_service "🦙" "Ollama" "Local LLM engine" "ENABLE_OLLAMA"; ask_service "🌐" "Open WebUI" "Chat UI for Ollama" "ENABLE_OPENWEBUI"; 
        ask_service "🔄" "n8n" "Workflow automation" "ENABLE_N8N"; ask_service "🌊" "Flowise" "AI flow builder" "ENABLE_FLOWISE"; 
        ask_service "🔀" "LiteLLM" "LLM proxy" "ENABLE_LITELLM"; ask_service "🤖" "AnythingLLM" "RAG" "ENABLE_ANYTHINGLLM"; 
        ask_service "📈" "Grafana" "Dashboard" "ENABLE_GRAFANA"; ask_service "🔭" "Prometheus" "Metrics" "ENABLE_PROMETHEUS"; 
        ask_service "🔑" "Authentik" "SSO" "ENABLE_AUTHENTIK"; ask_service "🔒" "Tailscale" "VPN" "ENABLE_TAILSCALE";
        ask_service "🐾" "OpenClaw" "Terminal Access" "ENABLE_OPENCLAW"
    fi
}

# --- Step 4: VectorDB Selection ---
collect_vectordb_choice() { if [[ "$ENABLE_ANYTHINGLLM$ENABLE_FLOWISE" != "falsetrue" && "$ENABLE_ANYTHINGLLM$ENABLE_FLOWISE" != "truefalse" && "$ENABLE_ANYTHINGLLM$ENABLE_FLOWISE" != "truetrue" ]]; then return; fi; print_step "4" "Vector Database Selection"; echo -e "  ${CYAN}1)${NC} Qdrant (Recommended), ${CYAN}2)${NC} Milvus, ${CYAN}3)${NC} Chroma, ${CYAN}4)${NC} None"; read -p "Select Vector DB [1]: " v; v=${v:-1}; if [[ "$v" == 1 ]]; then ENABLE_QDRANT=true; fi; if [[ "$v" == 2 ]]; then ENABLE_MILVUS=true; fi; if [[ "$v" == 3 ]]; then ENABLE_CHROMA=true; fi; ok "Vector DB selected."; }

# --- Step 5: Ollama Model Configuration ---
collect_ollama_models() { if [[ "${ENABLE_OLLAMA}" != "true" ]]; then return; fi; print_step "5" "Ollama Model Configuration"; read -p "Enter models to download (space-separated) [llama3]: " OLLAMA_MODELS; OLLAMA_MODELS=${OLLAMA_MODELS:-llama3}; ok "Models set."; }

# --- Step 6: LiteLLM Routing ---
collect_litellm_routing() { if [[ "${ENABLE_LITELLM}" != "true" ]]; then return; fi; print_step "6" "LiteLLM Routing Strategy"; echo -e "  ${CYAN}1)${NC} Cost-Optimized, ${CYAN}2)${NC} Speed, ${CYAN}3)${NC} Balanced, ${CYAN}4)${NC} Capability"; read -p "Select strategy [1]: " c; c=${c:-1}; case "$c" in 2) s="speed-optimized";; 3) s="balanced";; 4) s="capability-optimized";; *) s="cost-optimized";; esac; LITELLM_ROUTING_STRATEGY=$s; ok "Strategy set to ${s}."; }

# --- Step 7: Port Configuration ---
configure_ports() { print_step "7" "Service Port Configuration"; read -p "Customize default ports? [y/N]: " cust; if [[ "${cust,,}" == "y" ]]; then read -p "Postgres Port [5432]: " p; POSTGRES_PORT=${p:-5432}; read -p "Redis Port [6379]: " r; REDIS_PORT=${r:-6379}; if [[ "$ENABLE_OLLAMA" == "true" ]]; then read -p "Ollama Port [11434]: " o; OLLAMA_PORT=${o:-11434}; fi; if [[ "$ENABLE_QDRANT" == "true" ]]; then read -p "Qdrant Port [6333]: " q; QDRANT_PORT=${q:-6333}; fi; if [[ "$ENABLE_TAILSCALE" == "true" ]]; then read -p "Tailscale Port [8443]: " t; TAILSCALE_PORT=${t:-8443}; fi; fi; ok "Ports configured."; }

# --- Step 8: Network, Secrets & Files ---
collect_and_generate() {
    print_step "8" "Network, Secrets & Files"
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        while true; do 
            read -p "Enter Tailscale Auth Key: " TAILSCALE_AUTH_KEY
            # Basic validation (non-empty)
            if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then 
                ok "Tailscale key provided."
                break
            else
                warn "Tailscale key cannot be empty. Please try again."
            fi
        done
        read -p "Tailscale Extra Args [${TAILSCALE_EXTRA_ARGS}]: " args
        TAILSCALE_EXTRA_ARGS=${args:-${TAILSCALE_EXTRA_ARGS}}
    fi
    read -p "Enable Rclone? [y/N]: " rclone; if [[ "${rclone,,}" == "y" ]]; then ENABLE_RCLONE=true; echo "Rclone auth: ${CYAN}1)${NC} OAuth, ${CYAN}2)${NC} Service Account JSON"; read -p "[1]: " m; if [[ "$m" == "2" ]]; then GDRIVE_AUTH_METHOD="service_account"; log "Paste JSON, then CTRL+D."; json_input=""; while IFS= read -r line; do json_input+="$line\n"; done; if validate_json "${json_input}"; then RCLONE_JSON="${json_input}"; ok "Rclone JSON valid."; else fail "Invalid JSON."; fi; else GDRIVE_AUTH_METHOD="oauth"; read -p "Client ID: " GDRIVE_CLIENT_ID; read -p "Client Secret: " GDRIVE_CLIENT_SECRET; fi; fi
    read -p "Postgres User [platform]: " u; POSTGRES_USER=${u:-platform}; read -p "Postgres DB [platform]: " d; POSTGRES_DB=${d:-platform}
    local env="${DATA_ROOT}/.env"
    mkdir -p "${DATA_ROOT}"
    load_secret() { if [ -f "$env" ]; then grep "^$1=" "$env" | cut -d= -f2- || echo ""; else echo ""; fi; }
    POSTGRES_PASSWORD=$(load_secret "POSTGRES_PASSWORD" || openssl rand -base64 32); REDIS_PASSWORD=$(load_secret "REDIS_PASSWORD" || openssl rand -base64 32)
    mkdir -p "${DATA_ROOT}"/{lib/tailscale,run/tailscale,prometheus-data,caddy_data,postgres,redis,qdrant,ollama,openwebui,n8n,flowise,litellm,grafana,rclone,authentik/media,authentik/custom-templates,dify-data}
    if [[ "${GDRIVE_AUTH_METHOD}" == "service_account" ]]; then echo "${RCLONE_JSON}" > "${DATA_ROOT}/rclone/google_sa.json"; fi
    cat > "${env}" << EOF
# AI Platform Config - Generated: $(date -u --iso-8601=seconds)
# Core
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
DATA_ROOT=${DATA_ROOT}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
COMPOSE_PROJECT_NAME=ai-${TENANT_ID}
DOCKER_NETWORK=ai-${TENANT_ID}-net
# Service Enablement
$(compgen -A variable | grep '^ENABLE_' | sed 's/$/=${\0}/')
# Ports
POSTGRES_PORT=${POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
QDRANT_PORT=${QDRANT_PORT}
TAILSCALE_PORT=${TAILSCALE_PORT}
# Config & Secrets
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
LITELLM_ROUTING_STRATEGY=${LITELLM_ROUTING_STRATEGY}
OLLAMA_MODELS=${OLLAMA_MODELS}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_HOSTNAME=ai-platform-${TENANT_ID}
TAILSCALE_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS}
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD:-}
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID:-}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET:-}
EOF
    chmod 600 "${env}"; ok "Master .env file written and secured."
}

# --- Step 9: Finalize ---
finalize_setup() { print_step "9" "Finalize & Deploy"; log "Applying final ownership..."; chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"; if [[ -d "${DATA_ROOT}/grafana" ]]; then chown -R 472:472 "${DATA_ROOT}/grafana"; fi; if [[ -d "${DATA_ROOT}/prometheus-data" ]]; then chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"; fi; ok "Ownership set."; read -p "Deploy services now? [Y/n]: " run_next; if [[ "${run_next:-y}" =~ ^y$ ]]; then log "Executing deployment..."; bash "$(dirname "${BASH_SOURCE[0]}")/2-deploy-services.sh"; else log "Deployment skipped."; fi; }

# --- Main Execution (Definitive Flow) ---
main() { print_header; collect_identity; collect_proxy_choice; select_stack; collect_vectordb_choice; collect_ollama_models; collect_litellm_routing; configure_ports; collect_and_generate; finalize_setup; }

main "$@"
