#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - System Setup v5.2
# Path-agnostic: Works regardless of repo name
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory (works anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/setup-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - System Setup v5.2${NC}"
log "${BLUE}Repo: $(basename "$SCRIPT_DIR")${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}User: $(whoami) | Hostname: $(hostname)${NC}"
log "${BLUE}========================================${NC}"
echo ""

# ============================================
# [1/12] Pre-flight Checks
# ============================================
preflight_checks() {
    log "${BLUE}[1/12] Pre-flight checks...${NC}"
    
    # Check OS (warning only)
    if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
        log "   ${YELLOW}⚠️  Not Ubuntu 22.04, may have issues${NC}"
    else
        log "   ${GREEN}✓ Ubuntu 22.04 detected${NC}"
    fi
    
    # Check root disk (30GB minimum for system)
    local root_available=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $root_available -lt 30 ]]; then
        log "   ${RED}❌ Insufficient root disk: ${root_available}GB (need 30GB+)${NC}"
        exit 1
    else
        log "   ${GREEN}✓ Root disk: ${root_available}GB available${NC}"
    fi
    
    # Check data disk (if mounted)
    if mountpoint -q /mnt/data; then
        local data_available=$(df /mnt/data | awk 'NR==2 {print int($4/1024/1024)}')
        if [[ $data_available -lt 50 ]]; then
            log "   ${YELLOW}⚠️  Data disk: ${data_available}GB (recommend 100GB+)${NC}"
        else
            log "   ${GREEN}✓ Data disk: ${data_available}GB available${NC}"
        fi
    else
        log "   ${YELLOW}⚠️  /mnt/data not mounted yet (will mount EBS)${NC}"
    fi
    
    # Check RAM
    local ram_gb=$(free -g | awk 'NR==2 {print $2}')
    if [[ $ram_gb -lt 16 ]]; then
        log "   ${YELLOW}⚠️  RAM: ${ram_gb}GB (recommend 16GB+)${NC}"
    else
        log "   ${GREEN}✓ RAM: ${ram_gb}GB${NC}"
    fi
    
    # Check not root
    if [[ $EUID -eq 0 ]]; then
        log "   ${RED}❌ Don't run as root!${NC}"
        exit 1
    else
        log "   ${GREEN}✓ Running as: $(whoami)${NC}"
    fi
    
    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        log "   ${YELLOW}⚠️  Will prompt for sudo password${NC}"
    else
        log "   ${GREEN}✓ Sudo access verified${NC}"
    fi
    
    echo ""
}

# ============================================
# [2/12] Setup EBS Volume
# ============================================
setup_ebs_volume() {
    log "${BLUE}[2/12] Setting up EBS volume...${NC}"
    
    if mountpoint -q /mnt/data; then
        log "   ${GREEN}✓ /mnt/data already mounted${NC}"
        df -h /mnt/data | tail -1 | awk '{print "   Size: "$2", Available: "$4}'
        echo ""
        return 0
    fi
    
    # Detect EBS (NVMe or xvd)
    local ebs_device=""
    
    for dev in /dev/nvme*n1; do
        if [[ -b "$dev" ]] && [[ "$dev" != "/dev/nvme0n1" ]]; then
            local size_gb=$(lsblk -b "$dev" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024/1024)}')
            if [[ $size_gb -ge 50 ]]; then
                ebs_device="$dev"
                log "   ${GREEN}✓ Found: $dev (${size_gb}GB)${NC}"
                break
            fi
        fi
    done
    
    if [[ -z "$ebs_device" ]]; then
        for dev in /dev/xvd[b-z]; do
            if [[ -b "$dev" ]]; then
                local size_gb=$(lsblk -b "$dev" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024/1024)}')
                if [[ $size_gb -ge 50 ]]; then
                    ebs_device="$dev"
                    log "   ${GREEN}✓ Found: $dev (${size_gb}GB)${NC}"
                    break
                fi
            fi
        done
    fi
    
    if [[ -z "$ebs_device" ]]; then
        log "   ${RED}❌ No EBS volume (100GB+) found${NC}"
        exit 1
    fi
    
    # Format if needed
    if ! sudo blkid "$ebs_device" | grep -q "TYPE="; then
        log "   Formatting as ext4..."
        sudo mkfs.ext4 -F "$ebs_device" >> "$LOG_FILE" 2>&1
    fi
    
    # Mount
    sudo mkdir -p /mnt/data
    sudo mount "$ebs_device" /mnt/data
    
    # Add to fstab
    local uuid=$(sudo blkid -s UUID -o value "$ebs_device")
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid /mnt/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi
    
    sudo chown -R $(whoami):$(whoami) /mnt/data
    
    log "   ${GREEN}✓ Mounted and configured${NC}"
    echo ""
}

# ============================================
# [3/12] Update System
# ============================================
update_system() {
    log "${BLUE}[3/12] Updating system...${NC}"
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$LOG_FILE" 2>&1
    log "   ${GREEN}✓ Updated${NC}"
    echo ""
}

# ============================================
# [4/12] Install Dependencies
# ============================================
install_dependencies() {
    log "${BLUE}[4/12] Installing dependencies...${NC}"
    
    local packages=(
        curl wget git vim htop jq tree net-tools
        ca-certificates gnupg lsb-release software-properties-common
    )
    
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" >> "$LOG_FILE" 2>&1
    log "   ${GREEN}✓ Installed${NC}"
    echo ""
}

# ============================================
# [5/12] Install Docker
# ============================================
install_docker() {
    log "${BLUE}[5/12] Installing Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        log "   ${GREEN}✓ Already installed${NC}"
        echo ""
        return 0
    fi
    
    # Add GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
    
    # Add user to docker group
    sudo usermod -aG docker $(whoami)
    
    sudo systemctl enable docker >> "$LOG_FILE" 2>&1
    sudo systemctl start docker >> "$LOG_FILE" 2>&1
    
    log "   ${GREEN}✓ Installed${NC}"
    log "   ${YELLOW}⚠️  Logout/login to use docker${NC}"
    echo ""
}

# ============================================
# [6/12] Install NVIDIA (if GPU present)
# ============================================
install_nvidia() {
    log "${BLUE}[6/12] Checking for GPU...${NC}"
    
    if ! lspci | grep -i nvidia > /dev/null; then
        log "   ${YELLOW}⚠️  No NVIDIA GPU (CPU mode)${NC}"
        echo ""
        return 0
    fi
    
    log "   ${GREEN}✓ GPU detected${NC}"
    
    if command -v nvidia-smi &> /dev/null && nvidia-smi > /dev/null 2>&1; then
        log "   ${GREEN}✓ Drivers already installed${NC}"
        echo ""
        return 0
    fi
    
    log "   Installing drivers..."
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nvidia-driver-535 nvidia-utils-535 >> "$LOG_FILE" 2>&1
    
    log "   ${GREEN}✓ Installed (reboot needed)${NC}"
    echo ""
}

# ============================================
# [7/12] Install NVIDIA Docker
# ============================================
install_nvidia_docker() {
    log "${BLUE}[7/12] NVIDIA Container Toolkit...${NC}"
    
    if ! lspci | grep -i nvidia > /dev/null; then
        log "   ${YELLOW}⚠️  No GPU, skipping${NC}"
        echo ""
        return 0
    fi
    
    if command -v nvidia-ctk &> /dev/null; then
        log "   ${GREEN}✓ Already installed${NC}"
        echo ""
        return 0
    fi
    
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg >> "$LOG_FILE" 2>&1
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit >> "$LOG_FILE" 2>&1
    
    sudo nvidia-ctk runtime configure --runtime=docker >> "$LOG_FILE" 2>&1
    sudo systemctl restart docker >> "$LOG_FILE" 2>&1
    
    log "   ${GREEN}✓ Installed${NC}"
    echo ""
}

# ============================================
# [8/12] Verify Tailscale
# ============================================
verify_tailscale() {
    log "${BLUE}[8/12] Verifying Tailscale...${NC}"
    
    if ! command -v tailscale &> /dev/null; then
        log "   ${YELLOW}⚠️  Not installed${NC}"
        echo ""
        return 0
    fi
    
    if ! tailscale status &> /dev/null; then
        log "   ${YELLOW}⚠️  Not connected${NC}"
        echo ""
        return 0
    fi
    
    local ts_ip=$(tailscale ip -4 2>/dev/null)
    log "   ${GREEN}✓ Connected: $ts_ip${NC}"
    echo ""
}

# ============================================
# [9/12] Create Service Users
# ============================================
create_service_users() {
    log "${BLUE}[9/12] Creating service users...${NC}"
    
    local users=("ollama" "litellm" "signal" "dify" "anythingllm" "clawdbot")
    
    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            log "   ${GREEN}✓ Exists: $user${NC}"
        else
            sudo useradd -r -s /bin/false -d /mnt/data/$user "$user" >> "$LOG_FILE" 2>&1
            log "   ${GREEN}✓ Created: $user${NC}"
        fi
    done
    
    echo ""
}

# ============================================
# [10/12] Create Directories
# ============================================
create_directories() {
    log "${BLUE}[10/12] Creating directories...${NC}"
    
    local dirs=(
        "/mnt/data/ollama"
        "/mnt/data/litellm"
        "/mnt/data/signal"
        "/mnt/data/dify/db"
        "/mnt/data/dify/storage"
        "/mnt/data/dify/redis"
        "/mnt/data/anythingllm"
        "/mnt/data/clawdbot"
        "/mnt/data/gateway/certs"
        "$SCRIPT_DIR/stacks"
        "$SCRIPT_DIR/logs"
    )
    
    for dir in "${dirs[@]}"; do
        sudo mkdir -p "$dir"
    done
    
    # Set ownership
    sudo chown -R ollama:ollama /mnt/data/ollama
    sudo chown -R litellm:litellm /mnt/data/litellm
    sudo chown -R signal:signal /mnt/data/signal
    sudo chown -R dify:dify /mnt/data/dify
    sudo chown -R anythingllm:anythingllm /mnt/data/anythingllm
    sudo chown -R clawdbot:clawdbot /mnt/data/clawdbot
    sudo chown -R $(whoami):$(whoami) /mnt/data/gateway
    sudo chown -R $(whoami):$(whoami) "$SCRIPT_DIR/stacks"
    sudo chown -R $(whoami):$(whoami) "$SCRIPT_DIR/logs"
    
    log "   ${GREEN}✓ Created and configured${NC}"
    echo ""
}

# ============================================
# [11/12] Generate .env File
# ============================================
generate_env_file() {
    log "${BLUE}[11/12] Generating .env file...${NC}"
    
    local env_file="$SCRIPT_DIR/.env"
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "100.x.x.x")
    
    cat > "$env_file" <<ENV_EOF
# ============================================
# AI Platform - Environment Configuration
# Generated: $(date)
# Repo: $(basename "$SCRIPT_DIR")
# ============================================

# System
DOMAIN=ai-platform.local
TAILSCALE_IP=$ts_ip
PRIMARY_USER=$(whoami)
HOSTNAME=$(hostname)
REPO_PATH=$SCRIPT_DIR

# Storage
DATA_ROOT=/mnt/data
NETWORK_NAME=ai-platform-network

# Service Ports (internal)
OLLAMA_PORT=11434
LITELLM_PORT=4000
SIGNAL_PORT=8080
DIFY_API_PORT=5001
DIFY_WEB_PORT=4343
ANYTHINGLLM_PORT=3001
CLAWDBOT_PORT=18789
GATEWAY_PORT=8443

# AI Models
OLLAMA_MODELS=llama3.2:3b,qwen2.5:3b,nomic-embed-text
LITELLM_DEFAULT_MODEL=smart-router

# Database
POSTGRES_VERSION=15-alpine
POSTGRES_USER=dify
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d /=+)
POSTGRES_DB=dify

# Redis
REDIS_VERSION=7-alpine
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d /=+)

# Dify
DIFY_VERSION=0.11.0
DIFY_SECRET_KEY=$(openssl rand -base64 64 | tr -d /=+)

# AnythingLLM
ANYTHINGLLM_VERSION=latest

# Signal
SIGNAL_VERSION=latest

# ClawdBot
CLAWDBOT_VERSION=latest
ENV_EOF
    
    chmod 600 "$env_file"
    log "   ${GREEN}✓ Created: $env_file${NC}"
    echo ""
}

# ============================================
# [12/12] Summary
# ============================================
print_summary() {
    log "${BLUE}[12/12] Setup complete!${NC}"
    echo ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}✅ System Ready${NC}"
    log "${GREEN}========================================${NC}"
    echo ""
    
    log "Installation:"
    log "  ${GREEN}✓${NC} Docker"
    
    if lspci | grep -i nvidia > /dev/null; then
        log "  ${GREEN}✓${NC} NVIDIA GPU support"
    else
        log "  ${YELLOW}⚠${NC} CPU-only mode"
    fi
    
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        log "  ${GREEN}✓${NC} Tailscale: $(tailscale ip -4)"
    fi
    
    log "  ${GREEN}✓${NC} Data: /mnt/data ($(df -h /mnt/data | awk 'NR==2 {print $2}'))"
    log "  ${GREEN}✓${NC} Service users"
    log "  ${GREEN}✓${NC} Environment configured"
    
    echo ""
    log "${BLUE}Next steps:${NC}"
    log "  1. Logout: ${YELLOW}exit${NC}"
    log "  2. Reconnect: ${YELLOW}ssh $(whoami)@$(hostname)${NC}"
    log "  3. Go to: ${YELLOW}cd $SCRIPT_DIR/scripts${NC}"
    log "  4. Deploy: ${YELLOW}./2-deploy-services.sh${NC}"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    preflight_checks
    setup_ebs_volume
    update_system
    install_dependencies
    install_docker
    install_nvidia
    install_nvidia_docker
    verify_tailscale
    create_service_users
    create_directories
    generate_env_file
    print_summary
}

main "$@"

chmod +x scripts/1-setup-system.sh

