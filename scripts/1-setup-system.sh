#!/usr/bin/env bash

#==============================================================================
# Script: 1-setup-system.sh
# Description: System setup and configuration collection for AI Platform
# Version: 3.1.0 - Production Ready - Handles All Hardware Scenarios
# Purpose: Prepares system, collects config, generates .env and compose skeleton
# Flow: 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add-service
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
# GLOBAL CONFIGURATION
#==============================================================================

# Directories
BASE_DIR="/opt/ai-platform"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOGS_DIR="${BASE_DIR}/logs"
BACKUP_DIR="${BASE_DIR}/backups"
SSL_DIR="${BASE_DIR}/ssl"
SCRIPTS_DIR="${BASE_DIR}/scripts"

# Configuration files
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
SECRETS_FILE="${BASE_DIR}/.secrets"
STATE_FILE="${BASE_DIR}/.setup-state"

# Logging
LOGFILE="${LOGS_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="${LOGS_DIR}/setup-errors-$(date +%Y%m%d-%H%M%S).log"

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
SETUP_PHASES[domain]=0
SETUP_PHASES[services]=0
SETUP_PHASES[apikeys]=0
SETUP_PHASES[env]=0
SETUP_PHASES[compose]=0
SETUP_PHASES[litellm]=0
SETUP_PHASES[postgres_init]=0

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

# Service flags (default disabled)
ENABLE_LITELLM=false
ENABLE_OLLAMA=false
ENABLE_OPENWEBUI=false
ENABLE_ANYTHINGLLM=false
ENABLE_DIFY=false
ENABLE_N8N=false
ENABLE_FLOWISE=false
ENABLE_AIRFLOW=false
ENABLE_WEAVIATE=false
ENABLE_QDRANT=false
ENABLE_MILVUS=false
ENABLE_JUPYTERHUB=false
ENABLE_MLFLOW=false
ENABLE_MONGODB=false
ENABLE_NEO4J=false
ENABLE_METABASE=false
ENABLE_MONITORING=false
ENABLE_TAILSCALE=false

# Domain and SSL config
BASE_DOMAIN=""
USE_LETSENCRYPT=false
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
DB_PASSWORD=""
ADMIN_PASSWORD=""
JWT_SECRET=""
ENCRYPTION_KEY=""
REDIS_PASSWORD=""

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
    echo -e "${CYAN}║${NC}                      ${YELLOW}Version 3.1.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Repository root: ${REPO_ROOT}"
    echo "Running as user: ${REAL_USER}"
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
    
    local required_ports=(80 443 5432 6379 8080 11434)
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
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS}/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            
            # Add Docker repository
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
    
    # Add user to docker group
    usermod -aG docker "$REAL_USER"
    
    # Start Docker
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
    log_phase "PHASE 5: Creating Directory Structure"
    
    if [ "${SETUP_PHASES[directories]}" -eq 1 ]; then
        log_info "Directory structure already created - skipping"
        return 0
    fi
    
    log_info "Creating directory structure at ${BASE_DIR}..."
    
    # Core directories
    mkdir -p "${BASE_DIR}"/{config,data,logs,backups,ssl,scripts}
    
    # Service-specific data directories
    mkdir -p "${DATA_DIR}"/{postgres,redis,ollama,mongodb,neo4j,weaviate,qdrant,milvus}
    
    # Config directories for services
    mkdir -p "${CONFIG_DIR}"/{litellm,n8n,flowise,airflow,grafana,prometheus,nginx}
    
    # Jupyter and MLflow directories
    mkdir -p "${DATA_DIR}"/{jupyterhub,mlflow}
    
    # Log directories for services
    mkdir -p "${LOGS_DIR}"/{nginx,postgres,airflow}
    
    # Set ownership
    chown -R "${REAL_UID}:${REAL_GID}" "${BASE_DIR}"
    
    # Set permissions
    chmod -R 755 "${BASE_DIR}"
    chmod 700 "${SSL_DIR}"
    
    log_success "Directory structure created"
    log_info "Base directory: ${BASE_DIR}"
    
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
        
        # Allow SSH
        ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
        
        # Allow HTTP/HTTPS
        ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
        ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
        
        # Enable firewall (if not already enabled)
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
    
    if [ "${SETUP_PHASES[secrets]}" -eq 1 ] && [ -f "$SECRETS_FILE" ]; then
        log_info "Secrets already generated - skipping"
        
        # Load existing secrets
        source "$SECRETS_FILE"
        return 0
    fi
    
    log_info "Generating secure passwords and keys..."
    
    # Generate secrets
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '/+=' | cut -c1-64)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    
    # Save secrets
    cat > "$SECRETS_FILE" <<EOF
# Generated secrets - DO NOT COMMIT TO VERSION CONTROL
# Generated: $(date)

DB_PASSWORD="${DB_PASSWORD}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
JWT_SECRET="${JWT_SECRET}"
ENCRYPTION_KEY="${ENCRYPTION_KEY}"
REDIS_PASSWORD="${REDIS_PASSWORD}"
EOF
    
    chmod 600 "$SECRETS_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$SECRETS_FILE"
    
    log_success "Secrets generated and saved to ${SECRETS_FILE}"
    log_warning "IMPORTANT: Back up this file securely!"
    
    save_state "secrets"
}

#==============================================================================
# PHASE 10: COLLECT DOMAIN CONFIGURATION
#==============================================================================

collect_domain_config() {
    log_phase "PHASE 10: Domain Configuration"
    
    if [ "${SETUP_PHASES[domain]}" -eq 1 ]; then
        log_info "Domain configuration already collected - skipping"
        return 0
    fi
    
    echo ""
    echo "Domain Configuration"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    
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
    
    # Ask about SSL
    echo ""
    read -p "Use Let's Encrypt for SSL certificates? (Y/n): " -n 1 -r
    echo
    USE_LETSENCRYPT=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    
    if [ "$USE_LETSENCRYPT" = true ]; then
        read -p "Enter email for Let's Encrypt: " LETSENCRYPT_EMAIL
        
        if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid email format"
            exit 1
        fi
        
        log_success "SSL configured with Let's Encrypt"
    else
        log_info "Self-signed certificates will be used"
    fi
    
    save_state "domain"
}

#==============================================================================
# PHASE 11: SELECT SERVICES
#==============================================================================

select_services() {
    log_phase "PHASE 11: Service Selection"
    
    if [ "${SETUP_PHASES[services]}" -eq 1 ]; then
        log_info "Services already selected - skipping"
        return 0
    fi
    
    echo ""
    echo "Select services to deploy:"
    echo "────────────────────────────────────────────────────────────"
    echo ""
    
    # Core AI Services
    echo "🤖 Core AI Services:"
    read -p "  Install LiteLLM (AI Gateway)? (Y/n): " -n 1 -r; echo; ENABLE_LITELLM=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    read -p "  Install Ollama (Local LLMs)? (Y/n): " -n 1 -r; echo; ENABLE_OLLAMA=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    read -p "  Install Open WebUI? (Y/n): " -n 1 -r; echo; ENABLE_OPENWEBUI=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    
    echo ""
    echo "💬 AI Platforms:"
    read -p "  Install AnythingLLM? (y/N): " -n 1 -r; echo; ENABLE_ANYTHINGLLM=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Dify? (y/N): " -n 1 -r; echo; ENABLE_DIFY=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "🔄 Workflow Automation:"
    read -p "  Install n8n? (y/N): " -n 1 -r; echo; ENABLE_N8N=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Flowise? (y/N): " -n 1 -r; echo; ENABLE_FLOWISE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Apache Airflow? (y/N): " -n 1 -r; echo; ENABLE_AIRFLOW=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "🗄️ Vector Databases:"
    read -p "  Install Weaviate? (y/N): " -n 1 -r; echo; ENABLE_WEAVIATE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Qdrant? (y/N): " -n 1 -r; echo; ENABLE_QDRANT=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Milvus? (y/N): " -n 1 -r; echo; ENABLE_MILVUS=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "🔬 ML/Data Science:"
    read -p "  Install JupyterHub? (y/N): " -n 1 -r; echo; ENABLE_JUPYTERHUB=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install MLflow? (y/N): " -n 1 -r; echo; ENABLE_MLFLOW=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "💾 Databases:"
    read -p "  Install MongoDB? (y/N): " -n 1 -r; echo; ENABLE_MONGODB=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Neo4j? (y/N): " -n 1 -r; echo; ENABLE_NEO4J=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    
    echo ""
    echo "📊 Analytics & Monitoring:"
    read -p "  Install Metabase? (y/N): " -n 1 -r; echo; ENABLE_METABASE=$([[ $REPLY =~ ^[Yy]$ ]] && echo true || echo false)
    read -p "  Install Monitoring (Prometheus + Grafana)? (Y/n): " -n 1 -r; echo; ENABLE_MONITORING=$([[ ! $REPLY =~ ^[Nn]$ ]] && echo true || echo false)
    
    echo ""
    log_success "Service selection completed"
    
    save_state "services"
}

#==============================================================================
# PHASE 12: COLLECT API KEYS
#==============================================================================

collect_api_keys() {
    log_phase "PHASE 12: API Key Collection"
    
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
    echo "These keys are optional. You can add them later in the .env file."
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
# PHASE 13: GENERATE .ENV FILE
#==============================================================================

generate_env_file() {
    log_phase "PHASE 13: Generating Environment Configuration"
    
    if [ "${SETUP_PHASES[env]}" -eq 1 ]; then
        log_info ".env file already generated - skipping"
        return 0
    fi
    
    log_info "Generating .env file..."
    
    cat > "$ENV_FILE" <<EOF
# AI Platform Environment Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

#==============================================================================
# SYSTEM CONFIGURATION
#==============================================================================

BASE_DIR=${BASE_DIR}
CONFIG_DIR=${CONFIG_DIR}
DATA_DIR=${DATA_DIR}
LOGS_DIR=${LOGS_DIR}
BACKUP_DIR=${BACKUP_DIR}

#==============================================================================
# HARDWARE DETECTION
#==============================================================================

HARDWARE_TYPE=${HARDWARE_TYPE}
GPU_TYPE=${GPU_TYPE}
GPU_COUNT=${GPU_COUNT}
TOTAL_CPU_CORES=${TOTAL_CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

#==============================================================================
# DOMAIN AND SSL
#==============================================================================

BASE_DOMAIN=${BASE_DOMAIN}
USE_LETSENCRYPT=${USE_LETSENCRYPT}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}

#==============================================================================
# SECURITY - AUTO-GENERATED SECRETS
#==============================================================================

DB_PASSWORD=${DB_PASSWORD}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
REDIS_PASSWORD=${REDIS_PASSWORD}

#==============================================================================
# DATABASE CONFIGURATION
#==============================================================================

POSTGRES_DB=aiplatform
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

EOF

    # Add MongoDB config if enabled
    if [ "$ENABLE_MONGODB" = true ]; then
        cat >> "$ENV_FILE" <<EOF

#==============================================================================
# MONGODB CONFIGURATION
#==============================================================================

MONGODB_HOST=mongodb
MONGODB_PORT=27017
MONGODB_USERNAME=aiplatform
MONGODB_PASSWORD=${DB_PASSWORD}
MONGODB_DATABASE=aiplatform

EOF
    fi

    # Add Neo4j config if enabled
    if [ "$ENABLE_NEO4J" = true ]; then
        cat >> "$ENV_FILE" <<EOF

#==============================================================================
# NEO4J CONFIGURATION
#==============================================================================

NEO4J_AUTH=neo4j/${DB_PASSWORD}
NEO4J_HOST=neo4j
NEO4J_BOLT_PORT=7687
NEO4J_HTTP_PORT=7474

EOF
    fi

    # Add API keys if LiteLLM is enabled
    if [ "$ENABLE_LITELLM" = true ]; then
        cat >> "$ENV_FILE" <<EOF

#==============================================================================
# AI PROVIDER API KEYS
#==============================================================================

OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GEMINI_API_KEY=${GEMINI_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}
MISTRAL_API_KEY=${MISTRAL_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
HUGGINGFACE_API_KEY=${HUGGINGFACE_API_KEY:-}

EOF
    fi

    # Add service-specific configs
    cat >> "$ENV_FILE" <<EOF

#==============================================================================
# SERVICE FLAGS
#==============================================================================

ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_AIRFLOW=${ENABLE_AIRFLOW}
ENABLE_WEAVIATE=${ENABLE_WEAVIATE}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_MILVUS=${ENABLE_MILVUS}
ENABLE_JUPYTERHUB=${ENABLE_JUPYTERHUB}
ENABLE_MLFLOW=${ENABLE_MLFLOW}
ENABLE_MONGODB=${ENABLE_MONGODB}
ENABLE_NEO4J=${ENABLE_NEO4J}
ENABLE_METABASE=${ENABLE_METABASE}
ENABLE_MONITORING=${ENABLE_MONITORING}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}

#==============================================================================
# LITELLM CONFIGURATION
#==============================================================================

LITELLM_MASTER_KEY=${JWT_SECRET}
LITELLM_SALT_KEY=${ENCRYPTION_KEY}
LITELLM_DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@\${POSTGRES_HOST}:\${POSTGRES_PORT}/\${POSTGRES_DB}

#==============================================================================
# OLLAMA CONFIGURATION
#==============================================================================

OLLAMA_HOST=0.0.0.0:11434
OLLAMA_ORIGINS=*
OLLAMA_MODELS=llama2,mistral,codellama

EOF

    # Add GPU-specific config
    if [ "$HARDWARE_TYPE" = "gpu" ]; then
        cat >> "$ENV_FILE" <<EOF

#==============================================================================
# GPU CONFIGURATION
#==============================================================================

OLLAMA_GPU=1
OLLAMA_NUM_GPU=1

EOF
    else
        cat >> "$ENV_FILE" <<EOF

#==============================================================================
# CPU-ONLY CONFIGURATION
#==============================================================================

OLLAMA_GPU=0
OLLAMA_NUM_PARALLEL=2
OLLAMA_NUM_THREAD=${TOTAL_CPU_CORES}

EOF
    fi

    # Set permissions
    chmod 600 "$ENV_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$ENV_FILE"
    
    log_success ".env file generated: ${ENV_FILE}"
    
    save_state "env"
}

#==============================================================================
# PHASE 14: GENERATE DOCKER COMPOSE SKELETON
#==============================================================================

generate_docker_compose() {
    log_phase "PHASE 14: Generating Docker Compose Configuration"
    
    if [ "${SETUP_PHASES[compose]}" -eq 1 ]; then
        log_info "Docker Compose file already generated - skipping"
        return 0
    fi
    
    log_info "Generating docker-compose.yml skeleton..."
    
    cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

# AI Platform - Main Docker Compose Configuration
# This is a skeleton file - services will be added by deployment scripts

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
  ai-platform-internal:
    name: ai-platform-internal
    driver: bridge
    internal: true
  ai-platform-monitoring:
    name: ai-platform-monitoring
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  ollama_data:

services:
  # Core services will be added here by 2-deploy-platform.sh
  # Service deployment is modular based on .env configuration
  
  placeholder:
    image: hello-world
    networks:
      - ai-platform
    restart: "no"

EOF

    chmod 644 "$COMPOSE_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$COMPOSE_FILE"
    
    log_success "Docker Compose skeleton created: ${COMPOSE_FILE}"
    log_info "Services will be added during deployment (2-deploy-platform.sh)"
    
    save_state "compose"
}

#==============================================================================
# PHASE 15: GENERATE LITELLM CONFIG
#==============================================================================

generate_litellm_config() {
    if [ "$ENABLE_LITELLM" = false ]; then
        log_info "LiteLLM not enabled - skipping config generation"
        return 0
    fi
    
    log_phase "PHASE 15: Generating LiteLLM Configuration"
    
    if [ "${SETUP_PHASES[litellm]}" -eq 1 ]; then
        log_info "LiteLLM config already generated - skipping"
        return 0
    fi
    
    mkdir -p "${CONFIG_DIR}/litellm"
    
    log_info "Generating LiteLLM config.yaml..."
    
    cat > "${CONFIG_DIR}/litellm/config.yaml" <<'EOF'
# LiteLLM Configuration
# Auto-generated by setup script

model_list:
  # Ollama models (local)
  - model_name: llama2
    litellm_params:
      model: ollama/llama2
      api_base: http://ollama:11434

  - model_name: mistral
    litellm_params:
      model: ollama/mistral
      api_base: http://ollama:11434

  - model_name: codellama
    litellm_params:
      model: ollama/codellama
      api_base: http://ollama:11434

EOF

    # Add API-based models if keys are provided
    if [ -n "$OPENAI_API_KEY" ]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF

  # OpenAI models
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_key: \${OPENAI_API_KEY}

  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: \${OPENAI_API_KEY}

EOF
    fi

    if [ -n "$ANTHROPIC_API_KEY" ]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF

  # Anthropic models
  - model_name: claude-3-opus
    litellm_params:
      model: claude-3-opus-20240229
      api_key: \${ANTHROPIC_API_KEY}

  - model_name: claude-3-sonnet
    litellm_params:
      model: claude-3-sonnet-20240229
      api_key: \${ANTHROPIC_API_KEY}

EOF
    fi

    cat >> "${CONFIG_DIR}/litellm/config.yaml" <<'EOF'

# General settings
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${LITELLM_DATABASE_URL}
  
litellm_settings:
  drop_params: true
  set_verbose: false
  
EOF

    chown -R "${REAL_UID}:${REAL_GID}" "${CONFIG_DIR}/litellm"
    
    log_success "LiteLLM configuration generated"
    
    save_state "litellm"
}

#==============================================================================
# PHASE 16: GENERATE POSTGRES INIT SCRIPT
#==============================================================================

generate_postgres_init() {
    log_phase "PHASE 16: Generating Database Initialization"
    
    if [ "${SETUP_PHASES[postgres_init]}" -eq 1 ]; then
        log_info "Postgres init already generated - skipping"
        return 0
    fi
    
    mkdir -p "${CONFIG_DIR}/postgres"
    
    cat > "${CONFIG_DIR}/postgres/init.sql" <<EOF
-- AI Platform Database Initialization
-- Generated: $(date)

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS aiplatform;
CREATE SCHEMA IF NOT EXISTS monitoring;

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA aiplatform TO aiplatform;
GRANT ALL PRIVILEGES ON SCHEMA monitoring TO aiplatform;

-- Create basic tables for LiteLLM (if enabled)
EOF

    if [ "$ENABLE_LITELLM" = true ]; then
        cat >> "${CONFIG_DIR}/postgres/init.sql" <<'EOF'

CREATE TABLE IF NOT EXISTS aiplatform.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key_hash TEXT NOT NULL UNIQUE,
    key_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS aiplatform.usage_logs (
    id SERIAL PRIMARY KEY,
    api_key_id UUID REFERENCES aiplatform.api_keys(id),
    model TEXT NOT NULL,
    tokens_used INTEGER,
    cost DECIMAL(10, 6),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_usage_logs_created_at ON aiplatform.usage_logs(created_at);
CREATE INDEX idx_usage_logs_api_key_id ON aiplatform.usage_logs(api_key_id);

EOF
    fi

    chown -R "${REAL_UID}:${REAL_GID}" "${CONFIG_DIR}/postgres"
    
    log_success "Database initialization script generated"
    
    save_state "postgres_init"
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
    if [ -d "$BASE_DIR" ] && [ -d "$CONFIG_DIR" ] && [ -d "$DATA_DIR" ]; then
        log_success "Directory structure created"
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
    
    # Check configuration files
    if [ -f "$ENV_FILE" ]; then
        log_success ".env file generated"
    else
        log_error ".env file missing"
        errors=$((errors + 1))
    fi
    
    if [ -f "$COMPOSE_FILE" ]; then
        log_success "docker-compose.yml generated"
    else
        log_error "docker-compose.yml missing"
        errors=$((errors + 1))
    fi
    
    if [ -f "$SECRETS_FILE" ]; then
        log_success "Secrets file generated"
    else
        log_error "Secrets file missing"
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
    echo "  Configuration:"
    echo "    • Base Domain: ${BASE_DOMAIN}"
    echo "    • SSL: $([ "$USE_LETSENCRYPT" = true ] && echo "Let's Encrypt" || echo "Self-signed")"
    echo "    • Base Directory: ${BASE_DIR}"
    echo ""
    echo "  Selected Services:"
    [ "$ENABLE_LITELLM" = true ] && echo "    ✓ LiteLLM (AI Gateway)"
    [ "$ENABLE_OLLAMA" = true ] && echo "    ✓ Ollama (Local LLMs)"
    [ "$ENABLE_OPENWEBUI" = true ] && echo "    ✓ Open WebUI"
    [ "$ENABLE_ANYTHINGLLM" = true ] && echo "    ✓ AnythingLLM"
    [ "$ENABLE_DIFY" = true ] && echo "    ✓ Dify"
    [ "$ENABLE_N8N" = true ] && echo "    ✓ n8n"
    [ "$ENABLE_FLOWISE" = true ] && echo "    ✓ Flowise"
    [ "$ENABLE_AIRFLOW" = true ] && echo "    ✓ Apache Airflow"
    [ "$ENABLE_WEAVIATE" = true ] && echo "    ✓ Weaviate"
    [ "$ENABLE_QDRANT" = true ] && echo "    ✓ Qdrant"
    [ "$ENABLE_MILVUS" = true ] && echo "    ✓ Milvus"
    [ "$ENABLE_JUPYTERHUB" = true ] && echo "    ✓ JupyterHub"
    [ "$ENABLE_MLFLOW" = true ] && echo "    ✓ MLflow"
    [ "$ENABLE_MONGODB" = true ] && echo "    ✓ MongoDB"
    [ "$ENABLE_NEO4J" = true ] && echo "    ✓ Neo4j"
    [ "$ENABLE_METABASE" = true ] && echo "    ✓ Metabase"
    [ "$ENABLE_MONITORING" = true ] && echo "    ✓ Prometheus + Grafana"
    echo ""
    echo "  Generated Files:"
    echo "    • .env file: ${ENV_FILE}"
    echo "    • Docker Compose: ${COMPOSE_FILE}"
    echo "    • Secrets: ${SECRETS_FILE}"
    [ "$ENABLE_LITELLM" = true ] && echo "    • LiteLLM Config: ${CONFIG_DIR}/litellm/config.yaml"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "🚀 Next Steps:"
    echo ""
    echo "  1. Review configuration:"
    echo "     cat ${ENV_FILE}"
    echo ""
    echo "  2. Deploy the platform:"
    echo "     sudo ./2-deploy-platform.sh"
    echo ""
    echo "  3. Configure services:"
    echo "     sudo ./3-configure-services.sh"
    echo ""
    echo "  4. Add more services (optional):"
    echo "     sudo ./4-add-service.sh"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "📄 Important Files:"
    echo "  • Setup log: ${LOGFILE}"
    echo "  • Error log: ${ERROR_LOG}"
    echo "  • Secrets (BACK THIS UP!): ${SECRETS_FILE}"
    echo ""
    echo "⚠️  Security Notes:"
    echo "  • Your secrets file contains sensitive passwords"
    echo "  • Back up ${SECRETS_FILE} to a secure location"
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
    
    log_info "Starting AI Platform Setup v3.1.0"
    log_info "Executed by: ${REAL_USER} (UID: ${REAL_UID})"
    log_info "Script directory: ${SCRIPT_DIR}"
    
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
    collect_domain_config
    select_services
    collect_api_keys
    generate_env_file
    generate_docker_compose
    generate_litellm_config
    generate_postgres_init
    
    # Verification
    if verify_setup; then
        print_summary
        
        log_success "Setup completed successfully!"
        echo ""
        echo "You can now proceed with deployment:"
        echo "  sudo ./2-deploy-platform.sh"
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
