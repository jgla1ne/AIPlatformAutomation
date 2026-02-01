#!/bin/bash
set -euo pipefail

# =============================================================================
# AI Platform - System Setup Script v6.0 - COMPLETE ENV GENERATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

generate_key() {
    local length=${1:-32}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

check_gpu() {
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

get_tailscale_ip() {
    if command -v tailscale &> /dev/null; then
        tailscale_ip=$(tailscale ip -4 2>/dev/null | head -n1)
        if [[ -n "$tailscale_ip" && "$tailscale_ip" =~ ^100\. ]]; then
            echo "$tailscale_ip"
            return 0
        fi
    fi
    echo "127.0.0.1"
}

# =============================================================================
# Main Setup
# =============================================================================

header "AI Platform - System Setup v6.0"
info "Location: ${PROJECT_ROOT}"
info "Started: $(date)"

# =============================================================================
# Step 1: Update System
# =============================================================================

info "[1/6] Updating system packages..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log "System updated"

# =============================================================================
# Step 2: Install Dependencies
# =============================================================================

info "[2/6] Installing dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    openssl \
    netcat-openbsd \
    wget \
    software-properties-common

log "Dependencies installed"

# =============================================================================
# Step 3: Install and Configure Docker
# =============================================================================

info "[3/6] Installing and configuring Docker..."

# Stop existing services
info "Stopping existing Docker services..."
sudo systemctl stop docker.service 2>/dev/null || true
sudo systemctl stop docker.socket 2>/dev/null || true
sudo systemctl stop containerd.service 2>/dev/null || true

# Create docker group FIRST
info "Ensuring docker group exists..."
sudo groupadd docker 2>/dev/null || true
log "Docker group created"

# Add user to docker group
info "Adding $(whoami) to docker group..."
sudo usermod -aG docker "$(whoami)"
log "User added to docker group"

# Reload systemd to recognize the group
info "Reloading systemd to recognize docker group..."
sudo systemctl daemon-reload
log "Systemd reloaded"

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    docker_version=$(docker --version 2>/dev/null || echo "unknown")
    info "Docker already installed: ${docker_version}"
else
    info "Installing Docker..."
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker packages
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log "Docker installed"
fi

# Enable and start services in correct order
info "Starting Docker services..."
sudo systemctl enable containerd.service
sudo systemctl start containerd.service
sudo systemctl enable docker.socket
sudo systemctl start docker.socket
sudo systemctl enable docker.service
sudo systemctl start docker.service

# Verify Docker is running
if sudo systemctl is-active --quiet docker.service; then
    log "Docker is running"
else
    error "Docker failed to start"
    sudo systemctl status docker.service --no-pager
    exit 1
fi

# Create Docker network
info "Creating Docker network..."
if ! docker network inspect ai-platform-network &>/dev/null; then
    docker network create ai-platform-network
    log "Docker network created"
else
    info "Docker network already exists"
fi

# =============================================================================
# Step 4: GPU Detection
# =============================================================================

info "[4/6] Detecting GPU..."
HAS_GPU=$(check_gpu)

if [[ "$HAS_GPU" == "true" ]]; then
    log "GPU detected - will use GPU acceleration"
    
    # Install NVIDIA Container Toolkit
    if ! command -v nvidia-ctk &> /dev/null; then
        info "Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        sudo apt-get update -qq
        sudo apt-get install -y -qq nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        log "NVIDIA Container Toolkit installed"
    else
        info "NVIDIA Container Toolkit already installed"
    fi
else
    warn "No GPU detected - will use CPU only"
fi

# =============================================================================
# Step 5: Network Configuration
# =============================================================================

info "[5/6] Configuring network..."
TAILSCALE_IP=$(get_tailscale_ip)

if [[ "$TAILSCALE_IP" == "127.0.0.1" ]]; then
    warn "Tailscale not detected - using localhost"
else
    log "Tailscale IP: ${TAILSCALE_IP}"
fi

# =============================================================================
# Step 6: Generate Configuration
# =============================================================================

info "[6/6] Generating configuration..."

# Create data directory
DATA_DIR="${HOME}/AIPlatformAutomation/data"
mkdir -p "$DATA_DIR"/{litellm,dify,n8n,signal,ollama,postgres,redis}
log "Data directories created at ${DATA_DIR}"

# Generate .env file with ALL required variables
cat > "$ENV_FILE" << EOF
# =============================================================================
# AI Platform Configuration - COMPLETE
# Generated: $(date)
# =============================================================================

# System Configuration
HAS_GPU=${HAS_GPU}
TAILSCALE_IP=${TAILSCALE_IP}
LOG_LEVEL=info

# Docker Configuration
DOCKER_NETWORK=ai-platform-network
COMPOSE_PROJECT_NAME=ai-platform

# Directory Paths
DATA_DIR=${DATA_DIR}
SCRIPT_DIR=${SCRIPT_DIR}
PROJECT_ROOT=${PROJECT_ROOT}
ENV_FILE=${ENV_FILE}

# =============================================================================
# LiteLLM Configuration
# =============================================================================
LITELLM_MASTER_KEY=sk-$(generate_key 48)
LITELLM_PORT=4000
LITELLM_DATABASE_URL=postgresql://\${DIFY_DB_USER}:\${DIFY_DB_PASSWORD}@postgres:5432/litellm

# =============================================================================
# Dify Configuration
# =============================================================================
DIFY_DB_USER=dify_$(generate_key 8)
DIFY_DB_PASSWORD=$(generate_key 48)
POSTGRES_PASSWORD=$(generate_key 48)
DIFY_SECRET_KEY=$(generate_key 48)
REDIS_PASSWORD=$(generate_key 32)
DIFY_API_PORT=5001
DIFY_WEB_PORT=3000
SANDBOX_PORT=8194

# =============================================================================
# n8n Configuration
# =============================================================================
N8N_PORT=5678
N8N_ENCRYPTION_KEY=$(generate_key 32)
N8N_USER_MANAGEMENT_JWT_SECRET=$(generate_key 32)
N8N_WEBHOOK_URL=http://\${TAILSCALE_IP}:5678/

# =============================================================================
# Signal Configuration
# =============================================================================
SIGNAL_API_PORT=8080
SIGNAL_DEVICE_NAME=ai-platform-$(generate_key 8)
# SIGNAL_PHONE_NUMBER=  # Set this manually in script 4

# =============================================================================
# Ollama Configuration
# =============================================================================
OLLAMA_PORT=11434
OLLAMA_MODELS=llama2,codellama  # Models to pre-download

EOF

chmod 600 "$ENV_FILE"
log "Configuration generated"

# Set script permissions
chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true

# =============================================================================
# Completion Summary
# =============================================================================

header "Setup Complete!"
echo ""
echo "Configuration saved to: ${ENV_FILE}"
echo ""
echo "System Status:"
echo "  • GPU Available: ${HAS_GPU}"
echo "  • Tailscale IP: ${TAILSCALE_IP}"
echo "  • Data Directory: ${DATA_DIR}"
echo "  • Containerd: $(sudo systemctl is-active containerd)"
echo "  • Docker Socket: $(sudo systemctl is-active docker.socket)"
echo "  • Docker Service: $(sudo systemctl is-active docker)"
echo "  • Docker Network: $(docker network ls | grep -q ai-platform-network && echo 'active' || echo 'missing')"
echo ""

# Check if group membership is active
if groups | grep -q '\bdocker\b'; then
    log "Docker group is active - ready to proceed!"
    echo ""
    echo "Next step:"
    echo "  ./2-deploy-services.sh"
else
    warn "Docker group requires new session"
    echo ""
    echo "Run ONE of these:"
    echo "  newgrp docker && ./2-deploy-services.sh"
    echo ""
    echo "OR logout/login then:"
    echo "  ./2-deploy-services.sh"
fi

echo ""
log "Environment variables generated: $(grep -c '^[A-Z]' "$ENV_FILE")"
echo ""
