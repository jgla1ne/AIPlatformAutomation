#!/usr/bin/env bash

#==============================================================================
# Script: 1-setup-system.sh
# Version: 4.0.0 - ARCHITECTURE COMPLIANCE REFACTOR
# Description: System setup ONLY (hardware, Docker, NVIDIA, Ollama, models)
# Purpose: Prepares system for AI Platform deployment
# Flow: 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add-service
#
# SCOPE (Script 1 ONLY):
#   ✅ Hardware detection & profiling
#   ✅ Docker Engine + Docker Compose installation
#   ✅ NVIDIA Container Toolkit installation (if GPU detected)
#   ✅ Ollama installation & configuration
#   ✅ Default model pull based on system tier
#   ✅ Validation & handoff to Script 2
#
# OUT OF SCOPE (belongs in Script 2):
#   ❌ Service selection (LiteLLM, Dify, N8N, etc.)
#   ❌ Domain configuration
#   ❌ SSL/TLS setup
#   ❌ API key collection
#   ❌ Credential generation
#   ❌ .env file generation (full)
#   ❌ Docker Compose file generation
#   ❌ Docker network creation
#   ❌ LiteLLM configuration
#==============================================================================

set -euo pipefail

#==============================================================================
# SCRIPT LOCATION & USER DETECTION
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect real user (works with sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
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
# GLOBAL CONFIGURATION (per AI Platform Guide v76.3.0)
#==============================================================================

# Directories (FIXED: /mnt/data/ai-platform per README Section 1.5)
ROOT_PATH="/mnt/data/ai-platform"
CONFIG_PATH="${ROOT_PATH}/config"
DOCKER_PATH="${ROOT_PATH}/docker"
DATA_PATH="${ROOT_PATH}/data"
LOG_PATH="${ROOT_PATH}/logs"
SCRIPTS_PATH="${ROOT_PATH}/scripts"
BACKUP_PATH="${ROOT_PATH}/backups"

# Configuration files
HARDWARE_PROFILE="${CONFIG_PATH}/hardware-profile.env"
STATE_FILE="${ROOT_PATH}/.setup-state"

# Logging
LOGFILE="${LOG_PATH}/script-1-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="${LOG_PATH}/script-1-errors-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Setup phases tracking (ONLY Script 1 phases)
declare -A SETUP_PHASES
SETUP_PHASES[preflight]=0
SETUP_PHASES[docker]=0
SETUP_PHASES[nvidia_toolkit]=0
SETUP_PHASES[ollama_install]=0
SETUP_PHASES[ollama_models]=0
SETUP_PHASES[validation]=0

# System detection variables (will be populated by detect_hardware)
OS=""
OS_VERSION=""
ARCH=""
CPU_CORES=""
CPU_MODEL=""
TOTAL_RAM_GB=""
DISK_FREE_GB=""
DISK_TOTAL_GB=""
DISK_TYPE=""
GPU_AVAILABLE="false"
GPU_MODEL="none"
GPU_VRAM_MB="0"
GPU_DRIVER_VERSION="none"
SYSTEM_TIER=""
DEFAULT_MODELS=""

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    local msg="$1"
    echo -e "${BLUE}ℹ${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}" >> "${LOGFILE}" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: ${msg}" >> "${LOGFILE}" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}⚠${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "${LOGFILE}" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "${ERROR_LOG}" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "${LOGFILE}" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "${ERROR_LOG}" 2>/dev/null || true
}

log_section() {
    local section="$1"
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${section}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECTION: ${section}" >> "${LOGFILE}" 2>/dev/null || true
}

#==============================================================================
# STATE MANAGEMENT
#==============================================================================

save_state() {
    local phase="$1"
    SETUP_PHASES[${phase}]=1
    
    if [[ -d "$(dirname "${STATE_FILE}")" ]]; then
        {
            for key in "${!SETUP_PHASES[@]}"; do
                echo "${key}=${SETUP_PHASES[${key}]}"
            done
        } > "${STATE_FILE}"
    fi
}

load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Loading previous setup state..."
        while IFS='=' read -r key value; do
            if [[ -n "${key}" ]]; then
                SETUP_PHASES[${key}]=${value}
            fi
        done < "${STATE_FILE}"
    fi
}

#==============================================================================
# BANNER
#==============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       ${YELLOW}AI PLATFORM AUTOMATION - SCRIPT 1: SYSTEM SETUP${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                      ${GREEN}Version 4.0.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Repository root: ${REPO_ROOT}"
    echo "Running as user: ${REAL_USER}"
    echo ""
}

#==============================================================================
# PHASE 0: PREFLIGHT CHECKS
#==============================================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="${ID}"
        OS_VERSION="${VERSION_ID}"
    else
        OS="unknown"
        OS_VERSION="unknown"
    fi
    
    ARCH=$(uname -m)
}

detect_hardware() {
    log_section "Phase 1: Hardware Detection & Profiling"
    
    if [[ ${SETUP_PHASES[preflight]} -eq 1 ]]; then
        log_info "Hardware already detected — skipping"
        # Load from hardware-profile.env if exists
        if [[ -f "${HARDWARE_PROFILE}" ]]; then
            source "${HARDWARE_PROFILE}"
        fi
        return 0
    fi
    
    # CPU Detection
    if command -v nproc &>/dev/null; then
        CPU_CORES=$(nproc)
    else
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    fi
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
    log_info "CPU: ${CPU_MODEL} (${CPU_CORES} cores)"
    
    # RAM Detection (in GB)
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((total_ram_kb / 1024 / 1024))
    log_info "RAM: ${TOTAL_RAM_GB} GB"
    
    # Disk Detection (in GB)
    DISK_FREE_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    DISK_TOTAL_GB=$(df -BG / | tail -1 | awk '{print $2}' | tr -d 'G')
    
    # Disk Type (SSD vs HDD)
    local root_device
    root_device=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | xargs basename 2>/dev/null || echo "unknown")
    DISK_TYPE="unknown"
    if [[ -f "/sys/block/${root_device}/queue/rotational" ]]; then
        if [[ $(cat "/sys/block/${root_device}/queue/rotational") == "0" ]]; then
            DISK_TYPE="ssd"
        else
            DISK_TYPE="hdd"
        fi
    fi
    log_info "Disk: ${DISK_FREE_GB} GB free / ${DISK_TOTAL_GB} GB total (${DISK_TYPE})"
    
    # GPU Detection
    GPU_AVAILABLE="false"
    GPU_MODEL="none"
    GPU_VRAM_MB="0"
    GPU_DRIVER_VERSION="none"
    
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            GPU_AVAILABLE="true"
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs)
            GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | xargs)
            GPU_DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs)
            log_info "GPU: ${GPU_MODEL} (${GPU_VRAM_MB} MB VRAM, driver ${GPU_DRIVER_VERSION})"
        fi
    fi
    
    if [[ "${GPU_AVAILABLE}" == "false" ]]; then
        log_info "GPU: None detected — CPU-only mode"
    fi
    
    save_state "preflight"
    log_success "Hardware detection completed"
}

classify_system_tier() {
    log_info "Classifying system tier based on resources..."
    
    # Tier determines default model selection
    if [[ "${GPU_AVAILABLE}" == "true" && "${GPU_VRAM_MB}" -ge 16000 && "${TOTAL_RAM_GB}" -ge 32 ]]; then
        SYSTEM_TIER="performance"
        DEFAULT_MODELS="llama3.1:8b,nomic-embed-text,codellama:13b"
        log_info "System tier: PERFORMANCE (GPU: ${GPU_VRAM_MB}MB VRAM, ${TOTAL_RAM_GB}GB RAM)"
        log_info "Default models: ${DEFAULT_MODELS}"
    elif [[ "${GPU_AVAILABLE}" == "true" && "${GPU_VRAM_MB}" -ge 6000 && "${TOTAL_RAM_GB}" -ge 16 ]]; then
        SYSTEM_TIER="standard"
        DEFAULT_MODELS="llama3.1:8b,nomic-embed-text"
        log_info "System tier: STANDARD (GPU: ${GPU_VRAM_MB}MB VRAM, ${TOTAL_RAM_GB}GB RAM)"
        log_info "Default models: ${DEFAULT_MODELS}"
    else
        SYSTEM_TIER="minimal"
        DEFAULT_MODELS="llama3.2:3b,nomic-embed-text"
        log_info "System tier: MINIMAL (CPU-only or low resources)"
        log_info "Default models: ${DEFAULT_MODELS}"
    fi
}

write_hardware_profile() {
    log_info "Writing hardware profile..."
    
    mkdir -p "${CONFIG_PATH}"
    
    cat > "${HARDWARE_PROFILE}" << EOF
# Hardware Profile — Generated by 1-setup-system.sh
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

CPU_CORES=${CPU_CORES}
CPU_MODEL="${CPU_MODEL}"
TOTAL_RAM_GB=${TOTAL_RAM_GB}
DISK_FREE_GB=${DISK_FREE_GB}
DISK_TOTAL_GB=${DISK_TOTAL_GB}
DISK_TYPE=${DISK_TYPE}
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_MODEL="${GPU_MODEL}"
GPU_VRAM_MB=${GPU_VRAM_MB}
GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION}"
SYSTEM_TIER=${SYSTEM_TIER}
DEFAULT_MODELS="${DEFAULT_MODELS}"
EOF
    
    log_success "Hardware profile written to ${HARDWARE_PROFILE}"
}

preflight_checks() {
    detect_os
    detect_hardware
    classify_system_tier
    write_hardware_profile
    
    # Display summary
    echo ""
    echo "▶ System Information:"
    echo "  • OS: ${OS} ${OS_VERSION}"
    echo "  • Architecture: ${ARCH}"
    echo "  • CPU: ${CPU_CORES} cores"
    echo "  • RAM: ${TOTAL_RAM_GB}GB"
    echo "  • Disk: ${DISK_FREE_GB}GB free (${DISK_TYPE})"
    echo "  • GPU: ${GPU_MODEL}"
    echo "  • System Tier: ${SYSTEM_TIER}"
    echo ""
    
    # Check supported OS
    case "${OS}" in
        ubuntu|debian)
            log_success "Operating system supported: ${OS}"
            ;;
        *)
            log_warning "Untested operating system: ${OS}"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
    
    # Check internet connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_success "Internet connectivity verified"
    else
        log_error "No internet connectivity — required for downloads"
        exit 1
    fi
}

#==============================================================================
# PHASE 2: DOCKER ENGINE INSTALLATION
#==============================================================================

install_docker() {
    log_section "Phase 2: Docker Engine Installation"
    
    if [[ ${SETUP_PHASES[docker]} -eq 1 ]]; then
        log_info "Docker already installed — skipping"
        return 0
    fi
    
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        local docker_version
        docker_version=$(docker --version)
        log_info "Docker already installed: ${docker_version}"
        
        # Ensure user is in docker group
        if ! groups "${REAL_USER}" | grep -q docker; then
            log_info "Adding ${REAL_USER} to docker group..."
            usermod -aG docker "${REAL_USER}"
            log_success "User added to docker group (logout/login required)"
        fi
        
        save_state "docker"
        return 0
    fi
    
    log_info "Installing Docker Engine..."
    
    case "${OS}" in
        ubuntu|debian)
            # Remove conflicting packages
            log_info "Removing conflicting packages..."
            apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 \
                podman-docker containerd runc 2>/dev/null || true
            
            # Install prerequisites
            log_info "Installing prerequisites..."
            apt-get update -y
            apt-get install -y ca-certificates curl gnupg lsb-release
            
            # Add Docker GPG key
            log_info "Adding Docker GPG key..."
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS}/gpg | \
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add Docker repository
            log_info "Adding Docker repository..."
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
              $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            log_info "Installing Docker packages..."
            apt-get update -y
            apt-get install -y \
                docker-ce \
                docker-ce-cli \
                containerd.io \
                docker-buildx-plugin \
                docker-compose-plugin
            ;;
        *)
            log_error "Unsupported OS for Docker installation: ${OS}"
            exit 1
            ;;
    esac
    
    # Add user to docker group
    usermod -aG docker "${REAL_USER}"
    
    # Configure Docker daemon
    log_info "Configuring Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.20.0.0/14",
      "size": 24
    }
  ]
}
EOF
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    # Verify installation
    if docker info &>/dev/null && docker compose version &>/dev/null; then
        log_success "Docker installed: $(docker --version)"
        log_success "Docker Compose: $(docker compose version)"
        log_warning "User ${REAL_USER} added to docker group — logout/login required"
    else
        log_error "Docker installation verification failed"
        exit 1
    fi
    
    save_state "docker"
}

#==============================================================================
# PHASE 3: NVIDIA CONTAINER TOOLKIT (if GPU detected)
#==============================================================================

install_nvidia_toolkit() {
    log_section "Phase 3: NVIDIA Container Toolkit"
    
    # Skip if no GPU
    if [[ "${GPU_AVAILABLE}" != "true" ]]; then
        log_info "No GPU detected — skipping NVIDIA Container Toolkit"
        save_state "nvidia_toolkit"
        return 0
    fi
    
    if [[ ${SETUP_PHASES[nvidia_toolkit]} -eq 1 ]]; then
        log_info "NVIDIA Container Toolkit already installed — skipping"
        return 0
    fi
    
    # Idempotency check
    if dpkg -l | grep -q nvidia-container-toolkit && \
       docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_info "NVIDIA Container Toolkit already installed and working"
        save_state "nvidia_toolkit"
        return 0
    fi
    
    # Verify NVIDIA driver is present
    if ! nvidia-smi &>/dev/null; then
        log_error "NVIDIA driver not installed. Install GPU drivers first:"
        log_error "  sudo apt install nvidia-driver-535 (or appropriate version)"
        exit 1
    fi
    
    log_info "Adding NVIDIA Container Toolkit repository..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    log_info "Installing nvidia-container-toolkit..."
    apt-get update -y
    apt-get install -y nvidia-container-toolkit
    
    log_info "Configuring NVIDIA Docker runtime..."
    nvidia-ctk runtime configure --runtime=docker
    
    # Restart Docker to apply runtime changes
    systemctl restart docker
    
    # Test GPU passthrough
    log_info "Testing GPU passthrough..."
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi; then
        log_success "GPU passthrough test PASSED"
    else
        log_error "GPU passthrough test FAILED"
        exit 1
    fi
    
    save_state "nvidia_toolkit"
    log_success "NVIDIA Container Toolkit installed and configured"
}

#==============================================================================
# PHASE 4: OLLAMA INSTALLATION & MODEL PULL
#==============================================================================

install_ollama() {
    log_section "Phase 4: Ollama Installation"
    
    if [[ ${SETUP_PHASES[ollama_install]} -eq 1 ]]; then
        log_info "Ollama already installed — skipping"
        return 0
    fi
    
    # Idempotency check
    if command -v ollama &>/dev/null && systemctl is-active --quiet ollama; then
        log_info "Ollama already installed and running"
        configure_ollama_env
        save_state "ollama_install"
        return 0
    fi
    
    # Install via official script
    log_info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Configure environment
    configure_ollama_env
    
    # Handle AppArmor if active
    configure_ollama_apparmor
    
    # Start and enable
    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama
    
    # Wait for API to respond
    wait_for_ollama
    
    save_state "ollama_install"
    log_success "Ollama installed and running"
}

configure_ollama_env() {
    log_info "Configuring Ollama environment..."
    
    # Create override directory
    mkdir -p /etc/systemd/system/ollama.service.d
    
    # Detect host IP for container access
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    
    cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_KEEP_ALIVE=5m"
EOF
    
    systemctl daemon-reload
    log_info "Ollama configured: listening on 0.0.0.0:11434"
}

configure_ollama_apparmor() {
    # Check if AppArmor is active
    if ! command -v aa-status &>/dev/null; then
        log_info "AppArmor not installed — skipping"
        return 0
    fi
    
    if ! aa-status --enabled 2>/dev/null; then
        log_info "AppArmor not enabled — skipping"
        return 0
    fi
    
    log_info "Configuring AppArmor for Ollama..."
    
    # Check if Ollama is being blocked by AppArmor
    if aa-status 2>/dev/null | grep -q ollama; then
        log_info "Ollama AppArmor profile already exists"
        return 0
    fi
    
    # Create permissive profile for Ollama
    cat > /etc/apparmor.d/usr.local.bin.ollama << 'EOF'
#include <tunables/global>

/usr/local/bin/ollama flags=(unconfined) {
    userns,
}
EOF
    
    # Reload AppArmor
    apparmor_parser -r /etc/apparmor.d/usr.local.bin.ollama 2>/dev/null || true
    log_info "AppArmor profile configured for Ollama"
}

wait_for_ollama() {
    log_info "Waiting for Ollama API..."
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            log_success "Ollama API is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "Ollama API did not respond after ${max_attempts} attempts"
    exit 1
}

pull_ollama_models() {
    log_section "Phase 5: Pulling Ollama Models"
    
    if [[ ${SETUP_PHASES[ollama_models]} -eq 1 ]]; then
        log_info "Models already pulled — skipping"
        return 0
    fi
    
    # DEFAULT_MODELS is set by classify_system_tier()
    IFS=',' read -ra MODELS <<< "${DEFAULT_MODELS}"
    
    for model in "${MODELS[@]}"; do
        model=$(echo "${model}" | xargs)  # trim whitespace
        log_info "Pulling model: ${model}..."
        
        # Check if already pulled
        if ollama list 2>/dev/null | grep -q "^${model}"; then
            log_success "Model ${model} already available"
            continue
        fi
        
        if ollama pull "${model}"; then
            log_success "Model ${model} pulled successfully"
        else
            log_warning "Failed to pull model ${model} — continuing"
        fi
    done
    
    # List all available models
    echo ""
    log_info "Available models:"
    ollama list
    echo ""
    
    save_state "ollama_models"
    log_success "Model pull completed"
}

#==============================================================================
# PHASE 6: VALIDATION & HANDOFF
#==============================================================================

validate_system() {
    log_section "Phase 6: System Validation"
    
    if [[ ${SETUP_PHASES[validation]} -eq 1 ]]; then
        log_info "Validation already completed — skipping"
        return 0
    fi
    
    local errors=0
    
    echo "▶ Verifying installation..."
    echo ""
    
    # Docker daemon
    if docker info &>/dev/null; then
        log_success "✓ Docker daemon running"
    else
        log_error "✗ Docker daemon not running"
        errors=$((errors + 1))
    fi
    
    # Docker Compose
    if docker compose version &>/dev/null; then
        log_success "✓ Docker Compose available"
    else
        log_error "✗ Docker Compose not available"
        errors=$((errors + 1))
    fi
    
    # GPU (if detected)
    if [[ "${GPU_AVAILABLE}" == "true" ]]; then
        if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
            log_success "✓ GPU passthrough working"
        else
            log_error "✗ GPU passthrough failed"
            errors=$((errors + 1))
        fi
    fi
    
    # Ollama
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_success "✓ Ollama API responding"
    else
        log_error "✗ Ollama API not responding"
        errors=$((errors + 1))
    fi
    
    # Models
    local model_count
    model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
    if [[ "${model_count}" -gt 0 ]]; then
        log_success "✓ ${model_count} model(s) available"
    else
        log_warning "⚠ No models available (pull may have failed)"
    fi
    
    # Directory structure
    if [[ -d "${ROOT_PATH}/config" && -d "${ROOT_PATH}/docker" && -d "${ROOT_PATH}/data" ]]; then
        log_success "✓ Directory structure intact"
    else
        log_error "✗ Directory structure incomplete"
        errors=$((errors + 1))
    fi
    
    # Hardware profile
    if [[ -f "${HARDWARE_PROFILE}" ]]; then
        log_success "✓ Hardware profile saved"
    else
        log_error "✗ Hardware profile missing"
        errors=$((errors + 1))
    fi
    
    echo ""
    
    if [[ ${errors} -eq 0 ]]; then
        save_state "validation"
        log_section "VALIDATION PASSED — System Ready for Deployment"
        print_summary
    else
        log_error "VALIDATION FAILED — ${errors} error(s) found"
        log_error "Fix the issues above and re-run this script"
        exit 1
    fi
}

print_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}               ${GREEN}✓ SCRIPT 1 COMPLETED SUCCESSFULLY!${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 System Setup Summary"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "  Hardware Profile:"
    echo "    • System Tier: ${SYSTEM_TIER}"
    echo "    • CPU: ${CPU_CORES} cores"
    echo "    • RAM: ${TOTAL_RAM_GB}GB"
    echo "    • Disk: ${DISK_FREE_GB}GB free (${DISK_TYPE})"
    echo "    • GPU: ${GPU_MODEL}"
    echo ""
    echo "  Installed Components:"
    echo "    ✓ Docker Engine $(docker --version | cut -d' ' -f3)"
    echo "    ✓ Docker Compose $(docker compose version --short)"
    [[ "${GPU_AVAILABLE}" == "true" ]] && echo "    ✓ NVIDIA Container Toolkit"
    echo "    ✓ Ollama (systemd service on port 11434)"
    echo "    ✓ Models: ${DEFAULT_MODELS}"
    echo ""
    echo "  Generated Files:"
    echo "    • Hardware Profile: ${HARDWARE_PROFILE}"
    echo "    • Setup Log: ${LOGFILE}"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "🚀 Next Step:"
    echo ""
    echo "  Run Script 2 to deploy the platform:"
    echo ""
    echo "    ${GREEN}sudo bash 2-deploy-platform.sh${NC}"
    echo ""
    echo "  Script 2 will:"
    echo "    • Run interactive questionnaire (domain, SSL, providers, services)"
    echo "    • Generate all credentials and secrets"
    echo "    • Generate master.env with all configuration"
    echo "    • Generate docker-compose files for all services"
    echo "    • Deploy all containers"
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    print_banner
    
    # Root check (FIXED: proper bash [[...]] syntax per v97.0.0)
    if [[ ${EUID} -ne 0 ]]; then
        echo "❌ This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Create initial directory structure
    log_info "Creating directory structure..."
    mkdir -p "${ROOT_PATH}"/{config,docker,data,logs,scripts,backups}
    mkdir -p "${LOG_PATH}"
    
    # Load state if exists
    load_state
    
    log_info "Starting AI Platform Setup — Script 1 (System Setup) v4.0.0"
    log_info "Executed by: ${REAL_USER} (UID: ${REAL_UID})"
    log_info "Script directory: ${SCRIPT_DIR}"
    echo ""
    
    # Execute setup phases (ONLY Script 1 scope)
    preflight_checks
    install_docker
    install_nvidia_toolkit
    install_ollama
    pull_ollama_models
    validate_system
    
    log_success "Script 1 completed successfully!"
    exit 0
}

# Trap errors
trap 'log_error "Script failed at line ${LINENO} with exit code $?"' ERR

# Run main function
main "$@"

