#!/bin/bash
# ==============================================================================
# AI PLATFORM — Script 1: System Setup & Prerequisites
# ==============================================================================
# Version : 1.0.0
# Requires : Ubuntu 22.04 / 24.04 LTS, root privileges
# Purpose  : Prepare the host with all prerequisites for AI Platform
# Installs : Docker Engine, Docker Compose, NVIDIA Container Toolkit,
#            Ollama, UFW firewall rules, swap configuration
# Layout   : Static config in ROOT_PATH (parent of scripts/)
#            Dynamic data  in DATA_PATH (/mnt/data)
# Output   : ${ROOT_PATH}/.setup-complete marker on success
# ==============================================================================

set -euo pipefail

# ==============================================================================
# PATH DETECTION — ROOT_PATH is parent of scripts/ directory
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DATA_PATH="/mnt/data"

# ==============================================================================
# CONSTANTS
# ==============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="${DATA_PATH}/logs"
readonly LOG_FILE="${LOG_DIR}/1-setup-system-$(date +%Y%m%d-%H%M%S).log"
readonly MARKER_FILE="${ROOT_PATH}/.setup-complete"
readonly MIN_RAM_GB=8
readonly MIN_DISK_GB=50
readonly REQUIRED_UBUNTU_VERSIONS=("22.04" "24.04")
readonly SWAP_SIZE="8G"
readonly DOCKER_COMPOSE_MIN_VERSION="2.20"
readonly DEFAULT_MODELS=("llama3.2:latest" "nomic-embed-text:latest")

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Counters
TOTAL_STEPS=13
CURRENT_STEP=0
WARNINGS=0
ERRORS=0
GPU_DETECTED=false

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================
init_logging() {
    mkdir -p "$LOG_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "=== AI Platform Setup Log: $(date) ===" >> "$LOG_FILE"
}

log_info()    { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; ((WARNINGS++)) || true; }
log_error()   { echo -e "${RED}✗${NC}  $1"; ((ERRORS++)) || true; }

log_step() {
    ((CURRENT_STEP++)) || true
    echo ""
    echo -e "${CYAN}${BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}] $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================
command_exists() { command -v "$1" &>/dev/null; }
pkg_installed()  { dpkg -s "$1" &>/dev/null; }

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           AI PLATFORM — System Setup (Script 1)            ║"
    echo "║                     Version ${SCRIPT_VERSION}                          ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  ROOT_PATH : ${ROOT_PATH}"
    echo "║  DATA_PATH : ${DATA_PATH}"
    echo "║  Log file  : ${LOG_FILE}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ==============================================================================
# STEP 1 — PREFLIGHT CHECKS
# ==============================================================================
preflight_checks() {
    log_step "Preflight checks"

    # Root check
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
    log_success "Running as root"

    # OS check
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS — /etc/os-release missing"
        exit 1
    fi
    source /etc/os-release
    local version_ok=false
    for v in "${REQUIRED_UBUNTU_VERSIONS[@]}"; do
        if [[ "$VERSION_ID" == "$v" ]]; then
            version_ok=true
            break
        fi
    done
    if [[ "$version_ok" == true ]]; then
        log_success "Ubuntu ${VERSION_ID} detected"
    else
        log_error "Ubuntu ${REQUIRED_UBUNTU_VERSIONS[*]} required (found: ${VERSION_ID})"
        exit 1
    fi

    # RAM check
    local ram_gb
    ram_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    if [[ "$ram_gb" -ge "$MIN_RAM_GB" ]]; then
        log_success "RAM: ${ram_gb} GB (minimum: ${MIN_RAM_GB} GB)"
    else
        log_error "Insufficient RAM: ${ram_gb} GB (minimum: ${MIN_RAM_GB} GB)"
        exit 1
    fi

    # Disk check
    local disk_gb
    disk_gb=$(df / --output=avail -BG | tail -1 | tr -d 'G ')
    if [[ "$disk_gb" -ge "$MIN_DISK_GB" ]]; then
        log_success "Disk: ${disk_gb} GB free (minimum: ${MIN_DISK_GB} GB)"
    else
        log_error "Insufficient disk: ${disk_gb} GB free (minimum: ${MIN_DISK_GB} GB)"
        exit 1
    fi

    # GPU detection
    if command_exists nvidia-smi || lspci 2>/dev/null | grep -qi nvidia; then
        GPU_DETECTED=true
        log_success "NVIDIA GPU detected"
    else
        GPU_DETECTED=false
        log_warn "No NVIDIA GPU detected — will run in CPU-only mode"
    fi
}

# ==============================================================================
# STEP 2 — DIRECTORY STRUCTURE
# ==============================================================================
create_directory_structure() {
    log_step "Creating directory structure"

    # Static directories under ROOT_PATH
    local static_dirs=(
        "${ROOT_PATH}/config"
        "${ROOT_PATH}/compose"
        "${ROOT_PATH}/scripts"
        "${ROOT_PATH}/secrets"
    )

    # Dynamic directories under DATA_PATH
    local dynamic_dirs=(
        "${DATA_PATH}/ollama"
        "${DATA_PATH}/postgres"
        "${DATA_PATH}/redis"
        "${DATA_PATH}/dify"
        "${DATA_PATH}/n8n"
        "${DATA_PATH}/caddy"
        "${DATA_PATH}/grafana"
        "${DATA_PATH}/prometheus"
        "${DATA_PATH}/langfuse"
        "${DATA_PATH}/openwebui"
        "${DATA_PATH}/backups"
        "${DATA_PATH}/logs"
    )

    for dir in "${static_dirs[@]}"; do
        mkdir -p "$dir"
        log_success "Static:  ${dir}"
    done

    for dir in "${dynamic_dirs[@]}"; do
        mkdir -p "$dir"
        log_success "Dynamic: ${dir}"
    done

    # Set permissions on secrets
    chmod 700 "${ROOT_PATH}/secrets"
    log_success "Permissions set on ${ROOT_PATH}/secrets (700)"
}

# ==============================================================================
# STEP 3 — UPDATE SYSTEM PACKAGES
# ==============================================================================
update_system_packages() {
    log_step "Updating system packages"

    log_info "Running apt-get update..."
    if apt-get update -y >> "$LOG_FILE" 2>&1; then
        log_success "Package index updated"
    else
        log_warn "apt-get update had warnings (continuing)"
    fi

    log_info "Running apt-get upgrade..."
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
        log_success "System packages upgraded"
    else
        log_warn "apt-get upgrade had warnings (continuing)"
    fi
}

# ==============================================================================
# STEP 4 — INSTALL DEPENDENCIES
# ==============================================================================
install_dependencies() {
    log_step "Installing required packages"

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
        htop
        unzip
        net-tools
        fail2ban
    )

    local failed=0
    for pkg in "${packages[@]}"; do
        if pkg_installed "$pkg"; then
            log_success "${pkg} (already installed)"
        else
            log_info "Installing ${pkg}..."
            if DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1; then
                if pkg_installed "$pkg"; then
                    log_success "${pkg}"
                else
                    log_error "${pkg} — install reported OK but verification failed"
                    ((failed++)) || true
                fi
            else
                log_error "${pkg} — failed to install"
                ((failed++)) || true
            fi
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_error "${failed} package(s) failed to install"
        exit 1
    fi
}

# ==============================================================================
# STEP 5 — INSTALL DOCKER ENGINE
# ==============================================================================
install_docker() {
    log_step "Installing Docker Engine"

    if command_exists docker; then
        local docker_ver
        docker_ver=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_success "Docker already installed: v${docker_ver}"
    else
        log_info "Adding Docker GPG key and repository..."

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "$LOG_FILE"
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -y >> "$LOG_FILE" 2>&1

        log_info "Installing Docker packages..."
        if DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1; then
            log_success "Docker packages installed"
        else
            log_error "Docker installation failed"
            exit 1
        fi
    fi

    # Enable and start Docker
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl start docker >> "$LOG_FILE" 2>&1

    # Wait for Docker socket
    local retries=0
    while [[ $retries -lt 15 ]]; do
        if docker info &>/dev/null; then
            break
        fi
        sleep 2
        ((retries++)) || true
    done

    if docker info &>/dev/null; then
        log_success "Docker engine is running"
    else
        log_error "Docker failed to start"
        exit 1
    fi

    # Verify Docker Compose
    if docker compose version &>/dev/null; then
        local compose_ver
        compose_ver=$(docker compose version --short 2>/dev/null || docker compose version | grep -oP '\d+\.\d+\.\d+')
        log_success "Docker Compose: v${compose_ver}"
    else
        log_error "Docker Compose plugin not available"
        exit 1
    fi
}

# ==============================================================================
# STEP 6 — CREATE DOCKER NETWORK
# ==============================================================================
create_docker_network() {
    log_step "Creating Docker network"

    if docker network inspect ai-platform &>/dev/null; then
        log_success "Network 'ai-platform' already exists"
    else
        if docker network create ai-platform >> "$LOG_FILE" 2>&1; then
            log_success "Network 'ai-platform' created"
        else
            log_error "Failed to create Docker network"
            exit 1
        fi
    fi
}

# ==============================================================================
# STEP 7 — NVIDIA CONTAINER TOOLKIT (conditional)
# ==============================================================================
install_nvidia_toolkit() {
    log_step "NVIDIA Container Toolkit"

    if [[ "$GPU_DETECTED" != true ]]; then
        log_info "No NVIDIA GPU detected — skipping toolkit installation"
        return 0
    fi

    if command_exists nvidia-container-cli; then
        log_success "NVIDIA Container Toolkit already installed"
    else
        log_info "Adding NVIDIA Container Toolkit repository..."

        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
            gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>> "$LOG_FILE"

        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

        apt-get update -y >> "$LOG_FILE" 2>&1

        if DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit >> "$LOG_FILE" 2>&1; then
            log_success "NVIDIA Container Toolkit installed"
        else
            log_warn "NVIDIA Container Toolkit installation failed — GPU features may not work"
            return 0
        fi
    fi

    # Configure Docker runtime
    if nvidia-ctk runtime configure --runtime=docker >> "$LOG_FILE" 2>&1; then
        systemctl restart docker >> "$LOG_FILE" 2>&1
        sleep 3
        log_success "Docker configured with NVIDIA runtime"
    else
        log_warn "Failed to configure NVIDIA Docker runtime"
    fi

    # Quick validation
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_success "NVIDIA GPU accessible from Docker containers"
    else
        log_warn "GPU test container failed — GPU may not be available in containers"
    fi
}

# ==============================================================================
# STEP 8 — INSTALL OLLAMA
# ==============================================================================
install_ollama() {
    log_step "Installing Ollama"

    if command_exists ollama; then
        local ollama_ver
        ollama_ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
        log_success "Ollama already installed: ${ollama_ver}"
    else
        log_info "Installing Ollama via official installer..."
        if curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1; then
            log_success "Ollama installed"
        else
            log_error "Ollama installation failed"
            exit 1
        fi
    fi

    # Configure Ollama data directory to use DATA_PATH
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=${DATA_PATH}/ollama"
EOF

    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable ollama >> "$LOG_FILE" 2>&1
    systemctl restart ollama >> "$LOG_FILE" 2>&1

    # Wait for Ollama to be ready
    log_info "Waiting for Ollama to become ready..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            break
        fi
        sleep 2
        ((retries++)) || true
    done

    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_success "Ollama is running on port 11434"
        log_success "Model storage: ${DATA_PATH}/ollama"
    else
        log_error "Ollama failed to start"
        exit 1
    fi
}

# ==============================================================================
# STEP 9 — PULL DEFAULT OLLAMA MODELS
# ==============================================================================
pull_ollama_models() {
    log_step "Pulling default Ollama models"

    for model in "${DEFAULT_MODELS[@]}"; do
        log_info "Checking model: ${model}..."

        # Check if model already exists
        if ollama list 2>/dev/null | grep -q "${model%%:*}"; then
            log_success "${model} (already available)"
        else
            log_info "Pulling ${model} — this may take several minutes..."
            if ollama pull "$model" >> "$LOG_FILE" 2>&1; then
                log_success "${model} pulled successfully"
            else
                log_warn "Failed to pull ${model} — you can pull it manually later"
            fi
        fi
    done

    # Show available models
    echo ""
    log_info "Available Ollama models:"
    ollama list 2>/dev/null | head -20 || true
}

# ==============================================================================
# STEP 10 — CONFIGURE FIREWALL (UFW)
# ==============================================================================
configure_firewall() {
    log_step "Configuring firewall (UFW)"

    if ! command_exists ufw; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >> "$LOG_FILE" 2>&1
    fi

    # Reset to defaults
    ufw --force reset >> "$LOG_FILE" 2>&1

    # Default policies
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1

    # Allow essential ports
    ufw allow 22/tcp comment 'SSH' >> "$LOG_FILE" 2>&1
    log_success "Allowed: 22/tcp (SSH)"

    ufw allow 80/tcp comment 'HTTP' >> "$LOG_FILE" 2>&1
    log_success "Allowed: 80/tcp (HTTP)"

    ufw allow 443/tcp comment 'HTTPS' >> "$LOG_FILE" 2>&1
    log_success "Allowed: 443/tcp (HTTPS)"

    # Enable UFW
    ufw --force enable >> "$LOG_FILE" 2>&1
    log_success "UFW firewall enabled"

    # Show status
    ufw status verbose 2>/dev/null | head -15 || true
}

# ==============================================================================
# STEP 11 — CONFIGURE SWAP
# ==============================================================================
configure_swap() {
    log_step "Configuring swap space"

    local swapfile="/swapfile"
    local current_swap
    current_swap=$(swapon --show --noheadings 2>/dev/null | wc -l)

    if [[ "$current_swap" -gt 0 ]]; then
        local swap_total
        swap_total=$(free -h | awk '/^Swap:/ {print $2}')
        log_success "Swap already configured: ${swap_total}"
        return 0
    fi

    log_info "Creating ${SWAP_SIZE} swap file..."

    if fallocate -l "${SWAP_SIZE}" "$swapfile" 2>> "$LOG_FILE"; then
        chmod 600 "$swapfile"
        mkswap "$swapfile" >> "$LOG_FILE" 2>&1
        swapon "$swapfile" >> "$LOG_FILE" 2>&1

        # Persist in fstab
        if ! grep -q "$swapfile" /etc/fstab; then
            echo "${swapfile} none swap sw 0 0" >> /etc/fstab
        fi

        log_success "Swap configured: ${SWAP_SIZE}"
    else
        log_warn "Failed to create swap file — continuing without swap"
    fi
}

# ==============================================================================
# STEP 12 — SYSTEM TUNING
# ==============================================================================
configure_system_tuning() {
    log_step "Applying system tuning"

    local sysctl_file="/etc/sysctl.d/99-ai-platform.conf"
    cat > "$sysctl_file" <<'SYSCTL'
# AI Platform system tuning
vm.swappiness=10
vm.overcommit_memory=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
fs.file-max=2097152
fs.inotify.max_user_watches=524288
SYSCTL

    if sysctl --system >> "$LOG_FILE" 2>&1; then
        log_success "Kernel parameters applied"
    else
        log_warn "Some kernel parameters could not be applied"
    fi

    # Docker daemon.json tuning
    local docker_daemon="/etc/docker/daemon.json"
    if [[ ! -f "$docker_daemon" ]] || [[ ! -s "$docker_daemon" ]]; then
        cat > "$docker_daemon" <<'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {"base": "172.20.0.0/16", "size": 24}
  ]
}
DAEMON
        systemctl restart docker >> "$LOG_FILE" 2>&1
        sleep 3
        log_success "Docker daemon tuning applied"
    else
        log_success "Docker daemon.json already configured"
    fi
}

# ==============================================================================
# STEP 13 — FINAL HEALTH CHECK
# ==============================================================================
final_health_check() {
    log_step "Final health check"

    local checks_passed=0
    local checks_total=6

    # 1. Docker
    if docker info &>/dev/null; then
        log_success "Docker engine: running"
        ((checks_passed++)) || true
    else
        log_error "Docker engine: NOT running"
    fi

    # 2. Docker Compose
    if docker compose version &>/dev/null; then
        log_success "Docker Compose: available"
        ((checks_passed++)) || true
    else
        log_error "Docker Compose: NOT available"
    fi

    # 3. Docker network
    if docker network inspect ai-platform &>/dev/null; then
        log_success "Docker network 'ai-platform': exists"
        ((checks_passed++)) || true
    else
        log_error "Docker network 'ai-platform': MISSING"
    fi

    # 4. Ollama
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_success "Ollama API: responding on :11434"
        ((checks_passed++)) || true
    else
        log_error "Ollama API: NOT responding"
    fi

    # 5. UFW
    if ufw status | grep -q "Status: active"; then
        log_success "UFW firewall: active"
        ((checks_passed++)) || true
    else
        log_warn "UFW firewall: inactive"
    fi

    # 6. Directory structure
    if [[ -d "${ROOT_PATH}/config" && -d "${DATA_PATH}/ollama" ]]; then
        log_success "Directory structure: verified"
        ((checks_passed++)) || true
    else
        log_error "Directory structure: incomplete"
    fi

    echo ""
    log_info "Health check: ${checks_passed}/${checks_total} passed"

    if [[ $checks_passed -lt 4 ]]; then
        log_error "Too many health checks failed — review log: ${LOG_FILE}"
        exit 1
    fi

    # Write marker file
    cat > "$MARKER_FILE" <<EOF
setup_complete=true
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
script_version=${SCRIPT_VERSION}
root_path=${ROOT_PATH}
data_path=${DATA_PATH}
gpu_detected=${GPU_DETECTED}
docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
ollama_version=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
EOF
    log_success "Marker file written: ${MARKER_FILE}"
}

# ==============================================================================
# SUMMARY
# ==============================================================================
show_summary() {
    local ip_addr
    ip_addr=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          ✓ SCRIPT 1 COMPLETE — System Ready                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Host IP   : ${ip_addr}"
    echo "║  ROOT_PATH : ${ROOT_PATH}"
    echo "║  DATA_PATH : ${DATA_PATH}"
    echo "║  GPU       : ${GPU_DETECTED}"
    echo "║  Warnings  : ${WARNINGS}"
    echo "║  Errors    : ${ERRORS}"
    echo "║  Log       : ${LOG_FILE}"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  NEXT STEP:                                                ║"
    echo "║  sudo bash ${ROOT_PATH}/scripts/2-deploy.sh               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    show_banner
    init_logging

    preflight_checks              # Step 1
    create_directory_structure    # Step 2
    update_system_packages        # Step 3
    install_dependencies          # Step 4
    install_docker                # Step 5
    create_docker_network         # Step 6
    install_nvidia_toolkit        # Step 7
    install_ollama                # Step 8
    pull_ollama_models            # Step 9
    configure_firewall            # Step 10
    configure_swap                # Step 11
    configure_system_tuning       # Step 12
    final_health_check            # Step 13

    show_summary
    log_success "Script 1 finished at $(date)"
}

main "$@"
