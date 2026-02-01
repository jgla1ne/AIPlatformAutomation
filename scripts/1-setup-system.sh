#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - System Setup Script v8.2
# Fully automated setup including Google Drive sync
# ============================================================================

readonly SCRIPT_VERSION="8.2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Icons
CHECK_MARK="✓"
CROSS_MARK="✗"
WARN_MARK="⚠"
INFO_MARK="ℹ"

success() { echo -e "${GREEN}${CHECK_MARK} $*${NC}"; }
error() { echo -e "${RED}${CROSS_MARK} $*${NC}"; }
warn() { echo -e "${YELLOW}${WARN_MARK} $*${NC}"; }
info() { echo -e "${BLUE}${INFO_MARK} $*${NC}"; }

# ============================================================================
# Display Banner
# ============================================================================

display_banner() {
    echo ""
    echo "========================================"
    echo "AI Platform - System Setup v${SCRIPT_VERSION}"
    echo "========================================"
    echo ""
}

# ============================================================================
# Directory Creation
# ============================================================================

create_directories() {
    info "[1/7] Creating directory structure..."
    
    local dirs=(
        "${PROJECT_ROOT}/data/ollama"
        "${PROJECT_ROOT}/data/litellm"
        "${PROJECT_ROOT}/data/anythingllm"
        "${PROJECT_ROOT}/data/anythingllm/storage"
        "${PROJECT_ROOT}/data/anythingllm/vector-cache"
        "${PROJECT_ROOT}/data/clawdbot"
        "${PROJECT_ROOT}/data/dify/postgres"
        "${PROJECT_ROOT}/data/dify/redis"
        "${PROJECT_ROOT}/data/dify/api"
        "${PROJECT_ROOT}/data/n8n"
        "${PROJECT_ROOT}/data/signal"
        "${PROJECT_ROOT}/data/gdrive/config"
        "${PROJECT_ROOT}/data/gdrive/sync"
        "${PROJECT_ROOT}/data/gdrive/logs"
        "${PROJECT_ROOT}/data/nginx/ssl"
        "${PROJECT_ROOT}/data/nginx/conf.d"
        "${PROJECT_ROOT}/stacks/ollama"
        "${PROJECT_ROOT}/stacks/litellm"
        "${PROJECT_ROOT}/stacks/anythingllm"
        "${PROJECT_ROOT}/stacks/clawdbot"
        "${PROJECT_ROOT}/stacks/dify"
        "${PROJECT_ROOT}/stacks/n8n"
        "${PROJECT_ROOT}/stacks/signal"
        "${PROJECT_ROOT}/stacks/gdrive"
        "${PROJECT_ROOT}/stacks/nginx"
        "${PROJECT_ROOT}/scripts"
        "${PROJECT_ROOT}/logs"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    success "Directory structure created"
}

# ============================================================================
# System Dependencies
# ============================================================================

install_system_dependencies() {
    info "[2/7] Installing system dependencies..."
    
    sudo apt-get update
    sudo apt-get install -y \
        curl \
        wget \
        git \
        jq \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        openssl \
        fuse3 \
        libfuse3-dev
    
    success "System dependencies installed"
}

# ============================================================================
# Docker Installation
# ============================================================================

install_docker() {
    info "[3/7] Installing Docker..."
    
    if command -v docker &>/dev/null; then
        success "Docker already installed"
        docker --version
        return 0
    fi
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker "${USER}"
    
    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    success "Docker installed"
    docker --version
}

# ============================================================================
# Tailscale Installation & Configuration
# ============================================================================

install_and_configure_tailscale() {
    info "[4/7] Installing and configuring Tailscale..."
    
    # Install Tailscale if not present
    if ! command -v tailscale &>/dev/null; then
        info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
        success "Tailscale installed"
    else
        success "Tailscale already installed"
    fi
    
    # Check if already authenticated
    if sudo tailscale status &>/dev/null; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "")
        
        if [[ -n "$tailscale_ip" ]]; then
            success "Tailscale already authenticated"
            info "Tailscale IP: $tailscale_ip"
            return 0
        fi
    fi
    
    # Need to authenticate
    echo ""
    warn "═══════════════════════════════════════════════════════════"
    warn "  TAILSCALE AUTHENTICATION REQUIRED"
    warn "═══════════════════════════════════════════════════════════"
    echo ""
    info "This will open a browser window for authentication."
    info "Please complete the authentication process."
    echo ""
    read -p "Press ENTER to continue..." -r
    
    # Start Tailscale and authenticate
    sudo tailscale up --accept-routes --ssh
    
    # Wait for authentication
    local max_wait=60
    local count=0
    
    info "Waiting for Tailscale authentication..."
    while [ $count -lt $max_wait ]; do
        if tailscale status &>/dev/null; then
            local tailscale_ip
            tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "")
            
            if [[ -n "$tailscale_ip" ]]; then
                echo ""
                success "Tailscale authenticated successfully!"
                success "Tailscale IP: $tailscale_ip"
                
                # Configure Tailscale serve for HTTPS on port 8443
                info "Configuring Tailscale serve..."
                sudo tailscale serve https:8443 / https://127.0.0.1:443 &>/dev/null || \
                    warn "Tailscale serve will be configured after deployment"
                
                return 0
            fi
        fi
        echo -n "."
        sleep 2
        ((count+=2))
    done
    
    echo ""
    error "Tailscale authentication timed out"
    error "Please run manually: sudo tailscale up --accept-routes --ssh"
    exit 1
}

# ============================================================================
# Generate SSL Certificates
# ============================================================================

generate_ssl_certs() {
    info "[5/7] Generating self-signed SSL certificates..."
    
    local ssl_dir="${PROJECT_ROOT}/data/nginx/ssl"
    local cert_file="${ssl_dir}/cert.pem"
    local key_file="${ssl_dir}/key.pem"
    
    if [[ -f "$cert_file" ]] && [[ -f "$key_file" ]]; then
        success "SSL certificates already exist"
        return 0
    fi
    
    # Generate self-signed certificate valid for 1 year
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=US/ST=State/L=City/O=AI Platform/CN=ai-platform.local"
    
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    
    success "SSL certificates generated"
}

# ============================================================================
# Environment File Generation
# ============================================================================

generate_env_file() {
    info "[6/7] Generating environment configuration..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ -f "$env_file" ]]; then
        warn "Environment file already exists, backing up..."
        mv "$env_file" "${env_file}.backup.$(date +%s)"
    fi
    
    # Generate secure random keys
    local litellm_master_key=$(openssl rand -hex 32)
    local litellm_salt_key=$(openssl rand -hex 16)
    local dify_secret_key=$(openssl rand -hex 32)
    local dify_encrypt_key=$(openssl rand -base64 32)
    local dify_db_password=$(openssl rand -hex 16)
    local dify_redis_password=$(openssl rand -hex 16)
    local n8n_encryption_key=$(openssl rand -hex 32)
    local anythingllm_jwt_secret=$(openssl rand -hex 32)
    local anythingllm_storage_key=$(openssl rand -hex 32)
    local clawdbot_secret=$(openssl rand -hex 32)
    local gdrive_encryption_password=$(openssl rand -hex 32)
    
    # Get Tailscale IP
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "100.64.0.1")
    
    cat > "$env_file" << EOF
# ============================================================================
# AI Platform Environment Configuration v8.2
# Generated: $(date)
# ============================================================================

# Project Paths
PROJECT_ROOT=${PROJECT_ROOT}
DATA_DIR=${PROJECT_ROOT}/data
STACKS_DIR=${PROJECT_ROOT}/stacks

# Network Configuration
TAILSCALE_IP=${tailscale_ip}
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
TAILSCALE_HTTPS_PORT=8443

# Ollama Configuration
OLLAMA_PORT=11434
OLLAMA_HOST=0.0.0.0

# LiteLLM Configuration
LITELLM_PORT=4000
LITELLM_MASTER_KEY=${litellm_master_key}
LITELLM_SALT_KEY=${litellm_salt_key}

# AnythingLLM Configuration
ANYTHINGLLM_PORT=3001
ANYTHINGLLM_JWT_SECRET=${anythingllm_jwt_secret}
ANYTHINGLLM_STORAGE_KEY=${anythingllm_storage_key}
ANYTHINGLLM_STORAGE_DIR=${PROJECT_ROOT}/data/anythingllm/storage
ANYTHINGLLM_VECTOR_DB=lancedb

# Clawdbot Configuration
CLAWDBOT_PORT=18789
CLAWDBOT_SECRET=${clawdbot_secret}
CLAWDBOT_SIGNAL_NUMBER=
CLAWDBOT_ADMIN_NUMBERS=

# Dify Configuration
DIFY_WEB_PORT=3000
DIFY_API_PORT=5001
DIFY_DB_USER=dify
DIFY_DB_PASSWORD=${dify_db_password}
DIFY_DB_NAME=dify
DIFY_REDIS_PASSWORD=${dify_redis_password}
DIFY_SECRET_KEY=${dify_secret_key}
DIFY_ENCRYPT_KEY=${dify_encrypt_key}

# n8n Configuration
N8N_PORT=5678
N8N_ENCRYPTION_KEY=${n8n_encryption_key}
N8N_WEBHOOK_URL=https://${tailscale_ip}:8443/n8n/webhook

# Signal API Configuration
SIGNAL_API_PORT=8080
SIGNAL_AUTO_RECEIVE=0 */5 * * * *

# Google Drive Sync Configuration
GDRIVE_SYNC_INTERVAL=3600
GDRIVE_SYNC_DIR=${PROJECT_ROOT}/data/gdrive/sync
GDRIVE_CONFIG_DIR=${PROJECT_ROOT}/data/gdrive/config
GDRIVE_LOG_DIR=${PROJECT_ROOT}/data/gdrive/logs
GDRIVE_RCLONE_CONFIG_PASS=${gdrive_encryption_password}
GDRIVE_MOUNT_PATH=/gdrive
GDRIVE_REMOTE_NAME=gdrive
GDRIVE_REMOTE_PATH=/AI-Platform-Docs

# User Configuration
PLATFORM_USER=${USER}
PLATFORM_UID=$(id -u)
PLATFORM_GID=$(id -g)

# Logging
LOG_LEVEL=INFO
LOG_DIR=${PROJECT_ROOT}/logs
EOF
    
    chmod 600 "$env_file"
    
    success "Environment file generated: $env_file"
}

# ============================================================================
# Permissions Setup
# ============================================================================

set_permissions() {
    info "[7/7] Setting file permissions..."
    
    # Make all shell scripts executable
    find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    # Set ownership for data directories
    sudo chown -R "${USER}:${USER}" "${PROJECT_ROOT}/data"
    
    # Specific permissions for sensitive files
    chmod 700 "${PROJECT_ROOT}/data/nginx/ssl"
    chmod 700 "${PROJECT_ROOT}/data/gdrive/config"
    
    success "Permissions set"
}

# ============================================================================
# Verify Docker Group Membership
# ============================================================================

verify_docker_group() {
    info "Verifying Docker group membership..."
    
    if groups | grep -q docker; then
        success "User already in docker group"
        return 0
    fi
    
    warn "Docker group membership not active yet"
    warn "You need to log out and back in, OR run: newgrp docker"
    echo ""
    read -p "Would you like to activate docker group now? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Activating docker group..."
        exec sg docker "$0 --continue"
    fi
}

# ============================================================================
# Post-Installation Instructions
# ============================================================================

display_post_install() {
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "NOT_CONFIGURED")
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              SETUP COMPLETED SUCCESSFULLY!                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "System setup completed successfully"
    echo ""
    
    if [[ "$tailscale_ip" != "NOT_CONFIGURED" ]]; then
        success "Tailscale IP: $tailscale_ip"
        echo ""
        info "Next step:"
        echo "  cd ${PROJECT_ROOT}/scripts && ./2-deploy-services.sh"
    else
        warn "Tailscale not fully configured"
        echo ""
        info "Next steps:"
        echo "  1. Authenticate Tailscale: sudo tailscale up --accept-routes --ssh"
        echo "  2. Deploy services: cd ${PROJECT_ROOT}/scripts && ./2-deploy-services.sh"
    fi
    
    echo ""
    info "Environment file: ${PROJECT_ROOT}/.env"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Handle --continue flag for docker group activation
    if [[ "${1:-}" == "--continue" ]]; then
        shift
    fi
    
    display_banner
    
    create_directories
    install_system_dependencies
    install_docker
    install_and_configure_tailscale
    generate_ssl_certs
    generate_env_file
    set_permissions
    
    verify_docker_group
    
    display_post_install
}

main "$@"
