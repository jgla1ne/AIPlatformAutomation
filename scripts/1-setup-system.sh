#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - System Setup v5.3
# Path-agnostic: Works with any repo name
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="$(basename "$SCRIPT_DIR")"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/logs/setup-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - System Setup v5.3${NC}"
log "${BLUE}Repository: $REPO_NAME${NC}"
log "${BLUE}Location: $SCRIPT_DIR${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}========================================${NC}"
echo ""

# ============================================
# [1/10] Detect Environment
# ============================================
detect_environment() {
    log "${BLUE}[1/10] Detecting environment...${NC}"
    
    # Detect GPU
    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        log "   ${GREEN}✓ GPU detected: $GPU_INFO${NC}"
    else
        GPU_AVAILABLE=false
        log "   ${YELLOW}⚠ No GPU detected (CPU-only mode)${NC}"
    fi
    
    # Detect cloud provider
    if curl -s -m 2 http://169.254.169.254/latest/meta-data/ &> /dev/null; then
        CLOUD_PROVIDER="aws"
        INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
        log "   ${GREEN}✓ AWS EC2 detected: $INSTANCE_TYPE${NC}"
    else
        CLOUD_PROVIDER="unknown"
        log "   ${BLUE}ℹ Local/other environment${NC}"
    fi
    
    # Detect storage
    STORAGE_DEVICE=""
    if lsblk | grep -q nvme1n1; then
        STORAGE_DEVICE="/dev/nvme1n1"
        STORAGE_SIZE=$(lsblk -d -n -o SIZE "$STORAGE_DEVICE" | xargs)
        log "   ${GREEN}✓ Found: $STORAGE_DEVICE ($STORAGE_SIZE)${NC}"
    else
        log "   ${YELLOW}⚠ No secondary storage detected${NC}"
    fi
    
    echo ""
}

# ============================================
# [2/10] Update System
# ============================================
update_system() {
    log "${BLUE}[2/10] Updating system packages...${NC}"
    
    export DEBIAN_FRONTEND=noninteractive
    
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    sudo apt-get install -y -qq \
        curl \
        wget \
        git \
        jq \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common
    
    log "   ${GREEN}✓ System updated${NC}"
    echo ""
}

# ============================================
# [3/10] Configure Storage
# ============================================
configure_storage() {
    log "${BLUE}[3/10] Configuring storage...${NC}"
    
    if [[ -z "$STORAGE_DEVICE" ]]; then
        log "   ${YELLOW}⚠ Skipping - no secondary storage${NC}"
        
        # Use root filesystem
        sudo mkdir -p /mnt/data
        sudo chown -R $USER:$USER /mnt/data
        log "   ${GREEN}✓ Using /mnt/data on root filesystem${NC}"
        echo ""
        return
    fi
    
    # Check if already mounted
    if mountpoint -q /mnt/data; then
        log "   ${GREEN}✓ /mnt/data already mounted${NC}"
        echo ""
        return
    fi
    
    # Check if filesystem exists
    if ! sudo blkid "$STORAGE_DEVICE" | grep -q ext4; then
        log "   Creating ext4 filesystem on $STORAGE_DEVICE..."
        sudo mkfs.ext4 -F "$STORAGE_DEVICE" > /dev/null 2>&1
    fi
    
    # Mount
    sudo mkdir -p /mnt/data
    sudo mount "$STORAGE_DEVICE" /mnt/data
    
    # Add to fstab if not present
    DEVICE_UUID=$(sudo blkid -s UUID -o value "$STORAGE_DEVICE")
    if ! grep -q "$DEVICE_UUID" /etc/fstab; then
        echo "UUID=$DEVICE_UUID /mnt/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
        sudo systemctl daemon-reload
    fi
    
    sudo chown -R $USER:$USER /mnt/data
    
    log "   ${GREEN}✓ Mounted and configured${NC}"
    echo ""
}

# ============================================
# [4/10] Install Docker
# ============================================
install_docker() {
    log "${BLUE}[4/10] Installing Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log "   ${GREEN}✓ Docker already installed: $DOCKER_VERSION${NC}"
        echo ""
        return
    fi
    
    # Add Docker repository
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Configure Docker user
    sudo usermod -aG docker $USER
    
    # Configure Docker daemon
    sudo mkdir -p /etc/docker
    cat <<DOCKER_CONFIG | sudo tee /etc/docker/daemon.json > /dev/null
{
  "data-root": "/mnt/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKER_CONFIG
    
    sudo systemctl enable docker
    sudo systemctl restart docker
    
    log "   ${GREEN}✓ Docker installed${NC}"
    echo ""
}

# ============================================
# [5/10] Install NVIDIA Container Toolkit
# ============================================
install_nvidia_toolkit() {
    log "${BLUE}[5/10] Configuring GPU support...${NC}"
    
    if [[ "$GPU_AVAILABLE" != "true" ]]; then
        log "   ${YELLOW}⚠ Skipping - CPU-only mode${NC}"
        echo ""
        return
    fi
    
    # Check if already installed
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        log "   ${GREEN}✓ NVIDIA Container Toolkit already configured${NC}"
        echo ""
        return
    fi
    
    # Install toolkit
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit
    
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    
    log "   ${GREEN}✓ NVIDIA Container Toolkit installed${NC}"
    echo ""
}

# ============================================
# [6/10] Install Tailscale
# ============================================
install_tailscale() {
    log "${BLUE}[6/10] Installing Tailscale...${NC}"
    
    if command -v tailscale &> /dev/null; then
        if tailscale status &> /dev/null; then
            TAILSCALE_IP=$(tailscale ip -4)
            log "   ${GREEN}✓ Tailscale already configured: $TAILSCALE_IP${NC}"
            echo ""
            return
        fi
    fi
    
    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    
    # Start but don't authenticate yet
    sudo tailscale up --accept-routes
    
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not authenticated")
    
    if [[ "$TAILSCALE_IP" == "Not authenticated" ]]; then
        log "   ${YELLOW}⚠ Tailscale installed but not authenticated${NC}"
        log "   ${YELLOW}Run: sudo tailscale up${NC}"
    else
        log "   ${GREEN}✓ Tailscale configured: $TAILSCALE_IP${NC}"
    fi
    
    echo ""
}

# ============================================
# [7/10] Create Data Directories
# ============================================
create_directories() {
    log "${BLUE}[7/10] Creating data directories...${NC}"
    
    DIRS=(
        "/mnt/data/ollama"
        "/mnt/data/litellm"
        "/mnt/data/signal"
        "/mnt/data/dify/postgres"
        "/mnt/data/dify/redis"
        "/mnt/data/dify/storage"
        "/mnt/data/anythingllm"
        "/mnt/data/clawdbot"
    )
    
    for dir in "${DIRS[@]}"; do
        sudo mkdir -p "$dir"
        sudo chown -R $USER:$USER "$dir"
    done
    
    log "   ${GREEN}✓ All directories created${NC}"
    echo ""
}

# ============================================
# [8/10] Create Service Users
# ============================================
create_service_users() {
    log "${BLUE}[8/10] Creating service users...${NC}"
    
    USERS=("ollama" "litellm" "signal" "dify" "anythingllm" "clawdbot")
    
    for user in "${USERS[@]}"; do
        if ! id "$user" &>/dev/null; then
            sudo useradd -r -s /bin/false -M "$user"
        fi
        
        # Set ownership
        if [[ -d "/mnt/data/$user" ]]; then
            sudo chown -R $user:$user "/mnt/data/$user"
        fi
    done
    
    log "   ${GREEN}✓ Service users created${NC}"
    echo ""
}

# ============================================
# [9/10] Generate Environment File
# ============================================
generate_environment() {
    log "${BLUE}[9/10] Generating environment configuration...${NC}"
    
    # Generate secure passwords
    DIFY_DB_PASSWORD=$(openssl rand -hex 16)
    DIFY_SECRET_KEY=$(openssl rand -hex 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 16)
    LITELLM_SALT_KEY=$(openssl rand -hex 16)
    
    # Get Tailscale IP
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
    
    # Create .env file
    cat > "$ENV_FILE" <<ENV_CONTENT
# ============================================
# AI Platform Environment Configuration
# Generated: $(date)
# ============================================

# System Configuration
REPO_DIR=$SCRIPT_DIR
DATA_DIR=/mnt/data
GPU_AVAILABLE=$GPU_AVAILABLE
CLOUD_PROVIDER=$CLOUD_PROVIDER

# Network
TAILSCALE_IP=$TAILSCALE_IP
DOCKER_NETWORK=ai-platform-network

# Ollama
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_DATA=/mnt/data/ollama
OLLAMA_MODELS=llama3.2:latest,mistral:latest

# LiteLLM
LITELLM_PORT=4000
LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY
LITELLM_SALT_KEY=$LITELLM_SALT_KEY
LITELLM_DATA=/mnt/data/litellm

# Signal
SIGNAL_PORT=8080
SIGNAL_DATA=/mnt/data/signal
SIGNAL_NUMBER=

# Dify
DIFY_PORT=3000
DIFY_API_PORT=5001
DIFY_DB_PASSWORD=$DIFY_DB_PASSWORD
DIFY_SECRET_KEY=$DIFY_SECRET_KEY
DIFY_DATA=/mnt/data/dify

# AnythingLLM
ANYTHINGLLM_PORT=3001
ANYTHINGLLM_DATA=/mnt/data/anythingllm

# ClawdBot
CLAWDBOT_DATA=/mnt/data/clawdbot
CLAWDBOT_LOG_LEVEL=INFO

# Service Users
OLLAMA_UID=$(id -u ollama)
LITELLM_UID=$(id -u litellm)
SIGNAL_UID=$(id -u signal)
DIFY_UID=$(id -u dify)
ANYTHINGLLM_UID=$(id -u anythingllm)
CLAWDBOT_UID=$(id -u clawdbot)
ENV_CONTENT
    
    chmod 600 "$ENV_FILE"
    
    log "   ${GREEN}✓ Environment file created: $ENV_FILE${NC}"
    echo ""
}

# ============================================
# [10/10] Verify Installation
# ============================================
verify_installation() {
    log "${BLUE}[10/10] Verifying installation...${NC}"
    echo ""
    
    log "${GREEN}Installation Summary:${NC}"
    
    # Docker
    if docker --version &> /dev/null; then
        log "  ${GREEN}✓ Docker${NC}"
    else
        log "  ${RED}✗ Docker${NC}"
    fi
    
    # GPU
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        log "  ${GREEN}✓ GPU: $GPU_INFO${NC}"
    else
        log "  ${YELLOW}⚠ CPU-only mode${NC}"
    fi
    
    # Tailscale
    if command -v tailscale &> /dev/null; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not authenticated")
        log "  ${GREEN}✓ Tailscale: $TAILSCALE_IP${NC}"
    else
        log "  ${RED}✗ Tailscale${NC}"
    fi
    
    # Storage
    STORAGE_AVAILABLE=$(df -h /mnt/data | awk 'NR==2 {print $4}')
    log "  ${GREEN}✓ Data: /mnt/data ($STORAGE_AVAILABLE)${NC}"
    
    # Service users
    log "  ${GREEN}✓ Service users${NC}"
    
    # Environment
    log "  ${GREEN}✓ Environment configured${NC}"
    
    echo ""
}

# ============================================
# Final Instructions
# ============================================
print_next_steps() {
    log "${GREEN}========================================${NC}"
    log "${GREEN}✅ System Setup Complete${NC}"
    log "${GREEN}========================================${NC}"
    echo ""
    
    log "${YELLOW}⚠️  IMPORTANT: Logout and reconnect to apply Docker group${NC}"
    echo ""
    
    log "${BLUE}Next steps:${NC}"
    log "  1. Logout: ${YELLOW}exit${NC}"
    log "  2. Reconnect: ${YELLOW}ssh $USER@$(hostname)${NC}"
    log "  3. Go to: ${YELLOW}cd $SCRIPT_DIR/scripts${NC}"
    log "  4. Deploy: ${YELLOW}./2-deploy-services.sh${NC}"
    echo ""
    
    log "${BLUE}Files created:${NC}"
    log "  Environment: $ENV_FILE"
    log "  Log file: $LOG_FILE"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    detect_environment
    update_system
    configure_storage
    install_docker
    install_nvidia_toolkit
    install_tailscale
    create_directories
    create_service_users
    generate_environment
    verify_installation
    print_next_steps
}

main "$@"

