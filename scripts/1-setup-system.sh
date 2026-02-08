#!/bin/bash
################################################################################
# SCRIPT 1: SYSTEM SETUP & CONFIGURATION
# Version: v102.0.0
# Purpose: Comprehensive AI Platform system detection and configuration
# 
# This script performs:
# - System detection (OS, hardware, GPU)
# - Dependency installation (curl, jq, docker, etc.)
# - Service selection with user input
# - Model selection and API key collection
# - Configuration file generation
# - Infrastructure setup
#
# Prerequisites: git (must be installed before running)
#
# Reference: AI PLATFORM DEPLOYMENT v75.2.0
################################################################################

set -euo pipefail

################################################################################
# SCRIPT METADATA
################################################################################

readonly SCRIPT_VERSION="v102.0.0"
readonly SCRIPT_NAME="AI Platform System Setup"
readonly TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
readonly LOG_FILE="/var/log/ai-platform-setup-${TIMESTAMP}.log"
readonly TOTAL_STEPS=26

################################################################################
# COLOR CODES & FORMATTING
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

################################################################################
# GLOBAL VARIABLES
################################################################################

# System Detection
OS_NAME=""
OS_VERSION=""
PACKAGE_MANAGER=""
CPU_CORES=0
TOTAL_RAM_GB=0
HAS_GPU=false
GPU_TYPE=""
TIMEZONE=""
HOSTNAME=""

# Installation Paths
BASE_DIR="/opt/ai-platform"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
BACKUP_DIR="${BASE_DIR}/backups"
SCRIPTS_DIR="${BASE_DIR}/scripts"

# Service Configuration
declare -A SELECTED_SERVICES
declare -A SERVICE_PORTS
declare -A OLLAMA_MODELS
declare -A API_KEYS
declare -A GENERATED_SECRETS

# Network Configuration
DOMAIN_NAME=""
TAILNET_NAME=""
USE_CADDY=false
USE_NGINX=false

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_info() {
    local message="$1"
    echo -e "${BLUE}ℹ${NC} ${message}" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} ${message}" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠${NC} ${message}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}✗${NC} ${message}" | tee -a "$LOG_FILE"
}

log_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  STEP ${step}/${total}: ${message}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_header() {
    local message="$1"
    echo ""
    echo -e "${MAGENTA}${BOLD}${message}${NC}"
    echo -e "${MAGENTA}$(printf '═%.0s' {1..70})${NC}"
    echo ""
}

################################################################################
# BANNER
################################################################################

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                               ║${NC}"
    echo -e "${CYAN}║            ${BOLD}AI PLATFORM AUTOMATED DEPLOYMENT${NC}${CYAN}              ║${NC}"
    echo -e "${CYAN}║                                                               ║${NC}"
    echo -e "${CYAN}║                   System Setup & Configuration                ║${NC}"
    echo -e "${CYAN}║                                                               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${DIM}  Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${DIM}  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
    echo -e "${DIM}  Log: ${LOG_FILE}${NC}"
    echo ""
}

################################################################################
# PREREQUISITE CHECKS
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo ""
        echo "Usage: sudo bash $0"
        exit 1
    fi
}

check_git() {
    log_info "Checking for git installation..."
    
    if ! command -v git &>/dev/null; then
        log_error "git is NOT installed"
        echo ""
        echo -e "${RED}${BOLD}ERROR: git is required before running this script${NC}"
        echo ""
        echo "Install git first:"
        echo "  Ubuntu/Debian:  ${CYAN}sudo apt-get update && sudo apt-get install -y git${NC}"
        echo "  RHEL/CentOS:    ${CYAN}sudo yum install -y git${NC}"
        echo "  macOS:          ${CYAN}brew install git${NC}"
        echo ""
        exit 1
    fi
    
    log_success "git is installed: $(git --version | head -n1)"
}

################################################################################
# SYSTEM DETECTION FUNCTIONS
################################################################################

detect_os() {
    log_step "1" "$TOTAL_STEPS" "DETECTING OPERATING SYSTEM"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
        
        log_info "Operating System: ${NAME}"
        log_info "Version: ${VERSION}"
        
        # Determine package manager
        case "$OS_NAME" in
            ubuntu|debian)
                PACKAGE_MANAGER="apt"
                ;;
            rhel|centos|fedora|rocky|almalinux)
                PACKAGE_MANAGER="yum"
                if command -v dnf &>/dev/null; then
                    PACKAGE_MANAGER="dnf"
                fi
                ;;
            arch|manjaro)
                PACKAGE_MANAGER="pacman"
                ;;
            *)
                log_warning "Unknown Linux distribution: ${OS_NAME}"
                PACKAGE_MANAGER="unknown"
                ;;
        esac
        
        log_success "Package Manager: ${PACKAGE_MANAGER}"
        
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_NAME="macos"
        OS_VERSION=$(sw_vers -productVersion)
        PACKAGE_MANAGER="brew"
        
        log_info "Operating System: macOS"
        log_info "Version: ${OS_VERSION}"
        log_success "Package Manager: Homebrew"
        
        if ! command -v brew &>/dev/null; then
            log_warning "Homebrew is not installed"
            log_info "Install from: https://brew.sh"
        fi
    else
        log_error "Unsupported operating system"
        exit 1
    fi
}

detect_hardware() {
    log_step "2" "$TOTAL_STEPS" "DETECTING HARDWARE RESOURCES"
    
    # CPU Detection
    if [[ "$(uname)" == "Darwin" ]]; then
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        CPU_CORES=$(nproc)
    fi
    log_info "CPU Cores: ${CPU_CORES}"
    
    # RAM Detection
    if [[ "$(uname)" == "Darwin" ]]; then
        TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
        TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))
    else
        TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    fi
    log_info "Total RAM: ${TOTAL_RAM_GB} GB"
    
    # Minimum Requirements Check
    if [[ $CPU_CORES -lt 4 ]]; then
        log_warning "CPU cores (${CPU_CORES}) below recommended (4+)"
    else
        log_success "CPU cores meet requirements"
    fi
    
    if [[ $TOTAL_RAM_GB -lt 8 ]]; then
        log_warning "RAM (${TOTAL_RAM_GB}GB) below recommended (8GB+)"
    else
        log_success "RAM meets requirements"
    fi
}

detect_gpu() {
    log_step "3" "$TOTAL_STEPS" "DETECTING GPU"
    
    HAS_GPU=false
    GPU_TYPE="none"
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            HAS_GPU=true
            GPU_TYPE="nvidia"
            
            local gpu_name=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -n1)
            local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n1)
            local gpu_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
            
            log_success "NVIDIA GPU detected"
            log_info "  Model: ${gpu_name}"
            log_info "  VRAM: ${gpu_memory}"
            log_info "  Driver: ${gpu_driver}"
            
            # Check CUDA
            if command -v nvcc &>/dev/null; then
                local cuda_version=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
                log_info "  CUDA: ${cuda_version}"
            else
                log_warning "  CUDA toolkit not found (optional)"
            fi
        fi
    fi
    
    # Check for AMD GPU
    if [[ "$HAS_GPU" == false ]] && command -v rocm-smi &>/dev/null; then
        if rocm-smi &>/dev/null; then
            HAS_GPU=true
            GPU_TYPE="amd"
            log_success "AMD GPU detected (ROCm)"
        fi
    fi
    
    # Check for Apple Silicon
    if [[ "$HAS_GPU" == false ]] && [[ "$(uname)" == "Darwin" ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then
            HAS_GPU=true
            GPU_TYPE="apple_silicon"
            log_success "Apple Silicon detected (Metal support)"
        fi
    fi
    
    if [[ "$HAS_GPU" == false ]]; then
        log_warning "No GPU detected - will use CPU only"
        log_info "Large models will be slower without GPU"
    fi
}

detect_network() {
    log_step "4" "$TOTAL_STEPS" "DETECTING NETWORK CONFIGURATION"
    
    # Hostname
    HOSTNAME=$(hostname)
    log_info "Hostname: ${HOSTNAME}"
    
    # Timezone
    if [[ -f /etc/timezone ]]; then
        TIMEZONE=$(cat /etc/timezone)
    elif [[ -L /etc/localtime ]]; then
        TIMEZONE=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
    else
        TIMEZONE=$(date +%Z)
    fi
    log_info "Timezone: ${TIMEZONE}"
    
    # Check for Tailscale
    if command -v tailscale &>/dev/null; then
        if tailscale status &>/dev/null; then
            TAILNET_NAME=$(tailscale status --json 2>/dev/null | grep -o '"MagicDNSSuffix":"[^"]*"' | cut -d'"' -f4 || echo "")
            if [[ -n "$TAILNET_NAME" ]]; then
                log_success "Tailscale detected: ${TAILNET_NAME}"
            else
                log_info "Tailscale installed but not connected"
            fi
        else
            log_info "Tailscale installed but not running"
        fi
    else
        log_info "Tailscale not detected"
    fi
    
    # Check for Docker
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker detected: ${docker_version}"
    else
        log_warning "Docker not detected - will install"
    fi
}

################################################################################
# SYSTEM VALIDATION
################################################################################

validate_system() {
    log_step "5" "$TOTAL_STEPS" "VALIDATING SYSTEM REQUIREMENTS"
    
    local issues=0
    
    echo ""
    log_header "System Validation Report"
    
    # Check disk space
    local available_space=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    log_info "Available disk space: ${available_space}GB"
    
    if [[ $available_space -lt 50 ]]; then
        log_warning "Low disk space (${available_space}GB < 50GB recommended)"
        ((issues++))
    else
        log_success "Sufficient disk space"
    fi
    
    # Check internet connectivity
    log_info "Checking internet connectivity..."
    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_success "Internet connectivity confirmed"
    else
        log_error "No internet connectivity detected"
        ((issues++))
    fi
    
    # Summary
    echo ""
    if [[ $issues -eq 0 ]]; then
        log_success "All system requirements validated"
    else
        log_warning "Found ${issues} issue(s) - review warnings above"
        echo ""
        read -p "Continue anyway? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi
}

################################################################################
# PART 1 MAIN FUNCTION
################################################################################

main_part1() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    echo "AI Platform Setup Log - $(date)" >> "$LOG_FILE"
    echo "Script Version: ${SCRIPT_VERSION}" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Show banner
    show_banner
    
    # Prerequisite checks
    check_root
    check_git
    
    # System detection
    detect_os
    detect_hardware
    detect_gpu
    detect_network
    validate_system
    
    log_success "Part 1 completed: System detection finished"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 1 of Script 1 v${SCRIPT_VERSION} completed${NC}"
    echo -e "${CYAN}  Ready for Part 2: Dependency Installation${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute Part 1
main_part1
################################################################################
# DEPENDENCY INSTALLATION FUNCTIONS
################################################################################

install_system_dependencies() {
    log_step "6" "$TOTAL_STEPS" "INSTALLING SYSTEM DEPENDENCIES"

    local packages_to_install=()

    # Check and add missing packages
    local required_packages=("curl" "wget" "jq" "ca-certificates" "gnupg" "lsb-release" "tar" "gzip" "unzip")

    for pkg in "${required_packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        fi
    done

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_success "All required dependencies already installed"
        return 0
    fi

    log_info "Installing: ${packages_to_install[*]}"

    case "$PACKAGE_MANAGER" in
        apt)
            apt-get update -qq
            apt-get install -y "${packages_to_install[@]}" >/dev/null 2>&1
            ;;
        yum|dnf)
            $PACKAGE_MANAGER install -y "${packages_to_install[@]}" >/dev/null 2>&1
            ;;
        pacman)
            pacman -S --noconfirm "${packages_to_install[@]}" >/dev/null 2>&1
            ;;
        brew)
            for pkg in "${packages_to_install[@]}"; do
                brew install "$pkg" >/dev/null 2>&1 || true
            done
            ;;
        *)
            log_error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 1
            ;;
    esac

    # Verify installation
    local failed=0
    for pkg in "${packages_to_install[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            log_success "  ✓ ${pkg}"
        else
            log_error "  ✗ ${pkg} failed to install"
            ((failed++))
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All dependencies installed successfully"
    else
        log_error "${failed} package(s) failed to install"
        exit 1
    fi
}

install_docker() {
    log_step "7" "$TOTAL_STEPS" "INSTALLING DOCKER"

    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker already installed: ${docker_version}"
        return 0
    fi

    log_info "Installing Docker..."

    case "$PACKAGE_MANAGER" in
        apt)
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS_NAME}/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc

            # Add Docker repository
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_NAME} \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null

            # Install Docker
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;

        yum|dnf)
            $PACKAGE_MANAGER install -y yum-utils >/dev/null 2>&1
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            systemctl start docker
            systemctl enable docker
            ;;

        brew)
            log_warning "On macOS, please install Docker Desktop manually"
            log_info "Download from: https://www.docker.com/products/docker-desktop"
            exit 1
            ;;

        *)
            log_error "Automatic Docker installation not supported for ${PACKAGE_MANAGER}"
            log_info "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    # Verify installation
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker installed: ${docker_version}"

        # Start Docker service
        if [[ "$OS_NAME" != "macos" ]]; then
            systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
            systemctl enable docker 2>/dev/null || true
        fi
    else
        log_error "Docker installation failed"
        exit 1
    fi
}

configure_docker_gpu() {
    if [[ "$HAS_GPU" != true ]]; then
        log_info "No GPU detected - skipping GPU configuration"
        return 0
    fi

    log_step "8" "$TOTAL_STEPS" "CONFIGURING DOCKER FOR GPU"

    case "$GPU_TYPE" in
        nvidia)
            log_info "Configuring NVIDIA Docker runtime..."

            # Install nvidia-container-toolkit
            if ! command -v nvidia-ctk &>/dev/null; then
                case "$PACKAGE_MANAGER" in
                    apt)
                        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
                        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
                        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
                        apt-get update -qq
                        apt-get install -y nvidia-container-toolkit >/dev/null 2>&1
                        ;;
                    yum|dnf)
                        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
                        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/nvidia-container-toolkit.repo | \
                            tee /etc/yum.repos.d/nvidia-container-toolkit.repo
                        $PACKAGE_MANAGER install -y nvidia-container-toolkit >/dev/null 2>&1
                        ;;
                esac
            fi

            # Configure Docker daemon
            nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1
            systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true

            log_success "NVIDIA Docker runtime configured"
            ;;

        amd)
            log_info "AMD GPU detected - ROCm support"
            log_warning "ROCm Docker configuration requires manual setup"
            log_info "See: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html"
            ;;

        apple_silicon)
            log_success "Apple Silicon - Metal support built-in"
            ;;
    esac
}

################################################################################
# DIRECTORY STRUCTURE SETUP
################################################################################

setup_directory_structure() {
    log_step "9" "$TOTAL_STEPS" "SETTING UP DIRECTORY STRUCTURE"

    local directories=(
        "$BASE_DIR"
        "$DATA_DIR"
        "$DATA_DIR/ollama"
        "$DATA_DIR/open-webui"
        "$DATA_DIR/postgres"
        "$DATA_DIR/redis"
        "$DATA_DIR/qdrant"
        "$DATA_DIR/weaviate"
        "$DATA_DIR/chroma"
        "$DATA_DIR/milvus"
        "$DATA_DIR/minio"
        "$DATA_DIR/n8n"
        "$DATA_DIR/langfuse"
        "$DATA_DIR/dify"
        "$DATA_DIR/prometheus"
        "$DATA_DIR/grafana"
        "$DATA_DIR/loki"
        "$CONFIG_DIR"
        "$CONFIG_DIR/secrets"
        "$CONFIG_DIR/certs"
        "$CONFIG_DIR/caddy"
        "$CONFIG_DIR/nginx"
        "$CONFIG_DIR/litellm"
        "$CONFIG_DIR/prometheus"
        "$CONFIG_DIR/grafana"
        "$BACKUP_DIR"
        "$SCRIPTS_DIR"
    )

    log_info "Creating directory structure..."

    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "  Created: ${dir}"
        else
            log_info "  Exists: ${dir}"
        fi
    done

    # Set permissions
    chmod -R 755 "$BASE_DIR"
    chmod 700 "$CONFIG_DIR/secrets"

    log_success "Directory structure created"

    # Create .gitkeep files
    find "$BASE_DIR" -type d -empty -exec touch {}/.gitkeep \;
}

setup_docker_network() {
    log_step "10" "$TOTAL_STEPS" "SETTING UP DOCKER NETWORK"

    local network_name="ai-platform-network"

    if docker network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
        log_success "Docker network '${network_name}' already exists"
        return 0
    fi

    log_info "Creating Docker network: ${network_name}"

    docker network create \
        --driver bridge \
        --subnet 172.28.0.0/16 \
        --opt com.docker.network.bridge.name=br-ai-platform \
        --label ai-platform \
        "$network_name" >/dev/null 2>&1

    if docker network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
        log_success "Docker network created successfully"
    else
        log_error "Failed to create Docker network"
        exit 1
    fi
}

################################################################################
# PART 2 MAIN FUNCTION
################################################################################

main_part2() {
    install_system_dependencies
    install_docker
    configure_docker_gpu
    setup_directory_structure
    setup_docker_network

    log_success "Part 2 completed: Infrastructure setup finished"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 2 of Script 1 v${SCRIPT_VERSION} completed${NC}"
    echo -e "${CYAN}  Ready for Part 3: Service Selection${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute Part 2
main_part2
################################################################################
# SERVICE SELECTION FUNCTIONS
################################################################################

show_service_menu() {
    log_step "11" "$TOTAL_STEPS" "SERVICE SELECTION"

    echo ""
    log_header "Available Services"

    cat << 'EOF'
Select services to deploy (you can choose multiple):

CORE SERVICES (Recommended):
  [1] Ollama               - Local LLM runtime (GPU accelerated)
  [2] Open WebUI           - Chat interface for LLMs
  [3] LiteLLM              - Unified API gateway for all LLM providers

VECTOR DATABASES (Choose one or more):
  [4] Qdrant               - High-performance vector search
  [5] Weaviate             - AI-native vector database
  [6] ChromaDB             - Simple embedded vector store
  [7] Milvus               - Scalable vector database

DATA STORES:
  [8] PostgreSQL           - Relational database
  [9] Redis                - In-memory cache

AI PLATFORMS:
  [10] Dify                - LLM app development platform
  [11] Langfuse            - LLM observability & analytics
  [12] n8n                 - Workflow automation

STORAGE:
  [13] MinIO               - S3-compatible object storage
  [14] Google Drive Sync   - Sync files to Google Drive

MONITORING:
  [15] Prometheus          - Metrics collection
  [16] Grafana             - Metrics visualization
  [17] Loki                - Log aggregation

REVERSE PROXY (Choose one):
  [18] Caddy               - Auto HTTPS reverse proxy
  [19] Nginx               - Traditional reverse proxy

MANAGEMENT:
  [20] Portainer           - Docker GUI management

OPTIONAL:
  [21] Jupyter             - Interactive notebooks
  [22] Code Server         - VS Code in browser
  [23] Filebrowser         - Web file manager
  [24] Uptime Kuma         - Service monitoring
  [25] Plausible           - Privacy-friendly analytics

EOF
}

select_services() {
    show_service_menu

    echo ""
    echo -e "${YELLOW}Enter service numbers separated by spaces (e.g., 1 2 3 8 9 15 16 18)${NC}"
    echo -e "${YELLOW}Or enter 'all' for recommended stack, 'minimal' for core only${NC}"
    echo ""
    read -p "Your selection: " selection

    # Initialize all services as not selected
    SELECTED_SERVICES=(
        [ollama]=false
        [open-webui]=false
        [litellm]=false
        [qdrant]=false
        [weaviate]=false
        [chroma]=false
        [milvus]=false
        [postgres]=false
        [redis]=false
        [dify]=false
        [langfuse]=false
        [n8n]=false
        [minio]=false
        [gdrive-sync]=false
        [prometheus]=false
        [grafana]=false
        [loki]=false
        [caddy]=false
        [nginx]=false
        [portainer]=false
        [jupyter]=false
        [code-server]=false
        [filebrowser]=false
        [uptime-kuma]=false
        [plausible]=false
    )

    # Handle presets
    if [[ "$selection" == "all" ]]; then
        log_info "Selecting recommended stack..."
        SELECTED_SERVICES[ollama]=true
        SELECTED_SERVICES[open-webui]=true
        SELECTED_SERVICES[litellm]=true
        SELECTED_SERVICES[qdrant]=true
        SELECTED_SERVICES[postgres]=true
        SELECTED_SERVICES[redis]=true
        SELECTED_SERVICES[langfuse]=true
        SELECTED_SERVICES[n8n]=true
        SELECTED_SERVICES[minio]=true
        SELECTED_SERVICES[prometheus]=true
        SELECTED_SERVICES[grafana]=true
        SELECTED_SERVICES[caddy]=true
        SELECTED_SERVICES[portainer]=true

    elif [[ "$selection" == "minimal" ]]; then
        log_info "Selecting minimal stack..."
        SELECTED_SERVICES[ollama]=true
        SELECTED_SERVICES[open-webui]=true
        SELECTED_SERVICES[postgres]=true
        SELECTED_SERVICES[caddy]=true

    else
        # Parse individual selections
        for num in $selection; do
            case $num in
                1) SELECTED_SERVICES[ollama]=true ;;
                2) SELECTED_SERVICES[open-webui]=true ;;
                3) SELECTED_SERVICES[litellm]=true ;;
                4) SELECTED_SERVICES[qdrant]=true ;;
                5) SELECTED_SERVICES[weaviate]=true ;;
                6) SELECTED_SERVICES[chroma]=true ;;
                7) SELECTED_SERVICES[milvus]=true ;;
                8) SELECTED_SERVICES[postgres]=true ;;
                9) SELECTED_SERVICES[redis]=true ;;
                10) SELECTED_SERVICES[dify]=true ;;
                11) SELECTED_SERVICES[langfuse]=true ;;
                12) SELECTED_SERVICES[n8n]=true ;;
                13) SELECTED_SERVICES[minio]=true ;;
                14) SELECTED_SERVICES[gdrive-sync]=true ;;
                15) SELECTED_SERVICES[prometheus]=true ;;
                16) SELECTED_SERVICES[grafana]=true ;;
                17) SELECTED_SERVICES[loki]=true ;;
                18) SELECTED_SERVICES[caddy]=true; USE_CADDY=true ;;
                19) SELECTED_SERVICES[nginx]=true; USE_NGINX=true ;;
                20) SELECTED_SERVICES[portainer]=true ;;
                21) SELECTED_SERVICES[jupyter]=true ;;
                22) SELECTED_SERVICES[code-server]=true ;;
                23) SELECTED_SERVICES[filebrowser]=true ;;
                24) SELECTED_SERVICES[uptime-kuma]=true ;;
                25) SELECTED_SERVICES[plausible]=true ;;
                *) log_warning "Invalid selection: ${num}" ;;
            esac
        done
    fi

    # Validate selections
    validate_service_dependencies

    # Show summary
    show_service_summary
}

validate_service_dependencies() {
    log_info "Validating service dependencies..."

    # Langfuse requires PostgreSQL
    if [[ "${SELECTED_SERVICES[langfuse]}" == true ]] && [[ "${SELECTED_SERVICES[postgres]}" != true ]]; then
        log_warning "Langfuse requires PostgreSQL - adding automatically"
        SELECTED_SERVICES[postgres]=true
    fi

    # Dify requires PostgreSQL and Redis
    if [[ "${SELECTED_SERVICES[dify]}" == true ]]; then
        if [[ "${SELECTED_SERVICES[postgres]}" != true ]]; then
            log_warning "Dify requires PostgreSQL - adding automatically"
            SELECTED_SERVICES[postgres]=true
        fi
        if [[ "${SELECTED_SERVICES[redis]}" != true ]]; then
            log_warning "Dify requires Redis - adding automatically"
            SELECTED_SERVICES[redis]=true
        fi
    fi

    # Open WebUI works better with a vector DB
    if [[ "${SELECTED_SERVICES[open-webui]}" == true ]]; then
        local has_vector_db=false
        for vdb in qdrant weaviate chroma milvus; do
            if [[ "${SELECTED_SERVICES[$vdb]}" == true ]]; then
                has_vector_db=true
                break
            fi
        done

        if [[ "$has_vector_db" == false ]]; then
            log_warning "Open WebUI recommended with a vector database"
            read -p "Add Qdrant? [Y/n]: " add_qdrant
            if [[ ! "$add_qdrant" =~ ^[Nn]$ ]]; then
                SELECTED_SERVICES[qdrant]=true
            fi
        fi
    fi

    # Check reverse proxy selection
    if [[ "${SELECTED_SERVICES[caddy]}" == true ]] && [[ "${SELECTED_SERVICES[nginx]}" == true ]]; then
        log_error "Cannot select both Caddy and Nginx"
        echo "Choose one:"
        echo "  1) Caddy (recommended - auto HTTPS)"
        echo "  2) Nginx (traditional)"
        read -p "Selection [1/2]: " proxy_choice

        if [[ "$proxy_choice" == "1" ]]; then
            SELECTED_SERVICES[nginx]=false
            USE_NGINX=false
        else
            SELECTED_SERVICES[caddy]=false
            USE_CADDY=false
        fi
    fi

    # If no reverse proxy selected, add Caddy
    if [[ "${SELECTED_SERVICES[caddy]}" != true ]] && [[ "${SELECTED_SERVICES[nginx]}" != true ]]; then
        log_warning "No reverse proxy selected - adding Caddy (recommended)"
        SELECTED_SERVICES[caddy]=true
        USE_CADDY=true
    fi
}

show_service_summary() {
    echo ""
    log_header "Selected Services Summary"

    local count=0
    for service in "${!SELECTED_SERVICES[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]]; then
            echo -e "  ${GREEN}✓${NC} ${service}"
            ((count++))
        fi
    done

    echo ""
    log_info "Total services selected: ${count}"
    echo ""

    read -p "Proceed with these services? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Restarting service selection..."
        select_services
    fi
}

################################################################################
# PORT CONFIGURATION
################################################################################

configure_ports() {
    log_step "12" "$TOTAL_STEPS" "CONFIGURING SERVICE PORTS"

    log_info "Using default port configuration..."

    # Define default ports
    SERVICE_PORTS=(
        [ollama]=11434
        [open-webui]=8080
        [litellm]=4000
        [qdrant]=6333
        [weaviate]=8081
        [chroma]=8000
        [milvus]=19530
        [postgres]=5432
        [redis]=6379
        [dify]=3000
        [langfuse]=3001
        [n8n]=5678
        [minio]=9000
        [minio-console]=9001
        [prometheus]=9090
        [grafana]=3002
        [loki]=3100
        [caddy]=80
        [caddy-https]=443
        [nginx]=80
        [nginx-https]=443
        [portainer]=9443
        [jupyter]=8888
        [code-server]=8443
        [filebrowser]=8082
        [uptime-kuma]=3001
        [plausible]=8000
    )

    echo ""
    log_info "Port assignments:"
    for service in "${!SERVICE_PORTS[@]}"; do
        echo "  ${service}: ${SERVICE_PORTS[$service]}"
    done

    echo ""
    read -p "Use custom ports? [y/N]: " custom_ports

    if [[ "$custom_ports" =~ ^[Yy]$ ]]; then
        log_info "Custom port configuration..."
        for service in "${!SELECTED_SERVICES[@]}"; do
            if [[ "${SELECTED_SERVICES[$service]}" == true ]] && [[ -n "${SERVICE_PORTS[$service]}" ]]; then
                read -p "Port for ${service} [${SERVICE_PORTS[$service]}]: " custom_port
                if [[ -n "$custom_port" ]]; then
                    SERVICE_PORTS[$service]=$custom_port
                fi
            fi
        done
    fi

    log_success "Port configuration complete"
}

################################################################################
# DOMAIN CONFIGURATION
################################################################################

configure_domains() {
    log_step "13" "$TOTAL_STEPS" "CONFIGURING DOMAIN NAMES"

    echo ""
    echo -e "${YELLOW}Domain Configuration${NC}"
    echo ""
    echo "Options:"
    echo "  1) Use Tailscale domain (recommended if Tailscale is active)"
    echo "  2) Use custom domain"
    echo "  3) Use localhost (development only)"
    echo ""

    read -p "Selection [1-3]: " domain_choice

    case $domain_choice in
        1)
            if [[ -n "$TAILNET_NAME" ]]; then
                DOMAIN_NAME="${HOSTNAME}.${TAILNET_NAME}"
                log_success "Using Tailscale domain: ${DOMAIN_NAME}"
            else
                log_error "Tailscale not detected"
                configure_domains
            fi
            ;;
        2)
            read -p "Enter your domain name: " custom_domain
            DOMAIN_NAME="$custom_domain"
            log_success "Using custom domain: ${DOMAIN_NAME}"
            ;;
        3)
            DOMAIN_NAME="localhost"
            log_warning "Using localhost (development only - no HTTPS)"
            ;;
        *)
            log_error "Invalid selection"
            configure_domains
            ;;
    esac
}

################################################################################
# PART 3 MAIN FUNCTION
################################################################################

main_part3() {
    select_services
    configure_ports
    configure_domains

    log_success "Part 3 completed: Service configuration finished"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 3 of Script 1 v${SCRIPT_VERSION} completed${NC}"
    echo -e "${CYAN}  Ready for Part 4: Model & API Configuration${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute Part 3
main_part3
################################################################################
# MODEL SELECTION FUNCTIONS
################################################################################

select_ollama_models() {
    if [[ "${SELECTED_SERVICES[ollama]}" != true ]]; then
        log_info "Ollama not selected - skipping model selection"
        return 0
    fi

    log_step "14" "$TOTAL_STEPS" "SELECTING OLLAMA MODELS"

    echo ""
    log_header "Ollama Model Selection"

    cat << 'EOF'
Select models to download (you can choose multiple):

SMALL MODELS (Good for CPU, < 8GB RAM):
  [1] llama3.2:3b         - Meta's latest small model (2GB)
  [2] phi3:mini           - Microsoft's efficient model (2.3GB)
  [3] gemma2:2b           - Google's compact model (1.6GB)
  [4] qwen2.5:3b          - Alibaba's multilingual model (2GB)

MEDIUM MODELS (Recommended for GPU, 16GB+ RAM):
  [5] llama3.2:7b         - Meta's balanced model (4.7GB)
  [6] mistral:7b          - High quality general purpose (4.1GB)
  [7] phi3:medium         - Microsoft's capable model (7.9GB)
  [8] gemma2:9b           - Google's advanced model (5.5GB)
  [9] qwen2.5:7b          - Alibaba's advanced model (4.7GB)

LARGE MODELS (GPU recommended, 32GB+ RAM):
  [10] llama3.1:70b       - Meta's most capable (40GB)
  [11] mixtral:8x7b       - Mixture of Experts (26GB)
  [12] qwen2.5:72b        - Alibaba's largest model (41GB)

SPECIALIZED MODELS:
  [13] codellama:7b       - Code generation (3.8GB)
  [14] llama3.2-vision:11b - Vision + text model (7.9GB)
  [15] nomic-embed-text   - Embeddings for RAG (274MB)

EMBEDDING MODELS (Recommended for RAG):
  [16] mxbai-embed-large  - High quality embeddings (669MB)
  [17] all-minilm         - Fast lightweight embeddings (23MB)

EOF

    echo ""
    echo -e "${YELLOW}Enter model numbers separated by spaces (e.g., 5 6 13 15)${NC}"
    echo -e "${YELLOW}Or enter 'recommended' for optimal selection based on your hardware${NC}"
    echo ""
    read -p "Your selection: " model_selection

    # Initialize models array
    OLLAMA_MODELS=()

    if [[ "$model_selection" == "recommended" ]]; then
        log_info "Selecting recommended models based on hardware..."

        if [[ "$HAS_GPU" == true ]] && [[ $TOTAL_RAM_GB -ge 32 ]]; then
            # High-end setup
            OLLAMA_MODELS+=(
                "llama3.2:7b"
                "mistral:7b"
                "codellama:7b"
                "nomic-embed-text"
            )
            log_info "High-end configuration: 7B models + embeddings"

        elif [[ "$HAS_GPU" == true ]] && [[ $TOTAL_RAM_GB -ge 16 ]]; then
            # Mid-range GPU setup
            OLLAMA_MODELS+=(
                "llama3.2:7b"
                "phi3:medium"
                "nomic-embed-text"
            )
            log_info "Mid-range configuration: 7B models + embeddings"

        elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
            # CPU with good RAM
            OLLAMA_MODELS+=(
                "llama3.2:3b"
                "phi3:mini"
                "nomic-embed-text"
            )
            log_info "CPU configuration: Small models + embeddings"

        else
            # Minimal setup
            OLLAMA_MODELS+=(
                "gemma2:2b"
                "all-minilm"
            )
            log_info "Minimal configuration: Smallest models only"
        fi

    else
        # Parse individual selections
        for num in $model_selection; do
            case $num in
                1) OLLAMA_MODELS+=("llama3.2:3b") ;;
                2) OLLAMA_MODELS+=("phi3:mini") ;;
                3) OLLAMA_MODELS+=("gemma2:2b") ;;
                4) OLLAMA_MODELS+=("qwen2.5:3b") ;;
                5) OLLAMA_MODELS+=("llama3.2:7b") ;;
                6) OLLAMA_MODELS+=("mistral:7b") ;;
                7) OLLAMA_MODELS+=("phi3:medium") ;;
                8) OLLAMA_MODELS+=("gemma2:9b") ;;
                9) OLLAMA_MODELS+=("qwen2.5:7b") ;;
                10) OLLAMA_MODELS+=("llama3.1:70b") ;;
                11) OLLAMA_MODELS+=("mixtral:8x7b") ;;
                12) OLLAMA_MODELS+=("qwen2.5:72b") ;;
                13) OLLAMA_MODELS+=("codellama:7b") ;;
                14) OLLAMA_MODELS+=("llama3.2-vision:11b") ;;
                15) OLLAMA_MODELS+=("nomic-embed-text") ;;
                16) OLLAMA_MODELS+=("mxbai-embed-large") ;;
                17) OLLAMA_MODELS+=("all-minilm") ;;
                *) log_warning "Invalid model selection: ${num}" ;;
            esac
        done
    fi

    # Show selected models
    echo ""
    log_header "Selected Models"
    for model in "${OLLAMA_MODELS[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${model}"
    done

    echo ""
    log_warning "Models will be downloaded after Ollama starts (may take time)"
    echo ""

    read -p "Proceed with these models? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Restarting model selection..."
        select_ollama_models
    fi
}

################################################################################
# API KEY COLLECTION
################################################################################

collect_api_keys() {
    log_step "15" "$TOTAL_STEPS" "COLLECTING API KEYS"

    echo ""
    log_header "API Key Configuration"

    echo ""
    echo -e "${YELLOW}Configure API keys for external services (optional)${NC}"
    echo -e "${DIM}Press Enter to skip any service${NC}"
    echo ""

    # Initialize API keys array
    API_KEYS=()

    # LiteLLM API Keys
    if [[ "${SELECTED_SERVICES[litellm]}" == true ]]; then
        echo ""
        echo -e "${CYAN}═══ LiteLLM Provider Keys ═══${NC}"

        read -sp "OpenAI API Key (sk-...): " openai_key
        echo ""
        if [[ -n "$openai_key" ]]; then
            API_KEYS[OPENAI_API_KEY]="$openai_key"
            log_success "  ✓ OpenAI key configured"
        fi

        read -sp "Anthropic API Key (sk-ant-...): " anthropic_key
        echo ""
        if [[ -n "$anthropic_key" ]]; then
            API_KEYS[ANTHROPIC_API_KEY]="$anthropic_key"
            log_success "  ✓ Anthropic key configured"
        fi

        read -sp "Google AI API Key: " google_key
        echo ""
        if [[ -n "$google_key" ]]; then
            API_KEYS[GOOGLE_API_KEY]="$google_key"
            log_success "  ✓ Google AI key configured"
        fi

        read -sp "Cohere API Key: " cohere_key
        echo ""
        if [[ -n "$cohere_key" ]]; then
            API_KEYS[COHERE_API_KEY]="$cohere_key"
            log_success "  ✓ Cohere key configured"
        fi

        read -sp "Azure OpenAI API Key: " azure_key
        echo ""
        if [[ -n "$azure_key" ]]; then
            API_KEYS[AZURE_API_KEY]="$azure_key"

            read -p "Azure Endpoint: " azure_endpoint
            if [[ -n "$azure_endpoint" ]]; then
                API_KEYS[AZURE_API_BASE]="$azure_endpoint"
                log_success "  ✓ Azure OpenAI configured"
            fi
        fi

        read -sp "Mistral API Key: " mistral_key
        echo ""
        if [[ -n "$mistral_key" ]]; then
            API_KEYS[MISTRAL_API_KEY]="$mistral_key"
            log_success "  ✓ Mistral key configured"
        fi
    fi

    # Google Drive Sync
    if [[ "${SELECTED_SERVICES[gdrive-sync]}" == true ]]; then
        echo ""
        echo -e "${CYAN}═══ Google Drive Configuration ═══${NC}"
        echo "Google Drive requires OAuth2 setup"
        echo "See: https://rclone.org/drive/"
        echo ""

        read -p "Have you completed OAuth2 setup? [y/N]: " gdrive_ready
        if [[ "$gdrive_ready" =~ ^[Yy]$ ]]; then
            read -p "Google Drive client_id: " gdrive_client_id
            read -sp "Google Drive client_secret: " gdrive_client_secret
            echo ""

            if [[ -n "$gdrive_client_id" ]] && [[ -n "$gdrive_client_secret" ]]; then
                API_KEYS[GDRIVE_CLIENT_ID]="$gdrive_client_id"
                API_KEYS[GDRIVE_CLIENT_SECRET]="$gdrive_client_secret"
                log_success "  ✓ Google Drive configured"
            fi
        fi
    fi

    # Plausible Analytics
    if [[ "${SELECTED_SERVICES[plausible]}" == true ]]; then
        echo ""
        echo -e "${CYAN}═══ Plausible Analytics ═══${NC}"

        read -p "Admin email for Plausible: " plausible_email
        if [[ -n "$plausible_email" ]]; then
            API_KEYS[PLAUSIBLE_ADMIN_EMAIL]="$plausible_email"
            log_success "  ✓ Plausible email configured"
        fi
    fi

    # Show summary
    echo ""
    log_header "API Keys Summary"

    local key_count=0
    for key in "${!API_KEYS[@]}"; do
        if [[ -n "${API_KEYS[$key]}" ]]; then
            echo -e "  ${GREEN}✓${NC} ${key}: ${DIM}[configured]${NC}"
            ((key_count++))
        fi
    done

    if [[ $key_count -eq 0 ]]; then
        log_info "No API keys configured (you can add them later)"
    else
        log_success "Configured ${key_count} API key(s)"
    fi
}

################################################################################
# SECRET GENERATION
################################################################################

generate_secrets() {
    log_step "16" "$TOTAL_STEPS" "GENERATING SECRETS"

    log_info "Generating secure secrets..."

    # Generate function
    generate_secret() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
    }

    # PostgreSQL
    if [[ "${SELECTED_SERVICES[postgres]}" == true ]]; then
        GENERATED_SECRETS[POSTGRES_PASSWORD]=$(generate_secret)
        log_success "  ✓ PostgreSQL password generated"
    fi

    # Redis
    if [[ "${SELECTED_SERVICES[redis]}" == true ]]; then
        GENERATED_SECRETS[REDIS_PASSWORD]=$(generate_secret)
        log_success "  ✓ Redis password generated"
    fi

    # MinIO
    if [[ "${SELECTED_SERVICES[minio]}" == true ]]; then
        GENERATED_SECRETS[MINIO_ROOT_USER]="admin"
        GENERATED_SECRETS[MINIO_ROOT_PASSWORD]=$(generate_secret)
        log_success "  ✓ MinIO credentials generated"
    fi

    # Langfuse
    if [[ "${SELECTED_SERVICES[langfuse]}" == true ]]; then
        GENERATED_SECRETS[LANGFUSE_SECRET_KEY]=$(generate_secret)
        GENERATED_SECRETS[LANGFUSE_SALT]=$(generate_secret)
        log_success "  ✓ Langfuse secrets generated"
    fi

    # n8n
    if [[ "${SELECTED_SERVICES[n8n]}" == true ]]; then
        GENERATED_SECRETS[N8N_ENCRYPTION_KEY]=$(generate_secret)
        log_success "  ✓ n8n encryption key generated"
    fi

    # Dify
    if [[ "${SELECTED_SERVICES[dify]}" == true ]]; then
        GENERATED_SECRETS[DIFY_SECRET_KEY]=$(generate_secret)
        GENERATED_SECRETS[DIFY_API_KEY]=$(generate_secret)
        log_success "  ✓ Dify secrets generated"
    fi

    # Open WebUI
    if [[ "${SELECTED_SERVICES[open-webui]}" == true ]]; then
        GENERATED_SECRETS[WEBUI_SECRET_KEY]=$(generate_secret)
        log_success "  ✓ Open WebUI secret generated"
    fi

    # LiteLLM
    if [[ "${SELECTED_SERVICES[litellm]}" == true ]]; then
        GENERATED_SECRETS[LITELLM_MASTER_KEY]=$(generate_secret)
        GENERATED_SECRETS[LITELLM_SALT_KEY]=$(generate_secret)
        log_success "  ✓ LiteLLM master key generated"
    fi

    # Grafana
    if [[ "${SELECTED_SERVICES[grafana]}" == true ]]; then
        GENERATED_SECRETS[GRAFANA_ADMIN_PASSWORD]=$(generate_secret)
        log_success "  ✓ Grafana admin password generated"
    fi

    # Portainer
    if [[ "${SELECTED_SERVICES[portainer]}" == true ]]; then
        GENERATED_SECRETS[PORTAINER_ADMIN_PASSWORD]=$(generate_secret)
        log_success "  ✓ Portainer admin password generated"
    fi

    # Code Server
    if [[ "${SELECTED_SERVICES[code-server]}" == true ]]; then
        GENERATED_SECRETS[CODE_SERVER_PASSWORD]=$(generate_secret)
        log_success "  ✓ Code Server password generated"
    fi

    # Jupyter
    if [[ "${SELECTED_SERVICES[jupyter]}" == true ]]; then
        GENERATED_SECRETS[JUPYTER_TOKEN]=$(generate_secret)
        log_success "  ✓ Jupyter token generated"
    fi

    log_success "All secrets generated successfully"
}

################################################################################
# SAVE SECRETS TO FILE
################################################################################

save_secrets() {
    log_step "17" "$TOTAL_STEPS" "SAVING SECRETS"

    local secrets_file="${CONFIG_DIR}/secrets/.secrets.env"
    local secrets_backup="${BACKUP_DIR}/secrets-${TIMESTAMP}.env"

    log_info "Saving secrets to: ${secrets_file}"

    # Create secrets file
    cat > "$secrets_file" << EOF
################################################################################
# AI PLATFORM SECRETS
# Generated: $(date)
# Version: ${SCRIPT_VERSION}
#
# WARNING: Keep this file secure! Contains sensitive credentials.
# Permissions: 600 (read/write owner only)
################################################################################

# System Configuration
DOMAIN_NAME="${DOMAIN_NAME}"
HOSTNAME="${HOSTNAME}"
TIMEZONE="${TIMEZONE}"

EOF

    # Add generated secrets
    if [[ ${#GENERATED_SECRETS[@]} -gt 0 ]]; then
        echo "# Generated Secrets" >> "$secrets_file"
        for key in "${!GENERATED_SECRETS[@]}"; do
            echo "${key}=${GENERATED_SECRETS[$key]}" >> "$secrets_file"
        done
        echo "" >> "$secrets_file"
    fi

    # Add API keys
    if [[ ${#API_KEYS[@]} -gt 0 ]]; then
        echo "# API Keys" >> "$secrets_file"
        for key in "${!API_KEYS[@]}"; do
            echo "${key}=${API_KEYS[$key]}" >> "$secrets_file"
        done
        echo "" >> "$secrets_file"
    fi

    # Add service ports
    echo "# Service Ports" >> "$secrets_file"
    for service in "${!SERVICE_PORTS[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]] || [[ "$service" == *"-"* ]]; then
            echo "${service^^}_PORT=${SERVICE_PORTS[$service]}" >> "$secrets_file"
        fi
    done

    # Set secure permissions
    chmod 600 "$secrets_file"

    # Create backup
    cp "$secrets_file" "$secrets_backup"
    chmod 600 "$secrets_backup"

    log_success "Secrets saved securely"
    log_info "Backup created: ${secrets_backup}"
}

################################################################################
# CREDENTIALS SUMMARY
################################################################################

show_credentials_summary() {
    log_step "18" "$TOTAL_STEPS" "CREDENTIALS SUMMARY"

    local summary_file="${CONFIG_DIR}/CREDENTIALS.txt"

    echo ""
    log_header "Generated Credentials Summary"

    # Create summary file
    cat > "$summary_file" << EOF
═══════════════════════════════════════════════════════════════════════════
AI PLATFORM CREDENTIALS
Generated: $(date)
═══════════════════════════════════════════════════════════════════════════

IMPORTANT: Save this file securely and delete after recording credentials!

EOF

    # Display and save credentials
    {
        echo ""
        echo "SYSTEM ACCESS:"
        echo "  Domain: ${DOMAIN_NAME}"
        echo "  Base URL: https://${DOMAIN_NAME}"
        echo ""

        if [[ -n "${GENERATED_SECRETS[POSTGRES_PASSWORD]}" ]]; then
            echo "POSTGRESQL:"
            echo "  Username: postgres"
            echo "  Password: ${GENERATED_SECRETS[POSTGRES_PASSWORD]}"
            echo "  Port: ${SERVICE_PORTS[postgres]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[MINIO_ROOT_PASSWORD]}" ]]; then
            echo "MINIO:"
            echo "  Username: ${GENERATED_SECRETS[MINIO_ROOT_USER]}"
            echo "  Password: ${GENERATED_SECRETS[MINIO_ROOT_PASSWORD]}"
            echo "  Console: https://${DOMAIN_NAME}:${SERVICE_PORTS[minio-console]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[GRAFANA_ADMIN_PASSWORD]}" ]]; then
            echo "GRAFANA:"
            echo "  Username: admin"
            echo "  Password: ${GENERATED_SECRETS[GRAFANA_ADMIN_PASSWORD]}"
            echo "  URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[grafana]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[PORTAINER_ADMIN_PASSWORD]}" ]]; then
            echo "PORTAINER:"
            echo "  Username: admin"
            echo "  Password: ${GENERATED_SECRETS[PORTAINER_ADMIN_PASSWORD]}"
            echo "  URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[portainer]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[CODE_SERVER_PASSWORD]}" ]]; then
            echo "CODE SERVER:"
            echo "  Password: ${GENERATED_SECRETS[CODE_SERVER_PASSWORD]}"
            echo "  URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[code-server]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[JUPYTER_TOKEN]}" ]]; then
            echo "JUPYTER:"
            echo "  Token: ${GENERATED_SECRETS[JUPYTER_TOKEN]}"
            echo "  URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[jupyter]}"
            echo ""
        fi

        if [[ -n "${GENERATED_SECRETS[LITELLM_MASTER_KEY]}" ]]; then
            echo "LITELLM:"
            echo "  Master Key: ${GENERATED_SECRETS[LITELLM_MASTER_KEY]}"
            echo "  URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[litellm]}"
            echo ""
        fi

        echo "═══════════════════════════════════════════════════════════════════════════"
        echo "All credentials are also stored in:"
        echo "  ${CONFIG_DIR}/secrets/.secrets.env"
        echo ""
        echo "SECURITY REMINDERS:"
        echo "  - Change default passwords after first login"
        echo "  - Enable 2FA where available"
        echo "  - Restrict access to secrets files (chmod 600)"
        echo "  - Regular security audits recommended"
        echo "═══════════════════════════════════════════════════════════════════════════"

    } | tee -a "$summary_file"

    chmod 600 "$summary_file"

    echo ""
    log_success "Credentials summary saved: ${summary_file}"
}

################################################################################
# PART 4 MAIN FUNCTION
################################################################################

main_part4() {
    select_ollama_models
    collect_api_keys
    generate_secrets
    save_secrets
    show_credentials_summary

    log_success "Part 4 completed: Configuration finished"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 4 of Script 1 v${SCRIPT_VERSION} completed${NC}"
    echo -e "${CYAN}  Ready for Part 5: Configuration File Generation${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute Part 4
main_part4
################################################################################
# DOCKER COMPOSE HEADER GENERATION
################################################################################

generate_compose_header() {
    cat << 'EOF'
################################################################################
# AI PLATFORM DOCKER COMPOSE
# Auto-generated configuration file
#
# DO NOT EDIT MANUALLY - Regenerate with Script 1
################################################################################

version: '3.8'

networks:
  ai-platform-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
EOF
}

################################################################################
# VOLUME DEFINITIONS
################################################################################

generate_volumes() {
    echo ""

    # Core volumes
    if [[ "${SELECTED_SERVICES[postgres]}" == true ]]; then
        echo "  postgres-data:"
    fi

    if [[ "${SELECTED_SERVICES[redis]}" == true ]]; then
        echo "  redis-data:"
    fi

    if [[ "${SELECTED_SERVICES[minio]}" == true ]]; then
        echo "  minio-data:"
    fi

    if [[ "${SELECTED_SERVICES[ollama]}" == true ]]; then
        echo "  ollama-data:"
    fi

    # Service-specific volumes
    if [[ "${SELECTED_SERVICES[langfuse]}" == true ]]; then
        echo "  langfuse-data:"
    fi

    if [[ "${SELECTED_SERVICES[n8n]}" == true ]]; then
        echo "  n8n-data:"
    fi

    if [[ "${SELECTED_SERVICES[dify]}" == true ]]; then
        echo "  dify-app-data:"
        echo "  dify-worker-data:"
    fi

    if [[ "${SELECTED_SERVICES[open-webui]}" == true ]]; then
        echo "  open-webui-data:"
    fi

    if [[ "${SELECTED_SERVICES[qdrant]}" == true ]]; then
        echo "  qdrant-data:"
    fi

    if [[ "${SELECTED_SERVICES[grafana]}" == true ]]; then
        echo "  grafana-data:"
    fi

    if [[ "${SELECTED_SERVICES[prometheus]}" == true ]]; then
        echo "  prometheus-data:"
    fi

    if [[ "${SELECTED_SERVICES[portainer]}" == true ]]; then
        echo "  portainer-data:"
    fi

    if [[ "${SELECTED_SERVICES[code-server]}" == true ]]; then
        echo "  code-server-data:"
    fi

    if [[ "${SELECTED_SERVICES[jupyter]}" == true ]]; then
        echo "  jupyter-data:"
    fi

    if [[ "${SELECTED_SERVICES[weaviate]}" == true ]]; then
        echo "  weaviate-data:"
    fi

    if [[ "${SELECTED_SERVICES[chroma]}" == true ]]; then
        echo "  chroma-data:"
    fi

    echo ""
    echo "services:"
}

################################################################################
# POSTGRES SERVICE
################################################################################

generate_postgres_service() {
    [[ "${SELECTED_SERVICES[postgres]}" != true ]] && return

    cat << EOF
  postgres:
    image: pgvector/pgvector:pg16
    container_name: ai-platform-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: ai_platform
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres/init:/docker-entrypoint-initdb.d:ro
    ports:
      - "${SERVICE_PORTS[postgres]}:5432"
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

EOF
}

################################################################################
# REDIS SERVICE
################################################################################

generate_redis_service() {
    [[ "${SELECTED_SERVICES[redis]}" != true ]] && return

    cat << EOF
  redis:
    image: redis:7-alpine
    container_name: ai-platform-redis
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS_PASSWORD} --appendonly yes
    volumes:
      - redis-data:/data
    ports:
      - "${SERVICE_PORTS[redis]}:6379"
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

EOF
}

################################################################################
# MINIO SERVICE
################################################################################

generate_minio_service() {
    [[ "${SELECTED_SERVICES[minio]}" != true ]] && return

    cat << EOF
  minio:
    image: minio/minio:latest
    container_name: ai-platform-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: \${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: \${MINIO_ROOT_PASSWORD}
    volumes:
      - minio-data:/data
    ports:
      - "${SERVICE_PORTS[minio]}:9000"
      - "${SERVICE_PORTS[minio-console]}:9001"
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

EOF
}

################################################################################
# OLLAMA SERVICE
################################################################################

generate_ollama_service() {
    [[ "${SELECTED_SERVICES[ollama]}" != true ]] && return

    local gpu_config=""
    if [[ "$HAS_GPU" == true ]]; then
        case "$GPU_TYPE" in
            nvidia)
                gpu_config="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
                ;;
            amd)
                gpu_config="    devices:
      - /dev/kfd
      - /dev/dri"
                ;;
        esac
    fi

    cat << EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ai-platform-ollama
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama
    ports:
      - "${SERVICE_PORTS[ollama]}:11434"
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/version"]
      interval: 30s
      timeout: 10s
      retries: 3
${gpu_config}
    deploy:
      resources:
        limits:
          memory: ${TOTAL_RAM_GB}G
        reservations:
          memory: 4G

EOF
}

################################################################################
# LITELLM SERVICE
################################################################################

generate_litellm_service() {
    [[ "${SELECTED_SERVICES[litellm]}" != true ]] && return

    cat << EOF
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-platform-litellm
    restart: unless-stopped
    environment:
      LITELLM_MASTER_KEY: \${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: \${LITELLM_SALT_KEY}
      DATABASE_URL: postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/litellm
      STORE_MODEL_IN_DB: "True"
EOF

    # Add API keys if configured
    if [[ -n "${API_KEYS[OPENAI_API_KEY]}" ]]; then
        echo "      OPENAI_API_KEY: \${OPENAI_API_KEY}"
    fi
    if [[ -n "${API_KEYS[ANTHROPIC_API_KEY]}" ]]; then
        echo "      ANTHROPIC_API_KEY: \${ANTHROPIC_API_KEY}"
    fi
    if [[ -n "${API_KEYS[GOOGLE_API_KEY]}" ]]; then
        echo "      GOOGLE_API_KEY: \${GOOGLE_API_KEY}"
    fi
    if [[ -n "${API_KEYS[COHERE_API_KEY]}" ]]; then
        echo "      COHERE_API_KEY: \${COHERE_API_KEY}"
    fi

    cat << EOF
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "${SERVICE_PORTS[litellm]}:4000"
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

EOF
}

################################################################################
# LANGFUSE SERVICE
################################################################################

generate_langfuse_service() {
    [[ "${SELECTED_SERVICES[langfuse]}" != true ]] && return

    cat << EOF
  langfuse:
    image: langfuse/langfuse:2
    container_name: ai-platform-langfuse
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/langfuse
      NEXTAUTH_SECRET: \${LANGFUSE_SECRET_KEY}
      SALT: \${LANGFUSE_SALT}
      NEXTAUTH_URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[langfuse]}
      TELEMETRY_ENABLED: "false"
      LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES: "true"
    ports:
      - "${SERVICE_PORTS[langfuse]}:3000"
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/public/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

EOF
}

################################################################################
# N8N SERVICE
################################################################################

generate_n8n_service() {
    [[ "${SELECTED_SERVICES[n8n]}" != true ]] && return

    cat << EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: ai-platform-n8n
    restart: unless-stopped
    environment:
      N8N_ENCRYPTION_KEY: \${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: postgres
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      N8N_HOST: ${DOMAIN_NAME}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[n8n]}
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: redis
      QUEUE_BULL_REDIS_PORT: 6379
      QUEUE_BULL_REDIS_PASSWORD: \${REDIS_PASSWORD}
    volumes:
      - n8n-data:/home/node/.n8n
      - ${DATA_DIR}/n8n-files:/files
    ports:
      - "${SERVICE_PORTS[n8n]}:5678"
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

EOF
}

################################################################################
# DIFY SERVICES
################################################################################

generate_dify_services() {
    [[ "${SELECTED_SERVICES[dify]}" != true ]] && return

    cat << EOF
  dify-api:
    image: langgenius/dify-api:latest
    container_name: ai-platform-dify-api
    restart: unless-stopped
    environment:
      MODE: api
      SECRET_KEY: \${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: \${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: \${REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:\${REDIS_PASSWORD}@redis:6379/1
      STORAGE_TYPE: s3
      S3_ENDPOINT: http://minio:9000
      S3_ACCESS_KEY: \${MINIO_ROOT_USER}
      S3_SECRET_KEY: \${MINIO_ROOT_PASSWORD}
      S3_BUCKET_NAME: dify
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
    volumes:
      - dify-app-data:/app/api/storage
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: ai-platform-dify-worker
    restart: unless-stopped
    environment:
      MODE: worker
      SECRET_KEY: \${DIFY_SECRET_KEY}
      DB_USERNAME: postgres
      DB_PASSWORD: \${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: \${REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:\${REDIS_PASSWORD}@redis:6379/1
      STORAGE_TYPE: s3
      S3_ENDPOINT: http://minio:9000
      S3_ACCESS_KEY: \${MINIO_ROOT_USER}
      S3_SECRET_KEY: \${MINIO_ROOT_PASSWORD}
      S3_BUCKET_NAME: dify
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
    volumes:
      - dify-worker-data:/app/api/storage
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

  dify-web:
    image: langgenius/dify-web:latest
    container_name: ai-platform-dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    ports:
      - "${SERVICE_PORTS[dify]}:3000"
    networks:
      - ai-platform-network
    depends_on:
      - dify-api
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

EOF
}

################################################################################
# OPEN WEBUI SERVICE
################################################################################

generate_open_webui_service() {
    [[ "${SELECTED_SERVICES[open-webui]}" != true ]] && return

    cat << EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ai-platform-open-webui
    restart: unless-stopped
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
      WEBUI_SECRET_KEY: \${WEBUI_SECRET_KEY}
      DATABASE_URL: postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/open_webui
      ENABLE_RAG_WEB_SEARCH: "True"
      ENABLE_IMAGE_GENERATION: "True"
      ENABLE_COMMUNITY_SHARING: "False"
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "${SERVICE_PORTS[open-webui]}:8080"
    networks:
      - ai-platform-network
    depends_on:
      postgres:
        condition: service_healthy
EOF

    if [[ "${SELECTED_SERVICES[ollama]}" == true ]]; then
        echo "      ollama:"
        echo "        condition: service_healthy"
    fi

    cat << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

EOF
}

################################################################################
# QDRANT SERVICE
################################################################################

generate_qdrant_service() {
    [[ "${SELECTED_SERVICES[qdrant]}" != true ]] && return

    cat << EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ai-platform-qdrant
    restart: unless-stopped
    volumes:
      - qdrant-data:/qdrant/storage
    ports:
      - "${SERVICE_PORTS[qdrant]}:6333"
      - "${SERVICE_PORTS[qdrant-grpc]}:6334"
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

EOF
}

################################################################################
# MONITORING SERVICES
################################################################################

generate_monitoring_services() {
    # Prometheus
    if [[ "${SELECTED_SERVICES[prometheus]}" == true ]]; then
        cat << EOF
  prometheus:
    image: prom/prometheus:latest
    container_name: ai-platform-prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "${SERVICE_PORTS[prometheus]}:9090"
    networks:
      - ai-platform-network
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

EOF
    fi

    # Grafana
    if [[ "${SELECTED_SERVICES[grafana]}" == true ]]; then
        cat << EOF
  grafana:
    image: grafana/grafana:latest
    container_name: ai-platform-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_PASSWORD: \${GRAFANA_ADMIN_PASSWORD}
      GF_INSTALL_PLUGINS: grafana-clock-panel
      GF_SERVER_ROOT_URL: https://${DOMAIN_NAME}:${SERVICE_PORTS[grafana]}
    volumes:
      - grafana-data:/var/lib/grafana
      - ${CONFIG_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "${SERVICE_PORTS[grafana]}:3000"
    networks:
      - ai-platform-network
EOF

        if [[ "${SELECTED_SERVICES[prometheus]}" == true ]]; then
            echo "    depends_on:"
            echo "      - prometheus"
        fi

        cat << EOF
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

EOF
    fi
}

################################################################################
# MANAGEMENT SERVICES
################################################################################

generate_management_services() {
    # Portainer
    if [[ "${SELECTED_SERVICES[portainer]}" == true ]]; then
        cat << EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: ai-platform-portainer
    restart: unless-stopped
    command: --admin-password-file /tmp/portainer_password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data
    ports:
      - "${SERVICE_PORTS[portainer]}:9000"
      - "8000:8000"
    networks:
      - ai-platform-network
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

EOF
    fi

    # Code Server
    if [[ "${SELECTED_SERVICES[code-server]}" == true ]]; then
        cat << EOF
  code-server:
    image: codercom/code-server:latest
    container_name: ai-platform-code-server
    restart: unless-stopped
    environment:
      PASSWORD: \${CODE_SERVER_PASSWORD}
    volumes:
      - code-server-data:/home/coder
      - ${BASE_DIR}:/home/coder/project
    ports:
      - "${SERVICE_PORTS[code-server]}:8080"
    networks:
      - ai-platform-network
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

EOF
    fi

    # Jupyter
    if [[ "${SELECTED_SERVICES[jupyter]}" == true ]]; then
        cat << EOF
  jupyter:
    image: jupyter/scipy-notebook:latest
    container_name: ai-platform-jupyter
    restart: unless-stopped
    environment:
      JUPYTER_ENABLE_LAB: "yes"
      JUPYTER_TOKEN: \${JUPYTER_TOKEN}
    volumes:
      - jupyter-data:/home/jovyan/work
    ports:
      - "${SERVICE_PORTS[jupyter]}:8888"
    networks:
      - ai-platform-network
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

EOF
    fi
}

################################################################################
# GENERATE COMPLETE DOCKER COMPOSE FILE
################################################################################

generate_docker_compose() {
    log_step "19" "$TOTAL_STEPS" "GENERATING DOCKER COMPOSE FILE"

    local compose_file="${CONFIG_DIR}/docker-compose.yml"
    local compose_backup="${BACKUP_DIR}/docker-compose-${TIMESTAMP}.yml"

    log_info "Generating Docker Compose configuration..."

    {
        generate_compose_header
        generate_volumes
        generate_postgres_service
        generate_redis_service
        generate_minio_service
        generate_ollama_service
        generate_litellm_service
        generate_langfuse_service
        generate_n8n_service
        generate_dify_services
        generate_open_webui_service
        generate_qdrant_service
        generate_monitoring_services
        generate_management_services

    } > "$compose_file"

    # Create backup
    cp "$compose_file" "$compose_backup"

    log_success "Docker Compose file generated: ${compose_file}"
    log_info "Backup created: ${compose_backup}"

    # Validate syntax
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f "$compose_file" config &> /dev/null; then
            log_success "Docker Compose syntax validated successfully"
        else
            log_error "Docker Compose syntax validation failed"
            return 1
        fi
    fi
}

################################################################################
# GENERATE LITELLM CONFIG
################################################################################

generate_litellm_config() {
    [[ "${SELECTED_SERVICES[litellm]}" != true ]] && return

    log_step "20" "$TOTAL_STEPS" "GENERATING LITELLM CONFIGURATION"

    local litellm_config="${CONFIG_DIR}/litellm/config.yaml"

    mkdir -p "${CONFIG_DIR}/litellm"

    cat > "$litellm_config" << 'EOF'
# LiteLLM Configuration
# Auto-generated by Script 1

model_list:
EOF

    # Add Ollama models if selected
    if [[ "${SELECTED_SERVICES[ollama]}" == true ]] && [[ ${#OLLAMA_MODELS[@]} -gt 0 ]]; then
        for model in "${OLLAMA_MODELS[@]}"; do
            cat >> "$litellm_config" << EOF
  - model_name: ollama/${model}
    litellm_params:
      model: ollama/${model}
      api_base: http://ollama:11434
EOF
        done
    fi

    # Add OpenAI if configured
    if [[ -n "${API_KEYS[OPENAI_API_KEY]}" ]]; then
        cat >> "$litellm_config" << 'EOF'
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_key: os.environ/OPENAI_API_KEY
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: os.environ/OPENAI_API_KEY
EOF
    fi

    # Add Anthropic if configured
    if [[ -n "${API_KEYS[ANTHROPIC_API_KEY]}" ]]; then
        cat >> "$litellm_config" << 'EOF'
  - model_name: claude-3-opus
    litellm_params:
      model: claude-3-opus-20240229
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: claude-3-sonnet
    litellm_params:
      model: claude-3-sonnet-20240229
      api_key: os.environ/ANTHROPIC_API_KEY
EOF
    fi

    cat >> "$litellm_config" << 'EOF'

litellm_settings:
  drop_params: true
  set_verbose: false
  success_callback: ["langfuse"]

router_settings:
  routing_strategy: least-busy
  redis_host: redis
  redis_port: 6379
  redis_password: os.environ/REDIS_PASSWORD
EOF

    log_success "LiteLLM configuration generated"
}

################################################################################
# GENERATE PROMETHEUS CONFIG
################################################################################

generate_prometheus_config() {
    [[ "${SELECTED_SERVICES[prometheus]}" != true ]] && return

    log_step "21" "$TOTAL_STEPS" "GENERATING PROMETHEUS CONFIGURATION"

    local prometheus_config="${CONFIG_DIR}/prometheus/prometheus.yml"

    mkdir -p "${CONFIG_DIR}/prometheus"

    cat > "$prometheus_config" << 'EOF'
# Prometheus Configuration
# Auto-generated by Script 1

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'ai-platform'
    environment: 'production'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']

EOF

    # Add cadvisor for container metrics
    cat >> "$prometheus_config" << 'EOF'
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

EOF

    # Add service-specific scrape configs
    if [[ "${SELECTED_SERVICES[ollama]}" == true ]]; then
        cat >> "$prometheus_config" << EOF
  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']

EOF
    fi

    if [[ "${SELECTED_SERVICES[litellm]}" == true ]]; then
        cat >> "$prometheus_config" << EOF
  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']

EOF
    fi

    log_success "Prometheus configuration generated"
}

################################################################################
# GENERATE NGINX CONFIG
################################################################################

generate_nginx_config() {
    [[ "$USE_NGINX" != true ]] && return

    log_step "22" "$TOTAL_STEPS" "GENERATING NGINX CONFIGURATION"

    local nginx_config="${CONFIG_DIR}/nginx/nginx.conf"

    mkdir -p "${CONFIG_DIR}/nginx"

    cat > "$nginx_config" << EOF
# Nginx Configuration
# Auto-generated by Script 1

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=1r/m;

    # Upstream definitions
EOF

    # Add upstream blocks for each service
    for service in "${!SERVICE_PORTS[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]]; then
            cat >> "$nginx_config" << EOF
    upstream ${service}_backend {
        server ${service}:${SERVICE_PORTS[$service]};
    }

EOF
        fi
    done

    cat >> "$nginx_config" << EOF
    # Main server block
    server {
        listen 80;
        server_name ${DOMAIN_NAME};

        # Redirect to HTTPS
        return 301 https://\$server_name\$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name ${DOMAIN_NAME};

        # SSL configuration (use Caddy or Let's Encrypt)
        ssl_certificate /etc/nginx/certs/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        # Root location
        location / {
            return 200 "AI Platform - Service Router";
            add_header Content-Type text/plain;
        }
EOF

    # Add location blocks for each service
    if [[ "${SELECTED_SERVICES[open-webui]}" == true ]]; then
        cat >> "$nginx_config" << EOF

        location /webui/ {
            proxy_pass http://open-webui_backend/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
EOF
    fi

    if [[ "${SELECTED_SERVICES[langfuse]}" == true ]]; then
        cat >> "$nginx_config" << EOF

        location /langfuse/ {
            proxy_pass http://langfuse_backend/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
EOF
    fi

    cat >> "$nginx_config" << 'EOF'
    }
}
EOF

    log_success "Nginx configuration generated"
}

################################################################################
# GENERATE INITIALIZATION SCRIPTS
################################################################################

generate_init_scripts() {
    log_step "23" "$TOTAL_STEPS" "GENERATING INITIALIZATION SCRIPTS"

    # PostgreSQL init script
    if [[ "${SELECTED_SERVICES[postgres]}" == true ]]; then
        local pg_init="${CONFIG_DIR}/postgres/init/01-init-databases.sql"
        mkdir -p "${CONFIG_DIR}/postgres/init"

        cat > "$pg_init" << 'EOF'
-- PostgreSQL Initialization
-- Auto-generated by Script 1

-- Create databases for services
CREATE DATABASE litellm;
CREATE DATABASE langfuse;
CREATE DATABASE n8n;
CREATE DATABASE dify;
CREATE DATABASE open_webui;

-- Enable extensions
\c litellm;
CREATE EXTENSION IF NOT EXISTS vector;

\c langfuse;
CREATE EXTENSION IF NOT EXISTS vector;

\c dify;
CREATE EXTENSION IF NOT EXISTS vector;

\c open_webui;
CREATE EXTENSION IF NOT EXISTS vector;
EOF

        log_success "PostgreSQL init script generated"
    fi

    # Ollama model download script
    if [[ "${SELECTED_SERVICES[ollama]}" == true ]] && [[ ${#OLLAMA_MODELS[@]} -gt 0 ]]; then
        local ollama_init="${SCRIPTS_DIR}/download-ollama-models.sh"

        cat > "$ollama_init" << 'EOF'
#!/bin/bash
# Ollama Model Download Script
# Auto-generated by Script 1

set -euo pipefail

echo "Waiting for Ollama to be ready..."
until curl -s http://localhost:11434/api/version > /dev/null; do
    sleep 5
done

echo "Ollama is ready. Downloading models..."

EOF

        for model in "${OLLAMA_MODELS[@]}"; do
            echo "echo 'Downloading ${model}...'" >> "$ollama_init"
            echo "ollama pull ${model}" >> "$ollama_init"
            echo "" >> "$ollama_init"
        done

        echo 'echo "All models downloaded successfully!"' >> "$ollama_init"

        chmod +x "$ollama_init"
        log_success "Ollama download script generated"
    fi
}

################################################################################
# PART 5 MAIN FUNCTION
################################################################################

main_part5() {
    generate_docker_compose
    generate_litellm_config
    generate_prometheus_config
    generate_nginx_config
    generate_init_scripts

    log_success "Part 5 completed: Configuration files generated"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 5 of Script 1 v${SCRIPT_VERSION} completed${NC}"
    echo -e "${CYAN}  Ready for Part 6: Summary & Main Execution${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute Part 5
main_part5
################################################################################
# CONFIGURATION SUMMARY
################################################################################

show_configuration_summary() {
    log_step "24" "$TOTAL_STEPS" "CONFIGURATION SUMMARY"

    echo ""
    log_header "AI Platform Configuration Summary"

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}SYSTEM INFORMATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo "  Operating System: $OS_TYPE $OS_VERSION"
    echo "  Hostname: $HOSTNAME"
    echo "  CPU Cores: $CPU_CORES"
    echo "  Total RAM: ${TOTAL_RAM_GB}GB"
    echo "  Available Disk: ${AVAILABLE_DISK_GB}GB"

    if [[ "$HAS_GPU" == true ]]; then
        echo "  GPU: ${GPU_TYPE} (${GPU_MODEL})"
        echo "  GPU Memory: ${GPU_MEMORY}"
    else
        echo "  GPU: Not detected"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}NETWORK CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo "  Domain: ${DOMAIN_NAME}"
    echo "  Tailscale: ${HAS_TAILSCALE}"
    if [[ "$HAS_TAILSCALE" == true ]]; then
        echo "  Tailnet: ${TAILNET_NAME}"
        echo "  Tailscale IP: ${TAILSCALE_IP}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}SELECTED SERVICES${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    local service_count=0
    for service in "${!SELECTED_SERVICES[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]]; then
            ((service_count++))
            printf "  %-20s Port: %-6s Status: ${GREEN}ENABLED${NC}\n" \
                   "${service}" "${SERVICE_PORTS[$service]}"
        fi
    done

    echo ""
    echo "  Total Services: ${service_count}"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}OLLAMA MODELS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    if [[ ${#OLLAMA_MODELS[@]} -gt 0 ]]; then
        for model in "${OLLAMA_MODELS[@]}"; do
            echo "  - ${model}"
        done
        echo ""
        echo "  Total Models: ${#OLLAMA_MODELS[@]}"
    else
        echo "  No models selected"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}API INTEGRATIONS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    local api_count=0
    for api in "${!API_KEYS[@]}"; do
        if [[ -n "${API_KEYS[$api]}" ]]; then
            ((api_count++))
            local masked_key="${API_KEYS[$api]:0:8}...${API_KEYS[$api]: -4}"
            echo "  ${api}: ${masked_key}"
        fi
    done

    if [[ $api_count -eq 0 ]]; then
        echo "  No external APIs configured"
    else
        echo ""
        echo "  Total APIs: ${api_count}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}STORAGE CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo "  Base Directory: ${BASE_DIR}"
    echo "  Data Directory: ${DATA_DIR}"
    echo "  Config Directory: ${CONFIG_DIR}"
    echo "  Backup Directory: ${BACKUP_DIR}"
    echo "  Scripts Directory: ${SCRIPTS_DIR}"
    echo "  Logs Directory: ${LOGS_DIR}"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}GENERATED FILES${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo "  Docker Compose: ${CONFIG_DIR}/docker-compose.yml"
    echo "  Environment: ${CONFIG_DIR}/.env"
    echo "  Secrets: ${CONFIG_DIR}/secrets/.secrets.env"
    if [[ "${SELECTED_SERVICES[litellm]}" == true ]]; then
        echo "  LiteLLM Config: ${CONFIG_DIR}/litellm/config.yaml"
    fi
    if [[ "${SELECTED_SERVICES[prometheus]}" == true ]]; then
        echo "  Prometheus Config: ${CONFIG_DIR}/prometheus/prometheus.yml"
    fi
    if [[ "$USE_NGINX" == true ]]; then
        echo "  Nginx Config: ${CONFIG_DIR}/nginx/nginx.conf"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

validate_configuration() {
    log_step "25" "$TOTAL_STEPS" "VALIDATING CONFIGURATION"

    local validation_errors=0

    log_info "Running configuration validation checks..."

    # Check Docker Compose file
    if [[ ! -f "${CONFIG_DIR}/docker-compose.yml" ]]; then
        log_error "Docker Compose file not found"
        ((validation_errors++))
    else
        log_success "Docker Compose file exists"
    fi

    # Check environment file
    if [[ ! -f "${CONFIG_DIR}/.env" ]]; then
        log_error "Environment file not found"
        ((validation_errors++))
    else
        log_success "Environment file exists"
    fi

    # Check secrets file
    if [[ ! -f "${CONFIG_DIR}/secrets/.secrets.env" ]]; then
        log_error "Secrets file not found"
        ((validation_errors++))
    else
        log_success "Secrets file exists"

        # Verify file permissions
        local secrets_perms=$(stat -c %a "${CONFIG_DIR}/secrets/.secrets.env" 2>/dev/null || stat -f %A "${CONFIG_DIR}/secrets/.secrets.env")
        if [[ "$secrets_perms" != "600" ]]; then
            log_warning "Secrets file permissions not secure (expected 600, got ${secrets_perms})"
        else
            log_success "Secrets file permissions verified (600)"
        fi
    fi

    # Validate Docker Compose syntax
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f "${CONFIG_DIR}/docker-compose.yml" config &> /dev/null; then
            log_success "Docker Compose syntax validation passed"
        else
            log_error "Docker Compose syntax validation failed"
            ((validation_errors++))
        fi
    fi

    # Check disk space requirements
    local estimated_space=20  # Base requirement in GB

    # Add space for Ollama models
    for model in "${OLLAMA_MODELS[@]}"; do
        case "$model" in
            *:3b|*:2b) estimated_space=$((estimated_space + 3)) ;;
            *:7b) estimated_space=$((estimated_space + 5)) ;;
            *:13b) estimated_space=$((estimated_space + 8)) ;;
            *:70b) estimated_space=$((estimated_space + 42)) ;;
            *) estimated_space=$((estimated_space + 5)) ;;
        esac
    done

    if [[ $AVAILABLE_DISK_GB -lt $estimated_space ]]; then
        log_warning "Available disk space (${AVAILABLE_DISK_GB}GB) may be insufficient"
        log_warning "Estimated requirement: ${estimated_space}GB"
    else
        log_success "Sufficient disk space available (${AVAILABLE_DISK_GB}GB / ${estimated_space}GB required)"
    fi

    # Check port availability
    log_info "Checking port availability..."
    local port_conflicts=0

    for service in "${!SELECTED_SERVICES[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]]; then
            local port="${SERVICE_PORTS[$service]}"
            if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
                log_warning "Port ${port} (${service}) may be in use"
                ((port_conflicts++))
            fi
        fi
    done

    if [[ $port_conflicts -eq 0 ]]; then
        log_success "No port conflicts detected"
    else
        log_warning "${port_conflicts} potential port conflicts detected"
    fi

    # Summary
    echo ""
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Configuration validation completed successfully"
        return 0
    else
        log_error "Configuration validation failed with ${validation_errors} errors"
        return 1
    fi
}

################################################################################
# GENERATE QUICK START GUIDE
################################################################################

generate_quick_start_guide() {
    log_info "Generating quick start guide..."

    local guide_file="${BASE_DIR}/QUICK_START.md"

    cat > "$guide_file" << EOF
# AI Platform Quick Start Guide

Generated: $(date)
Version: ${SCRIPT_VERSION}

## System Information

- **OS**: ${OS_TYPE} ${OS_VERSION}
- **Hostname**: ${HOSTNAME}
- **Domain**: ${DOMAIN_NAME}
- **GPU**: ${HAS_GPU} ${GPU_MODEL:+(${GPU_MODEL})}

## Services Overview

EOF

    for service in "${!SELECTED_SERVICES[@]}"; do
        if [[ "${SELECTED_SERVICES[$service]}" == true ]]; then
            cat >> "$guide_file" << EOF
### ${service}
- **Port**: ${SERVICE_PORTS[$service]}
- **URL**: https://${DOMAIN_NAME}:${SERVICE_PORTS[$service]}

EOF
        fi
    done

    cat >> "$guide_file" << 'EOF'

## Getting Started

### 1. Start the Platform

```bash
cd ~/ai-platform
docker-compose up -d
