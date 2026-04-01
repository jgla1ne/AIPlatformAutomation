#!/usr/bin/env bash
# =============================================================================
# Script 1: Input Collector Only - RESTORED c38d365 + TTY SAFETY
# PURPOSE: Interactive user input and platform.conf generation ONLY
# USAGE:   bash scripts/1-setup-system.sh [tenant_id]
# =============================================================================

set -euo pipefail
trap 'error_handler $LINENO' ERR

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
LOG_FILE="/var/log/ai-platform-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Error Handler
error_handler() {
    local exit_code=$?
    local line=$1
    echo ""
    echo -e "${RED}[ERROR]${NC} Script failed at line $line with exit code $exit_code"
    exit $exit_code
}

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# NON-INTERACTIVE SAFE INPUT WRAPPER
# =============================================================================
safe_read() {
    # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value

    # Check for env var override first (allows: VAR=x sudo -E bash script1.sh)
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ${prompt}: ${value} (from environment)"
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input
        read -rp "  ${prompt} [${default}]: " value
        value="${value:-${default}}"
    else
        # Non-TTY (Windsurf, CI, pipe) — use default silently
        value="${default}"
        echo "  ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

# Helper function for yes/no prompts
safe_read_yesno() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value
    
    # Check for env var override first
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ${prompt}: ${value} (from environment)"
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input
        read -rp "  ${prompt} [y/n] (default: ${default}): " value
        value="${value:-${default}}"
        case "$value" in
            [Yy]*) value="true" ;;
            [Nn]*) value="false" ;;
            *) value="${default}" ;;
        esac
    else
        # Non-TTY — use default silently
        value="${default}"
        echo "  ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

# =============================================================================
# SYSTEM DETECTION (NON-INTERACTIVE)
# =============================================================================
detect_system() {
    log "Detecting system capabilities..."
    
    # GPU detection
    GPU_TYPE="cpu"
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        GPU_TYPE="nvidia"
        log "NVIDIA GPU detected"
    elif command -v rocm-smi &>/dev/null; then
        GPU_TYPE="amd"
        log "AMD GPU detected"
    else
        log "No GPU detected, using CPU"
    fi
    
    # Available RAM
    TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "8")
    
    # Available disk on /mnt
    MNT_DISK_GB=$(df /mnt 2>/dev/null | awk 'NR==2 {printf "%.0f", $4/1024/1024}' || echo "unknown")
    
    # Host MTU detection
    HOST_MTU=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -1 | xargs -I{} cat /sys/class/net/{}/mtu 2>/dev/null || echo "1500")
    
    log "System: RAM=${TOTAL_RAM_GB}GB, Disk(free on /mnt)=${MNT_DISK_GB}GB, GPU=${GPU_TYPE}, MTU=${HOST_MTU}"
}

# =============================================================================
# CHECK PREREQUISITES (NON-INTERACTIVE)
# =============================================================================
check_prerequisites() {
    section "Checking Prerequisites"
    
    local missing=()
    
    # Add user to docker group with proper validation
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
        echo "IMPORTANT: Log out and back in (or run 'newgrp docker') before running script 2"
    else
        warn "Could not determine invoking user for docker group assignment"
        warn "You may need to manually add your user to the docker group"
    fi
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    else
        DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log "Docker: $DOCKER_VERSION"
        
        # Verify docker daemon is running
        if ! docker info &>/dev/null; then
            warn "Docker daemon is not running. Start it with: sudo systemctl start docker"
        fi
    fi
    
    # Check docker compose (v2 plugin)
    if ! docker compose version &>/dev/null; then
        missing+=("docker-compose-plugin")
    else
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "v2")
        log "Docker Compose: $COMPOSE_VERSION"
    fi
    
    # Check curl
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    # Check /mnt is mounted and writable
    if ! mountpoint -q /mnt 2>/dev/null && [[ ! -d /mnt ]]; then
        warn "/mnt does not exist. Please ensure /mnt is available."
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing prerequisites: ${missing[*]}\nInstall them and re-run Script 1."
    fi
    
    log "All prerequisites satisfied"
}

# =============================================================================
# HELPER FUNCTIONS
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

apply_preset_defaults() {
    local preset="$1"
    
    case "${preset}" in
        minimal)
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            # All others false
            LIBRECHAT_ENABLED="false"
            OPENCLAW_ENABLED="false"
            N8N_ENABLED="false"
            FLOWISE_ENABLED="false"
            DIFY_ENABLED="false"
            AUTHENTIK_ENABLED="false"
            NGINXPM_ENABLED="false"
            SIGNALBOT_ENABLED="false"
            BIFROST_ENABLED="false"
            ;;
        standard)
            # minimal + automation
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            LIBRECHAT_ENABLED="true"
            OPENCLAW_ENABLED="true"
            N8N_ENABLED="true"
            FLOWISE_ENABLED="true"
            # Others false
            DIFY_ENABLED="false"
            AUTHENTIK_ENABLED="false"
            NGINXPM_ENABLED="false"
            SIGNALBOT_ENABLED="false"
            BIFROST_ENABLED="false"
            ;;
        full)
            # everything enabled
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            LIBRECHAT_ENABLED="true"
            OPENCLAW_ENABLED="true"
            N8N_ENABLED="true"
            FLOWISE_ENABLED="true"
            DIFY_ENABLED="true"
            AUTHENTIK_ENABLED="true"
            SIGNALBOT_ENABLED="true"
            BIFROST_ENABLED="true"
            NGINXPM_ENABLED="false"  # Caddy preferred
            ;;
    esac
}

# =============================================================================
# MAIN INPUT COLLECTION (RESTORED c38d365 PATTERN)
# =============================================================================
collect_configuration() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — Configuration Collector            ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  System detected:"
    echo "  • Architecture: $(uname -m)"
    echo "  • GPU Type    : $GPU_TYPE"
    echo "  • Total RAM   : ${TOTAL_RAM_GB}GB"
    echo "  • Free on /mnt: ${MNT_DISK_GB}GB"
    echo "  • Host MTU    : $HOST_MTU"
    echo ""
    echo "  You will be prompted for all configuration values."
    echo "  Press ENTER to accept defaults shown in [brackets]."
    echo ""

    # ── SECTION: Tenant Configuration ─────────────────────────────────────
    section "1. Tenant Configuration"
    
    safe_read "Tenant identifier (alphanumeric, no spaces)" "datasquiz" "TENANT_ID"
    safe_read "Base domain (example.com or 'local' for localhost)" "datasquiz.local" "BASE_DOMAIN"
    
    # Auto-derive BASE_DIR based on EBS mount detection
    if [[ -d "/mnt" ]]; then
        BASE_DIR="/mnt/${TENANT_ID}"
        echo "  Base directory: ${BASE_DIR} (EBS mount detected)"
    else
        BASE_DIR="${HOME}/ai-platform/${TENANT_ID}"
        echo "  Base directory: ${BASE_DIR} (fallback path)"
    fi

    # ── SECTION: Stack Preset ───────────────────────────────────────────────
    section "2. Stack Preset"
    
    echo "  Available presets:"
    echo "    minimal  - Core LLM platform (postgres, redis, litellm, ollama, openwebui, qdrant, caddy)"
    echo "    standard - Full automation (minimal + librechat, openclaw, n8n, flowise)"
    echo "    full     - Everything (standard + dify, authentik, signalbot, bifrost)"
    echo "    custom   - Choose services individually"
    
    local preset
    while true; do
        safe_read "Select preset" "minimal" "preset"
        preset=$(echo "${preset}" | xargs | tr '[:upper:]' '[:lower:]')
        case "${preset}" in
            minimal|standard|full|custom) break ;;
            *) echo "    Invalid preset. Choose: minimal, standard, full, or custom" ;;
        esac
    done
    STACK_PRESET="${preset}"
    
    # ── SECTION: Service Selection (if custom) ───────────────────────────────
    if [[ "${STACK_PRESET}" == "custom" ]]; then
        section "3. Service Selection"
        
        echo "  Infrastructure services:"
        safe_read_yesno "Enable PostgreSQL" "true" "POSTGRES_ENABLED"
        safe_read_yesno "Enable Redis" "true" "REDIS_ENABLED"
        
        echo "  LLM layer:"
        safe_read_yesno "Enable LiteLLM" "true" "LITELLM_ENABLED"
        safe_read_yesno "Enable Ollama" "true" "OLLAMA_ENABLED"
        
        echo "  Web UIs (any combination):"
        safe_read_yesno "Enable OpenWebUI" "true" "OPENWEBUI_ENABLED"
        safe_read_yesno "Enable LibreChat" "false" "LIBRECHAT_ENABLED"
        safe_read_yesno "Enable OpenClaw" "false" "OPENCLAW_ENABLED"
        
        echo "  RAG / Vector:"
        safe_read_yesno "Enable Qdrant" "true" "QDRANT_ENABLED"
        
        echo "  Automation:"
        safe_read_yesno "Enable N8N" "false" "N8N_ENABLED"
        safe_read_yesno "Enable Flowise" "false" "FLOWISE_ENABLED"
        safe_read_yesno "Enable Dify" "false" "DIFY_ENABLED"
        
        echo "  Identity:"
        safe_read_yesno "Enable Authentik" "false" "AUTHENTIK_ENABLED"
        
        echo "  Proxy:"
        safe_read_yesno "Use Caddy (default)" "true" "CADDY_ENABLED"
        safe_read_yesno "Use Nginx Proxy Manager" "false" "NGINXPM_ENABLED"
        
        echo "  Optional:"
        safe_read_yesno "Enable Signalbot" "false" "SIGNALBOT_ENABLED"
        safe_read_yesno "Enable Bifrost" "false" "BIFROST_ENABLED"
    else
        # Apply preset defaults
        apply_preset_defaults "${STACK_PRESET}"
    fi

    # ── SECTION: LLM Configuration ───────────────────────────────────────────
    if [[ "${LITELLM_ENABLED}" == "true" ]] || [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        section "4. LLM Configuration"
        
        if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
            safe_read "Default Ollama model" "llama3.2" "OLLAMA_DEFAULT_MODEL"
        fi
        
        if [[ "${LITELLM_ENABLED}" == "true" ]]; then
            echo "  LLM Provider API Keys (press ENTER to skip):"
            safe_read "  OpenAI API Key" "" "OPENAI_API_KEY"
            safe_read "  Anthropic API Key" "" "ANTHROPIC_API_KEY"
            safe_read "  Google API Key" "" "GOOGLE_API_KEY"
            safe_read "  Groq API Key" "" "GROQ_API_KEY"
            safe_read "  OpenRouter API Key" "" "OPENROUTER_API_KEY"
        fi
    fi

    # ── SECTION: Port Overrides (optional) ─────────────────────────────────
    section "5. Port Configuration"
    echo "  Press ENTER to accept defaults"
    
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        safe_read "PostgreSQL port" "5432" "POSTGRES_PORT"
    fi
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        safe_read "Redis port" "6379" "REDIS_PORT"
    fi
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        safe_read "LiteLLM port" "4000" "LITELLM_PORT"
    fi
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        safe_read "Ollama port" "11434" "OLLAMA_PORT"
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        safe_read "OpenWebUI port" "3000" "OPENWEBUI_PORT"
    fi
    if [[ "${LIBRECHAT_ENABLED}" == "true" ]]; then
        safe_read "LibreChat port" "3080" "LIBRECHAT_PORT"
    fi
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        safe_read "OpenClaw port" "3001" "OPENCLAW_PORT"
    fi
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        safe_read "Qdrant port" "6333" "QDRANT_PORT"
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        safe_read "N8N port" "5678" "N8N_PORT"
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        safe_read "Flowise port" "3030" "FLOWISE_PORT"
    fi
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        safe_read "Dify port" "3040" "DIFY_PORT"
    fi
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        safe_read "Authentik port" "9000" "AUTHENTIK_PORT"
    fi
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        safe_read "Signalbot port" "8080" "SIGNALBOT_PORT"
    fi
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        safe_read "Bifrost port" "8090" "BIFROST_PORT"
    fi

    # ── SECTION: Proxy Configuration ────────────────────────────────────────
    if [[ "${CADDY_ENABLED}" == "true" ]] || [[ "${NGINXPM_ENABLED}" == "true" ]]; then
        section "6. Proxy Configuration"
        
        if [[ "${CADDY_ENABLED}" == "true" ]] && [[ "${NGINXPM_ENABLED}" == "true" ]]; then
            echo "  ⚠️  Both proxies selected - using Caddy as primary"
            NGINXPM_ENABLED="false"
        fi
        
        if [[ "${CADDY_ENABLED}" == "true" ]]; then
            PROXY_TYPE="caddy"
            safe_read "Let's Encrypt email" "admin@${BASE_DOMAIN}" "PROXY_EMAIL"
        elif [[ "${NGINXPM_ENABLED}" == "true" ]]; then
            PROXY_TYPE="nginx"
            safe_read "Nginx PM admin email" "admin@${BASE_DOMAIN}" "PROXY_EMAIL"
        fi
    fi

    # ── SECTION: Signalbot Configuration (if enabled) ────────────────────────
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        section "7. Signalbot Configuration"
        
        safe_read "Signal sender phone number (E.164 format)" "" "SIGNAL_PHONE"
        safe_read "Signal recipient phone number (E.164 format)" "" "SIGNAL_RECIPIENT"
        
        if [[ -z "${SIGNAL_PHONE}" || -z "${SIGNAL_RECIPIENT}" ]]; then
            fail "Signal phone numbers are required when Signalbot is enabled"
        fi
    fi
}

# =============================================================================
# ATOMIC PLATFORM.CONF WRITE (README P1)
# =============================================================================
write_platform_conf() {
    local conf_file="${BASE_DIR}/platform.conf"
    local tmp_file="${conf_file}.tmp"

    # Generate secrets first
    local postgres_password redis_password litellm_master_key litellm_ui_password
    local openwebui_secret librechat_jwt_secret librechat_crypt_key n8n_encryption_key
    local flowise_password flowise_secretkey_overwrite dify_secret_key dify_init_password
    local authentik_secret_key authentik_bootstrap_password qdrant_api_key
    local bifrost_api_key
    
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        postgres_password="$(gen_password)"
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        redis_password="$(gen_password)"
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        litellm_master_key="sk-$(gen_secret)"
        litellm_ui_password="$(gen_password)"
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
    
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        bifrost_api_key="$(gen_secret)"
    fi

    # Generate ALL keys from README canonical list
    cat > "${tmp_file}" << EOF
# AI Platform Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Tenant: ${TENANT_ID}

# ── Identity ──────────────────────────────────────────────────────────────────
TENANT_ID="${TENANT_ID}"
TENANT_PREFIX="${TENANT_ID}"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SCRIPT_VERSION="5.1.0"

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR="${BASE_DIR}"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
COMPOSE_FILE="${BASE_DIR}/config/docker-compose.yml"
CONFIGURED_DIR="${BASE_DIR}/.configured"
LOG_DIR="${BASE_DIR}/logs"

# ── Platform user ─────────────────────────────────────────────────────────────
PLATFORM_USER="$(whoami)"
PUID="$(id -u)"
PGID="$(id -g)"
PLATFORM_ARCH="$(uname -m)"

# ── Network ───────────────────────────────────────────────────────────────────
BASE_DOMAIN="${BASE_DOMAIN}"
DOCKER_NETWORK="${TENANT_ID}-network"
STACK_PRESET="${STACK_PRESET:-custom}"

# ── Proxy ─────────────────────────────────────────────────────────────────────
PROXY_TYPE="${PROXY_TYPE:-caddy}"
PROXY_EMAIL="${PROXY_EMAIL:-admin@${BASE_DOMAIN}}"

# ── Infrastructure services ───────────────────────────────────────────────────
POSTGRES_ENABLED="${POSTGRES_ENABLED:-true}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-platform}"
POSTGRES_PASSWORD="${postgres_password}"
POSTGRES_DB="${POSTGRES_DB:-platform}"

REDIS_ENABLED="${REDIS_ENABLED:-true}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${redis_password}"

# ── LLM routing ───────────────────────────────────────────────────────────────
LITELLM_ENABLED="${LITELLM_ENABLED:-true}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_MASTER_KEY="${litellm_master_key}"
LITELLM_UI_PASSWORD="${litellm_ui_password}"
LITELLM_DB_URL="postgresql://${POSTGRES_USER}:${postgres_password}@${TENANT_ID}-postgres:5432/${POSTGRES_DB}"

OLLAMA_ENABLED="${OLLAMA_ENABLED:-true}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2}"
GPU_ENABLED="${GPU_ENABLED:-false}"

# ── LLM provider API keys (empty = provider disabled) ────────────────────────
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# ── Web UIs (any combination may be true simultaneously) ──────────────────────
OPENWEBUI_ENABLED="${OPENWEBUI_ENABLED:-true}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
OPENWEBUI_SECRET="${openwebui_secret}"

LIBRECHAT_ENABLED="${LIBRECHAT_ENABLED:-false}"
LIBRECHAT_PORT="${LIBRECHAT_PORT:-3080}"
LIBRECHAT_JWT_SECRET="${librechat_jwt_secret}"
LIBRECHAT_CRYPT_KEY="${librechat_crypt_key}"

OPENCLAW_ENABLED="${OPENCLAW_ENABLED:-false}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3001}"

# ── RAG / Vector ──────────────────────────────────────────────────────────────
QDRANT_ENABLED="${QDRANT_ENABLED:-true}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_API_KEY="${qdrant_api_key}"

# ── Automation ────────────────────────────────────────────────────────────────
N8N_ENABLED="${N8N_ENABLED:-false}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_ENCRYPTION_KEY="${n8n_encryption_key}"
N8N_WEBHOOK_URL="https://${BASE_DOMAIN}/n8n"

FLOWISE_ENABLED="${FLOWISE_ENABLED:-false}"
FLOWISE_PORT="${FLOWISE_PORT:-3030}"
FLOWISE_USERNAME="${FLOWISE_USERNAME:-admin}"
FLOWISE_PASSWORD="${flowise_password}"
FLOWISE_SECRETKEY_OVERWRITE="${flowise_secretkey_overwrite}"

DIFY_ENABLED="${DIFY_ENABLED:-false}"
DIFY_PORT="${DIFY_PORT:-3040}"
DIFY_SECRET_KEY="${dify_secret_key}"
DIFY_INIT_PASSWORD="${dify_init_password}"

# ── Identity ──────────────────────────────────────────────────────────────────
AUTHENTIK_ENABLED="${AUTHENTIK_ENABLED:-false}"
AUTHENTIK_PORT="${AUTHENTIK_PORT:-9000}"
AUTHENTIK_SECRET_KEY="${authentik_secret_key}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${authentik_bootstrap_password}"
AUTHENTIK_BOOTSTRAP_EMAIL="admin@${BASE_DOMAIN}"

# ── Alerting ──────────────────────────────────────────────────────────────────
SIGNALBOT_ENABLED="${SIGNALBOT_ENABLED:-false}"
SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"
SIGNAL_PHONE="${SIGNAL_PHONE}"
SIGNAL_RECIPIENT="${SIGNAL_RECIPIENT}"

# ── Bifrost (optional LLM gateway) ────────────────────────────────────────────
BIFROST_ENABLED="${BIFROST_ENABLED:-false}"
BIFROST_PORT="${BIFROST_PORT:-8090}"
BIFROST_API_KEY="${bifrost_api_key}"
EOF

    mv "${tmp_file}" "${conf_file}"
    chmod 600 "${conf_file}"
    echo "✅ platform.conf written to ${conf_file}"
}

# =============================================================================
# DIRECTORY SKELETON CREATION (README P4)
# =============================================================================
create_directory_skeleton() {
    log "Creating directory structure..."
    
    # Create main directories
    mkdir -p "${BASE_DIR}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${CONFIGURED_DIR}"
    mkdir -p "${LOG_DIR}"
    
    # Create per-service data directories
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/postgres"
    fi
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/redis"
    fi
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/litellm"
    fi
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/ollama"
        # Ollama container runs as user 1000
        chown -R 1000:1000 "${DATA_DIR}/ollama"
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/openwebui"
    fi
    if [[ "${LIBRECHAT_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/librechat"
    fi
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/openclaw"
    fi
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/qdrant"
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/n8n"
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/flowise"
    fi
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/dify"
    fi
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/authentik"
    fi
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/signalbot"
    fi
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/bifrost"
    fi
    
    ok "Directory structure created"
}

# =============================================================================
# PACKAGE INSTALLATION (README P13)
# =============================================================================
install_packages() {
    log "Installing required packages..."
    
    local packages=("docker" "docker-compose-plugin" "curl" "jq" "yq" "openssl" "lsof")
    local missing=()
    
    for package in "${packages[@]}"; do
        case "$package" in
            docker)
                if ! command -v docker &>/dev/null; then
                    missing+=("docker")
                fi
                ;;
            docker-compose-plugin)
                if ! docker compose version &>/dev/null; then
                    missing+=("docker-compose-plugin")
                fi
                ;;
            *)
                if ! command -v "$package" &>/dev/null; then
                    missing+=("$package")
                fi
                ;;
        esac
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Installing missing packages: ${missing[*]}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${missing[@]}"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "${missing[@]}"
        else
            fail "Cannot install packages automatically. Please install: ${missing[*]}"
        fi
    fi
    
    ok "All required packages installed"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    # Execute phases first to set BASE_DIR
    detect_system
    check_prerequisites
    collect_configuration
    
    # Set up logging after BASE_DIR is defined
    if [[ -n "${BASE_DIR}" ]]; then
        LOG_FILE="${BASE_DIR}/logs/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
        mkdir -p "$(dirname "$LOG_FILE")"
    fi
    
    write_platform_conf
    create_directory_skeleton
    install_packages
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Configuration saved to platform.conf                ║"
    echo "║                                                     ║"
    echo "║  Next: Deploy services                              ║"
    echo "║    bash scripts/2-deploy-services.sh              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ -f "${BASE_DIR}/platform.conf" ]]; then
        ok "platform.conf created successfully at ${BASE_DIR}/platform.conf"
        echo "  You can now run: bash scripts/2-deploy-services.sh"
    else
        fail "platform.conf was not created"
    fi
}

# Execute main function
main "$@"
