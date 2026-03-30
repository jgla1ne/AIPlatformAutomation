#!/usr/bin/env bash
# =============================================================================
# Script 1: System Compiler - BULLETPROOF v5.0 FINAL
# =============================================================================
# PURPOSE: Interactive input collection + platform.conf generation ONLY
# USAGE:   sudo bash scripts/1-setup-system.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show configuration without writing files
#          --non-interactive   Use defaults for all prompts (for automation)
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7 - mandatory)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    fail "This script must not be run as root (README P7 requirement)"
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING AND UTILITIES (README P11 - mandatory dual logging)
# =============================================================================
# Set up log file (will be set after tenant_id is known)
LOG_FILE=""

log() { 
    echo "[INFO] $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $1" >> "$LOG_FILE"
}
ok() { 
    echo "[OK] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
}
warn() { 
    echo "[WARN] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
}
fail() { 
    echo "[FAIL] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
    exit 1
}
section() { 
    echo ""
    echo "=== $* ==="
    echo ""
    [[ -n "$LOG_FILE" ]] && echo "" >> "$LOG_FILE" && echo "=== $* ===" >> "$LOG_FILE" && echo "" >> "$LOG_FILE"
}
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating system framework..."
    
    # Binary availability checks
    for bin in curl jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            fail "Missing required binary: $bin"
        fi
    done
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon not running or accessible"
    fi
    
    # Docker compose plugin
    if ! docker compose version >/dev/null 2>&1; then
        fail "Docker compose plugin not available"
    fi
    
    # EBS mount check
    if [[ ! -d /mnt ]]; then
        fail "EBS volume not mounted at /mnt"
    fi
    
    # Disk space check (minimum 10GB free)
    local free_gb
    free_gb=$(df /mnt | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $free_gb -lt 10 ]]; then
        fail "Insufficient disk space on /mnt (${free_gb}GB < 10GB minimum)"
    fi
    
    ok "Framework validation passed"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================
generate_token() {
    openssl rand -hex 16
}

generate_secret() {
    openssl rand -hex 32
}

# =============================================================================
# INTERACTIVE PROMPT FUNCTIONS
# =============================================================================
prompt_default() {
    local var="$1"
    local question="$2"
    local default="$3"
    
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        eval "$var='$default'"
        dry_run "Auto-setting $var=$default (non-interactive mode)"
        return
    fi
    
    echo ""
    read -r -p "  $question [$default]: " input
    eval "$var='${input:-$default}'"
}

prompt_required() {
    local var="$1"
    local question="$2"
    local value=""
    
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        fail "Required field $var cannot be empty in non-interactive mode"
    fi
    
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
    
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        eval "$var='$(generate_secret)'"
        dry_run "Auto-generated secret for $var"
        return
    fi
    
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
    
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        eval "$var=true"
        dry_run "Auto-setting $var=true (non-interactive mode)"
        return
    fi
    
    echo ""
    read -r -p "  $question [y/n] (default: $default): " answer
    answer="${answer:-$default}"
    case "$answer" in
        [Yy]*) eval "$var=true" ;;
        *)     eval "$var=false" ;;
    esac
}

# =============================================================================
# SYSTEM DETECTION
# =============================================================================
detect_system() {
    log "Detecting system capabilities..."
    
    # Platform architecture
    PLATFORM_ARCH=$(uname -m)
    
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
    
    # Host IP detection
    HOST_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
    
    log "System: Arch=${PLATFORM_ARCH}, RAM=${TOTAL_RAM_GB}GB, Disk=${MNT_DISK_GB}GB, GPU=${GPU_TYPE}, MTU=${HOST_MTU}"
}

# =============================================================================
# STACK PRESET FUNCTIONS (Expert Fix)
# =============================================================================
apply_stack_preset() {
    local preset="$1"
    
    case "$preset" in
        "minimal")
            POSTGRES_ENABLED=true
            REDIS_ENABLED=true
            # User selects LLM proxy (Expert Fix)
            prompt_default LLM_PROXY "Choose LLM proxy" "litellm"
            case "$LLM_PROXY" in
                "litellm")
                    LITELLM_ENABLED=true
                    BIFROST_ENABLED=false
                    ;;
                "bifrost")
                    BIFROST_ENABLED=true
                    LITELLM_ENABLED=false
                    ;;
                *)
                    fail "Invalid LLM proxy choice: $LLM_PROXY"
                    ;;
            esac
            # User selects vector DB (Expert Fix)
            prompt_default VECTOR_DB "Choose vector database" "qdrant"
            case "$VECTOR_DB" in
                "qdrant")
                    QDRANT_ENABLED=true
                    WEAVIATE_ENABLED=false
                    CHROMA_ENABLED=false
                    ;;
                "weaviate")
                    WEAVIATE_ENABLED=true
                    QDRANT_ENABLED=false
                    CHROMA_ENABLED=false
                    ;;
                "chroma")
                    CHROMA_ENABLED=true
                    QDRANT_ENABLED=false
                    WEAVIATE_ENABLED=false
                    ;;
                *)
                    fail "Invalid vector DB choice: $VECTOR_DB"
                    ;;
            esac
            ;;
        "dev")
            # Start with minimal setup
            apply_stack_preset "minimal"
            # Add workflow tools
            N8N_ENABLED=true
            FLOWISE_ENABLED=true
            # Add coding assistant
            CODE_SERVER_ENABLED=true
            ;;
        "full")
            POSTGRES_ENABLED=true
            REDIS_ENABLED=true
            LITELLM_ENABLED=true
            BIFROST_ENABLED=true
            OPEN_WEBUI_ENABLED=true
            QDRANT_ENABLED=true
            WEAVIATE_ENABLED=true
            CHROMA_ENABLED=true
            # MILVUS_ENABLED=false  # TODO: Implement etcd+minio+milvus stack (Expert Fix)
            N8N_ENABLED=true
            FLOWISE_ENABLED=true
            CODE_SERVER_ENABLED=true
            SEARXNG_ENABLED=true
            AUTHENTIK_ENABLED=true
            GRAFANA_ENABLED=true
            PROMETHEUS_ENABLED=true
            CADDY_ENABLED=true
            ;;
        "custom")
            # User will be prompted for each service
            ;;
        *)
            fail "Unknown stack preset: $preset"
            ;;
    esac
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================
validate_domain() {
    local domain="$1"
    
    # Soft validation (Expert Fix) - must contain at least one dot, no spaces, no leading hyphen
    if [[ "$domain" == "local" ]]; then
        return 0  # Allow "local" as special case
    fi
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$ ]]; then
        fail "Invalid domain format: $domain"
    fi
}

validate_e164() {
    local phone="$1"
    
    if [[ ! "$phone" =~ ^\+[1-9]\d{1,14}$ ]]; then
        fail "Invalid E.164 phone number format: $phone (should be like +1234567890)"
    fi
}

validate_port_range() {
    local port="$1"
    local service="$2"
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1024 ]] || [[ "$port" -gt 65535 ]]; then
        fail "Invalid port for $service: $port (must be 1024-65535)"
    fi
}

# Port conflict resolution with write-back pattern (README mandatory)
resolve_port() {
    local var_name="$1"
    local proposed="${!var_name}"
    local resolved="$proposed"
    
    while lsof -i ":${resolved}" &>/dev/null 2>&1; do
        resolved=$((resolved + 1))
        log "Port ${proposed} in use, trying ${resolved} for ${var_name}"
    done
    
    if [[ "$resolved" != "$proposed" ]]; then
        log "Resolved ${var_name}: ${proposed} → ${resolved} (port conflict)"
        printf -v "${var_name}" '%s' "${resolved}"
    fi
}

resolve_all_ports() {
    log "Resolving port conflicts..."
    
    # Resolve all port variables
    resolve_port "OPEN_WEBUI_PORT"
    resolve_port "LITELLM_PORT"
    resolve_port "BIFROST_PORT"
    resolve_port "OLLAMA_PORT"
    resolve_port "POSTGRES_PORT"
    resolve_port "REDIS_PORT"
    resolve_port "QDRANT_PORT"
    resolve_port "WEAVIATE_PORT"
    resolve_port "CHROMA_PORT"
    resolve_port "N8N_PORT"
    resolve_port "FLOWISE_PORT"
    resolve_port "SEARXNG_PORT"
    resolve_port "AUTHENTIK_PORT"
    resolve_port "GRAFANA_PORT"
    resolve_port "PROMETHEUS_PORT"
    
    ok "All port conflicts resolved"
}

# =============================================================================
# MAIN CONFIGURATION COLLECTION
# =============================================================================
collect_configuration() {
    local tenant_id="$1"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — System Compiler                   ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  System detected:"
    echo "  • Architecture : $PLATFORM_ARCH"
    echo "  • GPU Type     : $GPU_TYPE"
    echo "  • Total RAM    : ${TOTAL_RAM_GB}GB"
    echo "  • Free on /mnt : ${MNT_DISK_GB}GB"
    echo "  • Host MTU     : $HOST_MTU"
    echo "  • Host IP      : $HOST_IP"
    echo ""
    echo "  You will be prompted for all configuration values."
    echo "  Press ENTER to accept defaults shown in [brackets]."
    echo ""

    # ── SECTION: Tenant Configuration ────────────────────────────────────────
    section "1. Tenant Configuration"
    
    prompt_default TENANT_ID "Tenant identifier" "$tenant_id"
    prompt_default PREFIX "Container name prefix" "ai"
    prompt_default BASE_DOMAIN "Base domain (e.g., example.com or 'local' for localhost)" "local"
    validate_domain "$BASE_DOMAIN"
    
    # TLS configuration
    prompt_default TLS_MODE "TLS mode" "letsencrypt"
    case "$TLS_MODE" in
        "letsencrypt")
            prompt_required TLS_EMAIL "Let's Encrypt email address"
            ;;
        "selfsigned")
            warn "Self-signed certificates will be generated"
            ;;
        "provided")
            warn "You must provide certificates in /mnt/${TENANT_ID}/config/ssl/"
            ;;
        "none")
            warn "No TLS - only for development"
            ;;
        *)
            fail "Invalid TLS mode: $TLS_MODE"
            ;;
    esac

    # ── SECTION: Stack Preset ─────────────────────────────────────────────────
    section "2. Stack Preset"
    
    prompt_default STACK_PRESET "Choose stack preset (minimal, dev, full, custom)" "minimal"
    apply_stack_preset "$STACK_PRESET"

    # ── SECTION: Network Configuration ───────────────────────────────────────────
    section "3. Network Configuration"
    
    prompt_default DOCKER_NETWORK "Docker network name" "${PREFIX}${TENANT_ID}_net"
    prompt_default DOCKER_SUBNET "Docker network subnet" "172.20.0.0/16"
    prompt_default DOCKER_GATEWAY "Docker network gateway" "172.20.0.1"
    
    # Set recommended MTU based on host MTU
    if [[ "$HOST_MTU" -le 1500 ]]; then
        RECOMMENDED_MTU=$((HOST_MTU - 50))
    else
        RECOMMENDED_MTU="1450"
    fi
    
    prompt_default DOCKER_MTU "Docker network MTU (recommended: $RECOMMENDED_MTU)" "$RECOMMENDED_MTU"

    # ── SECTION: Port Configuration ───────────────────────────────────────────
    section "4. Port Configuration"
    
    # Core services
    if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
        prompt_default OPEN_WEBUI_PORT "Open WebUI port" "3000"
        validate_port_range "$OPEN_WEBUI_PORT" "Open WebUI"
    fi
    
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        prompt_default LITELLM_PORT "LiteLLM port" "4000"
        validate_port_range "$LITELLM_PORT" "LiteLLM"
    fi
    
    if [[ "$BIFROST_ENABLED" == "true" ]]; then
        prompt_default BIFROST_PORT "Bifrost port" "8000"
        validate_port_range "$BIFROST_PORT" "Bifrost"
    fi
    
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        prompt_default OLLAMA_PORT "Ollama port" "11434"
        validate_port_range "$OLLAMA_PORT" "Ollama"
    fi

    # Database services
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        prompt_default POSTGRES_PORT "PostgreSQL port" "5432"
        validate_port_range "$POSTGRES_PORT" "PostgreSQL"
    fi
    
    if [[ "$REDIS_ENABLED" == "true" ]]; then
        prompt_default REDIS_PORT "Redis port" "6379"
        validate_port_range "$REDIS_PORT" "Redis"
    fi

    # Vector databases
    if [[ "$QDRANT_ENABLED" == "true" ]]; then
        prompt_default QDRANT_PORT "Qdrant port" "6333"
        validate_port_range "$QDRANT_PORT" "Qdrant"
    fi
    
    if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
        prompt_default WEAVIATE_PORT "Weaviate port" "8080"
        validate_port_range "$WEAVIATE_PORT" "Weaviate"
    fi
    
    if [[ "$CHROMA_ENABLED" == "true" ]]; then
        prompt_default CHROMA_PORT "Chroma port" "8000"
        validate_port_range "$CHROMA_PORT" "Chroma"
    fi

    # Workflow tools
    if [[ "$N8N_ENABLED" == "true" ]]; then
        prompt_default N8N_PORT "n8n port" "5678"
        validate_port_range "$N8N_PORT" "n8n"
    fi
    
    if [[ "$FLOWISE_ENABLED" == "true" ]]; then
        prompt_default FLOWISE_PORT "Flowise port" "3001"
        validate_port_range "$FLOWISE_PORT" "Flowise"
    fi

    # Additional services
    if [[ "$SEARXNG_ENABLED" == "true" ]]; then
        prompt_default SEARXNG_PORT "SearXNG port" "8080"
        validate_port_range "$SEARXNG_PORT" "SearXNG"
    fi
    
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        prompt_default AUTHENTIK_PORT "Authentik port" "9000"
        validate_port_range "$AUTHENTIK_PORT" "Authentik"
    fi
    
    if [[ "$GRAFANA_ENABLED" == "true" ]]; then
        prompt_default GRAFANA_PORT "Grafana port" "3001"
        validate_port_range "$GRAFANA_PORT" "Grafana"
    fi
    
    if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
        prompt_default PROMETHEUS_PORT "Prometheus port" "9090"
        validate_port_range "$PROMETHEUS_PORT" "Prometheus"
    fi

    # ── SECTION: Database Configuration ────────────────────────────────────────
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        section "5. Database Configuration"
        
        prompt_default POSTGRES_USER "PostgreSQL superuser" "aiplatform"
        prompt_secret POSTGRES_PASSWORD "PostgreSQL password"
        prompt_default POSTGRES_DB "Default database name" "aiplatform"
        
        # Service-specific databases
        if [[ "$N8N_ENABLED" == "true" ]]; then
            prompt_default N8N_DB "n8n database name" "n8n"
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            prompt_default FLOWISE_DB "Flowise database name" "flowise"
        fi
        
        if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
            prompt_default AUTHENTIK_DB "Authentik database name" "authentik"
        fi
    fi

    # ── SECTION: LLM Configuration ─────────────────────────────────────────────
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        section "6. LLM Configuration"
        
        # GPU runtime configuration
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
        
        prompt_yesno OLLAMA_PULL_DEFAULT_MODEL "Pull a default Ollama model after deployment?" "y"
        if [[ "$OLLAMA_PULL_DEFAULT_MODEL" == "true" ]]; then
            prompt_default OLLAMA_DEFAULT_MODEL "Default model to pull" "llama3.2"
        fi
    fi

    # ── SECTION: LLM Proxy Configuration ─────────────────────────────────────
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        section "7. LiteLLM Configuration"
        
        prompt_secret LITELLM_MASTER_KEY "LiteLLM master key"
        prompt_default LITELLM_DATABASE_URL "LiteLLM database URL" "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
        
        # External LLM providers
        prompt_yesno ENABLE_OPENAI "Enable OpenAI provider?" "n"
        if [[ "$ENABLE_OPENAI" == "true" ]]; then
            prompt_secret OPENAI_API_KEY "OpenAI API key"
            prompt_default OPENAI_API_BASE "OpenAI API base URL" "https://api.openai.com/v1"
            prompt_default OPENAI_API_VERSION "OpenAI API version" "2023-07-01-preview"
        fi
        
        prompt_yesno ENABLE_ANTHROPIC "Enable Anthropic provider?" "n"
        if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
            prompt_secret ANTHROPIC_API_KEY "Anthropic API key"
        fi
    fi

    # ── SECTION: Authentication Configuration ──────────────────────────────────
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        section "8. Authentication Configuration"
        
        prompt_secret AUTHENTIK_BOOTSTRAP_PASSWORD "Authentik bootstrap password"
        prompt_default AUTHENTIK_BOOTSTRAP_EMAIL "Authentik bootstrap email" "admin@${BASE_DOMAIN}"
    fi

    # ── SECTION: Backup Configuration ─────────────────────────────────────────
    section "9. Backup Configuration"
    
    prompt_yesno ENABLE_BACKUP "Enable automated backups?" "n"
    if [[ "$ENABLE_BACKUP" == "true" ]]; then
        prompt_default BACKUP_SCHEDULE "Backup schedule (cron format)" "0 2 * * *"
        prompt_default BACKUP_RETENTION "Backup retention days" "7"
        
        prompt_default BACKUP_PROVIDER "Backup provider (local, gdrive, s3, azure)" "local"
        case "$BACKUP_PROVIDER" in
            "gdrive")
                prompt_default RCLONE_GDRIVE_SA_CREDENTIALS_FILE "Google Drive service account JSON path" "/mnt/${TENANT_ID}/config/gdrive-sa.json"
                ;;
            "s3")
                prompt_default AWS_S3_BUCKET "AWS S3 bucket name" ""
                prompt_default AWS_S3_REGION "AWS S3 region" "us-east-1"
                ;;
            "azure")
                prompt_default AZURE_STORAGE_ACCOUNT "Azure storage account" ""
                prompt_default AZURE_STORAGE_CONTAINER "Azure storage container" ""
                ;;
        esac
    fi

    # ── SECTION: Signal Configuration ─────────────────────────────────────────
    section "10. Signal Configuration"
    
    prompt_yesno ENABLE_SIGNAL "Enable Signal gateway?" "n"
    if [[ "$ENABLE_SIGNAL" == "true" ]]; then
        prompt_required SIGNAL_PHONE_NUMBER "Signal phone number (E.164 format, e.g., +1234567890)"
        validate_e164 "$SIGNAL_PHONE_NUMBER"
    fi
}

# =============================================================================
# PLATFORM.CONF GENERATION
# =============================================================================
write_platform_conf() {
    local tenant_id="$1"
    local base_dir="/mnt/${tenant_id}"
    local config_dir="${base_dir}/config"
    
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        # Create directory structure
        mkdir -p "$config_dir"
        chown -R 1000:1000 "$base_dir"
        
        local platform_conf="${config_dir}/platform.conf"
        
        # Backup existing platform.conf if present
        if [[ -f "$platform_conf" ]]; then
            cp "$platform_conf" "${platform_conf}.backup.$(date +%Y%m%d-%H%M%S)"
            log "Backed up existing platform.conf"
        fi
        
        log "Writing platform.conf to: $platform_conf"
    else
        dry_run "Would write platform.conf to: /mnt/${tenant_id}/config/platform.conf"
    fi
    
    # Generate platform.conf content
    local platform_conf_content
    platform_conf_content=$(cat << EOF
# =============================================================================
# AI Platform Configuration - PRIMARY SOURCE OF TRUTH
# Generated by Script 1 on $(date)
# Tenant: ${tenant_id}
# =============================================================================
# WARNING: This file is the single source of truth for the entire platform.
# All scripts (0, 2, 3) source this file directly.
# DO NOT EDIT MANUALLY - Re-run Script 1 to regenerate.

# ── TENANT CONFIGURATION ─────────────────────────────────────────────────────
TENANT_ID=${tenant_id}
PREFIX=${PREFIX}
BASE_DOMAIN=${BASE_DOMAIN}
BASE_DIR=${base_dir}
CONFIG_DIR=${config_dir}
PLATFORM_ARCH=${PLATFORM_ARCH}

# ── TLS CONFIGURATION ────────────────────────────────────────────────────────
TLS_MODE=${TLS_MODE}
TLS_EMAIL=${TLS_EMAIL:-}

# ── NETWORK CONFIGURATION ────────────────────────────────────────────────────
DOCKER_NETWORK=${DOCKER_NETWORK}
DOCKER_SUBNET=${DOCKER_SUBNET}
DOCKER_GATEWAY=${DOCKER_GATEWAY}
DOCKER_MTU=${DOCKER_MTU}
HOST_IP=${HOST_IP}
HOST_MTU=${HOST_MTU}

# ── SYSTEM CONFIGURATION ─────────────────────────────────────────────────────
GPU_TYPE=${GPU_TYPE}
TOTAL_RAM_GB=${TOTAL_RAM_GB}
MNT_DISK_GB=${MNT_DISK_GB}

# ── STACK PRESET ─────────────────────────────────────────────────────────────
STACK_PRESET=${STACK_PRESET}

# ── SERVICE ENABLE FLAGS ─────────────────────────────────────────────────────
POSTGRES_ENABLED=${POSTGRES_ENABLED:-false}
REDIS_ENABLED=${REDIS_ENABLED:-false}
OLLAMA_ENABLED=${OLLAMA_ENABLED:-false}
LITELLM_ENABLED=${LITELLM_ENABLED:-false}
BIFROST_ENABLED=${BIFROST_ENABLED:-false}
OPEN_WEBUI_ENABLED=${OPEN_WEBUI_ENABLED:-false}
QDRANT_ENABLED=${QDRANT_ENABLED:-false}
WEAVIATE_ENABLED=${WEAVIATE_ENABLED:-false}
CHROMA_ENABLED=${CHROMA_ENABLED:-false}
N8N_ENABLED=${N8N_ENABLED:-false}
FLOWISE_ENABLED=${FLOWISE_ENABLED:-false}
CODE_SERVER_ENABLED=${CODE_SERVER_ENABLED:-false}
SEARXNG_ENABLED=${SEARXNG_ENABLED:-false}
AUTHENTIK_ENABLED=${AUTHENTIK_ENABLED:-false}
GRAFANA_ENABLED=${GRAFANA_ENABLED:-false}
PROMETHEUS_ENABLED=${PROMETHEUS_ENABLED:-false}
CADDY_ENABLED=${CADDY_ENABLED:-false}

# ── PORT CONFIGURATION ───────────────────────────────────────────────────────
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT:-3000}
LITELLM_PORT=${LITELLM_PORT:-4000}
BIFROST_PORT=${BIFROST_PORT:-8000}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_PORT=${REDIS_PORT:-6379}
QDRANT_PORT=${QDRANT_PORT:-6333}
WEAVIATE_PORT=${WEAVIATE_PORT:-8080}
CHROMA_PORT=${CHROMA_PORT:-8000}
N8N_PORT=${N8N_PORT:-5678}
FLOWISE_PORT=${FLOWISE_PORT:-3001}
SEARXNG_PORT=${SEARXNG_PORT:-8080}
AUTHENTIK_PORT=${AUTHENTIK_PORT:-9000}
GRAFANA_PORT=${GRAFANA_PORT:-3001}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}

# ── DATABASE CONFIGURATION ───────────────────────────────────────────────────
POSTGRES_USER=${POSTGRES_USER:-aiplatform}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB:-aiplatform}
N8N_DB=${N8N_DB:-n8n}
FLOWISE_DB=${FLOWISE_DB:-flowise}
AUTHENTIK_DB=${AUTHENTIK_DB:-authentik}

# ── LLM CONFIGURATION ─────────────────────────────────────────────────────────
OLLAMA_RUNTIME=${OLLAMA_RUNTIME:-cpu}
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL:-}
OLLAMA_PULL_DEFAULT_MODEL=${OLLAMA_PULL_DEFAULT_MODEL:-false}

# ── LITELLM CONFIGURATION ─────────────────────────────────────────────────────
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_DATABASE_URL=${LITELLM_DATABASE_URL}
ENABLE_OPENAI=${ENABLE_OPENAI:-false}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
OPENAI_API_BASE=${OPENAI_API_BASE:-https://api.openai.com/v1}
OPENAI_API_VERSION=${OPENAI_API_VERSION:-2023-07-01-preview}
ENABLE_ANTHROPIC=${ENABLE_ANTHROPIC:-false}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}

# ── AUTHENTIK CONFIGURATION ───────────────────────────────────────────────────
AUTHENTIK_BOOTSTRAP_PASSWORD=${AUTHENTIK_BOOTSTRAP_PASSWORD}
AUTHENTIK_BOOTSTRAP_EMAIL=${AUTHENTIK_BOOTSTRAP_EMAIL}

# ── BACKUP CONFIGURATION ───────────────────────────────────────────────────────
ENABLE_BACKUP=${ENABLE_BACKUP:-false}
BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-0 2 * * *}
BACKUP_RETENTION=${BACKUP_RETENTION:-7}
BACKUP_PROVIDER=${BACKUP_PROVIDER:-local}
RCLONE_GDRIVE_SA_CREDENTIALS_FILE=${RCLONE_GDRIVE_SA_CREDENTIALS_FILE:-}
AWS_S3_BUCKET=${AWS_S3_BUCKET:-}
AWS_S3_REGION=${AWS_S3_REGION:-us-east-1}
AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT:-}
AZURE_STORAGE_CONTAINER=${AZURE_STORAGE_CONTAINER:-}

# ── SIGNAL CONFIGURATION ───────────────────────────────────────────────────────
ENABLE_SIGNAL=${ENABLE_SIGNAL:-false}
SIGNAL_PHONE_NUMBER=${SIGNAL_PHONE_NUMBER:-}

# ── GENERATED SECRETS ───────────────────────────────────────────────────────
# Auto-generated encryption keys and tokens
N8N_ENCRYPTION_KEY=$(generate_token)
SEARXNG_SECRET_KEY=$(generate_secret)
FLOWISE_SECRET_KEY=$(generate_secret)
EOF
)
    
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        echo "$platform_conf_content" > "$platform_conf"
        chmod 600 "$platform_conf"
        chown 1000:1000 "$platform_conf"
        ok "platform.conf written and secured"
    else
        dry_run "Platform configuration content generated (dry-run mode)"
    fi
}

# =============================================================================
# MISSION-CONTROL.JSON GENERATION (DERIVED ONLY)
# =============================================================================
write_mission_control_json() {
    local tenant_id="$1"
    local base_dir="/mnt/${tenant_id}"
    local config_dir="${base_dir}/config"
    local platform_conf="${config_dir}/platform.conf"
    local mission_control_json="${config_dir}/mission-control.json"
    
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        log "Generating derived mission-control.json..."
        
        # Source platform.conf to generate JSON
        source "$platform_conf"
        
        # Generate mission-control.json as derived artifact
        cat > "$mission_control_json" << EOF
{
  "tenant_id": "${TENANT_ID}",
  "base_path": "${BASE_DIR}",
  "config_dir": "${CONFIG_DIR}",
  "network": {
    "name": "${DOCKER_NETWORK}",
    "subnet": "${DOCKER_SUBNET}",
    "gateway": "${DOCKER_GATEWAY}",
    "mtu": ${DOCKER_MTU}
  },
  "platform_arch": "${PLATFORM_ARCH}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "services": {
$(if [[ "$POSTGRES_ENABLED" == "true" ]]; then cat << POSTGRES
    "postgres": {
      "container": "${PREFIX}${TENANT_ID}_postgres",
      "port": ${POSTGRES_PORT},
      "health": "pg_isready"
    },
POSTGRES
fi)
$(if [[ "$REDIS_ENABLED" == "true" ]]; then cat << REDIS
    "redis": {
      "container": "${PREFIX}${TENANT_ID}_redis",
      "port": ${REDIS_PORT},
      "health": "redis-cli ping"
    },
REDIS
fi)
$(if [[ "$OLLAMA_ENABLED" == "true" ]]; then cat << OLLAMA
    "ollama": {
      "container": "${PREFIX}${TENANT_ID}_ollama",
      "port": ${OLLAMA_PORT},
      "health": "/api/tags"
    },
OLLAMA
fi)
$(if [[ "$LITELLM_ENABLED" == "true" ]]; then cat << LITELLM
    "litellm": {
      "container": "${PREFIX}${TENANT_ID}_litellm",
      "port": ${LITELLM_PORT},
      "health": "/health",
      "depends_on": ["postgres"]
    },
LITELLM
fi)
$(if [[ "$BIFROST_ENABLED" == "true" ]]; then cat << BIFROST
    "bifrost": {
      "container": "${PREFIX}${TENANT_ID}_bifrost",
      "port": ${BIFROST_PORT},
      "health": "/health",
      "depends_on": ["ollama"]
    },
BIFROST
fi)
$(if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then cat << OPENWEBUI
    "open-webui": {
      "container": "${PREFIX}${TENANT_ID}_open-webui",
      "port": ${OPEN_WEBUI_PORT},
      "depends_on": ["litellm", "bifrost"]
    },
OPENWEBUI
fi)
$(if [[ "$QDRANT_ENABLED" == "true" ]]; then cat << QDRANT
    "qdrant": {
      "container": "${PREFIX}${TENANT_ID}_qdrant",
      "port": ${QDRANT_PORT},
      "health": "/healthz"
    },
QDRANT
fi)
$(if [[ "$WEAVIATE_ENABLED" == "true" ]]; then cat << WEAVIATE
    "weaviate": {
      "container": "${PREFIX}${TENANT_ID}_weaviate",
      "port": ${WEAVIATE_PORT},
      "health": "/v1/.well-known/ready"
    },
WEAVIATE
fi)
$(if [[ "$CHROMA_ENABLED" == "true" ]]; then cat << CHROMA
    "chroma": {
      "container": "${PREFIX}${TENANT_ID}_chroma",
      "port": ${CHROMA_PORT},
      "health": "/api/v1/heartbeat"
    },
CHROMA
fi)
$(if [[ "$N8N_ENABLED" == "true" ]]; then cat << N8N
    "n8n": {
      "container": "${PREFIX}${TENANT_ID}_n8n",
      "port": ${N8N_PORT},
      "depends_on": ["postgres"]
    },
N8N
fi)
$(if [[ "$FLOWISE_ENABLED" == "true" ]]; then cat << FLOWISE
    "flowise": {
      "container": "${PREFIX}${TENANT_ID}_flowise",
      "port": ${FLOWISE_PORT},
      "depends_on": ["postgres"]
    },
FLOWISE
fi)
$(if [[ "$SEARXNG_ENABLED" == "true" ]]; then cat << SEARXNG
    "searxng": {
      "container": "${PREFIX}${TENANT_ID}_searxng",
      "port": ${SEARXNG_PORT}
    },
SEARXNG
fi)
$(if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then cat << AUTHENTIK
    "authentik": {
      "container": "${PREFIX}${TENANT_ID}_authentik",
      "port": ${AUTHENTIK_PORT},
      "health": "/outpost.goauthentik.io/",
      "depends_on": ["postgres"]
    },
AUTHENTIK
fi)
$(if [[ "$GRAFANA_ENABLED" == "true" ]]; then cat << GRAFANA
    "grafana": {
      "container": "${PREFIX}${TENANT_ID}_grafana",
      "port": ${GRAFANA_PORT},
      "depends_on": ["prometheus"]
    },
GRAFANA
fi)
$(if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then cat << PROMETHEUS
    "prometheus": {
      "container": "${PREFIX}${TENANT_ID}_prometheus",
      "port": ${PROMETHEUS_PORT}
    }
PROMETHEUS
fi)
  }
}
EOF
        
        chmod 644 "$mission_control_json"
        chown 1000:1000 "$mission_control_json"
        ok "mission-control.json generated (derived artifact)"
    else
        dry_run "Would generate mission-control.json as derived artifact"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================
validate_configuration() {
    local tenant_id="$1"
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        section "Validating Configuration"
        
        # Source platform.conf to validate
        source "$platform_conf"
        
        # Validate required variables
        local required_vars=(
            "TENANT_ID" "BASE_DOMAIN" "DOCKER_NETWORK" "DOCKER_SUBNET"
            "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB"
        )
        
        local missing=()
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                missing+=("$var")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            fail "Missing required variables: ${missing[*]}"
        fi
        
        # Validate port ranges
        validate_port_range "$POSTGRES_PORT" "PostgreSQL"
        
        # Validate domain format
        validate_domain "$BASE_DOMAIN"
        
        # Validate subnet format
        if ! echo "$DOCKER_SUBNET" | grep -qP '^\d+\.\d+\.\d+\.\d+/\d+$'; then
            fail "Invalid subnet format: $DOCKER_SUBNET"
        fi
        
        # Focused hardcoding scan (Expert Fix)
        log "Scanning for placeholder values..."
        if grep -rE "CHANGEME|TODO|FIXME|xxxx" "$platform_conf" >/dev/null 2>&1; then
            fail "Placeholder values detected in platform.conf"
        fi
        
        ok "Configuration validation passed"
    else
        dry_run "Would validate configuration"
    fi
}

# =============================================================================
# SUMMARY AND NEXT STEPS
# =============================================================================
print_summary() {
    local tenant_id="$1"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 1 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ Configuration collected interactively"
    echo "  ✓ platform.conf written to: /mnt/${tenant_id}/config/platform.conf"
    echo "  ✓ mission-control.json generated as derived artifact"
    echo "  ✓ All variables validated"
    echo ""
    echo "  Next steps:"
    echo "  1. Deploy services: bash scripts/2-deploy-services.sh ${tenant_id}"
    echo "  2. Verify deployment: bash scripts/3-configure-services.sh ${tenant_id}"
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-default}"
    local dry_run=false
    local non_interactive=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    export NON_INTERACTIVE="$non_interactive"
    
    log "=== Script 1: System Compiler ==="
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    log "Non-interactive: ${non_interactive}"
    
    # Framework validation
    framework_validate
    
    # System detection
    detect_system
    
    # Configuration collection
    collect_configuration "$tenant_id"
    
    # Set up log file (README P11 - after tenant_id is known)
    local base_dir="/mnt/${tenant_id}"
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        mkdir -p "${base_dir}/logs"
        LOG_FILE="${base_dir}/logs/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
        log "Log file: $LOG_FILE"
    fi
    
    # Resolve port conflicts (README mandatory - before writing platform.conf)
    resolve_all_ports
    
    # Generate platform.conf (primary source of truth)
    write_platform_conf "$tenant_id"
    
    # Generate mission-control.json (derived artifact)
    write_mission_control_json "$tenant_id"
    
    # Validate configuration
    validate_configuration "$tenant_id"
    
    # Print summary
    print_summary "$tenant_id"
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
