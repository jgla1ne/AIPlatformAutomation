#!/usr/bin/env bash
# =============================================================================
# Script 1: System Compiler - README COMPLIANT
# =============================================================================
# PURPOSE: Collect input, write platform.conf, create directories, install packages
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
# INTERACTIVE INPUT FUNCTIONS
# =============================================================================
prompt_default() {
    local var="$1"
    local question="$2"
    local default="$3"
    
    echo ""
    read -r -p "  $question [$default]: " input
    eval "$var='${input:-$default}'"
}

prompt_yesno() {
    local var="$1"
    local question="$2"
    local default="$3"
    
    local prompt="$question"
    [[ "$default" == "y" ]] && prompt="$prompt [Y/n]" || prompt="$prompt [y/N]"
    
    while true; do
        echo ""
        read -r -p "  $prompt: " input
        input="${input:-$default}"
        case "$input" in
            [Yy]|[Yy][Ee][Ss]) eval "$var=true"; break ;;
            [Nn]|[Nn][Oo]) eval "$var=false"; break ;;
            *) echo "  Please enter y or n" ;;
        esac
    done
}

prompt_secret() {
    local var="$1"
    local question="$2"
    
    echo ""
    read -r -s -p "  $question: " input
    echo ""
    eval "$var='$input'"
}

# =============================================================================
# MAIN COLLECTION FUNCTION
# =============================================================================
collect_configuration() {
    local tenant_id="$1"
    
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
    
    # ── TENANT CONFIGURATION ────────────────────────────────────────
    prompt_default TENANT_ID "Tenant identifier" "$tenant_id"
    prompt_default PREFIX "Container name prefix" "ai"
    prompt_default BASE_DOMAIN "Base domain (example.com or local)" "local"
    
    # ── USER DETECTION (README P7) ────────────────────────────────────
    PUID=$(id -u)
    PGID=$(id -g)
    log "Detected user UID:PGID = $PUID:$PGID"
    
    # ── PLATFORM SETTINGS ───────────────────────────────────────────────
    PLATFORM_ARCH=$(uname -m)
    GPU_TYPE="cpu"
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        GPU_TYPE="nvidia"
        log "NVIDIA GPU detected"
    fi
    
    # ── SERVICE ENABLEMENT ───────────────────────────────────────────────
    echo ""
    echo "  === Service Selection ==="
    prompt_yesno POSTGRES_ENABLED "Enable PostgreSQL database" "y"
    prompt_yesno REDIS_ENABLED "Enable Redis cache" "y"
    prompt_yesno OLLAMA_ENABLED "Enable Ollama (local LLM)" "y"
    prompt_yesno LITELLM_ENABLED "Enable LiteLLM proxy" "y"
    prompt_yesno OPEN_WEBUI_ENABLED "Enable Open WebUI" "y"
    prompt_yesno QDRANT_ENABLED "Enable Qdrant vector DB" "y"
    prompt_yesno CADDY_ENABLED "Enable Caddy reverse proxy" "n"
    
    # ── PORT CONFIGURATION ───────────────────────────────────────────────
    echo ""
    echo "  === Port Configuration ==="
    prompt_default POSTGRES_PORT "PostgreSQL port" "5432"
    prompt_default REDIS_PORT "Redis port" "6379"
    prompt_default OLLAMA_PORT "Ollama port" "11434"
    prompt_default LITELLM_PORT "LiteLLM port" "4000"
    prompt_default OPEN_WEBUI_PORT "Open WebUI port" "3000"
    prompt_default QDRANT_PORT "Qdrant port" "6333"
    if [[ "$CADDY_ENABLED" == "true" ]]; then
        prompt_default CADDY_HTTP_PORT "Caddy HTTP port" "80"
        prompt_default CADDY_HTTPS_PORT "Caddy HTTPS port" "443"
    fi
    
    # ── DATABASE CONFIGURATION ───────────────────────────────────────────
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        echo ""
        echo "  === Database Configuration ==="
        prompt_default POSTGRES_USER "PostgreSQL username" "aiplatform"
        prompt_secret POSTGRES_PASSWORD "PostgreSQL password"
        prompt_default POSTGRES_DB "PostgreSQL database" "aiplatform"
    fi
    
    # ── PATHS (DERIVED) ───────────────────────────────────────────────────
    BASE_DIR="/mnt/${TENANT_ID}"
    CONFIG_DIR="${BASE_DIR}/config"
    DATA_DIR="${BASE_DIR}/data"
    LOGS_DIR="${BASE_DIR}/logs"
    DOCKER_NETWORK="${PREFIX}-${TENANT_ID}-network"
    DOCKER_SUBNET="172.20.0.0/16"
}

# =============================================================================
# PLATFORM.CONF GENERATION (README P1)
# =============================================================================
write_platform_conf() {
    local tenant_id="$1"
    local platform_conf="${CONFIG_DIR}/platform.conf"
    
    log "Creating platform.conf at $platform_conf"
    
    cat > "$platform_conf" << EOF
# =============================================================================
# AI Platform Configuration - PRIMARY SOURCE OF TRUTH (README P1)
# Generated by Script 1 on $(date)
# Tenant: ${tenant_id}
# =============================================================================
# WARNING: This file is the single source of truth for the entire platform.
# All scripts (0, 2, 3) source this file directly.
# DO NOT EDIT MANUALLY - Re-run Script 1 to regenerate.

# ── TENANT CONFIGURATION ─────────────────────────────────────────────────────
TENANT_ID=${TENANT_ID}
PREFIX=${PREFIX}
BASE_DOMAIN=${BASE_DOMAIN}

# ── USER CONFIGURATION (README P7) ───────────────────────────────────────────────
PUID=${PUID}
PGID=${PGID}

# ── PLATFORM SETTINGS ───────────────────────────────────────────────────────
PLATFORM_ARCH=${PLATFORM_ARCH}
GPU_TYPE=${GPU_TYPE}

# ── PATHS (DERIVED) ───────────────────────────────────────────────────────
BASE_DIR=${BASE_DIR}
CONFIG_DIR=${CONFIG_DIR}
DATA_DIR=${DATA_DIR}
LOGS_DIR=${LOGS_DIR}
DOCKER_NETWORK=${DOCKER_NETWORK}
DOCKER_SUBNET=${DOCKER_SUBNET}

# ── SERVICE ENABLEMENT ───────────────────────────────────────────────────────
POSTGRES_ENABLED=${POSTGRES_ENABLED}
REDIS_ENABLED=${REDIS_ENABLED}
OLLAMA_ENABLED=${OLLAMA_ENABLED}
LITELLM_ENABLED=${LITELLM_ENABLED}
OPEN_WEBUI_ENABLED=${OPEN_WEBUI_ENABLED}
QDRANT_ENABLED=${QDRANT_ENABLED}
CADDY_ENABLED=${CADDY_ENABLED}

# ── PORT CONFIGURATION ───────────────────────────────────────────────────────
POSTGRES_PORT=${POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
LITELLM_PORT=${LITELLM_PORT}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT}
QDRANT_PORT=${QDRANT_PORT}
EOF

    if [[ "$CADDY_ENABLED" == "true" ]]; then
        cat >> "$platform_conf" << EOF
CADDY_HTTP_PORT=${CADDY_HTTP_PORT}
CADDY_HTTPS_PORT=${CADDY_HTTPS_PORT}
EOF
    fi
    
    # Database configuration
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        cat >> "$platform_conf" << EOF

# ── DATABASE CONFIGURATION ───────────────────────────────────────────────────
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
EOF
    fi
    
    # Set permissions (README P1)
    chmod 600 "$platform_conf"
    chown "$PUID:$PGID" "$platform_conf"
    
    ok "platform.conf created with chmod 600"
}

# =============================================================================
# DIRECTORY STRUCTURE CREATION
# =============================================================================
create_directories() {
    log "Creating directory structure..."
    
    local dirs=(
        "$BASE_DIR"
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$LOGS_DIR"
        "$DATA_DIR/postgres"
        "$DATA_DIR/redis"
        "$DATA_DIR/ollama"
        "$DATA_DIR/qdrant"
        "$CONFIG_DIR/caddy"
        "$CONFIG_DIR/litellm"
        "$CONFIG_DIR/open-webui"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chown "$PUID:$PGID" "$dir"
            log "Created: $dir"
        fi
    done
    
    ok "Directory structure created"
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================
install_packages() {
    log "Installing required packages..."
    
    # Update package list
    sudo apt-get update -qq
    
    # Install required packages
    local packages=(
        "curl"
        "wget"
        "git"
        "jq"
        "docker.io"
        "docker-compose-plugin"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "Installing $package..."
            sudo apt-get install -y "$package"
        else
            log "$package already installed"
        fi
    done
    
    # Add user to docker group if not already
    if ! groups "$USER" | grep -q docker; then
        log "Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        warn "You will need to log out and back in for docker group changes to take effect"
    fi
    
    ok "Package installation complete"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-default}"
    
    # Collect configuration interactively
    collect_configuration "$tenant_id"
    
    # Create directories
    create_directories
    
    # Write platform.conf (README P1)
    write_platform_conf "$tenant_id"
    
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
    echo "  1. Deploy services: bash scripts/2-deploy-services.sh ${tenant_id}"
    echo "  2. Verify deployment: bash scripts/3-configure-services.sh ${tenant_id}"
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
