#!/usr/bin/env bash
# =============================================================================
# Script 1: Input Collector Only - BULLETPROOF v4.2
# PURPOSE: Interactive user input and .env generation ONLY
# USAGE:   sudo bash scripts/1-setup-system.sh [tenant_id]
# =============================================================================

set -euo pipefail
trap 'error_handler $LINENO' ERR

# Script Directory and Repository Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Logging Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Error Handler
error_handler() {
    local exit_code=$?
    local line=$1
    echo ""
    echo -e "${RED}[ERROR]${NC} Script failed at line $line with exit code $exit_code"
    exit $exit_code
}

# Generate random token
generate_token() {
    openssl rand -hex 16
}

# --------------------------------------------------------------------------
# Interactive Prompt Functions (RESTORED from 943b6dd)
# --------------------------------------------------------------------------
prompt_default() {
    local var="$1"
    local question="$2"
    local default="$3"
    echo ""
    read -r -p "  $question [$default]: " input
    eval "$var='${input:-$default}'"
}

prompt_required() {
    local var="$1"
    local question="$2"
    local value=""
    while [[ -z "$value" ]]; do
        echo ""
        read -r -p "  $question (required): " value
        if [[ -z "$value" ]]; then
            echo "  ⚠  This field is required."
        fi
    done
    eval "$var='$value'"
}

prompt_secret() {
    local var="$1"
    local question="$2"
    local value=""
    while [[ -z "$value" ]]; do
        echo ""
        read -r -s -p "  $question (required, hidden): " value
        echo ""
        if [[ -z "$value" ]]; then
            echo "  ⚠  This field is required."
        fi
    done
    eval "$var='$value'"
}

prompt_yesno() {
    local var="$1"
    local question="$2"
    local default="${3:-y}"
    local answer=""
    echo ""
    read -r -p "  $question [y/n] (default: $default): " answer
    answer="${answer:-$default}"
    case "$answer" in
        [Yy]*) eval "$var=true" ;;
        *)     eval "$var=false" ;;
    esac
}

# --------------------------------------------------------------------------
# System Detection (NON-INTERACTIVE)
# --------------------------------------------------------------------------
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
    HOST_MTU=$(ip route get 8.8.8.8 2>/dev/null | \
        grep -oP 'dev \K\S+' | head -1 | \
        xargs -I{} cat /sys/class/net/{}/mtu 2>/dev/null || echo "1500")
    
    log "System: RAM=${TOTAL_RAM_GB}GB, Disk(free on /mnt)=${MNT_DISK_GB}GB, GPU=${GPU_TYPE}, MTU=${HOST_MTU}"
}

# --------------------------------------------------------------------------
# Check Prerequisites (NON-INTERACTIVE)
# --------------------------------------------------------------------------
check_prerequisites() {
    section "Checking Prerequisites"
    
    local missing=()
    
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

# --------------------------------------------------------------------------
# Main Interactive Collection
# --------------------------------------------------------------------------
collect_configuration() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — Configuration Collector            ║"
    echo "║                    Script 1 of 3                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  System detected:"
    echo "  • GPU Type    : $GPU_TYPE"
    echo "  • Total RAM   : ${TOTAL_RAM_GB}GB"
    echo "  • Free on /mnt: ${MNT_DISK_GB}GB"
    echo "  • Host MTU    : $HOST_MTU"
    echo ""
    echo "  You will be prompted for all configuration values."
    echo "  Press ENTER to accept defaults shown in [brackets]."
    echo ""

    # ── SECTION: Paths ──────────────────────────────────────────────────────
    section "1. Base Paths"
    
    prompt_default MNT_BASE \
        "Base directory for all platform data" \
        "/mnt/aiplatform"
    
    # Validate /mnt prefix
    if [[ "$MNT_BASE" != /mnt/* ]]; then
        warn "MNT_BASE must be under /mnt/. Forcing /mnt/aiplatform"
        MNT_BASE="/mnt/aiplatform"
    fi

    # ── SECTION: Domain / Network ───────────────────────────────────────────
    section "2. Domain & Network"
    
    prompt_default DOMAIN \
        "Base domain (e.g., example.com or 'local' for localhost)" \
        "local"
    
    prompt_default HOST_IP \
        "Host IP address (used for service binding)" \
        "$(hostname -I | awk '{print $1}')"

    # Bifrost network config
    prompt_default BIFROST_SUBNET \
        "Bifrost Docker network subnet" \
        "172.20.0.0/16"
    
    prompt_default BIFROST_GATEWAY \
        "Bifrost Docker network gateway" \
        "172.20.0.1"
    
    # Set recommended MTU based on host MTU
    if [[ "$HOST_MTU" -le 1500 ]]; then
        RECOMMENDED_MTU=$((HOST_MTU - 50))
    else
        RECOMMENDED_MTU="1450"
    fi
    
    prompt_default BIFROST_MTU \
        "Bifrost network MTU (recommended: $RECOMMENDED_MTU for your host MTU of $HOST_MTU)" \
        "$RECOMMENDED_MTU"

    # ── SECTION: Portainer (Mission Control) ───────────────────────────────
    section "3. Portainer — Mission Control"
    
    prompt_default PORTAINER_CONTAINER_NAME \
        "Portainer container name" \
        "portainer"
    
    prompt_default PORTAINER_PORT \
        "Portainer HTTPS port" \
        "9443"
    
    prompt_default PORTAINER_HTTP_PORT \
        "Portainer HTTP port (tunnel/edge)" \
        "8000"
    
    prompt_secret PORTAINER_ADMIN_PASSWORD \
        "Portainer admin password"

    # ── SECTION: Ollama ─────────────────────────────────────────────────────
    section "4. Ollama — LLM Engine"
    
    prompt_default OLLAMA_CONTAINER_NAME \
        "Ollama container name" \
        "ollama"
    
    prompt_default OLLAMA_PORT \
        "Ollama API port" \
        "11434"
    
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        OLLAMA_RUNTIME="nvidia"
        log "Auto-configured Ollama for NVIDIA GPU"
    elif [[ "$GPU_TYPE" == "amd" ]]; then
        OLLAMA_RUNTIME="amd"
        log "Auto-configured Ollama for AMD GPU"
    else
        OLLAMA_RUNTIME="cpu"
        log "Ollama will run on CPU"
    fi
    
    prompt_yesno OLLAMA_PULL_DEFAULT_MODEL \
        "Pull a default Ollama model after deployment?" \
        "y"
    
    if [[ "$OLLAMA_PULL_DEFAULT_MODEL" == "true" ]]; then
        prompt_default OLLAMA_DEFAULT_MODEL \
            "Default model to pull (e.g., llama3.2, mistral, gemma2)" \
            "llama3.2"
    else
        OLLAMA_DEFAULT_MODEL=""
    fi

    # ── SECTION: Open WebUI ─────────────────────────────────────────────────
    section "5. Open WebUI"
    
    prompt_default OPEN_WEBUI_CONTAINER_NAME \
        "Open WebUI container name" \
        "open-webui"
    
    prompt_default OPEN_WEBUI_PORT \
        "Open WebUI port" \
        "3000"

    # ── SECTION: PostgreSQL ─────────────────────────────────────────────────
    section "6. PostgreSQL — Shared Database"
    
    prompt_default POSTGRES_CONTAINER_NAME \
        "PostgreSQL container name" \
        "postgres"
    
    prompt_default POSTGRES_PORT \
        "PostgreSQL port" \
        "5432"
    
    prompt_default POSTGRES_USER \
        "PostgreSQL superuser" \
        "aiplatform"
    
    prompt_secret POSTGRES_PASSWORD \
        "PostgreSQL password"
    
    prompt_default POSTGRES_DB \
        "Default database name" \
        "aiplatform"
    
    # Per-service databases
    prompt_default N8N_DB \
        "n8n database name" \
        "n8n"
    
    prompt_default FLOWISE_DB \
        "Flowise database name" \
        "flowise"

    # ── SECTION: Redis ──────────────────────────────────────────────────────
    section "7. Redis — Cache Layer"
    
    prompt_default REDIS_CONTAINER_NAME \
        "Redis container name" \
        "redis"
    
    prompt_default REDIS_PORT \
        "Redis port" \
        "6379"
    
    prompt_secret REDIS_PASSWORD \
        "Redis password"

    # ── SECTION: n8n ────────────────────────────────────────────────────────
    section "8. n8n — Workflow Automation"
    
    prompt_default N8N_CONTAINER_NAME \
        "n8n container name" \
        "n8n"
    
    prompt_default N8N_PORT \
        "n8n port" \
        "5678"
    
    if [[ "$DOMAIN" == "local" ]]; then
        N8N_WEBHOOK_URL="http://${HOST_IP}:${N8N_PORT}"
    else
        N8N_WEBHOOK_URL="https://n8n.${DOMAIN}"
    fi
    
    prompt_default N8N_WEBHOOK_URL \
        "n8n Webhook URL (used for workflow triggers)" \
        "$N8N_WEBHOOK_URL"
    
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    log "Auto-generated n8n encryption key"

    # ── SECTION: SearXNG ────────────────────────────────────────────────────
    section "9. SearXNG — Private Search"
    
    prompt_default SEARXNG_CONTAINER_NAME \
        "SearXNG container name" \
        "searxng"
    
    prompt_default SEARXNG_PORT \
        "SearXNG port" \
        "8080"
    
    # SearXNG requires secret key
    SEARXNG_SECRET_KEY=$(openssl rand -hex 32)
    log "Auto-generated SearXNG secret key"

    # ── SECTION: Flowise ────────────────────────────────────────────────────
    section "10. Flowise — AI Flow Builder"
    
    prompt_default FLOWISE_CONTAINER_NAME \
        "Flowise container name" \
        "flowise"
    
    prompt_default FLOWISE_PORT \
        "Flowise port" \
        "3001"
    
    prompt_default FLOWISE_USERNAME \
        "Flowise admin username" \
        "admin"
    
    prompt_secret FLOWISE_PASSWORD \
        "Flowise admin password"

    # ── SECTION: Nginx (optional) ───────────────────────────────────────────
    section "11. Nginx Reverse Proxy"
    
    prompt_yesno ENABLE_NGINX \
        "Enable Nginx reverse proxy?" \
        "y"
    
    if [[ "$ENABLE_NGINX" == "true" ]]; then
        prompt_default NGINX_HTTP_PORT \
            "Nginx HTTP port" \
            "80"
        
        prompt_default NGINX_HTTPS_PORT \
            "Nginx HTTPS port" \
            "443"
    fi

    # ── SECTION: Confirm ────────────────────────────────────────────────────
    section "Configuration Summary"
    
    echo ""
    echo "  Base Path      : $MNT_BASE"
    echo "  Domain         : $DOMAIN"
    echo "  Host IP        : $HOST_IP"
    echo "  Bifrost Subnet : $BIFROST_SUBNET"
    echo "  Bifrost Gateway: $BIFROST_GATEWAY"
    echo "  Bifrost MTU    : $BIFROST_MTU"
    echo "  GPU Runtime    : $OLLAMA_RUNTIME"
    echo "  Portainer      : $PORTAINER_CONTAINER_NAME :$PORTAINER_PORT"
    echo "  Ollama         : $OLLAMA_CONTAINER_NAME :$OLLAMA_PORT"
    echo "  Open WebUI     : $OPEN_WEBUI_CONTAINER_NAME :$OPEN_WEBUI_PORT"
    echo "  n8n            : $N8N_CONTAINER_NAME :$N8N_PORT"
    echo "  SearXNG        : $SEARXNG_CONTAINER_NAME :$SEARXNG_PORT"
    echo "  Flowise        : $FLOWISE_CONTAINER_NAME :$FLOWISE_PORT"
    echo "  PostgreSQL     : $POSTGRES_CONTAINER_NAME :$POSTGRES_PORT"
    echo "  Redis          : $REDIS_CONTAINER_NAME :$REDIS_PORT"
    [[ "$ENABLE_NGINX" == "true" ]] && echo "  Nginx          : :$NGINX_HTTP_PORT / :$NGINX_HTTPS_PORT"
    echo ""
    
    read -r -p "  Proceed with this configuration? [y/N]: " CONFIRM
    case "$CONFIRM" in
        [Yy]*) log "Configuration confirmed" ;;
        *)     log "Configuration cancelled by user."; exit 0 ;;
    esac
}

# --------------------------------------------------------------------------
# Write .env file
# --------------------------------------------------------------------------
write_env_file() {
    section "Writing .env File"
    
    local ENV_FILE="${REPO_ROOT}/.env"
    
    # Backup existing .env if present
    if [[ -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        log "Backed up existing .env"
    fi
    
    log "Writing to: $ENV_FILE"
    
    # Ensure repo root exists
    mkdir -p "$(dirname "$ENV_FILE")"
    
    cat > "$ENV_FILE" << EOF
# =============================================================================
# AI Platform Configuration
# Generated by Script 1 on $(date)
# SOURCE OF TRUTH — All scripts source this file
# DO NOT EDIT MANUALLY — Re-run Script 1 to regenerate
# =============================================================================

# ── Core Paths ────────────────────────────────────────────────────────────────
MNT_BASE=${MNT_BASE}
REPO_ROOT=${REPO_ROOT}

# ── Network ───────────────────────────────────────────────────────────────────
DOMAIN=${DOMAIN}
HOST_IP=${HOST_IP}
BIFROST_SUBNET=${BIFROST_SUBNET}
BIFROST_GATEWAY=${BIFROST_GATEWAY}
BIFROST_MTU=${BIFROST_MTU}

# ── GPU ───────────────────────────────────────────────────────────────────────
GPU_TYPE=${GPU_TYPE}
OLLAMA_RUNTIME=${OLLAMA_RUNTIME}

# ── Portainer ─────────────────────────────────────────────────────────────────
PORTAINER_CONTAINER_NAME=${PORTAINER_CONTAINER_NAME}
PORTAINER_PORT=${PORTAINER_PORT}
PORTAINER_HTTP_PORT=${PORTAINER_HTTP_PORT}
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD}

# ── Ollama ────────────────────────────────────────────────────────────────────
OLLAMA_CONTAINER_NAME=${OLLAMA_CONTAINER_NAME}
OLLAMA_PORT=${OLLAMA_PORT}
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL:-}
OLLAMA_PULL_DEFAULT_MODEL=${OLLAMA_PULL_DEFAULT_MODEL}

# ── Open WebUI ────────────────────────────────────────────────────────────────
OPEN_WEBUI_CONTAINER_NAME=${OPEN_WEBUI_CONTAINER_NAME}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT}

# ── PostgreSQL ────────────────────────────────────────────────────────────────
POSTGRES_CONTAINER_NAME=${POSTGRES_CONTAINER_NAME}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
N8N_DB=${N8N_DB}
FLOWISE_DB=${FLOWISE_DB}

# ── Redis ─────────────────────────────────────────────────────────────────────
REDIS_CONTAINER_NAME=${REDIS_CONTAINER_NAME}
REDIS_PORT=${REDIS_PORT}
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── n8n ───────────────────────────────────────────────────────────────────────
N8N_CONTAINER_NAME=${N8N_CONTAINER_NAME}
N8N_PORT=${N8N_PORT}
N8N_WEBHOOK_URL=${N8N_WEBHOOK_URL}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# ── SearXNG ───────────────────────────────────────────────────────────────────
SEARXNG_CONTAINER_NAME=${SEARXNG_CONTAINER_NAME}
SEARXNG_PORT=${SEARXNG_PORT}
SEARXNG_SECRET_KEY=${SEARXNG_SECRET_KEY}

# ── Flowise ───────────────────────────────────────────────────────────────────
FLOWISE_CONTAINER_NAME=${FLOWISE_CONTAINER_NAME}
FLOWISE_PORT=${FLOWISE_PORT}
FLOWISE_USERNAME=${FLOWISE_USERNAME}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}

# ── Nginx ─────────────────────────────────────────────────────────────────────
ENABLE_NGINX=${ENABLE_NGINX}
NGINX_HTTP_PORT=${NGINX_HTTP_PORT:-80}
NGINX_HTTPS_PORT=${NGINX_HTTPS_PORT:-443}
EOF

    chmod 600 "$ENV_FILE"
    log ".env written and secured (chmod 600)"
}

# --------------------------------------------------------------------------
# Validate .env completeness
# --------------------------------------------------------------------------
validate_env() {
    section "Validating Configuration"
    
    local ENV_FILE="${REPO_ROOT}/.env"
    local required_vars=(
        "MNT_BASE" "DOMAIN" "HOST_IP"
        "BIFROST_SUBNET" "BIFROST_GATEWAY" "BIFROST_MTU"
        "PORTAINER_CONTAINER_NAME" "PORTAINER_PORT" "PORTAINER_ADMIN_PASSWORD"
        "OLLAMA_CONTAINER_NAME" "OLLAMA_PORT" "OLLAMA_RUNTIME"
        "OPEN_WEBUI_CONTAINER_NAME" "OPEN_WEBUI_PORT"
        "POSTGRES_CONTAINER_NAME" "POSTGRES_PORT" "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB"
        "REDIS_CONTAINER_NAME" "REDIS_PORT" "REDIS_PASSWORD"
        "N8N_CONTAINER_NAME" "N8N_PORT" "N8N_WEBHOOK_URL" "N8N_ENCRYPTION_KEY"
        "SEARXNG_CONTAINER_NAME" "SEARXNG_PORT" "SEARXNG_SECRET_KEY"
        "FLOWISE_CONTAINER_NAME" "FLOWISE_PORT" "FLOWISE_USERNAME" "FLOWISE_PASSWORD"
    )
    
    local missing=()
    
    # Source the written .env to validate
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing required variables in .env: ${missing[*]}"
    fi
    
    # Validate /mnt prefix
    if [[ "$MNT_BASE" != /mnt/* ]]; then
        fail "MNT_BASE must be under /mnt/ (current: $MNT_BASE)"
    fi
    
    # Validate subnet format
    if ! echo "$BIFROST_SUBNET" | grep -qP '^\d+\.\d+\.\d+\.\d+/\d+$'; then
        fail "BIFROST_SUBNET format invalid: $BIFROST_SUBNET"
    fi
    
    log "All required variables validated ✓"
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 1 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ Configuration collected interactively"
    echo "  ✓ .env written to: ${REPO_ROOT}/.env"
    echo "  ✓ All variables validated"
    echo ""
}

# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------
main() {
    local TENANT_ID=${1:-"default"}
    
    log "=== Script 1: Input Collector ==="
    log "Tenant: ${TENANT_ID}"
    
    # Claude Audit: /mnt writable check
    if [[ ! -w "/mnt" ]]; then
        fail "/mnt is not writable. Cannot proceed with deployment."
    fi
    
    detect_system
    check_prerequisites
    collect_configuration
    echo "  │  Configuration saved to .env                │"
    echo "  │                                             │"
    echo "  │  Next: System setup via Mission Control     │"
    echo "  │  This will:                                 │"
    echo "  │    • Install required packages              │"
    echo "  │    • Configure Docker daemon                │"
    echo "  │    • Create /mnt directory structure        │"
    echo "  │    • Generate service configuration files  │"
    echo "  └─────────────────────────────────────┘"
    echo ""
    
    prompt_yesno RUN_SETUP_NOW \
        "Run system setup now?" \
        "Y"
    if [[ "${RUN_SETUP_NOW}" == "true" ]]; then
        echo ""
        echo "  Invoking Mission Control (setup mode)..."
        echo ""
        bash "${SCRIPT_DIR}/3-configure-services.sh" --setup-only
    else
        echo ""
        echo "  Skipped. Run setup manually when ready:"
        echo "  bash scripts/3-configure-services.sh --setup-only"
        echo ""
        echo "  Then deploy:"
        echo "  bash scripts/2-deploy-services.sh"
        echo ""
    fi
}

main "$@"
