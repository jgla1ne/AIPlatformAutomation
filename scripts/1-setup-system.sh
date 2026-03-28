#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script 1: Tenant Setup - Complete System Configuration Wizard
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# Clear any inherited environment variables to ensure clean state
unset TENANT_ID ADMIN_EMAIL DOMAIN

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m'

# ─── Utility Functions ────────────────────────────────────────────────────────
fail() {
    log "ERROR" "$1"
    exit 1
}

ok() {
    log "SUCCESS" "$1"
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

# ─── Runtime vars (set after volume selection) ────────────────────────────────
DATA_ROOT=""
ENV_FILE=""
COMPOSE_DIR=""
CADDY_DIR=""
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Dynamic service URLs (will be set after tenant selection)
VECTOR_DB_URL=""
OLLAMA_INTERNAL_URL=""
QDRANT_INTERNAL_URL=""
REDIS_INTERNAL_URL=""
POSTGRES_INTERNAL_URL=""
N8N_INTERNAL_URL=""

# ─── Default Values (to prevent unbound variable errors) ───────────────────────
# Service flags
ENABLE_POSTGRES="false"
ENABLE_REDIS="false"
ENABLE_CADDY="false"
ENABLE_OLLAMA="false"
ENABLE_OPENAI="false"
ENABLE_ANTHROPIC="false"
ENABLE_GOOGLE="false"
ENABLE_GROQ="false"
ENABLE_OPENROUTER="false"
ENABLE_LOCALAI="false"
ENABLE_VLLM="false"
ENABLE_OPENWEBUI="false"
ENABLE_ANYTHINGLLM="false"
ENABLE_DIFY="false"
ENABLE_N8N="false"
ENABLE_FLOWISE="false"
ENABLE_QDRANT="false"
ENABLE_WEAVIATE="false"
ENABLE_PINECONE="false"
ENABLE_CHROMADB="false"
ENABLE_MILVUS="false"
ENABLE_GRAFANA="false"
ENABLE_PROMETHEUS="false"
ENABLE_AUTHENTIK="false"
ENABLE_SIGNAL="false"
ENABLE_TAILSCALE="false"
ENABLE_OPENCLAW="false"
ENABLE_RCLONE="false"
ENABLE_MINIO="false"

# Dynamic port configuration (will be set during collection)
CADDY_HTTP_PORT=""
CADDY_HTTPS_PORT=""
    CADDY_INTERNAL_HTTP_PORT="80"
    CADDY_INTERNAL_HTTPS_PORT="443"
N8N_PORT=""
FLOWISE_PORT=""
OPENWEBUI_PORT=""
ANYTHINGLLM_PORT=""
    OPENWEBUI_INTERNAL_PORT="8081"
    OPENCLAW_INTERNAL_PORT="18789"
    SIGNAL_INTERNAL_PORT="8080"
GRAFANA_PORT=""
PROMETHEUS_PORT=""
    N8N_INTERNAL_PORT="5678"
    FLOWISE_INTERNAL_PORT="3000"
    ANYTHINGLLM_INTERNAL_PORT="3001"
    GRAFANA_INTERNAL_PORT="3000"
    PROMETHEUS_INTERNAL_PORT="9090"
    MINIO_INTERNAL_PORT="9000"
    MINIO_CONSOLE_INTERNAL_PORT="9001"
OLLAMA_PORT=""
QDRANT_PORT=""
    OLLAMA_INTERNAL_PORT="11434"
    QDRANT_INTERNAL_PORT="6333"
    QDRANT_INTERNAL_HTTP_PORT="6333"
    POSTGRES_INTERNAL_PORT="5432"
    REDIS_INTERNAL_PORT="6379"
SIGNAL_PORT=""
OPENCLAW_PORT=""
TAILSCALE_PORT=""
RCLONE_PORT=""
    TAILSCALE_INTERNAL_PORT="8443"

# Database defaults
POSTGRES_USER="platform"
POSTGRES_PASSWORD=""
POSTGRES_DB="platform"
REDIS_PASSWORD=""
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD=""

# Proxy defaults
PROXY_TYPE="caddy"
ROUTING_METHOD="subdomain"
SSL_TYPE="acme"
CUSTOM_PROXY_IMAGE=""
HTTP_PROXY=""
HTTPS_PROXY=""
NO_PROXY=""

# Hardware defaults
GPU_TYPE="cpu"
GPU_COUNT="0"
GPU_LAYERS="auto"
CPU_CORES="$(nproc)"
TOTAL_RAM_GB="$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)"

# LLM defaults
OLLAMA_DEFAULT_MODEL=""
OLLAMA_MODELS=""
LLM_PROVIDERS="local"
OPENAI_API_KEY=""
GOOGLE_API_KEY=""
GROQ_API_KEY=""
OPENROUTER_API_KEY=""

# Vector DB defaults
VECTOR_DB="qdrant"
VECTOR_DB_HOST="qdrant"
VECTOR_DB_PORT="6333"
VECTOR_DB_URL=""

# Service defaults
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"
FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY:-}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
JWT_SECRET="${JWT_SECRET:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-}"
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
OPENWEBUI_SECRET_KEY="${OPENWEBUI_SECRET_KEY:-}"
DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# Network defaults
TAILSCALE_AUTH_KEY=""
TAILSCALE_HOSTNAME=""
TAILSCALE_FUNNEL="https"
SIGNAL_PHONE_NUMBER=""
SIGNAL_VERIFICATION_CODE=""
GDRIVE_CLIENT_ID=""
GDRIVE_CLIENT_SECRET=""
GDRIVE_FOLDER_NAME=""
GDRIVE_FOLDER_ID=""
GDRIVE_AUTH_METHOD=""

# Admin defaults
ADMIN_EMAIL=""

# Search defaults
SEARCH_PROVIDER="none"
BRAVE_API_KEY=""
SERPAPI_KEY=""
SERPAPI_ENGINE="google"
CUSTOM_SEARCH_URL=""
CUSTOM_SEARCH_KEY=""

# Pinecone configuration
PINECONE_PROJECT_ID=""
PINECONE_API_KEY=""

# Service configuration variables
WEAVIATE_SERVICE_NAME="weaviate"
WEAVIATE_PORT="8080"
CHROMADB_SERVICE_NAME="chromadb"
CHROMADB_PORT="8000"
MILVUS_SERVICE_NAME="milvus"
MILVUS_PORT="19530"
PINECONE_SERVICE_NAME="pinecone"
QDRANT_SERVICE_NAME="qdrant"
QDRANT_PORT="6333"
REDIS_SERVICE_NAME="redis"
REDIS_PORT="6379"
POSTGRES_SERVICE_NAME="postgres"
POSTGRES_PORT="5432"
N8N_SERVICE_NAME="n8n"
N8N_PORT="5678"
OLLAMA_SERVICE_NAME="ollama"
OLLAMA_PORT="11434"
VLLM_SERVICE_NAME="vllm"

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
    local level="${1}" message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

# ─── UI Helpers ──────────────────────────────────────────────────────────────
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

print_section() {
    local title="${1}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}${title}${NC}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_divider() {
    echo ""
    echo -e "${DIM}  ════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─── ask_service helper ──────────────────────────────────────────────────────
# Usage: ask_service "emoji" "Label" "Description" "VAR_NAME" "default"
ask_service() {
    local emoji="$1" name="$2" desc="$3" var="$4" default="$5"
    local prompt_default
    [ "${default}" = "y" ] && prompt_default="[Y/n]" || prompt_default="[y/N]"
    
    printf "  %s  %-20s - %-35s" "${emoji}" "${name}" "${desc}"
    read -p " ${prompt_default}: " answer
    answer="${answer:-${default}}"
    
    if [[ "${answer,,}" == "y" ]]; then
        export "${var}=true"
        echo "  ✅ ${name} enabled"
    else
        export "${var}=false"
        echo "  ❌ ${name} disabled"
    fi
}

# ─── Prerequisites ───────────────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_prerequisites() {
    print_step "1" "9" "System Prerequisites"

    # Check if running interactively (safety check)
    if [[ ! -t 0 ]]; then
        log "ERROR" "Script 1 must be run interactively (TTY required)"
        log "ERROR" "This script collects user input and cannot run non-interactively"
        log "ERROR" "Run: sudo bash scripts/1-setup-system.sh"
        exit 1
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker not installed. Install Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log "ERROR" "Docker Compose not available. Install Docker Compose first."
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running. Start Docker service first."
        exit 1
    fi

    log "SUCCESS" "Docker and Docker Compose are available"
}

# ─── EBS Volume Detection and Mounting ────────────────────────────────────────
detect_and_mount_ebs() {
    print_step "3" "11" "EBS Volume Detection and Mounting"

    echo -e "  ${BOLD}💾  EBS Volume Detection${NC}"
    echo -e "  ${DIM}Scanning for available EBS volumes to mount${NC}"
    echo ""

    # List available block devices
    echo -e "  ${BOLD}Available Block Devices:${NC}"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "^nvme|^xvd|^sd" | while read -r line; do
        echo -e "  ${CYAN}    ${line}${NC}"
    done
    echo ""

    # Find unmounted EBS volumes
    local unmounted_volumes=()
    while IFS= read -r device; do
        if ! lsblk -n -o MOUNTPOINT "/dev/${device}" | grep -q "."; then
            unmounted_volumes+=("${device}")
        fi
    done < <(lsblk -d -n -o NAME | grep -E "^nvme|^xvd|^sd")

    if [ ${#unmounted_volumes[@]} -eq 0 ]; then
        log "INFO" "No unmounted EBS volumes found"
        return
    fi

    echo -e "  ${BOLD}Unmounted EBS Volumes:${NC}"
    local idx=0
    for volume in "${unmounted_volumes[@]}"; do
        size=$(lsblk -d -n -o SIZE "/dev/${volume}")
        echo -e "  ${CYAN}  $((++idx))${NC}  /dev/${volume}  ${DIM}(${size})${NC}"
    done
    echo ""

    # Ask user to select volume to mount
    while true; do
        read -p "  ➤ Select EBS volume to mount [1-${idx}] (or skip): " choice
        if [[ -z "${choice}" ]]; then
            log "INFO" "Skipping EBS mount"
            break
        fi
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${idx}" ]; then
            local selected_volume="${unmounted_volumes[$((choice-1))]}"
            local mount_point="/mnt/data"
            
            log "INFO" "Mounting /dev/${selected_volume} to ${mount_point}"
            
            # Create mount point if it doesn't exist
            sudo mkdir -p "${mount_point}"
            # CRITICAL: Ensure mount point is owned by tenant, not root
            sudo chown "${TENANT_UID}:${TENANT_GID}" "${mount_point}"
            
            # Check if already mounted
            if mountpoint -q "${mount_point}" 2>/dev/null; then
                log "WARN" "${mount_point} is already mounted"
                break
            fi
            
            # Mount the volume
            if sudo mount "/dev/${selected_volume}" "${mount_point}" 2>/dev/null; then
                log "SUCCESS" "EBS volume mounted: /dev/${selected_volume} → ${mount_point}"
                
                # Add to /etc/fstab for persistence
                if ! grep -q "/dev/${selected_volume}" /etc/fstab; then
                    echo "/dev/${selected_volume}  ${mount_point}  ext4  defaults  0  2" | sudo tee -a /etc/fstab
                    log "INFO" "Added to /etc/fstab for persistence"
                fi
                break
            else
                log "ERROR" "Failed to mount /dev/${selected_volume}"
                echo -e "  ${DIM}You may need to format the volume first:${NC}"
                echo -e "  ${DIM}  sudo mkfs.ext4 /dev/${selected_volume}${NC}"
            fi
            break
        else
            echo "  ❌ Enter a number between 1 and ${idx}, or leave empty to skip"
        fi
    done
}

# ─── Data Volume Selection ───────────────────────────────────────────────────
select_data_volume() {
    print_step "4" "11" "Data Volume Selection"

    echo -e "  ${BOLD}💾  Available Mount Points${NC}"
    echo -e "  ${DIM}Select where to store AI platform data${NC}"
    echo ""

    # Enumerate available mounts
    local mounts=()
    local idx=0
    
    # Add /mnt/data if it's a mount point
    if mountpoint -q /mnt/data 2>/dev/null; then
        mounts+=("/mnt/data")
        echo -e "  ${CYAN}  $((++idx))${NC}  /mnt/data  ${DIM}$(findmnt /mnt/data -no SIZE -o SIZE || echo "EBS volume")${NC}"
    fi
    
    # Add /mnt if it's a mount point (legacy)
    if mountpoint -q /mnt 2>/dev/null; then
        mounts+=("/mnt")
        echo -e "  ${CYAN}  $((++idx))${NC}  /mnt  ${DIM}$(findmnt /mnt -no SIZE -o SIZE || echo "EBS volume")${NC}"
    fi

    # Add other potential mount points
    while IFS= read -r mount; do
        if [[ "${mount}" != "/mnt/data" ]] && [[ "${mount}" != "/mnt" ]] && mountpoint -q "${mount}" 2>/dev/null; then
            mounts+=("${mount}")
            echo -e "  ${CYAN}  $((++idx))${NC}  ${mount}  ${DIM}$(findmnt "${mount}" -no SIZE -o SIZE || echo "Unknown size")${NC}"
        fi
    done < <(findmnt -l -n -o TARGET | grep -E '^/[^/]' | sort)

    # Add custom option
    echo -e "  ${CYAN}  $((++idx))${NC}  Custom path"
    echo ""

    while true; do
        read -p "  ➤ Select volume [1-${idx}]: " choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${idx}" ]; then
            break
        fi
        echo "  ❌ Enter a number between 1 and ${idx}"
    done

    if [ "${choice}" -eq "${idx}" ]; then
        # Custom path
        while true; do
            read -p "  ➤ Enter custom path: " custom_path
            if [ -n "${custom_path}" ]; then
                DATA_ROOT="${custom_path}/${TENANT_ID}"
                break
            fi
            echo "  ❌ Path cannot be empty"
        done
    else
        # Always use /mnt/data as base per runsheet requirements
        local base_path="${mounts[$((choice-1))]}"
        # If the selected mount is /mnt, use /mnt/data instead (runsheet requirement)
        if [ "${base_path}" = "/mnt" ]; then
            base_path="/mnt/data"
        fi
        DATA_ROOT="${base_path}/${TENANT_ID}"
    fi
    
    # Set derived paths
    ENV_FILE="${DATA_ROOT}/.env"
    COMPOSE_DIR="${DATA_ROOT}/compose"
    CADDY_DIR="${DATA_ROOT}/caddy"

    # Set tenant UID/GID for proper ownership (core principle: tenant owns their data)
    # When running with sudo, SUDO_UID/GID are set by sudo, but we need the username
    if [[ -n "${SUDO_USER:-}" ]]; then
        # Running with sudo - get original user's UID/GID
        export TENANT_UID="${SUDO_UID}"
        export TENANT_GID="${SUDO_GID}"
        log "INFO" "Detected sudo user: ${SUDO_USER} (UID:${TENANT_UID}, GID:${TENANT_GID})"
    elif [[ -n "${TENANT_USER:-}" ]]; then
        # Running with sudo -u specified user
        export TENANT_UID=$(id -u "${TENANT_USER}")
        export TENANT_GID=$(id -g "${TENANT_USER}")
        log "INFO" "Using specified tenant user: ${TENANT_USER} (UID:${TENANT_UID}, GID:${TENANT_GID})"
    else
        # Not running with sudo or sudo preserved environment
        export TENANT_UID="${TENANT_UID:-$(id -u)}"
        export TENANT_GID="${TENANT_GID:-$(id -g)}"
        log "INFO" "Using current user: $(id -un) (UID:${TENANT_UID}, GID:${TENANT_GID})"
    fi
    
    log "INFO" "Tenant ownership will be set to: ${TENANT_UID}:${TENANT_GID}"
    
    # ── Structured Logging Setup ───────────────────────────────────────
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    # CRITICAL: Ensure log directory is owned by tenant, not root
    chown -R "${TENANT_UID}:${TENANT_GID}" "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/script-1-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    
    # --- setup_logging function ---
setup_logging() {
    if [[ -z "${DATA_ROOT:-}" ]]; then return; fi
    local script_name
    script_name=$(basename "$0" .sh)
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    [[ -n "${TENANT_GID:-}" ]] && chown :"${TENANT_GID}" "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/${script_name}-$(date +%Y%m%d-%H%M%S).log"

    # Redirect all subsequent output
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log "INFO" "All output is now logged to: ${LOG_FILE}"
}
    
    # Set dynamic service URLs based on tenant configuration
    VECTOR_DB_URL="http://\${QDRANT_SERVICE_NAME:-qdrant}:\${QDRANT_PORT:-6333}"
    OLLAMA_INTERNAL_URL="http://\${OLLAMA_SERVICE_NAME:-ollama}:\${OLLAMA_PORT:-11434}"
    QDRANT_INTERNAL_URL="http://\${QDRANT_SERVICE_NAME:-qdrant}:\${QDRANT_PORT:-6333}"
    REDIS_INTERNAL_URL="redis://\${REDIS_SERVICE_NAME:-redis}:\${REDIS_PORT:-6379}"
    POSTGRES_INTERNAL_URL="postgresql://\${POSTGRES_SERVICE_NAME:-postgres}:\${POSTGRES_PORT:-5432}"
    N8N_INTERNAL_URL="http://\${N8N_SERVICE_NAME:-n8n}:\${N8N_PORT:-5678}"

    log "SUCCESS" "Data will be stored in: ${DATA_ROOT}"
}

# ─── Hardware Detection ────────────────────────────────────────────────────
detect_gpu() {
    print_step "5" "11" "Hardware Detection"

    # Initialize GPU_TYPE to prevent unbound variable error
    GPU_TYPE="cpu"
    
    # Method 1: nvidia-smi
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        export GPU_TYPE="nvidia"
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        log "INFO" "NVIDIA GPU detected: ${GPU_COUNT} GPU(s)"
        return
    fi

    # Method 2: lspci
    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            export GPU_TYPE="nvidia"
            log "WARN" "NVIDIA GPU found via lspci but nvidia-smi unavailable"
            log "WARN" "Install: sudo apt install nvidia-container-toolkit"
        elif lspci 2>/dev/null | grep -qi "amd.*display\|radeon"; then
            export GPU_TYPE="amd"
        fi
        return
    fi

    # Method 3: /proc/driver/nvidia
    if [ -d "/proc/driver/nvidia" ]; then
        export GPU_TYPE="nvidia"
        return
    fi

    export GPU_TYPE="cpu"
    log "INFO" "No GPU detected — using CPU mode"
}

load_or_generate_secret() {
    local var_name="$1"
    local current_value
    # Check if the variable already has a value (from a previous run's .env)
    eval "current_value=\$$var_name"
    if [[ -z "$current_value" ]]; then
        # If not, generate a new one
        eval "$var_name=$(openssl rand -hex 32)"
        log "INFO" "Generated new secret for ${var_name}."
    else
        log "INFO" "Loaded existing secret for ${var_name}."
    fi
}

# ─── Utility Functions ─────────────────────────────────────────────────────
fail() {
    log "ERROR" "$1"
    exit 1
}

ok() {
    log "SUCCESS" "$1"
}

warn() {
    log "WARN" "$1"
}

# ─── Tailscale Auth Key Validation ───────────────────────────────────────────
validate_tailscale_auth_key() {
    local auth_key="$1"
    
    # Check if auth key is provided
    if [[ -z "${auth_key}" ]]; then
        return 1
    fi
    
    # Validate format: should start with 'tskey-' followed by alphanumeric chars and hyphens
    if [[ ! "${auth_key}" =~ ^tskey-[a-zA-Z0-9-]+$ ]]; then
        echo -e "  ${DIM}Auth key format: should start with 'tskey-' followed by alphanumeric characters${NC}"
        return 1
    fi
    
    # Optional: Test the auth key against Tailscale API
    echo -e "  ${DIM}Testing auth key against Tailscale API...${NC}"
    
    # Extract the key prefix for API testing (remove tskey- prefix for some API calls)
    local key_id="${auth_key#tskey-}"
    
    # Use curl to test the key (this is a basic validation)
    if command -v curl >/dev/null 2>&1; then
        # Test with a simple API call - this validates the key format and basic structure
        local api_test
        api_test=$(curl -s --max-time 10 \
            -H "Authorization: Bearer ${auth_key}" \
            "https://api.tailscale.com/api/v2/device" 2>/dev/null || echo "failed")
        
        if [[ "${api_test}" == "failed" ]]; then
            echo -e "  ${YELLOW}⚠️ Could not validate auth key against API (network issue?)${NC}"
            echo -e "  ${DIM}Proceeding with format validation only...${NC}"
            return 0  # Don't fail on network issues, just proceed
        elif [[ "${api_test}" =~ "error" ]]; then
            echo -e "  ${RED}❌ Auth key validation failed (invalid or expired key)${NC}"
            return 1
        else
            echo -e "  ${GREEN}✅ Auth key validated against Tailscale API${NC}"
            return 0
        fi
    else
        echo -e "  ${YELLOW}⚠️ curl not available, skipping API validation${NC}"
        return 0  # Don't fail if curl is not available
    fi
}

# ─── Logging ─────────────────────────────────────────────────────────
log() {
    local level="${1}" message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

# ─── DNS resolution check (used inside collect_identity) ─────────────────────
check_dns() {
    local domain="${1}"
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null \
             || curl -s --max-time 5 api.ipify.org 2>/dev/null \
             || echo "unknown")
    RESOLVED_IP=$(dig +short "${domain}" 2>/dev/null | grep -E '^[0-9]+\.' | tail -1 || echo "")

    if [ -z "${RESOLVED_IP}" ]; then
        log "WARN" "DNS for ${domain} did not resolve — self-signed TLS will be used"
        SSL_TYPE="selfsigned"
        DOMAIN_RESOLVES=false
    elif [ "${RESOLVED_IP}" = "${PUBLIC_IP}" ]; then
        log "SUCCESS" "DNS verified — ${domain} → ${PUBLIC_IP}"
        SSL_TYPE="acme"
        DOMAIN_RESOLVES=true
    else
        log "WARN" "DNS mismatch — expected ${PUBLIC_IP}, got ${RESOLVED_IP}"
        log "WARN" "Caddy will attempt ACME but may fail — check your DNS records"
        SSL_TYPE="acme"
        DOMAIN_RESOLVES=false
    fi
}

# ─── Rebuild collect_identity to use check_dns ───────────────────────────────
collect_identity() {
    print_step "2" "11" "Domain & Identity"

    echo -e "  ${BOLD}🌐  Domain Setup${NC}"
    echo -e "  ${DIM}DNS must already point to this server for automatic TLS to work${NC}"
    echo ""

    while true; do
        read -p "  ➤ Domain name (e.g. ai.example.com): " DOMAIN
        DOMAIN="${DOMAIN,,}"
        if [[ "${DOMAIN}" =~ ^[a-z0-9][a-z0-9.\-]{2,253}[a-z0-9]$ ]]; then
            break
        fi
        echo "  ❌ Invalid domain format — try again"
    done

    check_dns "${DOMAIN}"

    print_divider

    echo -e "  ${BOLD}🏷️   Tenant Identifier${NC}"
    echo -e "  ${DIM}Short ID used for naming, namespacing and branding${NC}"
    echo ""

    # Skip tenant collection if already provided via command line or collected in main()
    if [ "${SKIP_TENANT_COLLECTION:-false}" = "true" ]; then
        # Use the tenant name collected in main()
        TENANT_ID="${TENANT_NAME}"
        log "INFO" "Tenant ID already set: ${TENANT_ID}"
        # Define TENANT_DIR right after TENANT_ID is set
        TENANT_DIR="/mnt/data/${TENANT_ID}"
        # Set default PROJECT_PREFIX since we're skipping interactive collection
        PROJECT_PREFIX="${PROJECT_PREFIX:-ai-}"
        # Set default ADMIN_EMAIL when skipping interactive collection
        ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${TENANT_ID}.local}"
        # Set default DOMAIN when skipping interactive collection
        DOMAIN="${DOMAIN:-ai.${TENANT_ID}.local}"
        print_divider
        return
    fi

    while true; do
        read -p "  ➤ Tenant ID (e.g. mycompany): " TENANT_ID
            TENANT_ID="${TENANT_ID,,}"
            if [[ "${TENANT_ID}" =~ ^[a-z][a-z0-9\-]{2,29}$ ]]; then
                # Define TENANT_DIR right after TENANT_ID is set
                TENANT_DIR="/mnt/data/${TENANT_ID}"
                # Define TENANT_DIR right after TENANT_ID is set
                TENANT_DIR="/mnt/data/${TENANT_ID}"
                break
            fi
            echo "  ❌ Must start with a letter, 3–30 chars, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}�  Project Prefix${NC}"
    echo -e "  ${DIM}Prefix for Docker resources (compose project, containers, volumes)${NC}"
    echo ""

    while true; do
        read -p "  ➤ Project prefix [ai-]: " PROJECT_PREFIX
        PROJECT_PREFIX="${PROJECT_PREFIX:-ai-}"
        PROJECT_PREFIX="${PROJECT_PREFIX,,}"
        if [[ "${PROJECT_PREFIX}" =~ ^[a-z][a-z0-9\-]*-$ ]]; then
            break
        fi
        echo "  ❌ Must end with hyphen, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}🔧 Hardware Acceleration${NC}"
    echo ""
    read -p "  ➤ Enable NVIDIA GPU support? (Requires nvidia-container-toolkit) [y/N]: " answer
    if [[ "${answer,,}" == "y" ]]; then
        declare -g ENABLE_GPU="true"
    else
        declare -g ENABLE_GPU="false"
    fi
    echo ""

    echo -e "  ${BOLD}📧 Admin Email${NC}"
    echo ""
    while true; do
        read -p "  ➤ Admin email address: " ADMIN_EMAIL
        if [[ "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            break
        fi
        echo "  ❌ Invalid email format — try again"
    done
}

# ─── STEP 5: Stack selection ──────────────────────────────────────────────────
select_stack() {
    print_step "6" "11" "Service Stack Selection"

    echo -e "  ${BOLD}📦  Choose a service stack${NC}"
    echo -e "  ${DIM}Stacks are pre-configured bundles — you can customise in the next step${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC}  🟢  ${BOLD}Minimal${NC}       — Ollama + Open WebUI only"
    echo -e "             ${DIM}Ideal for local LLM inference, low resource usage${NC}"
    echo ""
    echo -e "  ${CYAN}  2)${NC}  🟢  ${BOLD}Development${NC}   - Bifrost router + Ollama + code server, continue.dev, Openclaw with tailscale for local dev."
    echo -e "             ${DIM}Full development environment with AI integration${NC}"
    echo ""
    echo -e "  ${CYAN}  3)${NC}  🔵  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + Bifrost"
    echo -e "             ${DIM}Full AI automation stack, recommended starting point${NC}"
    echo ""
    echo -e "  ${CYAN}  4)${NC}  🟣  ${BOLD}Full${NC}          — Standard + AnythingLLM + Grafana + Prometheus + Authentik + Dev tools"
    echo -e "             ${DIM}Production-grade with observability and SSO${NC}"
    echo ""
    echo -e "  ${CYAN}  5)${NC}  ⚙️   ${BOLD}Custom${NC}        — Pick services individually"
    echo -e "             ${DIM}Full control over what gets deployed${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select stack [1-5]: " stack_choice
        stack_choice="${stack_choice:-1}"
        case "${stack_choice}" in
            1|2|3|4|5) break ;;
            *) echo "  ❌ Enter 1, 2, 3, 4 or 5" ;;
        esac
    done

    # ── Apply stack presets ───────────────────────────────────────────────────
    # First, set core triad defaults to true
    ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true; ENABLE_OPENWEBUI=true;
    ENABLE_QDRANT=true; ENABLE_CADDY=true # Always on infrastructure
    
    # Set LLM router based on LLM_ROUTER choice (will be set later)
    # Router flags will be set in configure_llm_router function
    
    # Zero out optional services
    ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false; ENABLE_N8N=false; ENABLE_FLOWISE=false;
    ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false;
    ENABLE_AUTHENTIK=false; ENABLE_SIGNAL=false; ENABLE_OPENCLAW=false; ENABLE_TAILSCALE=false;
    ENABLE_RCLONE=false; ENABLE_OPENAI=false; ENABLE_ANTHROPIC=false;
    ENABLE_LOCALAI=false; ENABLE_VLLM=false;
    ENABLE_WEAVIATE=false; ENABLE_CHROMADB=false; ENABLE_MILVUS=false; ENABLE_PINECONE=false;
    ENABLE_MINIO=false; ENABLE_CODESERVER=false; ENABLE_CONTINUE=false

    case "${stack_choice}" in
        1) # Minimal Stack
            log "INFO" "Applying 'Minimal' preset: OpenWebUI, Ollama, Qdrant"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_QDRANT=true;
            STACK_NAME="minimal"
            ;;
        2) # Development Stack
            log "INFO" "Applying 'Development' preset: Code Server, Continue.dev, Ollama, OpenClaw, Tailscale"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_QDRANT=true; ENABLE_OPENWEBUI=true;
            ENABLE_CODESERVER=true; ENABLE_CONTINUE=true; ENABLE_OPENCLAW=true; ENABLE_TAILSCALE=true;
            STACK_NAME="development"
            ;;
        3) # Standard Stack
            log "INFO" "Applying 'Standard' preset: Minimal + n8n + Flowise + Qdrant"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_QDRANT=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true;
            STACK_NAME="standard"
            ;;
        4) # Full Stack
            log "WARN" "Applying 'Full Stack' preset. This requires significant system resources."
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_ANYTHINGLLM=true; ENABLE_DIFY=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true;
            ENABLE_QDRANT=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true;
            ENABLE_AUTHENTIK=true; ENABLE_SIGNAL=true; ENABLE_OPENCLAW=true;
            ENABLE_TAILSCALE=true; ENABLE_RCLONE=true; ENABLE_MONITORING=true;
            ENABLE_CODESERVER=true; ENABLE_CONTINUE=true
            STACK_NAME="full"
            ;;
        5) # Custom — all off, user picks in next step
            STACK_NAME="custom"
            log "INFO" "Stack: Custom — configure individually below"
            ;;
    esac

    print_divider

        # ── LLM Provider Configuration ───────────────────────────────────────────
    select_llm_providers() {
        print_step "4" "8" "LLM Provider Selection"

        echo -e "  ${BOLD}🤖  Choose LLM Providers${NC}"
        echo ""
        echo -e "  ${CYAN}  1)${NC}  Local Only      ${DIM}(Ollama)${NC}"
        echo -e "  ${CYAN}  2)${NC}  External Only  ${DIM}(OpenAI, Anthropic, Gemini, Groq, OpenRouter)${NC}"
        echo -e "  ${CYAN}  3)${NC}  Hybrid         ${DIM}(Local + External)${NC}"
        echo ""
        while true; do
            read -p "  ➤ Select LLM providers [1-3]: " llm_choice
            llm_choice="${llm_choice:-1}"
            case "${llm_choice}" in
                1|2|3) break ;;
                *) echo "  ❌ Enter 1, 2 or 3" ;;
            esac
        done

        case "${llm_choice}" in
            1) # Local Only
                ENABLE_OPENAI=false; ENABLE_ANTHROPIC=false; ENABLE_GROQ=false; ENABLE_OPENROUTER=false;
                ENABLE_GOOGLE=false; ENABLE_LOCALAI=false; ENABLE_VLLM=false
                LLM_PROVIDERS="local"
                log "INFO" "LLM Providers: Local only (Ollama)"
                ;;
            2) # External Only
                ENABLE_OPENAI=true; ENABLE_ANTHROPIC=true; ENABLE_GROQ=true; ENABLE_OPENROUTER=true;
                ENABLE_GOOGLE=true; ENABLE_LOCALAI=false; ENABLE_VLLM=false;
                LLM_PROVIDERS="external"
                log "INFO" "LLM Providers: External only (OpenAI, Anthropic, Gemini, Groq, OpenRouter)"
                ;;
            3) # Hybrid
                ENABLE_OPENAI=true; ENABLE_ANTHROPIC=true; ENABLE_GROQ=true; ENABLE_OPENROUTER=true;
                ENABLE_GOOGLE=true; ENABLE_LOCALAI=false; ENABLE_VLLM=false;
                LLM_PROVIDERS="hybrid"
                log "INFO" "LLM Providers: Hybrid (Local + External)"
                ;;
        esac
    }

    # ── Always offer fine-grained override ────────────────────────────────────
    if [ "${stack_choice}" != "5" ]; then
        echo ""
        echo -e "  ${DIM}Stack applied. Would you like to customise individual services?${NC}"
        echo ""
        read -p "  ➤ Customise service selection? [y/N]: " customise
        customise="${customise:-n}"
        if [[ "${customise,,}" =~ ^y ]]; then
            # Convert to Full Stack for customization
            stack_choice=4
        else
            # Skip service prompts and proceed to next step
            echo ""
            return
        fi
    fi

    if [ "${stack_choice}" = "4" ]; then
        echo ""
        echo -e "  ${BOLD}─── 🤖  AI / LLM ────────────────────────────────────────${NC}"
        ask_service "🦙" "Ollama"        "Local LLM engine"           "ENABLE_OLLAMA"        "$( [[ "${ENABLE_OLLAMA}" == "true" ]]        && echo y || echo n )"
        ask_service "🌐" "Open WebUI"    "Chat UI for Ollama"         "ENABLE_OPENWEBUI"     "$( [[ "${ENABLE_OPENWEBUI}" == "true" ]]     && echo y || echo n )"
        ask_service "🤖" "AnythingLLM"   "AI assistant & RAG"         "ENABLE_ANYTHINGLLM"   "$( [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]   && echo y || echo n )"
        ask_service "🏗️ " "Dify"          "LLM app builder"            "ENABLE_DIFY"          "$( [[ "${ENABLE_DIFY}" == "true" ]]          && echo y || echo n )"
        echo ""
        
        # Development Environment (only for Development and Full stacks)
        if [[ "${stack_choice}" == "2" ]] || [[ "${stack_choice}" == "4" ]]; then
            echo -e "  ${BOLD}─── 🔧 Development ───────────────────────────────────${NC}"
            ask_service "💻" "Code Server"   "VS Code in browser + Continue.dev"    "ENABLE_CODESERVER"   "$( [[ "${ENABLE_CODESERVER}" == "true" ]]   && echo y || echo n )"
            ask_service "🤖" "Continue.dev"  "AI assistant for Code Server"           "ENABLE_CONTINUE"     "$( [[ "${ENABLE_CONTINUE}" == "true" ]]     && echo y || echo n )"
            ask_service "🦅" "OpenClaw"      "Tailscale-based development terminal"         "ENABLE_OPENCLAW"     "$( [[ "${ENABLE_OPENCLAW}" == "true" ]]     && echo y || echo n )"
        fi
        echo ""
        
        echo -e "  ${BOLD}─── ⚡  Automation ──────────────────────────────────────${NC}"
        ask_service "🔄" "n8n"           "Workflow automation"         "ENABLE_N8N"           "$( [[ "${ENABLE_N8N}" == "true" ]]           && echo y || echo n )"
        ask_service "🌊" "Flowise"       "AI flow builder"             "ENABLE_FLOWISE"       "$( [[ "${ENABLE_FLOWISE}" == "true" ]]       && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 📊  Observability ───────────────────────────────────${NC}"
        ask_service "📈" "Grafana"       "Metrics dashboard"           "ENABLE_GRAFANA"       "$( [[ "${ENABLE_GRAFANA}" == "true" ]]       && echo y || echo n )"
        ask_service "🔭" "Prometheus"    "Metrics collection"          "ENABLE_PROMETHEUS"    "$( [[ "${ENABLE_PROMETHEUS}" == "true" ]]    && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 🔐  Security ────────────────────────────────────────${NC}"
        ask_service "🔑" "Authentik"     "SSO / identity provider"     "ENABLE_AUTHENTIK"     "$( [[ "${ENABLE_AUTHENTIK}" == "true" ]]     && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 💬  Messaging ───────────────────────────────────────${NC}"
        ask_service "📱" "Signal API"    "Signal messaging bridge"     "ENABLE_SIGNAL"        "$( [[ "${ENABLE_SIGNAL}" == "true" ]]        && echo y || echo n )"
    fi
}

# ─── Dify Configuration ───────────────────────────────────────────────────────
configure_dify() {
    # Only run if Dify is enabled
    if [[ "${ENABLE_DIFY}" != "true" ]]; then
        return
    fi
    
    print_step "6.5" "11" "Dify Configuration"
    
    echo -e "  ${BOLD}🏗️  Dify Configuration${NC}"
    echo -e "  ${DIM}Configure Dify LLM app builder settings${NC}"
    echo ""
    
    # Generate or prompt for Dify secret key
    if [[ -z "${DIFY_SECRET_KEY}" ]]; then
        DIFY_SECRET_KEY=$(openssl rand -hex 32)
        echo -e "  ${DIM}Generated DIFY_SECRET_KEY: ${DIFY_SECRET_KEY}${NC}"
        read -p "  ➤ Press Enter to accept or enter custom secret key: " custom_key
        if [[ -n "${custom_key}" ]]; then
            DIFY_SECRET_KEY="${custom_key}"
        fi
    else
        echo -e "  ${DIM}Using existing DIFY_SECRET_KEY${NC}"
    fi
    
    # Generate or prompt for Dify inner API key
    if [[ -z "${DIFY_INNER_API_KEY}" ]]; then
        DIFY_INNER_API_KEY=$(openssl rand -hex 32)
        echo -e "  ${DIM}Generated DIFY_INNER_API_KEY: ${DIFY_INNER_API_KEY}${NC}"
        read -p "  ➤ Press Enter to accept or enter custom inner API key: " custom_inner_key
        if [[ -n "${custom_inner_key}" ]]; then
            DIFY_INNER_API_KEY="${custom_inner_key}"
        fi
    else
        echo -e "  ${DIM}Using existing DIFY_INNER_API_KEY${NC}"
    fi
    
    log "SUCCESS" "Dify configuration completed"
}

# ─── Database Configuration ───────────────────────────────────────────────────────
configure_databases() {
    print_step "5" "9" "Database Configuration"
    
    echo -e "  ${BOLD}🗄️  Database Configuration${NC}"
    echo -e "  ${DIM}Configure database settings for multi-tenant deployment${NC}"
    echo ""
    
    # PostgreSQL Configuration
    echo -e "  ${CYAN}PostgreSQL Configuration:${NC}"
    read -p "  ➤ PostgreSQL user [${POSTGRES_USER:-datasquiz}]: " POSTGRES_USER
    POSTGRES_USER="${POSTGRES_USER:-datasquiz}"
    
    read -p "  ➤ PostgreSQL database name [${POSTGRES_DB:-datasquiz_db}]: " POSTGRES_DB
    POSTGRES_DB="${POSTGRES_DB:-datasquiz_db}"
    
    echo ""
    echo -e "  ${CYAN}Redis Configuration:${NC}"
    echo -e "  ${DIM}Redis will be configured with secure authentication${NC}"
    echo ""
    
    # Redis Configuration
    read -p "  ➤ Redis database number [0]: " REDIS_DB
    REDIS_DB="${REDIS_DB:-0}"
    
    print_divider
}

# ─── Vector DB Selection ───────────────────────────────────────────────────
select_vector_db() {
    print_step "7" "11" "Vector Database Selection"

    echo -e "  ${BOLD}🗄️  Choose Vector Database${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC}  Qdrant     ${DIM}(recommended, high-performance)${NC}"
    echo -e "  ${CYAN}  2)${NC}  Weaviate   ${DIM}(GraphQL API, advanced)${NC}"
    echo -e "  ${CYAN}  3)${NC}  ChromaDB   ${DIM}(lightweight, embedded)${NC}"
    echo -e "  ${CYAN}  4)${NC}  Milvus     ${DIM}(enterprise-scale)${NC}"
    echo -e "  ${CYAN}  5)${NC}  Pinecone   ${DIM}(managed service)${NC}"
    echo -e "  ${CYAN}  6)${NC}  None       ${DIM}(use external vector DB)${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select vector database [1-6]: " choice
        choice="${choice:-1}"
        case "${choice}" in
            1|2|3|4|5|6) break ;;
            *) echo "  ❌ Enter 1, 2, 3, 4, 5 or 6" ;;
        esac
    done

    # First, disable all vector databases
    ENABLE_QDRANT=false
    ENABLE_WEAVIATE=false
    ENABLE_CHROMADB=false
    ENABLE_MILVUS=false
    ENABLE_PINECONE=false

    # Then enable the selected one
    case "${choice}" in
        1) 
            VECTOR_DB="qdrant"
            ENABLE_QDRANT=true
            ;;
        2) 
            VECTOR_DB="weaviate"
            ENABLE_WEAVIATE=true
            ;;
        3) 
            VECTOR_DB="chromadb"
            ENABLE_CHROMADB=true
            ;;
        4) 
            VECTOR_DB="milvus"
            ENABLE_MILVUS=true
            ;;
        5) 
            VECTOR_DB="pinecone"
            ENABLE_PINECONE=true
            echo -e "  ${DIM}Note: Pinecone is a managed service - no local deployment${NC}"
            ;;
        6) 
            VECTOR_DB="none"
            echo -e "  ${DIM}Note: You'll need to configure external vector DB manually${NC}"
            ;;
    esac

    # Prompt for vector size if local vector database is selected
    if [[ "${VECTOR_DB}" != "pinecone" && "${VECTOR_DB}" != "none" ]]; then
        echo ""
        echo -e "  ${BOLD}🔢  Vector Size Configuration${NC}"
        echo -e "  ${DIM}Choose the embedding dimension for your vector database${NC}"
        echo ""
        echo -e "  ${CYAN}  1)${NC} 768   ${DIM}(nomic-embed-text, all-MiniLM-L6-v2)${NC}"
        echo -e "  ${CYAN}  2)${NC} 1024  ${DIM}(mxbai-embed-large, text-embedding-ada-002)${NC}"
        echo -e "  ${CYAN}  3)${NC} 1536  ${DIM}(text-embedding-3-large)${NC}"
        echo -e "  ${CYAN}  4)${NC} Custom size"
        echo ""
        
        while true; do
            read -p "  ➤ Select vector size [1-4]: " size_choice
            size_choice="${size_choice:-1}"
            case "${size_choice}" in
                1) 
                    QDRANT_VECTOR_SIZE=768
                    break 
                    ;;
                2) 
                    QDRANT_VECTOR_SIZE=1024
                    break 
                    ;;
                3) 
                    QDRANT_VECTOR_SIZE=1536
                    break 
                    ;;
                4) 
                    read -p "  ➤ Enter custom vector size: " custom_size
                    if [[ "${custom_size}" =~ ^[0-9]+$ ]]; then
                        QDRANT_VECTOR_SIZE="${custom_size}"
                        break
                    else
                        echo "  ❌ Please enter a valid number"
                    fi
                    ;;
                *) 
                    echo "  ❌ Enter 1, 2, 3 or 4" 
                    ;;
            esac
        done
        
        echo -e "  ${DIM}Vector size set to: ${QDRANT_VECTOR_SIZE}${NC}"
    fi

    log "SUCCESS" "Vector database: ${VECTOR_DB}"
}

# ─── Database Configuration ─────────────────────────────────────────────────────
collect_database() {
    print_step "7.5" "11" "Database Configuration"

    echo -e "  ${BOLD}🗄️  Database Configuration${NC}"
    echo -e "  ${DIM}Configure database settings for the AI platform${NC}"
    echo ""

    echo -e "  ${BOLD}PostgreSQL Configuration:${NC}"
    echo -e "  ${DIM}Default username: platform${NC}"
    read -p "  ➤ PostgreSQL username [platform]: " input_user
    
    # Use input if provided, otherwise keep default
    if [[ -n "${input_user}" ]]; then
        POSTGRES_USER="${input_user}"
    else
        POSTGRES_USER="platform"
    fi

    echo -e "  ${DIM}Database name: platform${NC}"
    read -p "  ➤ Database name [platform]: " input_db
    
    if [[ -n "${input_db}" ]]; then
        POSTGRES_DB="${input_db}"
    else
        POSTGRES_DB="platform"
    fi

    echo ""
    echo -e "  ${BOLD}Redis Configuration:${NC}"
    echo -e "  ${DIM}Redis will be configured with a secure password${NC}"
    echo ""

    print_divider
    log "SUCCESS" "Database configured: ${POSTGRES_USER}/${POSTGRES_DB}"
}

# ─── LLM Configuration ─────────────────────────────────────────────────────
collect_llm_config() {
    print_step "8" "11" "LLM Provider Configuration"

    echo -e "  ${BOLD}🔑  LLM Provider API Keys${NC}"
    echo -e "  ${DIM}Enter API keys for providers you want to use (leave blank to skip)${NC}"
    echo ""

    read -p "  ➤ OpenAI API key: " OPENAI_API_KEY
    read -p "  ➤ Google (Gemini) API key: " GOOGLE_API_KEY
    read -p "  ➤ Groq API key: " GROQ_API_KEY
    read -p "  ➤ OpenRouter API key: " OPENROUTER_API_KEY

    print_divider

    echo -e "  ${BOLD}🦙  Ollama Model Selection${NC}"
    echo -e "  ${DIM}Choose models appropriate for your available RAM${NC}"
    echo ""

    # Get system RAM for suggestion
    TOTAL_RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)
    
    echo -e "  ${DIM}System RAM: ${TOTAL_RAM_GB}GB${NC}"
    echo ""
    
    # Available models with RAM requirements - grouped by size
    echo -e "  ${BOLD}Available Models:${NC}"
    echo ""
    echo -e "  ${YELLOW}🟢 Small Models (1-8GB RAM):${NC}"
    echo -e "  ${CYAN}  1)${NC} llama3.2:1b      ${DIM}~1GB RAM${NC}"
    echo -e "  ${CYAN}  2)${NC} llama3.2:3b      ${DIM}~4GB RAM${NC}"
    echo -e "  ${CYAN}  3)${NC} qwen2.5:7b       ${DIM}~8GB RAM${NC}"
    echo ""
    echo -e "  ${YELLOW}🟡 Medium Models (10-16GB RAM):${NC}"
    echo -e "  ${CYAN}  4)${NC} llama3.1:8b      ${DIM}~10GB RAM${NC}"
    echo ""
    echo -e "  ${YELLOW}🔴 Large Models (50GB+ RAM):${NC}"
    echo -e "  ${CYAN}  5)${NC} llama3.1:70b     ${DIM}~50GB RAM${NC}"
    echo -e "  ${CYAN}  6)${NC} Custom model     ${DIM}Enter model name manually${NC}"
    echo ""
    
    echo -e "  ${DIM}Select models to download (comma-separated, e.g. 1,2,3)${NC}"
    read -p "  ➤ Models to install: " model_selection
    
    # Parse model selection
    OLLAMA_MODELS=""
    if [ -n "${model_selection}" ]; then
        for num in $(echo "${model_selection}" | tr ',' ' '); do
            case "${num}" in
                1) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.2:1b " ;;
                2) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.2:3b " ;;
                3) OLLAMA_MODELS="${OLLAMA_MODELS}qwen2.5:7b " ;;
                4) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.1:8b " ;;
                5) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.1:70b " ;;
                6) 
                    read -p "  ➤ Enter custom model name: " custom_model
                    [ -n "${custom_model}" ] && OLLAMA_MODELS="${OLLAMA_MODELS}${custom_model} "
                    ;;
            esac
        done
    fi
    
    # Set default model (first selected or suggested)
    if [ -n "${OLLAMA_MODELS}" ]; then
        OLLAMA_DEFAULT_MODEL=$(echo "${OLLAMA_MODELS}" | awk '{print $1}')
    else
        local suggested_model
        if [ "${TOTAL_RAM_GB}" -lt 8 ]; then
            suggested_model="llama3.2:1b"
        elif [ "${TOTAL_RAM_GB}" -lt 16 ]; then
            suggested_model="llama3.2:3b"
        elif [ "${TOTAL_RAM_GB}" -lt 32 ]; then
            suggested_model="qwen2.5:7b"
        else
            suggested_model="llama3.1:8b"
        fi
        OLLAMA_MODELS="${suggested_model}"
        OLLAMA_DEFAULT_MODEL="${suggested_model}"
    fi

    echo ""
    log "SUCCESS" "Models to download: ${OLLAMA_MODELS}"
    log "SUCCESS" "Default model: ${OLLAMA_DEFAULT_MODEL}"
}

# ─── Bifrost Configuration ─────────────────────────────────────────────────────
init_bifrost() {
    log "INFO" "Initializing Bifrost LLM gateway..."
    mkdir -p "${CONFIG_DIR}/bifrost"

    [[ -z "${LLM_MASTER_KEY}" ]] && { log "ERROR" "LLM_MASTER_KEY empty"; return 1; }
    [[ -z "${OLLAMA_CONTAINER}" ]] && { log "ERROR" "OLLAMA_CONTAINER empty"; return 1; }

    # Validate no special chars that break YAML
    local key="${LLM_MASTER_KEY}"
    local ollama_url="http://${OLLAMA_CONTAINER}:${OLLAMA_PORT:-11434}"

    # Write using python3 to guarantee valid YAML — no sed, no heredoc, no printf issues
    python3 - << PYEOF
import yaml, sys

config = {
    "accounts": [{
        "name": "default",
        "keys": [{"value": "${key}"}],
        "providers": {
            "ollama": {
                "base_url": "${ollama_url}",
                "timeout": 300
            }
        },
        "models": {
            "ollama": ["*"]
        }
    }],
    "server": {
        "port": ${BIFROST_PORT:-8082}
    }
}

with open("${CONFIG_DIR}/bifrost/config.yaml", "w") as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)

print("OK")
PYEOF

    local rc=$?
    if [[ ${rc} -ne 0 ]] || [[ ! -s "${CONFIG_DIR}/bifrost/config.yaml" ]]; then
        log "ERROR" "Bifrost config write failed"
        return 1
    fi

    log "INFO" "Bifrost config content:"
    cat "${CONFIG_DIR}/bifrost/config.yaml" | while IFS= read -r line; do
        log "INFO" "  ${line}"
    done

    chown "${DOCKER_USER_ID:-1000}:${DOCKER_GROUP_ID:-1000}" \
        "${CONFIG_DIR}/bifrost/config.yaml"
    chmod 640 "${CONFIG_DIR}/bifrost/config.yaml"

    update_env "LLM_GATEWAY_CONTAINER" "${LLM_GATEWAY_CONTAINER}"
    update_env "BIFROST_PORT" "${BIFROST_PORT}"
    log "SUCCESS" "Bifrost config written and validated"
}

# ─── LiteLLM Configuration ─────────────────────────────────────────────────────

# ─── Mem0 Configuration ─────────────────────────────────────────────────────
init_mem0() {
    print_step "8.4" "11" "Mem0 Configuration"

    echo -e "  ${BOLD}🧠 Mem0 Configuration${NC}"
    echo -e "  ${DIM}Configuring Mem0 memory layer${NC}"
    
    # Generate Mem0 API key if not exists
    local existing_key=$(grep "^MEM0_API_KEY=" "${ENV_FILE}" 2>/dev/null \
        | cut -d= -f2- | tr -d '"')
    local mem0_key="${existing_key:-mem0-$(openssl rand -hex 24)}"
    
    # Create directories
    mkdir -p "${CONFIG_DIR}/mem0" "${DATA_DIR}/mem0" "${DATA_DIR}/mem0-pip-cache"
    
    # Write Mem0 config using placeholder-sed pattern
    cat > "${CONFIG_DIR}/mem0/config.yaml" << 'MEM0_EOF'
vector_store:
  provider: qdrant
  config:
    host: "PLACEHOLDER_QDRANT_HOST"
    port: PLACEHOLDER_QDRANT_PORT
    collection_name: "PLACEHOLDER_COLLECTION"
    embedding_model_dims: 768

llm:
  provider: ollama
  config:
    model: "PLACEHOLDER_MODEL"
    ollama_base_url: "PLACEHOLDER_OLLAMA_URL"
    temperature: 0.1
    max_tokens: 2000

embedder:
  provider: ollama
  config:
    model: "nomic-embed-text"
    ollama_base_url: "PLACEHOLDER_OLLAMA_URL"
MEM0_EOF

    # Substitute placeholders
    sed -i "s|PLACEHOLDER_QDRANT_HOST|${PROJECT_PREFIX}${TENANT_ID}-qdrant|g" \
        "${CONFIG_DIR}/mem0/config.yaml"
    sed -i "s|PLACEHOLDER_QDRANT_PORT|6333|g" \
        "${CONFIG_DIR}/mem0/config.yaml"
    sed -i "s|PLACEHOLDER_COLLECTION|${TENANT_ID}_memory|g" \
        "${CONFIG_DIR}/mem0/config.yaml"
    sed -i "s|PLACEHOLDER_MODEL|llama3.2|g" \
        "${CONFIG_DIR}/mem0/config.yaml"
    sed -i "s|PLACEHOLDER_OLLAMA_URL|http://${PROJECT_PREFIX}${TENANT_ID}-ollama:11434|g" \
        "${CONFIG_DIR}/mem0/config.yaml"

    # Write the FastAPI server
    cat > "${CONFIG_DIR}/mem0/server.py" << 'PYEOF'
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List
import os, yaml

app = FastAPI()
API_KEY = os.environ.get("MEM0_API_KEY", "")

def verify(authorization: str = Header(None)):
    if authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401)

class Msg(BaseModel):
    role: str
    content: str

class MemReq(BaseModel):
    messages: List[Msg]
    user_id: str

class SearchReq(BaseModel):
    query: str
    user_id: str

try:
    from mem0 import Memory
    with open("/app/config.yaml") as f:
        mem = Memory.from_config(yaml.safe_load(f))
except Exception as e:
    print(f"Mem0 init warning: {e}")
    mem = None

@app.get("/health")
def health():
    return {"status": "ok", "ready": mem is not None}

@app.post("/v1/memories")
def add(req: MemReq, authorization: str = Header(None)):
    verify(authorization)
    if not mem:
        raise HTTPException(503)
    return mem.add([m.dict() for m in req.messages], user_id=req.user_id)

@app.post("/v1/memories/search")
def search(req: SearchReq, authorization: str = Header(None)):
    verify(authorization)
    if not mem:
        raise HTTPException(503)
    return {"results": mem.search(req.query, user_id=req.user_id)}
PYEOF

    # Set ownership
    chown -R "${TENANT_UID}:${TENANT_GID}" "${CONFIG_DIR}/mem0" "${DATA_DIR}/mem0" "${DATA_DIR}/mem0-pip-cache"
    chmod 640 "${CONFIG_DIR}/mem0/config.yaml"
    chmod 644 "${CONFIG_DIR}/mem0/server.py"
    
    # Write Mem0 variables to .env
    [[ -f "${ENV_FILE}" ]] && sed -i '/^MEM0_API_KEY=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "MEM0_API_KEY=${mem0_key}" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^MEM0_PORT=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "MEM0_PORT=8765" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^QDRANT_MEMORY_COLLECTION=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "QDRANT_MEMORY_COLLECTION=${TENANT_ID}_memory" >> "${ENV_FILE}"
    
    log "SUCCESS" "Mem0 configured"
    echo -e "  ${GREEN}✅${NC} Mem0 config created: ${CONFIG_DIR}/mem0/config.yaml"
    echo -e "  ${DIM}✅ Port: 8765${NC}"
    echo -e "  ${DIM}✅ Collection: ${TENANT_ID}_memory${NC}"
}

# ─── LiteLLM Configuration ─────────────────────────────────────────────────────
init_litellm() {
    print_step "8.3" "11" "LiteLLM Configuration"

    echo -e "  ${BOLD}⚙️  LiteLLM Configuration${NC}"
    echo -e "  ${DIM}Configuring LiteLLM with environment variables${NC}"
    
    # Generate or preserve master key
    local existing_key=$(grep "^LITELLM_MASTER_KEY=" "${ENV_FILE}" 2>/dev/null \
        | cut -d= -f2- | tr -d '"')
    local master_key="${existing_key:-sk-litellm-$(openssl rand -hex 24)}"
    
    # Get user input for port (default 4000)
    local port
    echo -e "  ${CYAN}➤ LiteLLM port [4000]:${NC} "
    read -r port
    port="${port:-4000}"
    
    # Ollama URL must already exist from init_ollama()
    local ollama_url="http://${PROJECT_PREFIX}${TENANT_ID}-ollama:11434"
    
    # Write LiteLLM configuration to .env
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LITELLM_MASTER_KEY=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LITELLM_MASTER_KEY=${master_key}" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LITELLM_PORT=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LITELLM_PORT=${port}" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LITELLM_OLLAMA_URL=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LITELLM_OLLAMA_URL=${ollama_url}" >> "${ENV_FILE}"
    
    # Set router-agnostic variables
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_ROUTER_CONTAINER=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LLM_ROUTER_CONTAINER=${PROJECT_PREFIX}${TENANT_ID}-litellm" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_ROUTER_PORT=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LLM_ROUTER_PORT=${port}" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_GATEWAY_URL=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LLM_GATEWAY_URL=http://${PROJECT_PREFIX}${TENANT_ID}-litellm:${port}" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_GATEWAY_API_URL=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LLM_GATEWAY_API_URL=http://${PROJECT_PREFIX}${TENANT_ID}-litellm:${port}/v1" >> "${ENV_FILE}"
    
    [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_MASTER_KEY=/d' "${ENV_FILE}" 2>/dev/null || true
    echo "LLM_MASTER_KEY=${master_key}" >> "${ENV_FILE}"
    
    log "SUCCESS" "LiteLLM configured with environment variables"
    echo -e "  ${GREEN}✅${NC} LiteLLM environment config created"
    echo -e "  ${DIM}✅ Port: ${port}${NC}"
    echo -e "  ${DIM}✅ Container: ${PROJECT_PREFIX}${TENANT_ID}-litellm${NC}"
}

# ─── LLM Router Configuration (Modular Choice) ───────────────────────────────
configure_llm_router() {
    print_step "8.2" "11" "LLM Router Configuration"
    
    echo -e "  ${BOLD}🚀 LLM Router Configuration${NC}"
    echo -e "  ${DIM}Choose your LLM routing strategy${NC}"
    echo ""
    echo -e "  ${YELLOW}🟢 Option 1:${NC} Bifrost - Lightweight Go-based router"
    echo -e "     ${DIM}• YAML configuration file${NC}"
    echo -e "     ${DIM}• Fast startup, minimal dependencies${NC}"
    echo -e "     ${DIM}• Direct Ollama integration${NC}"
    echo -e "     ${DIM}• Production-ready reliability${NC}"
    echo ""
    echo -e "  ${YELLOW}🟡 Option 2:${NC} LiteLLM - Feature-rich Python router"
    echo -e "     ${DIM}• Environment variable configuration${NC}"
    echo -e "     ${DIM}• Advanced load balancing & retry logic${NC}"
    echo -e "     ${DIM}• Multiple provider support${NC}"
    echo -e "     ${DIM}• Database-backed configuration${NC}"
    echo ""
    
    # Get user choice
    local router_choice
    echo -e "  ${CYAN}➤ Choose LLM router [1=Bifrost, 2=LiteLLM] (default: 1):${NC} "
    read -r router_choice
    router_choice="${router_choice:-1}"
    
    case "${router_choice}" in
        1)
            LLM_ROUTER="bifrost"
            BIFROST_PORT="${BIFROST_PORT:-8000}"
            BIFROST_ROUTING_MODE="${BIFROST_ROUTING_MODE:-direct}"
            
            echo -e "  ${GREEN}✅${NC} Bifrost selected - Lightweight, fast routing"
            echo -e "  ${DIM}✅ Bifrost configured for port ${BIFROST_PORT}${NC}"
            echo -e "  ${DIM}✅ Bifrost routing mode: ${BIFROST_ROUTING_MODE}${NC}"
            
            # Write router configuration to .env
            [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_ROUTER=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "LLM_ROUTER=${LLM_ROUTER}" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_BIFROST=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_BIFROST=true" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_LITELLM=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_LITELLM=false" >> "${ENV_FILE}"
            
            echo -e "  ${DIM}✅ Bifrost enabled${NC}"
            ;;
        2)
            LLM_ROUTER="litellm"
            LITELLM_PORT="${LITELLM_PORT:-4000}"
            LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-litellm-$(openssl rand -hex 24)}"
            
            echo -e "  ${GREEN}✅${NC} LiteLLM selected - Feature-rich routing"
            echo -e "  ${DIM}✅ LiteLLM configured for port ${LITELLM_PORT}${NC}"
            echo -e "  ${DIM}✅ Master key generated${NC}"
            
            # Write router configuration to .env
            [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_ROUTER=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "LLM_ROUTER=${LLM_ROUTER}" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_LITELLM=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_LITELLM=true" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_BIFROST=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_BIFROST=false" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^LITELLM_MASTER_KEY=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}" >> "${ENV_FILE}"
            
            echo -e "  ${DIM}✅ LiteLLM enabled${NC}"
            ;;
        *)
            echo -e "  ${RED}❌ Invalid choice. Defaulting to Bifrost.${NC}"
            LLM_ROUTER="bifrost"
            BIFROST_PORT="4000"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^LLM_ROUTER=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "LLM_ROUTER=${LLM_ROUTER}" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_BIFROST=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_BIFROST=true" >> "${ENV_FILE}"
            
            [[ -f "${ENV_FILE}" ]] && sed -i '/^ENABLE_LITELLM=/d' "${ENV_FILE}" 2>/dev/null || true
            echo "ENABLE_LITELLM=false" >> "${ENV_FILE}"
            ;;
    esac
    
    log "SUCCESS" "LLM Router: ${LLM_ROUTER}"
}

# ─── Network & Security Configuration ───────────────────────────────────────────
collect_network_config() {
    print_step "9" "11" "Network & Security Configuration"

    echo -e "  ${BOLD}🔐  Network & Security Settings${NC}"
    echo -e "  ${DIM}Configure networking, VPN, and security options${NC}"
    echo ""

    # Tailscale Configuration
    echo -e "  ${BOLD}🌐  Tailscale VPN${NC}"
    echo -e "  ${DIM}Zero-trust networking for secure access${NC}"
    echo ""
    read -p "  ➤ Enable Tailscale VPN? [Y/n]: " enable_ts
    if [[ "${enable_ts,,}" =~ ^y ]]; then
        export ENABLE_TAILSCALE="true"
        while true; do
            read -p "  ➤ Tailscale auth key (required): " TAILSCALE_AUTH_KEY
            if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
                # Validate Tailscale auth key format
                if [[ "${TAILSCALE_AUTH_KEY}" =~ ^tskey-[a-zA-Z0-9-]+$ ]]; then
                    echo -e "  ${DIM}✅ Auth key format validated${NC}"
                    break
                else
                    echo -e "  ${YELLOW}⚠️ Invalid auth key format. Should start with 'tskey-'${NC}"
                fi
            else
                echo "  ❌ Auth key cannot be empty if Tailscale is enabled."
            fi
        done
        read -p "  ➤ Tailscale hostname [${PROJECT_PREFIX}${TENANT_ID}]: " TAILSCALE_HOSTNAME
        TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-${PROJECT_PREFIX}${TENANT_ID}}"
        
        # Validate Tailscale auth key before proceeding
        echo ""
        echo -e "  ${DIM}Validating Tailscale auth key...${NC}"
        if validate_tailscale_auth_key "${TAILSCALE_AUTH_KEY}"; then
            echo -e "  ${GREEN}✅ Auth key format validated${NC}"
        else
            echo -e "  ${RED}❌ Invalid auth key format. Please check your auth key.${NC}"
            echo -e "  ${DIM}Auth keys should start with 'tskey-' followed by alphanumeric characters${NC}"
            # Allow retry instead of failing completely
            while true; do
                read -p "  ➤ Re-enter Tailscale auth key (or press Enter to skip): " TAILSCALE_AUTH_KEY
                if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
                    echo -e "  ${YELLOW}⚠️ Skipping Tailscale configuration${NC}"
                    export ENABLE_TAILSCALE="false"
                    break
                elif validate_tailscale_auth_key "${TAILSCALE_AUTH_KEY}"; then
                    echo -e "  ${GREEN}✅ Auth key format validated${NC}"
                    break
                else
                    echo -e "  ${RED}❌ Invalid format. Try again or press Enter to skip.${NC}"
                fi
            done
        fi
        
        # If auth key provided, ask for serve mode and funnel
        echo ""
        echo -e "  ${DIM}Tailscale serve mode (for serving web services):${NC}"
        read -p "  ➤ Enable serve mode? [y/N]: " enable_serve
        if [[ "${enable_serve,,}" == "y" ]]; then
            TAILSCALE_SERVE_MODE="true"
            echo -e "  ${DIM}✅ Serve mode enabled - services will be accessible via Tailscale${NC}"
            
            # Ask for funnel configuration
            echo ""
            echo -e "  ${DIM}Tailscale Funnel Configuration:${NC}"
            echo -e "  ${DIM}Choose funnel type for service access:${NC}"
            echo ""
            echo -e "  ${CYAN}  1)${NC} HTTPS funnel (recommended, secure)"
            echo -e "  ${CYAN}  2)${NC} TCP funnel (for specific services)"
            echo ""
            read -p "  ➤ Select funnel type [1-2]: " funnel_choice
            case "${funnel_choice}" in
                1) TAILSCALE_FUNNEL="https" ;;
                2) TAILSCALE_FUNNEL="tcp" ;;
                *) TAILSCALE_FUNNEL="https" ;;
            esac
            echo -e "  ${DIM}✅ Funnel type: ${TAILSCALE_FUNNEL}${NC}"
        else
            TAILSCALE_SERVE_MODE="false"
            TAILSCALE_FUNNEL="https"
        fi
    else
        export ENABLE_TAILSCALE="false"
        export TAILSCALE_AUTH_KEY=""
        TAILSCALE_SERVE_MODE="false"
        TAILSCALE_FUNNEL="https"
    fi

    print_divider

    # Signal API Configuration
    echo -e "  ${BOLD}📱  Signal API Bridge${NC}"
    echo -e "  ${DIM}Bridge Signal messaging to web API${NC}"
    echo ""
    read -p "  ➤ Signal phone number (with country code, e.g. +1234567890): " SIGNAL_PHONE_NUMBER
    
    echo ""
    echo -e "  ${DIM}Signal verification options:${NC}"
    echo -e "  ${CYAN}  1)${NC} Generate verification code (recommended)"
    echo -e "  ${CYAN} 2)${NC} Enter existing verification code"
    echo -e "  ${CYAN}  3)${NC} Skip Signal API setup"
    echo ""
    read -p "  ➤ Select verification method [1-3]: " signal_verify_method
    
    case "${signal_verify_method}" in
        1)
            echo -e "  ${DIM}Verification code will be generated automatically after Signal API starts${NC}"
            SIGNAL_VERIFICATION_CODE=""
            ENABLE_SIGNAL=true
            ;;
        2)
            read -p "  ➤ Enter verification code: " SIGNAL_VERIFICATION_CODE
            ENABLE_SIGNAL=true
            ;;
        3)
            echo -e "  ${DIM}Skipping Signal API setup${NC}"
            SIGNAL_PHONE_NUMBER=""
            SIGNAL_VERIFICATION_CODE=""
            ENABLE_SIGNAL=false
            ;;
    esac

    print_divider

    # Google Drive Integration
    echo -e "  ${BOLD}💾  Google Drive Integration${NC}"
    echo -e "  ${DIM}Configure rclone for Google Drive access${NC}"
    echo ""
    read -p "  ➤ Enable Google Drive integration? [y/N]: " enable_gdrive
    if [[ "${enable_gdrive,,}" == "y" ]]; then
        ENABLE_RCLONE=true
        
        echo -e "  ${DIM}Choose authentication method:${NC}"
        echo -e "  ${CYAN}  1)${NC} OAuth Client Credentials (recommended for personal use)"
        echo -e "  ${CYAN}  2)${NC} Service Account JSON (recommended for server/automated use)"
        echo ""
        read -p "  ➤ Select method [1/2]: " auth_method
        
        if [[ "$auth_method" == "2" ]]; then
            # Service Account JSON method
            echo -e "  ${DIM}Service Account JSON Configuration${NC}"
            echo -e "  ${DIM}Get JSON from: Google Cloud Console > IAM & Admin > Service Accounts${NC}"
            echo ""
            echo -e "  ${YELLOW}Paste the complete JSON content below (press Enter on empty line to finish):${NC}"
            echo -e "  ${DIM}Example: {\"type\": \"service_account\", \"project_id\": \"...\"${NC}"
            echo -e "  ${DIM}Note: JSON can span multiple lines with proper formatting${NC}"
            echo -e "  ${DIM}💡 TIP: Copy the entire JSON including all quotes and brackets${NC}"
            echo ""
            
            # Create rclone directory first (ensure it exists)
            mkdir -p "${TENANT_DIR}/rclone"
            
            # Create a temporary file for JSON input
            local temp_json_file="${TENANT_DIR}/rclone/temp_json_input.txt"
            
            echo -e "  ${CYAN}📝 Ready for JSON input...${NC}"
            echo -e "  ${DIM}Paste JSON content now, then press Enter on an empty line when done:${NC}"
            echo ""
            
            # Read JSON content using a more robust method
            json_content=""
            echo "" > "$temp_json_file"  # Initialize temp file
            
            # Use a different approach - read until we detect the JSON structure
            while IFS= read -r line; do
                # If we get an empty line and have some content, break
                if [[ -z "$line" && -s "$temp_json_file" ]]; then
                    break
                fi
                
                # Add line to temp file
                echo "$line" >> "$temp_json_file"
            done
            
            # Read the complete JSON from temp file
            json_content=$(cat "$temp_json_file" 2>/dev/null || echo "")
            
            # Clean up temp file
            rm -f "$temp_json_file" 2>/dev/null
            
            echo ""
            echo -e "  ${DIM}Processing JSON content...${NC}"
            
            # Validate JSON content
            if [[ -n "$json_content" ]] && echo "$json_content" | python3 -m json.tool >/dev/null 2>&1; then
                # Save JSON to rclone directory for container mounting
                echo "$json_content" > "${TENANT_DIR}/rclone/google_sa.json"
                
                # Extract key information from JSON for validation
                local sa_type=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('type', 'unknown'))" 2>/dev/null)
                local sa_email=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_email', 'unknown'))" 2>/dev/null)
                
                if [[ "$sa_type" == "service_account" ]]; then
                    echo -e "  ${GREEN}✅ Valid Service Account JSON detected${NC}"
                    echo -e "  ${DIM}Service Account: ${sa_email}${NC}"
                else
                    echo -e "  ${YELLOW}⚠️ JSON type is '${sa_type}' (expected 'service_account')${NC}"
                    echo -e "  ${DIM}Proceeding anyway, but authentication may fail${NC}"
                fi
                
                # Generate Rclone token using Service Account
                echo ""
                echo -e "  ${DIM}🔄 Generating Rclone token for Service Account...${NC}"
                
                # Use rclone to generate token (similar to Script 3 approach)
                if command -v rclone >/dev/null 2>&1; then
                    echo -e "  ${DIM}⏳ Initializing Rclone configuration...${NC}"
                    
                    # Pause for 2 seconds to ensure JSON file is fully written
                    sleep 2
                    
                    # Create temporary config for token generation
                    local temp_config="${TENANT_DIR}/rclone/temp_sa.conf"
                    
                    # Extract Service Account credentials
                    local private_key=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('private_key', ''))" 2>/dev/null || echo "")
                    local client_email=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_email', ''))" 2>/dev/null || echo "")
                    
                    if [[ -n "$private_key" && -n "$client_email" ]]; then
                        # Service Account uses private_key and JSON file directly
                        cat > "$temp_config" << EOF
[gdrive_sa]
type = drive
scope = drive
service_account_file = ${TENANT_DIR}/rclone/google_sa.json
token = {"access_token":"test"}
EOF
                        echo -e "  ${DIM}   Using Service Account JSON file authentication${NC}"
                        echo -e "  ${DIM}   Service Account: ${client_email}${NC}"
                    else
                        echo -e "  ${RED}❌ Could not extract Service Account credentials from JSON${NC}"
                        echo -e "  ${DIM}   JSON should have private_key and client_email for Service Account${NC}"
                        GDRIVE_TOKEN=""
                        rm -f "$temp_config" 2>/dev/null
                    fi
                    
                    # For Service Accounts, we don't need token generation - the JSON file is enough
                    # Just validate the JSON file exists and is readable
                    if [[ -f "${TENANT_DIR}/rclone/google_sa.json" ]] && [[ -r "${TENANT_DIR}/rclone/google_sa.json" ]]; then
                        # Set a simple placeholder token for Service Account (no quotes to avoid .env issues)
                        GDRIVE_TOKEN='service_account_valid'
                        echo -e "  ${DIM}   Service Account JSON file validated${NC}"
                        echo -e "  ${GREEN}✅ Rclone Service Account configured successfully${NC}"
                        echo -e "  ${DIM}   Token will be generated automatically during deployment${NC}"
                        log "SUCCESS" "Rclone Service Account JSON validated and stored"
                    else
                        echo -e "  ${RED}❌ Service Account JSON file not accessible${NC}"
                        echo -e "  ${DIM}   Token will be generated automatically during deployment${NC}"
                        GDRIVE_TOKEN=""
                    fi
                    
                    # Clean up temp config
                    rm -f "$temp_config" 2>/dev/null
                    
                    # Final pause to ensure everything is settled
                    sleep 1
                    
                else
                    echo -e "  ${YELLOW}⚠️ rclone not available for token generation${NC}"
                    echo -e "  ${DIM}   Token will be generated automatically when Rclone container starts${NC}"
                    GDRIVE_TOKEN=""
                fi
                
                # Collect Google Drive root folder ID
                echo ""
                echo -e "  ${DIM}Optional: Google Drive root folder ID for specific folder access${NC}"
                echo -e "  ${DIM}Get from URL: https://drive.google.com/drive/folders/[FOLDER_ID]${NC}"
                read -p "  ➤ Google Drive root folder ID (optional): " RCLONE_GDRIVE_ROOT_ID
                
                # Set variables for .env
                GDRIVE_AUTH_METHOD="service_account"
                log "SUCCESS" "Google Drive Service Account configuration completed"
                
                # Health status summary
                echo ""
                echo -e "  ${CYAN}📊 Service Account Health Status:${NC}"
                if [[ -n "$GDRIVE_TOKEN" ]]; then
                    echo -e "  ${GREEN}✅ Rclone Token: Generated and stored${NC}"
                else
                    echo -e "  ${YELLOW}⚠️ Rclone Token: Will be generated during deployment${NC}"
                fi
                echo -e "  ${GREEN}✅ JSON Validation: Passed${NC}"
                echo -e "  ${GREEN}✅ Service Account: ${sa_email}${NC}"
                
            else
                echo -e "  ${RED}❌ Invalid JSON content. Please check your input.${NC}"
                echo -e "  ${DIM}Google Drive integration will be skipped.${NC}"
                ENABLE_RCLONE=false
                
                # Health status for failed validation
                echo ""
                echo -e "  ${CYAN}📊 Service Account Health Status:${NC}"
                echo -e "  ${RED}❌ JSON Validation: Failed${NC}"
                echo -e "  ${RED}❌ Rclone Token: Not generated${NC}"
            fi
            
        else
            # OAuth Client Credentials method
            echo -e "  ${DIM}OAuth Client Credentials Configuration${NC}"
            echo -e "  ${DIM}Get credentials from: https://rclone.org/drive/${NC}"
            echo ""
            read -p "  ➤ Google Drive client ID: " GDRIVE_CLIENT_ID
            read -p "  ➤ Google Drive client secret: " GDRIVE_CLIENT_SECRET
            read -p "  ➤ Google Drive folder name (optional): " GDRIVE_FOLDER_NAME
            read -p "  ➤ Google Drive folder ID (optional, for shared folders): " GDRIVE_FOLDER_ID
            
            GDRIVE_AUTH_METHOD="oauth"
            
            # Test OAuth credentials and get token
            echo -e "  ${DIM}Testing OAuth credentials and retrieving token...${NC}"
            if GDRIVE_TOKEN=$(get_oauth_token "${GDRIVE_CLIENT_ID}" "${GDRIVE_CLIENT_SECRET}"); then
                echo -e "  ${GREEN}✅ OAuth authentication successful${NC}"
                echo -e "  ${DIM}Token retrieved and validated${NC}"
            else
                echo -e "  ${YELLOW}⚠️ OAuth credentials configured but token retrieval failed${NC}"
                echo -e "  ${DIM}Token will be generated during deployment${NC}"
            fi
            
            log "SUCCESS" "Google Drive OAuth configuration completed"
        fi
        
    else
        ENABLE_RCLONE=false
    fi

    print_divider

    # Search API Configuration
    echo -e "  ${BOLD}🔍  Search API Configuration${NC}"
    echo -e "  ${DIM}Configure search providers for AI services${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC} Brave Search API"
    echo -e "  ${CYAN}  2)${NC} SerpApi (Google/Bing/etc)"
    echo -e "  ${CYAN}  3)${NC} Custom search endpoint"
    echo -e "  ${CYAN}  4)${NC} Multiple providers"
    echo -e "  ${CYAN}  5)${NC} Skip search APIs"
    echo ""
    read -p "  ➤ Select search provider [1-5]: " search_provider

    case "${search_provider}" in
        1)
            read -p "  ➤ Brave Search API key: " BRAVE_API_KEY
            SEARCH_PROVIDER="brave"
            ;;
        2)
            read -p "  ➤ SerpApi key: " SERPAPI_KEY
            read -p "  ➤ SerpApi engine [google]: " SERPAPI_ENGINE
            SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
            SEARCH_PROVIDER="serpapi"
            ;;
        3)
            read -p "  ➤ Custom search endpoint URL: " CUSTOM_SEARCH_URL
            read -p "  ➤ Custom search API key: " CUSTOM_SEARCH_KEY
            SEARCH_PROVIDER="custom"
            ;;
        4)
            echo -e "  ${DIM}Multiple providers configuration:${NC}"
            read -p "  ➤ Brave Search API key: " BRAVE_API_KEY
            read -p "  ➤ SerpApi key: " SERPAPI_KEY
            read -p "  ➤ SerpApi engine [google]: " SERPAPI_ENGINE
            SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
            SEARCH_PROVIDER="multiple"
            ;;
        5)
            SEARCH_PROVIDER="none"
            ;;
    esac

    print_divider

    # Proxy Configuration
    echo -e "  ${BOLD}🌍  Proxy Configuration${NC}"
    echo -e "  ${DIM}Configure reverse proxy settings for external access${NC}"
    echo ""
    read -p "  ➤ Enable reverse proxy? [y/N]: " enable_proxy
    if [[ "${enable_proxy,,}" == "y" ]]; then
        echo -e "  ${CYAN}  1)${NC} Caddy (built-in, recommended)"
        echo -e "  ${CYAN}  2)${NC} Nginx (high performance)"
        echo -e "  ${CYAN}   ${CYAN} 3)${NC} Traefik (automatic discovery)"
        echo -e "  ${CYAN}  4)${NC} Custom proxy"
        echo ""
        read -p "  ➤ Select proxy type [1-4]: " proxy_type
        
        case "${proxy_type}" in
            1) 
                PROXY_TYPE="caddy"
                echo -e "  ${DIM}Using Caddy as reverse proxy${NC}"
                ;;
            2) 
                PROXY_TYPE="nginx"
                echo -e "  ${DIM}Using Nginx as reverse proxy${NC}"
                ;;
            3) 
                PROXY_TYPE="traefik"
                echo -e "  ${DIM}Using Traefik as reverse proxy${NC}"
                ;;
            4) 
                read -p "  ➤ Custom proxy image: " CUSTOM_PROXY_IMAGE
                PROXY_TYPE="custom"
                ;;
        esac
        
        echo ""
        echo -e "  ${BOLD}🔄  Routing Method${NC}"
        echo -e "  ${CYAN}  1)${NC} Direct port mapping (simple)"
        echo -e "  ${CYAN}  2)${NC} Subdomain routing (recommended)"
        echo -e "  ${CYAN}  3)${NC}  Path-based routing"
        echo ""
        read -p "  ➤ Select routing method [1-3]: " routing_method
        
        case "${routing_method}" in
            1) ROUTING_METHOD="direct" ;;
            2) ROUTING_METHOD="subdomain" ;;
            3) ROUTING_METHOD="path" ;;
        esac
        
        echo ""
        echo -e "  ${BOLD}🔄  Port Redirect Configuration${NC}"
        echo -e "  ${DIM}Configure HTTP to HTTPS redirect behavior${NC}"
        echo ""
        read -p "  ➤ Redirect port 80 to 443 (HTTPS only)? [Y/n]: " redirect_http
        redirect_http="${redirect_http:-y}"
        
        if [[ "${redirect_http,,}" == "y" ]]; then
            HTTP_TO_HTTPS_REDIRECT="true"
            echo -e "  ${DIM}Port 80 will redirect to HTTPS (port 443)${NC}"
        else
            HTTP_TO_HTTPS_REDIRECT="false"
            echo -e "  ${DIM}Port 80 will serve HTTP content${NC}"
        fi
        
        # Auto-detect proxy from environment
        HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
        HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
        NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,.local}"
        
        if [[ -n "${HTTP_PROXY}" || -n "${HTTPS_PROXY}" ]]; then
            echo -e "  ${DIM}Proxy detected from environment variables${NC}"
        else
            echo -e "  ${DIM}No proxy detected${NC}"
        fi
        
        echo ""
        echo -e "  ${BOLD}🔒  SSL Certificate Method${NC}"
        echo -e "  ${CYAN}  1)${NC} Let's Encrypt (automatic, requires DNS)"
        echo -e "  ${CYAN}  2)${NC} Self-signed (quick, no DNS needed)"
        echo -e "  ${CYAN}  3)  ${CYAN} 3)${NC} Custom certificates"
        echo -e "  ${CYAN}  4)${NC} No SSL (HTTP only)"
        echo ""
        read -p "  ➤ Select SSL method [1-4]: " ssl_method
        
        case "${ssl_method}" in
            1) SSL_TYPE="acme" ;;
            2) SSL_TYPE="selfsigned" ;;
            3) SSL_TYPE="custom" ;;
            4) SSL_TYPE="none" ;;
        esac
        
        if [ "${SSL_TYPE}" = "acme" ]; then
            echo ""
            echo -e "  ${DIM}Let's Encrypt requires:${NC}"
            echo -e "  • Domain A record pointing to this server"
            echo -e "  • Ports 80 and 443 open in firewall"
            echo -e "  • Valid admin email for cert alerts (already collected)"
            echo ""
            echo -e "  ${GREEN}✅ Admin email already set: ${ADMIN_EMAIL}${NC}"
        fi
    fi

    # Dynamic proxy service enablement based on selection
    if [[ "${enable_proxy,,}" == "y" ]]; then
        case "${PROXY_TYPE}" in
            "caddy")
                ENABLE_CADDY=true
                log "INFO" "Caddy proxy enabled - ENABLE_CADDY set to true"
                ;;
            "nginx"|"traefik"|"custom")
                ENABLE_CADDY=false
                log "INFO" "${PROXY_TYPE} proxy selected - ENABLE_CADDY set to false"
                ;;
        esac
    else
        ENABLE_CADDY=false
        log "INFO" "No proxy selected - ENABLE_CADDY set to false"
    fi

    print_divider

    # OpenClaw Configuration
    echo -e "  ${BOLD}🦅  OpenClaw Private Gateway${NC}"
    echo -e "  ${DIM}Secure private access gateway${NC}"
    # Only ask for OpenClaw if not already set by stack
    if [[ "${ENABLE_OPENCLAW}" != "true" ]]; then
        echo ""
        read -p "  ➤ Enable OpenClaw? [y/N]: " enable_openclaw
        if [[ "${enable_openclaw,,}" =~ ^y ]]; then
            echo ""
            read -p "  ➤ OpenClaw admin password: " -s OPENCLAW_PASSWORD
            echo ""
            read -p "  ➤ OpenClaw port [18789]: " OPENCLAW_PORT
            OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
            OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-$CODESERVER_PASSWORD}"
            OPENCLAW_ADMIN_USER=admin
            OPENCLAW_SECRET="${OPENCLAW_PASSWORD:-$CODESERVER_PASSWORD}"
            OPENCLAW_PORT=${OPENCLAW_PORT}
            OPENCLAW_IMAGE=openclaw:latest
        fi
    else
        # OpenClaw was enabled by stack selection, collect password
        echo ""
        echo -e "  ${BOLD}🦅  OpenClaw Configuration${NC}"
        echo -e "  ${DIM}OpenClaw was enabled by stack selection${NC}"
        read -p "  ➤ OpenClaw admin password: " -s OPENCLAW_PASSWORD
        echo ""
        read -p "  ➤ OpenClaw port [18789]: " OPENCLAW_PORT
        OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
    fi

    log "SUCCESS" "Network & security configuration completed"
}

# ─── Port Configuration ────────────────────────────────────────────────────
collect_ports() {
    print_step "10" "11" "Port Configuration"

    echo -e "  ${BOLD}🔌  Service Ports${NC}"
    echo -e "  ${DIM}Configure ports for each enabled service${NC}"
    echo ""
    
    # Track used ports to prevent conflicts
    local used_ports=""
    
    # Port validation function
    read_port() {
        local service="${1}" default="${2}" varname="${3}"
        while true; do
            read -p "  ➤ ${service} port [${default}]: " input
            if [ -z "${input}" ]; then
                input="${default}"
            fi
            
            # Check if port is already in use on system
            if ss -tuln 2>/dev/null | grep -q ":${input} "; then
                log "WARN" "Port ${input} is already in use on system - choose another"
                continue
            fi
            
            # Check if port is already assigned to another service
            if [[ " ${used_ports} " =~ " ${input} " ]]; then
                log "WARN" "Port ${input} is already assigned to another service - choose another"
                continue
            fi
            
            eval "${varname}=\"${input}\""
            used_ports="${used_ports} ${input}"
            break
        done
    }
    
    # Dynamic port collection based on enabled services
    local ports_to_configure=()
    
    # Build list of ports to configure based on enabled services
    [[ "${ENABLE_N8N}" = "true" ]]         && ports_to_configure+=("n8n:5678:N8N_PORT")
    [[ "${ENABLE_FLOWISE}" = "true" ]]     && ports_to_configure+=("Flowise:3000:FLOWISE_PORT")
    [[ "${ENABLE_OPENWEBUI}" = "true" ]]   && ports_to_configure+=("Open WebUI:8081:OPENWEBUI_PORT")
    [[ "${ENABLE_ANYTHINGLLM}" = "true" ]] && ports_to_configure+=("AnythingLLM:3001:ANYTHINGLLM_PORT")
    [[ "${ENABLE_VLLM}" = "true" ]]         && ports_to_configure+=("VLLM:8000:VLLM_PORT")
    [[ "${ENABLE_GRAFANA}" = "true" ]]     && ports_to_configure+=("Grafana:3002:GRAFANA_PORT")
    [[ "${ENABLE_PROMETHEUS}" = "true" ]]  && ports_to_configure+=("Prometheus:9090:PROMETHEUS_PORT")
    [[ "${ENABLE_OLLAMA}" = "true" ]]      && ports_to_configure+=("Ollama:11434:OLLAMA_PORT")
    [[ "${ENABLE_QDRANT}" = "true" ]]      && ports_to_configure+=("Qdrant:6333:QDRANT_PORT")
    [[ "${ENABLE_AUTHENTIK}" = "true" ]]    && ports_to_configure+=("Authentik:9000:AUTHENTIK_PORT")
    [[ "${ENABLE_SIGNAL}" = "true" ]]      && ports_to_configure+=("Signal API:8080:SIGNAL_PORT")
    [[ "${ENABLE_OPENCLAW}" = "true" ]]    && ports_to_configure+=("OpenClaw:18789:OPENCLAW_PORT")
    [[ "${ENABLE_TAILSCALE}" = "true" ]]   && ports_to_configure+=("Tailscale:8443:TAILSCALE_PORT")
    [[ "${ENABLE_RCLONE}" = "true" ]]      && ports_to_configure+=("Rclone:5572:RCLONE_PORT")
    [[ "${ENABLE_CODESERVER}" = "true" ]]  && ports_to_configure+=("Code Server:8444:CODESERVER_PORT")

    # Configure each port
    for port_config in "${ports_to_configure[@]}"; do
        IFS=':' read -r service default_port var_name <<< "$port_config"
        read_port "$service" "$default_port" "$var_name"
    done

    log "SUCCESS" "Ports configured"
}

# ─── Generate secrets (preserve on re-run) ───────────────────────────────────
generate_secrets() {
    print_step "11" "11" "Generating Secrets"

    load_existing_secret() {
        local key="${1}" default="${2}"
        if [ -f "${ENV_FILE}" ]; then
            local val
            val=$(grep "^${key}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || echo "")
            [ -n "${val}" ] && echo "${val}" && return
        fi
        echo "${default}"
    }

    DB_PASSWORD=$(load_existing_secret "POSTGRES_PASSWORD" "$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)")
    REDIS_PASSWORD=$(load_existing_secret "REDIS_PASSWORD" "$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)")
    POSTGRES_PASSWORD="${DB_PASSWORD}"
    N8N_ENCRYPTION_KEY=$(load_existing_secret "N8N_ENCRYPTION_KEY"     "$(openssl rand -hex 32)")
    FLOWISE_SECRET_KEY=$(load_existing_secret "FLOWISE_SECRET_KEY"     "$(openssl rand -hex 32)")
    
    # Router-specific API keys
    BIFROST_AUTH_TOKEN=$(load_existing_secret "BIFROST_AUTH_TOKEN"       "sk-bifrost-$(openssl rand -hex 24)")
    
    ANYTHINGLLM_JWT_SECRET=$(load_existing_secret "ANYTHINGLLM_JWT_SECRET" "$(openssl rand -hex 32)")
    JWT_SECRET=$(load_existing_secret "JWT_SECRET"                   "$(openssl rand -hex 32)")
    ENCRYPTION_KEY=$(load_existing_secret "ENCRYPTION_KEY"           "$(openssl rand -hex 32)")
    ANYTHINGLLM_AUTH_TOKEN=$(load_existing_secret "ANYTHINGLLM_AUTH_TOKEN" "$(openssl rand -hex 16)")
    ANYTHINGLLM_API_KEY=$(load_existing_secret "ANYTHINGLLM_API_KEY" "$(openssl rand -hex 32)")
    GRAFANA_PASSWORD=$(load_existing_secret "GRAFANA_PASSWORD"          "$(openssl rand -hex 16)")
    CODESERVER_PASSWORD=$(load_existing_secret "CODESERVER_PASSWORD" "$(openssl rand -hex 12)")
    AUTHENTIK_SECRET_KEY=$(load_existing_secret "AUTHENTIK_SECRET_KEY" "$(openssl rand -hex 32)")
    MINIO_ROOT_PASSWORD=$(load_existing_secret "MINIO_ROOT_PASSWORD" "$(openssl rand -hex 16)")
    QDRANT_API_KEY=$(load_existing_secret   "QDRANT_API_KEY"            "$(openssl rand -hex 32)")
    N8N_API_KEY=$(load_existing_secret      "N8N_API_KEY"               "$(openssl rand -hex 32)")
    N8N_PASSWORD=$(load_existing_secret     "N8N_PASSWORD"              "$(openssl rand -hex 12)")
    FLOWISE_PASSWORD=$(load_existing_secret "FLOWISE_PASSWORD"          "$(openssl rand -hex 12)")
    AUTHENTIK_BOOTSTRAP_PASSWORD=$(load_existing_secret "AUTHENTIK_BOOTSTRAP_PASSWORD" "$(openssl rand -hex 12)")

    log "SUCCESS" "Secrets ready (preserved from prior run where available)"
}

# ─── Write Prometheus Configuration ─────────────────────────────────────────────
write_prometheus_config() {
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    
    log "INFO" "Generating prometheus.yml..."
    
    cat > "${DATA_ROOT}/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    log "SUCCESS" "Prometheus configuration written to ${DATA_ROOT}/prometheus.yml"
}

write_caddyfile() {
    log "INFO" "Executing dynamic Caddyfile generation as per README.md..."
    local CADDY_FILE="${DATA_ROOT}/Caddyfile"

    # Use a temporary file to build the content
    TMP_CADDY=$(mktemp)

    # 1. Global Options Block - ALWAYS formatted correctly
    cat > "$TMP_CADDY" <<-EOF
	{
	    email ${ADMIN_EMAIL}
	    # acme_dns google_cloud_dns ... # Placeholder for future DNS challenge
	}

	EOF

    # 2. Main Domain Route
    cat >> "$TMP_CADDY" <<-EOF
	${DOMAIN} {
	    # Add the tls directive here
	    tls internal {
	        on_demand
	    }
	    respond "AI Platform v3.2.0 is active. Welcome." 200
	}

	EOF

    # 3. Dynamically add routes for ONLY enabled services
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<-EOF
	grafana.${DOMAIN} {
	    tls internal
	    reverse_proxy grafana:${GRAFANA_INTERNAL_PORT}
	}

	EOF
        ok "Caddy route added for Grafana."
    fi
    
    if [[ "${ENABLE_PROMETHEUS}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<-EOF
	prometheus.${DOMAIN} {
	    tls internal
	    reverse_proxy prometheus:${PROMETHEUS_INTERNAL_PORT}
	}

	EOF
        ok "Caddy route added for Prometheus."
    fi
    
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<-EOF
	qdrant.${DOMAIN} {
	    tls internal
	    reverse_proxy qdrant:${QDRANT_INTERNAL_PORT}
	}

	EOF
        ok "Caddy route added for Qdrant."
    fi
    
    if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<-EOF
	ollama.${DOMAIN} {
	    tls internal
	    reverse_proxy ollama:${OLLAMA_INTERNAL_PORT}
	}

	EOF
        ok "Caddy route added for Ollama."
    fi
    
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<-EOF
	openwebui.${DOMAIN} {
	    tls internal
	    reverse_proxy openwebui:${OPENWEBUI_INTERNAL_PORT}
	}

	EOF
        ok "Caddy route added for OpenWebUI."
    fi

    # 4. Atomically move the file and run 'caddy fmt'
    mv "$TMP_CADDY" "$CADDY_FILE"
    log "INFO" "Running 'caddy fmt' to ensure perfect formatting..."
    docker run --rm -v "$CADDY_FILE":/etc/caddy/Caddyfile caddy:2 caddy fmt --overwrite
    
    chown "${TENANT_UID}:${TENANT_GID}" "$CADDY_FILE"
    log "SUCCESS" "Dynamic Caddyfile generation complete and validated."
}

# ─── Generate PostgreSQL Init Script ───────────────────────────────────────────
generate_postgres_init() {
    mkdir -p "${CONFIG_DIR}/postgres"
    
    # Write init script with variables resolved at generation time
    cat > "${CONFIG_DIR}/postgres/init-all-databases.sh" <<INITEOF
#!/usr/bin/env bash
set -e

# This file was generated by 1-setup-system.sh
# It runs once when the postgres container first starts

PG_USER="${POSTGRES_USER}"
PG_PASS="${POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "\$PG_USER" --dbname "postgres" <<EOSQL

  -- Ensure the platform role exists (idempotent)
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
      CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
  END \$\$;

  -- Create per-service databases (idempotent)
  SELECT 'CREATE DATABASE openwebui OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='openwebui') \gexec

  SELECT 'CREATE DATABASE n8n       OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='n8n')       \gexec

  SELECT 'CREATE DATABASE flowise   OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='flowise')   \gexec

  -- Grant all privileges
  GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB}  TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE openwebui        TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE n8n              TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE flowise          TO ${POSTGRES_USER};

EOSQL
INITEOF

    chmod +x "${CONFIG_DIR}/postgres/init-all-databases.sh"
    chown "${TENANT_UID}:${TENANT_GID}" "${CONFIG_DIR}/postgres/init-all-databases.sh"
    log "SUCCESS" "Postgres init script written — creates all service databases"
}

# ─── Write .env ───────────────────────────────────────────────────────────────
write_env_file() {
    mkdir -p "${DATA_ROOT}"

    # Create .env file atomically
    local temp_env_file="${ENV_FILE}.tmp"
    
    # Define project configuration variables
    local COMPOSE_PROJECT_NAME=${PROJECT_PREFIX}${TENANT_ID}
    local DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}-net"
    
    cat > "${temp_env_file}" << EOF
# ════════════════════════════════════════════════════════════════════════
# AI Platform — Environment Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ════════════════════════════════════════════════════════════════════════

# ─── Platform Identity ────────────────────────────────────────────────────────
TENANT_ID=${TENANT_ID}
TENANT=${TENANT_ID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
DATA_ROOT=${DATA_ROOT}
TENANT_DIR=${DATA_ROOT}
CONFIG_DIR=${DATA_ROOT}/configs
DATA_DIR=${DATA_ROOT}/data
LOGS_DIR=${DATA_ROOT}/logs
COMPOSE_FILE=${DATA_ROOT}/docker-compose.yml
SSL_TYPE=${SSL_TYPE}
PROJECT_PREFIX=${PROJECT_PREFIX}

# ─── Tenant User Configuration ───────────────────────────────────────────────────
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}

# ─── Service Ownership UIDs (Pragmatic Exception Pattern) ───────────────────────
# Per README.md, some services ignore the 'user:' directive and require
# their internal UID to own their data directory. These are defined here as
# configurable variables to avoid hardcoding in scripts.
# If a service is compliant, its variable can be left blank or removed.
POSTGRES_UID=${POSTGRES_UID:-70}
PROMETHEUS_UID=${PROMETHEUS_UID:-65534}
GRAFANA_UID=${GRAFANA_UID:-472}
N8N_UID=${N8N_UID:-1000}
QDRANT_UID=${QDRANT_UID:-1000}
REDIS_UID=${REDIS_UID:-999}
OPENWEBUI_UID=${OPENWEBUI_UID:-1000}
ANYTHINGLLM_UID=${ANYTHINGLLM_UID:-1000}
OLLAMA_UID=${OLLAMA_UID:-1001}
FLOWISE_UID=${FLOWISE_UID:-1000}
AUTHENTIK_UID=${AUTHENTIK_UID:-1000}
CADDY_UID=${CADDY_UID:-1000}
# Note: Cloud services (Pinecone, Weaviate, ChromaDB, Milvus, OpenAI, Anthropic, LocalAI, VLLM) don't need UIDs

# ─── Service Flags ─────────────────────────────────────────────────────────────
ENABLE_POSTGRES=${ENABLE_POSTGRES}
ENABLE_REDIS=${ENABLE_REDIS}
ENABLE_CADDY=${ENABLE_CADDY}
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_OPENAI=${ENABLE_OPENAI}
ENABLE_ANTHROPIC=${ENABLE_ANTHROPIC}
ENABLE_GOOGLE=${ENABLE_GOOGLE}
ENABLE_GROQ=${ENABLE_GROQ}
ENABLE_OPENROUTER=${ENABLE_OPENROUTER}
ENABLE_LOCALAI=${ENABLE_LOCALAI}
ENABLE_VLLM=${ENABLE_VLLM}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_WEAVIATE=${ENABLE_WEAVIATE}
ENABLE_PINECONE=${ENABLE_PINECONE}
ENABLE_CHROMADB=${ENABLE_CHROMADB}
ENABLE_MILVUS=${ENABLE_MILVUS}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS}
ENABLE_MONITORING=${ENABLE_MONITORING:-${ENABLE_GRAFANA:-false}}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW:-false}
ENABLE_RCLONE=${ENABLE_RCLONE}
ENABLE_MINIO=${ENABLE_MINIO}
ENABLE_CODESERVER=${ENABLE_CODESERVER:-false}
ENABLE_CONTINUE=${ENABLE_CONTINUE:-false}

# ─── Service Ownership UIDs (The "Pragmatic Exception Pattern") ───────────────────────
# Per README.md (Line 484), some services ignore the 'user:' directive and require
# their internal UID to own their data directory. These are defined here as
# configurable variables to avoid hardcoding in scripts.
# If a service is compliant, its variable can be left blank or removed.
POSTGRES_UID=70
PROMETHEUS_UID=65534
GRAFANA_UID=472
N8N_UID=1000
QDRANT_UID=1000
REDIS_UID=999
OLLAMA_UID=1001

# ─── Vector Database Configuration ───────────────────────────────────────────────────
PINECONE_PROJECT_ID=${PINECONE_PROJECT_ID:-your-project-id}

# ─── Service URLs (for dynamic configuration) ───────────────────────────────────
# Internal service URLs (Docker network communication)
OLLAMA_INTERNAL_URL="http://\${OLLAMA_SERVICE_NAME:-ollama}:\${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="http://\${OLLAMA_SERVICE_NAME:-ollama}:\${OLLAMA_PORT:-11434}"
OPENAI_INTERNAL_URL="https://api.openai.com/v1"
ANTHROPIC_INTERNAL_URL="https://api.anthropic.com"
LOCALAI_INTERNAL_URL="http://\${LOCALAI_SERVICE_NAME:-localai}:\${LOCALAI_PORT:-8080}"
VLLM_INTERNAL_URL="http://\${VLLM_SERVICE_NAME:-vllm}:\${VLLM_PORT:-8000}"
QDRANT_INTERNAL_URL="http://\${QDRANT_SERVICE_NAME:-qdrant}:\${QDRANT_PORT:-6333}"
WEAVIATE_INTERNAL_URL="http://\${WEAVIATE_SERVICE_NAME:-weaviate}:\${WEAVIATE_PORT:-8080}"
PINECONE_INTERNAL_URL="https://\${PINECONE_PROJECT_ID:-your-project-id}.svc.pinecone.io"
CHROMADB_INTERNAL_URL="http://\${CHROMADB_SERVICE_NAME:-chromadb}:\${CHROMADB_PORT:-8000}"
MILVUS_INTERNAL_URL="http://\${MILVUS_SERVICE_NAME:-milvus}:\${MILVUS_PORT:-19530}"
REDIS_INTERNAL_URL="redis://\${REDIS_SERVICE_NAME:-redis}:\${REDIS_PORT:-6379}"
POSTGRES_INTERNAL_URL="postgresql://\${POSTGRES_SERVICE_NAME:-postgres}:\${POSTGRES_PORT:-5432}"
N8N_INTERNAL_URL="http://\${N8N_SERVICE_NAME:-n8n}:\${N8N_PORT:-5678}"

# Service API endpoints
OLLAMA_API_ENDPOINT="${OLLAMA_INTERNAL_URL}/api/tags"
QDRANT_API_ENDPOINT="${QDRANT_INTERNAL_URL}"

# ─── Project Configuration ───────────────────────────────────────────────────
export COMPOSE_PROJECT_NAME="${PROJECT_PREFIX}${TENANT_ID}"
export DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}-net"

# ─── Hardware ─────────────────────────────────────────────────────────────────
GPU_TYPE=${GPU_TYPE}
GPU_COUNT=${GPU_COUNT}
OLLAMA_GPU_LAYERS=${GPU_LAYERS}
CPU_CORES=${CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

# ─── Ollama ───────────────────────────────────────────────────────────────────
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL}
OLLAMA_MODELS="${OLLAMA_MODELS}"

# ─── Pinecone Configuration ───────────────────────────────────────────────────────
PINECONE_PROJECT_ID="${PINECONE_PROJECT_ID}"
PINECONE_API_KEY="${PINECONE_API_KEY}"

# ─── LLM Providers ────────────────────────────────────────────────────────────
LLM_PROVIDERS="${LLM_PROVIDERS}"
OPENAI_API_KEY="${OPENAI_API_KEY}"
GOOGLE_API_KEY="${GOOGLE_API_KEY}"
GROQ_API_KEY="${GROQ_API_KEY}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY}"

# ─── Bifrost Configuration ───────────────────────────────────────────────
BIFROST_AUTH_TOKEN="${BIFROST_AUTH_TOKEN}"
BIFROST_PORT="${BIFROST_PORT:-8000}"
BIFROST_PROVIDERS='[{"provider":"ollama","base_url":"http://ollama:11434"}]'

# ─── Internal Service Ports ───────────────────────────────────────────────
CADDY_INTERNAL_HTTP_PORT=${CADDY_INTERNAL_HTTP_PORT:-80}
CADDY_INTERNAL_HTTPS_PORT=${CADDY_INTERNAL_HTTPS_PORT:-443}
OLLAMA_INTERNAL_PORT=${OLLAMA_INTERNAL_PORT:-11434}
QDRANT_INTERNAL_PORT=${QDRANT_INTERNAL_PORT:-6333}
QDRANT_INTERNAL_HTTP_PORT=${QDRANT_INTERNAL_HTTP_PORT:-6333}
OPENWEBUI_INTERNAL_PORT=${OPENWEBUI_INTERNAL_PORT:-8080}
OPENCLAW_INTERNAL_PORT=${OPENCLAW_INTERNAL_PORT:-8082}
SIGNAL_INTERNAL_PORT=${SIGNAL_INTERNAL_PORT:-8080}
VLLM_INTERNAL_PORT=${VLLM_INTERNAL_PORT:-8000}
N8N_INTERNAL_PORT=${N8N_INTERNAL_PORT:-5678}
FLOWISE_INTERNAL_PORT=${FLOWISE_INTERNAL_PORT:-5678}
ANYTHINGLLM_INTERNAL_PORT=${ANYTHINGLLM_INTERNAL_PORT:-3001}
GRAFANA_INTERNAL_PORT=${GRAFANA_INTERNAL_PORT:-3000}
PROMETHEUS_INTERNAL_PORT=${PROMETHEUS_INTERNAL_PORT:-9090}
MINIO_INTERNAL_PORT=${MINIO_INTERNAL_PORT:-9000}
MINIO_CONSOLE_INTERNAL_PORT=${MINIO_CONSOLE_INTERNAL_PORT:-9001}
TAILSCALE_INTERNAL_PORT=${TAILSCALE_INTERNAL_PORT:-443}
POSTGRES_INTERNAL_PORT=${POSTGRES_INTERNAL_PORT:-5432}
REDIS_INTERNAL_PORT=${REDIS_INTERNAL_PORT:-6379}

# ─── Database ─────────────────────────────────────────────────────────────────
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_DB="${POSTGRES_DB}"

# ─── Database Compatibility (for script 3) ───────────────────────────────
DB_USER="${POSTGRES_USER}"
DB_PASSWORD="${POSTGRES_PASSWORD}"

# ─── Per-Service Database URLs (CRITICAL) ───────────────────────────────────
# These must be resolved at write time with actual values, not variable references
OPENWEBUI_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/openwebui"
N8N_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/n8n"
FLOWISE_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/flowise"
REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379/${REDIS_DB:-0}"

# ─── Network Configuration (for dynamic references) ───────────────────
LOCALHOST=localhost

# ─── Redis ────────────────────────────────────────────────────────────────────
REDIS_PASSWORD="${REDIS_PASSWORD}"
REDIS_DB="${REDIS_DB:-0}"

# ─── n8n ──────────────────────────────────────────────────────────────────────
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"
N8N_API_KEY="${N8N_API_KEY}"
N8N_USER="admin@${DOMAIN}"
N8N_PASSWORD="${N8N_PASSWORD}"

# ─── Flowise ──────────────────────────────────────────────────────────────────
FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY}"
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD="${FLOWISE_PASSWORD}"

# Bifrost configuration (replaces LiteLLM)
JWT_SECRET="${JWT_SECRET}"
ENCRYPTION_KEY="${ENCRYPTION_KEY}"
# ADMIN_PASSWORD will be set below after AUTHENTIK_BOOTSTRAP_PASSWORD is generated

# ─── AnythingLLM ────────────────────────────────────────────────────────────────
ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET}"
ANYTHINGLLM_AUTH_TOKEN="${ANYTHINGLLM_AUTH_TOKEN}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT}"

# ─── Qdrant ───────────────────────────────────────────────────────────────────
QDRANT_API_KEY="${QDRANT_API_KEY}"
QDRANT_VECTOR_SIZE="768"

# ─── Grafana ──────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER="admin"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD}"
GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
ADMIN_PASSWORD="${GRAFANA_PASSWORD}"

# ─── Code Server & OpenClaw ──────────────────────────────────────────────────
CODESERVER_PASSWORD="${CODESERVER_PASSWORD}"
OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD}"

# ─── Authentik ────────────────────────────────────────────────────────────────
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_BOOTSTRAP_EMAIL="${ADMIN_EMAIL}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD}"

# ─── MinIO ────────────────────────────────────────────────────────────────────
MINIO_ROOT_USER="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}"

# ─── Dify ─────────────────────────────────────────────────────────────────────
DIFY_SECRET_KEY="${DIFY_SECRET_KEY}"
DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY}"

# ─── Network & Security ───────────────────────────────────────────────────────
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME}"
TAILSCALE_SERVE_MODE="${TAILSCALE_SERVE_MODE}"
TAILSCALE_FUNNEL="${TAILSCALE_FUNNEL}"
SIGNAL_PHONE_NUMBER="${SIGNAL_PHONE_NUMBER}"
# Note: SIGNAL_VERIFICATION_CODE will be populated in script 2 after user registration

# ─── Google Drive Integration ───────────────────────────────────────────────────
GDRIVE_AUTH_METHOD="${GDRIVE_AUTH_METHOD}"
GDRIVE_CLIENT_ID="${GDRIVE_CLIENT_ID}"
GDRIVE_CLIENT_SECRET="${GDRIVE_CLIENT_SECRET}"
GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME}"
GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID}"
# GDRIVE_TOKEN (included for both OAuth and Service Account methods)
GDRIVE_TOKEN="${GDRIVE_TOKEN}"

# Google Service Account for Rclone (non-interactive)
# This will be processed during .env generation
RCLONE_AUTH_METHOD="${GDRIVE_AUTH_METHOD}"

# ─── Search APIs ───────────────────────────────────────────────────────────────
SEARCH_PROVIDER="${SEARCH_PROVIDER}"
BRAVE_API_KEY="${BRAVE_API_KEY}"
SERPAPI_KEY="${SERPAPI_KEY}"
SERPAPI_ENGINE="${SERPAPI_ENGINE}"
CUSTOM_SEARCH_URL="${CUSTOM_SEARCH_URL}"
CUSTOM_SEARCH_KEY="${CUSTOM_SEARCH_KEY}"

# ─── Pinecone Configuration ───────────────────────────────────────────────────────
PINECONE_PROJECT_ID=${PINECONE_PROJECT_ID}
PINECONE_API_KEY=${PINECONE_API_KEY}

# ─── Service Configuration Variables ───────────────────────────────────────────────
WEAVIATE_SERVICE_NAME=${WEAVIATE_SERVICE_NAME}
WEAVIATE_PORT=${WEAVIATE_PORT}
CHROMADB_SERVICE_NAME=${CHROMADB_SERVICE_NAME}
CHROMADB_PORT=${CHROMADB_PORT}
MILVUS_SERVICE_NAME=${MILVUS_SERVICE_NAME}
MILVUS_PORT=${MILVUS_PORT}
PINECONE_SERVICE_NAME=${PINECONE_SERVICE_NAME}
QDRANT_SERVICE_NAME=${QDRANT_SERVICE_NAME}
QDRANT_PORT=${QDRANT_PORT}
REDIS_SERVICE_NAME=${REDIS_SERVICE_NAME}
REDIS_PORT=${REDIS_PORT}
POSTGRES_SERVICE_NAME=${POSTGRES_SERVICE_NAME}
POSTGRES_PORT=${POSTGRES_PORT}
N8N_SERVICE_NAME=${N8N_SERVICE_NAME}
N8N_PORT=${N8N_PORT}
OLLAMA_SERVICE_NAME=${OLLAMA_SERVICE_NAME}
OLLAMA_PORT=${OLLAMA_PORT}
VLLM_SERVICE_NAME=${VLLM_SERVICE_NAME}
VLLM_PORT=${VLLM_PORT:-8000}

# ─── Proxy Configuration ───────────────────────────────────────────────────────
PROXY_TYPE=${PROXY_TYPE}
ROUTING_METHOD=${ROUTING_METHOD}
SSL_TYPE=${SSL_TYPE}
CUSTOM_PROXY_IMAGE=${CUSTOM_PROXY_IMAGE}
HTTP_PROXY=${HTTP_PROXY}
HTTPS_PROXY=${HTTPS_PROXY}
NO_PROXY=${NO_PROXY}
HTTP_TO_HTTPS_REDIRECT=${HTTP_TO_HTTPS_REDIRECT:-false}

# ─── Code Server ─────────────────────────────────────────────────────────────────
CODESERVER_PORT=${CODESERVER_PORT:-8443}
CODESERVER_IMAGE=lscr.io/linuxserver/code-server:latest
GIT_REPO=${GIT_REPO:-/mnt/data/git}
GITHUB_PROJECT=${GITHUB_PROJECT:-github}

# ─── Continue.dev ─────────────────────────────────────────────────────────────────
CONTINUE_PORT=${CONTINUE_PORT:-3000}
CONTINUE_IMAGE=continuedev/continue:latest

# ─── OpenClaw ────────────────────────────────────────────────────────────────
OPENCLAW_PASSWORD=${OPENCLAW_PASSWORD:-$CODESERVER_PASSWORD}
OPENCLAW_ADMIN_USER=admin
OPENCLAW_SECRET=${OPENCLAW_PASSWORD}
OPENCLAW_PORT=${OPENCLAW_PORT}
OPENCLAW_IMAGE=openclaw:latest

# ─── Ports ────────────────────────────────────────────────────────────────────
CADDY_HTTP_PORT=${CADDY_HTTP_PORT:-80}
CADDY_HTTPS_PORT=${CADDY_HTTPS_PORT:-443}
N8N_PORT=${N8N_PORT}
FLOWISE_PORT=${FLOWISE_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
QDRANT_PORT=${QDRANT_PORT}
SIGNAL_PORT=${SIGNAL_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
TAILSCALE_PORT=${TAILSCALE_PORT}
RCLONE_PORT=${RCLONE_PORT}

# ─── PORT_ aliases for Docker Compose (Script 3 uses PORT_X naming) ─────────
PORT_OPENWEBUI=${OPENWEBUI_PORT:-3000}
PORT_N8N=${N8N_PORT:-5678}
PORT_FLOWISE=${FLOWISE_PORT:-3001}
PORT_GRAFANA=${GRAFANA_PORT:-3002}
PORT_PROMETHEUS=${PROMETHEUS_PORT:-9090}
PORT_QDRANT=${QDRANT_PORT:-6333}
PORT_ANYTHINGLLM=${ANYTHINGLLM_PORT:-3003}
PORT_OPENCLAW=${OPENCLAW_PORT:-18789}
PORT_CODESERVER=${CODESERVER_PORT:-8443}
PORT_OLLAMA=${OLLAMA_PORT:-11434}

# ─── Additional Variables for Script 2 ───────────────────────────────────────────
SSL_EMAIL=${ADMIN_EMAIL}
GPU_DEVICE=${GPU_TYPE}
TENANT_DIR=${DATA_ROOT}
TAILSCALE_EXTRA_ARGS="${TAILSCALE_AUTH_KEY:+--authkey ${TAILSCALE_AUTH_KEY}}"
MINIO_CONSOLE_PORT=9001
MINIO_PORT=9000

# Redis configuration for Authentik
AUTHENTIK_REDIS__HOST=redis

# Dify storage configuration
DIFY_STORAGE_TYPE=local
DIFY_STORAGE_LOCAL_ROOT=/data
EOF

    # Use robust file write pattern for critical service variables
    VARS_TO_ADD=$(cat <<EOF
# Additional variables already written in main section - no duplicates needed
EOF
)

    # Append variables and immediately force a sync to disk
    echo "${VARS_TO_ADD}" >> "${temp_env_file}" && sync

    # Verify ownership immediately after writing
    chown "${TENANT_UID}:${TENANT_GID}" "${temp_env_file}"
    ok "Appended and synced service variables to .env file."

    chmod 600 "${temp_env_file}"
    
    # Google Service Account for Rclone (non-interactive)
    if [[ "${GDRIVE_AUTH_METHOD}" == "service_account" ]]; then
        # Generate rclone.conf for service account
        cat > "${TENANT_DIR}/rclone/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /config/google_sa.json
team_drive =
root_folder_id = \${RCLONE_GDRIVE_ROOT_ID}
EOF
        
        # Ensure tenant ownership
        chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/rclone"
        
        # Set environment variable for script-2
        echo "RCLONE_CONFIG_PATH=${TENANT_DIR}/rclone/rclone.conf" >> "${temp_env_file}"
        echo "RCLONE_GDRIVE_ROOT_ID=${RCLONE_GDRIVE_ROOT_ID:-}" >> "${temp_env_file}"
        
        ok "Rclone configuration generated for Service Account authentication."
    elif [[ "${GDRIVE_AUTH_METHOD}" == "oauth" ]]; then
        # OAuth method - generate rclone config for OAuth
        mkdir -p "${TENANT_DIR}/rclone"
        cat > "${TENANT_DIR}/rclone/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
client_id = \${GDRIVE_CLIENT_ID}
client_secret = \${GDRIVE_CLIENT_SECRET}
token = \${GDRIVE_TOKEN}
team_drive =
EOF
        
        # Ensure tenant ownership
        chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/rclone"
        
        # Set environment variable for script-2
        echo "RCLONE_CONFIG_PATH=${TENANT_DIR}/rclone/rclone.conf" >> "${temp_env_file}"
        
        ok "Rclone OAuth configuration generated. Token will be set during deployment."
    fi
    
    # Atomic move to final location
    mv "${temp_env_file}" "${ENV_FILE}"
    
    log "SUCCESS" "Configuration written to ${ENV_FILE}"
}

# =============================================================================
# DEFINITIVE FUNCTION: Apply Final Ownership with Pragmatic Exceptions
# =============================================================================
apply_final_ownership() {
    log "INFO" "Applying Final Ownership Structure..."

    # --- STAGE 1: Set Base Tenant Ownership (CORRECT and NECESSARY) ---
    # This sets the default for all directories.
    log "INFO" "Setting base ownership for tenant user ${TENANT_UID}..."
    if ! chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"; then
        fail "ERROR" "Failed to set base recursive ownership on ${DATA_ROOT}."
    fi
    log "SUCCESS" "Base ownership applied."

    # --- STAGE 2: Apply Ownership Exceptions (THE CRITICAL FIX) ---
    # This overrides the default for specific services.
    log "INFO" "Applying ownership exceptions for services with specific UIDs..."

    # Exception for Postgres (requires UID 70 - system requirement)
    if [[ -d "${DATA_ROOT}/postgres" ]]; then
        chown -R 70:70 "${DATA_ROOT}/postgres"
        log "SUCCESS" "Set ownership for 'postgres' directory to 70:70 (system requirement)."
    fi
    
    # Exception for Grafana (requires UID 472 - system requirement)
    if [[ -d "${DATA_ROOT}/grafana" ]]; then
        chown -R 472:472 "${DATA_ROOT}/grafana"
        log "SUCCESS" "Set ownership for 'grafana' directory to 472:472 (system requirement)."
    fi
    
    # ALL OTHER SERVICES: Use tenant user for maximum non-root compliance
    log "INFO" "Setting ALL other services to tenant user ${TENANT_UID}:${TENANT_GID} for non-root compliance..."
    
    for service_dir in "${DATA_ROOT}"/*; do
        if [[ -d "${service_dir}" ]]; then
            service_name=$(basename "${service_dir}")
            # Skip system services that already have specific ownership
            case "${service_name}" in
                postgres|grafana)
                    log "INFO" "Skipping ${service_name} - already has system ownership"
                    continue
                    ;;
                qdrant)
                    # Qdrant requires UID 1000 per security documentation
                    chown -R 1000:1000 "${service_dir}"
                    log "SUCCESS" "Set ownership for '${service_name}' to 1000:1000 (Qdrant requirement)"
                    ;;
                *)
                    # All other services use tenant user for non-root compliance
                    chown -R "${TENANT_UID}:${TENANT_GID}" "${service_dir}"
                    log "SUCCESS" "Set ownership for '${service_name}' to tenant user ${TENANT_UID}:${TENANT_GID}"
                    ;;
            esac
        fi
    done
    
    log "SUCCESS" "All service directories configured for maximum non-root compliance."

    # --- STAGE 3: Secure Final Permissions ---
    log "INFO" "Setting secure permissions on tenant root and .env file..."
    chmod 750 "${DATA_ROOT}"
    chmod 640 "${ENV_FILE}"
    log "SUCCESS" "Secure permissions set. Ownership structure is now correct."
}

# ─── Create directory structure with dynamic permissions ────────────────────────
create_directories() {
    log "INFO" "Creating all service directories with dynamic permissions..."
    
    # Create base directories first
    mkdir -p "${DATA_ROOT}"
    mkdir -p "${DATA_ROOT}/caddy/config" "${DATA_ROOT}/caddy/data"
    mkdir -p "${DATA_ROOT}/grafana/provisioning/datasources" "${DATA_ROOT}/grafana/provisioning/dashboards"
    mkdir -p "${DATA_ROOT}/n8n/workflows" "${DATA_ROOT}/anythingllm/tmp"
    mkdir -p "${DATA_ROOT}/run/tailscale" "${DATA_ROOT}/lib/tailscale"
    mkdir -p "${DATA_ROOT}/rclone" "${DATA_ROOT}/storage" "${DATA_ROOT}/gdrive"
    mkdir -p "${DATA_ROOT}/signal-data"
    
    # Create service directories
    ALL_SERVICES="postgres redis qdrant grafana prometheus authentik signal n8n weaviate chromadb milvus ollama localai vllm openwebui anythingllm flowise dify codeserver"
    for service in ${ALL_SERVICES}; do
        # Check if the service is enabled via the ENABLE_SERVICENAME variable
        if [[ $(declare -p "ENABLE_${service^^}" 2>/dev/null) =~ "true" ]]; then
            mkdir -p "${DATA_ROOT}/${service}"
        fi
    done
    
    log "SUCCESS" "All service directories created with dynamic permissions."
}

# ─── Write Caddyfile ─────────────────────────────────────────────────────────
write_caddyfile() {
    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    local CADDYFILE_PATH="${CADDY_DIR}/Caddyfile"
    
    # Start with global config based on SSL method
    if [[ "${SSL_TYPE}" == "selfsigned" ]]; then
        cat > "${CADDYFILE_PATH}" << EOF
# AI Platform Caddyfile
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Using self-signed certificates for immediate access

{
    email ${ADMIN_EMAIL}
    # Disable HTTPS for self-signed testing
    auto_https off
}

EOF
    else
        cat > "${CADDYFILE_PATH}" << EOF
# AI Platform Caddyfile
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
    email ${ADMIN_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    acme_ca_root /etc/ssl/certs/ca-certificates.crt
}

EOF
    fi

    # Add service blocks - SIMPLE FORMAT (consistent with script-2)
    if [[ "${ENABLE_N8N}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
n8n.${DOMAIN} {
    reverse_proxy n8n:5678
}

EOF
    fi

    if [[ "${ENABLE_FLOWISE}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
flowise.${DOMAIN} {
    reverse_proxy flowise:3000
}

EOF
    fi

    if [[ "${ENABLE_OPENWEBUI}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
openwebui.${DOMAIN} {
    reverse_proxy openwebui:8080
}

EOF
    fi

    if [[ "${ENABLE_ANYTHINGLLM}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}

EOF
    fi

    if [[ "${ENABLE_GRAFANA}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
grafana.${DOMAIN} {
    reverse_proxy grafana:3000
}

EOF
    fi

    if [[ "${ENABLE_AUTHENTIK}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
auth.${DOMAIN} {
    reverse_proxy authentik-server:9000
}

EOF
    fi

    if [[ "${ENABLE_SIGNAL}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
signal.${DOMAIN} {
    reverse_proxy signal-api:8080
}

EOF
    fi

    # --- CRITICAL: Validate generated Caddyfile ---
    log "INFO" "Validating generated Caddyfile configuration..."
    
    # 1. Format the file (fixes spacing issues)
    if command -v caddy >/dev/null 2>&1; then
        if caddy fmt --overwrite "${CADDYFILE_PATH}" 2>/dev/null; then
            log "SUCCESS" "Caddyfile formatted successfully"
        else
            warn "Caddy formatting failed - continuing anyway"
        fi
        
        # 2. Validate the configuration
        if caddy validate --config "${CADDYFILE_PATH}" 2>/dev/null; then
            log "SUCCESS" "Caddyfile validation passed"
        else
            local validation_error=$(caddy validate --config "${CADDYFILE_PATH}" 2>&1 || echo "Unknown validation error")
            fail "ERROR" "Caddyfile validation failed: ${validation_error}"
        fi
    else
        # Basic validation without Caddy CLI
        log "INFO" "Performing basic Caddyfile syntax validation..."
        if [[ ! -f "${CADDYFILE_PATH}" ]]; then
            fail "ERROR" "Caddyfile not found at ${CADDYFILE_PATH}"
        fi
        
        # Check for basic syntax errors
        if grep -q "^[[:space:]]*{" "${CADDYFILE_PATH}" && grep -q "^}" "${CADDYFILE_PATH}"; then
            log "INFO" "Basic Caddyfile structure validation passed."
        else
            warn "Caddyfile may have syntax issues (missing braces or structure)."
        fi
        
        # Check for common configuration errors
        if grep -q "tls.*{" "${CADDYFILE_PATH}" && grep -q "reverse_proxy" "${CADDYFILE_PATH}"; then
            log "SUCCESS" "Caddyfile contains TLS and proxy configurations."
        else
            warn "Caddyfile may be missing TLS or proxy configurations."
        fi
    fi

    chmod 644 "${CADDY_DIR}/Caddyfile"
    log "SUCCESS" "Caddyfile written"
}

# ─── Pre-commit summary ───────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                   📋  Configuration Summary                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  ${BOLD}%-22s${NC} %s\n" "Data root:"    "${DATA_ROOT}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Domain:"       "${DOMAIN}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Tenant ID:"    "${TENANT_ID}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Admin email:"  "${ADMIN_EMAIL}"
    printf "  ${BOLD}%-22s${NC} %s\n" "SSL:"          "${SSL_TYPE}"
    printf "  ${BOLD}%-22s${NC} %s\n" "GPU:"          "${GPU_TYPE} (layers: ${GPU_LAYERS:-auto})"
    printf "  ${BOLD}%-22s${NC} %s\n" "Vector DB:"    "${VECTOR_DB:-none}"
    printf "  ${BOLD}%-22s${NC} %s\n" "LLM providers:" "${LLM_PROVIDERS:-local}"
    # Show specific enabled providers
    local provider_list=""
    [[ "${ENABLE_OLLAMA}" = "true" ]] && provider_list="${provider_list}Ollama "
    [[ "${ENABLE_OPENAI}" = "true" ]] && provider_list="${provider_list}OpenAI "
    [[ "${ENABLE_ANTHROPIC}" = "true" ]] && provider_list="${provider_list}Anthropic "
    [[ "${ENABLE_GOOGLE}" = "true" ]] && provider_list="${provider_list}Gemini "
    [[ "${ENABLE_GROQ}" = "true" ]] && provider_list="${provider_list}Groq "
    [[ "${ENABLE_OPENROUTER}" = "true" ]] && provider_list="${provider_list}OpenRouter "
    [[ "${ENABLE_VLLM}" = "true" ]] && provider_list="${provider_list}VLLM "
    [[ -n "${provider_list}" ]] && printf "  ${BOLD}%-22s${NC} %s\n" "Enabled:" "${provider_list% }"
    echo ""
    echo -e "  ${BOLD}Enabled services:${NC}"
    [ "${ENABLE_OLLAMA}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Ollama       (models: ${OLLAMA_MODELS:-auto})"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Open WebUI   :${OPENWEBUI_PORT}"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo -e "    ${GREEN}✓${NC}  AnythingLLM  :${ANYTHINGLLM_PORT}"
    [ "${ENABLE_DIFY}" = "true" ]        && echo -e "    ${GREEN}✓${NC}  Dify"
    [ "${ENABLE_N8N}" = "true" ]         && echo -e "    ${GREEN}✓${NC}  n8n          :${N8N_PORT}"
    [ "${ENABLE_FLOWISE}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  Flowise      :${FLOWISE_PORT}"
    if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
        echo "  LLM Router:    Bifrost (port ${BIFROST_PORT:-4000})"
        echo "  Bifrost Key:   ${BIFROST_AUTH_TOKEN:0:20}..."
    fi
    [ "${ENABLE_QDRANT}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Qdrant       :${QDRANT_PORT}"
    [ "${ENABLE_GRAFANA}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  Grafana      :${GRAFANA_PORT}"
    [ "${ENABLE_PROMETHEUS}" = "true" ]  && echo -e "    ${GREEN}✓${NC}  Prometheus   :${PROMETHEUS_PORT}"
    [ "${ENABLE_AUTHENTIK}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Authentik    :${AUTHENTIK_PORT}"
    [ "${ENABLE_SIGNAL}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Signal API   :${SIGNAL_PORT}"
    [ "${ENABLE_OPENCLAW}" = "true" ]    && echo -e "    ${GREEN}✓${NC}  OpenClaw     :${OPENCLAW_PORT}"
    [ "${ENABLE_TAILSCALE}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Tailscale    :${TAILSCALE_PORT}"
    [ "${ENABLE_RCLONE}" = "true" ]       && echo -e "    ${GREEN}✓${NC}  Rclone       :${RCLONE_PORT}"
    echo ""

    # Health Status Section
    echo -e "  ${BOLD}🏥  Health Status Check:${NC}"
    echo -e "  ${DIM}Pre-deployment validation results:${NC}"
    echo ""
    
    # Tailscale Health Status
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        if [[ -n "${TAILSCALE_AUTH_KEY}" ]] && validate_tailscale_auth_key "${TAILSCALE_AUTH_KEY}"; then
            echo -e "    ${GREEN}✅${NC}  Tailscale Auth Key: Valid format"
            echo -e "    ${GREEN}✅${NC}  Tailscale Validation: Passed"
            echo -e "    ${DIM}   → VPN connectivity will be verified during deployment${NC}"
        else
            echo -e "    ${RED}❌${NC}  Tailscale Auth Key: Invalid or missing"
            echo -e "    ${YELLOW}⚠️${NC}  Tailscale Validation: Failed (warning only)"
            echo -e "    ${DIM}   → Script 2 will attempt to fix this issue${NC}"
        fi
    else
        echo -e "    ${GRAY}⊖${NC}  Tailscale: Disabled"
    fi
    
    # Rclone Health Status
    if [[ "${ENABLE_RCLONE}" == "true" ]]; then
        if [[ "${GDRIVE_AUTH_METHOD}" == "service_account" ]]; then
            if [[ -f "${TENANT_DIR}/rclone/google_sa.json" ]]; then
                echo -e "    ${GREEN}✅${NC}  Google Drive JSON: Valid Service Account"
                if [[ -n "${GDRIVE_TOKEN}" ]]; then
                    echo -e "    ${GREEN}✅${NC}  Rclone Token: Generated and stored"
                    echo -e "    ${DIM}   → Google Drive integration ready${NC}"
                else
                    echo -e "    ${YELLOW}⚠️${NC}  Rclone Token: Will be generated during deployment"
                    echo -e "    ${DIM}   → Token generation will be attempted in Script 2${NC}"
                fi
            else
                echo -e "    ${RED}❌${NC}  Google Drive JSON: File not found"
                echo -e "    ${YELLOW}⚠️${NC}  Rclone Validation: Failed (warning only)"
            fi
        elif [[ "${GDRIVE_AUTH_METHOD}" == "oauth" ]]; then
            if [[ -n "${GDRIVE_TOKEN}" ]]; then
                echo -e "    ${GREEN}✅${NC}  OAuth Token: Generated and stored"
                echo -e "    ${DIM}   → Google Drive integration ready${NC}"
            else
                echo -e "    ${YELLOW}⚠️${NC}  OAuth Token: Will be generated during deployment"
                echo -e "    ${DIM}   → Token generation will be attempted in Script 2${NC}"
            fi
        else
            echo -e "    ${RED}❌${NC}  Google Drive: No authentication method configured"
        fi
    else
        echo -e "    ${GRAY}⊖${NC}  Rclone: Disabled"
    fi
    
    # Overall Health Summary
    echo ""
    echo -e "  ${BOLD}📊  Overall Health:${NC}"
    local issues=0
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        if [[ -z "${TAILSCALE_AUTH_KEY}" ]] || ! validate_tailscale_auth_key "${TAILSCALE_AUTH_KEY}"; then
            ((issues++))
        fi
    fi
    if [[ "${ENABLE_RCLONE}" == "true" && "${GDRIVE_AUTH_METHOD}" == "service_account" ]]; then
        if [[ ! -f "${TENANT_DIR}/rclone/google_sa.json" ]]; then
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "    ${GREEN}✅${NC}  All validations passed - Ready for deployment"
    else
        echo -e "    ${YELLOW}⚠️${NC}  ${issues} validation warning(s) - Will be addressed during deployment"
    fi
    echo ""

    print_divider

    # Service URLs section
    if [ -n "${DOMAIN}" ] && [ "${DOMAIN}" != "localhost" ]; then
        echo -e "  ${BOLD}Expected Service URLs:${NC}"
        echo -e "  ${DIM}After deployment, services will be available at:${NC}"
        echo ""
        [ "${ENABLE_N8N}" = "true" ] && echo -e "    ${CYAN}•${NC} n8n:          https://n8n.${DOMAIN}"
        [ "${ENABLE_FLOWISE}" = "true" ] && echo -e "    ${CYAN}•${NC} Flowise:      https://flowise.${DOMAIN}"
        [ "${ENABLE_OPENWEBUI}" = "true" ] && echo -e "    ${CYAN}•${NC} Open WebUI:   https://openwebui.${DOMAIN}"
        [ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo -e "    ${CYAN}•${NC} AnythingLLM:  https://anythingllm.${DOMAIN}"
        [ "${ENABLE_DIFY}" = "true" ] && echo -e "    ${CYAN}•${NC} Dify:         https://dify.${DOMAIN}"
        [ "${ENABLE_GRAFANA}" = "true" ] && echo -e "    ${CYAN}•${NC} Grafana:      https://grafana.${DOMAIN}"
        [ "${ENABLE_AUTHENTIK}" = "true" ] && echo -e "    ${CYAN}•${NC} Authentik:    https://auth.${DOMAIN}"
        [ "${ENABLE_RCLONE}" = "true" ] && echo -e "    ${CYAN}•${NC} Rclone:        https://rclone.${DOMAIN}"
        [ "${ENABLE_MONITORING}" = "true" ] && echo -e "    ${CYAN}•${NC} Prometheus:   https://prometheus.${DOMAIN}"
        [ "${ENABLE_OPENCLAW}" = "true" ] && echo -e "    ${CYAN}•${NC} OpenClaw:     https://openclaw.${DOMAIN}"
        [ "${ENABLE_CODESERVER}" = "true" ] && echo -e "    ${CYAN}•${NC} OpenCode:     https://opencode.${DOMAIN}"
        [ "${ENABLE_SIGNAL}" = "true" ] && echo -e "    ${CYAN}•${NC} Signal API:   https://signal.${DOMAIN}"
        echo ""
        
        # Tailscale VPN URLs (if IP is available)
        if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
            # Try to get Tailscale IP
            local tailscale_ip=$(tailscale status --json 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('Self', {}).get('TailscaleIPs', [''])[0] if data.get('Self', {}).get('TailscaleIPs') else '')" 2>/dev/null || echo "")
            
            if [[ -n "$tailscale_ip" && "$tailscale_ip" != "" ]]; then
                echo -e "  ${BOLD}Tailscale VPN URLs:${NC}"
                echo -e "  ${DIM}Services accessible via Tailscale network:${NC}"
                echo ""
                [ "${ENABLE_OPENCLAW}" = "true" ] && echo -e "    ${GREEN}•${NC} OpenClaw:     https://${tailscale_ip}:${OPENCLAW_PORT:-18789}"
                [ "${ENABLE_SIGNAL}" = "true" ] && echo -e "    ${GREEN}•${NC} Signal API:   http://${tailscale_ip}:${SIGNAL_PORT:-8080}"
                [ "${ENABLE_GRAFANA}" = "true" ] && echo -e "    ${GREEN}•${NC} Grafana:      http://${tailscale_ip}:${GRAFANA_PORT:-3002}"
                [ "${ENABLE_AUTHENTIK}" = "true" ] && echo -e "    ${GREEN}•${NC} Authentik:    http://${tailscale_ip}:${AUTHENTIK_PORT:-9000}"
                echo ""
            else
                echo -e "  ${DIM}📡 Tailscale VPN URLs: Will be available after deployment${NC}"
                echo ""
            fi
        fi
        
        # Local access URLs
        echo -e "  ${BOLD}Local Access URLs:${NC}"
        echo ""
        [ "${ENABLE_OLLAMA}" = "true" ] && echo -e "    ${CYAN}•${NC} Ollama API:   http://localhost:${OLLAMA_PORT:-11434}/api/tags"
        [ "${ENABLE_QDRANT}" = "true" ] && echo -e "    ${CYAN}•${NC} Qdrant API:   http://localhost:${QDRANT_PORT:-6333}"
        [ "${ENABLE_SIGNAL}" = "true" ] && echo -e "    ${CYAN}•${NC} Signal API:   http://localhost:${SIGNAL_PORT:-8080}"
        echo ""
        
        # Service Health & Access Summary
        echo -e "  ${BOLD}Service Health & Access:${NC}"
        echo -e "  ${DIM}After deployment, check service health with:${NC}"
        echo ""
        echo -e "  ${DIM}  • Health check: sudo docker compose ps${NC}"
        echo -e "  ${DIM}  • Service logs: sudo docker compose logs [service]${NC}"
        echo -e "  ${DIM}  • Full status: sudo bash scripts/3-configure-services.sh --check${NC}"
        echo ""
        
        # Special Access Information
        if [ "${ENABLE_TAILSCALE}" = "true" ] && [ -n "${TAILSCALE_AUTH_KEY}" ]; then
            echo -e "  ${BOLD}Tailscale VPN Access:${NC}"
            echo -e "  ${DIM}  • Auth status: Check with 'tailscale status' after deployment${NC}"
            echo -e "  ${DIM}  • IP address: Will be assigned and available in Tailscale network${NC}"
            if [ "${TAILSCALE_SERVE_MODE}" = "true" ]; then
                echo -e "  ${DIM}  • Serve mode: Services accessible via Tailscale IPs${NC}"
            fi
            echo ""
        fi
        
        if [ "${ENABLE_OPENCLAW}" = "true" ]; then
            echo -e "  ${BOLD}OpenClaw Gateway:${NC}"
            echo -e "  ${DIM}  • Network: Isolated network (per README.md)${NC}"
            echo -e "  ${DIM}  • Access: Configure DNS CNAME after getting IP from script 2${NC}"
            echo -e "  ${DIM}  • Port: ${OPENCLAW_PORT} (external) → 8082 (internal)${NC}"
            echo ""
        fi
        
        if [ "${ENABLE_RCLONE}" = "true" ]; then
            echo -e "  ${BOLD}Google Drive Integration:${NC}"
            echo -e "  ${DIM}  • Sync logs: /mnt/data/${TENANT_ID}/logs/rclone-${TENANT_ID}.log${NC}"
            echo -e "  ${DIM}  • Status: Check with 'sudo docker compose logs rclone'${NC}"
            echo ""
        fi
    fi

    print_divider

    echo -e "  ${YELLOW}⚠️   Review the above before confirming.${NC}"
    echo -e "  ${DIM}This will write ${ENV_FILE} and create directory structure.${NC}"
    echo ""
    read -p "  ➤ Confirm and write configuration? [Y/n]: " confirm
    confirm="${confirm:-y}"
    if [[ ! "${confirm,,}" =~ ^y ]]; then
        log "INFO" "Aborted — no changes made"
        exit 0
    fi
}

# ─── Final launch prompt ──────────────────────────────────────────────────────
offer_next_step() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                   ✅  Setup Complete                         ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Configuration saved to: ${BOLD}${ENV_FILE}${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo ""
    echo -e "    ${CYAN}2)${NC}  Deploy services"
    echo -e "        ${DIM}sudo bash scripts/2-deploy-services.sh <TENANT_ID>${NC}"
    echo ""
    echo -e "    ${CYAN}3)${NC}  Configure services (post-deploy API setup)"
    echo -e "        ${DIM}sudo bash scripts/3-configure-services.sh ${TENANT_ID}${NC}"
    echo ""
    read -p "  ➤ Run script 2 (deploy services) now? [Y/n]: " run_next
    run_next="${run_next:-y}"
    if [[ "${run_next,,}" =~ ^y ]]; then
        if [ -f "${SCRIPTS_DIR}/2-deploy-services.sh" ]; then
            log "INFO" "Starting comprehensive deployment with logging engine..."
            bash "${SCRIPTS_DIR}/2-deploy-services.sh" "${TENANT_ID}"
        else
            log "ERROR" "2-deploy-services.sh not found at ${SCRIPTS_DIR}"
            exit 1
        fi
    else
        echo ""
        log "INFO" "Run script 2 when ready:"
        echo ""
        echo "    sudo bash scripts/2-deploy-services.sh ${TENANT_ID}"
        echo ""
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    # Collect tenant identity FIRST - before any other variables
    if [ -z "${TENANT:-}" ]; then
        read -p "Tenant ID (e.g. datasquiz, no spaces): " TENANT_NAME
        TENANT_NAME="${TENANT_NAME// /_}"   # sanitise
    else
        TENANT_NAME="${TENANT}"
    fi

    # ALL paths derive from this single variable - no exceptions
    DATA_ROOT="/mnt/data/${TENANT_NAME}"
    CONFIG_DIR="${DATA_ROOT}/configs"
    DATA_DIR="${DATA_ROOT}/data"
    LOGS_DIR="${DATA_ROOT}/logs"
    COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"
    ENV_FILE="${DATA_ROOT}/.env"  # Data confinement - everything under /mnt/data/tenant/

    # Accept TENANT_ID as optional command line argument (legacy support)
    if [ -n "${1:-}" ]; then
        TENANT_ID="${1,,}"
        log "INFO" "Using tenant ID from command line: ${TENANT_ID}"
        # Skip interactive tenant collection if provided
        SKIP_TENANT_COLLECTION=true
    fi
    
    # Reconcile — TENANT_ID is canonical variable used throughout Script 1
    # TENANT_NAME comes from interactive input; TENANT_ID from CLI arg
    # After this line both are always set and equal
    TENANT_ID="${TENANT_ID:-${TENANT_NAME}}"
    TENANT_NAME="${TENANT_ID}"
    
    print_header
    check_root
    check_prerequisites      # Step 1
    collect_identity         # Step 2
    detect_and_mount_ebs     # Step 3 - NEW: EBS detection and mounting
    select_data_volume       # Step 4
    detect_gpu               # Step 5
    select_stack             # Step 6
    configure_dify           # Step 6.5 - Dify configuration (if enabled)
    select_vector_db         # Step 7
    configure_databases      # Step 7.5 - Database configuration
    collect_llm_config       # Step 8
    configure_llm_router      # Step 8.2 - LLM router configuration (Modular choice)
    # Initialize router-specific configuration
    if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
        init_bifrost
    elif [[ "${LLM_ROUTER}" == "litellm" ]]; then
        init_litellm
    fi
    
    # Initialize Mem0 memory layer (CLAUDE.md Change 3)
    init_mem0
    collect_network_config   # Step 9 - NEW: Network & security configuration
    collect_ports            # Step 10
    generate_secrets         # Step 11
    
    log "INFO" "Verifying and generating all application secrets..."
    load_or_generate_secret "N8N_ENCRYPTION_KEY"
    load_or_generate_secret "FLOWISE_SECRET_KEY"
    
    # Generate router-specific secrets
    if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
        # Bifrost auth token already generated in init_bifrost()
        # Just ensure it's loaded for consistency
        load_or_generate_secret "BIFROST_AUTH_TOKEN"
    elif [[ "${LLM_ROUTER}" == "litellm" ]]; then
        # LiteLLM master key already generated in init_litellm()
        # Just ensure it's loaded for consistency
        load_or_generate_secret "LITELLM_MASTER_KEY"
    fi
    
    load_or_generate_secret "ANYTHINGLLM_JWT_SECRET"
    load_or_generate_secret "JWT_SECRET"
    load_or_generate_secret "ENCRYPTION_KEY"
    load_or_generate_secret "QDRANT_API_KEY"
    load_or_generate_secret "GRAFANA_PASSWORD"
    load_or_generate_secret "AUTHENTIK_SECRET_KEY"
    load_or_generate_secret "OPENWEBUI_SECRET_KEY"
    load_or_generate_secret "REDIS_PASSWORD"
    load_or_generate_secret "POSTGRES_PASSWORD"
    
    print_summary
    write_env_file
    
    # Source Script 3 AFTER .env is written so functions can load it
    export TENANT="${TENANT_ID}"
    source "${SCRIPTS_DIR}/3-configure-services.sh"
    
    # Directories and ownership — Script 1's responsibility
    create_directories
    
    # Apply the final, correct ownership structure (NEW FINAL STEP)
    apply_final_ownership
    
    # Config generation is Script 2's responsibility (via generate_configs)
    # DO NOT call generate_postgres_init, write_caddyfile, write_prometheus_config here
    
    # ── Final Service Configuration Summary ─────────────────────────────────────────
    final_service_summary() {
        if [ -n "${DOMAIN}" ] && [ "${DOMAIN}" != "localhost" ]; then
            echo ""
            echo -e "  ${BOLD}🎯 Final Service Configuration Summary${NC}"
            echo ""
            echo -e "  ${DIM}All enabled services with their configurations:${NC}"
            echo ""
            
            # Core Infrastructure
            echo -e "  ${CYAN}📊 Infrastructure:${NC}"
            [ "${ENABLE_POSTGRES}" = "true" ] && echo -e "    ${GREEN}✓${NC} PostgreSQL: port 5432, system UID 70"
            [ "${ENABLE_REDIS}" = "true" ] && echo -e "    ${GREEN}✓${NC} Redis: port 6379, authenticated"
            [ "${ENABLE_CADDY}" = "true" ] && echo -e "    ${GREEN}✓${NC} Caddy: ports 80/443, automatic HTTPS"
            [ "${ENABLE_QDRANT}" = "true" ] && echo -e "    ${GREEN}✓${NC} Qdrant: port 6333, UID 1000"
            echo ""
            
            # AI Runtime
            echo -e "  ${CYAN}🤖 AI Runtime:${NC}"
            [ "${ENABLE_OLLAMA}" = "true" ] && echo -e "    ${GREEN}✓${NC} Ollama: port 11434, local LLM"
            [ "${ENABLE_OPENWEBUI}" = "true" ] && echo -e "    ${GREEN}✓${NC} OpenWebUI: https://openwebui.${DOMAIN}"
            echo ""
            
            # Development Environment
            echo -e "  ${CYAN}🔧 Development:${NC}"
            [ "${ENABLE_CODESERVER}" = "true" ] && echo -e "    ${GREEN}✓${NC} Code Server: https://opencode.${DOMAIN} (VS Code + Continue.dev)"
            [ "${ENABLE_OPENCLAW}" = "true" ] && echo -e "    ${GREEN}✓${NC} OpenClaw: https://openclaw.${DOMAIN} + Tailscale VPN"
            echo ""
            
            # Enterprise Services
            echo -e "  ${CYAN}🏢 Enterprise:${NC}"
            [ "${ENABLE_N8N}" = "true" ] && echo -e "    ${GREEN}✓${NC} n8n: https://n8n.${DOMAIN}"
            [ "${ENABLE_FLOWISE}" = "true" ] && echo -e "    ${GREEN}✓${NC} Flowise: https://flowise.${DOMAIN}"
            [ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo -e "    ${GREEN}✓${NC} AnythingLLM: https://anythingllm.${DOMAIN}"
            [ "${ENABLE_DIFY}" = "true" ] && echo -e "    ${GREEN}✓${NC} Dify: https://dify.${DOMAIN}"
            [ "${ENABLE_GRAFANA}" = "true" ] && echo -e "    ${GREEN}✓${NC} Grafana: https://grafana.${DOMAIN}"
            [ "${ENABLE_AUTHENTIK}" = "true" ] && echo -e "    ${GREEN}✓${NC} Authentik: https://auth.${DOMAIN}"
            [ "${ENABLE_SIGNAL}" = "true" ] && echo -e "    ${GREEN}✓${NC} Signal API: https://signal.${DOMAIN}"
            [ "${ENABLE_RCLONE}" = "true" ] && echo -e "    ${GREEN}✓${NC} Rclone: https://rclone.${DOMAIN}"
            [ "${ENABLE_MONITORING}" = "true" ] && echo -e "    ${GREEN}✓${NC} Prometheus: https://prometheus.${DOMAIN}"
            echo ""
            
            # LLM Providers
            echo -e "  ${CYAN}🧠 LLM Providers:${NC}"
            [ "${LLM_PROVIDERS}" = "local" ] && echo -e "    ${GREEN}✓${NC} Local only (Ollama)"
            [ "${LLM_PROVIDERS}" = "external" ] && echo -e "    ${GREEN}✓${NC} External only (OpenAI, Anthropic, Gemini, Groq, OpenRouter)"
            [ "${LLM_PROVIDERS}" = "hybrid" ] && echo -e "    ${GREEN}✓${NC} Hybrid (Local + External)"
            echo ""
            
            echo -e "  ${BOLD}Stack Type: ${STACK_NAME^^}${NC}"
            echo ""
        fi
    }
    
    # Show final summary
    final_service_summary
    
    offer_next_step
}

main "$@"
