#!/bin/bash

#==============================================================================
# Script 1: System Setup
# Purpose: Prepare Ubuntu 24.04 system for AI platform deployment
# Features:
#   - System requirements check
#   - Docker installation
#   - Tailscale setup
#   - Storage configuration
#   - GPU detection and NVIDIA setup
#   - Directory structure creation
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Color Definitions
#------------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/mnt/data"
MIN_DISK_GB=50
MIN_RAM_GB=8
TAILSCALE_INSTALLED=false
TAILSCALE_IP=""
GPU_AVAILABLE=false

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}AI PLATFORM AUTOMATION - SYSTEM SETUP${NC}           ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Script 1 of 5${NC} - Preparing your system                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -n "  "
    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 10))
        printf "\r${CYAN}${spin:$i:1}${NC} $msg"
        sleep 0.1
    done
    printf "\r"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$(echo -e ${YELLOW}$prompt${NC})" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# System Checks
#------------------------------------------------------------------------------

check_os() {
    print_step "Checking operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu only"
        print_info "Detected: $PRETTY_NAME"
        exit 1
    fi
    
    if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "22.04" ]]; then
        print_warning "Tested on Ubuntu 24.04 LTS"
        print_info "Your version: $VERSION_ID"
        
        if ! confirm "Continue anyway?" n; then
            exit 0
        fi
    fi
    
    print_success "OS Check: $PRETTY_NAME"
}

check_internet() {
    print_step "Checking internet connectivity..."
    
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    
    if ! curl -s --head --max-time 3 https://www.google.com &>/dev/null; then
        print_error "Cannot reach internet (DNS/firewall issue?)"
        exit 1
    fi
    
    print_success "Internet connectivity OK"
}

check_system_resources() {
    print_step "Checking system resources..."
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))
    
    if [[ $total_ram_gb -lt $MIN_RAM_GB ]]; then
        print_error "Insufficient RAM: ${total_ram_gb}GB (minimum: ${MIN_RAM_GB}GB)"
        exit 1
    fi
    
    print_success "RAM: ${total_ram_gb}GB"
    
    # Check disk space
    local available_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [[ $available_space_gb -lt $MIN_DISK_GB ]]; then
        print_error "Insufficient disk space: ${available_space_gb}GB (minimum: ${MIN_DISK_GB}GB)"
        exit 1
    fi
    
    print_success "Available disk space: ${available_space_gb}GB"
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    print_success "CPU cores: $cpu_cores"
    
    if [[ $cpu_cores -lt 4 ]]; then
        print_warning "Recommended minimum: 4 CPU cores (detected: $cpu_cores)"
        if ! confirm "Continue anyway?" n; then
            exit 0
        fi
    fi
}

check_gpu() {
    print_step "Detecting GPU..."
    
    if command -v nvidia-smi &>/dev/null; then
        local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        
        if [[ -n "$gpu_info" ]]; then
            GPU_AVAILABLE=true
            print_success "NVIDIA GPU detected: $gpu_info"
            return 0
        fi
    fi
    
    if lspci | grep -i nvidia &>/dev/null; then
        print_warning "NVIDIA GPU detected but drivers not installed"
        print_info "GPU support will be configured during setup"
        GPU_AVAILABLE=true
    else
        print_info "No GPU detected - will use CPU only"
        GPU_AVAILABLE=false
    fi
}

#------------------------------------------------------------------------------
# Storage Configuration
#------------------------------------------------------------------------------

select_storage_location() {
    print_header
    echo -e "${BOLD}Storage Configuration${NC}"
    echo ""
    echo "The platform requires a persistent storage location for:"
    echo "  • Docker volumes (containers, images)"
    echo "  • Service data (databases, vector stores)"
    echo "  • Configuration files"
    echo "  • Backups"
    echo ""
    echo "Available options:"
    echo ""
    
    # List mounted filesystems
    local i=1
    local options=()
    
    while IFS= read -r line; do
        local mount_point=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local avail=$(echo "$line" | awk '{print $4}')
        local percent=$(echo "$line" | awk '{print $5}')
        
        options+=("$mount_point")
        echo -e "  ${CYAN}$i)${NC} $mount_point"
        echo -e "     Size: $size | Available: $avail | Used: $percent"
        echo ""
        ((i++))
    done < <(df -h | grep -E '^/dev/' | grep -v '/boot' | grep -v '/snap')
    
    echo -e "  ${CYAN}$i)${NC} Custom path"
    echo ""
    
    local selection
    read -p "Select storage location [1-$i]: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -lt $i ]]; then
        local selected_mount="${options[$((selection-1))]}"
        DATA_DIR="${selected_mount}/ai-platform-data"
        print_success "Selected: $DATA_DIR"
    elif [[ $selection -eq $i ]]; then
        read -p "Enter custom path: " DATA_DIR
        DATA_DIR="${DATA_DIR%/}"  # Remove trailing slash
        print_info "Custom path: $DATA_DIR"
    else
        print_error "Invalid selection"
        exit 1
    fi
    
    # Confirm
    echo ""
    echo -e "${YELLOW}Data will be stored at: ${BOLD}$DATA_DIR${NC}"
    
    if [[ -d "$DATA_DIR" ]]; then
        print_warning "Directory already exists"
        if ! confirm "Use existing directory?" n; then
            exit 0
        fi
    else
        if ! confirm "Create this directory?" y; then
            exit 0
        fi
    fi
}

create_directory_structure() {
    print_step "Creating directory structure..."
    
    local dirs=(
        "$DATA_DIR"
        "$DATA_DIR/compose"
        "$DATA_DIR/env"
        "$DATA_DIR/config"
        "$DATA_DIR/metadata"
        "$DATA_DIR/backups/postgres"
        "$DATA_DIR/backups/redis"
        "$DATA_DIR/backups/qdrant"
        "$DATA_DIR/backups/configs"
        "$DATA_DIR/backups/containers"
        "$DATA_DIR/logs"
        "$DATA_DIR/postgres"
        "$DATA_DIR/redis"
        "$DATA_DIR/qdrant"
        "$DATA_DIR/ollama"
        "$DATA_DIR/openwebui"
        "$DATA_DIR/anythingllm"
        "$DATA_DIR/dify"
        "$DATA_DIR/n8n"
        "$DATA_DIR/signal"
        "$DATA_DIR/comfyui"
        "$DATA_DIR/flowise"
        "$DATA_DIR/nginx-pm"
        "$DATA_DIR/gdrive"
        "$DATA_DIR/gdrive/mount"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Set permissions
    chown -R 1000:1000 "$DATA_DIR"
    chmod -R 755 "$DATA_DIR"
    
    print_success "Directory structure created at $DATA_DIR"
}

#------------------------------------------------------------------------------
# Package Installation
#------------------------------------------------------------------------------

update_system() {
    print_step "Updating system packages..."
    
    (
        apt-get update &>/dev/null
        apt-get upgrade -y &>/dev/null
    ) &
    spinner $! "Updating packages (this may take a few minutes)..."
    wait $!
    
    print_success "System updated"
}

install_base_packages() {
    print_step "Installing base packages..."
    
    local packages=(
        curl
        wget
        git
        vim
        htop
        net-tools
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
        apt-transport-https
        jq
        yamllint
        unzip
    )
    
    (
        apt-get install -y "${packages[@]}" &>/dev/null
    ) &
    spinner $! "Installing base packages..."
    wait $!
    
    print_success "Base packages installed"
}

#------------------------------------------------------------------------------
# Docker Installation
#------------------------------------------------------------------------------

install_docker() {
    print_step "Installing Docker..."
    
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        print_info "Docker already installed: $docker_version"
        
        if ! confirm "Reinstall Docker?" n; then
            return 0
        fi
    fi
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc &>/dev/null || true
    
    # Add Docker repository
    print_info "Adding Docker repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    (
        apt-get update &>/dev/null
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
    ) &
    spinner $! "Installing Docker Engine..."
    wait $!
    
    # Start Docker
    systemctl enable docker &>/dev/null
    systemctl start docker &>/dev/null
    
    # Verify installation
    if docker run --rm hello-world &>/dev/null; then
        print_success "Docker installed successfully"
    else
        print_error "Docker installation failed"
        exit 1
    fi
    
    # Add current user to docker group
    local real_user=$(logname 2>/dev/null || echo $SUDO_USER)
    if [[ -n "$real_user" ]]; then
        usermod -aG docker "$real_user"
        print_info "Added $real_user to docker group (logout/login required)"
    fi
}

configure_docker_storage() {
    print_step "Configuring Docker storage..."
    
    local daemon_config="/etc/docker/daemon.json"
    local docker_data_root="$DATA_DIR/docker"
    
    mkdir -p "$docker_data_root"
    
    cat > "$daemon_config" <<EOF
{
  "data-root": "$docker_data_root",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Restart Docker to apply changes
    systemctl restart docker &>/dev/null
    
    print_success "Docker storage configured at $docker_data_root"
}

#------------------------------------------------------------------------------
# NVIDIA GPU Setup
#------------------------------------------------------------------------------

install_nvidia_drivers() {
    print_step "Installing NVIDIA drivers..."
    
    # Detect recommended driver
    ubuntu-drivers devices &>/dev/null
    local recommended_driver=$(ubuntu-drivers devices 2>/dev/null | grep recommended | awk '{print $3}')
    
    if [[ -z "$recommended_driver" ]]; then
        print_warning "Could not detect recommended driver"
        recommended_driver="nvidia-driver-535"
    fi
    
    print_info "Installing: $recommended_driver"
    
    (
        apt-get install -y "$recommended_driver" &>/dev/null
    ) &
    spinner $! "Installing NVIDIA driver (this may take several minutes)..."
    wait $!
    
    print_success "NVIDIA drivers installed"
    print_warning "System reboot required for drivers to take effect"
}

install_nvidia_docker() {
    print_step "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    (
        apt-get update &>/dev/null
        apt-get install -y nvidia-container-toolkit &>/dev/null
    ) &
    spinner $! "Installing NVIDIA Container Toolkit..."
    wait $!
    
    # Configure Docker to use NVIDIA runtime
    nvidia-ctk runtime configure --runtime=docker &>/dev/null
    systemctl restart docker &>/dev/null
    
    # Test GPU access
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        print_success "NVIDIA Container Toolkit configured successfully"
    else
        print_warning "GPU test failed - may need system reboot"
    fi
}

setup_gpu() {
    if [[ "$GPU_AVAILABLE" == false ]]; then
        return 0
    fi
    
    print_header
    echo -e "${BOLD}GPU Configuration${NC}"
    echo ""
    
    if command -v nvidia-smi &>/dev/null; then
        print_info "NVIDIA drivers already installed"
        nvidia-smi
        echo ""
    else
        echo "NVIDIA GPU detected but drivers not installed."
        echo ""
        
        if confirm "Install NVIDIA drivers?" y; then
            install_nvidia_drivers
        else
            print_warning "Skipping GPU setup - can be configured later"
            return 0
        fi
    fi
    
    if ! command -v nvidia-ctk &>/dev/null; then
        if confirm "Install NVIDIA Container Toolkit for Docker?" y; then
            install_nvidia_docker
        fi
    else
        print_info "NVIDIA Container Toolkit already installed"
    fi
}

#------------------------------------------------------------------------------
# Tailscale Setup
#------------------------------------------------------------------------------

install_tailscale() {
    print_header
    echo -e "${BOLD}Tailscale Configuration${NC}"
    echo ""
    echo "Tailscale provides secure remote access to your AI platform."
    echo ""
    echo -e "${CYAN}Benefits:${NC}"
    echo "  • Access services from anywhere"
    echo "  • Zero-trust security (encrypted)"
    echo "  • No port forwarding needed"
    echo "  • Free for personal use (up to 100 devices)"
    echo ""
    
    if ! confirm "Install and configure Tailscale?" y; then
        print_warning "Skipping Tailscale - will use local access only"
        return 0
    fi
    
    print_step "Installing Tailscale..."
    
    if command -v tailscale &>/dev/null; then
        print_info "Tailscale already installed"
    else
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Check if already authenticated
    if tailscale status &>/dev/null; then
        TAILSCALE_IP=$(tailscale ip -4)
        TAILSCALE_INSTALLED=true
        print_success "Tailscale already running: $TAILSCALE_IP"
        return 0
    fi
    
    print_step "Authenticating with Tailscale..."
    echo ""
    echo -e "${YELLOW}Opening browser for authentication...${NC}"
    echo "If browser doesn't open, visit the URL shown below."
    echo ""
    
    # Start tailscale and get auth URL
    tailscale up
    
    # Wait for connection
    local timeout=60
    local elapsed=0
    while ! tailscale status &>/dev/null; do
        sleep 1
        ((elapsed++))
        if [[ $elapsed -ge $timeout ]]; then
            print_error "Tailscale authentication timeout"
            return 1
        fi
    done
    
    TAILSCALE_IP=$(tailscale ip -4)
    TAILSCALE_INSTALLED=true
    
    print_success "Tailscale connected: $TAILSCALE_IP"
    
    # Enable IP forwarding (for subnet routing if needed)
    echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
    sysctl -p &>/dev/null
}

#------------------------------------------------------------------------------
# Save Installation Metadata
#------------------------------------------------------------------------------

save_metadata() {
    print_step "Saving installation metadata..."
    
    local metadata_file="$DATA_DIR/metadata/deployment_info.json"
    local network_file="$DATA_DIR/metadata/network_config.json"
    local tailscale_file="$DATA_DIR/metadata/tailscale_info.json"
    
    # Deployment info
    cat > "$metadata_file" <<EOF
{
  "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "script_version": "1.0.0",
  "os_version": "$(lsb_release -ds)",
  "data_directory": "$DATA_DIR",
  "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
  "gpu_available": $GPU_AVAILABLE,
  "tailscale_enabled": $TAILSCALE_INSTALLED
}
EOF
    
    # Network config
    local local_ip=$(hostname -I | awk '{print $1}')
    cat > "$network_file" <<EOF
{
  "local_ip": "$local_ip",
  "hostname": "$(hostname)",
  "interfaces": $(ip -j addr show | jq '[.[] | select(.ifname != "lo") | {name: .ifname, addresses: [.addr_info[] | .local]}]')
}
EOF
    
    # Tailscale info
    if [[ "$TAILSCALE_INSTALLED" == true ]]; then
        cat > "$tailscale_file" <<EOF
{
  "enabled": true,
  "ip_address": "$TAILSCALE_IP",
  "status": $(tailscale status --json 2>/dev/null || echo '{}')
}
EOF
    else
        cat > "$tailscale_file" <<EOF
{
  "enabled": false
}
EOF
    fi
    
    print_success "Metadata saved"
}

#------------------------------------------------------------------------------
# Summary and Next Steps
#------------------------------------------------------------------------------

print_summary() {
    clear
    print_header
    
    echo -e "${GREEN}${BOLD}✓ System Setup Complete!${NC}"
    echo ""
    echo -e "${BOLD}Installation Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo -e "${CYAN}Storage:${NC}"
    echo "  Data Directory: $DATA_DIR"
    echo "  Available Space: $(df -h "$DATA_DIR" | awk 'NR==2 {print $4}')"
    echo ""
    
    echo -e "${CYAN}Docker:${NC}"
    echo "  Version: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "  Storage: $DATA_DIR/docker"
    echo ""
    
    if [[ "$GPU_AVAILABLE" == true ]]; then
        echo -e "${CYAN}GPU:${NC}"
        if command -v nvidia-smi &>/dev/null; then
            echo "  $(nvidia-smi --query-gpu=name --format=csv,noheader)"
            echo "  NVIDIA Container Toolkit: Installed"
        else
            echo "  Detected but drivers not installed"
            echo "  ${YELLOW}Note: Reboot required for GPU support${NC}"
        fi
        echo ""
    fi
    
    if [[ "$TAILSCALE_INSTALLED" == true ]]; then
        echo -e "${CYAN}Tailscale:${NC}"
        echo "  Status: Connected"
        echo "  IP Address: $TAILSCALE_IP"
        echo "  Access URL: http://$TAILSCALE_IP"
        echo ""
    fi
    
    echo -e "${CYAN}System Resources:${NC}"
    echo "  RAM: $(free -h | awk 'NR==2 {print $2}')"
    echo "  CPU Cores: $(nproc)"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ "$GPU_AVAILABLE" == true ]] && ! command -v nvidia-smi &>/dev/null; then
        echo -e "${YELLOW}${BOLD}⚠ REBOOT REQUIRED${NC}"
        echo ""
        echo "NVIDIA drivers were installed. Please reboot before continuing:"
        echo ""
        echo -e "  ${CYAN}sudo reboot${NC}"
        echo ""
        echo "After reboot, run the next script:"
        echo -e "  ${CYAN}sudo ./scripts/2-deploy-services.sh${NC}"
        echo ""
    else
        echo -e "${GREEN}${BOLD}Next Steps:${NC}"
        echo ""
        echo "1. Review the configuration:"
        echo -e "   ${CYAN}cat $DATA_DIR/metadata/deployment_info.json${NC}"
        echo ""
        echo "2. Deploy services:"
        echo -e "   ${CYAN}sudo ./scripts/2-deploy-services.sh${NC}"
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#------------------------------------------------------------------------------
# Main Function
#------------------------------------------------------------------------------

main() {
    print_header
    
    # Pre-flight checks
    check_root
    check_os
    check_internet
    check_system_resources
    check_gpu
    
    echo ""
    read -p "Press Enter to continue with installation..."
    
    # Storage configuration
    select_storage_location
    create_directory_structure
    
    # System updates
    update_system
    install_base_packages
    
    # Docker installation
    install_docker
    configure_docker_storage
    
    # GPU setup (if available)
    setup_gpu
    
    # Tailscale setup
    install_tailscale
    
    # Save metadata
    save_metadata
    
    # Show summary
    print_summary
}

# Run main function
main "$@"
