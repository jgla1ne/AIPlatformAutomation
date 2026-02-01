#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - System Setup v5.5
# FIXED: Proper Docker group handling
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/logs/setup-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# ============================================
# Banner
# ============================================
echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - System Setup v5.5${NC}"
log "${BLUE}Location: $SCRIPT_DIR${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}========================================${NC}"
echo ""

# ============================================
# [1/11] Detect GPU
# ============================================
log "${BLUE}[1/11] Detecting GPU...${NC}"

if lspci | grep -i nvidia > /dev/null 2>&1; then
    HAS_GPU=true
    GPU_MODEL=$(lspci | grep -i nvidia | head -1 | cut -d: -f3 | xargs)
    log "   ${GREEN}✓ NVIDIA GPU detected: $GPU_MODEL${NC}"
else
    HAS_GPU=false
    log "   ${YELLOW}⚠ No NVIDIA GPU detected - CPU-only mode${NC}"
fi
echo ""

# ============================================
# [2/11] System Updates
# ============================================
log "${BLUE}[2/11] Updating system packages...${NC}"
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
log "   ${GREEN}✓ System updated${NC}"
echo ""

# ============================================
# [3/11] Install Prerequisites
# ============================================
log "${BLUE}[3/11] Installing prerequisites...${NC}"

PACKAGES=(
    "curl"
    "wget"
    "git"
    "jq"
    "ca-certificates"
    "gnupg"
    "lsb-release"
    "build-essential"
    "python3"
    "python3-pip"
)

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        sudo apt-get install -y -qq "$pkg"
        log "   ${GREEN}✓ Installed: $pkg${NC}"
    else
        log "   ${YELLOW}Already installed: $pkg${NC}"
    fi
done
echo ""

# ============================================
# [4/11] Install Docker
# ============================================
log "${BLUE}[4/11] Installing Docker...${NC}"

if command -v docker &>/dev/null; then
    log "   ${YELLOW}Docker already installed${NC}"
else
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "   ${GREEN}✓ Docker installed${NC}"
fi

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker
log "   ${GREEN}✓ Docker service started${NC}"

# ⭐ ENSURE DOCKER GROUP EXISTS (critical fix!)
if ! getent group docker > /dev/null; then
    sudo groupadd docker
    log "   ${GREEN}✓ Docker group created${NC}"
fi

# Add user to docker group
if ! groups $USER | grep -q docker; then
    sudo usermod -aG docker $USER
    log "   ${GREEN}✓ User added to docker group${NC}"
    log "   ${YELLOW}⚠️  You MUST logout and reconnect for this to take effect${NC}"
else
    log "   ${YELLOW}User already in docker group${NC}"
fi
echo ""

# ============================================
# [5/11] Install NVIDIA Container Toolkit (if GPU)
# ============================================
if [[ "$HAS_GPU" == "true" ]]; then
    log "${BLUE}[5/11] Installing NVIDIA Container Toolkit...${NC}"
    
    if ! command -v nvidia-ctk &>/dev/null; then
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        sudo apt-get update -qq
        sudo apt-get install -y -qq nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        
        log "   ${GREEN}✓ NVIDIA Container Toolkit installed${NC}"
    else
        log "   ${YELLOW}NVIDIA Container Toolkit already installed${NC}"
    fi
else
    log "${BLUE}[5/11] Skipping NVIDIA Container Toolkit (no GPU)${NC}"
fi
echo ""

# ============================================
# [6/11] Install Tailscale
# ============================================
log "${BLUE}[6/11] Installing Tailscale...${NC}"

if command -v tailscale &>/dev/null; then
    log "   ${YELLOW}Tailscale already installed${NC}"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    log "   ${GREEN}✓ Tailscale installed${NC}"
fi

# Get Tailscale IP
if sudo tailscale status &>/dev/null; then
    TAILSCALE_IP=$(sudo tailscale ip -4)
    log "   ${GREEN}✓ Tailscale running: $TAILSCALE_IP${NC}"
else
    log "   ${YELLOW}⚠️  Tailscale not connected - run: sudo tailscale up${NC}"
    TAILSCALE_IP="not-configured"
fi
echo ""

# ============================================
# [7/11] Create Data Directories
# ============================================
log "${BLUE}[7/11] Creating data directories...${NC}"

DATA_DIR="$SCRIPT_DIR/data"
mkdir -p "$DATA_DIR"/{litellm,dify,postgres,redis,weaviate,sandbox,ssrf_proxy,nginx}

# Set ownership
sudo chown -R $USER:$USER "$DATA_DIR"
chmod -R 755 "$DATA_DIR"

log "   ${GREEN}✓ Data directories created at: $DATA_DIR${NC}"
echo ""

# ============================================
# [8/11] Install NVIDIA Drivers (if GPU and not installed)
# ============================================
if [[ "$HAS_GPU" == "true" ]]; then
    log "${BLUE}[8/11] Checking NVIDIA drivers...${NC}"
    
    if ! command -v nvidia-smi &>/dev/null; then
        log "   ${YELLOW}Installing NVIDIA drivers (this may take 5-10 minutes)...${NC}"
        sudo apt-get install -y -qq ubuntu-drivers-common
        sudo ubuntu-drivers autoinstall
        log "   ${GREEN}✓ NVIDIA drivers installed${NC}"
        log "   ${RED}⚠️  REBOOT REQUIRED after script completes${NC}"
    else
        log "   ${GREEN}✓ NVIDIA drivers already installed${NC}"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | while read line; do
            log "      $line"
        done
    fi
else
    log "${BLUE}[8/11] Skipping NVIDIA drivers (no GPU)${NC}"
fi
echo ""

# ============================================
# [9/11] Install Ollama
# ============================================
log "${BLUE}[9/11] Installing Ollama...${NC}"

if command -v ollama &>/dev/null; then
    log "   ${YELLOW}Ollama already installed${NC}"
else
    curl -fsSL https://ollama.com/install.sh | sh
    log "   ${GREEN}✓ Ollama installed${NC}"
fi

# Configure Ollama service
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat | sudo tee /etc/systemd/system/ollama.service.d/environment.conf > /dev/null <<OLLAMA_ENV
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
OLLAMA_ENV

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

log "   ${GREEN}✓ Ollama service configured${NC}"
echo ""

# ============================================
# [10/11] Generate Secure Keys
# ============================================
log "${BLUE}[10/11] Generating secure credentials...${NC}"

LITELLM_MASTER_KEY="sk-$(openssl rand -hex 24)"
DIFY_DB_USER="dify_$(openssl rand -hex 4)"
DIFY_DB_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=')"
POSTGRES_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=')"
DIFY_SECRET_KEY="$(openssl rand -base64 48 | tr -d '/+=')"

log "   ${GREEN}✓ Credentials generated${NC}"
echo ""

# ============================================
# [11/11] Create Environment File
# ============================================
log "${BLUE}[11/11] Creating environment file...${NC}"

cat > "$ENV_FILE" <<ENV
# AI Platform Configuration
# Generated: $(date)

# System
HAS_GPU=$HAS_GPU
DATA_DIR=$DATA_DIR
TAILSCALE_IP=$TAILSCALE_IP

# LiteLLM
LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY

# Dify
DIFY_DB_USER=$DIFY_DB_USER
DIFY_DB_PASSWORD=$DIFY_DB_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DIFY_SECRET_KEY=$DIFY_SECRET_KEY

# Paths
SCRIPT_DIR=$SCRIPT_DIR
ENV

chmod 600 "$ENV_FILE"
log "   ${GREEN}✓ Environment file created: $ENV_FILE${NC}"
echo ""

# ============================================
# Summary
# ============================================
log "${GREEN}========================================${NC}"
log "${GREEN}✅ System Setup Complete!${NC}"
log "${GREEN}========================================${NC}"
echo ""

log "${BLUE}Configuration:${NC}"
log "  GPU Mode:       $(if [[ "$HAS_GPU" == "true" ]]; then echo "${GREEN}Enabled${NC}"; else echo "${YELLOW}CPU-only${NC}"; fi)"
log "  Data Directory: $DATA_DIR"
log "  Tailscale IP:   $TAILSCALE_IP"
echo ""

log "${YELLOW}⚠️  IMPORTANT - YOU MUST:${NC}"
log "  1. ${RED}LOGOUT${NC} completely (type 'logout' or close SSH)"
log "  2. ${RED}RECONNECT${NC} via SSH"
log "  3. Then run: ${YELLOW}cd $SCRIPT_DIR/scripts && ./2-deploy-services.sh${NC}"
echo ""

if [[ "$HAS_GPU" == "true" ]] && ! command -v nvidia-smi &>/dev/null; then
    log "${YELLOW}⚠️  GPU drivers installed - reboot required:${NC}"
    log "   ${YELLOW}sudo reboot${NC}"
    echo ""
fi

log "${BLUE}Log file: $LOG_FILE${NC}"
echo ""

