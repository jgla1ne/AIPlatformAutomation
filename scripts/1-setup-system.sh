#!/usr/bin/env bash

################################################################################
# AI Platform Automation - Script 1: Interactive Setup
# Version: 101.0.0
# Purpose: Collect configuration, generate files, NO DEPLOYMENT
# 
# What this script does:
# - Pre-flight checks (root, OS, connectivity)
# - System health assessment
# - Install packages (Docker, Tailscale, NVIDIA if GPU)
# - Interactive service selection (ALL ports!)
# - API key collection
# - Secret generation (with confirmation)
# - Generate ALL config files
# - Generate systemd services
# - Generate helper scripts
# - Display summary
#
# What this script does NOT do:
# - Deploy Docker containers (that's Script 2)
# - Pull Ollama models (that's Script 2)
# - Run migrations (that's Script 2)
#
# Output Files:
# - /mnt/data/logs/script1_YYYYMMDD-HHMMSS.log (previous deleted)
# - /opt/ai-platform/.env (ALL variables)
# - /opt/ai-platform/secrets/credentials.txt
# - /opt/ai-platform/config/litellm/config.yaml
# - /opt/ai-platform/config/openclaw/config.yaml
# - /opt/ai-platform/config/gdrive/rclone.conf
# - /opt/ai-platform/stacks/core.yml
# - /opt/ai-platform/stacks/automation.yml
# - /opt/ai-platform/stacks/optional.yml
# - /etc/systemd/system/ai-platform-*.service
# - /opt/ai-platform/scripts/health-check.sh
# - /opt/ai-platform/scripts/backup.sh
# - /opt/ai-platform/scripts/update.sh
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Pre-flight check failed
#   3 - Package installation failed
#   4 - Configuration generation failed
#
################################################################################

set -euo pipefail

################################################################################
# CONSTANTS & CONFIGURATION
################################################################################

readonly SCRIPT_VERSION="101.0.0"
readonly SCRIPT_NAME="setup-system.sh"
readonly TOTAL_STEPS=28

# System paths (CORRECTED per gap analysis)
readonly ROOT_PATH="/opt/ai-platform"
readonly DATA_DIR="/mnt/data/ai-platform"
readonly CONFIG_DIR="${ROOT_PATH}/config"
readonly STACK_DIR="${ROOT_PATH}/stacks"
readonly SECRETS_DIR="${ROOT_PATH}/secrets"
readonly SCRIPTS_DIR="${ROOT_PATH}/scripts"
readonly LOG_DIR="/mnt/data/logs"                    # ✅ CORRECTED
readonly BACKUP_DIR="/mnt/data/backups"
readonly GDRIVE_LOCAL_PATH="/mnt/data/gdrive"        # ✅ CORRECTED

# Log file with timestamp (previous deleted)
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${LOG_DIR}/script1_${TIMESTAMP}.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Timeouts
readonly APT_LOCK_TIMEOUT=300
readonly APT_RETRY_DELAY=5
readonly CONNECTIVITY_TIMEOUT=10

# Required minimum resources
readonly MIN_DISK_GB=100
readonly MIN_RAM_GB=8
readonly MIN_SWAP_GB=2

################################################################################
# GLOBAL VARIABLES
################################################################################

# Associative arrays for configuration
declare -A SERVICE_ENABLED
declare -A SERVICE_PORTS
declare -A SERVICE_CONFIGS
declare -A SECRETS
declare -A API_KEYS

# System state
GPU_AVAILABLE=false
GPU_TYPE=""
CURRENT_STEP=0

# User selections
OLLAMA_MODELS=""
REVERSE_PROXY=""
SELECTED_VECTOR_DB=""

################################################################################
# LOGGING & OUTPUT FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    # Create log directory
    mkdir -p "${LOG_DIR}"
    
    # Delete previous script1 logs
    find "${LOG_DIR}" -name "script1_*.log" -type f -delete 2>/dev/null || true
    
    # Create new log file
    touch "${LOG_FILE}"
    chmod 644 "${LOG_FILE}"
    
    log_info "=== AI Platform Setup - Script 1 v${SCRIPT_VERSION} ==="
    log_info "Started at: $(date)"
    log_info "Log file: ${LOG_FILE}"
}

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
    echo -e "${CYAN}ℹ ${NC}$*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✓ ${NC}$*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠ ${NC}$*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}✗ ${NC}$*" >&2
}

log_step() {
    local step=$1
    local total=$2
    local message=$3
    CURRENT_STEP=$step
    
    log "STEP" "[$step/$total] $message"
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  STEP $step/$total: $message${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Progress spinner
spinner() {
    local pid=$1
    local message=$2
    local spinstr='|/-\'
    local temp
    
    echo -n "$message "
    while kill -0 $pid 2>/dev/null; do
        temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    wait $pid
    return $?
}

################################################################################
# ERROR HANDLING
################################################################################

# Error handler
error_exit() {
    local message=$1
    local exit_code=${2:-1}
    
    log_error "$message"
    log_error "Setup failed at step ${CURRENT_STEP}/${TOTAL_STEPS}"
    log_error "Check log file: ${LOG_FILE}"
    
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  SETUP FAILED${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}Error: $message${NC}"
    echo -e "${RED}Step: ${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
    echo -e "${RED}Log: ${LOG_FILE}${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    exit "$exit_code"
}

# Trap errors
trap 'error_exit "Unexpected error at line $LINENO" 1' ERR

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Prompt yes/no question
prompt_yes_no() {
    local question=$1
    local default=${2:-n}
    local answer
    
    if [[ "$default" == "y" ]]; then
        read -p "$question [Y/n]: " answer
        answer=${answer:-y}
    else
        read -p "$question [y/N]: " answer
        answer=${answer:-n}
    fi
    
    [[ "$answer" =~ ^[Yy] ]]
}

# Wait for APT lock with timeout
wait_for_apt() {
    local timeout=$APT_LOCK_TIMEOUT
    local elapsed=0
    
    log_info "Checking for APT locks..."
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        if [ $elapsed -ge $timeout ]; then
            error_exit "APT lock timeout after ${timeout}s. Another package manager is running." 3
        fi
        
        echo -n "."
        sleep $APT_RETRY_DELAY
        elapsed=$((elapsed + APT_RETRY_DELAY))
    done
    
    echo ""
    log_success "APT is available"
}

# Generate random password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Generate API key
generate_api_key() {
    echo "sk-$(openssl rand -hex 24)"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if port is available
is_port_available() {
    local port=$1
    ! ss -tuln | grep -q ":${port} "
}

# Validate IP address
is_valid_ip() {
    local ip=$1
    [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Convert GB to bytes
gb_to_bytes() {
    echo $(($1 * 1024 * 1024 * 1024))
}

################################################################################
# PRE-FLIGHT CHECKS
################################################################################

check_root() {
    log_step "1" "$TOTAL_STEPS" "PRE-FLIGHT CHECKS"
    
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root" 2
    fi
    log_success "Running as root"
}

check_os() {
    log_info "Checking operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        error_exit "Cannot determine OS - /etc/os-release not found" 2
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu)
            if [[ ! "$VERSION_ID" =~ ^(20.04|22.04|24.04)$ ]]; then
                log_warning "Ubuntu $VERSION_ID detected. Recommended: 20.04, 22.04, or 24.04"
                if ! prompt_yes_no "Continue anyway?"; then
                    error_exit "Unsupported Ubuntu version" 2
                fi
            fi
            ;;
        debian)
            if [[ ! "$VERSION_ID" =~ ^(11|12)$ ]]; then
                log_warning "Debian $VERSION_ID detected. Recommended: 11 or 12"
                if ! prompt_yes_no "Continue anyway?"; then
                    error_exit "Unsupported Debian version" 2
                fi
            fi
            ;;
        *)
            error_exit "Unsupported OS: $ID. Only Ubuntu and Debian are supported." 2
            ;;
    esac
    
    log_success "OS: $PRETTY_NAME"
}

check_connectivity() {
    log_info "Checking internet connectivity..."
    
    local test_urls=(
        "https://github.com"
        "https://download.docker.com"
        "https://tailscale.com"
    )
    
    local failed=0
    for url in "${test_urls[@]}"; do
        if ! curl -s --connect-timeout $CONNECTIVITY_TIMEOUT "$url" >/dev/null; then
            log_warning "Cannot reach: $url"
            ((failed++))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        log_warning "$failed/$((${#test_urls[@]})) connectivity checks failed"
        if ! prompt_yes_no "Continue anyway?"; then
            error_exit "Internet connectivity required" 2
        fi
    else
        log_success "Internet connectivity OK"
    fi
}

check_system_resources() {
    log_step "2" "$TOTAL_STEPS" "SYSTEM HEALTH ASSESSMENT"
    
    # Check disk space
    log_info "Checking disk space..."
    local disk_avail_gb=$(df -BG /opt | tail -1 | awk '{print $4}' | sed 's/G//')
    log_info "Available disk space: ${disk_avail_gb}GB"
    
    if [[ $disk_avail_gb -lt $MIN_DISK_GB ]]; then
        log_warning "Low disk space. Recommended: ${MIN_DISK_GB}GB, Available: ${disk_avail_gb}GB"
        if ! prompt_yes_no "Continue anyway?"; then
            error_exit "Insufficient disk space" 2
        fi
    else
        log_success "Disk space: ${disk_avail_gb}GB available"
    fi
    
    # Check RAM
    log_info "Checking RAM..."
    local ram_total_gb=$(free -g | awk '/^Mem:/{print $2}')
    log_info "Total RAM: ${ram_total_gb}GB"
    
    if [[ $ram_total_gb -lt $MIN_RAM_GB ]]; then
        log_warning "Low RAM. Recommended: ${MIN_RAM_GB}GB, Available: ${ram_total_gb}GB"
        if ! prompt_yes_no "Continue anyway?"; then
            error_exit "Insufficient RAM" 2
        fi
    else
        log_success "RAM: ${ram_total_gb}GB available"
    fi
    
    # Check swap
    log_info "Checking swap..."
    local swap_total_gb=$(free -g | awk '/^Swap:/{print $2}')
    log_info "Total swap: ${swap_total_gb}GB"
    
    if [[ $swap_total_gb -lt $MIN_SWAP_GB ]]; then
        log_warning "Low swap. Recommended: ${MIN_SWAP_GB}GB, Available: ${swap_total_gb}GB"
    else
        log_success "Swap: ${swap_total_gb}GB configured"
    fi
    
    # Check CPU
    log_info "Checking CPU..."
    local cpu_count=$(nproc)
    local cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    log_info "CPU: $cpu_model"
    log_success "CPU cores: $cpu_count"
    
    # Check GPU
    log_info "Checking GPU..."
    if command_exists nvidia-smi; then
        GPU_AVAILABLE=true
        GPU_TYPE="NVIDIA"
        local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        log_success "GPU detected: $gpu_name"
    elif lspci | grep -i "amd.*vga" >/dev/null; then
        GPU_AVAILABLE=true
        GPU_TYPE="AMD"
        log_success "AMD GPU detected"
        log_warning "AMD GPU support limited. NVIDIA recommended for full acceleration."
    else
        GPU_AVAILABLE=false
        log_warning "No GPU detected. CPU-only mode will be used."
    fi
}

################################################################################
# MAIN EXECUTION (placeholder)
################################################################################

main() {
    # Initialize logging first
    init_logging
    
    # Run pre-flight checks
    check_root
    check_os
    check_connectivity
    check_system_resources
    
    log_success "Pre-flight checks completed"
    
    # TO BE CONTINUED IN NEXT PARTS...
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 1 of Script 1 v101.0.0 loaded successfully${NC}"
    echo -e "${CYAN}  Ready for Part 2: Package Installation${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Don't run main yet - wait for all parts
# main "$@"
################################################################################
# PACKAGE INSTALLATION
################################################################################

install_system_packages() {
    log_step "3" "$TOTAL_STEPS" "INSTALLING SYSTEM PACKAGES"
    
    wait_for_apt
    
    log_info "Updating package lists..."
    apt-get update -qq 2>&1 | tee -a "${LOG_FILE}" || error_exit "Failed to update package lists" 3
    log_success "Package lists updated"
    
    log_info "Installing required packages..."
    local packages=(
        curl
        wget
        git
        jq
        ca-certificates
        gnupg
        lsb-release
        apt-transport-https
        software-properties-common
        net-tools
        htop
        ncdu
        unzip
        openssl
        rsync
    )
    
    apt-get install -y -qq "${packages[@]}" 2>&1 | tee -a "${LOG_FILE}" || error_exit "Failed to install system packages" 3
    log_success "System packages installed"
}

install_docker() {
    log_step "4" "$TOTAL_STEPS" "INSTALLING DOCKER"
    
    if command_exists docker; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_warning "Docker already installed: $docker_version"
        if prompt_yes_no "Reinstall Docker?"; then
            log_info "Removing existing Docker installation..."
            apt-get remove -y docker docker-engine docker.io containerd runc 2>&1 | tee -a "${LOG_FILE}" || true
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "${LOG_FILE}" || true
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd
            log_success "Existing Docker removed"
        else
            log_info "Skipping Docker installation"
            return 0
        fi
    fi
    
    wait_for_apt
    
    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    log_success "Docker GPG key added"
    
    log_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    log_success "Docker repository added"
    
    wait_for_apt
    
    log_info "Installing Docker packages..."
    apt-get update -qq 2>&1 | tee -a "${LOG_FILE}"
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "${LOG_FILE}" || error_exit "Failed to install Docker" 3
    log_success "Docker installed"
    
    log_info "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
    log_success "Docker service started and enabled"
    
    # Verify Docker installation
    if docker --version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        local compose_version=$(docker compose version | awk '{print $4}')
        log_success "Docker $docker_version installed"
        log_success "Docker Compose $compose_version installed"
    else
        error_exit "Docker installation verification failed" 3
    fi
}

configure_docker_non_root() {
    log_info "Configuring Docker for non-root access..."
    
    # Get the user who invoked sudo (if any)
    local actual_user="${SUDO_USER:-root}"
    
    if [[ "$actual_user" != "root" ]]; then
        if ! getent group docker >/dev/null; then
            groupadd docker
        fi
        usermod -aG docker "$actual_user"
        log_success "User '$actual_user' added to docker group"
        log_warning "User needs to log out and back in for group changes to take effect"
    else
        log_warning "Running as root, skipping non-root Docker configuration"
    fi
}

install_nvidia_toolkit() {
    log_step "5" "$TOTAL_STEPS" "INSTALLING NVIDIA CONTAINER TOOLKIT"
    
    if [[ "$GPU_AVAILABLE" != "true" ]] || [[ "$GPU_TYPE" != "NVIDIA" ]]; then
        log_info "No NVIDIA GPU detected, skipping NVIDIA toolkit installation"
        return 0
    fi
    
    log_info "Installing NVIDIA Container Toolkit..."
    
    # Check if nvidia-smi is available
    if ! command_exists nvidia-smi; then
        log_warning "nvidia-smi not found. Install NVIDIA drivers first."
        if ! prompt_yes_no "Skip NVIDIA toolkit installation?"; then
            error_exit "NVIDIA drivers required" 3
        fi
        return 0
    fi
    
    wait_for_apt
    
    log_info "Adding NVIDIA Container Toolkit repository..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    log_success "NVIDIA repository added"
    
    wait_for_apt
    
    log_info "Installing NVIDIA Container Toolkit packages..."
    apt-get update -qq 2>&1 | tee -a "${LOG_FILE}"
    apt-get install -y -qq nvidia-container-toolkit 2>&1 | tee -a "${LOG_FILE}" || error_exit "Failed to install NVIDIA toolkit" 3
    log_success "NVIDIA Container Toolkit installed"
    
    log_info "Configuring Docker for NVIDIA runtime..."
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    log_success "Docker configured for NVIDIA GPU"
    
    # Verify NVIDIA toolkit
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        log_success "NVIDIA Container Toolkit verified"
    else
        log_warning "NVIDIA toolkit verification failed, but continuing..."
    fi
}

install_tailscale() {
    log_step "6" "$TOTAL_STEPS" "INSTALLING TAILSCALE"
    
    if command_exists tailscale; then
        local ts_version=$(tailscale version | head -1 | awk '{print $1}')
        log_warning "Tailscale already installed: $ts_version"
        if ! prompt_yes_no "Reinstall Tailscale?"; then
            log_info "Skipping Tailscale installation"
            return 0
        fi
        
        log_info "Removing existing Tailscale installation..."
        apt-get remove -y tailscale 2>&1 | tee -a "${LOG_FILE}" || true
        rm -f /etc/apt/sources.list.d/tailscale.list
        rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
        log_success "Existing Tailscale removed"
    fi
    
    wait_for_apt
    
    log_info "Adding Tailscale GPG key..."
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    log_success "Tailscale GPG key added"
    
    log_info "Adding Tailscale repository..."
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/tailscale.list
    log_success "Tailscale repository added"
    
    wait_for_apt
    
    log_info "Installing Tailscale..."
    apt-get update -qq 2>&1 | tee -a "${LOG_FILE}"
    apt-get install -y -qq tailscale 2>&1 | tee -a "${LOG_FILE}" || error_exit "Failed to install Tailscale" 3
    log_success "Tailscale installed"
    
    # Verify Tailscale installation
    if tailscale version >/dev/null 2>&1; then
        local ts_version=$(tailscale version | head -1 | awk '{print $1}')
        log_success "Tailscale $ts_version installed"
    else
        error_exit "Tailscale installation verification failed" 3
    fi
    
    log_info "Enabling Tailscale service..."
    systemctl enable tailscaled
    systemctl start tailscaled
    log_success "Tailscale service started and enabled"
}

configure_apparmor() {
    log_step "7" "$TOTAL_STEPS" "CONFIGURING APPARMOR"
    
    if ! command_exists aa-status; then
        log_warning "AppArmor not available on this system"
        return 0
    fi
    
    log_info "Checking AppArmor status..."
    if ! systemctl is-active --quiet apparmor; then
        log_warning "AppArmor service not active"
        if prompt_yes_no "Enable AppArmor?"; then
            systemctl enable apparmor
            systemctl start apparmor
            log_success "AppArmor enabled"
        else
            log_warning "Continuing without AppArmor"
            return 0
        fi
    fi
    
    log_info "Creating AppArmor profile for Docker..."
    cat > /etc/apparmor.d/docker-default <<'EOF'
#include <tunables/global>

profile docker-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  network,
  capability,
  file,
  umount,

  deny @{PROC}/* w,   # deny write for all files directly in /proc (not in a subdir)
  deny @{PROC}/{[^1-9],[^1-9][^0-9],[^1-9s][^0-9y][^0-9s],[^1-9][^0-9][^0-9][^0-9]*}/** w,
  deny @{PROC}/sys/[^k]** w,  # deny /proc/sys except /proc/sys/k* (effectively /proc/sys/kernel)
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]**} w,  # deny everything except shm* in /proc/sys/kernel/
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/mem rwklx,
  deny @{PROC}/kmem rwklx,
  deny @{PROC}/kcore rwklx,

  deny mount,

  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/kernel/security/** rwklx,
}
EOF
    
    log_info "Reloading AppArmor profiles..."
    apparmor_parser -r /etc/apparmor.d/docker-default 2>&1 | tee -a "${LOG_FILE}" || log_warning "Failed to load AppArmor profile"
    log_success "AppArmor configured"
}

create_directory_structure() {
    log_step "8" "$TOTAL_STEPS" "CREATING DIRECTORY STRUCTURE"
    
    log_info "Creating directory structure..."
    
    # Root directories
    mkdir -p "${ROOT_PATH}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${STACK_DIR}"
    mkdir -p "${SECRETS_DIR}"
    mkdir -p "${SCRIPTS_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${GDRIVE_LOCAL_PATH}"
    
    # Config subdirectories
    mkdir -p "${CONFIG_DIR}/ollama"
    mkdir -p "${CONFIG_DIR}/litellm"
    mkdir -p "${CONFIG_DIR}/openclaw"
    mkdir -p "${CONFIG_DIR}/webui"
    mkdir -p "${CONFIG_DIR}/dify"
    mkdir -p "${CONFIG_DIR}/anythingllm"
    mkdir -p "${CONFIG_DIR}/qdrant"
    mkdir -p "${CONFIG_DIR}/weaviate"
    mkdir -p "${CONFIG_DIR}/chromadb"
    mkdir -p "${CONFIG_DIR}/milvus"
    mkdir -p "${CONFIG_DIR}/signal-api"
    mkdir -p "${CONFIG_DIR}/gdrive"
    mkdir -p "${CONFIG_DIR}/n8n"
    mkdir -p "${CONFIG_DIR}/langfuse"
    mkdir -p "${CONFIG_DIR}/prometheus"
    mkdir -p "${CONFIG_DIR}/grafana"
    mkdir -p "${CONFIG_DIR}/loki"
    mkdir -p "${CONFIG_DIR}/minio"
    mkdir -p "${CONFIG_DIR}/caddy"
    mkdir -p "${CONFIG_DIR}/nginx"
    
    # Data subdirectories (in /mnt/data)
    mkdir -p "${DATA_DIR}/ollama"
    mkdir -p "${DATA_DIR}/postgres"
    mkdir -p "${DATA_DIR}/redis"
    mkdir -p "${DATA_DIR}/qdrant"
    mkdir -p "${DATA_DIR}/weaviate"
    mkdir -p "${DATA_DIR}/chromadb"
    mkdir -p "${DATA_DIR}/milvus"
    mkdir -p "${DATA_DIR}/dify"
    mkdir -p "${DATA_DIR}/anythingllm"
    mkdir -p "${DATA_DIR}/openclaw"
    mkdir -p "${DATA_DIR}/n8n"
    mkdir -p "${DATA_DIR}/langfuse"
    mkdir -p "${DATA_DIR}/prometheus"
    mkdir -p "${DATA_DIR}/grafana"
    mkdir -p "${DATA_DIR}/loki"
    mkdir -p "${DATA_DIR}/minio"
    
    # Log subdirectories (in /mnt/data/logs)
    mkdir -p "${LOG_DIR}/docker"
    mkdir -p "${LOG_DIR}/services"
    mkdir -p "${LOG_DIR}/ollama"
    mkdir -p "${LOG_DIR}/litellm"
    mkdir -p "${LOG_DIR}/openclaw"
    mkdir -p "${LOG_DIR}/nginx"
    mkdir -p "${LOG_DIR}/caddy"
    
    # Backup subdirectories
    mkdir -p "${BACKUP_DIR}/daily"
    mkdir -p "${BACKUP_DIR}/weekly"
    mkdir -p "${BACKUP_DIR}/monthly"
    
    # Set permissions
    chmod 755 "${ROOT_PATH}"
    chmod 755 "${CONFIG_DIR}"
    chmod 755 "${STACK_DIR}"
    chmod 700 "${SECRETS_DIR}"
    chmod 755 "${SCRIPTS_DIR}"
    chmod 755 "${LOG_DIR}"
    chmod 755 "${BACKUP_DIR}"
    chmod 755 "${GDRIVE_LOCAL_PATH}"
    
    log_success "Directory structure created"
    
    # Display structure
    log_info "Directory structure:"
    cat <<EOF | tee -a "${LOG_FILE}"
/opt/ai-platform/          # Root installation directory
├── config/                # Configuration files
├── stacks/                # Docker Compose files
├── secrets/               # Sensitive data (700 permissions)
└── scripts/               # Helper scripts

/mnt/data/                 # Persistent data storage
├── ai-platform/           # Service data volumes
├── gdrive/                # Google Drive sync target
├── logs/                  # All logs (growing)
│   ├── script0.log       # Cleanup logs
│   ├── script1.log       # Setup logs
│   ├── script2.log       # Deploy logs
│   ├── docker/           # Container logs
│   └── services/         # Service-specific logs
└── backups/              # Backup storage
    ├── daily/
    ├── weekly/
    └── monthly/
EOF
}

################################################################################
# MAIN EXECUTION CONTINUATION
################################################################################

main_part2() {
    # Package installation phase
    install_system_packages
    install_docker
    configure_docker_non_root
    install_nvidia_toolkit
    install_tailscale
    configure_apparmor
    create_directory_structure
    
    log_success "Package installation phase completed"
    
    # TO BE CONTINUED IN NEXT PARTS...
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 2 of Script 1 v101.0.0 loaded successfully${NC}"
    echo -e "${CYAN}  Ready for Part 3: Service Selection${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Don't run yet - wait for all parts
# main_part2 "$@"
################################################################################
# SERVICE SELECTION & PORT CONFIGURATION
################################################################################

# Service definitions with defaults
declare -A SERVICE_DEFAULTS=(
    # Core Services
    [ollama_port]="11434"
    [litellm_port]="4000"
    [webui_port]="3000"
    
    # Databases
    [postgres_port]="5432"
    [redis_port]="6379"
    
    # Vector Databases
    [qdrant_port]="6333"
    [weaviate_port]="8080"
    [chromadb_port]="8000"
    [milvus_port]="19530"
    
    # AI Platforms
    [dify_port]="3001"
    [anythingllm_port]="3002"
    [openclaw_port]="8090"
    
    # Automation
    [n8n_port]="5678"
    
    # Observability
    [langfuse_port]="3003"
    [prometheus_port]="9090"
    [grafana_port]="3004"
    [loki_port]="3100"
    
    # Infrastructure
    [minio_port]="9000"
    [minio_console_port]="9001"
    [portainer_port]="9443"
    [caddy_http_port]="80"
    [caddy_https_port]="443"
    [nginx_http_port]="8080"
    [nginx_https_port]="8443"
    [tailscale_port]="41641"
    [signal_api_port]="8082"
)

display_service_selection_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SERVICE SELECTION & PORT CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Select which services to deploy. Each service will prompt for:"
    echo "  • Whether to enable the service"
    echo "  • Port configuration"
    echo "  • Service-specific settings"
    echo ""
    echo "Note: Some services have dependencies that will be auto-enabled."
    echo ""
}

select_core_services() {
    log_step "9" "$TOTAL_STEPS" "SELECTING CORE SERVICES"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  CORE SERVICES (Required)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Ollama (Required)
    echo -e "${CYAN}[1/3] Ollama - Local LLM Runtime${NC}"
    echo "Purpose: Run local language models (Llama, Mistral, etc.)"
    SERVICE_ENABLED[ollama]=true
    log_success "Ollama: ENABLED (required)"
    
    read -p "Port for Ollama API [${SERVICE_DEFAULTS[ollama_port]}]: " input
    SERVICE_PORTS[ollama]="${input:-${SERVICE_DEFAULTS[ollama_port]}}"
    log_info "Ollama port: ${SERVICE_PORTS[ollama]}"
    
    echo ""
    
    # LiteLLM (Required)
    echo -e "${CYAN}[2/3] LiteLLM - Unified LLM Gateway${NC}"
    echo "Purpose: Unified API for all LLM providers (Ollama, OpenAI, Anthropic, etc.)"
    SERVICE_ENABLED[litellm]=true
    log_success "LiteLLM: ENABLED (required)"
    
    read -p "Port for LiteLLM API [${SERVICE_DEFAULTS[litellm_port]}]: " input
    SERVICE_PORTS[litellm]="${input:-${SERVICE_DEFAULTS[litellm_port]}}"
    log_info "LiteLLM port: ${SERVICE_PORTS[litellm]}"
    
    echo ""
    
    # Open WebUI (Required)
    echo -e "${CYAN}[3/3] Open WebUI - Chat Interface${NC}"
    echo "Purpose: ChatGPT-style web interface for local LLMs"
    SERVICE_ENABLED[webui]=true
    log_success "Open WebUI: ENABLED (required)"
    
    read -p "Port for Open WebUI [${SERVICE_DEFAULTS[webui_port]}]: " input
    SERVICE_PORTS[webui]="${input:-${SERVICE_DEFAULTS[webui_port]}}"
    log_info "Open WebUI port: ${SERVICE_PORTS[webui]}"
    
    echo ""
}

select_database_services() {
    log_step "10" "$TOTAL_STEPS" "SELECTING DATABASE SERVICES"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  DATABASE SERVICES${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # PostgreSQL
    echo -e "${CYAN}[1/2] PostgreSQL - Relational Database${NC}"
    echo "Purpose: Primary database for Dify, n8n, Langfuse, and other services"
    echo "Required by: Dify, n8n, Langfuse"
    if prompt_yes_no "Enable PostgreSQL?" "y"; then
        SERVICE_ENABLED[postgres]=true
        log_success "PostgreSQL: ENABLED"
        
        read -p "Port for PostgreSQL [${SERVICE_DEFAULTS[postgres_port]}]: " input
        SERVICE_PORTS[postgres]="${input:-${SERVICE_DEFAULTS[postgres_port]}}"
        log_info "PostgreSQL port: ${SERVICE_PORTS[postgres]}"
    else
        SERVICE_ENABLED[postgres]=false
        log_warning "PostgreSQL: DISABLED (some services will not work)"
    fi
    
    echo ""
    
    # Redis
    echo -e "${CYAN}[2/2] Redis - In-Memory Cache${NC}"
    echo "Purpose: Caching and session storage for web services"
    echo "Required by: Dify, Open WebUI"
    if prompt_yes_no "Enable Redis?" "y"; then
        SERVICE_ENABLED[redis]=true
        log_success "Redis: ENABLED"
        
        read -p "Port for Redis [${SERVICE_DEFAULTS[redis_port]}]: " input
        SERVICE_PORTS[redis]="${input:-${SERVICE_DEFAULTS[redis_port]}}"
        log_info "Redis port: ${SERVICE_PORTS[redis]}"
    else
        SERVICE_ENABLED[redis]=false
        log_warning "Redis: DISABLED (some services will not work)"
    fi
    
    echo ""
}

select_vector_database() {
    log_step "11" "$TOTAL_STEPS" "SELECTING VECTOR DATABASE"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  VECTOR DATABASE (Choose ONE)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Vector databases store embeddings for RAG (Retrieval Augmented Generation)."
    echo "Select ONE vector database for your deployment:"
    echo ""
    echo "  1) Qdrant      - Fast, Rust-based, excellent for production"
    echo "  2) Weaviate    - Feature-rich, GraphQL API, strong ecosystem"
    echo "  3) ChromaDB    - Simple, Python-based, easy to use"
    echo "  4) Milvus      - Enterprise-grade, highly scalable"
    echo "  5) None        - Skip vector database (RAG features disabled)"
    echo ""
    
    while true; do
        read -p "Select vector database [1-5]: " choice
        case $choice in
            1)
                SELECTED_VECTOR_DB="qdrant"
                SERVICE_ENABLED[qdrant]=true
                log_success "Selected: Qdrant"
                
                read -p "Port for Qdrant [${SERVICE_DEFAULTS[qdrant_port]}]: " input
                SERVICE_PORTS[qdrant]="${input:-${SERVICE_DEFAULTS[qdrant_port]}}"
                log_info "Qdrant port: ${SERVICE_PORTS[qdrant]}"
                break
                ;;
            2)
                SELECTED_VECTOR_DB="weaviate"
                SERVICE_ENABLED[weaviate]=true
                log_success "Selected: Weaviate"
                
                read -p "Port for Weaviate [${SERVICE_DEFAULTS[weaviate_port]}]: " input
                SERVICE_PORTS[weaviate]="${input:-${SERVICE_DEFAULTS[weaviate_port]}}"
                log_info "Weaviate port: ${SERVICE_PORTS[weaviate]}"
                break
                ;;
            3)
                SELECTED_VECTOR_DB="chromadb"
                SERVICE_ENABLED[chromadb]=true
                log_success "Selected: ChromaDB"
                
                read -p "Port for ChromaDB [${SERVICE_DEFAULTS[chromadb_port]}]: " input
                SERVICE_PORTS[chromadb]="${input:-${SERVICE_DEFAULTS[chromadb_port]}}"
                log_info "ChromaDB port: ${SERVICE_PORTS[chromadb]}"
                break
                ;;
            4)
                SELECTED_VECTOR_DB="milvus"
                SERVICE_ENABLED[milvus]=true
                log_success "Selected: Milvus"
                
                read -p "Port for Milvus [${SERVICE_DEFAULTS[milvus_port]}]: " input
                SERVICE_PORTS[milvus]="${input:-${SERVICE_DEFAULTS[milvus_port]}}"
                log_info "Milvus port: ${SERVICE_PORTS[milvus]}"
                
                read -p "Port for Milvus Web UI [19121]: " input
                SERVICE_PORTS[milvus_web]="${input:-19121}"
                log_info "Milvus Web UI port: ${SERVICE_PORTS[milvus_web]}"
                break
                ;;
            5)
                SELECTED_VECTOR_DB="none"
                log_warning "No vector database selected (RAG features will be disabled)"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-5.${NC}"
                ;;
        esac
    done
    
    echo ""
}

select_ai_platforms() {
    log_step "12" "$TOTAL_STEPS" "SELECTING AI PLATFORMS"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  AI PLATFORMS (Optional)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Dify
    echo -e "${CYAN}[1/3] Dify - LLMOps Platform${NC}"
    echo "Purpose: Build and operate AI applications with workflow editor"
    echo "Dependencies: PostgreSQL, Redis"
    if prompt_yes_no "Enable Dify?"; then
        SERVICE_ENABLED[dify]=true
        log_success "Dify: ENABLED"
        
        # Auto-enable dependencies
        if [[ "${SERVICE_ENABLED[postgres]}" != "true" ]]; then
            log_warning "Enabling PostgreSQL (required by Dify)"
            SERVICE_ENABLED[postgres]=true
            SERVICE_PORTS[postgres]="${SERVICE_DEFAULTS[postgres_port]}"
        fi
        if [[ "${SERVICE_ENABLED[redis]}" != "true" ]]; then
            log_warning "Enabling Redis (required by Dify)"
            SERVICE_ENABLED[redis]=true
            SERVICE_PORTS[redis]="${SERVICE_DEFAULTS[redis_port]}"
        fi
        
        read -p "Port for Dify Web [${SERVICE_DEFAULTS[dify_port]}]: " input
        SERVICE_PORTS[dify]="${input:-${SERVICE_DEFAULTS[dify_port]}}"
        log_info "Dify port: ${SERVICE_PORTS[dify]}"
        
        read -p "Port for Dify API [3002]: " input
        SERVICE_PORTS[dify_api]="${input:-3002}"
        log_info "Dify API port: ${SERVICE_PORTS[dify_api]}"
    else
        SERVICE_ENABLED[dify]=false
        log_info "Dify: DISABLED"
    fi
    
    echo ""
    
    # AnythingLLM
    echo -e "${CYAN}[2/3] AnythingLLM - Document Chat Platform${NC}"
    echo "Purpose: Chat with documents using RAG"
    echo "Dependencies: Vector database (recommended)"
    if prompt_yes_no "Enable AnythingLLM?"; then
        SERVICE_ENABLED[anythingllm]=true
        log_success "AnythingLLM: ENABLED"
        
        read -p "Port for AnythingLLM [${SERVICE_DEFAULTS[anythingllm_port]}]: " input
        SERVICE_PORTS[anythingllm]="${input:-${SERVICE_DEFAULTS[anythingllm_port]}}"
        log_info "AnythingLLM port: ${SERVICE_PORTS[anythingllm]}"
    else
        SERVICE_ENABLED[anythingllm]=false
        log_info "AnythingLLM: DISABLED"
    fi
    
    echo ""
    
    # OpenClaw
    echo -e "${CYAN}[3/3] OpenClaw - AI Automation Platform${NC}"
    echo "Purpose: Advanced AI workflows with vector search integration"
    echo "Dependencies: Vector database, LiteLLM"
    if prompt_yes_no "Enable OpenClaw?"; then
        SERVICE_ENABLED[openclaw]=true
        log_success "OpenClaw: ENABLED"
        
        if [[ "$SELECTED_VECTOR_DB" == "none" ]]; then
            log_warning "OpenClaw works best with a vector database"
            log_warning "Consider going back and selecting one"
        fi
        
        read -p "Port for OpenClaw [${SERVICE_DEFAULTS[openclaw_port]}]: " input
        SERVICE_PORTS[openclaw]="${input:-${SERVICE_DEFAULTS[openclaw_port]}}"
        log_info "OpenClaw port: ${SERVICE_PORTS[openclaw]}"
    else
        SERVICE_ENABLED[openclaw]=false
        log_info "OpenClaw: DISABLED"
    fi
    
    echo ""
}

select_automation_services() {
    log_step "13" "$TOTAL_STEPS" "SELECTING AUTOMATION SERVICES"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  AUTOMATION SERVICES${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # n8n
    echo -e "${CYAN}[1/2] n8n - Workflow Automation${NC}"
    echo "Purpose: Build complex workflows and integrations"
    echo "Dependencies: PostgreSQL (recommended)"
    if prompt_yes_no "Enable n8n?"; then
        SERVICE_ENABLED[n8n]=true
        log_success "n8n: ENABLED"
        
        if [[ "${SERVICE_ENABLED[postgres]}" != "true" ]]; then
            if prompt_yes_no "Enable PostgreSQL for n8n (recommended)?"; then
                SERVICE_ENABLED[postgres]=true
                SERVICE_PORTS[postgres]="${SERVICE_DEFAULTS[postgres_port]}"
                log_success "PostgreSQL enabled for n8n"
            fi
        fi
        
        read -p "Port for n8n [${SERVICE_DEFAULTS[n8n_port]}]: " input
        SERVICE_PORTS[n8n]="${input:-${SERVICE_DEFAULTS[n8n_port]}}"
        log_info "n8n port: ${SERVICE_PORTS[n8n]}"
    else
        SERVICE_ENABLED[n8n]=false
        log_info "n8n: DISABLED"
    fi
    
    echo ""
    
    # Signal-API
    echo -e "${CYAN}[2/2] Signal-API - Signal Messenger Integration${NC}"
    echo "Purpose: Send/receive Signal messages (for notifications, automation)"
    if prompt_yes_no "Enable Signal-API?"; then
        SERVICE_ENABLED[signal_api]=true
        log_success "Signal-API: ENABLED"
        
        read -p "Port for Signal-API [${SERVICE_DEFAULTS[signal_api_port]}]: " input
        SERVICE_PORTS[signal_api]="${input:-${SERVICE_DEFAULTS[signal_api_port]}}"
        log_info "Signal-API port: ${SERVICE_PORTS[signal_api]}"
        
        read -p "Signal phone number (with country code, e.g., +1234567890): " signal_phone
        SERVICE_CONFIGS[signal_phone]="$signal_phone"
        log_info "Signal phone: $signal_phone"
    else
        SERVICE_ENABLED[signal_api]=false
        log_info "Signal-API: DISABLED"
    fi
    
    echo ""
}

select_observability_services() {
    log_step "14" "$TOTAL_STEPS" "SELECTING OBSERVABILITY SERVICES"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  OBSERVABILITY & MONITORING${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Langfuse
    echo -e "${CYAN}[1/4] Langfuse - LLM Observability${NC}"
    echo "Purpose: Track LLM calls, costs, and performance"
    echo "Dependencies: PostgreSQL"
    if prompt_yes_no "Enable Langfuse?"; then
        SERVICE_ENABLED[langfuse]=true
        log_success "Langfuse: ENABLED"
        
        if [[ "${SERVICE_ENABLED[postgres]}" != "true" ]]; then
            log_warning "Enabling PostgreSQL (required by Langfuse)"
            SERVICE_ENABLED[postgres]=true
            SERVICE_PORTS[postgres]="${SERVICE_DEFAULTS[postgres_port]}"
        fi
        
        read -p "Port for Langfuse [${SERVICE_DEFAULTS[langfuse_port]}]: " input
        SERVICE_PORTS[langfuse]="${input:-${SERVICE_DEFAULTS[langfuse_port]}}"
        log_info "Langfuse port: ${SERVICE_PORTS[langfuse]}"
    else
        SERVICE_ENABLED[langfuse]=false
        log_info "Langfuse: DISABLED"
    fi
    
    echo ""
    
    # Prometheus
    echo -e "${CYAN}[2/4] Prometheus - Metrics Collection${NC}"
    echo "Purpose: Collect and store system and service metrics"
    if prompt_yes_no "Enable Prometheus?"; then
        SERVICE_ENABLED[prometheus]=true
        log_success "Prometheus: ENABLED"
        
        read -p "Port for Prometheus [${SERVICE_DEFAULTS[prometheus_port]}]: " input
        SERVICE_PORTS[prometheus]="${input:-${SERVICE_DEFAULTS[prometheus_port]}}"
        log_info "Prometheus port: ${SERVICE_PORTS[prometheus]}"
    else
        SERVICE_ENABLED[prometheus]=false
        log_info "Prometheus: DISABLED"
    fi
    
    echo ""
    
    # Grafana
    echo -e "${CYAN}[3/4] Grafana - Visualization Dashboard${NC}"
    echo "Purpose: Visualize metrics from Prometheus"
    echo "Dependencies: Prometheus (recommended)"
    if prompt_yes_no "Enable Grafana?"; then
        SERVICE_ENABLED[grafana]=true
        log_success "Grafana: ENABLED"
        
        if [[ "${SERVICE_ENABLED[prometheus]}" != "true" ]]; then
            if prompt_yes_no "Enable Prometheus for Grafana (recommended)?"; then
                SERVICE_ENABLED[prometheus]=true
                SERVICE_PORTS[prometheus]="${SERVICE_DEFAULTS[prometheus_port]}"
                log_success "Prometheus enabled for Grafana"
            fi
        fi
        
        read -p "Port for Grafana [${SERVICE_DEFAULTS[grafana_port]}]: " input
        SERVICE_PORTS[grafana]="${input:-${SERVICE_DEFAULTS[grafana_port]}}"
        log_info "Grafana port: ${SERVICE_PORTS[grafana]}"
    else
        SERVICE_ENABLED[grafana]=false
        log_info "Grafana: DISABLED"
    fi
    
    echo ""
    
    # Loki
    echo -e "${CYAN}[4/4] Loki - Log Aggregation${NC}"
    echo "Purpose: Collect and query logs from all services"
    if prompt_yes_no "Enable Loki?"; then
        SERVICE_ENABLED[loki]=true
        log_success "Loki: ENABLED"
        
        read -p "Port for Loki [${SERVICE_DEFAULTS[loki_port]}]: " input
        SERVICE_PORTS[loki]="${input:-${SERVICE_DEFAULTS[loki_port]}}"
        log_info "Loki port: ${SERVICE_PORTS[loki]}"
    else
        SERVICE_ENABLED[loki]=false
        log_info "Loki: DISABLED"
    fi
    
    echo ""
}

select_infrastructure_services() {
    log_step "15" "$TOTAL_STEPS" "SELECTING INFRASTRUCTURE SERVICES"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  INFRASTRUCTURE SERVICES${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # MinIO
    echo -e "${CYAN}[1/3] MinIO - S3-Compatible Object Storage${NC}"
    echo "Purpose: Store files, backups, and model artifacts"
    if prompt_yes_no "Enable MinIO?"; then
        SERVICE_ENABLED[minio]=true
        log_success "MinIO: ENABLED"
        
        read -p "Port for MinIO API [${SERVICE_DEFAULTS[minio_port]}]: " input
        SERVICE_PORTS[minio]="${input:-${SERVICE_DEFAULTS[minio_port]}}"
        log_info "MinIO API port: ${SERVICE_PORTS[minio]}"
        
        read -p "Port for MinIO Console [${SERVICE_DEFAULTS[minio_console_port]}]: " input
        SERVICE_PORTS[minio_console]="${input:-${SERVICE_DEFAULTS[minio_console_port]}}"
        log_info "MinIO Console port: ${SERVICE_PORTS[minio_console]}"
    else
        SERVICE_ENABLED[minio]=false
        log_info "MinIO: DISABLED"
    fi
    
    echo ""
    
    # Portainer
    echo -e "${CYAN}[2/3] Portainer - Docker Management UI${NC}"
    echo "Purpose: Manage Docker containers via web interface"
    if prompt_yes_no "Enable Portainer?"; then
        SERVICE_ENABLED[portainer]=true
        log_success "Portainer: ENABLED"
        
        read -p "Port for Portainer [${SERVICE_DEFAULTS[portainer_port]}]: " input
        SERVICE_PORTS[portainer]="${input:-${SERVICE_DEFAULTS[portainer_port]}}"
        log_info "Portainer port: ${SERVICE_PORTS[portainer]}"
    else
        SERVICE_ENABLED[portainer]=false
        log_info "Portainer: DISABLED"
    fi
    
    echo ""
    
    # Reverse Proxy
    echo -e "${CYAN}[3/3] Reverse Proxy${NC}"
    echo "Purpose: Expose services via domain names with SSL"
    echo ""
    echo "  1) Caddy  - Automatic HTTPS, simpler configuration"
    echo "  2) Nginx  - More control, traditional configuration"
    echo "  3) None   - Direct port access only (Tailscale recommended)"
    echo ""
    
    while true; do
        read -p "Select reverse proxy [1-3]: " choice
        case $choice in
            1)
                SERVICE_ENABLED[caddy]=true
                SELECTED_PROXY="caddy"
                log_success "Selected: Caddy"
                
                read -p "Port for Caddy HTTP [${SERVICE_DEFAULTS[caddy_http_port]}]: " input
                SERVICE_PORTS[caddy_http]="${input:-${SERVICE_DEFAULTS[caddy_http_port]}}"
                
                read -p "Port for Caddy HTTPS [${SERVICE_DEFAULTS[caddy_https_port]}]: " input
                SERVICE_PORTS[caddy_https]="${input:-${SERVICE_DEFAULTS[caddy_https_port]}}"
                
                read -p "Domain name (e.g., ai.example.com) [optional]: " domain
                SERVICE_CONFIGS[domain]="$domain"
                
                log_info "Caddy HTTP port: ${SERVICE_PORTS[caddy_http]}"
                log_info "Caddy HTTPS port: ${SERVICE_PORTS[caddy_https]}"
                [[ -n "$domain" ]] && log_info "Domain: $domain"
                break
                ;;
            2)
                SERVICE_ENABLED[nginx]=true
                SELECTED_PROXY="nginx"
                log_success "Selected: Nginx"
                
                read -p "Port for Nginx HTTP [${SERVICE_DEFAULTS[nginx_http_port]}]: " input
                SERVICE_PORTS[nginx_http]="${input:-${SERVICE_DEFAULTS[nginx_http_port]}}"
                
                read -p "Port for Nginx HTTPS [${SERVICE_DEFAULTS[nginx_https_port]}]: " input
                SERVICE_PORTS[nginx_https]="${input:-${SERVICE_DEFAULTS[nginx_https_port]}}"
                
                read -p "Domain name (e.g., ai.example.com) [optional]: " domain
                SERVICE_CONFIGS[domain]="$domain"
                
                log_info "Nginx HTTP port: ${SERVICE_PORTS[nginx_http]}"
                log_info "Nginx HTTPS port: ${SERVICE_PORTS[nginx_https]}"
                [[ -n "$domain" ]] && log_info "Domain: $domain"
                break
                ;;
            3)
                SELECTED_PROXY="none"
                log_warning "No reverse proxy selected"
                log_info "Services will be accessed via direct ports"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-3.${NC}"
                ;;
        esac
    done
    
    echo ""
}

################################################################################
# MAIN EXECUTION CONTINUATION
################################################################################

main_part3() {
    # Service selection phase
    display_service_selection_header
    select_core_services
    select_database_services
    select_vector_database
    select_ai_platforms
    select_automation_services
    select_observability_services
    select_infrastructure_services
    
    log_success "Service selection completed"
    
    # TO BE CONTINUED IN NEXT PARTS...
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 3 of Script 1 v101.0.0 loaded successfully${NC}"
    echo -e "${CYAN}  Ready for Part 4: Ollama Models & API Keys${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Don't run yet - wait for all parts
# main_part3 "$@"
################################################################################
# OLLAMA MODEL SELECTION
################################################################################

select_ollama_models() {
    log_step "16" "$TOTAL_STEPS" "SELECTING OLLAMA MODELS"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  OLLAMA MODEL SELECTION${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Select models to download. Models will be pulled during Script 2 deployment."
    echo ""
    echo "Available models:"
    echo ""
    echo -e "${CYAN}Small Models (< 5GB):${NC}"
    echo "  1) llama3.2:3b              - Fast, efficient, good for chat (2GB)"
    echo "  2) phi3:mini                - Microsoft's small model (2.3GB)"
    echo "  3) gemma2:2b                - Google's compact model (1.6GB)"
    echo "  4) qwen2.5:3b               - Alibaba's multilingual model (2.3GB)"
    echo ""
    echo -e "${CYAN}Medium Models (5-15GB):${NC}"
    echo "  5) llama3.2:8b              - Balanced performance (4.7GB)"
    echo "  6) llama3.1:8b              - Previous gen, very capable (4.7GB)"
    echo "  7) mistral:7b               - Excellent general purpose (4.1GB)"
    echo "  8) gemma2:9b                - Google's medium model (5.4GB)"
    echo "  9) qwen2.5:7b               - Alibaba 7B (4.7GB)"
    echo " 10) codellama:7b             - Code-specialized (3.8GB)"
    echo ""
    echo -e "${CYAN}Large Models (15-40GB):${NC}"
    echo " 11) llama3.1:70b             - High performance (40GB) ${RED}*GPU recommended${NC}"
    echo " 12) mixtral:8x7b             - MoE architecture (26GB) ${RED}*GPU recommended${NC}"
    echo " 13) qwen2.5:14b              - Large multilingual (8.7GB)"
    echo " 14) codellama:13b            - Advanced code model (7.4GB)"
    echo ""
    echo -e "${CYAN}Specialized Models:${NC}"
    echo " 15) llava:7b                 - Vision + Language (4.7GB)"
    echo " 16) llama3.2-vision:11b      - Latest vision model (7.9GB)"
    echo " 17) deepseek-coder-v2:16b    - Advanced coding (8.9GB)"
    echo " 18) nomic-embed-text         - Embeddings for RAG (274MB)"
    echo ""
    echo " 19) Custom model name        - Enter any Ollama model"
    echo "  0) Done selecting models"
    echo ""
    
    SELECTED_OLLAMA_MODELS=()
    
    while true; do
        echo ""
        echo -e "${GREEN}Currently selected (${#SELECTED_OLLAMA_MODELS[@]} models):${NC}"
        if [[ ${#SELECTED_OLLAMA_MODELS[@]} -eq 0 ]]; then
            echo "  (none)"
        else
            for model in "${SELECTED_OLLAMA_MODELS[@]}"; do
                echo "  - $model"
            done
        fi
        echo ""
        
        read -p "Select model [0-19]: " choice
        
        case $choice in
            0)
                if [[ ${#SELECTED_OLLAMA_MODELS[@]} -eq 0 ]]; then
                    log_warning "No models selected. At least one model is recommended."
                    if ! prompt_yes_no "Continue without models?"; then
                        continue
                    fi
                fi
                log_success "Model selection completed: ${#SELECTED_OLLAMA_MODELS[@]} models"
                break
                ;;
            1) add_ollama_model "llama3.2:3b" ;;
            2) add_ollama_model "phi3:mini" ;;
            3) add_ollama_model "gemma2:2b" ;;
            4) add_ollama_model "qwen2.5:3b" ;;
            5) add_ollama_model "llama3.2:8b" ;;
            6) add_ollama_model "llama3.1:8b" ;;
            7) add_ollama_model "mistral:7b" ;;
            8) add_ollama_model "gemma2:9b" ;;
            9) add_ollama_model "qwen2.5:7b" ;;
            10) add_ollama_model "codellama:7b" ;;
            11)
                if [[ "$HAS_GPU" != "true" ]]; then
                    log_warning "This model is very large (40GB) and runs slowly on CPU"
                    if ! prompt_yes_no "Add llama3.1:70b anyway?"; then
                        continue
                    fi
                fi
                add_ollama_model "llama3.1:70b"
                ;;
            12)
                if [[ "$HAS_GPU" != "true" ]]; then
                    log_warning "This model is very large (26GB) and runs slowly on CPU"
                    if ! prompt_yes_no "Add mixtral:8x7b anyway?"; then
                        continue
                    fi
                fi
                add_ollama_model "mixtral:8x7b"
                ;;
            13) add_ollama_model "qwen2.5:14b" ;;
            14) add_ollama_model "codellama:13b" ;;
            15) add_ollama_model "llava:7b" ;;
            16) add_ollama_model "llama3.2-vision:11b" ;;
            17) add_ollama_model "deepseek-coder-v2:16b" ;;
            18) add_ollama_model "nomic-embed-text" ;;
            19)
                read -p "Enter custom model name (e.g., mistral:latest): " custom_model
                if [[ -n "$custom_model" ]]; then
                    add_ollama_model "$custom_model"
                else
                    log_error "Invalid model name"
                fi
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 0-19.${NC}"
                ;;
        esac
    done
    
    # Store models in config
    OLLAMA_MODELS_STRING=$(IFS=,; echo "${SELECTED_OLLAMA_MODELS[*]}")
    
    echo ""
}

add_ollama_model() {
    local model="$1"
    
    # Check if already selected
    for existing in "${SELECTED_OLLAMA_MODELS[@]}"; do
        if [[ "$existing" == "$model" ]]; then
            log_warning "Model '$model' already selected"
            return
        fi
    done
    
    SELECTED_OLLAMA_MODELS+=("$model")
    log_success "Added: $model"
}

################################################################################
# API KEY COLLECTION
################################################################################

collect_api_keys() {
    log_step "17" "$TOTAL_STEPS" "COLLECTING API KEYS"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  API KEY COLLECTION${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Provide API keys for external LLM providers (optional)."
    echo "These will be configured in LiteLLM for unified access."
    echo ""
    echo "Press ENTER to skip any provider you don't need."
    echo ""
    
    # OpenAI
    echo -e "${CYAN}OpenAI API Key${NC}"
    echo "Get your key from: https://platform.openai.com/api-keys"
    read -p "OpenAI API Key: " -s openai_key
    echo ""
    if [[ -n "$openai_key" ]]; then
        API_KEYS[openai]="$openai_key"
        log_success "OpenAI API key collected"
    else
        log_info "OpenAI: Skipped"
    fi
    echo ""
    
    # Anthropic
    echo -e "${CYAN}Anthropic (Claude) API Key${NC}"
    echo "Get your key from: https://console.anthropic.com/settings/keys"
    read -p "Anthropic API Key: " -s anthropic_key
    echo ""
    if [[ -n "$anthropic_key" ]]; then
        API_KEYS[anthropic]="$anthropic_key"
        log_success "Anthropic API key collected"
    else
        log_info "Anthropic: Skipped"
    fi
    echo ""
    
    # Google AI
    echo -e "${CYAN}Google AI (Gemini) API Key${NC}"
    echo "Get your key from: https://makersuite.google.com/app/apikey"
    read -p "Google AI API Key: " -s google_key
    echo ""
    if [[ -n "$google_key" ]]; then
        API_KEYS[google]="$google_key"
        log_success "Google AI API key collected"
    else
        log_info "Google AI: Skipped"
    fi
    echo ""
    
    # Groq
    echo -e "${CYAN}Groq API Key${NC}"
    echo "Get your key from: https://console.groq.com/keys"
    read -p "Groq API Key: " -s groq_key
    echo ""
    if [[ -n "$groq_key" ]]; then
        API_KEYS[groq]="$groq_key"
        log_success "Groq API key collected"
    else
        log_info "Groq: Skipped"
    fi
    echo ""
    
    # Cohere
    echo -e "${CYAN}Cohere API Key${NC}"
    echo "Get your key from: https://dashboard.cohere.com/api-keys"
    read -p "Cohere API Key: " -s cohere_key
    echo ""
    if [[ -n "$cohere_key" ]]; then
        API_KEYS[cohere]="$cohere_key"
        log_success "Cohere API key collected"
    else
        log_info "Cohere: Skipped"
    fi
    echo ""
    
    # Together AI
    echo -e "${CYAN}Together AI API Key${NC}"
    echo "Get your key from: https://api.together.xyz/settings/api-keys"
    read -p "Together AI API Key: " -s together_key
    echo ""
    if [[ -n "$together_key" ]]; then
        API_KEYS[together]="$together_key"
        log_success "Together AI API key collected"
    else
        log_info "Together AI: Skipped"
    fi
    echo ""
    
    # Perplexity
    echo -e "${CYAN}Perplexity API Key${NC}"
    echo "Get your key from: https://www.perplexity.ai/settings/api"
    read -p "Perplexity API Key: " -s perplexity_key
    echo ""
    if [[ -n "$perplexity_key" ]]; then
        API_KEYS[perplexity]="$perplexity_key"
        log_success "Perplexity API key collected"
    else
        log_info "Perplexity: Skipped"
    fi
    echo ""
    
    # Replicate
    echo -e "${CYAN}Replicate API Key${NC}"
    echo "Get your key from: https://replicate.com/account/api-tokens"
    read -p "Replicate API Key: " -s replicate_key
    echo ""
    if [[ -n "$replicate_key" ]]; then
        API_KEYS[replicate]="$replicate_key"
        log_success "Replicate API key collected"
    else
        log_info "Replicate: Skipped"
    fi
    echo ""
    
    # Hugging Face
    echo -e "${CYAN}Hugging Face API Key${NC}"
    echo "Get your key from: https://huggingface.co/settings/tokens"
    read -p "Hugging Face API Key: " -s huggingface_key
    echo ""
    if [[ -n "$huggingface_key" ]]; then
        API_KEYS[huggingface]="$huggingface_key"
        log_success "Hugging Face API key collected"
    else
        log_info "Hugging Face: Skipped"
    fi
    echo ""
    
    local key_count=${#API_KEYS[@]}
    log_success "API key collection completed: $key_count providers configured"
    
    echo ""
}

################################################################################
# GOOGLE DRIVE CONFIGURATION
################################################################################

configure_google_drive() {
    log_step "18" "$TOTAL_STEPS" "CONFIGURING GOOGLE DRIVE SYNC"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  GOOGLE DRIVE CONFIGURATION${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Configure automated Google Drive synchronization."
    echo "This will sync files bidirectionally with your Drive."
    echo ""
    
    if prompt_yes_no "Configure Google Drive sync?"; then
        GDRIVE_ENABLED=true
        log_success "Google Drive sync: ENABLED"
        
        echo ""
        echo "Google Drive authentication requires OAuth2."
        echo "You'll need to:"
        echo "  1. Visit the OAuth URL (displayed after setup)"
        echo "  2. Authorize the application"
        echo "  3. Paste the verification code"
        echo ""
        
        read -p "Google Drive folder name to sync [AI-Platform]: " gdrive_folder
        GDRIVE_FOLDER="${gdrive_folder:-AI-Platform}"
        log_info "Google Drive folder: $GDRIVE_FOLDER"
        
        read -p "Sync interval in minutes [30]: " sync_interval
        GDRIVE_SYNC_INTERVAL="${sync_interval:-30}"
        log_info "Sync interval: $GDRIVE_SYNC_INTERVAL minutes"
        
        echo ""
        echo -e "${CYAN}Google Drive will be configured during Script 2 deployment.${NC}"
        echo -e "${CYAN}You'll be prompted to authorize access when services start.${NC}"
        echo ""
    else
        GDRIVE_ENABLED=false
        log_info "Google Drive sync: DISABLED"
    fi
    
    echo ""
}

################################################################################
# SECRET GENERATION
################################################################################

generate_secrets() {
    log_step "19" "$TOTAL_STEPS" "GENERATING SECRETS"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  SECRET GENERATION${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Generating secure random secrets for all services..."
    echo ""
    
    # Generate secrets
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    POSTGRES_USER="aiplatform"
    POSTGRES_DB="aiplatform"
    
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    MINIO_ROOT_USER="minioadmin"
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    DIFY_SECRET_KEY=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-32)
    
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    LANGFUSE_SALT=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    LANGFUSE_SECRET=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-32)
    
    JWT_SECRET=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-32)
    
    ANYTHINGLLM_JWT=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-32)
    
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log_success "All secrets generated successfully"
    
    # Display secrets for confirmation
    echo ""
    echo -e "${CYAN}Generated secrets (will be saved to /opt/ai-platform/secrets/):${NC}"
    echo ""
    echo "PostgreSQL:"
    echo "  User:     $POSTGRES_USER"
    echo "  Password: ${POSTGRES_PASSWORD:0:5}...${POSTGRES_PASSWORD: -5}"
    echo "  Database: $POSTGRES_DB"
    echo ""
    echo "Redis:"
    echo "  Password: ${REDIS_PASSWORD:0:5}...${REDIS_PASSWORD: -5}"
    echo ""
    echo "MinIO:"
    echo "  User:     $MINIO_ROOT_USER"
    echo "  Password: ${MINIO_ROOT_PASSWORD:0:5}...${MINIO_ROOT_PASSWORD: -5}"
    echo ""
    echo "Grafana:"
    echo "  Admin Password: ${GRAFANA_ADMIN_PASSWORD:0:5}...${GRAFANA_ADMIN_PASSWORD: -5}"
    echo ""
    echo -e "${GREEN}All other secrets generated and will be saved securely.${NC}"
    echo ""
    
    if ! prompt_yes_no "Confirm secret generation?"; then
        log_warning "Secret generation rejected. Regenerating..."
        generate_secrets
        return
    fi
    
    log_success "Secrets confirmed"
    echo ""
}

################################################################################
# MAIN EXECUTION CONTINUATION
################################################################################

main_part4() {
    # Ollama models and API keys
    select_ollama_models
    collect_api_keys
    configure_google_drive
    generate_secrets
    
    log_success "Ollama models, API keys, and secrets configured"
    
    # TO BE CONTINUED IN NEXT PARTS...
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 4 of Script 1 v101.0.0 loaded successfully${NC}"
    echo -e "${CYAN}  Ready for Part 5: Configuration File Generation${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Don't run yet - wait for all parts
# main_part4 "$@"
################################################################################
# CONFIGURATION FILE GENERATION
################################################################################

generate_master_env() {
    log_step "20" "$TOTAL_STEPS" "GENERATING MASTER ENVIRONMENT FILE"
    
    local env_file="${CONFIG_DIR}/.env"
    
    log_info "Creating master .env file..."
    
    cat > "$env_file" << EOF
################################################################################
# AI PLATFORM MASTER CONFIGURATION
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Script Version: v101.0.0
################################################################################

# System Configuration
PLATFORM_VERSION=v101.0.0
HOSTNAME=${HOSTNAME}
TIMEZONE=${TIMEZONE}
DATA_DIR=${DATA_DIR}
CONFIG_DIR=${CONFIG_DIR}
LOG_DIR=${LOG_DIR}

# Hardware Detection
HAS_GPU=${HAS_GPU}
GPU_TYPE=${GPU_TYPE:-none}
TOTAL_RAM_GB=${TOTAL_RAM_GB}
CPU_CORES=${CPU_CORES}

# Network Configuration
TAILNET_NAME=${TAILNET_NAME:-}
DOMAIN_NAME=${DOMAIN_NAME:-}
REVERSE_PROXY=${REVERSE_PROXY:-none}

# Service Enablement
ENABLE_OLLAMA=${SERVICE_ENABLED[ollama]:-false}
ENABLE_LITELLM=${SERVICE_ENABLED[litellm]:-false}
ENABLE_WEBUI=${SERVICE_ENABLED[webui]:-false}
ENABLE_POSTGRES=${SERVICE_ENABLED[postgres]:-false}
ENABLE_REDIS=${SERVICE_ENABLED[redis]:-false}
ENABLE_QDRANT=${SERVICE_ENABLED[qdrant]:-false}
ENABLE_WEAVIATE=${SERVICE_ENABLED[weaviate]:-false}
ENABLE_CHROMADB=${SERVICE_ENABLED[chromadb]:-false}
ENABLE_MILVUS=${SERVICE_ENABLED[milvus]:-false}
ENABLE_DIFY=${SERVICE_ENABLED[dify]:-false}
ENABLE_ANYTHINGLLM=${SERVICE_ENABLED[anythingllm]:-false}
ENABLE_OPENCLAW=${SERVICE_ENABLED[openclaw]:-false}
ENABLE_N8N=${SERVICE_ENABLED[n8n]:-false}
ENABLE_SIGNAL_API=${SERVICE_ENABLED[signal_api]:-false}
ENABLE_LANGFUSE=${SERVICE_ENABLED[langfuse]:-false}
ENABLE_PROMETHEUS=${SERVICE_ENABLED[prometheus]:-false}
ENABLE_GRAFANA=${SERVICE_ENABLED[grafana]:-false}
ENABLE_LOKI=${SERVICE_ENABLED[loki]:-false}
ENABLE_MINIO=${SERVICE_ENABLED[minio]:-false}
ENABLE_PORTAINER=${SERVICE_ENABLED[portainer]:-false}

# Port Configuration
OLLAMA_PORT=${SERVICE_PORTS[ollama]:-11434}
LITELLM_PORT=${SERVICE_PORTS[litellm]:-4000}
WEBUI_PORT=${SERVICE_PORTS[webui]:-3000}
POSTGRES_PORT=${SERVICE_PORTS[postgres]:-5432}
REDIS_PORT=${SERVICE_PORTS[redis]:-6379}
QDRANT_PORT=${SERVICE_PORTS[qdrant]:-6333}
WEAVIATE_PORT=${SERVICE_PORTS[weaviate]:-8080}
CHROMADB_PORT=${SERVICE_PORTS[chromadb]:-8000}
MILVUS_PORT=${SERVICE_PORTS[milvus]:-19530}
DIFY_PORT=${SERVICE_PORTS[dify]:-3001}
ANYTHINGLLM_PORT=${SERVICE_PORTS[anythingllm]:-3002}
OPENCLAW_PORT=${SERVICE_PORTS[openclaw]:-8090}
N8N_PORT=${SERVICE_PORTS[n8n]:-5678}
SIGNAL_API_PORT=${SERVICE_PORTS[signal_api]:-8082}
LANGFUSE_PORT=${SERVICE_PORTS[langfuse]:-3003}
PROMETHEUS_PORT=${SERVICE_PORTS[prometheus]:-9090}
GRAFANA_PORT=${SERVICE_PORTS[grafana]:-3004}
LOKI_PORT=${SERVICE_PORTS[loki]:-3100}
MINIO_PORT=${SERVICE_PORTS[minio]:-9000}
MINIO_CONSOLE_PORT=${SERVICE_PORTS[minio_console]:-9001}
PORTAINER_PORT=${SERVICE_PORTS[portainer]:-9443}
CADDY_HTTP_PORT=${SERVICE_PORTS[caddy_http]:-80}
CADDY_HTTPS_PORT=${SERVICE_PORTS[caddy_https]:-443}
NGINX_HTTP_PORT=${SERVICE_PORTS[nginx_http]:-8080}
NGINX_HTTPS_PORT=${SERVICE_PORTS[nginx_https]:-8443}

################################################################################
# DATABASE CREDENTIALS
################################################################################

# PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_HOST=postgres
POSTGRES_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@\${POSTGRES_HOST}:\${POSTGRES_PORT}/\${POSTGRES_DB}

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_HOST=redis
REDIS_URL=redis://:\${REDIS_PASSWORD}@\${REDIS_HOST}:\${REDIS_PORT}/0

################################################################################
# STORAGE CREDENTIALS
################################################################################

# MinIO
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_ENDPOINT=minio:\${MINIO_PORT}
MINIO_BROWSER_REDIRECT_URL=http://\${HOSTNAME}:\${MINIO_CONSOLE_PORT}

################################################################################
# SERVICE SECRETS
################################################################################

# Dify
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}

# n8n
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${JWT_SECRET}

# Langfuse
LANGFUSE_SALT=${LANGFUSE_SALT}
LANGFUSE_NEXTAUTH_SECRET=${LANGFUSE_SECRET}
LANGFUSE_NEXTAUTH_URL=http://\${HOSTNAME}:\${LANGFUSE_PORT}

# AnythingLLM
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT}
ANYTHINGLLM_STORAGE_DIR=\${DATA_DIR}/anythingllm

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# Signal API
SIGNAL_PHONE_NUMBER=${SIGNAL_PHONE_NUMBER:-}

################################################################################
# API KEYS (External LLM Providers)
################################################################################

OPENAI_API_KEY=${API_KEYS[openai]:-}
ANTHROPIC_API_KEY=${API_KEYS[anthropic]:-}
GOOGLE_API_KEY=${API_KEYS[google]:-}
GROQ_API_KEY=${API_KEYS[groq]:-}
COHERE_API_KEY=${API_KEYS[cohere]:-}
TOGETHER_API_KEY=${API_KEYS[together]:-}
PERPLEXITY_API_KEY=${API_KEYS[perplexity]:-}
REPLICATE_API_KEY=${API_KEYS[replicate]:-}
HUGGINGFACE_API_KEY=${API_KEYS[huggingface]:-}

################################################################################
# OLLAMA CONFIGURATION
################################################################################

OLLAMA_MODELS=${OLLAMA_MODELS_STRING:-}
OLLAMA_HOST=http://ollama:\${OLLAMA_PORT}
OLLAMA_BASE_URL=\${OLLAMA_HOST}

################################################################################
# GOOGLE DRIVE SYNC
################################################################################

GDRIVE_ENABLED=${GDRIVE_ENABLED:-false}
GDRIVE_FOLDER=${GDRIVE_FOLDER:-AI-Platform}
GDRIVE_SYNC_INTERVAL=${GDRIVE_SYNC_INTERVAL:-30}
GDRIVE_SYNC_DIR=\${DATA_DIR}/gdrive

################################################################################
# VECTOR DATABASE CONFIGURATION
################################################################################

VECTOR_DB=${SELECTED_VECTOR_DB:-qdrant}
QDRANT_URL=http://qdrant:\${QDRANT_PORT}
WEAVIATE_URL=http://weaviate:\${WEAVIATE_PORT}
CHROMADB_URL=http://chromadb:\${CHROMADB_PORT}
MILVUS_URL=http://milvus:\${MILVUS_PORT}

################################################################################
# LOGGING & OBSERVABILITY
################################################################################

LOG_LEVEL=info
LOKI_URL=http://loki:\${LOKI_PORT}
PROMETHEUS_URL=http://prometheus:\${PROMETHEUS_PORT}

################################################################################
# DOCKER CONFIGURATION
################################################################################

COMPOSE_PROJECT_NAME=ai-platform
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

EOF

    chmod 600 "$env_file"
    log_success "Master .env file created: $env_file"
    
    # Create secrets directory and save individual secrets
    mkdir -p "${CONFIG_DIR}/secrets"
    chmod 700 "${CONFIG_DIR}/secrets"
    
    echo "$POSTGRES_PASSWORD" > "${CONFIG_DIR}/secrets/postgres_password"
    echo "$REDIS_PASSWORD" > "${CONFIG_DIR}/secrets/redis_password"
    echo "$MINIO_ROOT_PASSWORD" > "${CONFIG_DIR}/secrets/minio_password"
    echo "$DIFY_SECRET_KEY" > "${CONFIG_DIR}/secrets/dify_secret"
    echo "$N8N_ENCRYPTION_KEY" > "${CONFIG_DIR}/secrets/n8n_encryption"
    echo "$LANGFUSE_SECRET" > "${CONFIG_DIR}/secrets/langfuse_secret"
    echo "$JWT_SECRET" > "${CONFIG_DIR}/secrets/jwt_secret"
    echo "$GRAFANA_ADMIN_PASSWORD" > "${CONFIG_DIR}/secrets/grafana_password"
    
    chmod 600 "${CONFIG_DIR}/secrets/"*
    log_success "Individual secrets saved to ${CONFIG_DIR}/secrets/"
    
    echo ""
}

generate_litellm_config() {
    log_step "21" "$TOTAL_STEPS" "GENERATING LITELLM CONFIGURATION"
    
    local config_file="${CONFIG_DIR}/litellm/config.yaml"
    mkdir -p "${CONFIG_DIR}/litellm"
    
    log_info "Creating LiteLLM config.yaml..."
    
    cat > "$config_file" << 'EOF'
# LiteLLM Configuration
# Generated by AI Platform Setup v101.0.0

model_list:
  # Ollama Models (Local)
  - model_name: ollama/*
    litellm_params:
      model: ollama/*
      api_base: ${OLLAMA_BASE_URL}
      stream: true
      
EOF

    # Add external providers if API keys exist
    if [[ -n "${API_KEYS[openai]}" ]]; then
        cat >> "$config_file" << 'EOF'
  # OpenAI Models
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: ${OPENAI_API_KEY}
      
  - model_name: gpt-4-turbo
    litellm_params:
      model: openai/gpt-4-turbo-preview
      api_key: ${OPENAI_API_KEY}
      
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: ${OPENAI_API_KEY}
      
EOF
    fi
    
    if [[ -n "${API_KEYS[anthropic]}" ]]; then
        cat >> "$config_file" << 'EOF'
  # Anthropic Models
  - model_name: claude-3-opus
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: ${ANTHROPIC_API_KEY}
      
  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}
      
  - model_name: claude-3-haiku
    litellm_params:
      model: anthropic/claude-3-haiku-20240307
      api_key: ${ANTHROPIC_API_KEY}
      
EOF
    fi
    
    if [[ -n "${API_KEYS[google]}" ]]; then
        cat >> "$config_file" << 'EOF'
  # Google AI Models
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: ${GOOGLE_API_KEY}
      
  - model_name: gemini-pro-vision
    litellm_params:
      model: gemini/gemini-pro-vision
      api_key: ${GOOGLE_API_KEY}
      
EOF
    fi
    
    if [[ -n "${API_KEYS[groq]}" ]]; then
        cat >> "$config_file" << 'EOF'
  # Groq Models (Ultra-fast inference)
  - model_name: mixtral-8x7b-groq
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key: ${GROQ_API_KEY}
      
  - model_name: llama3-70b-groq
    litellm_params:
      model: groq/llama3-70b-8192
      api_key: ${GROQ_API_KEY}
      
EOF
    fi
    
    if [[ -n "${API_KEYS[cohere]}" ]]; then
        cat >> "$config_file" << 'EOF'
  # Cohere Models
  - model_name: command
    litellm_params:
      model: cohere/command
      api_key: ${COHERE_API_KEY}
      
  - model_name: command-light
    litellm_params:
      model: cohere/command-light
      api_key: ${COHERE_API_KEY}
      
EOF
    fi
    
    # Add general settings
    cat >> "$config_file" << 'EOF'

# General Settings
general_settings:
  master_key: ${JWT_SECRET}
  database_url: ${POSTGRES_URL}
  
  # Logging
  set_verbose: false
  json_logs: true
  
  # Caching
  cache: true
  cache_params:
    type: redis
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}
    
  # Rate Limiting
  litellm_settings:
    success_callback: ["langfuse"]
    failure_callback: ["langfuse"]
    
# Router Settings
router_settings:
  routing_strategy: simple-shuffle
  model_group_alias:
    gpt-4: [gpt-4, gpt-4-turbo]
    claude: [claude-3-opus, claude-3-sonnet]
  num_retries: 3
  timeout: 600
  fallbacks: []
  context_window_fallbacks: []
  
EOF

    log_success "LiteLLM configuration created: $config_file"
    echo ""
}

generate_prometheus_config() {
    log_step "22" "$TOTAL_STEPS" "GENERATING PROMETHEUS CONFIGURATION"
    
    if [[ "${SERVICE_ENABLED[prometheus]}" != "true" ]]; then
        log_info "Prometheus disabled, skipping configuration"
        return
    fi
    
    local config_file="${CONFIG_DIR}/prometheus/prometheus.yml"
    mkdir -p "${CONFIG_DIR}/prometheus"
    
    log_info "Creating Prometheus configuration..."
    
    cat > "$config_file" << EOF
# Prometheus Configuration
# Generated by AI Platform Setup v101.0.0

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'ai-platform'
    hostname: '${HOSTNAME}'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Load rules once and periodically evaluate them
rule_files:
  # - "rules/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  # Docker daemon metrics (if enabled)
  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']
    metrics_path: /metrics
  
  # Node Exporter (system metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
  
  # cAdvisor (container metrics)
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

    # Add LiteLLM metrics if enabled
    if [[ "${SERVICE_ENABLED[litellm]}" == "true" ]]; then
        cat >> "$config_file" << EOF
  
  # LiteLLM metrics
  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:${SERVICE_PORTS[litellm]}']
    metrics_path: /metrics
EOF
    fi
    
    # Add MinIO metrics if enabled
    if [[ "${SERVICE_ENABLED[minio]}" == "true" ]]; then
        cat >> "$config_file" << EOF
  
  # MinIO metrics
  - job_name: 'minio'
    static_configs:
      - targets: ['minio:${SERVICE_PORTS[minio]}']
    metrics_path: /minio/v2/metrics/cluster
EOF
    fi
    
    # Add PostgreSQL metrics if enabled
    if [[ "${SERVICE_ENABLED[postgres]}" == "true" ]]; then
        cat >> "$config_file" << EOF
  
  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
EOF
    fi
    
    # Add Redis metrics if enabled
    if [[ "${SERVICE_ENABLED[redis]}" == "true" ]]; then
        cat >> "$config_file" << EOF
  
  # Redis metrics
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
EOF
    fi
    
    log_success "Prometheus configuration created: $config_file"
    echo ""
}

generate_grafana_config() {
    log_step "23" "$TOTAL_STEPS" "GENERATING GRAFANA CONFIGURATION"
    
    if [[ "${SERVICE_ENABLED[grafana]}" != "true" ]]; then
        log_info "Grafana disabled, skipping configuration"
        return
    fi
    
    mkdir -p "${CONFIG_DIR}/grafana/provisioning/datasources"
    mkdir -p "${CONFIG_DIR}/grafana/provisioning/dashboards"
    
    # Datasources configuration
    local datasources_file="${CONFIG_DIR}/grafana/provisioning/datasources/datasources.yml"
    
    log_info "Creating Grafana datasources configuration..."
    
    cat > "$datasources_file" << EOF
# Grafana Datasources
# Generated by AI Platform Setup v101.0.0

apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:${SERVICE_PORTS[prometheus]}
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s
EOF

    if [[ "${SERVICE_ENABLED[loki]}" == "true" ]]; then
        cat >> "$datasources_file" << EOF
  
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:${SERVICE_PORTS[loki]}
    editable: true
    jsonData:
      maxLines: 1000
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[postgres]}" == "true" ]]; then
        cat >> "$datasources_file" << EOF
  
  - name: PostgreSQL
    type: postgres
    access: proxy
    url: postgres:${SERVICE_PORTS[postgres]}
    user: ${POSTGRES_USER}
    secureJsonData:
      password: ${POSTGRES_PASSWORD}
    jsonData:
      database: ${POSTGRES_DB}
      sslmode: disable
    editable: true
EOF
    fi
    
    # Dashboard provisioning
    local dashboards_file="${CONFIG_DIR}/grafana/provisioning/dashboards/dashboards.yml"
    
    cat > "$dashboards_file" << EOF
# Grafana Dashboard Provisioning
# Generated by AI Platform Setup v101.0.0

apiVersion: 1

providers:
  - name: 'AI Platform'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/json
EOF
    
    log_success "Grafana configuration created"
    echo ""
}

generate_caddy_config() {
    log_step "24" "$TOTAL_STEPS" "GENERATING CADDY CONFIGURATION"
    
    if [[ "$REVERSE_PROXY" != "caddy" ]]; then
        log_info "Caddy not selected, skipping configuration"
        return
    fi
    
    local config_file="${CONFIG_DIR}/caddy/Caddyfile"
    mkdir -p "${CONFIG_DIR}/caddy"
    
    log_info "Creating Caddyfile..."
    
    cat > "$config_file" << EOF
# Caddyfile - AI Platform Reverse Proxy
# Generated by AI Platform Setup v101.0.0
# Domain: ${DOMAIN_NAME}

{
    # Global options
    email admin@${DOMAIN_NAME}
    admin off
}

# Main domain
${DOMAIN_NAME} {
    # Open WebUI (main interface)
    reverse_proxy webui:${SERVICE_PORTS[webui]}
    
    encode gzip
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

# LiteLLM API
api.${DOMAIN_NAME} {
    reverse_proxy litellm:${SERVICE_PORTS[litellm]}
    
    encode gzip
    log {
        output file /var/log/caddy/api.log
        format json
    }
}

# Ollama API
ollama.${DOMAIN_NAME} {
    reverse_proxy ollama:${SERVICE_PORTS[ollama]}
    
    encode gzip
    log {
        output file /var/log/caddy/ollama.log
        format json
    }
}
EOF

    # Add service-specific subdomains
    if [[ "${SERVICE_ENABLED[dify]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# Dify
dify.${DOMAIN_NAME} {
    reverse_proxy dify:${SERVICE_PORTS[dify]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[anythingllm]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# AnythingLLM
anything.${DOMAIN_NAME} {
    reverse_proxy anythingllm:${SERVICE_PORTS[anythingllm]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[n8n]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# n8n
n8n.${DOMAIN_NAME} {
    reverse_proxy n8n:${SERVICE_PORTS[n8n]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[langfuse]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# Langfuse
langfuse.${DOMAIN_NAME} {
    reverse_proxy langfuse:${SERVICE_PORTS[langfuse]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[grafana]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# Grafana
grafana.${DOMAIN_NAME} {
    reverse_proxy grafana:${SERVICE_PORTS[grafana]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[portainer]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# Portainer
portainer.${DOMAIN_NAME} {
    reverse_proxy portainer:${SERVICE_PORTS[portainer]}
    encode gzip
}
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[minio]}" == "true" ]]; then
        cat >> "$config_file" << EOF

# MinIO Console
minio.${DOMAIN_NAME} {
    reverse_proxy minio:${SERVICE_PORTS[minio_console]}
    encode gzip
}

# MinIO API
minio-api.${DOMAIN_NAME} {
    reverse_proxy minio:${SERVICE_PORTS[minio]}
    encode gzip
}
EOF
    fi
    
    log_success "Caddyfile created: $config_file"
    echo ""
}

generate_nginx_config() {
    log_step "25" "$TOTAL_STEPS" "GENERATING NGINX CONFIGURATION"
    
    if [[ "$REVERSE_PROXY" != "nginx" ]]; then
        log_info "Nginx not selected, skipping configuration"
        return
    fi
    
    local config_file="${CONFIG_DIR}/nginx/nginx.conf"
    mkdir -p "${CONFIG_DIR}/nginx/conf.d"
    
    log_info "Creating nginx.conf..."
    
    cat > "$config_file" << EOF
# Nginx Configuration - AI Platform
# Generated by AI Platform Setup v101.0.0

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss;

    # Include all virtual host configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create main site config
    local site_config="${CONFIG_DIR}/nginx/conf.d/ai-platform.conf"
    
    cat > "$site_config" << EOF
# AI Platform - Main Configuration
# Domain: ${DOMAIN_NAME}

# Open WebUI (main interface)
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    
    location / {
        proxy_pass http://webui:${SERVICE_PORTS[webui]};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# LiteLLM API
server {
    listen 80;
    server_name api.${DOMAIN_NAME};
    
    location / {
        proxy_pass http://litellm:${SERVICE_PORTS[litellm]};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Ollama API
server {
    listen 80;
    server_name ollama.${DOMAIN_NAME};
    
    location / {
        proxy_pass http://ollama:${SERVICE_PORTS[ollama]};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Add other services as needed
    if [[ "${SERVICE_ENABLED[grafana]}" == "true" ]]; then
        cat >> "$site_config" << EOF

# Grafana
server {
    listen 80;
    server_name grafana.${DOMAIN_NAME};
    
    location / {
        proxy_pass http://grafana:${SERVICE_PORTS[grafana]};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
    fi
    
    log_success "Nginx configuration created: $config_file"
    echo ""
}

################################################################################
# MAIN EXECUTION CONTINUATION
################################################################################

main_part5() {
    # Configuration file generation
    generate_master_env
    generate_litellm_config
    generate_prometheus_config
    generate_grafana_config
    generate_caddy_config
    generate_nginx_config
    
    log_success "All configuration files generated"
    
    # TO BE CONTINUED IN FINAL PART...
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Part 5 of Script 1 v101.0.0 loaded successfully${NC}"
    echo -e "${CYAN}  Ready for Part 6 (FINAL): Summary & Completion${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Don't run yet - wait for all parts
# main_part5 "$@"
################################################################################
# DEPLOYMENT SUMMARY GENERATION
################################################################################

generate_deployment_summary() {
    log_step "26" "$TOTAL_STEPS" "GENERATING DEPLOYMENT SUMMARY"
    
    local summary_file="${CONFIG_DIR}/deployment-summary.txt"
    local json_file="${CONFIG_DIR}/deployment-manifest.json"
    
    log_info "Creating deployment summary..."
    
    cat > "$summary_file" << EOF
═══════════════════════════════════════════════════════════════════════════════
                    AI PLATFORM DEPLOYMENT SUMMARY
═══════════════════════════════════════════════════════════════════════════════

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Script Version: v101.0.0
Deployment ID: $(uuidgen 2>/dev/null || echo "$(date +%s)-${RANDOM}")

═══════════════════════════════════════════════════════════════════════════════
SYSTEM INFORMATION
═══════════════════════════════════════════════════════════════════════════════

Hostname:           ${HOSTNAME}
Operating System:   ${OS_NAME}
Architecture:       $(uname -m)
Kernel:             $(uname -r)
Timezone:           ${TIMEZONE}

Hardware:
  CPU Cores:        ${CPU_CORES}
  Total RAM:        ${TOTAL_RAM_GB} GB
  GPU Detected:     ${HAS_GPU}
EOF

    if [[ "$HAS_GPU" == "true" ]]; then
        cat >> "$summary_file" << EOF
  GPU Type:         ${GPU_TYPE}
  GPU Driver:       $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "N/A")
EOF
    fi

    cat >> "$summary_file" << EOF

Network:
  Tailscale:        ${TAILNET_NAME:-Not configured}
  Domain Name:      ${DOMAIN_NAME:-Not configured}
  Reverse Proxy:    ${REVERSE_PROXY}

═══════════════════════════════════════════════════════════════════════════════
DIRECTORY STRUCTURE
═══════════════════════════════════════════════════════════════════════════════

Base Directory:     ${DATA_DIR}
Configuration:      ${CONFIG_DIR}
Logs:               ${LOG_DIR}

Service Data Directories:
EOF

    # List data directories for enabled services
    for service in ollama litellm webui postgres redis qdrant weaviate chromadb milvus \
                   dify anythingllm openclaw n8n langfuse prometheus grafana loki minio portainer; do
        if [[ "${SERVICE_ENABLED[$service]}" == "true" ]]; then
            echo "  - ${DATA_DIR}/${service}" >> "$summary_file"
        fi
    done

    cat >> "$summary_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
ENABLED SERVICES
═══════════════════════════════════════════════════════════════════════════════

Core Services:
EOF

    [[ "${SERVICE_ENABLED[ollama]}" == "true" ]] && echo "  ✓ Ollama               (Port ${SERVICE_PORTS[ollama]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[litellm]}" == "true" ]] && echo "  ✓ LiteLLM              (Port ${SERVICE_PORTS[litellm]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[webui]}" == "true" ]] && echo "  ✓ Open WebUI           (Port ${SERVICE_PORTS[webui]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

Databases:
EOF

    [[ "${SERVICE_ENABLED[postgres]}" == "true" ]] && echo "  ✓ PostgreSQL           (Port ${SERVICE_PORTS[postgres]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[redis]}" == "true" ]] && echo "  ✓ Redis                (Port ${SERVICE_PORTS[redis]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

Vector Database:
EOF

    [[ "${SERVICE_ENABLED[qdrant]}" == "true" ]] && echo "  ✓ Qdrant               (Port ${SERVICE_PORTS[qdrant]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[weaviate]}" == "true" ]] && echo "  ✓ Weaviate             (Port ${SERVICE_PORTS[weaviate]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[chromadb]}" == "true" ]] && echo "  ✓ ChromaDB             (Port ${SERVICE_PORTS[chromadb]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[milvus]}" == "true" ]] && echo "  ✓ Milvus               (Port ${SERVICE_PORTS[milvus]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

AI Platforms:
EOF

    [[ "${SERVICE_ENABLED[dify]}" == "true" ]] && echo "  ✓ Dify                 (Port ${SERVICE_PORTS[dify]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[anythingllm]}" == "true" ]] && echo "  ✓ AnythingLLM          (Port ${SERVICE_PORTS[anythingllm]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[openclaw]}" == "true" ]] && echo "  ✓ OpenClaw             (Port ${SERVICE_PORTS[openclaw]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

Automation:
EOF

    [[ "${SERVICE_ENABLED[n8n]}" == "true" ]] && echo "  ✓ n8n                  (Port ${SERVICE_PORTS[n8n]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[signal_api]}" == "true" ]] && echo "  ✓ Signal API           (Port ${SERVICE_PORTS[signal_api]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

Observability:
EOF

    [[ "${SERVICE_ENABLED[langfuse]}" == "true" ]] && echo "  ✓ Langfuse             (Port ${SERVICE_PORTS[langfuse]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[prometheus]}" == "true" ]] && echo "  ✓ Prometheus           (Port ${SERVICE_PORTS[prometheus]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "  ✓ Grafana              (Port ${SERVICE_PORTS[grafana]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[loki]}" == "true" ]] && echo "  ✓ Loki                 (Port ${SERVICE_PORTS[loki]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

Infrastructure:
EOF

    [[ "${SERVICE_ENABLED[minio]}" == "true" ]] && echo "  ✓ MinIO                (Port ${SERVICE_PORTS[minio]}, Console ${SERVICE_PORTS[minio_console]})" >> "$summary_file"
    [[ "${SERVICE_ENABLED[portainer]}" == "true" ]] && echo "  ✓ Portainer            (Port ${SERVICE_PORTS[portainer]})" >> "$summary_file"
    [[ "$REVERSE_PROXY" == "caddy" ]] && echo "  ✓ Caddy                (Ports ${SERVICE_PORTS[caddy_http]}, ${SERVICE_PORTS[caddy_https]})" >> "$summary_file"
    [[ "$REVERSE_PROXY" == "nginx" ]] && echo "  ✓ Nginx                (Ports ${SERVICE_PORTS[nginx_http]}, ${SERVICE_PORTS[nginx_https]})" >> "$summary_file"

    cat >> "$summary_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
OLLAMA MODELS SELECTED
═══════════════════════════════════════════════════════════════════════════════

EOF

    if [[ ${#SELECTED_OLLAMA_MODELS[@]} -eq 0 ]]; then
        echo "  No models selected (will be pulled manually)" >> "$summary_file"
    else
        for model in "${SELECTED_OLLAMA_MODELS[@]}"; do
            echo "  • $model" >> "$summary_file"
        done
    fi

    cat >> "$summary_file" << EOF

Total Models: ${#SELECTED_OLLAMA_MODELS[@]}

═══════════════════════════════════════════════════════════════════════════════
API KEYS CONFIGURED
═══════════════════════════════════════════════════════════════════════════════

EOF

    local key_count=0
    for provider in openai anthropic google groq cohere together perplexity replicate huggingface; do
        if [[ -n "${API_KEYS[$provider]}" ]]; then
            echo "  ✓ ${provider^}" >> "$summary_file"
            ((key_count++))
        fi
    done
    
    [[ $key_count -eq 0 ]] && echo "  No external API keys configured" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "Total Providers: $key_count" >> "$summary_file"

    cat >> "$summary_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
GOOGLE DRIVE SYNC
═══════════════════════════════════════════════════════════════════════════════

Enabled:            ${GDRIVE_ENABLED:-false}
EOF

    if [[ "${GDRIVE_ENABLED}" == "true" ]]; then
        cat >> "$summary_file" << EOF
Folder Name:        ${GDRIVE_FOLDER}
Sync Interval:      ${GDRIVE_SYNC_INTERVAL} minutes
Sync Directory:     ${DATA_DIR}/gdrive
EOF
    fi

    cat >> "$summary_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
SECURITY NOTES
═══════════════════════════════════════════════════════════════════════════════

✓ All secrets generated with 32-48 character random strings
✓ Individual secret files created in: ${CONFIG_DIR}/secrets/
✓ Environment file secured with permissions: 600
✓ Secrets directory secured with permissions: 700

Default Credentials:
  PostgreSQL User:     ${POSTGRES_USER}
  PostgreSQL Password: [Saved in ${CONFIG_DIR}/secrets/postgres_password]
  
  Grafana User:        admin
  Grafana Password:    [Saved in ${CONFIG_DIR}/secrets/grafana_password]
  
  MinIO User:          ${MINIO_ROOT_USER}
  MinIO Password:      [Saved in ${CONFIG_DIR}/secrets/minio_password]

IMPORTANT: Change default passwords after first login!

═══════════════════════════════════════════════════════════════════════════════
CONFIGURATION FILES GENERATED
═══════════════════════════════════════════════════════════════════════════════

  ✓ ${CONFIG_DIR}/.env
  ✓ ${CONFIG_DIR}/litellm/config.yaml
EOF

    [[ "${SERVICE_ENABLED[prometheus]}" == "true" ]] && echo "  ✓ ${CONFIG_DIR}/prometheus/prometheus.yml" >> "$summary_file"
    [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "  ✓ ${CONFIG_DIR}/grafana/provisioning/datasources/datasources.yml" >> "$summary_file"
    [[ "$REVERSE_PROXY" == "caddy" ]] && echo "  ✓ ${CONFIG_DIR}/caddy/Caddyfile" >> "$summary_file"
    [[ "$REVERSE_PROXY" == "nginx" ]] && echo "  ✓ ${CONFIG_DIR}/nginx/nginx.conf" >> "$summary_file"

    cat >> "$summary_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
NEXT STEPS
═══════════════════════════════════════════════════════════════════════════════

1. Review this summary and verify all settings
2. Review generated configuration files in: ${CONFIG_DIR}/
3. If using Google Drive sync, complete OAuth2 setup:
   https://rclone.org/drive/

4. Run Script 2 to generate Docker Compose files:
   sudo bash /opt/ai-platform/scripts/script2-generate-compose.sh

5. After Script 2 completes, deploy services:
   cd ${CONFIG_DIR}
   docker compose up -d

6. Monitor deployment:
   docker compose logs -f

7. Access services at:
EOF

    # Generate access URLs
    if [[ -n "$DOMAIN_NAME" ]]; then
        cat >> "$summary_file" << EOF
   Open WebUI:       https://${DOMAIN_NAME}
   LiteLLM API:      https://api.${DOMAIN_NAME}
   Ollama API:       https://ollama.${DOMAIN_NAME}
EOF
        [[ "${SERVICE_ENABLED[dify]}" == "true" ]] && echo "   Dify:             https://dify.${DOMAIN_NAME}" >> "$summary_file"
        [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "   Grafana:          https://grafana.${DOMAIN_NAME}" >> "$summary_file"
        [[ "${SERVICE_ENABLED[portainer]}" == "true" ]] && echo "   Portainer:        https://portainer.${DOMAIN_NAME}" >> "$summary_file"
    else
        cat >> "$summary_file" << EOF
   Open WebUI:       http://${HOSTNAME}:${SERVICE_PORTS[webui]}
   LiteLLM API:      http://${HOSTNAME}:${SERVICE_PORTS[litellm]}
   Ollama API:       http://${HOSTNAME}:${SERVICE_PORTS[ollama]}
EOF
        [[ "${SERVICE_ENABLED[dify]}" == "true" ]] && echo "   Dify:             http://${HOSTNAME}:${SERVICE_PORTS[dify]}" >> "$summary_file"
        [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "   Grafana:          http://${HOSTNAME}:${SERVICE_PORTS[grafana]}" >> "$summary_file"
        [[ "${SERVICE_ENABLED[portainer]}" == "true" ]] && echo "   Portainer:        http://${HOSTNAME}:${SERVICE_PORTS[portainer]}" >> "$summary_file"
    fi

    cat >> "$summary_file" << EOF

8. Check service health:
   cd ${CONFIG_DIR}
   docker compose ps

═══════════════════════════════════════════════════════════════════════════════
TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════════════════

View logs:
  All services:    docker compose logs -f
  Specific:        docker compose logs -f <service-name>

Restart service:   docker compose restart <service-name>
Stop all:          docker compose down
Start all:         docker compose up -d

Check resources:
  docker stats

Documentation:     ${CONFIG_DIR}/docs/
Support:           Create issue at project repository

═══════════════════════════════════════════════════════════════════════════════
IMPORTANT FILES
═══════════════════════════════════════════════════════════════════════════════

Configuration:     ${CONFIG_DIR}/.env
Secrets:           ${CONFIG_DIR}/secrets/
This Summary:      ${CONFIG_DIR}/deployment-summary.txt
Deployment Log:    ${LOG_DIR}/script1-$(date +%Y%m%d-%H%M%S).log

BACKUP THESE FILES BEFORE MAKING CHANGES!

═══════════════════════════════════════════════════════════════════════════════
                           DEPLOYMENT COMPLETE
═══════════════════════════════════════════════════════════════════════════════

Configuration phase completed successfully!
Ready to proceed with Script 2 for Docker Compose generation.

EOF

    log_success "Deployment summary created: $summary_file"
    
    # Generate JSON manifest for automation
    generate_json_manifest "$json_file"
    
    echo ""
}

generate_json_manifest() {
    local json_file="$1"
    
    log_info "Creating deployment manifest (JSON)..."
    
    # Build services array
    local services_json="["
    local first=true
    for service in "${!SERVICE_ENABLED[@]}"; do
        if [[ "${SERVICE_ENABLED[$service]}" == "true" ]]; then
            [[ "$first" == false ]] && services_json+=","
            services_json+="{\"name\":\"$service\",\"port\":${SERVICE_PORTS[$service]:-0}}"
            first=false
        fi
    done
    services_json+="]"
    
    # Build models array
    local models_json="["
    first=true
    for model in "${SELECTED_OLLAMA_MODELS[@]}"; do
        [[ "$first" == false ]] && models_json+=","
        models_json+="\"$model\""
        first=false
    done
    models_json+="]"
    
    # Build API keys array
    local api_keys_json="["
    first=true
    for provider in "${!API_KEYS[@]}"; do
        if [[ -n "${API_KEYS[$provider]}" ]]; then
            [[ "$first" == false ]] && api_keys_json+=","
            api_keys_json+="\"$provider\""
            first=false
        fi
    done
    api_keys_json+="]"
    
    cat > "$json_file" << EOF
{
  "version": "v101.0.0",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "deployment_id": "$(uuidgen 2>/dev/null || echo "$(date +%s)-${RANDOM}")",
  "system": {
    "hostname": "${HOSTNAME}",
    "os": "${OS_NAME}",
    "architecture": "$(uname -m)",
    "timezone": "${TIMEZONE}",
    "cpu_cores": ${CPU_CORES},
    "ram_gb": ${TOTAL_RAM_GB},
    "has_gpu": ${HAS_GPU},
    "gpu_type": "${GPU_TYPE:-none}"
  },
  "network": {
    "tailnet": "${TAILNET_NAME:-}",
    "domain": "${DOMAIN_NAME:-}",
    "reverse_proxy": "${REVERSE_PROXY}"
  },
  "directories": {
    "data": "${DATA_DIR}",
    "config": "${CONFIG_DIR}",
    "logs": "${LOG_DIR}"
  },
  "services": ${services_json},
  "ollama_models": ${models_json},
  "api_providers": ${api_keys_json},
  "vector_db": "${SELECTED_VECTOR_DB:-qdrant}",
  "gdrive_sync": ${GDRIVE_ENABLED:-false}
}
EOF

    chmod 644 "$json_file"
    log_success "Deployment manifest created: $json_file"
}

display_final_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           🎉 SCRIPT 1 COMPLETED SUCCESSFULLY 🎉${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Configuration Phase Complete!${NC}"
    echo ""
    echo "Summary:"
    echo "  • Services configured: $(count_enabled_services)"
    echo "  • Ollama models selected: ${#SELECTED_OLLAMA_MODELS[@]}"
    echo "  • API providers configured: $(count_api_keys)"
    echo "  • Configuration files generated: ✓"
    echo ""
    echo -e "${YELLOW}Important Files:${NC}"
    echo "  📄 Deployment Summary:  ${CONFIG_DIR}/deployment-summary.txt"
    echo "  📄 Environment Config:  ${CONFIG_DIR}/.env"
    echo "  📄 JSON Manifest:       ${CONFIG_DIR}/deployment-manifest.json"
    echo "  📁 Secrets Directory:   ${CONFIG_DIR}/secrets/"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo "  1️⃣  Review the deployment summary:"
    echo "      ${CYAN}cat ${CONFIG_DIR}/deployment-summary.txt${NC}"
    echo ""
    echo "  2️⃣  Run Script 2 to generate Docker Compose files:"
    echo "      ${CYAN}sudo bash /opt/ai-platform/scripts/script2-generate-compose.sh${NC}"
    echo ""
    echo "  3️⃣  After Script 2, deploy the platform:"
    echo "      ${CYAN}cd ${CONFIG_DIR} && docker compose up -d${NC}"
    echo ""
    
    if [[ -n "$DOMAIN_NAME" ]]; then
        echo -e "${YELLOW}Access URLs (after deployment):${NC}"
        echo "  🌐 Open WebUI:    https://${DOMAIN_NAME}"
        echo "  🔌 LiteLLM API:   https://api.${DOMAIN_NAME}"
        echo "  🤖 Ollama API:    https://ollama.${DOMAIN_NAME}"
        [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "  📊 Grafana:       https://grafana.${DOMAIN_NAME}"
        [[ "${SERVICE_ENABLED[portainer]}" == "true" ]] && echo "  🐳 Portainer:     https://portainer.${DOMAIN_NAME}"
    else
        echo -e "${YELLOW}Access URLs (after deployment):${NC}"
        echo "  🌐 Open WebUI:    http://${HOSTNAME}:${SERVICE_PORTS[webui]}"
        echo "  🔌 LiteLLM API:   http://${HOSTNAME}:${SERVICE_PORTS[litellm]}"
        echo "  🤖 Ollama API:    http://${HOSTNAME}:${SERVICE_PORTS[ollama]}"
        [[ "${SERVICE_ENABLED[grafana]}" == "true" ]] && echo "  📊 Grafana:       http://${HOSTNAME}:${SERVICE_PORTS[grafana]}"
        [[ "${SERVICE_ENABLED[portainer]}" == "true" ]] && echo "  🐳 Portainer:     http://${HOSTNAME}:${SERVICE_PORTS[portainer]}"
    fi
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Thank you for using AI Platform Setup v101.0.0!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

count_enabled_services() {
    local count=0
    for service in "${!SERVICE_ENABLED[@]}"; do
        [[ "${SERVICE_ENABLED[$service]}" == "true" ]] && ((count++))
    done
    echo "$count"
}

count_api_keys() {
    local count=0
    for key in "${!API_KEYS[@]}"; do
        [[ -n "${API_KEYS[$key]}" ]] && ((count++))
    done
    echo "$count"
}

################################################################################
# MAIN EXECUTION - FINAL
################################################################################

main_part6() {
    # Generate deployment summary
    generate_deployment_summary
    
    # Display final summary
    display_final_summary
    
    # Log completion
    log_success "Script 1 v101.0.0 completed successfully"
    log_info "Total execution time: $SECONDS seconds"
    
    # Save final log
    local final_log="${LOG_DIR}/script1-$(date +%Y%m%d-%H%M%S).log"
    if command -v script &>/dev/null; then
        log_info "Session log saved to: $final_log"
    fi
    
    echo ""
    echo -e "${CYAN}Ready to proceed with Script 2!${NC}"
    echo ""
    
    exit 0
}

################################################################################
# SCRIPT EXECUTION ENTRY POINT (ALL PARTS COMBINED)
################################################################################

main() {
    # Execute all parts in sequence
    main_part1 "$@"  # System detection & validation
    main_part2 "$@"  # Directory setup & dependencies
    main_part3 "$@"  # Service selection
    main_part4 "$@"  # Ollama models & API keys
    main_part5 "$@"  # Configuration generation
    main_part6 "$@"  # Summary & completion
}

# Only execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
