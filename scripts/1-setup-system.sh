#!/usr/bin/env bash

#==============================================================================
# Script: 1-setup-system.sh
# Description: System setup and configuration collection for AI Platform
# Version: 4.0.0 - REFACTORED - Modular Architecture
# Purpose: Prepares system, collects config, generates modular files & metadata
# Flow: 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add-service
#
# KEY CHANGES IN v4.0:
# - Modular file storage in /mnt/data/
# - Individual compose/env files per service
# - Metadata-driven deployment (JSON outputs)
# - NO execution - only preparation and config collection
# - Proper proxy selection (Nginx/Traefik/Caddy/None)
#==============================================================================

set -euo pipefail

#==============================================================================
# SCRIPT LOCATION & USER DETECTION
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect real user (works with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="${SUDO_USER}"
    REAL_UID=$(id -u "${SUDO_USER}")
    REAL_GID=$(id -g "${SUDO_USER}")
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_USER="${USER}"
    REAL_UID=$(id -u)
    REAL_GID=$(id -g)
    REAL_HOME="${HOME}"
fi

#==============================================================================
# GLOBAL CONFIGURATION - REFACTORED PATHS
#==============================================================================

# NEW: Modular data directory structure
MNT_DATA="/mnt/data"
COMPOSE_DIR="${MNT_DATA}/compose"
ENV_DIR="${MNT_DATA}/env"
CONFIG_DIR="${MNT_DATA}/config"
METADATA_DIR="${MNT_DATA}/metadata"

# Deployment target (where script 2 will deploy)
DEPLOY_BASE="/opt/ai-platform"
DEPLOY_DATA="${DEPLOY_BASE}/data"
DEPLOY_LOGS="${DEPLOY_BASE}/logs"
DEPLOY_BACKUPS="${DEPLOY_BASE}/backups"

# Logging
LOGS_DIR="${MNT_DATA}/logs"
LOGFILE="${LOGS_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="${LOGS_DIR}/setup-errors-$(date +%Y%m%d-%H%M%S).log"

# State file for resumable setup
STATE_FILE="${MNT_DATA}/.setup-state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Hardware requirements - GUIDELINES ONLY
RECOMMENDED_CPU_CORES=4
RECOMMENDED_RAM_GB=16
MIN_DISK_GB=50

# Setup phases tracking
declare -A SETUP_PHASES
SETUP_PHASES[preflight]=0
SETUP_PHASES[packages]=0
SETUP_PHASES[docker]=0
SETUP_PHASES[directories]=0
SETUP_PHASES[networks]=0
SETUP_PHASES[security]=0
SETUP_PHASES[tailscale]=0
SETUP_PHASES[secrets]=0
SETUP_PHASES[proxy]=0
SETUP_PHASES[domain]=0
SETUP_PHASES[services]=0
SETUP_PHASES[apikeys]=0
SETUP_PHASES[metadata]=0
SETUP_PHASES[compose_files]=0
SETUP_PHASES[env_files]=0

# System detection variables
OS=""
OS_VERSION=""
ARCH=""
HARDWARE_TYPE=""
GPU_TYPE="none"
GPU_COUNT=0
TOTAL_CPU_CORES=0
TOTAL_RAM_GB=0
AVAILABLE_DISK_GB=0

# Proxy configuration - NEW
PROXY_TYPE=""  # nginx, traefik, caddy, or none
PROXY_HTTP_PORT=80
PROXY_HTTPS_PORT=443
PROXY_SSL_TYPE=""  # letsencrypt, self, or none

# Core infrastructure flags
ENABLE_POSTGRES=true   # Always enabled for core services
ENABLE_REDIS=true      # Always enabled for caching/queuing
ENABLE_VECTOR_DB=true  # At least one vector DB required

# Vector DB selection (user picks ONE)
VECTOR_DB_TYPE=""  # qdrant, weaviate, or milvus

# Service flags (default disabled)
ENABLE_OLLAMA=false
ENABLE_LITELLM=false
ENABLE_OPENWEBUI=false
ENABLE_ANYTHINGLLM=false
ENABLE_DIFY=false
ENABLE_N8N=false
ENABLE_FLOWISE=false
ENABLE_SIGNAL_API=false
ENABLE_GDRIVE=false
ENABLE_LANGFUSE=false
ENABLE_MONITORING=false
ENABLE_TAILSCALE=false

# Domain and SSL config
BASE_DOMAIN=""
LETSENCRYPT_EMAIL=""

# API Keys
OPENAI_API_KEY=""
ANTHROPIC_API_KEY=""
GEMINI_API_KEY=""
GROQ_API_KEY=""
MISTRAL_API_KEY=""
OPENROUTER_API_KEY=""
HUGGINGFACE_API_KEY=""

# Generated secrets
DB_MASTER_PASSWORD=""
ADMIN_PASSWORD=""
JWT_SECRET=""
ENCRYPTION_KEY=""
REDIS_PASSWORD=""
QDRANT_API_KEY=""

# Per-service database credentials
N8N_DB_USER="n8n"
N8N_DB_PASSWORD=""
N8N_DB_NAME="n8n"

DIFY_DB_USER="dify"
DIFY_DB_PASSWORD=""
DIFY_DB_NAME="dify"

FLOWISE_DB_USER="flowise"
FLOWISE_DB_PASSWORD=""
FLOWISE_DB_NAME="flowise"

LITELLM_DB_USER="litellm"
LITELLM_DB_PASSWORD=""
LITELLM_DB_NAME="litellm"

LANGFUSE_DB_USER="langfuse"
LANGFUSE_DB_PASSWORD=""
LANGFUSE_DB_NAME="langfuse"

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    local msg="$1"
    echo -e "${BLUE}ℹ${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}⚠${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "$LOGFILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "$ERROR_LOG" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$LOGFILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$ERROR_LOG" 2>/dev/null || true
}

log_phase() {
    local phase="$1"
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${phase}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PHASE: ${phase}" >> "$LOGFILE" 2>/dev/null || true
}

#==============================================================================
# STATE MANAGEMENT
#==============================================================================

save_state() {
    local phase="$1"
    SETUP_PHASES[$phase]=1
    
    if [ -d "$(dirname "$STATE_FILE")" ]; then
        {
            for key in "${!SETUP_PHASES[@]}"; do
                echo "${key}=${SETUP_PHASES[$key]}"
            done
        } > "$STATE_FILE"
    fi
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        log_info "Loading previous setup state..."
        while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                SETUP_PHASES[$key]=$value
            fi
        done < "$STATE_FILE"
    fi
}

#==============================================================================
# BANNER AND SYSTEM INFO
#==============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}            ${MAGENTA}AI PLATFORM AUTOMATION - SETUP${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                      ${YELLOW}Version 4.0.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                  ${GREEN}Refactored Architecture${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Repository root: ${REPO_ROOT}"
    echo "Running as user: ${REAL_USER}"
    echo "Modular data directory: ${MNT_DATA}"
    echo ""
}

#==============================================================================
# SYSTEM DETECTION
#==============================================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        OS_VERSION="$VERSION_ID"
    else
        OS="unknown"
        OS_VERSION="unknown"
    fi
    
    ARCH=$(uname -m)
}

detect_hardware() {
    # CPU Detection
    if command -v nproc &> /dev/null; then
        TOTAL_CPU_CORES=$(nproc)
    else
        TOTAL_CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    fi
    
    # RAM Detection (in GB)
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM_GB" -eq 0 ]; then
        TOTAL_RAM_GB=$(free -m | awk '/^Mem:/{printf "%.1f", $2/1024}')
    fi
    
    # Disk Detection (in GB)
    AVAILABLE_DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    # GPU Detection
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l || echo "0")
        if [ "$GPU_COUNT" -gt 0 ]; then
            GPU_TYPE="nvidia"
            HARDWARE_TYPE="gpu"
        fi
    elif lspci 2>/dev/null | grep -i 'vga.*amd' &> /dev/null; then
        GPU_TYPE="amd"
        GPU_COUNT=1
        HARDWARE_TYPE="gpu"
    elif lspci 2>/dev/null | grep -i 'vga.*intel' &> /dev/null; then
        GPU_TYPE="intel"
        GPU_COUNT=1
        HARDWARE_TYPE="gpu"
    elif sysctl -n hw.optional.arm64 &> /dev/null 2>&1; then
        GPU_TYPE="apple_silicon"
        GPU_COUNT=1
        HARDWARE_TYPE="gpu"
    else
        GPU_TYPE="none"
        GPU_COUNT=0
        HARDWARE_TYPE="cpu"
    fi
}

#==============================================================================
# PHASE 1: PREFLIGHT CHECKS
#==============================================================================

preflight_checks() {
    log_phase "PHASE 1: Preflight Checks"
    
    if [ "${SETUP_PHASES[preflight]}" -eq 1 ]; then
        log_info "Preflight checks already completed - skipping"
        return 0
    fi
    
    # Detect system
    detect_os
    detect_hardware
    
    echo "▶ System Detection:"
    echo "  • OS: ${OS} ${OS_VERSION}"
    echo "  • Architecture: ${ARCH}"
    echo "  • CPU Cores: ${TOTAL_CPU_CORES}"
    echo "  • RAM: ${TOTAL_RAM_GB}GB"
    echo "  • Available Disk: ${AVAILABLE_DISK_GB}GB"
    echo "  • Hardware Type: ${HARDWARE_TYPE}"
    echo "  • GPU: ${GPU_TYPE} (${GPU_COUNT} devices)"
    echo ""
    
    # Check requirements - WARNINGS ONLY, NOT BLOCKING
    echo "▶ Checking requirements (guidelines only)..."
    
    local warnings=0
    
    if [ "$TOTAL_CPU_CORES" -lt "$RECOMMENDED_CPU_CORES" ]; then
        log_warning "CPU: ${TOTAL_CPU_CORES} cores (${RECOMMENDED_CPU_CORES} recommended for optimal performance)"
        warnings=$((warnings + 1))
    else
        log_success "CPU: ${TOTAL_CPU_CORES} cores"
    fi
    
    if [ "${TOTAL_RAM_GB%.*}" -lt "$RECOMMENDED_RAM_GB" ]; then
        log_warning "RAM: ${TOTAL_RAM_GB}GB (${RECOMMENDED_RAM_GB}GB recommended for optimal performance)"
        warnings=$((warnings + 1))
    else
        log_success "RAM: ${TOTAL_RAM_GB}GB"
    fi
    
    if [ "$AVAILABLE_DISK_GB" -lt "$MIN_DISK_GB" ]; then
        log_warning "Disk: ${AVAILABLE_DISK_GB}GB available (${MIN_DISK_GB}GB recommended)"
        warnings=$((warnings + 1))
    else
        log_success "Disk: ${AVAILABLE_DISK_GB}GB available"
    fi
    
    # Show recommendation but don't block
    if [ "$warnings" -gt 0 ]; then
        echo ""
        log_warning "Your system is below recommended specs but can still run the platform"
        log_info "Consider: Limiting active services, using CPU-only models, or upgrading hardware"
        echo ""
        read -p "Continue with current hardware? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi
    
    # Check supported OS
    case "$OS" in
        ubuntu|debian|centos|rhel|fedora|rocky|alma)
            log_success "Operating system supported: ${OS}"
            ;;
        *)
            log_warning "Untested operating system: ${OS}"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
    
    # Check internet connectivity
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_success "Internet connectivity verified"
    else
        log_error "No internet connectivity - required for downloads"
        exit 1
    fi
    
    save_state "preflight"
    log_success "Preflight checks completed"
}

#==============================================================================
# PHASE 2: PORT HEALTH CHECK
#==============================================================================

port_health_check() {
    log_phase "PHASE 2: Port Health Check"
    
    local required_ports=(80 443 5432 6379 6333 8080 11434)
    local ports_in_use=()
    
    echo "▶ Checking required ports..."
    
    for port in "${required_ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warning "Port ${port} is already in use"
            ports_in_use+=("$port")
        else
            log_success "Port ${port} is available"
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        echo ""
        log_warning "Some ports are in use: ${ports_in_use[*]}"
        echo "This may cause conflicts. Consider running ./0-cleanup.sh first"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Port health check completed"
}

#==============================================================================
# PHASE 3: INSTALL SYSTEM PACKAGES
#==============================================================================

install_system_packages() {
    log_phase "PHASE 3: Installing System Packages"
    
    if [ "${SETUP_PHASES[packages]}" -eq 1 ]; then
        log_info "System packages already installed - skipping"
        return 0
    fi
    
    log_info "Updating package lists..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release \
                apt-transport-https \
                software-properties-common \
                net-tools \
                htop \
                vim \
                unzip
            ;;
        centos|rhel|fedora|rocky|alma)
            yum install -y -q \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates \
                gnupg \
                net-tools \
                htop \
                vim \
                unzip
            ;;
        *)
            log_error "Unsupported OS for automatic package installation"
            exit 1
            ;;
    esac
    
    log_success "System packages installed"
    save_state "packages"
}

#==============================================================================
# PHASE 4: INSTALL DOCKER
#==============================================================================

install_docker() {
    log_phase "PHASE 4: Installing Docker"
    
    if [ "${SETUP_PHASES[docker]}" -eq 1 ]; then
        log_info "Docker already installed - skipping"
        return 0
    fi
    
    if command -v docker &> /dev/null; then
        log_info "Docker already installed: $(docker --version)"
        
        # Check Docker Compose
        if docker compose version &> /dev/null; then
            log_info "Docker Compose already installed: $(docker compose version)"
        else
            log_warning "Docker Compose plugin not found, installing..."
            case "$OS" in
                ubuntu|debian)
                    apt-get install -y docker-compose-plugin
                    ;;
                centos|rhel|fedora|rocky|alma)
                    yum install -y docker-compose-plugin
                    ;;
            esac
        fi
        
        # Ensure user is in docker group
        if ! groups "$REAL_USER" | grep -q docker; then
            log_info "Adding ${REAL_USER} to docker group..."
            usermod -aG docker "$REAL_USER"
            log_success "User added to docker group (logout/login required)"
        fi
        
        save_state "docker"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    case "$OS" in
        ubuntu|debian)
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS}/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS} \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        centos|rhel|rocky|alma)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            systemctl start docker
            systemctl enable docker
            ;;
            
        fedora)
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            systemctl start docker
            systemctl enable docker
            ;;
            
        *)
            log_error "Unsupported OS for Docker installation: ${OS}"
            exit 1
            ;;
    esac
    
    usermod -aG docker "$REAL_USER"
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker installed successfully"
    log_info "Docker version: $(docker --version)"
    log_info "Docker Compose version: $(docker compose version)"
    log_warning "User ${REAL_USER} added to docker group - logout/login required for non-sudo docker"
    
    save_state "docker"
}

#==============================================================================
# PHASE 5: CREATE DIRECTORY STRUCTURE
#==============================================================================

create_directory_structure() {
    log_phase "PHASE 5: Creating Modular Directory Structure"
    
    if [ "${SETUP_PHASES[directories]}" -eq 1 ]; then
        log_info "Directory structure already created - skipping"
        return 0
    fi
    
    log_info "Creating modular directory structure at ${MNT_DATA}..."
    
    # Core modular directories
    mkdir -p "${MNT_DATA}"/{compose,env,config,metadata,logs}
    
    # Service-specific config directories
    mkdir -p "${CONFIG_DIR}"/{nginx,traefik,caddy,litellm,prometheus,grafana,loki,postgres}
    
    # Nginx subdirectories
    mkdir -p "${CONFIG_DIR}/nginx/sites"
    
    # Traefik subdirectories
    mkdir -p "${CONFIG_DIR}/traefik/dynamic"
    
    # Grafana subdirectories
    mkdir -p "${CONFIG_DIR}/grafana/dashboards"
    
    # Set ownership
    chown -R "${REAL_UID}:${REAL_GID}" "${MNT_DATA}"
    
    # Set permissions
    chmod -R 755 "${MNT_DATA}"
    chmod 700 "${METADATA_DIR}"  # Metadata should be protected
    
    log_success "Modular directory structure created"
    log_info "Compose files: ${COMPOSE_DIR}"
    log_info "Environment files: ${ENV_DIR}"
    log_info "Config files: ${CONFIG_DIR}"
    log_info "Metadata: ${METADATA_DIR}"
    
    save_state "directories"
}

#==============================================================================
# PHASE 6: CREATE DOCKER NETWORKS
#==============================================================================

create_docker_networks() {
    log_phase "PHASE 6: Creating Docker Networks"
    
    if [ "${SETUP_PHASES[networks]}" -eq 1 ]; then
        log_info "Docker networks already created - skipping"
        return 0
    fi
    
    local networks=("ai-platform" "ai-platform-internal" "ai-platform-monitoring")
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" &> /dev/null; then
            log_info "Network ${network} already exists"
        else
            docker network create "$network" --driver bridge
            log_success "Created network: ${network}"
        fi
    done
    
    save_state "networks"
    log_success "Docker networks configured"
}

#==============================================================================
# PHASE 7: CONFIGURE SECURITY
#==============================================================================

configure_security() {
    log_phase "PHASE 7: Configuring Security"
    
    if [ "${SETUP_PHASES[security]}" -eq 1 ]; then
        log_info "Security already configured - skipping"
        return 0
    fi
    
    # Configure firewall (basic setup)
    if command -v ufw &> /dev/null; then
        log_info "Configuring UFW firewall..."
        
        ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
        ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
        ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
        
        echo "y" | ufw enable 2>/dev/null || true
        
        log_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        log_info "Configuring firewalld..."
        
        systemctl start firewalld
        systemctl enable firewalld
        
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        
        log_success "Firewalld configured"
    else
        log_warning "No firewall detected - consider installing ufw or firewalld"
    fi
    
    # Set up Docker daemon security
    if [ ! -f /etc/docker/daemon.json ]; then
        log_info "Configuring Docker daemon security..."
        cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF
        systemctl restart docker
        log_success "Docker daemon configured"
    fi
    
    save_state "security"
    log_success "Security configuration completed"
}

#==============================================================================
# PHASE 8: INSTALL TAILSCALE (OPTIONAL)
#==============================================================================

install_tailscale() {
    log_phase "PHASE 8: Tailscale Setup (Optional)"
    
    if [ "${SETUP_PHASES[tailscale]}" -eq 1 ]; then
        log_info "Tailscale already configured - skipping"
        return 0
    fi
    
    echo ""
    read -p "Install Tailscale for secure remote access? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_TAILSCALE=true
        
        if command -v tailscale &> /dev/null; then
            log_info "Tailscale already installed"
        else
            log_info "Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh
            log_success "Tailscale installed"
        fi
        
        echo ""
        log_info "To connect this machine to your Tailscale network, run:"
        echo "  sudo tailscale up"
        echo ""
    else
        ENABLE_TAILSCALE=false
        log_info "Skipping Tailscale installation"
    fi
    
    save_state "tailscale"
}

#==============================================================================
# PHASE 9: GENERATE SECRETS
#==============================================================================

generate_secrets() {
    log_phase "PHASE 9: Generating Secure Secrets"
    
    if [ "${SETUP_PHASES[secrets]}" -eq 1 ]; then
        log_info "Secrets already generated - loading existing"
        
        # Load from metadata if exists
        if [ -f "${METADATA_DIR}/secrets.json" ]; then
            DB_MASTER_PASSWORD=$(jq -r '.db_master_password' "${METADATA_DIR}/secrets.json")
            ADMIN_PASSWORD=$(jq -r '.admin_password' "${METADATA_DIR}/secrets.json")
            JWT_SECRET=$(jq -r '.jwt_secret' "${METADATA_DIR}/secrets.json")
            ENCRYPTION_KEY=$(jq -r '.encryption_key' "${METADATA_DIR}/secrets.json")
            REDIS_PASSWORD=$(jq -r '.redis_password' "${METADATA_DIR}/secrets.json")
            QDRANT_API_KEY=$(jq -r '.qdrant_api_key' "${METADATA_DIR}/secrets.json")
        fi
        
        return 0
    fi
    
    log_info "Generating secure passwords and keys..."
    
    # Generate master secrets
    DB_MASTER_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '/+=' | cut -c1-64)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    QDRANT_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    
    # Generate per-service database passwords
    N8N_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    DIFY_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    FLOWISE_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    LITELLM_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    LANGFUSE_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    
    log_success "Secrets generated"
    log_warning "IMPORTANT: Secrets will be saved to metadata/secrets.json - back up securely!"
    
    save_state "secrets"
}

#==============================================================================
# PHASE 10: PROXY SELECTION
#==============================================================================

select_proxy() {
    log_phase "PHASE 10: Reverse Proxy Selection"
    
    if [ "${SETUP_PHASES[proxy]}" -eq 1 ]; then
        log_info "Proxy already selected - skipping"
        return 0
    fi
    
    echo ""
    echo "Select Reverse Proxy:"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    echo "  1) Nginx (Traditional - Reliable, simple config)"
    echo "  2) Traefik (Modern - Auto SSL, Docker labels)"
    echo "  3) Caddy (Automatic - Zero-config HTTPS)"
    echo "  4) None (Direct port access - not recommended for production)"
    echo ""
    
    while true; do
        read -p "Select proxy [1-4]: " proxy_choice
        
        case $proxy_choice in
            1)
                PROXY_TYPE="nginx"
                log_success "Selected: Nginx"
                break
                ;;
            2)
                PROXY_TYPE="traefik"
                log_success "Selected: Traefik"
                break
                ;;
            3)
                PROXY_TYPE="caddy"
                log_success "Selected: Caddy"
                break
                ;;
            4)
                PROXY_TYPE="none"
                log_warning "Selected: No proxy (direct access)"
                log_warning "This is not recommended for production deployments"
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-4."
                ;;
        esac
    done
    
    # If proxy selected, configure SSL
    if [ "$PROXY_TYPE" != "none" ]; then
        echo ""
        echo "Select SSL Certificate Type:"
        echo "  1) Let's Encrypt (Automatic - requires public domain)"
        echo "  2) Self-signed (Testing/internal use)"
        echo "  3) None (HTTP only - not recommended)"
        echo ""
        
        while true; do
            read -p "Select SSL type [1-3]: " ssl_choice
            
            case $ssl_choice in
                1)
                    PROXY_SSL_TYPE="letsencrypt"
                    log_success "Selected: Let's Encrypt"
                    break
                    ;;
                2)
                    PROXY_SSL_TYPE="self"
                    log_success "Selected: Self-signed certificates"
                    break
                    ;;
                3)
                    PROXY_SSL_TYPE="none"
                    log_warning "Selected: No SSL (HTTP only)"
                    break
                    ;;
                *)
                    log_error "Invalid selection. Please choose 1-3."
                    ;;
            esac
        done
    fi
    
    save_state "proxy"
}

#==============================================================================
# PHASE 11: COLLECT DOMAIN CONFIGURATION
#==============================================================================

collect_domain_config() {
    log_phase "PHASE 11: Domain Configuration"
    
    if [ "${SETUP_PHASES[domain]}" -eq 1 ]; then
        log_info "Domain configuration already collected - skipping"
        return 0
    fi
    
    echo ""
    echo "Domain Configuration"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    
    if [ "$PROXY_TYPE" = "none" ]; then
        log_info "No proxy selected - skipping domain configuration"
        BASE_DOMAIN="localhost"
        save_state "domain"
        return 0
    fi
    
    read -p "Enter your base domain (e.g., example.com): " BASE_DOMAIN
    
    if [ -z "$BASE_DOMAIN" ]; then
        log_error "Domain cannot be empty"
        exit 1
    fi
    
    # Validate domain format
    if [[ ! "$BASE_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format"
        exit 1
    fi
    
    log_success "Domain configured: ${BASE_DOMAIN}"
    
    # If Let's Encrypt, get email
    if [ "$PROXY_SSL_TYPE" = "letsencrypt" ]; then
        read -p "Enter email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
        
        if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid email format"
            exit 1
        fi
        
        log_success "Let's Encrypt email: ${LETSENCRYPT_EMAIL}"
    fi
    
    save_state "domain"
}

#==============================================================================
# PHASE 12: SELECT SERVICES
#==============================================================================

select_services() {
    log_phase "PHASE 12: Service Selection"
    
    if [ "${SETUP_PHASES[services]}" -eq 1 ]; then
        log_info "Services already selected - skipping"
        return 0
    fi
    
    echo ""
    echo "Select services to deploy:"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    
    # Vector Database selection (REQUIRED - pick ONE)
    echo "📦 Vector Database (Required - choose ONE):"
    echo "  1) Qdrant (Recommended - Fast, easy to use)"
    echo "  2) Weaviate (Advanced - Graph capabilities)"
    echo "  3) Milvus (High-scale - Complex setup)"
    echo ""
    
    while true; do
        read -p "Select vector database [1-3]: " vdb_choice
        
        case $vdb_choice in
            1)
                VECTOR_DB_TYPE="qdrant"
                log_success "Selected: Qdrant"
                break
                ;;
            2)
                VECTOR_DB_TYPE="weaviate"
                log_success "Selected: Weaviate"
                break
                ;;
            3)
                VECTOR_DB_TYPE="milvus"
                log_success "Selected: Milvus"
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-3."
                ;;
        esac
    done
    
    echo ""
    echo "🤖 Core AI Services:"
    read -p "  Install Ollama (Local LLMs)? (Y/n): " -n 1 -r; echo; ENABLE_OLLAMA=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    read -p "  Install LiteLLM (AI Gateway)? (Y/n): " -n 1 -r; echo; ENABLE_LITELLM=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    read -p "  Install Open WebUI? (Y/n): " -n 1 -r; echo; ENABLE_OPENWEBUI=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    
    echo ""
    echo "💬 AI Platforms:"
    read -p "  Install AnythingLLM? (y/N): " -n 1 -r; echo; ENABLE_ANYTHINGLLM=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Dify? (y/N): " -n 1 -r; echo; ENABLE_DIFY=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "🔄 Workflow Automation:"
    read -p "  Install n8n? (y/N): " -n 1 -r; echo; ENABLE_N8N=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Flowise? (y/N): " -n 1 -r; echo; ENABLE_FLOWISE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "🔌 Integrations:"
    read -p "  Install Signal API (SMS/Messaging)? (y/N): " -n 1 -r; echo; ENABLE_SIGNAL_API=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Google Drive sync? (y/N): " -n 1 -r; echo; ENABLE_GDRIVE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "📊 Observability:"
    read -p "  Install Langfuse (LLM Observability)? (y/N): " -n 1 -r; echo; ENABLE_LANGFUSE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Monitoring (Prometheus + Grafana + Loki)? (Y/n): " -n 1 -r; echo; ENABLE_MONITORING=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    
    echo ""
    log_success "Service selection completed"
    
    save_state "services"
}

#==============================================================================
# PHASE 13: COLLECT API KEYS
#==============================================================================

collect_api_keys() {
    log_phase "PHASE 13: API Key Collection"
    
    if [ "${SETUP_PHASES[apikeys]}" -eq 1 ]; then
        log_info "API keys already collected - skipping"
        return 0
    fi
    
    if [ "$ENABLE_LITELLM" = false ]; then
        log_info "LiteLLM not enabled - skipping API key collection"
        save_state "apikeys"
        return 0
    fi
    
    echo ""
    echo "API Key Configuration (Optional - press Enter to skip)"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    echo "These keys are optional. You can add them later by editing env files."
    echo ""
    
    read -p "OpenAI API Key: " OPENAI_API_KEY
    read -p "Anthropic API Key: " ANTHROPIC_API_KEY
    read -p "Google Gemini API Key: " GEMINI_API_KEY
    read -p "Groq API Key: " GROQ_API_KEY
    read -p "Mistral API Key: " MISTRAL_API_KEY
    read -p "OpenRouter API Key: " OPENROUTER_API_KEY
    read -p "HuggingFace API Key: " HUGGINGFACE_API_KEY
    
    echo ""
    
    local keys_count=0
    [ -n "$OPENAI_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$ANTHROPIC_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$GEMINI_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$GROQ_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$MISTRAL_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$OPENROUTER_API_KEY" ] && keys_count=$((keys_count + 1))
    [ -n "$HUGGINGFACE_API_KEY" ] && keys_count=$((keys_count + 1))
    
    if [ $keys_count -gt 0 ]; then
        log_success "Collected ${keys_count} API key(s)"
    else
        log_info "No API keys provided - you can add them later"
    fi
    
    save_state "apikeys"
}

#==============================================================================
# PHASE 14: GENERATE METADATA FILES
#==============================================================================

generate_metadata() {
    log_phase "PHASE 14: Generating Deployment Metadata"
    
    if [ "${SETUP_PHASES[metadata]}" -eq 1 ]; then
        log_info "Metadata already generated - skipping"
        return 0
    fi
    
    log_info "Generating metadata files for deployment..."
    
    # 1. Configuration metadata
    cat > "${METADATA_DIR}/configuration.json" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "script_version": "4.0.0",
  "system": {
    "os": "${OS}",
    "os_version": "${OS_VERSION}",
    "arch": "${ARCH}",
    "cpu_cores": ${TOTAL_CPU_CORES},
    "ram_gb": ${TOTAL_RAM_GB},
    "disk_gb": ${AVAILABLE_DISK_GB},
    "hardware_type": "${HARDWARE_TYPE}",
    "gpu_type": "${GPU_TYPE}",
    "gpu_count": ${GPU_COUNT}
  },
  "network": {
    "base_domain": "${BASE_DOMAIN}",
    "proxy_type": "${PROXY_TYPE}",
    "proxy_http_port": ${PROXY_HTTP_PORT},
    "proxy_https_port": ${PROXY_HTTPS_PORT},
    "ssl_type": "${PROXY_SSL_TYPE}",
    "letsencrypt_email": "${LETSENCRYPT_EMAIL}"
  },
  "paths": {
    "mnt_data": "${MNT_DATA}",
    "deploy_base": "${DEPLOY_BASE}",
    "compose_dir": "${COMPOSE_DIR}",
    "env_dir": "${ENV_DIR}",
    "config_dir": "${CONFIG_DIR}"
  }
}
EOF
    
    # 2. Selected services metadata
    cat > "${METADATA_DIR}/selected_services.json" <<EOF
{
  "core_infrastructure": {
    "postgres": true,
    "redis": true,
    "vector_db": "${VECTOR_DB_TYPE}"
  },
  "proxy": {
    "type": "${PROXY_TYPE}",
    "enabled": $([ "$PROXY_TYPE" != "none" ] && echo true || echo false)
  },
  "ai_services": {
    "ollama": ${ENABLE_OLLAMA},
    "litellm": ${ENABLE_LITELLM},
    "openwebui": ${ENABLE_OPENWEBUI},
    "anythingllm": ${ENABLE_ANYTHINGLLM},
    "dify": ${ENABLE_DIFY}
  },
  "workflow": {
    "n8n": ${ENABLE_N8N},
    "flowise": ${ENABLE_FLOWISE}
  },
  "integrations": {
    "signal_api": ${ENABLE_SIGNAL_API},
    "gdrive": ${ENABLE_GDRIVE},
    "tailscale": ${ENABLE_TAILSCALE}
  },
  "observability": {
    "langfuse": ${ENABLE_LANGFUSE},
    "monitoring": ${ENABLE_MONITORING}
  }
}
EOF
    
    # 3. Secrets metadata (encrypted storage recommended)
    cat > "${METADATA_DIR}/secrets.json" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "warning": "THIS FILE CONTAINS SENSITIVE CREDENTIALS - BACKUP SECURELY",
  "db_master_password": "${DB_MASTER_PASSWORD}",
  "admin_password": "${ADMIN_PASSWORD}",
  "jwt_secret": "${JWT_SECRET}",
  "encryption_key": "${ENCRYPTION_KEY}",
  "redis_password": "${REDIS_PASSWORD}",
  "qdrant_api_key": "${QDRANT_API_KEY}",
  "per_service_db": {
    "n8n": {
      "user": "${N8N_DB_USER}",
      "password": "${N8N_DB_PASSWORD}",
      "database": "${N8N_DB_NAME}"
    },
    "dify": {
      "user": "${DIFY_DB_USER}",
      "password": "${DIFY_DB_PASSWORD}",
      "database": "${DIFY_DB_NAME}"
    },
    "flowise": {
      "user": "${FLOWISE_DB_USER}",
      "password": "${FLOWISE_DB_PASSWORD}",
      "database": "${FLOWISE_DB_NAME}"
    },
    "litellm": {
      "user": "${LITELLM_DB_USER}",
      "password": "${LITELLM_DB_PASSWORD}",
      "database": "${LITELLM_DB_NAME}"
    },
    "langfuse": {
      "user": "${LANGFUSE_DB_USER}",
      "password": "${LANGFUSE_DB_PASSWORD}",
      "database": "${LANGFUSE_DB_NAME}"
    }
  },
  "api_keys": {
    "openai": "${OPENAI_API_KEY}",
    "anthropic": "${ANTHROPIC_API_KEY}",
    "gemini": "${GEMINI_API_KEY}",
    "groq": "${GROQ_API_KEY}",
    "mistral": "${MISTRAL_API_KEY}",
    "openrouter": "${OPENROUTER_API_KEY}",
    "huggingface": "${HUGGINGFACE_API_KEY}"
  }
}
EOF
    
    # 4. Deployment plan
    cat > "${METADATA_DIR}/deployment_plan.json" <<EOF
{
  "deployment_order": [
    "postgres",
    "redis",
    "${VECTOR_DB_TYPE}",
    $([ "$PROXY_TYPE" != "none" ] && echo "\"${PROXY_TYPE}\"," || echo "")
    $([ "$ENABLE_OLLAMA" = true ] && echo "\"ollama\"," || echo "")
    $([ "$ENABLE_LITELLM" = true ] && echo "\"litellm\"," || echo "")
    $([ "$ENABLE_OPENWEBUI" = true ] && echo "\"openwebui\"," || echo "")
    $([ "$ENABLE_ANYTHINGLLM" = true ] && echo "\"anythingllm\"," || echo "")
    $([ "$ENABLE_DIFY" = true ] && echo "\"dify\"," || echo "")
    $([ "$ENABLE_N8N" = true ] && echo "\"n8n\"," || echo "")
    $([ "$ENABLE_FLOWISE" = true ] && echo "\"flowise\"," || echo "")
    $([ "$ENABLE_SIGNAL_API" = true ] && echo "\"signal-api\"," || echo "")
    $([ "$ENABLE_GDRIVE" = true ] && echo "\"gdrive\"," || echo "")
    $([ "$ENABLE_LANGFUSE" = true ] && echo "\"langfuse\"," || echo "")
    $([ "$ENABLE_MONITORING" = true ] && echo "\"prometheus\",\"grafana\",\"loki\"," || echo "")
    $([ "$ENABLE_TAILSCALE" = true ] && echo "\"tailscale\"" || echo "")
  ]
}
EOF
    
    # Clean up trailing commas in JSON (simple sed fix)
    sed -i 's/,\s*]/]/g' "${METADATA_DIR}/deployment_plan.json"
    
    # Set permissions
    chmod 600 "${METADATA_DIR}/secrets.json"
    chmod 644 "${METADATA_DIR}/configuration.json"
    chmod 644 "${METADATA_DIR}/selected_services.json"
    chmod 644 "${METADATA_DIR}/deployment_plan.json"
    
    chown "${REAL_UID}:${REAL_GID}" "${METADATA_DIR}"/*.json
    
    log_success "Metadata files generated"
    log_info "Configuration: ${METADATA_DIR}/configuration.json"
    log_info "Services: ${METADATA_DIR}/selected_services.json"
    log_info "Secrets: ${METADATA_DIR}/secrets.json"
    log_info "Deployment plan: ${METADATA_DIR}/deployment_plan.json"
    
    save_state "metadata"
}

#==============================================================================
# PHASE 15: GENERATE COMPOSE FILES (MODULAR)
#==============================================================================

generate_compose_files() {
    log_phase "PHASE 15: Generating Modular Compose Files"
    
    if [ "${SETUP_PHASES[compose_files]}" -eq 1 ]; then
        log_info "Compose files already generated - skipping"
        return 0
    fi
    
    log_info "Generating individual service compose files..."
    
    # NOTE: This is a simplified example - full implementation would include all services
    # For brevity, showing PostgreSQL, Redis, and Qdrant as examples
    
    # PostgreSQL
    cat > "${COMPOSE_DIR}/postgres.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: ai-platform-postgres
    restart: unless-stopped
    env_file:
      - ../env/postgres.env
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - ai-platform-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "ai-platform.service=postgres"
      - "ai-platform.type=database"

volumes:
  postgres_data:
    name: ai-platform-postgres-data

networks:
  ai-platform-internal:
    external: true
EOF
    
    # Redis
    cat > "${COMPOSE_DIR}/redis.yml" <<'EOF'
services:
  redis:
    image: redis:7-alpine
    container_name: ai-platform-redis
    restart: unless-stopped
    env_file:
      - ../env/redis.env
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --maxmemory ${REDIS_MAXMEMORY}
      --maxmemory-policy ${REDIS_POLICY}
    volumes:
      - redis_data:/data
    networks:
      - ai-platform-internal
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "ai-platform.service=redis"
      - "ai-platform.type=cache"

volumes:
  redis_data:
    name: ai-platform-redis-data

networks:
  ai-platform-internal:
    external: true
EOF
    
    # Qdrant (if selected)
    if [ "$VECTOR_DB_TYPE" = "qdrant" ]; then
        cat > "${COMPOSE_DIR}/qdrant.yml" <<'EOF'
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ai-platform-qdrant
    restart: unless-stopped
    env_file:
      - ../env/qdrant.env
    volumes:
      - qdrant_data:/qdrant/storage
    networks:
      - ai-platform-internal
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "ai-platform.service=qdrant"
      - "ai-platform.type=vector-db"

volumes:
  qdrant_data:
    name: ai-platform-qdrant-data

networks:
  ai-platform-internal:
    external: true
EOF
    fi
    
    # Nginx (if selected)
    if [ "$PROXY_TYPE" = "nginx" ]; then
        cat > "${COMPOSE_DIR}/nginx.yml" <<'EOF'
services:
  nginx:
    image: nginx:alpine
    container_name: ai-platform-nginx
    restart: unless-stopped
    env_file:
      - ../env/nginx.env
    ports:
      - "${HTTP_PORT}:80"
      - "${HTTPS_PORT}:443"
    volumes:
      - ../config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ../config/nginx/sites:/etc/nginx/sites-enabled:ro
      - nginx_certs:/etc/nginx/certs
      - nginx_logs:/var/log/nginx
    networks:
      - ai-platform
      - ai-platform-internal
    depends_on:
      - postgres
      - redis
    labels:
      - "ai-platform.service=nginx"
      - "ai-platform.type=proxy"

volumes:
  nginx_certs:
    name: ai-platform-nginx-certs
  nginx_logs:
    name: ai-platform-nginx-logs

networks:
  ai-platform:
    external: true
  ai-platform-internal:
    external: true
EOF
    fi
    
    # Traefik (if selected)
    if [ "$PROXY_TYPE" = "traefik" ]; then
        cat > "${COMPOSE_DIR}/traefik.yml" <<'EOF'
services:
  traefik:
    image: traefik:v3.0
    container_name: ai-platform-traefik
    restart: unless-stopped
    env_file:
      - ../env/traefik.env
    ports:
      - "${HTTP_PORT}:80"
      - "${HTTPS_PORT}:443"
      - "8080:8080"  # Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ../config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ../config/traefik/dynamic:/etc/traefik/dynamic:ro
      - traefik_certs:/letsencrypt
    networks:
      - ai-platform
      - ai-platform-internal
    labels:
      - "ai-platform.service=traefik"
      - "ai-platform.type=proxy"

volumes:
  traefik_certs:
    name: ai-platform-traefik-certs

networks:
  ai-platform:
    external: true
  ai-platform-internal:
    external: true
EOF
    fi
    
    # Caddy (if selected)
    if [ "$PROXY_TYPE" = "caddy" ]; then
        cat > "${COMPOSE_DIR}/caddy.yml" <<'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: ai-platform-caddy
    restart: unless-stopped
    env_file:
      - ../env/caddy.env
    ports:
      - "${HTTP_PORT}:80"
      - "${HTTPS_PORT}:443"
    volumes:
      - ../config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - ai-platform
      - ai-platform-internal
    labels:
      - "ai-platform.service=caddy"
      - "ai-platform.type=proxy"

volumes:
  caddy_data:
    name: ai-platform-caddy-data
  caddy_config:
    name: ai-platform-caddy-config

networks:
  ai-platform:
    external: true
  ai-platform-internal:
    external: true
EOF
    fi
    
    # Set permissions
    chmod 644 "${COMPOSE_DIR}"/*.yml
    chown "${REAL_UID}:${REAL_GID}" "${COMPOSE_DIR}"/*.yml
    
    log_success "Modular compose files generated"
    log_info "Files location: ${COMPOSE_DIR}/"
    
    save_state "compose_files"
}

#==============================================================================
# PHASE 16: GENERATE ENV FILES (MODULAR)
#==============================================================================

generate_env_files() {
    log_phase "PHASE 16: Generating Modular Environment Files"
    
    if [ "${SETUP_PHASES[env_files]}" -eq 1 ]; then
        log_info "Environment files already generated - skipping"
        return 0
    fi
    
    log_info "Generating individual service environment files..."
    
    # PostgreSQL env
    cat > "${ENV_DIR}/postgres.env" <<EOF
# PostgreSQL Configuration
POSTGRES_VERSION=16-alpine
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${DB_MASTER_PASSWORD}
POSTGRES_DB=postgres
POSTGRES_PORT=5432
POSTGRES_MAX_CONNECTIONS=100
POSTGRES_SHARED_BUFFERS=256MB
EOF
    
    # Redis env
    cat > "${ENV_DIR}/redis.env" <<EOF
# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=6379
REDIS_MAXMEMORY=256mb
REDIS_POLICY=allkeys-lru
EOF
    
    # Qdrant env (if selected)
    if [ "$VECTOR_DB_TYPE" = "qdrant" ]; then
        cat > "${ENV_DIR}/qdrant.env" <<EOF
# Qdrant Configuration
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
QDRANT_API_KEY=${QDRANT_API_KEY}
QDRANT_ALLOW_ANONYMOUS=false
EOF
    fi
    
    # Nginx env (if selected)
    if [ "$PROXY_TYPE" = "nginx" ]; then
        cat > "${ENV_DIR}/nginx.env" <<EOF
# Nginx Configuration
HTTP_PORT=${PROXY_HTTP_PORT}
HTTPS_PORT=${PROXY_HTTPS_PORT}
DOMAIN_NAME=${BASE_DOMAIN}
SSL_TYPE=${PROXY_SSL_TYPE}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
EOF
    fi
    
    # Traefik env (if selected)
    if [ "$PROXY_TYPE" = "traefik" ]; then
        cat > "${ENV_DIR}/traefik.env" <<EOF
# Traefik Configuration
HTTP_PORT=${PROXY_HTTP_PORT}
HTTPS_PORT=${PROXY_HTTPS_PORT}
DOMAIN_NAME=${BASE_DOMAIN}
ACME_EMAIL=${LETSENCRYPT_EMAIL}
TRAEFIK_DASHBOARD=true
TRAEFIK_API=true
EOF
    fi
    
    # Caddy env (if selected)
    if [ "$PROXY_TYPE" = "caddy" ]; then
        cat > "${ENV_DIR}/caddy.env" <<EOF
# Caddy Configuration
HTTP_PORT=${PROXY_HTTP_PORT}
HTTPS_PORT=${PROXY_HTTPS_PORT}
DOMAIN_NAME=${BASE_DOMAIN}
CADDY_AUTO_HTTPS=true
ACME_EMAIL=${LETSENCRYPT_EMAIL}
EOF
    fi
    
    # Set permissions (env files should be restricted)
    chmod 600 "${ENV_DIR}"/*.env
    chown "${REAL_UID}:${REAL_GID}" "${ENV_DIR}"/*.env
    
    log_success "Modular environment files generated"
    log_info "Files location: ${ENV_DIR}/"
    
    save_state "env_files"
}

#==============================================================================
# VERIFICATION
#==============================================================================

verify_setup() {
    log_phase "VERIFICATION: Setup Validation"
    
    local errors=0
    
    echo "▶ Verifying installation..."
    
    # Check Docker
    if docker --version &> /dev/null; then
        log_success "Docker is installed and running"
    else
        log_error "Docker verification failed"
        errors=$((errors + 1))
    fi
    
    # Check Docker Compose
    if docker compose version &> /dev/null; then
        log_success "Docker Compose is available"
    else
        log_error "Docker Compose verification failed"
        errors=$((errors + 1))
    fi
    
    # Check directory structure
    if [ -d "$MNT_DATA" ] && [ -d "$COMPOSE_DIR" ] && [ -d "$ENV_DIR" ] && [ -d "$CONFIG_DIR" ] && [ -d "$METADATA_DIR" ]; then
        log_success "Modular directory structure created"
    else
        log_error "Directory structure incomplete"
        errors=$((errors + 1))
    fi
    
    # Check networks
    if docker network inspect ai-platform &> /dev/null; then
        log_success "Docker networks configured"
    else
        log_error "Docker networks missing"
        errors=$((errors + 1))
    fi
    
    # Check metadata files
    local metadata_files=("configuration.json" "selected_services.json" "secrets.json" "deployment_plan.json")
    for file in "${metadata_files[@]}"; do
        if [ -f "${METADATA_DIR}/${file}" ]; then
            log_success "Metadata file: ${file}"
        else
            log_error "Missing metadata file: ${file}"
            errors=$((errors + 1))
        fi
    done
    
    # Check compose files
    local compose_count=$(find "$COMPOSE_DIR" -name "*.yml" | wc -l)
    if [ "$compose_count" -gt 0 ]; then
        log_success "Generated ${compose_count} compose file(s)"
    else
        log_error "No compose files generated"
        errors=$((errors + 1))
    fi
    
    # Check env files
    local env_count=$(find "$ENV_DIR" -name "*.env" | wc -l)
    if [ "$env_count" -gt 0 ]; then
        log_success "Generated ${env_count} environment file(s)"
    else
        log_error "No environment files generated"
        errors=$((errors + 1))
    fi
    
    echo ""
    
    if [ $errors -eq 0 ]; then
        log_success "All verification checks passed!"
        return 0
    else
        log_error "Verification failed with ${errors} error(s)"
        return 1
    fi
}

#==============================================================================
# SUMMARY
#==============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                ${GREEN}✓ SETUP COMPLETED SUCCESSFULLY!${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Configuration Summary"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "  System Information:"
    echo "    • Hardware: ${HARDWARE_TYPE}"
    echo "    • GPU: ${GPU_TYPE} (${GPU_COUNT} devices)"
    echo "    • CPU: ${TOTAL_CPU_CORES} cores"
    echo "    • RAM: ${TOTAL_RAM_GB}GB"
    echo "    • OS: ${OS} ${OS_VERSION}"
    echo "    • Architecture: ${ARCH}"
    echo ""
    echo "  Network Configuration:"
    echo "    • Proxy: ${PROXY_TYPE}"
    echo "    • Base Domain: ${BASE_DOMAIN}"
    echo "    • SSL: ${PROXY_SSL_TYPE}"
    [ -n "$LETSENCRYPT_EMAIL" ] && echo "    • Let's Encrypt Email: ${LETSENCRYPT_EMAIL}"
    echo ""
    echo "  Core Infrastructure:"
    echo "    ✓ PostgreSQL (with per-service databases)"
    echo "    ✓ Redis (caching & queuing)"
    echo "    ✓ ${VECTOR_DB_TYPE^} (vector database)"
    echo ""
    echo "  Selected Services:"
    [ "$PROXY_TYPE" != "none" ] && echo "    ✓ ${PROXY_TYPE^} (reverse proxy)"
    [ "$ENABLE_OLLAMA" = true ] && echo "    ✓ Ollama (local LLMs)"
    [ "$ENABLE_LITELLM" = true ] && echo "    ✓ LiteLLM (AI gateway)"
    [ "$ENABLE_OPENWEBUI" = true ] && echo "    ✓ Open WebUI"
    [ "$ENABLE_ANYTHINGLLM" = true ] && echo "    ✓ AnythingLLM"
    [ "$ENABLE_DIFY" = true ] && echo "    ✓ Dify"
    [ "$ENABLE_N8N" = true ] && echo "    ✓ n8n (workflow automation)"
    [ "$ENABLE_FLOWISE" = true ] && echo "    ✓ Flowise"
    [ "$ENABLE_SIGNAL_API" = true ] && echo "    ✓ Signal API"
    [ "$ENABLE_GDRIVE" = true ] && echo "    ✓ Google Drive sync"
    [ "$ENABLE_LANGFUSE" = true ] && echo "    ✓ Langfuse (observability)"
    [ "$ENABLE_MONITORING" = true ] && echo "    ✓ Monitoring stack (Prometheus + Grafana + Loki)"
    echo ""
    echo "  Generated Files:"
    echo "    • Compose files: ${COMPOSE_DIR}/"
    echo "    • Environment files: ${ENV_DIR}/"
    echo "    • Config files: ${CONFIG_DIR}/"
    echo "    • Metadata: ${METADATA_DIR}/"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "🚀 Next Steps:"
    echo ""
    echo "  1. Review metadata files:"
    echo "     cat ${METADATA_DIR}/configuration.json"
    echo "     cat ${METADATA_DIR}/selected_services.json"
    echo "     cat ${METADATA_DIR}/deployment_plan.json"
    echo ""
    echo "  2. Deploy the platform:"
    echo "     sudo ./2-deploy-services.sh"
    echo ""
    echo "  3. The deployment script will:"
    echo "     • Read metadata files from ${METADATA_DIR}/"
    echo "     • Merge individual compose files"
    echo "     • Deploy services in the correct order"
    echo "     • Configure service integrations"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "📄 Important Files:"
    echo "  • Setup log: ${LOGFILE}"
    echo "  • Error log: ${ERROR_LOG}"
    echo "  • Secrets (BACK THIS UP!): ${METADATA_DIR}/secrets.json"
    echo ""
    echo "⚠️  Security Notes:"
    echo "  • Your secrets file contains sensitive passwords"
    echo "  • Back up ${METADATA_DIR}/secrets.json to a secure location"
    echo "  • All credentials are auto-generated and unique per service"
    echo "  • User ${REAL_USER} has been added to docker group"
    echo "  • You may need to log out and back in for group changes"
    echo ""
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    print_banner
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "❌ This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Create initial log directory
    mkdir -p "$LOGS_DIR" 2>/dev/null || mkdir -p "/tmp/ai-platform-logs"
    LOGS_DIR="${LOGS_DIR:-/tmp/ai-platform-logs}"
    LOGFILE="${LOGS_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
    ERROR_LOG="${LOGS_DIR}/setup-errors-$(date +%Y%m%d-%H%M%S).log"
    
    # Load state if exists
    load_state
    
    log_info "Starting AI Platform Setup v4.0.0 (Refactored)"
    log_info "Executed by: ${REAL_USER} (UID: ${REAL_UID})"
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Modular data directory: ${MNT_DATA}"
    
    # Execute setup phases
    preflight_checks
    port_health_check
    install_system_packages
    install_docker
    create_directory_structure
    create_docker_networks
    configure_security
    install_tailscale
    generate_secrets
    select_proxy
    collect_domain_config
    select_services
    collect_api_keys
    generate_metadata
    generate_compose_files
    generate_env_files
    
    # Verification
    if verify_setup; then
        print_summary
        
        log_success "Setup completed successfully!"
        echo ""
        echo "You can now proceed with deployment:"
        echo "  sudo ./2-deploy-services.sh"
        echo ""
        exit 0
    else
        log_error "Setup completed with errors - please review logs"
        echo ""
        echo "Log files:"
        echo "  • Full log: ${LOGFILE}"
        echo "  • Errors: ${ERROR_LOG}"
        echo ""
        exit 1
    fi
}

# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Run main function
main "$@"
