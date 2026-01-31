#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform System Setup v3.3
# Ubuntu 22.04 & 24.04 Support
# Auto-detects GPU vs CPU-only instances
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/ai-platform-setup.log"
sudo touch "$LOG_FILE"
sudo chown $USER:$USER "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI Platform System Setup v3.3${NC}"
echo -e "${BLUE}User: $USER (UID: $(id -u))${NC}"
echo -e "${BLUE}Started: $(date)${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================
# Detect System Configuration
# ============================================
detect_system() {
    echo -e "\n${BLUE}[1/11] Checking prerequisites...${NC}"
    echo "   Current user: $USER"
    echo "   UID: $(id -u)"
    echo "   GID: $(id -g)"
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        UBUNTU_VERSION="$VERSION_ID"
        echo "   Ubuntu version: $UBUNTU_VERSION"
        
        if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
            echo -e "${RED}❌ Ubuntu 22.04 or 24.04 LTS required${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Cannot detect Ubuntu version${NC}"
        exit 1
    fi
    
    # Detect GPU
    if command -v nvidia-smi &> /dev/null; then
        HAS_GPU="true"
        GPU_TYPE=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "nvidia")
        echo "   GPU detected: $GPU_TYPE"
    else
        HAS_GPU="false"
        GPU_TYPE="none"
        echo "   No GPU detected (CPU-only mode)"
    fi
    
    # Detect instance type
    if command -v ec2-metadata &> /dev/null; then
        INSTANCE_TYPE=$(ec2-metadata --instance-type 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    else
        INSTANCE_TYPE="unknown"
    fi
    
    # Get Tailscale IP
    if command -v tailscale &> /dev/null; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "not-connected")
    else
        TAILSCALE_IP="not-installed"
    fi
    
    echo -e "   ${GREEN}✅ System detected${NC}"
}

# ============================================
# Generate Secrets
# ============================================
generate_secret() {
    openssl rand -hex 32
}

# ============================================
# Create Environment File
# ============================================
create_env_file() {
    echo -e "\n${BLUE}[2/11] Creating environment file...${NC}"
    
    local DATA_PATH="/home/$USER/ai-platform-data"
    
    cat > "$SCRIPT_DIR/.env" <<ENV_EOF
# AI Platform Environment
PLATFORM_USER=$USER
PLATFORM_UID=$(id -u)
PLATFORM_GID=$(id -g)
TAILSCALE_IP=$TAILSCALE_IP
UBUNTU_VERSION=$UBUNTU_VERSION
HAS_GPU=$HAS_GPU
GPU_TYPE=$GPU_TYPE
INSTANCE_TYPE=$INSTANCE_TYPE
INSTALL_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S%z")

# Data Paths
DATA_PATH=$DATA_PATH
OLLAMA_DATA=${DATA_PATH}/ollama
LITELLM_DATA=${DATA_PATH}/litellm
DIFY_DATA=${DATA_PATH}/dify
ANYTHINGLLM_DATA=${DATA_PATH}/anythingllm
SIGNAL_DATA=${DATA_PATH}/signal
CLAWDBOT_DATA=${DATA_PATH}/clawdbot

# API Keys and Secrets
OLLAMA_API_KEY=$(generate_secret)
DIFY_DB_PASSWORD=$(generate_secret)
ANYTHINGLLM_JWT_SECRET=$(generate_secret)
CLAWDBOT_MCP_API_KEY=$(generate_secret)

# Service Ports
OLLAMA_PORT=11434
LITELLM_PORT=4000
DIFY_PORT=5001
ANYTHINGLLM_PORT=3001
SIGNAL_PORT=8080
CLAWDBOT_PORT=8000
ENV_EOF

    chmod 600 "$SCRIPT_DIR/.env"
    echo -e "   ${GREEN}✅ Environment file created${NC}"
    echo "   Location: $SCRIPT_DIR/.env"
}

# ============================================
# Create Data Directories
# ============================================
create_data_dirs() {
    echo -e "\n${BLUE}[3/11] Creating data directories...${NC}"
    
    source "$SCRIPT_DIR/.env"
    
    local dirs=(
        "$DATA_PATH"
        "$OLLAMA_DATA"
        "$LITELLM_DATA"
        "$DIFY_DATA"
        "$ANYTHINGLLM_DATA"
        "$SIGNAL_DATA"
        "$CLAWDBOT_DATA"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        echo "   Created: $dir"
    done
    
    echo -e "   ${GREEN}✅ Data directories created${NC}"
}

# ============================================
# Update System
# ============================================
update_system() {
    echo -e "\n${BLUE}[4/11] Updating system packages...${NC}"
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    echo -e "   ${GREEN}✅ System updated${NC}"
}

# ============================================
# Install Base Packages
# ============================================
install_base_packages() {
    echo -e "\n${BLUE}[5/11] Installing base packages...${NC}"
    
    local packages=(
        curl
        wget
        git
        vim
        htop
        tmux
        jq
        ca-certificates
        gnupg
        lsb-release
        apt-transport-https
        software-properties-common
        gettext-base
    )
    
    sudo apt-get install -y -qq "${packages[@]}"
    echo -e "   ${GREEN}✅ Base packages installed${NC}"
}

# ============================================
# Install Docker
# ============================================
install_docker() {
    echo -e "\n${BLUE}[6/11] Installing Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        echo "   Docker already installed"
        DOCKER_VERSION=$(docker --version)
        echo "   $DOCKER_VERSION"
    else
        # Add Docker's official GPG key
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        # Add Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        echo -e "   ${GREEN}✅ Docker installed${NC}"
    fi
    
    # Add user to docker group
    if ! groups $USER | grep -q docker; then
        sudo usermod -aG docker $USER
        echo "   Added $USER to docker group"
    fi
    
    # Create Docker network
    if ! docker network ls | grep -q ai-platform-network; then
        docker network create ai-platform-network 2>/dev/null || true
        echo "   Created Docker network: ai-platform-network"
    fi
}

# ============================================
# Install NVIDIA Container Toolkit (if GPU)
# ============================================
install_nvidia_toolkit() {
    if [[ "$HAS_GPU" != "true" ]]; then
        echo -e "\n${BLUE}[7/11] Skipping NVIDIA toolkit (no GPU)${NC}"
        return 0
    fi
    
    echo -e "\n${BLUE}[7/11] Installing NVIDIA Container Toolkit...${NC}"
    
    if docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        echo "   NVIDIA Container Toolkit already configured"
        return 0
    fi
    
    # Add NVIDIA repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Install toolkit
    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit
    
    # Configure Docker
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    
    echo -e "   ${GREEN}✅ NVIDIA Container Toolkit installed${NC}"
}

# ============================================
# Install Tailscale
# ============================================
install_tailscale() {
    echo -e "\n${BLUE}[8/11] Installing Tailscale...${NC}"
    
    if command -v tailscale &> /dev/null; then
        echo "   Tailscale already installed"
        TAILSCALE_STATUS=$(tailscale status --json 2>/dev/null | jq -r '.Self.Online' || echo "unknown")
        echo "   Status: $TAILSCALE_STATUS"
    else
        curl -fsSL https://tailscale.com/install.sh | sh
        echo -e "   ${GREEN}✅ Tailscale installed${NC}"
        echo -e "   ${YELLOW}⚠️  Run 'sudo tailscale up' to connect${NC}"
    fi
}

# ============================================
# Setup Systemd Services
# ============================================
setup_systemd() {
    echo -e "\n${BLUE}[9/11] Setting up systemd services...${NC}"
    
    # Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    echo -e "   ${GREEN}✅ Services configured${NC}"
}

# ============================================
# Configure Firewall
# ============================================
configure_firewall() {
    echo -e "\n${BLUE}[10/11] Configuring firewall...${NC}"
    
    if ! command -v ufw &> /dev/null; then
        sudo apt-get install -y -qq ufw
    fi
    
    # Allow Tailscale
    sudo ufw allow in on tailscale0
    
    # Allow SSH (just in case)
    sudo ufw allow 22/tcp
    
    # Enable firewall (non-interactive)
    echo "y" | sudo ufw enable 2>/dev/null || true
    
    echo -e "   ${GREEN}✅ Firewall configured${NC}"
}

# ============================================
# Final Summary
# ============================================
show_summary() {
    echo -e "\n${BLUE}[11/11] Setup complete!${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}System Setup Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "System Configuration:"
    echo "  User: $USER"
    echo "  Ubuntu: $UBUNTU_VERSION"
    echo "  GPU: $HAS_GPU ($GPU_TYPE)"
    echo "  Instance: $INSTANCE_TYPE"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. IMPORTANT - Log out and log back in:"
    echo -e "   ${YELLOW}Log out and log back in${NC} for group memberships to take effect:"
    echo "   exit"
    echo "   ssh $USER@<ip>"
    echo ""
    echo "2. Verify everything works:"
    echo "   docker ps"
    if [[ "$HAS_GPU" == "true" ]]; then
        echo "   docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi"
    fi
    echo ""
    echo "3. Deploy services:"
    echo "   cd ~/ai-platform-installer"
    echo "   ./deploy-services.sh"
    echo ""
    echo "Environment file: $SCRIPT_DIR/.env"
    echo "Logs: $LOG_FILE"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    detect_system
    create_env_file
    create_data_dirs
    update_system
    install_base_packages
    install_docker
    install_nvidia_toolkit
    install_tailscale
    setup_systemd
    configure_firewall
    show_summary
}

main "$@"

chmod +x ~/ai-platform-installer/setup-system.sh
