#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - System Setup v5.0
# Idempotent, can be run multiple times safely
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/ai-platform-setup.log"

# Ensure log file exists
sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/ai-platform-setup.log"
sudo chown $USER:$USER "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI Platform - System Setup v5.0${NC}"
echo -e "${BLUE}Started: $(date)${NC}"
echo -e "${BLUE}User: $USER | Hostname: $(hostname)${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================
# Pre-flight Checks
# ============================================
preflight_checks() {
    echo -e "\n${BLUE}[1/12] Pre-flight checks...${NC}"

    # Check user
    if [[ "$USER" != "jglaine" ]] && [[ "$USER" != "ubuntu" ]]; then
        echo -e "   ${YELLOW}⚠️  Running as: $USER (expected: jglaine)${NC}"
        read -p "   Continue? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # Check Ubuntu version
    if ! grep -q "22.04" /etc/os-release 2>/dev/null; then
        echo -e "   ${YELLOW}⚠️  Not Ubuntu 22.04, may have issues${NC}"
    fi

    # Check disk space
    local available=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available -lt 100 ]]; then
        echo -e "   ${RED}❌ Insufficient disk space: ${available}GB (need 100GB+)${NC}"
        exit 1
    fi

    # Check for GPU
    if command -v nvidia-smi &> /dev/null; then
        echo -e "   ${GREEN}✅ NVIDIA GPU detected${NC}"
        nvidia-smi --query-gpu=name --format=csv,noheader | sed 's/^/      /'
    else
        echo -e "   ${YELLOW}⚠️  No NVIDIA GPU detected${NC}"
    fi

    echo -e "   ${GREEN}✅ Pre-flight checks passed${NC}"
}

# ============================================
# Verify Directory Structure
# ============================================
verify_structure() {
    echo -e "\n${BLUE}[2/12] Verifying directory structure...${NC}"

    cd "$SCRIPT_DIR"

    # Check configs/ exists
    if [[ ! -d "configs" ]]; then
        echo -e "   ${RED}❌ configs/ directory missing${NC}"
        exit 1
    fi

    # Verify required config directories
    local required_configs=(signal ollama litellm dify anythingllm clawdbot)
    for config in "${required_configs[@]}"; do
        if [[ -d "configs/$config" ]]; then
            echo -e "   ${GREEN}✅ configs/$config${NC}"
        else
            echo -e "   ${YELLOW}⚠️  configs/$config missing (will create)${NC}"
            mkdir -p "configs/$config"
        fi
    done

    # Create stacks/ if missing (runtime directory)
    mkdir -p stacks
    echo -e "   ${GREEN}✅ Directory structure verified${NC}"
}

# ============================================
# Create Data Directories
# ============================================
create_data_dirs() {
    echo -e "\n${BLUE}[3/12] Creating data directories...${NC}"

    local base_dir="$HOME/ai-platform-data"

    local dirs=(
        "$base_dir"
        "$base_dir/ollama"
        "$base_dir/litellm"
        "$base_dir/dify/postgres"
        "$base_dir/dify/redis"
        "$base_dir/dify/weaviate"
        "$base_dir/dify/nginx/certs"
        "$base_dir/anythingllm"
        "$base_dir/signal"
        "$base_dir/clawdbot/config"
        "$base_dir/clawdbot/logs"
        "$base_dir/clawdbot/data"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            echo "   Created: $dir"
        fi
    done

    # Set proper permissions
    chmod -R 755 "$base_dir"

    echo -e "   ${GREEN}✅ Data directories created${NC}"
}

# ============================================
# Update System
# ============================================
update_system() {
    echo -e "\n${BLUE}[4/12] Updating system packages...${NC}"

    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq

    echo -e "   ${GREEN}✅ System updated${NC}"
}

# ============================================
# Install Base Packages
# ============================================
install_base_packages() {
    echo -e "\n${BLUE}[5/12] Installing base packages...${NC}"

    local packages=(
        curl wget git vim htop tmux jq tree
        ca-certificates gnupg lsb-release
        apt-transport-https software-properties-common
        gettext-base build-essential
        python3 python3-pip python3-venv
        qrencode  # For QR code generation
    )

    sudo apt-get install -y -qq "${packages[@]}"

    echo -e "   ${GREEN}✅ Base packages installed${NC}"
}

# ============================================
# Install Docker
# ============================================
install_docker() {
    echo -e "\n${BLUE}[6/12] Installing Docker...${NC}"

    if command -v docker &> /dev/null; then
        echo -e "   ${GREEN}✅ Docker already installed${NC}"
        docker --version | sed 's/^/      /'
        return 0
    fi

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker $USER

    echo -e "   ${GREEN}✅ Docker installed${NC}"
    echo -e "   ${YELLOW}⚠️  Log out and back in for group changes to take effect${NC}"
}

# ============================================
# Configure Docker
# ============================================
configure_docker() {
    echo -e "\n${BLUE}[7/12] Configuring Docker...${NC}"

    # Create daemon.json for better logging
    sudo mkdir -p /etc/docker

    if [[ -f /etc/docker/daemon.json ]]; then
        echo -e "   ${GREEN}✅ daemon.json already exists${NC}"
    else
        sudo tee /etc/docker/daemon.json > /dev/null <<DAEMON_EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
DAEMON_EOF
        sudo systemctl restart docker
        echo -e "   ${GREEN}✅ Docker configured${NC}"
    fi
}

# ============================================
# Install NVIDIA Container Toolkit
# ============================================
install_nvidia_toolkit() {
    echo -e "\n${BLUE}[8/12] Installing NVIDIA Container Toolkit...${NC}"

    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "   ${BLUE}ℹ️  No NVIDIA GPU, skipping${NC}"
        return 0
    fi

    # Test if already working
    if docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi &> /dev/null 2>&1; then
        echo -e "   ${GREEN}✅ NVIDIA Container Toolkit already working${NC}"
        return 0
    fi

    # Install toolkit
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update -qq
    sudo apt-get install -y nvidia-container-toolkit

    # Configure Docker to use NVIDIA runtime
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker

    echo -e "   ${GREEN}✅ NVIDIA Container Toolkit installed${NC}"
}

# ============================================
# Create Docker Network
# ============================================
create_docker_network() {
    echo -e "\n${BLUE}[9/12] Creating Docker network...${NC}"

    if docker network ls | grep -q "ai-platform-network"; then
        echo -e "   ${GREEN}✅ Network already exists${NC}"
    else
        docker network create ai-platform-network
        echo -e "   ${GREEN}✅ Network created: ai-platform-network${NC}"
    fi
}

# ============================================
# Install Tailscale
# ============================================
install_tailscale() {
    echo -e "\n${BLUE}[10/12] Installing Tailscale...${NC}"

    if command -v tailscale &> /dev/null; then
        if tailscale status &> /dev/null 2>&1; then
            local ts_ip=$(tailscale ip -4 2>/dev/null || echo "UNKNOWN")
            echo -e "   ${GREEN}✅ Tailscale connected: $ts_ip${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Tailscale installed but not connected${NC}"
            echo -e "   ${BLUE}   Run: sudo tailscale up${NC}"
        fi
        return 0
    fi

    curl -fsSL https://tailscale.com/install.sh | sh
    echo -e "   ${GREEN}✅ Tailscale installed${NC}"
    echo -e "   ${YELLOW}⚠️  Run 'sudo tailscale up' to connect${NC}"
}

# ============================================
# Generate Secrets
# ============================================
generate_secrets() {
    echo -e "\n${BLUE}[11/12] Generating secrets...${NC}"

    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        echo -e "   ${GREEN}✅ .secrets already exists${NC}"
        return 0
    fi

    # Generate all secrets
    local postgres_pw=$(openssl rand -hex 32)
    local redis_pw=$(openssl rand -hex 32)
    local dify_secret=$(openssl rand -hex 32)
    local dify_init_pw=$(openssl rand -base64 12)
    local litellm_key="sk-$(openssl rand -hex 24)"
    local anythingllm_jwt=$(openssl rand -hex 32)
    local anythingllm_key="sk-$(openssl rand -hex 24)"
    local weaviate_key=$(openssl rand -hex 32)

    cat > "$SCRIPT_DIR/.secrets" <<SECRETS_EOF
# AI Platform Secrets
# Generated: $(date)
# DO NOT COMMIT THIS FILE

export POSTGRES_PASSWORD="$postgres_pw"
export REDIS_PASSWORD="$redis_pw"
export DIFY_SECRET_KEY="$dify_secret"
export DIFY_INIT_PASSWORD="$dify_init_pw"
export DIFY_WEAVIATE_API_KEY="$weaviate_key"
export LITELLM_MASTER_KEY="$litellm_key"
export ANYTHINGLLM_JWT_SECRET="$anythingllm_jwt"
export ANYTHINGLLM_API_KEY="$anythingllm_key"
export SIGNAL_NUMBER=""
SECRETS_EOF

    chmod 600 "$SCRIPT_DIR/.secrets"

    echo -e "   ${GREEN}✅ Secrets generated and saved${NC}"
}

# ============================================
# Create Environment File
# ============================================
create_env_file() {
    echo -e "\n${BLUE}[12/12] Creating environment file...${NC}"

    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "   ${GREEN}✅ .env already exists${NC}"
        return 0
    fi

    # Detect Tailscale IP
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "NOT_SET")
    local data_path="$HOME/ai-platform-data"

    cat > "$SCRIPT_DIR/.env" <<ENV_EOF
# ============================================
# AI Platform Environment Configuration
# Generated: $(date)
# ============================================

# System
PLATFORM_USER=$USER
PLATFORM_UID=$(id -u)
PLATFORM_GID=$(id -g)
TAILSCALE_IP=$ts_ip
DATA_PATH=$data_path

# Network
NETWORK_NAME=ai-platform-network

# Paths (relative to DATA_PATH)
OLLAMA_DATA=\${DATA_PATH}/ollama
LITELLM_DATA=\${DATA_PATH}/litellm
DIFY_DATA=\${DATA_PATH}/dify
ANYTHINGLLM_DATA=\${DATA_PATH}/anythingllm
SIGNAL_DATA=\${DATA_PATH}/signal
CLAWDBOT_DATA=\${DATA_PATH}/clawdbot

# Ollama
OLLAMA_MODELS=llama3.2:latest,mistral:latest
OLLAMA_HOST=0.0.0.0:11434

# LiteLLM
LITELLM_PORT=4000

# Dify
DIFY_POSTGRES_DB=dify
DIFY_POSTGRES_USER=dify
DIFY_API_PORT=5001
DIFY_WEB_PORT=3000

# AnythingLLM
ANYTHINGLLM_PORT=3001

# Signal
SIGNAL_API_PORT=8080
SIGNAL_NUMBER=

# ClawdBot
CLAWDBOT_PORT=18789
ANTHROPIC_API_KEY=

# External Services
OPENAI_API_KEY=
ENV_EOF

    chmod 644 "$SCRIPT_DIR/.env"

    echo -e "   ${GREEN}✅ .env created${NC}"
}

# ============================================
# Final Summary
# ============================================
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}System Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "✅ Ubuntu system updated"
    echo "✅ Docker installed and configured"
    echo "✅ NVIDIA toolkit installed (if GPU present)"
    echo "✅ Tailscale installed"
    echo "✅ Docker network created"
    echo "✅ Data directories created"
    echo "✅ Environment files generated"
    echo ""
    echo -e "${BLUE}Configuration Files:${NC}"
    echo "  • $SCRIPT_DIR/.env (main config)"
    echo "  • $SCRIPT_DIR/.secrets (generated secrets)"
    echo ""
    echo -e "${BLUE}Data Directory:${NC}"
    echo "  • $HOME/ai-platform-data/"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Review and edit .env if needed:"
    echo "     vim $SCRIPT_DIR/.env"
    echo ""
    echo "  2. If you were added to docker group, log out and back in:"
    echo "     logout (then reconnect)"
    echo ""
    echo "  3. Deploy services:"
    echo "     cd $SCRIPT_DIR/scripts"
    echo "     ./2-deploy-services.sh"
    echo ""
    echo -e "${YELLOW}⚠️  Important: If Tailscale not connected, run:${NC}"
    echo "     sudo tailscale up"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    preflight_checks
    verify_structure
    create_data_dirs
    update_system
    install_base_packages
    install_docker
    configure_docker
    install_nvidia_toolkit
    create_docker_network
    install_tailscale
    generate_secrets
    create_env_file
    print_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

chmod +x ~/ai-platform-installer/scripts/1-setup-system.sh
