#!/usr/bin/env bash
# =============================================================================
# Script 1: System Compiler — README v5.1.0 COMPLIANT
# =============================================================================
# PURPOSE: Collect input, write platform.conf, create directory skeleton, install packages
# USAGE:   bash scripts/1-setup-system.sh [tenant_id]
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE=""
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# SYSTEM DETECTION FUNCTIONS
# =============================================================================
detect_system() {
    log "Detecting system configuration..."
    
    # Platform architecture
    PLATFORM_ARCH=$(uname -m)
    log "  Architecture: ${PLATFORM_ARCH}"
    
    # User detection
    PLATFORM_USER=$(whoami)
    PUID=$(id -u)
    PGID=$(id -g)
    log "  User: ${PLATFORM_USER} (${PUID}:${PGID})"
    
    # GPU detection
    GPU_TYPE="cpu"
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        GPU_TYPE="nvidia"
        log "  GPU: NVIDIA detected"
    elif command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        GPU_TYPE="rocm"
        log "  GPU: AMD ROCm detected"
    else
        log "  GPU: CPU only"
    fi
    
    # Memory detection
    TOTAL_RAM_GB=$(free -g | awk 'NR==2{print $2}')
    log "  RAM: ${TOTAL_RAM_GB}GB"
    
    # Disk space detection
    if [[ -d "/mnt" ]]; then
        MNT_DISK_GB=$(df /mnt | awk 'NR==2{print int($4/1024/1024)}')
        log "  /mnt free: ${MNT_DISK_GB}GB"
    fi
}

# =============================================================================
# PORT CONFLICT RESOLUTION (README §6 - write-back pattern)
# =============================================================================
resolve_port() {
    local var_name="$1"
    local proposed="${!var_name}"
    
    log "  Checking port ${proposed} for ${var_name}..."
    while lsof -i ":${proposed}" &>/dev/null 2>&1; do
        proposed=$(( proposed + 1 ))
        log "  Port ${proposed} in use, trying ${proposed}..."
    done
    
    # Write back the resolved value
    printf -v "${var_name}" '%s' "${proposed}"
    log "  Resolved ${var_name} to ${proposed}"
}

resolve_all_ports() {
    log "Resolving port conflicts..."
    
    # Only resolve ports for services that will be enabled
    [[ "${POSTGRES_ENABLED}" == "true" ]] && resolve_port POSTGRES_PORT
    [[ "${REDIS_ENABLED}" == "true" ]] && resolve_port REDIS_PORT
    [[ "${LITELLM_ENABLED}" == "true" ]] && resolve_port LITELLM_PORT
    [[ "${OLLAMA_ENABLED}" == "true" ]] && resolve_port OLLAMA_PORT
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && resolve_port OPENWEBUI_PORT
    [[ "${LIBRECHAT_ENABLED}" == "true" ]] && resolve_port LIBRECHAT_PORT
    [[ "${OPENCLAW_ENABLED}" == "true" ]] && resolve_port OPENCLAW_PORT
    [[ "${QDRANT_ENABLED}" == "true" ]] && resolve_port QDRANT_PORT
    [[ "${N8N_ENABLED}" == "true" ]] && resolve_port N8N_PORT
    [[ "${FLOWISE_ENABLED}" == "true" ]] && resolve_port FLOWISE_PORT
    [[ "${DIFY_ENABLED}" == "true" ]] && resolve_port DIFY_PORT
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && resolve_port AUTHENTIK_PORT
    [[ "${SIGNALBOT_ENABLED}" == "true" ]] && resolve_port SIGNALBOT_PORT
    [[ "${BIFROST_ENABLED}" == "true" ]] && resolve_port BIFROST_PORT
    [[ "${CADDY_ENABLED}" == "true" ]] && resolve_port CADDY_HTTP_PORT
    
    ok "Port conflicts resolved"
}

# =============================================================================
# PRESET IMPLEMENTATION (README §8 - mandatory pattern)
# =============================================================================
service_enabled_by_preset() {
    local service="$1"
    case "${STACK_PRESET}" in
        minimal)  case "${service}" in
                    postgres|redis|litellm|ollama|openwebui|qdrant|caddy)
                        return 0 ;; *) return 1 ;; esac ;;
        standard) case "${service}" in
                    postgres|redis|litellm|ollama|openwebui|qdrant|caddy|\
                    librechat|openclaw|n8n|flowise)
                        return 0 ;; *) return 1 ;; esac ;;
        full)     return 0 ;;
        custom)   return 1 ;;
    esac
}

# =============================================================================
# INTERACTIVE PROMPT FUNCTIONS
# =============================================================================
prompt_default() {
    local prompt="$1"
    local default="$2"
    local response
    
    # Check if stdin is available for interactive input
    if [[ ! -t 0 ]]; then
        echo "  WARNING: Non-interactive environment detected"
        echo "  Using default value for '${prompt}': ${default:-<empty>}"
        echo "${default}"
        return
    fi
    
    # Show prompt and read input
    echo -n "  ${prompt} [${default}]: "
    if read -r response; then
        echo "${response:-$default}"
    else
        echo "  ERROR: Failed to read input, using default"
        echo "${default}"
    fi
}

prompt_yesno() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        echo -n "  ${prompt} [y/N]: "
        read -r response
        response=$(echo "${response}" | tr '[:upper:]' '[:lower:]')
        case "${response}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "    Please enter y or n" ;;
        esac
    done
}

prompt_secret() {
    local prompt="$1"
    local response
    
    while true; do
        echo -n "  ${prompt}: "
        read -rs response
        echo
        [[ -n "$response" ]] && break
        echo "    Secret cannot be empty"
    done
    echo "$response"
}

# =============================================================================
# CONFIGURATION COLLECTION
# =============================================================================
collect_tenant_config() {
    log "Collecting tenant configuration..."
    
    TENANT_ID=$(prompt_default "Tenant identifier" "")
    if [[ -z "$TENANT_ID" ]]; then
        fail "Tenant ID is required"
    fi
    
    BASE_DOMAIN=$(prompt_default "Base domain (example.com or local)" "local")
    
    # Detect EBS mount
    if [[ -d "/mnt" ]]; then
        BASE_DIR="/mnt/${TENANT_ID}"
        log "  Using EBS mount: ${BASE_DIR}"
    else
        BASE_DIR="${HOME}/ai-platform/${TENANT_ID}"
        log "  Using fallback directory: ${BASE_DIR}"
    fi
}

collect_preset() {
    log "Collecting stack preset..."
    
    echo "  Available presets:"
    echo "    minimal  - Core LLM platform (postgres, redis, litellm, ollama, openwebui, qdrant, caddy)"
    echo "    standard - Full automation (minimal + librechat, openclaw, n8n, flowise)"
    echo "    full     - Everything (standard + dify, authentik, signalbot, bifrost)"
    echo "    custom   - Choose services individually"
    
    local preset
    while true; do
        preset=$(prompt_default "Select preset" "minimal")
        # Clean up input - remove whitespace and convert to lowercase
        preset=$(echo "${preset}" | xargs | tr '[:upper:]' '[:lower:]')
        case "${preset}" in
            minimal|standard|full|custom) break ;;
            *) echo "    Invalid preset. Choose: minimal, standard, full, or custom" ;;
        esac
    done
    
    STACK_PRESET="${preset}"
    log "  Selected preset: ${STACK_PRESET}"
}

collect_service_flags() {
    log "Configuring services..."
    
    # Set defaults based on preset
    if [[ "${STACK_PRESET}" != "custom" ]]; then
        if service_enabled_by_preset "postgres"; then
            POSTGRES_ENABLED="true"
        else
            POSTGRES_ENABLED="false"
        fi
        
        if service_enabled_by_preset "redis"; then
            REDIS_ENABLED="true"
        else
            REDIS_ENABLED="false"
        fi
        
        if service_enabled_by_preset "litellm"; then
            LITELLM_ENABLED="true"
        else
            LITELLM_ENABLED="false"
        fi
        
        if service_enabled_by_preset "ollama"; then
            OLLAMA_ENABLED="true"
        else
            OLLAMA_ENABLED="false"
        fi
        
        if service_enabled_by_preset "openwebui"; then
            OPENWEBUI_ENABLED="true"
        else
            OPENWEBUI_ENABLED="false"
        fi
        
        if service_enabled_by_preset "qdrant"; then
            QDRANT_ENABLED="true"
        else
            QDRANT_ENABLED="false"
        fi
        
        if service_enabled_by_preset "caddy"; then
            CADDY_ENABLED="true"
        else
            CADDY_ENABLED="false"
        fi
        
        if service_enabled_by_preset "librechat"; then
            LIBRECHAT_ENABLED="true"
        else
            LIBRECHAT_ENABLED="false"
        fi
        
        if service_enabled_by_preset "openclaw"; then
            OPENCLAW_ENABLED="true"
        else
            OPENCLAW_ENABLED="false"
        fi
        
        if service_enabled_by_preset "n8n"; then
            N8N_ENABLED="true"
        else
            N8N_ENABLED="false"
        fi
        
        if service_enabled_by_preset "flowise"; then
            FLOWISE_ENABLED="true"
        else
            FLOWISE_ENABLED="false"
        fi
        
        if service_enabled_by_preset "dify"; then
            DIFY_ENABLED="true"
        else
            DIFY_ENABLED="false"
        fi
        
        if service_enabled_by_preset "authentik"; then
            AUTHENTIK_ENABLED="true"
        else
            AUTHENTIK_ENABLED="false"
        fi
        
        if service_enabled_by_preset "signalbot"; then
            SIGNALBOT_ENABLED="true"
        else
            SIGNALBOT_ENABLED="false"
        fi
        
        if service_enabled_by_preset "bifrost"; then
            BIFROST_ENABLED="true"
        else
            BIFROST_ENABLED="false"
        fi
        
        log "  Services configured by preset"
        return
    fi
    
    # Custom mode - prompt for each service
    echo "  Configure individual services:"
    if prompt_yesno "Enable PostgreSQL" "y"; then
        POSTGRES_ENABLED="true"
    else
        POSTGRES_ENABLED="false"
    fi
    
    if prompt_yesno "Enable Redis" "y"; then
        REDIS_ENABLED="true"
    else
        REDIS_ENABLED="false"
    fi
    
    if prompt_yesno "Enable LiteLLM" "y"; then
        LITELLM_ENABLED="true"
    else
        LITELLM_ENABLED="false"
    fi
    
    if prompt_yesno "Enable Ollama" "y"; then
        OLLAMA_ENABLED="true"
    else
        OLLAMA_ENABLED="false"
    fi
    if prompt_yesno "Enable Open WebUI" "y"; then
        OPENWEBUI_ENABLED="true"
    else
        OPENWEBUI_ENABLED="false"
    fi
    if prompt_yesno "Enable Qdrant" "y"; then
        QDRANT_ENABLED="true"
    else
        QDRANT_ENABLED="false"
    fi
    if prompt_yesno "Enable Caddy" "y"; then
        CADDY_ENABLED="true"
    else
        CADDY_ENABLED="false"
    fi
    if prompt_yesno "Enable LibreChat" "n"; then
        LIBRECHAT_ENABLED="true"
    else
        LIBRECHAT_ENABLED="false"
    fi
    if prompt_yesno "Enable OpenClaw" "n"; then
        OPENCLAW_ENABLED="true"
    else
        OPENCLAW_ENABLED="false"
    fi
    if prompt_yesno "Enable N8N" "n"; then
        N8N_ENABLED="true"
    else
        N8N_ENABLED="false"
    fi
    if prompt_yesno "Enable Flowise" "n"; then
        FLOWISE_ENABLED="true"
    else
        FLOWISE_ENABLED="false"
    fi
    if prompt_yesno "Enable Dify" "n"; then
        DIFY_ENABLED="true"
    else
        DIFY_ENABLED="false"
    fi
    if prompt_yesno "Enable Authentik" "n"; then
        AUTHENTIK_ENABLED="true"
    else
        AUTHENTIK_ENABLED="false"
    fi
    if prompt_yesno "Enable Signalbot" "n"; then
        SIGNALBOT_ENABLED="true"
    else
        SIGNALBOT_ENABLED="false"
    fi
    if prompt_yesno "Enable Bifrost" "n"; then
        BIFROST_ENABLED="true"
    else
        BIFROST_ENABLED="false"
    fi
}

collect_api_keys() {
    log "Collecting API keys (press Enter to skip)..."
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        echo "  LLM Provider API Keys:"
        OPENAI_API_KEY=$(prompt_default "  OpenAI API Key" "")
        ANTHROPIC_API_KEY=$(prompt_default "  Anthropic API Key" "")
        GOOGLE_API_KEY=$(prompt_default "  Google API Key" "")
        GROQ_API_KEY=$(prompt_default "  Groq API Key" "")
        OPENROUTER_API_KEY=$(prompt_default "  OpenRouter API Key" "")
    fi
}

collect_port_overrides() {
    log "Configuring ports (press Enter for defaults)..."
    
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        POSTGRES_PORT=$(prompt_default "PostgreSQL port" "5432")
    fi
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        REDIS_PORT=$(prompt_default "Redis port" "6379")
    fi
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        LITELLM_PORT=$(prompt_default "LiteLLM port" "4000")
    fi
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        OLLAMA_PORT=$(prompt_default "Ollama port" "11434")
        OLLAMA_DEFAULT_MODEL=$(prompt_default "Default Ollama model" "llama3.2")
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        OPENWEBUI_PORT=$(prompt_default "Open WebUI port" "3000")
    fi
    if [[ "${LIBRECHAT_ENABLED}" == "true" ]]; then
        LIBRECHAT_PORT=$(prompt_default "LibreChat port" "3080")
    fi
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        OPENCLAW_PORT=$(prompt_default "OpenClaw port" "3001")
    fi
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        QDRANT_PORT=$(prompt_default "Qdrant port" "6333")
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        N8N_PORT=$(prompt_default "N8N port" "5678")
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        FLOWISE_PORT=$(prompt_default "Flowise port" "3030")
    fi
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        DIFY_PORT=$(prompt_default "Dify port" "3040")
    fi
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        AUTHENTIK_PORT=$(prompt_default "Authentik port" "9000")
    fi
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        SIGNALBOT_PORT=$(prompt_default "Signalbot port" "8080")
    fi
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        BIFROST_PORT=$(prompt_default "Bifrost port" "8090")
    fi
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        CADDY_HTTP_PORT=$(prompt_default "Caddy HTTP port" "80")
        CADDY_HTTPS_PORT=$(prompt_default "Caddy HTTPS port" "443")
    fi
}

# =============================================================================
# PLATFORM CONF WRITING (README §5 - canonical pattern)
# =============================================================================
write_platform_conf() {
    local conf_file="${BASE_DIR}/platform.conf"
    
    log "Writing platform.conf..."
    
    # Generate secrets
    local postgres_user="platform"
    local postgres_db="platform"
    local tenant_prefix="${TENANT_ID}"
    local litellm_master_key litellm_ui_password litellm_db_url
    local postgres_password redis_password openwebui_secret
    local librechat_jwt_secret librechat_crypt_key n8n_encryption_key
    local flowise_password flowise_secretkey_overwrite dify_secret_key dify_init_password
    local authentik_secret_key authentik_bootstrap_password qdrant_api_key
    local signal_phone signal_recipient bifrost_api_key
    
    # Generate passwords first (before any dependencies)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        postgres_password="$(gen_password)"
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        redis_password="$(gen_password)"
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        litellm_master_key="sk-$(gen_secret)"
        litellm_ui_password="$(gen_password)"
        # Fix: Use tenant_prefix which is already defined above
        litellm_db_url="postgresql://${postgres_user}:${postgres_password}@${tenant_prefix}-postgres:5432/${postgres_db}"
    fi
    
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        openwebui_secret="$(gen_secret)"
    fi
    
    if [[ "${LIBRECHAT_ENABLED}" == "true" ]]; then
        librechat_jwt_secret="$(gen_secret)"
        librechat_crypt_key="$(gen_secret)"
    fi
    
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        n8n_encryption_key="$(gen_secret)"
    fi
    
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        flowise_password="$(gen_password)"
        flowise_secretkey_overwrite="$(gen_secret)"
    fi
    
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        dify_secret_key="$(gen_secret)"
        dify_init_password="$(gen_password)"
    fi
    
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        authentik_secret_key="$(gen_secret)"
        authentik_bootstrap_password="$(gen_password)"
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        qdrant_api_key="$(gen_secret)"
    fi
    
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        signal_phone=$(prompt_default "Signal sender phone number (E.164 format)" "")
        signal_recipient=$(prompt_default "Signal recipient phone number (E.164 format)" "")
        if [[ -z "${signal_phone}" || -z "${signal_recipient}" ]]; then
            fail "Signal phone numbers are required when Signalbot is enabled"
        fi
    fi
    
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        bifrost_api_key="$(gen_secret)"
    fi
    
    # Write the configuration file
    cat > "${conf_file}" << EOF
# AI Platform Configuration
# Generated by 1-setup-system.sh v${SCRIPT_VERSION}
# GENERATED_AT: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT EDIT MANUALLY — re-run 1-setup-system.sh to regenerate

# ── Identity ──────────────────────────────────────────────────────────────────
TENANT_ID="${TENANT_ID}"
TENANT_PREFIX="${TENANT_ID}"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SCRIPT_VERSION="${SCRIPT_VERSION}"

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR="${BASE_DIR}"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
COMPOSE_FILE="${BASE_DIR}/config/docker-compose.yml"
CONFIGURED_DIR="${BASE_DIR}/.configured"
LOG_DIR="${BASE_DIR}/logs"

# ── Platform user ─────────────────────────────────────────────────────────────
PLATFORM_USER="${PLATFORM_USER}"
PUID="${PUID}"
PGID="${PGID}"
PLATFORM_ARCH="${PLATFORM_ARCH}"

# ── Network ───────────────────────────────────────────────────────────────────
BASE_DOMAIN="${BASE_DOMAIN}"
DOCKER_NETWORK="${TENANT_ID}-network"
STACK_PRESET="${STACK_PRESET}"

# ── Proxy ─────────────────────────────────────────────────────────────────────
PROXY_TYPE="caddy"
PROXY_EMAIL="admin@${BASE_DOMAIN}"

# ── Infrastructure services ────────────────────────────────────────────────────
POSTGRES_ENABLED="${POSTGRES_ENABLED}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="platform"
POSTGRES_PASSWORD="${postgres_password:-}"
POSTGRES_DB="platform"

REDIS_ENABLED="${REDIS_ENABLED}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${redis_password:-}"

# ── LLM Layer ─────────────────────────────────────────────────────────────────
LITELLM_ENABLED="${LITELLM_ENABLED}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_MASTER_KEY="${litellm_master_key:-}"
LITELLM_UI_PASSWORD="${litellm_ui_password:-}"
LITELLM_DB_URL="${litellm_db_url:-}"

OLLAMA_ENABLED="${OLLAMA_ENABLED}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2}"
GPU_ENABLED="false"

# ── Provider API Keys ─────────────────────────────────────────────────────────
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# ── Web UIs ───────────────────────────────────────────────────────────────────
OPENWEBUI_ENABLED="${OPENWEBUI_ENABLED}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
OPENWEBUI_SECRET="${openwebui_secret:-}"

LIBRECHAT_ENABLED="${LIBRECHAT_ENABLED}"
LIBRECHAT_PORT="${LIBRECHAT_PORT:-3080}"
LIBRECHAT_JWT_SECRET="${librechat_jwt_secret:-}"
LIBRECHAT_CRYPT_KEY="${librechat_crypt_key:-}"

OPENCLAW_ENABLED="${OPENCLAW_ENABLED}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3001}"

# ── RAG / Vector ──────────────────────────────────────────────────────────────
QDRANT_ENABLED="${QDRANT_ENABLED}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_API_KEY="${qdrant_api_key:-}"

# ── Automation ────────────────────────────────────────────────────────────────
N8N_ENABLED="${N8N_ENABLED}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_ENCRYPTION_KEY="${n8n_encryption_key:-}"
N8N_WEBHOOK_URL="https://${BASE_DOMAIN}/n8n"

FLOWISE_ENABLED="${FLOWISE_ENABLED}"
FLOWISE_PORT="${FLOWISE_PORT:-3030}"
FLOWISE_USERNAME="admin"
FLOWISE_PASSWORD="${flowise_password:-}"
FLOWISE_SECRETKEY_OVERWRITE="${flowise_secretkey_overwrite:-}"

DIFY_ENABLED="${DIFY_ENABLED}"
DIFY_PORT="${DIFY_PORT:-3040}"
DIFY_SECRET_KEY="${dify_secret_key:-}"
DIFY_INIT_PASSWORD="${dify_init_password:-}"

# ── Identity ──────────────────────────────────────────────────────────────────
AUTHENTIK_ENABLED="${AUTHENTIK_ENABLED}"
AUTHENTIK_PORT="${AUTHENTIK_PORT:-9000}"
AUTHENTIK_SECRET_KEY="${authentik_secret_key:-}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${authentik_bootstrap_password:-}"
AUTHENTIK_BOOTSTRAP_EMAIL="admin@${BASE_DOMAIN}"

# ── Alerting ──────────────────────────────────────────────────────────────────
SIGNALBOT_ENABLED="${SIGNALBOT_ENABLED}"
SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"
SIGNAL_PHONE="${signal_phone:-}"
SIGNAL_RECIPIENT="${signal_recipient:-}"

# ── Proxy Ports ───────────────────────────────────────────────────────
CADDY_ENABLED="${CADDY_ENABLED}"
CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"

# ── Bifrost ───────────────────────────────────────────────────────────────────
BIFROST_ENABLED="${BIFROST_ENABLED}"
BIFROST_PORT="${BIFROST_PORT:-8090}"
BIFROST_API_KEY="${bifrost_api_key:-}"
EOF
    
    chmod 600 "${conf_file}"
    chown "$PUID:$PGID" "${conf_file}"
    ok "platform.conf written ($(wc -l < "${conf_file}") lines, chmod 600)"
}

# =============================================================================
# DIRECTORY STRUCTURE CREATION (README §4)
# =============================================================================
create_directory_skeleton() {
    log "Creating directory structure..."
    
    # Create main directories
    mkdir -p "${BASE_DIR}" "${DATA_DIR}" "${CONFIG_DIR}" "${CONFIGURED_DIR}" "${LOG_DIR}"
    
    # Create service data directories
    [[ "${POSTGRES_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/postgres"
    [[ "${REDIS_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/redis"
    [[ "${OLLAMA_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/ollama"
    [[ "${QDRANT_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/qdrant"
    [[ "${LITELLM_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/litellm"
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/openwebui"
    [[ "${LIBRECHAT_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/librechat"
    [[ "${OPENCLAW_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/openclaw"
    [[ "${N8N_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/n8n"
    [[ "${FLOWISE_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/flowise"
    [[ "${DIFY_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/dify"
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/authentik"
    [[ "${SIGNALBOT_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/signalbot"
    [[ "${BIFROST_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/bifrost"
    
    # Set ownership
    chown -R "$PUID:$PGID" "${BASE_DIR}"
    
    ok "Directory structure created"
}

# =============================================================================
# PACKAGE INSTALLATION (README §13)
# =============================================================================
install_packages() {
    log "Installing required packages..."
    
    # Update package list
    sudo apt-get update -qq
    
    # Install required packages
    local packages=(
        "docker.io"
        "docker-compose-plugin"
        "curl"
        "jq"
        "yq"
        "openssl"
        "lsof"
        "git"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l "$package" >/dev/null 2>&1; then
            log "  Installing ${package}..."
            sudo apt-get install -y "$package"
        else
            log "  ${package} already installed"
        fi
    done
    
    # Add user to docker group
    if ! groups "$USER" | grep -q docker; then
        log "  Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        warn "You may need to log out and log back in for docker group changes to take effect"
    fi
    
    # Install yq if not available via apt
    if ! command -v yq >/dev/null 2>&1; then
        log "  Installing yq..."
        local yq_arch
        case "${PLATFORM_ARCH}" in
            x86_64)  yq_arch="amd64" ;;
            aarch64) yq_arch="arm64" ;;
            *)       fail "Unsupported architecture for yq: ${PLATFORM_ARCH}" ;;
        esac
        sudo wget -qO /usr/local/bin/yq \
            "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}"
        sudo chmod +x /usr/local/bin/yq
    fi
    
    ok "Package installation completed"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    
    # Set up logging
    LOG_FILE="${HOME}/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== Script 1: System Compiler ==="
    log "Version: ${SCRIPT_VERSION}"
    
    # Display banner
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — System Compiler                   ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  This script will:"
    echo "  • Collect all configuration interactively"
    echo "  • Create platform.conf (single source of truth)"
    echo "  • Set up directory structure"
    echo "  • Install required packages"
    echo ""
    
    # Always collect tenant configuration interactively
    collect_tenant_config
    
    # Validate tenant ID
    if [[ -z "$TENANT_ID" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Check if platform.conf already exists
    if [[ -f "${BASE_DIR}/platform.conf" ]]; then
        warn "platform.conf already exists for tenant '${TENANT_ID}'"
        if ! prompt_yesno "Overwrite existing configuration?" "n"; then
            log "Aborted by user"
            exit 0
        fi
    fi
    
    # System detection
    detect_system
    
    # Collect configuration
    collect_preset
    collect_service_flags
    collect_api_keys
    collect_port_overrides
    
    # Resolve port conflicts
    resolve_all_ports
    
    # Create platform.conf
    write_platform_conf
    
    # Create directory structure
    create_directory_skeleton
    
    # Install packages
    install_packages
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 1 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ Configuration collected interactively"
    echo "  ✓ platform.conf created (single source of truth)"
    echo "  ✓ Directory structure created"
    echo "  ✓ Required packages installed"
    echo ""
    echo "  Next steps:"
    echo "  1. Deploy services: bash scripts/2-deploy-services.sh ${TENANT_ID}"
    echo "  2. Configure services: bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo ""
    echo "  Configuration file: ${BASE_DIR}/platform.conf"
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
