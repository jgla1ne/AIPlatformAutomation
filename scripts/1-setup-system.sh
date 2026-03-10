#!/usr/bin/env bash
set -euo pipefail

# Import utility functions from Mission Control (modular architecture)
# Script-3 is now source-safe and will only define functions when sourced
source "$(dirname "$0")/3-configure-services.sh" 2>/dev/null || true

# =============================================================================
# Script 1: Tenant Setup - Complete System Configurationzard
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Runtime vars (set after volume selection) ────────────────────────────────
DATA_ROOT=""
ENV_FILE=""
COMPOSE_DIR=""
CADDY_DIR=""
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Dynamic service URLs (will be set after tenant selection)
VECTOR_DB_URL=""
OLLAMA_INTERNAL_URL=""
LITELLM_INTERNAL_URL=""
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
ENABLE_LOCALAI="false"
ENABLE_VLLM="false"
ENABLE_OPENWEBUI="false"
ENABLE_ANYTHINGLLM="false"
ENABLE_DIFY="false"
ENABLE_N8N="false"
ENABLE_FLOWISE="false"
ENABLE_LITELLM="false"
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
LITELLM_PORT=""
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
N8N_ENCRYPTION_KEY=""
N8N_API_KEY=""
N8N_PASSWORD=""
FLOWISE_SECRET_KEY=""
FLOWISE_PASSWORD=""
LITELLM_MASTER_KEY=""
LITELLM_SALT_KEY=""
ANYTHINGLLM_API_KEY=""
ANYTHINGLLM_JWT_SECRET=""
ANYTHINGLLM_AUTH_TOKEN=""
ANYTHINGLLM_PORT=""
QDRANT_API_KEY=""
GRAFANA_PASSWORD=""
AUTHENTIK_SECRET_KEY=""
AUTHENTIK_BOOTSTRAP_PASSWORD=""
DIFY_SECRET_KEY=""
DIFY_INNER_API_KEY=""

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
LITELLM_SERVICE_NAME="litellm"
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
    LITELLM_INTERNAL_URL="http://\${LITELLM_SERVICE_NAME:-litellm}:\${LITELLM_PORT:-4000}"
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
        read -p "  ➤ Project prefix [aip-]: " PROJECT_PREFIX
        PROJECT_PREFIX="${PROJECT_PREFIX:-aip-}"
        PROJECT_PREFIX="${PROJECT_PREFIX,,}"
        if [[ "${PROJECT_PREFIX}" =~ ^[a-z][a-z0-9\-]*-$ ]]; then
            break
        fi
        echo "  ❌ Must end with hyphen, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}�  Admin Email${NC}"
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
    echo -e "  ${CYAN}  2)${NC}  🔵  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + LiteLLM"
    echo -e "             ${DIM}Full AI automation stack, recommended starting point${NC}"
    echo ""
    echo -e "  ${CYAN}  3)${NC}  🟣  ${BOLD}Full${NC}          — Standard + AnythingLLM + Grafana + Prometheus + Authentik"
    echo -e "             ${DIM}Production-grade with observability and SSO${NC}"
    echo ""
    echo -e "  ${CYAN}  4)${NC}  ⚙️   ${BOLD}Custom${NC}        — Pick services individually"
    echo -e "             ${DIM}Full control over what gets deployed${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select stack [1-5]: " stack_choice
        stack_choice="${stack_choice:-2}"
        case "${stack_choice}" in
            1|2|3|4|5) break ;;
            *) echo "  ❌ Enter 1, 2, 3, 4 or 5" ;;
        esac
    done

    # ── Apply stack presets ───────────────────────────────────────────────────
    # First, zero everything out
    ENABLE_POSTGRES=false; ENABLE_REDIS=false; ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false;
    ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false; ENABLE_N8N=false; ENABLE_FLOWISE=false;
    ENABLE_LITELLM=false; ENABLE_QDRANT=false; ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false;
    ENABLE_AUTHENTIK=false; ENABLE_SIGNAL=false; ENABLE_OPENCLAW=false; ENABLE_TAILSCALE=false;
    ENABLE_RCLONE=false; ENABLE_CADDY=true # Caddy is always on

    case "${stack_choice}" in
        1) # Lite Stack
            log "INFO" "Applying 'Lite' preset: OpenWebUI, Ollama, Qdrant, LiteLLM"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_QDRANT=true; ENABLE_LITELLM=true;
            STACK_NAME="lite"
            ;;
        2) # Local LLM Developer Stack
            log "INFO" "Applying 'Local LLM Developer' preset: All local AI tools"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_ANYTHINGLLM=true; ENABLE_DIFY=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true;
            ENABLE_QDRANT=true;
            STACK_NAME="local-llm-dev"
            ;;
        3) # Monitoring & Security Stack
            log "INFO" "Applying 'Monitoring & Security' preset: Core DBs, Monitoring, Security"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_QDRANT=true;
            ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true; ENABLE_AUTHENTIK=true;
            ENABLE_TAILSCALE=true;
            STACK_NAME="monitoring-security"
            ;;
        4) # Full Stack (All Services)
            log "WARN" "Applying 'Full Stack' preset. This requires significant system resources."
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_ANYTHINGLLM=true; ENABLE_DIFY=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true;
            ENABLE_QDRANT=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true;
            ENABLE_AUTHENTIK=true; ENABLE_SIGNAL=true; ENABLE_OPENCLAW=true;
            ENABLE_TAILSCALE=true; ENABLE_RCLONE=true;
            STACK_NAME="full"
            ;;
        5) # Custom — all off, user picks in next step
            STACK_NAME="custom"
            log "INFO" "Stack: Custom — configure individually below"
            ;;
    esac

    print_divider

    # ── Always offer fine-grained override ────────────────────────────────────
    if [ "${stack_choice}" != "5" ]; then
        echo -e "  ${DIM}Stack applied. Would you like to customise individual services?${NC}"
        echo ""
        read -p "  ➤ Customise service selection? [y/N]: " customise
        customise="${customise:-n}"
        [[ "${customise,,}" =~ ^y ]] && stack_choice=4
    fi

    if [ "${stack_choice}" = "4" ]; then
        echo ""
        echo -e "  ${BOLD}─── 🤖  AI / LLM ────────────────────────────────────────${NC}"
        ask_service "🦙" "Ollama"        "Local LLM engine"           "ENABLE_OLLAMA"        "$( [[ "${ENABLE_OLLAMA}" == "true" ]]        && echo y || echo n )"
        ask_service "🌐" "Open WebUI"    "Chat UI for Ollama"         "ENABLE_OPENWEBUI"     "$( [[ "${ENABLE_OPENWEBUI}" == "true" ]]     && echo y || echo n )"
        ask_service "🤖" "AnythingLLM"   "AI assistant & RAG"         "ENABLE_ANYTHINGLLM"   "$( [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]   && echo y || echo n )"
        ask_service "🏗️ " "Dify"          "LLM app builder"            "ENABLE_DIFY"          "$( [[ "${ENABLE_DIFY}" == "true" ]]          && echo y || echo n )"
        ask_service "🔀" "LiteLLM"       "LLM proxy gateway"          "ENABLE_LITELLM"       "$( [[ "${ENABLE_LITELLM}" == "true" ]]       && echo y || echo n )"

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

# ─── LiteLLM Routing Strategy Configuration ───────────────────────────────
collect_litellm_routing() {
    print_step "8.5" "11" "LiteLLM Routing Strategy"
    
    echo -e "  ${BOLD}🧠  LiteLLM Routing Strategy${NC}"
    echo -e "  ${DIM}Configure intelligent model routing for cost/latency optimization${NC}"
    echo ""
    
    echo -e "  ${BOLD}Available Routing Strategies:${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC} Cost-Optimized (recommended)"
    echo -e "     ${DIM}Prioritize free/local models, then cheapest paid models${NC}"
    echo ""
    echo -e "  ${CYAN}  2)${NC} Speed-Optimized"
    echo -e "     ${DIM}Prioritize fastest response times (Groq > Gemini > Local)${NC}"
    echo ""
    echo -e "  ${CYAN}  3)${NC} Balanced"
    echo -e "     ${DIM}Balance cost, speed, and capability${NC}"
    echo ""
    echo -e "  ${CYAN}  4)${NC} Capability-Optimized"
    echo -e "     ${DIM}Prioritize most capable models (GPT-4o > Claude-3 > Gemini)${NC}"
    echo ""
    
    read -p "  ➤ Select LiteLLM routing strategy [1-4]: " litellm_routing_choice
    
    case "${litellm_routing_choice}" in
        1) 
            LITELLM_ROUTING_STRATEGY="cost-optimized"
            echo -e "  ${GREEN}✅${NC} Cost-optimized routing selected"
            ;;
        2) 
            LITELLM_ROUTING_STRATEGY="speed-optimized"
            echo -e "  ${GREEN}✅${NC} Speed-optimized routing selected"
            ;;
        3) 
            LITELLM_ROUTING_STRATEGY="balanced"
            echo -e "  ${GREEN}✅${NC} Balanced routing selected"
            ;;
        4) 
            LITELLM_ROUTING_STRATEGY="capability-optimized"
            echo -e "  ${GREEN}✅${NC} Capability-optimized routing selected"
            ;;
        *) 
            LITELLM_ROUTING_STRATEGY="cost-optimized"
            echo -e "  ${YELLOW}⚠️${NC} Defaulting to cost-optimized routing"
            ;;
    esac
    
    log "SUCCESS" "LiteLLM routing strategy: ${LITELLM_ROUTING_STRATEGY}"
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
                    
                    # Extract client_id and client_secret safely
                    local client_id=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_id', ''))" 2>/dev/null || echo "")
                    local client_secret=$(echo "$json_content" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('client_secret', ''))" 2>/dev/null || echo "")
                    
                    if [[ -n "$client_id" && -n "$client_secret" ]]; then
                        cat > "$temp_config" << EOF
[gdrive_sa]
type = drive
scope = drive
client_id = ${client_id}
client_secret = ${client_secret}
service_account_file = ${TENANT_DIR}/rclone/google_sa.json
token = {"access_token":"test"}
EOF
                        
                        echo -e "  ${DIM}🔐 Attempting token generation (with retry mechanism)...${NC}"
                        
                        # Retry mechanism for token generation
                        local max_retries=3
                        local retry_count=0
                        local gdrive_token=""
                        
                        while [[ $retry_count -lt $max_retries && -z "$gdrive_token" ]]; do
                            ((retry_count++))
                            echo -e "  ${DIM}   Attempt ${retry_count}/${max_retries}...${NC}"
                            
                            # Generate token with timeout
                            gdrive_token=$(timeout 30s rclone config create gdrive-sa --config "$temp_config" "drive" "service_account" "${TENANT_DIR}/rclone/google_sa.json" 2>/dev/null)
                            
                            # Extract token from output
                            gdrive_token=$(echo "$gdrive_token" 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                            
                            if [[ -n "$gdrive_token" ]]; then
                                break
                            else
                                echo -e "  ${YELLOW}   ⚠️  Token generation failed, retrying in 5 seconds...${NC}"
                                sleep 5
                            fi
                        done
                        
                        if [[ -n "$gdrive_token" ]]; then
                            GDRIVE_TOKEN="$gdrive_token"
                            echo -e "  ${GREEN}✅ Rclone token generated successfully${NC}"
                            echo -e "  ${DIM}   Token length: ${#GDRIVE_TOKEN} characters${NC}"
                            log "SUCCESS" "Rclone Service Account token generated (${retry_count} attempts)"
                        else
                            echo -e "  ${YELLOW}⚠️ Rclone token generation failed after ${max_retries} attempts${NC}"
                            echo -e "  ${DIM}   Token will be generated automatically when Rclone container starts${NC}"
                            echo -e "  ${DIM}   This is normal and will be handled during deployment${NC}"
                            GDRIVE_TOKEN=""
                        fi
                    else
                        echo -e "  ${RED}❌ Could not extract client_id/client_secret from JSON${NC}"
                        echo -e "  ${DIM}   Token will be generated automatically when Rclone container starts${NC}"
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
            echo -e "  • Valid admin email for cert alerts"
            echo ""
            read -p "  ➤ Admin email (for SSL cert alerts): " ADMIN_EMAIL
            while [[ ! "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
                echo "  ❌ Invalid email"
                read -p "  ➤ Admin email: " ADMIN_EMAIL
            done
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
    echo ""
    read -p "  ➤ Enable OpenClaw? [y/N]: " enable_openclaw
    if [[ "${enable_openclaw,,}" == "y" ]]; then
        read -p "  ➤ OpenClaw admin password: " OPENCLAW_PASSWORD
        read -p "  ➤ OpenClaw port [18789]: " OPENCLAW_PORT
        OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
        ENABLE_OPENCLAW="true"
    else
        ENABLE_OPENCLAW="false"
    fi

    log "SUCCESS" "Network & security configuration completed"
}

# ─── Port Configuration ────────────────────────────────────────────────────
collect_ports() {
    print_step "10" "11" "Port Configuration"

    echo -e "  ${BOLD}🔌  Service Ports${NC}"
    echo -e "  ${DIM}Configure ports for each enabled service${NC}"
    echo ""

    # Default ports (based on actual Docker internal ports)
    local d_n8n="5678"
    local d_flowise="3000"
    local d_openwebui="8081"
    local d_anythingllm="3001"
    local d_litellm="4000"
    local d_grafana="3002"          # Host port, internal is 3000
    local d_prometheus="9090"
    local d_ollama="11434"
    local d_qdrant="6333"
    local d_authentik="9000"         # Host port, internal is 9000
    local d_signal="8080"           # Host port, internal is 8080
    local d_openclaw="18789"        # Host port, internal is 8082
    local d_tailscale="8443"        # Host port, internal is 443 (for OpenClaw)
    local d_rclone="5572"           # Host port, internal is 5572

    # Track used ports to prevent conflicts
    local used_ports=""

    read_port() {
        local service="${1}" default="${2}" varname="${3}"
        while true; do
            read -p "  ➤ ${service} port [${default}]: " input
            if [ -z "${input}" ]; then
                input="${default}"
            fi
            
            if [[ "${input}" =~ ^[0-9]+$ ]] && [ "${input}" -ge 1024 ] && [ "${input}" -le 65535 ]; then
                # Check if port is already in use on system
                if ss -tuln 2>/dev/null | grep -q ":${input} "; then
                    log "WARN" "Port ${input} is already in use on system — choose another"
                    continue
                fi
                
                # Check if port is already assigned to another service
                if [[ " ${used_ports} " =~ " ${input} " ]]; then
                    log "WARN" "Port ${input} is already assigned to another service — choose another"
                    continue
                fi
                
                eval "${varname}=${input}"
                used_ports="${used_ports} ${input}"
                break
            else
                echo "  ❌ Enter a valid port (1024–65535)"
            fi
        done
    }

    [ "${ENABLE_N8N}" = "true" ]         && read_port "n8n"         "${d_n8n}"         "N8N_PORT"
    [ "${ENABLE_FLOWISE}" = "true" ]     && read_port "Flowise"     "${d_flowise}"     "FLOWISE_PORT"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && read_port "Open WebUI"  "${d_openwebui}"   "OPENWEBUI_PORT"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && read_port "AnythingLLM" "${d_anythingllm}" "ANYTHINGLLM_PORT"
    [ "${ENABLE_LITELLM}" = "true" ]     && read_port "LiteLLM"     "${d_litellm}"     "LITELLM_PORT"
    [ "${ENABLE_GRAFANA}" = "true" ]     && read_port "Grafana"     "${d_grafana}"     "GRAFANA_PORT"
    [ "${ENABLE_PROMETHEUS}" = "true" ]  && read_port "Prometheus"  "${d_prometheus}"  "PROMETHEUS_PORT"
    [ "${ENABLE_OLLAMA}" = "true" ]      && read_port "Ollama"      "${d_ollama}"      "OLLAMA_PORT"
    [ "${ENABLE_QDRANT}" = "true" ]      && read_port "Qdrant"      "${d_qdrant}"      "QDRANT_PORT"
    [ "${ENABLE_AUTHENTIK}" = "true" ]    && read_port "Authentik"   "${d_authentik}"   "AUTHENTIK_PORT"
    [ "${ENABLE_SIGNAL}" = "true" ]      && read_port "Signal API"  "${d_signal}"      "SIGNAL_PORT"
    [ "${ENABLE_OPENCLAW}" = "true" ]    && read_port "OpenClaw"    "${d_openclaw}"    "OPENCLAW_PORT"
    [ "${ENABLE_TAILSCALE}" = "true" ]   && read_port "Tailscale"   "${d_tailscale}"   "TAILSCALE_PORT"
    [ "${ENABLE_RCLONE}" = "true" ]      && read_port "Rclone"      "${d_rclone}"      "RCLONE_PORT"

    # Set safe defaults for disabled services
    N8N_PORT="${N8N_PORT:-${d_n8n}}"
    FLOWISE_PORT="${FLOWISE_PORT:-${d_flowise}}"
    OPENWEBUI_PORT="${OPENWEBUI_PORT:-${d_openwebui}}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-${d_anythingllm}}"
    LITELLM_PORT="${LITELLM_PORT:-${d_litellm}}"
    LITELLM_INTERNAL_PORT="4000"
    GRAFANA_PORT="${GRAFANA_PORT:-${d_grafana}}"
    PROMETHEUS_PORT="${PROMETHEUS_PORT:-${d_prometheus}}"
    OLLAMA_PORT="${OLLAMA_PORT:-${d_ollama}}"
    QDRANT_PORT="${QDRANT_PORT:-${d_qdrant}}"
    AUTHENTIK_PORT="${AUTHENTIK_PORT:-${d_authentik}}"
    SIGNAL_PORT="${SIGNAL_PORT:-${d_signal}}"
    OPENCLAW_PORT="${OPENCLAW_PORT:-${d_openclaw}}"
    TAILSCALE_PORT="${TAILSCALE_PORT:-${d_tailscale}}"
    RCLONE_PORT="${RCLONE_PORT:-${d_rclone}}"

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
    LITELLM_MASTER_KEY=$(load_existing_secret "LITELLM_MASTER_KEY"     "sk-$(openssl rand -hex 32)")
    LITELLM_SALT_KEY=$(load_existing_secret "LITELLM_SALT_KEY"     "$(openssl rand -hex 32)")
    ANYTHINGLLM_JWT_SECRET=$(load_existing_secret "ANYTHINGLLM_JWT_SECRET" "$(openssl rand -hex 32)")
    ANYTHINGLLM_AUTH_TOKEN=$(load_existing_secret "ANYTHINGLLM_AUTH_TOKEN" "$(openssl rand -hex 16)")
    ANYTHINGLLM_API_KEY=$(load_existing_secret "ANYTHINGLLM_API_KEY" "$(openssl rand -hex 32)")
    GRAFANA_PASSWORD=$(load_existing_secret "GRAFANA_PASSWORD"          "$(openssl rand -hex 16)")
    AUTHENTIK_SECRET_KEY=$(load_existing_secret "AUTHENTIK_SECRET_KEY" "$(openssl rand -hex 32)")
    MINIO_ROOT_PASSWORD=$(load_existing_secret "MINIO_ROOT_PASSWORD" "$(openssl rand -hex 16)")
    QDRANT_API_KEY=$(load_existing_secret   "QDRANT_API_KEY"            "$(openssl rand -hex 32)")
    N8N_API_KEY=$(load_existing_secret      "N8N_API_KEY"               "n8n-$(openssl rand -hex 16)")
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
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
DATA_ROOT=${DATA_ROOT}
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
LITELLM_UID=${LITELLM_UID:-1000}
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
ENABLE_LOCALAI=${ENABLE_LOCALAI}
ENABLE_VLLM=${ENABLE_VLLM}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_WEAVIATE=${ENABLE_WEAVIATE}
ENABLE_PINECONE=${ENABLE_PINECONE}
ENABLE_CHROMADB=${ENABLE_CHROMADB}
ENABLE_MILVUS=${ENABLE_MILVUS}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW:-false}
ENABLE_RCLONE=${ENABLE_RCLONE}
ENABLE_MINIO=${ENABLE_MINIO}

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
LITELLM_INTERNAL_URL="http://\${LITELLM_SERVICE_NAME:-litellm}:\${LITELLM_PORT:-4000}"
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
LITELLM_API_ENDPOINT="${LITELLM_INTERNAL_URL}/v1"
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

# ─── LiteLLM Routing Strategy ───────────────────────────────────────────────
LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY}"
LITELLM_INTERNAL_PORT="${LITELLM_INTERNAL_PORT}"

# ─── Internal Service Ports ───────────────────────────────────────────────
CADDY_INTERNAL_HTTP_PORT=${CADDY_INTERNAL_HTTP_PORT}
CADDY_INTERNAL_HTTPS_PORT=${CADDY_INTERNAL_HTTPS_PORT}
OLLAMA_INTERNAL_PORT=${OLLAMA_INTERNAL_PORT}
QDRANT_INTERNAL_PORT=${QDRANT_INTERNAL_PORT}
QDRANT_INTERNAL_HTTP_PORT=${QDRANT_INTERNAL_HTTP_PORT}
OPENWEBUI_INTERNAL_PORT=${OPENWEBUI_INTERNAL_PORT}
OPENCLAW_INTERNAL_PORT=${OPENCLAW_PORT:-18789}
SIGNAL_INTERNAL_PORT=${SIGNAL_INTERNAL_PORT}
N8N_INTERNAL_PORT=${N8N_INTERNAL_PORT}
FLOWISE_INTERNAL_PORT=${FLOWISE_INTERNAL_PORT}
ANYTHINGLLM_INTERNAL_PORT=${ANYTHINGLLM_INTERNAL_PORT}
GRAFANA_INTERNAL_PORT=${GRAFANA_INTERNAL_PORT}
PROMETHEUS_INTERNAL_PORT=${PROMETHEUS_INTERNAL_PORT}
MINIO_INTERNAL_PORT=${MINIO_INTERNAL_PORT}
MINIO_CONSOLE_INTERNAL_PORT=${MINIO_CONSOLE_INTERNAL_PORT}
TAILSCALE_INTERNAL_PORT=${TAILSCALE_INTERNAL_PORT}
POSTGRES_INTERNAL_PORT=${POSTGRES_INTERNAL_PORT}
REDIS_INTERNAL_PORT=${REDIS_INTERNAL_PORT}

# ─── Database ─────────────────────────────────────────────────────────────────
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_DB="${POSTGRES_DB}"

# ─── Database Compatibility (for script 3) ───────────────────────────────
DB_USER="${POSTGRES_USER}"
DB_PASSWORD="${POSTGRES_PASSWORD}"

# ─── Network Configuration (for dynamic references) ───────────────────
LOCALHOST=localhost

# ─── Redis ────────────────────────────────────────────────────────────────────
REDIS_PASSWORD="${REDIS_PASSWORD}"

# ─── n8n ──────────────────────────────────────────────────────────────────────
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"
N8N_API_KEY="${N8N_API_KEY}"
N8N_USER="admin@${DOMAIN}"
N8N_PASSWORD="${N8N_PASSWORD}"

# ─── Flowise ──────────────────────────────────────────────────────────────────
FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY}"
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD="${FLOWISE_PASSWORD}"

# LiteLLM configuration for central AI gateway
LITELLM_CONFIG_YAML='
model_list:
  - model_name: ${OLLAMA_DEFAULT_MODEL}
    litellm_params:
      model: ${OLLAMA_DEFAULT_MODEL}
      api_base: http://${OLLAMA_INTERNAL_URL}
      rpm_limit: 6
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      rpm_limit: 100
'

# ─── LiteLLM ──────────────────────────────────────────────────────────────────
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
LITELLM_SALT_KEY="${LITELLM_SALT_KEY}"

# ─── AnythingLLM ────────────────────────────────────────────────────────────────
ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET}"
ANYTHINGLLM_AUTH_TOKEN="${ANYTHINGLLM_AUTH_TOKEN}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT}"

# ─── Qdrant ───────────────────────────────────────────────────────────────────
QDRANT_API_KEY="${QDRANT_API_KEY}"
QDRANT_VECTOR_SIZE="768"

# ─── Grafana ──────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_USER="admin"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD}"
GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"

# ─── Authentik ────────────────────────────────────────────────────────────────
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_BOOTSTRAP_EMAIL="${ADMIN_EMAIL}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD}"
ADMIN_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD}"

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
# Only export GDRIVE_TOKEN for OAuth method (Service Account doesn't use tokens)
if [[ "${GDRIVE_AUTH_METHOD}" == "oauth" ]]; then
    GDRIVE_TOKEN="${GDRIVE_TOKEN}"
fi

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
LITELLM_SERVICE_NAME=${LITELLM_SERVICE_NAME}
LITELLM_PORT=${LITELLM_PORT}
VLLM_SERVICE_NAME=${VLLM_SERVICE_NAME}
VLLM_PORT=${VLLM_PORT}

# ─── Proxy Configuration ───────────────────────────────────────────────────────
PROXY_TYPE=${PROXY_TYPE}
ROUTING_METHOD=${ROUTING_METHOD}
SSL_TYPE=${SSL_TYPE}
CUSTOM_PROXY_IMAGE=${CUSTOM_PROXY_IMAGE}
HTTP_PROXY=${HTTP_PROXY}
HTTPS_PROXY=${HTTPS_PROXY}
NO_PROXY=${NO_PROXY}
HTTP_TO_HTTPS_REDIRECT=${HTTP_TO_HTTPS_REDIRECT:-false}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
OPENCLAW_PASSWORD=${OPENCLAW_PASSWORD:-default_password}
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
LITELLM_PORT=${LITELLM_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
QDRANT_PORT=${QDRANT_PORT}
SIGNAL_PORT=${SIGNAL_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
TAILSCALE_PORT=${TAILSCALE_PORT}
RCLONE_PORT=${RCLONE_PORT}

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
# Redis configuration for Authentik
AUTHENTIK_REDIS__HOST=redis

# Dify storage configuration
DIFY_STORAGE_TYPE=local
DIFY_STORAGE_LOCAL_ROOT=/data
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

    # Exception for Postgres (requires UID 70)
    if [[ -d "${DATA_ROOT}/postgres" ]]; then
        chown -R 70:70 "${DATA_ROOT}/postgres"
        log "SUCCESS" "Set ownership for 'postgres' directory to 70:70."
    fi

    # Exception for Grafana (requires UID 472)
    if [[ -d "${DATA_ROOT}/grafana" ]]; then
        chown -R 472:472 "${DATA_ROOT}/grafana"
        log "SUCCESS" "Set ownership for 'grafana' directory to 472:472."
    fi

    # Exception for n8n (requires UID 1000)
    if [[ -d "${DATA_ROOT}/n8n" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/n8n"
        log "SUCCESS" "Set ownership for 'n8n' directory to 1000:1000."
    fi

    # Exception for Flowise (requires UID 1000)
    if [[ -d "${DATA_ROOT}/flowise" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/flowise"
        log "SUCCESS" "Set ownership for 'flowise' directory to 1000:1000."
    fi
    
    # Exception for Prometheus (requires UID 65534)
    if [[ -d "${DATA_ROOT}/prometheus-data" ]]; then
        chown -R 65534:65534 "${DATA_ROOT}/prometheus-data"
        log "SUCCESS" "Set ownership for 'prometheus' directory to 65534:65534."
    fi

    # Exception for Redis (requires UID 999)
    if [[ -d "${DATA_ROOT}/redis" ]]; then
        chown -R 999:999 "${DATA_ROOT}/redis"
        log "SUCCESS" "Set ownership for 'redis' directory to 999:999."
    fi

    # Exception for Ollama (requires UID 1001)
    if [[ -d "${DATA_ROOT}/ollama" ]]; then
        chown -R 1001:1001 "${DATA_ROOT}/ollama"
        log "SUCCESS" "Set ownership for 'ollama' directory to 1001:1001."
    fi

    # Exception for Qdrant (requires UID 1000)
    if [[ -d "${DATA_ROOT}/qdrant" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/qdrant"
        log "SUCCESS" "Set ownership for 'qdrant' directory to 1000:1000."
    fi

    # Exception for Flowise (requires UID 1000)
    if [[ -d "${DATA_ROOT}/flowise" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/flowise"
        log "SUCCESS" "Set ownership for 'flowise' directory to 1000:1000."
    fi

    # Exception for OpenWebUI (requires UID 1000)
    if [[ -d "${DATA_ROOT}/openwebui" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/openwebui"
        log "SUCCESS" "Set ownership for 'openwebui' directory to 1000:1000."
    fi

    # Exception for AnythingLLM (requires UID 1000)
    if [[ -d "${DATA_ROOT}/anythingllm" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/anythingllm"
        log "SUCCESS" "Set ownership for 'anythingllm' directory to 1000:1000."
    fi

    # Exception for LiteLLM (requires UID 1000)
    if [[ -d "${DATA_ROOT}/litellm" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/litellm"
        log "SUCCESS" "Set ownership for 'litellm' directory to 1000:1000."
    fi

    # Exception for Authentik (requires UID 1000)
    if [[ -d "${DATA_ROOT}/authentik" ]]; then
        chown -R 1000:1000 "${DATA_ROOT}/authentik"
        log "SUCCESS" "Set ownership for 'authentik' directory to 1000:1000."
    fi

    # Exception for Prometheus (already handled above)
    # Exception for Grafana (already handled above)
    # Exception for Postgres (already handled above)
    # Exception for Redis (already handled above)
    # Exception for Ollama (already handled above)

    # --- STAGE 3: Secure Final Permissions ---
    log "INFO" "Setting secure permissions on tenant root and .env file..."
    chmod 750 "${DATA_ROOT}"
    chmod 640 "${ENV_FILE}"
    log "SUCCESS" "Secure permissions set. Ownership structure is now correct."
}

# ─── Create directory structure ──────────────────────────────────────────────
create_directories() {
    log "INFO" "Creating all service directories..."

    # This function creates directories without setting ownership
    # Ownership will be set correctly by apply_final_ownership function
    create_dir() {
        local dir_path="$1"
        mkdir -p "${DATA_ROOT}/${dir_path}"
        printf "  ${DIM}Created '${dir_path}'${NC}\n"
    }

    # --- Create all possible directories ---
    create_dir "logs"
    create_dir "compose"
    create_dir "caddy"
    create_dir "caddy/config"
    create_dir "caddy/data"
    create_dir "redis"
    create_dir "litellm"
    create_dir "authentik/media"
    create_dir "authentik/certs"
    create_dir "authentik/custom-templates"
    create_dir "signal"
    create_dir "backups"

    # Service-specific directories
    create_dir "postgres"
    create_dir "prometheus-data"
    create_dir "grafana/provisioning/datasources"
    create_dir "grafana/provisioning/dashboards"
    create_dir "n8n"
    create_dir "n8n/workflows"
    create_dir "qdrant"
    create_dir "weaviate"
    create_dir "chromadb"
    create_dir "milvus"
    create_dir "ollama"
    create_dir "localai"
    create_dir "vllm"
    create_dir "openwebui"
    create_dir "anythingllm"
    create_dir "anythingllm/tmp"
    create_dir "flowise"
    create_dir "run/tailscale"
    create_dir "lib/tailscale"

    log "SUCCESS" "All service directories created."
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

    if [[ "${ENABLE_LITELLM}" = "true" ]]; then
        cat >> "${CADDYFILE_PATH}" << EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:4000
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
        warn "Caddy CLI not available - skipping validation"
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
    echo ""
    echo -e "  ${BOLD}Enabled services:${NC}"
    [ "${ENABLE_OLLAMA}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Ollama       (models: ${OLLAMA_MODELS:-auto})"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Open WebUI   :${OPENWEBUI_PORT}"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo -e "    ${GREEN}✓${NC}  AnythingLLM  :${ANYTHINGLLM_PORT}"
    [ "${ENABLE_DIFY}" = "true" ]        && echo -e "    ${GREEN}✓${NC}  Dify"
    [ "${ENABLE_N8N}" = "true" ]         && echo -e "    ${GREEN}✓${NC}  n8n          :${N8N_PORT}"
    [ "${ENABLE_FLOWISE}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  Flowise      :${FLOWISE_PORT}"
    [ "${ENABLE_LITELLM}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  LiteLLM      :${LITELLM_PORT}"
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
        [ "${ENABLE_LITELLM}" = "true" ] && echo -e "    ${CYAN}•${NC} LiteLLM:      https://litellm.${DOMAIN}"
        [ "${ENABLE_GRAFANA}" = "true" ] && echo -e "    ${CYAN}•${NC} Grafana:      https://grafana.${DOMAIN}"
        [ "${ENABLE_AUTHENTIK}" = "true" ] && echo -e "    ${CYAN}•${NC} Authentik:    https://auth.${DOMAIN}"
        [ "${ENABLE_DIFY}" = "true" ] && echo -e "    ${CYAN}•${NC} Dify:         https://dify.${DOMAIN}"
        [ "${ENABLE_OPENCLAW}" = "true" ] && echo -e "    ${CYAN}•${NC} OpenClaw:     https://openclaw.${DOMAIN}"
        [ "${ENABLE_SIGNAL}" = "true" ] && echo -e "    ${CYAN}•${NC} Signal API:   https://signal.${DOMAIN}"
        echo ""
        
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
    collect_database         # Step 7.5 - Database configuration
    collect_llm_config       # Step 8
    collect_litellm_routing  # Step 8.5 - LiteLLM routing strategy
    collect_network_config   # Step 9 - NEW: Network & security configuration
    collect_ports            # Step 10
    generate_secrets         # Step 11
    print_summary
    write_env_file
    
    create_directories
    
    # Apply the final, correct ownership structure (NEW FINAL STEP)
    apply_final_ownership
    
    write_caddyfile
    write_prometheus_config
    offer_next_step
}

main "$@"
