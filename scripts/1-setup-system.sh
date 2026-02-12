#!/bin/bash

#═══════════════════════════════════════════════════════════════════════════════
# AI Platform Automation - Script 1: System Setup & Configuration Collection
#═══════════════════════════════════════════════════════════════════════════════
# 
# Purpose: Initialize system, detect hardware, collect ALL service configurations
# 
# Phases:
#   1. System Requirements Check
#   2. Hardware Detection
#   3. Storage Configuration
#   4. Docker Installation
#   5. NVIDIA Container Toolkit (if GPU detected)
#   6. Ollama Installation
#   7. Service Selection & Configuration Collection
#   8. Directory Structure & Validation
#
# Output: 
#   - /mnt/data/env/.env (all configuration variables)
#   - /mnt/data/metadata/selected-services.json
#   - /mnt/data/metadata/system-info.json
#
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

#───────────────────────────────────────────────────────────────────────────────
# GLOBAL VARIABLES
#───────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="${ROOT_PATH}/logs"
readonly LOG_FILE="${LOG_DIR}/1-setup-system-$(date +%Y%m%d-%H%M%S).log"

# Data paths
readonly DATA_ROOT="/mnt/data"
readonly ENV_FILE="${DATA_ROOT}/env/.env"
readonly METADATA_DIR="${DATA_ROOT}/metadata"
readonly SERVICES_FILE="${METADATA_DIR}/selected-services.json"
readonly SYSTEM_INFO_FILE="${METADATA_DIR}/system-info.json"

# Minimum requirements
readonly MIN_RAM_GB=16
readonly MIN_STORAGE_GB=100
readonly REQUIRED_UBUNTU_VERSION="24.04"

#───────────────────────────────────────────────────────────────────────────────
# COLOR CODES & FORMATTING
#───────────────────────────────────────────────────────────────────────────────

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║          AI Platform Automation Setup v76.5.0                       ║"
    echo "║          Complete Installation Wizard                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

log_phase() {
    local step="$1"
    local description="$2"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔍 STEP $step/13: $description${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${WHITE}${BOLD}$title${NC}"
    echo "$(printf '═%.0s' {1..60})"
}

confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    
    while true; do
        if [[ "$default" == "Y" ]]; then
            print_info "$prompt [Y/n]: "
        else
            print_info "$prompt [y/N]: "
        fi
        
        read -r response
        
        # Use default if empty
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "${response^^}" in
            Y|YES)
                return 0
                ;;
            N|NO)
                return 1
                ;;
            *)
                print_error "Please answer Y or N"
                ;;
        esac
    done
}

#───────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    log_info "Logging initialized: $LOG_FILE"
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${WHITE}${BOLD}  $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

log_phase() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}[PHASE $1]${NC} ${BOLD}$2${NC}" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $*"
}

print_error() {
    echo -e "  ${RED}✗${NC} $*"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $*"
}

print_info() {
    echo -e "  ${BLUE}→${NC} $*"
}

#───────────────────────────────────────────────────────────────────────────────
# VALIDATION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_phone() {
    local phone="$1"
    # Validate format: +[country code][number]
    if [[ "$phone" =~ ^\+[1-9][0-9]{7,14}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_password() {
    local password="$1"
    local min_length=8
    
    if [[ ${#password} -lt $min_length ]]; then
        echo "Password must be at least $min_length characters"
        return 1
    fi
    
    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# INPUT COLLECTION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local secret="${4:-false}"
    local validation_func="${5:-}"
    
    while true; do
        if [[ -n "$default" ]]; then
            print_info "$prompt [$default]: "
        else
            print_info "$prompt: "
        fi
        
        if [[ "$secret" == "true" ]]; then
            read -s input
            echo ""
        else
            read -r input
        fi
        
        # Use default if empty
        if [[ -z "$input" ]] && [[ -n "$default" ]]; then
            input="$default"
        fi
        
        # Validate if function provided
        if [[ -n "$validation_func" ]]; then
            if $validation_func "$input"; then
                eval "$var_name='$input'"
                return 0
            else
                print_error "Invalid input. Please try again."
                continue
            fi
        fi
        
        # No validation needed
        if [[ -n "$input" ]]; then
            eval "$var_name='$input'"
            return 0
        fi
        
        print_error "Input cannot be empty. Please try again."
    done
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-Y}"
    
    while true; do
        if [[ "$default" == "Y" ]]; then
            print_info "$prompt [Y/n]: "
        else
            print_info "$prompt [y/N]: "
        fi
        
        read -r response
        
        # Use default if empty
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "${response^^}" in
            Y|YES)
                return 0
                ;;
            N|NO)
                return 1
                ;;
            *)
                print_error "Please answer Y or N"
                ;;
        esac
    done
}

generate_random_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

#───────────────────────────────────────────────────────────────────────────────
# SYSTEM CHECK FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

check_system_requirements() {
    log_info "System Requirements Check"
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$VERSION_ID" == "$REQUIRED_UBUNTU_VERSION" ]]; then
            print_success "Ubuntu $VERSION_ID detected"
        else
            print_warn "Ubuntu $VERSION_ID detected (recommended: $REQUIRED_UBUNTU_VERSION)"
        fi
    else
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_success "Running as root"
    else
        print_error "Not running as root"
        exit 1
    fi
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))
    
    if [[ $total_ram_gb -ge $MIN_RAM_GB ]]; then
        print_success "${total_ram_gb}GB RAM available (minimum: ${MIN_RAM_GB}GB)"
    else
        print_error "${total_ram_gb}GB RAM available (minimum: ${MIN_RAM_GB}GB required)"
        exit 1
    fi
    
    # Check storage
    local available_storage_gb=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    
    if [[ $available_storage_gb -ge $MIN_STORAGE_GB ]]; then
        print_success "${available_storage_gb}GB storage available"
    else
        print_warn "${available_storage_gb}GB storage available (recommended: ${MIN_STORAGE_GB}GB)"
    fi
    
    # Check internet connectivity
    if curl -s --max-time 5 https://google.com > /dev/null 2>&1; then
        print_success "Internet connectivity confirmed"
    else
        print_error "No internet connectivity"
        exit 1
    fi
}
#───────────────────────────────────────────────────────────────────────────────
# HARDWARE DETECTION
#───────────────────────────────────────────────────────────────────────────────

detect_hardware() {
    log_info "Hardware Detection"

    local has_gpu=false
    local gpu_info=""
    local gpu_vram=""
    local cuda_version=""

    # Detect NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
        gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)

        if [[ -n "$gpu_info" ]]; then
            has_gpu=true
            print_success "NVIDIA GPU detected: $gpu_info (${gpu_vram}MB VRAM)"

            # Check CUDA version
            if command -v nvcc &> /dev/null; then
                cuda_version=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
                print_success "CUDA $cuda_version installed"
            else
                print_info "CUDA not installed (will be installed later)"
            fi
        fi
    else
        print_info "No NVIDIA GPU detected (CPU-only mode)"
    fi

    # Detect additional storage devices
    local additional_devices=()
    while IFS= read -r device; do
        local device_name=$(basename "$device")
        local device_size=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null | awk '{print int($1/1024/1024/1024)}')

        # Skip if already mounted or is root device
        if ! grep -q "$device" /proc/mounts && [[ "$device" != *"$(df / | tail -1 | awk '{print $1}')"* ]]; then
            additional_devices+=("$device:${device_size}GB")
            print_success "Additional storage detected: $device (${device_size}GB)"
        fi
    done < <(lsblk -d -n -p -o NAME,TYPE | grep "disk" | awk '{print $1}')

    if [[ ${#additional_devices[@]} -eq 0 ]]; then
        print_info "No additional storage devices detected"
    fi

    # Save hardware info to metadata
    cat > "$SYSTEM_INFO_FILE.tmp" <<EOF
{
  "detection_time": "$(date -Iseconds)",
  "cpu": {
    "model": "$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)",
    "cores": $(nproc),
    "threads": $(nproc)
  },
  "memory": {
    "total_gb": $total_ram_gb,
    "available_gb": $(free -g | awk '/^Mem:/{print $7}')
  },
  "gpu": {
    "present": $has_gpu,
    "model": "$gpu_info",
    "vram_mb": "${gpu_vram:-0}",
    "cuda_version": "$cuda_version"
  },
  "storage": {
    "additional_devices": [$(printf '"%s",' "${additional_devices[@]}" | sed 's/,$//')]
  }
}
EOF

    # Export for later use
    export HAS_GPU="$has_gpu"
    export GPU_INFO="$gpu_info"
    export ADDITIONAL_DEVICES="${additional_devices[@]}}"
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN SYSTEM DETECTION
#───────────────────────────────────────────────────────────────────────────────

detect_system() {
    log_phase "1" "🔍 System Detection"
    
    print_info "Performing comprehensive system detection..."
    
    # Run all detection functions
    check_system_requirements
    detect_hardware
    
    # Save system info
    mv "$SYSTEM_INFO_FILE.tmp" "$SYSTEM_INFO_FILE"
    print_success "System information saved to: $SYSTEM_INFO_FILE"
    
    # Display summary
    echo ""
    print_info "System Detection Summary:"
    echo "  • OS: Ubuntu $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
    echo "  • CPU: $(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)"
    echo "  • RAM: $(free -h | awk '/^Mem:/{print $2}')"
    echo "  • GPU: ${GPU_INFO:-"Not detected"}"
    echo "  • Storage: $(df -h / | tail -1 | awk '{print $2}') available"
}

#───────────────────────────────────────────────────────────────────────────────
# DOMAIN AND NETWORK CONFIGURATION
#───────────────────────────────────────────────────────────────────────────────

collect_domain_info() {
    log_phase "2" "🌐 Domain & Network Configuration"
    
    echo ""
    print_info "Configure your platform domain and networking..."
    
    # Domain configuration
    while true; do
        echo ""
        print_info "Enter your domain (e.g., ai.example.com) or press Enter for IP-only access:"
        read -r domain_input
        
        if [[ -z "$domain_input" ]]; then
            # IP-only mode
            DETECTED_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
            PLATFORM_DOMAIN="$DETECTED_IP"
            ACCESS_MODE="ip"
            print_success "IP-only mode configured: $PLATFORM_DOMAIN"
            break
        else
            # Domain mode - validate
            if [[ "$domain_input" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
                PLATFORM_DOMAIN="$domain_input"
                ACCESS_MODE="domain"
                
                # Test DNS resolution
                print_info "Testing DNS resolution for $PLATFORM_DOMAIN..."
                if nslookup "$PLATFORM_DOMAIN" >/dev/null 2>&1; then
                    print_success "DNS resolution successful"
                else
                    print_warn "DNS resolution failed - you may need to configure DNS later"
                fi
                break
            else
                print_error "Invalid domain format. Please use format: domain.example.com"
            fi
        fi
    done
    
    # SSL Configuration
    echo ""
    print_info "SSL/TLS Configuration:"
    echo "  1) Automatic HTTPS (Let's Encrypt - requires domain)"
    echo "  2) Self-signed certificates"
    echo "  3) No SSL (HTTP only - not recommended)"
    
    while true; do
        print_info "Select SSL option [1-3]: "
        read -r ssl_option
        
        case $ssl_option in
            1)
                if [[ "$ACCESS_MODE" == "domain" ]]; then
                    SSL_MODE="letsencrypt"
                    print_success "Let's Encrypt SSL selected"
                    break
                else
                    print_error "Let's Encrypt requires a domain name"
                fi
                ;;
            2)
                SSL_MODE="selfsigned"
                print_success "Self-signed SSL selected"
                break
                ;;
            3)
                SSL_MODE="none"
                print_warn "HTTP-only mode selected"
                break
                ;;
            *)
                print_error "Invalid option. Please select 1-3"
                ;;
        esac
    done
    
    # Email for Let's Encrypt
    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        while true; do
            print_info "Enter email for Let's Encrypt notifications: "
            read -r le_email
            
            if [[ "$le_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                LETSENCRYPT_EMAIL="$le_email"
                print_success "Email configured: $LETSENCRYPT_EMAIL"
                break
            else
                print_error "Invalid email format"
            fi
        done
    fi
    
    # Detect local IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    print_success "Local IP detected: $LOCAL_IP"
    
    # Save network configuration
    cat > "$METADATA_DIR/network_config.json" <<EOF
{
  "platform_domain": "$PLATFORM_DOMAIN",
  "access_mode": "$ACCESS_MODE",
  "ssl_mode": "$SSL_MODE",
  "letsencrypt_email": "${LETSENCRYPT_EMAIL:-}",
  "public_ip": "${DETECTED_IP:-}",
  "local_ip": "$LOCAL_IP",
  "configured_at": "$(date -Iseconds)"
}
EOF
    
    print_success "Network configuration saved"
}

#───────────────────────────────────────────────────────────────────────────────
# STORAGE CONFIGURATION
#───────────────────────────────────────────────────────────────────────────────

configure_storage() {
    log_info "Storage Configuration"

    # Check if /mnt/data already exists and is mounted
    if mountpoint -q /mnt/data; then
        print_success "/mnt/data already mounted"
        local mount_device=$(df /mnt/data | tail -1 | awk '{print $1}')
        local mount_size=$(df -h /mnt/data | tail -1 | awk '{print $2}')
        print_info "Current mount: $mount_device ($mount_size)"
        return 0
    fi

    # Parse additional devices
    if [[ -z "$ADDITIONAL_DEVICES" ]]; then
        print_info "No additional storage devices to configure"
        print_info "Using root filesystem for /mnt/data"
        mkdir -p /mnt/data
        print_success "/mnt/data created on root filesystem"
        return 0
    fi

    # Present device selection
    echo ""
    echo "Available storage devices:"
    echo ""

    local device_array=()
    local count=1

    for device_info in $ADDITIONAL_DEVICES; do
        local device=$(echo "$device_info" | cut -d':' -f1)
        local size=$(echo "$device_info" | cut -d':' -f2)
        echo "  [$count] $device ($size)"
        device_array+=("$device")
        ((count++))
    done

    echo "  [0] Skip - use root filesystem"
    echo ""

    # Get user selection
    local selection=-1
    while true; do
        print_info "Select device to mount at /mnt/data [0-$((count-1))]: "
        read -r selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 0 ]] && [[ $selection -lt $count ]]; then
            break
        else
            print_error "Invalid selection. Please enter a number between 0 and $((count-1))"
        fi
    done

    # Handle selection
    if [[ $selection -eq 0 ]]; then
        print_info "Using root filesystem for /mnt/data"
        mkdir -p /mnt/data
        print_success "/mnt/data created on root filesystem"
        return 0
    fi

    local selected_device="${device_array[$((selection-1))]}"

    # Confirm formatting
    echo ""
    print_warn "WARNING: This will FORMAT $selected_device and erase all data!"
    if ! prompt_yes_no "Continue with formatting $selected_device?" "N"; then
        print_info "Storage configuration cancelled"
        mkdir -p /mnt/data
        print_success "/mnt/data created on root filesystem"
        return 0
    fi

    # Format device
    print_info "Formatting $selected_device as ext4..."
    if mkfs.ext4 -F "$selected_device" &>> "$LOG_FILE"; then
        print_success "Device formatted successfully"
    else
        print_error "Failed to format device"
        exit 1
    fi

    # Create mount point
    mkdir -p /mnt/data

    # Mount device
    print_info "Mounting $selected_device to /mnt/data..."
    if mount "$selected_device" /mnt/data; then
        print_success "Device mounted successfully"
    else
        print_error "Failed to mount device"
        exit 1
    fi

    # Get UUID
    local device_uuid=$(blkid -s UUID -o value "$selected_device")

    # Add to /etc/fstab
    if ! grep -q "$device_uuid" /etc/fstab; then
        echo "UUID=$device_uuid /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab
        print_success "Added to /etc/fstab for persistence"
    fi

    # Set permissions
    chown -R 1000:1000 /mnt/data
    chmod -R 755 /mnt/data

    print_success "Storage configuration complete"
}

#───────────────────────────────────────────────────────────────────────────────
# SYSTEM UPDATE
#───────────────────────────────────────────────────────────────────────────────

update_system() {
    log_phase "3" "🔄 System Update"
    
    print_info "Updating system packages..."
    
    # Update package lists
    if apt update &>> "$LOG_FILE"; then
        print_success "Package lists updated"
    else
        print_error "Failed to update package lists"
        exit 1
    fi
    
    # Upgrade packages
    print_info "Upgrading installed packages..."
    if apt upgrade -y &>> "$LOG_FILE"; then
        print_success "System packages upgraded"
    else
        print_error "Failed to upgrade packages"
        exit 1
    fi
    
    # Install essential packages
    print_info "Installing essential packages..."
    local essential_packages=(
        "curl"
        "wget"
        "git"
        "unzip"
        "jq"
        "lsb-release"
        "gnupg"
        "ca-certificates"
    )
    
    for package in "${essential_packages[@]}"; do
        print_info "Installing $package..."
        if apt install -y "$package" &>> "$LOG_FILE"; then
            print_success "$package installed"
        else
            print_error "Failed to install $package"
            exit 1
        fi
    done
    
    print_success "System update complete"
}

#───────────────────────────────────────────────────────────────────────────────
# DOCKER CONFIGURATION
#───────────────────────────────────────────────────────────────────────────────

configure_docker() {
    log_phase "5" "⚙️  Docker Configuration"
    
    # Add user to docker group
    local current_user="${SUDO_USER:-$USER}"
    print_info "Adding user $current_user to docker group..."
    
    if usermod -aG docker "$current_user"; then
        print_success "User added to docker group"
    else
        print_error "Failed to add user to docker group"
        exit 1
    fi
    
    # Enable docker service
    print_info "Enabling Docker service..."
    if systemctl enable docker &>> "$LOG_FILE"; then
        print_success "Docker service enabled"
    else
        print_error "Failed to enable Docker service"
        exit 1
    fi
    
    # Start docker service
    print_info "Starting Docker service..."
    if systemctl start docker &>> "$LOG_FILE"; then
        print_success "Docker service started"
    else
        print_error "Failed to start Docker service"
        exit 1
    fi
    
    # Verify docker is working
    print_info "Verifying Docker installation..."
    if docker run --rm hello-world &>> "$LOG_FILE"; then
        print_success "Docker is working correctly"
    else
        print_error "Docker verification failed"
        exit 1
    fi
    
    # Create docker network for the platform
    print_info "Creating Docker network for AI platform..."
    if docker network create ai-platform &>> "$LOG_FILE"; then
        print_success "Docker network 'ai-platform' created"
    else
        print_warn "Docker network might already exist"
    fi
    
    print_success "Docker configuration complete"
    
    # Display group membership notice
    echo ""
    print_info "⚠️  IMPORTANT: You need to log out and log back in"
    print_info "   or run 'newgrp docker' to use Docker without sudo."
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# DOCKER INSTALLATION
#───────────────────────────────────────────────────────────────────────────────

install_docker() {
    log_phase "4" "📦 Docker Installation"

    # Check if Docker already installed
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        print_success "Docker already installed (version $docker_version)"

        # Check Docker Compose
        if docker compose version &> /dev/null; then
            local compose_version=$(docker compose version --short)
            print_success "Docker Compose already installed (version $compose_version)"
        fi

        # Ensure docker service is running
        if systemctl is-active --quiet docker; then
            print_success "Docker service is running"
        else
            print_info "Starting Docker service..."
            systemctl start docker
            systemctl enable docker
            print_success "Docker service started"
        fi

        return 0
    fi

    print_info "Installing Docker..."

    # Update package index
    apt-get update -qq &>> "$LOG_FILE"

    # Install prerequisites
    apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        &>> "$LOG_FILE"

    print_success "Prerequisites installed"

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_success "Docker repository added"

    # Install Docker Engine
    apt-get update -qq &>> "$LOG_FILE"
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        &>> "$LOG_FILE"

    local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    print_success "Docker $docker_version installed"

    local compose_version=$(docker compose version --short)
    print_success "Docker Compose $compose_version installed"

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    print_success "Docker service started and enabled"

    # Add ubuntu user to docker group (if exists)
    if id "ubuntu" &>/dev/null; then
        usermod -aG docker ubuntu
        print_success "User 'ubuntu' added to docker group"
    fi

    # Verify installation
    if docker run --rm hello-world &>> "$LOG_FILE"; then
        print_success "Docker installation verified"
    else
        print_error "Docker installation verification failed"
        exit 1
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# NVIDIA CONTAINER TOOLKIT
#───────────────────────────────────────────────────────────────────────────────

install_nvidia_toolkit() {
    if [[ "$HAS_GPU" != "true" ]]; then
        log_phase "5" "🎮 NVIDIA Container Toolkit (Skipped - No GPU)"
        print_info "No NVIDIA GPU detected, skipping GPU setup"
        return 0
    fi

    log_phase "5" "🎮 NVIDIA Container Toolkit"

    # Check if NVIDIA drivers installed
    if ! command -v nvidia-smi &> /dev/null; then
        print_info "Installing NVIDIA drivers..."

        apt-get update -qq &>> "$LOG_FILE"
        apt-get install -y -qq nvidia-driver-535 &>> "$LOG_FILE"

        print_success "NVIDIA drivers installed (reboot required)"
        print_warn "Please reboot and run this script again"
        exit 0
    fi

    local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
    print_success "NVIDIA drivers installed (version $driver_version)"

    # Install NVIDIA Container Toolkit
    if command -v nvidia-ctk &> /dev/null; then
        print_success "NVIDIA Container Toolkit already installed"
    else
        print_info "Installing NVIDIA Container Toolkit..."

        # Add NVIDIA package repository
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        apt-get update -qq &>> "$LOG_FILE"
        apt-get install -y -qq nvidia-container-toolkit &>> "$LOG_FILE"

        print_success "NVIDIA Container Toolkit installed"
    fi

    # Configure Docker to use NVIDIA runtime
    nvidia-ctk runtime configure --runtime=docker &>> "$LOG_FILE"
    systemctl restart docker

    print_success "Docker configured for GPU access"

    # Verify GPU access in Docker
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>> "$LOG_FILE"; then
        print_success "GPU accessible in Docker containers"
    else
        print_warn "GPU verification failed, but continuing..."
    fi
}
#───────────────────────────────────────────────────────────────────────────────
# OLLAMA INSTALLATION
#───────────────────────────────────────────────────────────────────────────────

install_ollama() {
    log_phase "6" "🦙 Ollama Installation"

    # Check if Ollama already installed
    if command -v ollama &> /dev/null; then
        local ollama_version=$(ollama --version 2>/dev/null | awk '{print $NF}')
        print_success "Ollama already installed (version $ollama_version)"
    else
        print_info "Installing Ollama..."

        # Install Ollama
        curl -fsSL https://ollama.ai/install.sh | sh &>> "$LOG_FILE"

        if command -v ollama &> /dev/null; then
            print_success "Ollama installed successfully"
        else
            print_error "Ollama installation failed"
            exit 1
        fi
    fi

    # Start Ollama service
    if systemctl is-active --quiet ollama; then
        print_success "Ollama service is running"
    else
        print_info "Starting Ollama service..."
        systemctl start ollama
        systemctl enable ollama
        sleep 3
        print_success "Ollama service started"
    fi

    # Interactive model selection
    echo ""
    print_header "🤖 Ollama Model Selection"
    echo ""
    echo "Select models to download (space-separated numbers, or 0 to skip):"
    echo ""

    local models=(
        "llama3.2:latest:Meta Llama 3.2 (3B) - Fast, general purpose"
        "llama3.2:1b:Meta Llama 3.2 (1B) - Lightweight, fast"
        "llama3.1:8b:Meta Llama 3.1 (8B) - Balanced performance"
        "llama3.1:70b:Meta Llama 3.1 (70B) - High quality (requires 48GB+ VRAM)"
        "mistral:latest:Mistral 7B - Excellent reasoning"
        "mixtral:latest:Mixtral 8x7B - Expert mixture model"
        "codellama:latest:Code Llama - Code generation"
        "phi3:latest:Microsoft Phi-3 - Efficient small model"
        "gemma2:9b:Google Gemma 2 (9B) - Latest Google model"
        "qwen2.5:latest:Alibaba Qwen 2.5 - Multilingual"
    )

    local count=1
    for model_info in "${models[@]}}"; do
        local model_name=$(echo "$model_info" | cut -d':' -f1,2)
        local model_desc=$(echo "$model_info" | cut -d':' -f3)
        printf "  [%2d] %-20s - %s\n" "$count" "$model_name" "$model_desc"
        ((count++))
    done

    echo "  [ 0] Skip model download"
    echo ""

    print_info "Enter selections (e.g., '1 5 7' or '0' to skip): "
    read -r selections

    if [[ "$selections" == "0" ]]; then
        print_info "Model download skipped"
        return 0
    fi

    # Download selected models
    local selected_models=()
    for selection in $selections; do
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -gt 0 ]] && [[ $selection -le ${#models[@]} ]]; then
            local model_info="${models[$((selection-1))]}"
            local model_name=$(echo "$model_info" | cut -d':' -f1,2)
            selected_models+=("$model_name")
        fi
    done

    if [[ ${#selected_models[@]} -eq 0 ]]; then
        print_info "No valid models selected"
        return 0
    fi

    echo ""
    print_info "Downloading ${#selected_models[@]} model(s)..."
    echo ""

    for model in "${selected_models[@]}"; do
        print_info "Downloading $model..."
        if ollama pull "$model" 2>&1 | tee -a "$LOG_FILE" | grep -E "(pulling|success)"; then
            print_success "$model downloaded"
        else
            print_warn "$model download failed (continuing...)"
        fi
        echo ""
    done

    # List downloaded models
    print_info "Available models:"
    ollama list 2>&1 | tee -a "$LOG_FILE"
}

#───────────────────────────────────────────────────────────────────────────────
# SERVICE CATALOG DEFINITION
#───────────────────────────────────────────────────────────────────────────────

declare -A SERVICE_CATALOG

# Format: "service_key:display_name:description:category:dependencies:requires_config"

SERVICE_CATALOG=(
    # Core Infrastructure
    ["traefik"]="traefik:Traefik:Reverse proxy & SSL termination:infrastructure::domain,email,cloudflare_token"
    ["tailscale"]="tailscale:Tailscale:VPN mesh network:infrastructure::auth_key,tailnet"
    ["portainer"]="portainer:Portainer:Container management UI:infrastructure::"

    # Databases
    ["postgres"]="postgres:PostgreSQL:Relational database:database::postgres_password"
    ["redis"]="redis:Redis:In-memory cache:database::redis_password"
    ["mongodb"]="mongodb:MongoDB:Document database:database::mongo_password"

    # Vector Databases
    ["qdrant"]="qdrant:Qdrant:Vector database:vector_db::qdrant_api_key"
    ["weaviate"]="weaviate:Weaviate:Vector database with ML:vector_db::"
    ["milvus"]="milvus:Milvus:Scalable vector database:vector_db::milvus_password"
    ["chroma"]="chroma:ChromaDB:Embeddings database:vector_db::"

    # AI Chat Interfaces
    ["librechat"]="librechat:LibreChat:Multi-provider chat UI:ai_chat:postgres:google_client_id,google_client_secret,jwt_secret"
    ["openwebui"]="openwebui:Open WebUI:Ollama web interface:ai_chat::admin_email,admin_password"
    ["chatgpt_ui"]="chatgpt_ui:ChatGPT UI:ChatGPT-like interface:ai_chat::openai_api_key"

    # LLM Infrastructure
    ["litellm"]="litellm:LiteLLM:LLM proxy & load balancer:llm::litellm_master_key,openai_api_key"
    ["ollama_webui"]="ollama_webui:Ollama WebUI:Ollama management:llm::"
    ["localai"]="localai:LocalAI:OpenAI-compatible API:llm::"

    # Communication
    ["signal"]="signal:Signal Bot:Signal messaging bot:communication::signal_phone,signal_password"
    ["ntfy"]="ntfy:Ntfy:Push notifications:communication::"

    # Automation & Orchestration
    ["n8n"]="n8n:n8n:Workflow automation:automation:postgres:n8n_encryption_key"
    ["activepieces"]="activepieces:Activepieces:Workflow automation:automation:postgres:ap_encryption_key"
    ["windmill"]="windmill:Windmill:Developer platform:automation:postgres:windmill_token"

    # Monitoring
    ["prometheus"]="prometheus:Prometheus:Metrics collection:monitoring::prometheus_retention"
    ["grafana"]="grafana:Grafana:Metrics visualization:monitoring:prometheus:grafana_password"
    ["uptime_kuma"]="uptime_kuma:Uptime Kuma:Uptime monitoring:monitoring::"
    ["netdata"]="netdata:Netdata:Real-time monitoring:monitoring::"

    # Development Tools
    ["code_server"]="code_server:Code Server:VS Code in browser:development::code_password"
    ["jupyter"]="jupyter:JupyterLab:Data science notebooks:development::jupyter_token"

    # Storage & Files
    ["minio"]="minio:MinIO:S3-compatible storage:storage::minio_root_user,minio_root_password"
    ["seafile"]="seafile:Seafile:File sync & share:storage::seafile_admin_email,seafile_admin_password"

    # Search & Knowledge
    ["searxng"]="searxng:SearXNG:Meta search engine:search::searxng_secret"
    ["meilisearch"]="meilisearch:Meilisearch:Search engine:search::meili_master_key"

    # RAG & Document Processing
    ["anything_llm"]="anything_llm:AnythingLLM:RAG document chat:rag::anything_llm_password"
    ["danswer"]="danswer:Danswer:Enterprise RAG:rag:postgres,qdrant:danswer_secret"
    ["quivr"]="quivr:Quivr:Personal AI assistant:rag:postgres:quivr_jwt_secret"
)

#───────────────────────────────────────────────────────────────────────────────
# SERVICE CATEGORY DEFINITIONS
#───────────────────────────────────────────────────────────────────────────────

declare -A SERVICE_CATEGORIES=(
    ["infrastructure"]="🏗️  Core Infrastructure"
    ["database"]="💾 Databases"
    ["vector_db"]="🧠 Vector Databases"
    ["ai_chat"]="💬 AI Chat Interfaces"
    ["llm"]="🤖 LLM Infrastructure"
    ["communication"]="📡 Communication"
    ["automation"]="⚙️  Automation"
    ["monitoring"]="📊 Monitoring"
    ["development"]="👨‍💻 Development"
    ["storage"]="📦 Storage"
    ["search"]="🔍 Search"
    ["rag"]="📚 RAG & Documents"
)

#───────────────────────────────────────────────────────────────────────────────
# SERVICE SELECTION HELPERS
#───────────────────────────────────────────────────────────────────────────────

get_service_info() {
    local service_key="$1"
    local field="$2"  # display_name, description, category, dependencies, requires_config

    local service_data="${SERVICE_CATALOG[$service_key]}"
    local field_index

    case "$field" in
        "key") echo "$service_key" ;;
        "display_name") echo "$service_data" | cut -d':' -f2 ;;
        "description") echo "$service_data" | cut -d':' -f3 ;;
        "category") echo "$service_data" | cut -d':' -f4 ;;
        "dependencies") echo "$service_data" | cut -d':' -f5 ;;
        "requires_config") echo "$service_data" | cut -d':' -f6 ;;
        *) echo "" ;;
    esac
}

check_dependencies() {
    local service_key="$1"
    local selected_services="$2"  # comma-separated string

    local deps=$(get_service_info "$service_key" "dependencies")

    if [[ -z "$deps" ]]; then
        return 0  # No dependencies
    fi

    local missing_deps=()
    IFS=',' read -ra DEP_ARRAY <<< "$deps"

    for dep in "${DEP_ARRAY[@]}"; do
        if [[ ! ",$selected_services," =~ ",$dep," ]]; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        return 1  # Has missing dependencies
    fi

    return 0  # All dependencies met
}
#───────────────────────────────────────────────────────────────────────────────
# INTERACTIVE SERVICE SELECTION
#───────────────────────────────────────────────────────────────────────────────

select_services() {
    log_phase "7" "🎯 Service Selection"

    local selected_services=()
    local -A selected_map

    # Group services by category
    local -A category_services
    for service_key in "${!SERVICE_CATALOG[@]}"; do
        local category=$(get_service_info "$service_key" "category")
        if [[ -z "${category_services[$category]}" ]]; then
            category_services[$category]="$service_key"
        else
            category_services[$category]="${category_services[$category]} $service_key"
        fi
    done

    echo ""
    print_header "📋 Available Services"
    echo ""
    print_info "Select services to deploy. Dependencies will be auto-selected."
    echo ""

    # Display services by category
    local service_number=1
    local -A number_to_service

    for category in "${!SERVICE_CATEGORIES[@]"; do
        if [[ -n "${category_services[$category]}" ]]; then
            echo ""
            echo "${SERVICE_CATEGORIES[$category]}"
            echo "$(printf '─%.0s' {1..60})"

            for service_key in ${category_services[$category]}; do
                local display_name=$(get_service_info "$service_key" "display_name")
                local description=$(get_service_info "$service_key" "description")
                local deps=$(get_service_info "$service_key" "dependencies")

                printf "  [%2d] %-18s - %s" "$service_number" "$display_name" "$description"

                if [[ -n "$deps" ]]; then
                    echo -e "${YELLOW} (needs: $deps)${NC}"
                else
                    echo ""
                fi

                number_to_service[$service_number]="$service_key"
                ((service_number++))
            done
        fi
    done

    echo ""
    echo "$(printf '═%.0s' {1..60})"
    echo ""
    print_info "Enter service numbers (space-separated, e.g., '1 5 12 18'):"
    print_info "Or enter 'all' for all services, 'none' to skip:"
    echo ""
    read -r -p "Selection: " selection

    # Process selection
    if [[ "$selection" == "none" ]]; then
        print_info "No services selected"
        return 0
    elif [[ "$selection" == "all" ]]; then
        for service_key in "${!SERVICE_CATALOG[@]}"; do
            selected_services+=("$service_key")
            selected_map[$service_key]=1
        done
        print_success "All services selected"
    else
        # Parse individual selections
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ -n "${number_to_service[$num]}" ]]; then
                local service_key="${number_to_service[$num]}"
                selected_services+=("$service_key")
                selected_map[$service_key]=1
            else
                print_warn "Invalid selection: $num (skipped)"
            fi
        done
    fi

    # Auto-select dependencies
    echo ""
    print_info "Checking dependencies..."

    local deps_added=0
    local max_iterations=10
    local iteration=0

    while [[ $iteration -lt $max_iterations ]]; do
        local added_this_round=0

        for service_key in "${selected_services[@]}"; do
            local deps=$(get_service_info "$service_key" "dependencies")

            if [[ -n "$deps" ]]; then
                IFS=',' read -ra DEP_ARRAY <<< "$deps"

                for dep in "${DEP_ARRAY[@]}"; do
                    if [[ -z "${selected_map[$dep]}" ]]; then
                        selected_services+=("$dep")
                        selected_map[$dep]=1

                        local dep_name=$(get_service_info "$dep" "display_name")
                        print_success "Auto-selected dependency: $dep_name"

                        ((deps_added++))
                        ((added_this_round++))
                    fi
                done
            fi
        done

        if [[ $added_this_round -eq 0 ]]; then
            break
        fi

        ((iteration++))
    done

    if [[ $deps_added -gt 0 ]]; then
        echo ""
        print_success "$deps_added dependencies auto-selected"
    fi

    # Display final selection
    echo ""
    print_header "✅ Selected Services (${#selected_services[@]})"
    echo ""

    for category in "${!SERVICE_CATEGORIES[@]}"; do
        local category_has_services=false
        local category_list=""

        for service_key in "${selected_services[@]}"; do
            if [[ "$(get_service_info "$service_key" "category")" == "$category" ]]; then
                category_has_services=true
                local display_name=$(get_service_info "$service_key" "display_name")
                category_list="${category_list}  • $display_name\n"
            fi
        done

        if [[ "$category_has_services" == true ]]; then
            echo "${SERVICE_CATEGORIES[$category]}"
            echo -e "$category_list"
        fi
    done

    # Confirm selection
    echo ""
    if ! confirm "Proceed with these services?"; then
        print_info "Service selection cancelled"
        return 1
    fi

    # Save selected services to JSON
    mkdir -p "$METADATA_DIR"

    cat > "$SERVICES_FILE" <<EOF
{
  "selection_time": "$(date -Iseconds)",
  "total_services": ${#selected_services[@]},
  "services": [
EOF

    local first=true
    for service_key in "${selected_services[@]}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$SERVICES_FILE"
        fi
        first=false

        local display_name=$(get_service_info "$service_key" "display_name")
        local description=$(get_service_info "$service_key" "description")
        local category=$(get_service_info "$service_key" "category")
        local deps=$(get_service_info "$service_key" "dependencies")
        local configs=$(get_service_info "$service_key" "requires_config")

        cat >> "$SERVICES_FILE" <<EOF
    {
      "key": "$service_key",
      "display_name": "$display_name",
      "description": "$description",
      "category": "$category",
      "dependencies": [$(echo "$deps" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')]",
      "required_configs": [$(echo "$configs" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')]"
    }
EOF
    done

    cat >> "$SERVICES_FILE" <<EOF

  ]
}
EOF

    print_success "Service selection saved to $SERVICES_FILE"

    # Export selected services for next phase
    export SELECTED_SERVICES="${selected_services[@]}"

    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# CONFIGURATION COLLECTION
#───────────────────────────────────────────────────────────────────────────────

collect_configurations() {
    log_phase "8" "⚙️  Configuration Collection"

    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Services file not found: $SERVICES_FILE"
        exit 1
    fi

    # Read selected services from JSON
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE"))

    if [[ ${#selected_services[@]} -eq 0 ]]; then
        print_info "No services selected, skipping configuration"
        return 0
    fi

    echo ""
    print_header "🔧 Service Configuration"
    echo ""
    print_info "Collecting configuration for ${#selected_services[@]} services"
    echo ""

    # Initialize .env file
    mkdir -p "$(dirname "$ENV_FILE")"

    cat > "$ENV_FILE" <<EOF
#═══════════════════════════════════════════════════════════════════════════════
# AI Platform Configuration
# Generated: $(date -Iseconds)
#═══════════════════════════════════════════════════════════════════════════════

# System Paths
DATA_ROOT=$DATA_ROOT
METADATA_DIR=$METADATA_DIR

# Hardware Configuration
EOF

    # Add hardware info
    local has_gpu=$(jq -r '.gpu.detected' "$SYSTEM_INFO_FILE")
    echo "HAS_GPU=$has_gpu" >> "$ENV_FILE"

    if [[ "$has_gpu" == "true" ]]; then
        local gpu_name=$(jq -r '.gpu.name' "$SYSTEM_INFO_FILE")
        local gpu_vram=$(jq -r '.gpu.vram_mb' "$SYSTEM_INFO_FILE")
        echo "GPU_NAME=\"$gpu_name\"" >> "$ENV_FILE"
        echo "GPU_VRAM_MB=$gpu_vram" >> "$ENV_FILE"
    fi

    echo "" >> "$ENV_FILE"

    # Collect required configurations
    local -A collected_configs
    local all_required_configs=()

    # Gather all unique required configs
    for service_key in "${selected_services[@]}"; do
        local configs=$(get_service_info "$service_key" "requires_config")

        if [[ -n "$configs" ]]; then
            IFS=',' read -ra CONFIG_ARRAY <<< "$configs"
            for config in "${CONFIG_ARRAY[@]}"; do
                if [[ -z "${collected_configs[$config]}" ]]; then
                    all_required_configs+=("$config")
                    collected_configs[$config]=1
                fi
            done
        fi
    done

    if [[ ${#all_required_configs[@] -eq 0 ]]; then
        print_success "No additional configuration required"
        return 0
    fi

    echo ""
    print_info "Required configuration items: ${#all_required_configs[@]"
    echo ""

    # Collect each configuration
    for config_key in "${all_required_configs[@]}"; do
        collect_config_value "$config_key"
    done

    # Add common configurations
    echo "" >> "$ENV_FILE"
    echo "# Common Settings" >> "$ENV_FILE"

    prompt_input "TIMEZONE" "Timezone (e.g., America/New_York)" "UTC" false
    echo "TIMEZONE=$INPUT_RESULT" >> "$ENV_FILE"

    prompt_input "LOG_LEVEL" "Log level (debug/info/warn/error)" "info" false
    echo "LOG_LEVEL=$INPUT_RESULT" >> "$ENV_FILE"

    # Generate common secrets
    echo "" >> "$ENV_FILE"
    echo "# Generated Secrets" >> "$ENV_FILE"
    echo "MASTER_SECRET=$(generate_random_password 64)" >> "$ENV_FILE"
    echo "ENCRYPTION_KEY=$(generate_random_password 32)" >> "$ENV_FILE"

    print_success "Configuration saved to $ENV_FILE"

    # Set restrictive permissions
    chmod 600 "$ENV_FILE"
    print_success "Secure permissions set on $ENV_FILE"
}

collect_config_value() {
    local config_key="$1"

    echo "" >> "$ENV_FILE"
    echo "# Configuration: $config_key" >> "$ENV_FILE"

    case "$config_key" in
        # Domain & DNS
        "domain")
            prompt_input "DOMAIN" "Primary domain name" "" true "validate_domain"
            echo "DOMAIN=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # Email
        "email")
            prompt_input "ADMIN_EMAIL" "Administrator email" "" true "validate_email"
            echo "ADMIN_EMAIL=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # Cloudflare
        "cloudflare_token")
            prompt_input "CLOUDFLARE_API_TOKEN" "Cloudflare API Token" "" false
            echo "CLOUDFLARE_API_TOKEN=$INPUT_RESULT" >> "$ENV_FILE"

            prompt_input "CLOUDFLARE_ZONE_ID" "Cloudflare Zone ID" "" false
            echo "CLOUDFLARE_ZONE_ID=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # Tailscale
        "auth_key")
            prompt_input "TAILSCALE_AUTH_KEY" "Tailscale Auth Key" "" false
            echo "TAILSCALE_AUTH_KEY=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        "tailnet")
            prompt_input "TAILSCALE_TAILNET" "Tailscale Tailnet name" "" false
            echo "TAILSCALE_TAILNET=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # Database passwords
        "postgres_password")
            local pg_pass=$(generate_random_password 32)
            echo "POSTGRES_PASSWORD=$pg_pass" >> "$ENV_FILE"
            print_success "Generated PostgreSQL password"
            ;;

        "redis_password")
            local redis_pass=$(generate_random_password 32)
            echo "REDIS_PASSWORD=$redis_pass" >> "$ENV_FILE"
            print_success "Generated Redis password"
            ;;

        "mongo_password")
            local mongo_pass=$(generate_random_password 32)
            echo "MONGO_PASSWORD=$mongo_pass" >> "$ENV_FILE"
            print_success "Generated MongoDB password"
            ;;

        # API Keys
        "qdrant_api_key")
            local qdrant_key=$(generate_random_password 32)
            echo "QDRANT_API_KEY=$qdrant_key" >> "$ENV_FILE"
            print_success "Generated Qdrant API key"
            ;;

        "litellm_master_key")
            local litellm_key=$(generate_random_password 32)
            echo "LITELLM_MASTER_KEY=$litellm_key" >> "$ENV_FILE"
            print_success "Generated LiteLLM master key"
            ;;

        "openai_api_key")
            prompt_input "OPENAI_API_KEY" "OpenAI API Key (or skip)" "" false
            echo "OPENAI_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # OAuth
        "google_client_id")
            prompt_input "GOOGLE_CLIENT_ID" "Google OAuth Client ID" "" false
            echo "GOOGLE_CLIENT_ID=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        "google_client_secret")
            prompt_input "GOOGLE_CLIENT_SECRET" "Google OAuth Client Secret" "" false
            echo "GOOGLE_CLIENT_SECRET=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # JWT Secrets
        "jwt_secret"|"n8n_encryption_key"|"ap_encryption_key"|"windmill_token"|"quivr_jwt_secret"|"danswer_secret"|"searxng_secret"|"meili_master_key")
            local secret=$(generate_random_password 64)
            local var_name=$(echo "$config_key" | tr '[:lower:]' '[:upper:]')
            echo "${var_name}=$secret" >> "$ENV_FILE"
            print_success "Generated $config_key"
            ;;

        # Admin credentials
        "admin_password")
            prompt_input "ADMIN_PASSWORD" "Admin password (min 12 chars)" "" true "validate_password"
            echo "ADMIN_PASSWORD=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        "grafana_password"|"code_password"|"seafile_admin_password"|"anything_llm_password")
            local pass=$(generate_random_password 24)
            local var_name=$(echo "$config_key" | tr '[:lower:]' '[:upper:]')
            echo "${var_name}=$pass" >> "$ENV_FILE"
            print_success "Generated $config_key"
            ;;

        # MinIO
        "minio_root_user")
            prompt_input "MINIO_ROOT_USER" "MinIO root username" "minioadmin" false
            echo "MINIO_ROOT_USER=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        "minio_root_password")
            local minio_pass=$(generate_random_password 32)
            echo "MINIO_ROOT_PASSWORD=$minio_pass" >> "$ENV_FILE"
            print_success "Generated MinIO password"
            ;;

        # Signal
        "signal_phone")
            prompt_input "SIGNAL_PHONE" "Signal phone number (+1234567890)" "" false "validate_phone"
            echo "SIGNAL_PHONE=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        "signal_password")
            local signal_pass=$(generate_random_password 32)
            echo "SIGNAL_PASSWORD=$signal_pass" >> "$ENV_FILE"
            print_success "Generated Signal password"
            ;;

        # Jupyter
        "jupyter_token")
            local jupyter_token=$(generate_random_password 48)
            echo "JUPYTER_TOKEN=$jupyter_token" >> "$ENV_FILE"
            print_success "Generated Jupyter token"
            ;;

        # Prometheus
        "prometheus_retention")
            prompt_input "PROMETHEUS_RETENTION" "Prometheus data retention (e.g., 15d)" "15d" false
            echo "PROMETHEUS_RETENTION=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        # Seafile
        "seafile_admin_email")
            prompt_input "SEAFILE_ADMIN_EMAIL" "Seafile admin email" "$ADMIN_EMAIL" true "validate_email"
            echo "SEAFILE_ADMIN_EMAIL=$INPUT_RESULT" >> "$ENV_FILE"
            ;;

        *)
            print_warn "Unknown configuration: $config_key (skipped)"
            ;;
    esac
}
#───────────────────────────────────────────────────────────────────────────────
# DIRECTORY STRUCTURE CREATION
#───────────────────────────────────────────────────────────────────────────────

create_directory_structure() {
    log_phase "9" "📁 Directory Structure Creation"

    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Services file not found: $SERVICES_FILE"
        exit 1
    fi

    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE"))

    echo ""
    print_header "🏗️  Creating Directory Structure"
    echo ""

    # Create base directories
    print_info "Creating base directories..."

    local base_dirs=(
        "$DATA_ROOT"
        "$METADATA_DIR"
        "$DATA_ROOT/compose"
        "$DATA_ROOT/configs"
        "$DATA_ROOT/scripts"
        "$DATA_ROOT/backups"
        "$DATA_ROOT/logs"
        "$DATA_ROOT/temp"
    )

    for dir in "${base_dirs[@]"; do
        if mkdir -p "$dir" 2>/dev/null; then
            print_success "Created: $dir"
        else
            print_error "Failed to create: $dir"
            exit 1
        fi
    done

    # Create service-specific directories
    echo ""
    print_info "Creating service directories..."

    local created_count=0

    for service_key in "${selected_services[@]}"; do
        local service_dirs=()

        case "$service_key" in
            # Reverse Proxy
            "traefik")
                service_dirs=(
                    "$DATA_ROOT/traefik/config"
                    "$DATA_ROOT/traefik/acme"
                    "$DATA_ROOT/traefik/logs"
                )
                ;;

            # VPN
            "tailscale")
                service_dirs=(
                    "$DATA_ROOT/tailscale/state"
                    "$DATA_ROOT/tailscale/config"
                )
                ;;

            # Container Management
            "portainer")
                service_dirs=(
                    "$DATA_ROOT/portainer/data"
                )
                ;;

            "yacht")
                service_dirs=(
                    "$DATA_ROOT/yacht/config"
                )
                ;;

            # Databases
            "postgres")
                service_dirs=(
                    "$DATA_ROOT/postgres/data"
                    "$DATA_ROOT/postgres/backups"
                    "$DATA_ROOT/postgres/init"
                )
                ;;

            "redis")
                service_dirs=(
                    "$DATA_ROOT/redis/data"
                    "$DATA_ROOT/redis/config"
                )
                ;;

            "mongodb")
                service_dirs=(
                    "$DATA_ROOT/mongodb/data"
                    "$DATA_ROOT/mongodb/backups"
                    "$DATA_ROOT/mongodb/logs"
                )
                ;;

            # Vector Databases
            "qdrant")
                service_dirs=(
                    "$DATA_ROOT/qdrant/storage"
                    "$DATA_ROOT/qdrant/snapshots"
                    "$DATA_ROOT/qdrant/config"
                )
                ;;

            "weaviate")
                service_dirs=(
                    "$DATA_ROOT/weaviate/data"
                    "$DATA_ROOT/weaviate/backups"
                )
                ;;

            "milvus")
                service_dirs=(
                    "$DATA_ROOT/milvus/data"
                    "$DATA_ROOT/milvus/etcd"
                    "$DATA_ROOT/milvus/minio"
                    "$DATA_ROOT/milvus/logs"
                )
                ;;

            "chromadb")
                service_dirs=(
                    "$DATA_ROOT/chromadb/data"
                    "$DATA_ROOT/chromadb/backups"
                )
                ;;

            # AI Chat Interfaces
            "librechat")
                service_dirs=(
                    "$DATA_ROOT/librechat/uploads"
                    "$DATA_ROOT/librechat/config"
                    "$DATA_ROOT/librechat/logs"
                )
                ;;

            "openwebui")
                service_dirs=(
                    "$DATA_ROOT/openwebui/data"
                    "$DATA_ROOT/openwebui/uploads"
                )
                ;;

            "chatgptui")
                service_dirs=(
                    "$DATA_ROOT/chatgptui/data"
                )
                ;;

            "lobe")
                service_dirs=(
                    "$DATA_ROOT/lobe/data"
                    "$DATA_ROOT/lobe/uploads"
                )
                ;;

            "hollama")
                service_dirs=(
                    "$DATA_ROOT/hollama/data"
                )
                ;;

            # LLM Infrastructure
            "litellm")
                service_dirs=(
                    "$DATA_ROOT/litellm/config"
                    "$DATA_ROOT/litellm/logs"
                    "$DATA_ROOT/litellm/cache"
                )
                ;;

            "localai")
                service_dirs=(
                    "$DATA_ROOT/localai/models"
                    "$DATA_ROOT/localai/uploads"
                    "$DATA_ROOT/localai/config"
                )
                ;;

            # Communication
            "signal")
                service_dirs=(
                    "$DATA_ROOT/signal/data"
                    "$DATA_ROOT/signal/attachments"
                )
                ;;

            "ntfy")
                service_dirs=(
                    "$DATA_ROOT/ntfy/data"
                    "$DATA_ROOT/ntfy/cache"
                    "$DATA_ROOT/ntfy/config"
                )
                ;;

            # Automation
            "n8n")
                service_dirs=(
                    "$DATA_ROOT/n8n/data"
                    "$DATA_ROOT/n8n/workflows"
                    "$DATA_ROOT/n8n/backups"
                )
                ;;

            "activepieces")
                service_dirs=(
                    "$DATA_ROOT/activepieces/data"
                    "$DATA_ROOT/activepieces/flows"
                )
                ;;

            "windmill")
                service_dirs=(
                    "$DATA_ROOT/windmill/data"
                    "$DATA_ROOT/windmill/scripts"
                    "$DATA_ROOT/windmill/resources"
                )
                ;;

            "huginn")
                service_dirs=(
                    "$DATA_ROOT/huginn/data"
                )
                ;;

            # Monitoring
            "prometheus")
                service_dirs=(
                    "$DATA_ROOT/prometheus/data"
                    "$DATA_ROOT/prometheus/config"
                    "$DATA_ROOT/prometheus/rules"
                )
                ;;

            "grafana")
                service_dirs=(
                    "$DATA_ROOT/grafana/data"
                    "$DATA_ROOT/grafana/dashboards"
                    "$DATA_ROOT/grafana/provisioning/datasources"
                    "$DATA_ROOT/grafana/provisioning/dashboards"
                    "$DATA_ROOT/grafana/plugins"
                )
                ;;

            "uptimekuma")
                service_dirs=(
                    "$DATA_ROOT/uptimekuma/data"
                )
                ;;

            "netdata")
                service_dirs=(
                    "$DATA_ROOT/netdata/config"
                    "$DATA_ROOT/netdata/cache"
                    "$DATA_ROOT/netdata/lib"
                )
                ;;

            # Development
            "codeserver")
                service_dirs=(
                    "$DATA_ROOT/codeserver/config"
                    "$DATA_ROOT/codeserver/projects"
                    "$DATA_ROOT/codeserver/extensions"
                )
                ;;

            "jupyter")
                service_dirs=(
                    "$DATA_ROOT/jupyter/notebooks"
                    "$DATA_ROOT/jupyter/data"
                    "$DATA_ROOT/jupyter/config"
                )
                ;;

            # Storage
            "minio")
                service_dirs=(
                    "$DATA_ROOT/minio/data"
                    "$DATA_ROOT/minio/config"
                )
                ;;

            "seafile")
                service_dirs=(
                    "$DATA_ROOT/seafile/data"
                    "$DATA_ROOT/seafile/mysql"
                    "$DATA_ROOT/seafile/logs"
                )
                ;;

            # Search
            "searxng")
                service_dirs=(
                    "$DATA_ROOT/searxng/config"
                )
                ;;

            "meilisearch")
                service_dirs=(
                    "$DATA_ROOT/meilisearch/data"
                    "$DATA_ROOT/meilisearch/dumps"
                )
                ;;

            # RAG & Documents
            "anythingllm")
                service_dirs=(
                    "$DATA_ROOT/anythingllm/storage"
                    "$DATA_ROOT/anythingllm/documents"
                    "$DATA_ROOT/anythingllm/vector-cache"
                    "$DATA_ROOT/anythingllm/uploads"
                )
                ;;

            "danswer")
                service_dirs=(
                    "$DATA_ROOT/danswer/data"
                    "$DATA_ROOT/danswer/indexes"
                    "$DATA_ROOT/danswer/uploads"
                )
                ;;

            "quivr")
                service_dirs=(
                    "$DATA_ROOT/quivr/data"
                    "$DATA_ROOT/quivr/uploads"
                    "$DATA_ROOT/quivr/embeddings"
                )
                ;;

            *)
                print_warn "No directory structure defined for: $service_key"
                continue
                ;;
        esac

        # Create the directories
        for dir in "${service_dirs[@]"; do
            if mkdir -p "$dir" 2>/dev/null; then
                ((created_count++))
            else
                print_error "Failed to create: $dir"
            fi
        done
    done

    print_success "Created $created_count service directories"

    # Set appropriate permissions
    echo ""
    print_info "Setting directory permissions..."

    # Most directories: 755
    find "$DATA_ROOT" -type d -exec chmod 755 {} \; 2>/dev/null

    # Sensitive directories: 700
    local secure_dirs=(
        "$DATA_ROOT/traefik/acme"
        "$DATA_ROOT/tailscale/state"
        "$DATA_ROOT/postgres/data"
        "$DATA_ROOT/mongodb/data"
        "$DATA_ROOT/redis/data"
        "$METADATA_DIR"
    )

    for dir in "${secure_dirs[@]"; do
        if [[ -d "$dir" ]]; then
            chmod 700 "$dir"
        fi
    done

    print_success "Directory permissions configured"

    # Create directory map
    local dir_map_file="$METADATA_DIR/directory_map.json"

    cat > "$dir_map_file" <<EOF
{
  "created": "$(date -Iseconds)",
  "data_root": "$DATA_ROOT",
  "total_directories": $created_count,
  "base_directories": [
EOF

    local first=true
    for dir in "${base_dirs[@]"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$dir_map_file"
        fi
        first=false
        echo "    \"$dir\"" >> "$dir_map_file"
    done

    cat >> "$dir_map_file" <<EOF

  ],
  "service_directories": {
EOF

    first=true
    for service_key in "${selected_services[@]}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$dir_map_file"
        fi
        first=false

        echo "    \"$service_key\": [" >> "$dir_map_file"

        # List directories for this service
        local service_dirs=($(find "$DATA_ROOT" -type d -path "*/$service_key/*" 2>/dev/null | sort))
        local dir_first=true

        for dir in "${service_dirs[@]"; do
            if [[ "$dir_first" == false ]]; then
                echo "," >> "$dir_map_file"
            fi
            dir_first=false
            echo "      \"$dir\"" >> "$dir_map_file"
        done

        echo "    ]" >> "$dir_map_file"
    done

    cat >> "$dir_map_file" <<EOF

  }
}
EOF

    print_success "Directory map saved to $dir_map_file"
}

#───────────────────────────────────────────────────────────────────────────────
# SYSTEM VALIDATION
#───────────────────────────────────────────────────────────────────────────────

validate_system() {
    log_phase "10" "✅ System Validation"

    echo ""
    print_header "🔍 System Validation"
    echo ""

    local validation_errors=0
    local validation_warnings=0

    # Check Docker
    print_info "Validating Docker..."
    if ! docker ps &>/dev/null; then
        print_error "Docker is not running"
        ((validation_errors++))
    else
        print_success "Docker is running"

        # Check Docker Compose
        if ! docker compose version &>/dev/null; then
            print_error "Docker Compose not available"
            ((validation_errors++))
        else
            local compose_version=$(docker compose version --short)
            print_success "Docker Compose $compose_version available"
        fi
    fi

    # Check Ollama
    print_info "Validating Ollama..."
    if ! systemctl is-active --quiet ollama; then
        print_warn "Ollama service not running"
        ((validation_warnings++))
    else
        print_success "Ollama service is active"

        # Check if any models installed
        local model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
        if [[ $model_count -eq 0 ]]; then
            print_warn "No Ollama models installed"
            ((validation_warnings++))
        else
            print_success "$model_count Ollama model(s) installed"
        fi
    fi

    # Check GPU (if applicable)
    if [[ -f "$SYSTEM_INFO_FILE" ]]; then
        local has_gpu=$(jq -r '.gpu.detected' "$SYSTEM_INFO_FILE")

        if [[ "$has_gpu" == "true" ]]; then
            print_info "Validating GPU access..."

            if ! nvidia-smi &>/dev/null; then
                print_error "nvidia-smi not accessible"
                ((validation_errors++))
            else
                print_success "NVIDIA GPU accessible"

                # Test GPU in Docker
                if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
                    print_success "GPU accessible in Docker containers"
                else
                    print_warn "GPU not accessible in Docker"
                    ((validation_warnings++))
                fi
            fi
        fi
    fi

    # Check required files
    print_info "Validating configuration files..."

    local required_files=(
        "$SYSTEM_INFO_FILE:System info"
        "$SERVICES_FILE:Service selection"
        "$ENV_FILE:Environment config"
    )

    for file_info in "${required_files[@]"; do
        local file_path=$(echo "$file_info" | cut -d':' -f1)
        local file_desc=$(echo "$file_info" | cut -d':' -f2)

        if [[ ! -f "$file_path" ]]; then
            print_error "$file_desc not found: $file_path"
            ((validation_errors++))
        else
            print_success "$file_desc exists"
        fi
    done

    # Check directory structure
    print_info "Validating directory structure..."

    local required_dirs=(
        "$DATA_ROOT"
        "$METADATA_DIR"
        "$DATA_ROOT/compose"
        "$DATA_ROOT/configs"
        "$DATA_ROOT/scripts"
    )

    for dir in "${required_dirs[@]"; do
        if [[ ! -d "$dir" ]]; then
            print_error "Required directory missing: $dir"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -eq 0 ]]; then
        print_success "All required directories exist"
    fi

    # Check disk space
    print_info "Validating disk space..."

    local available_gb=$(df -BG "$DATA_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')

    if [[ $available_gb -lt 10 ]]; then
        print_error "Insufficient disk space: ${available_gb}GB available (minimum 10GB required)"
        ((validation_errors++))
    elif [[ $available_gb -lt 50 ]]; then
        print_warn "Low disk space: ${available_gb}GB available (50GB+ recommended)"
        ((validation_warnings++))
    else
        print_success "Sufficient disk space: ${available_gb}GB available"
    fi

    # Check memory
    print_info "Validating memory..."

    local total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')

    if [[ $total_mem_gb -lt 4 ]]; then
        print_error "Insufficient memory: ${total_mem_gb}GB (minimum 4GB required)"
        ((validation_errors++))
    elif [[ $total_mem_gb -lt 8 ]]; then
        print_warn "Limited memory: ${total_mem_gb}GB (8GB+ recommended)"
        ((validation_warnings++))
    else
        print_success "Sufficient memory: ${total_mem_gb}GB available"
    fi

    # Check network connectivity
    print_info "Validating network connectivity..."

    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        print_error "No internet connectivity"
        ((validation_errors++))
    else
        print_success "Internet connectivity OK"

        # Check DNS resolution
        if ! ping -c 1 -W 2 google.com &>/dev/null; then
            print_warn "DNS resolution issues detected"
            ((validation_warnings++))
        else
            print_success "DNS resolution OK"
        fi
    fi

    # Summary
    echo ""
    echo "$(printf '═%.0s' {1..60})"
    echo ""

    if [[ $validation_errors -eq 0 && $validation_warnings -eq 0 ]]; then
        print_success "✅ All validations passed!"
    elif [[ $validation_errors -eq 0 ]]; then
        print_warn "⚠️  Validation completed with $validation_warnings warning(s)"
    else
        print_error "❌ Validation failed with $validation_errors error(s) and $validation_warnings warning(s)"

        echo ""
        if ! confirm "Continue despite validation errors?"; then
            print_error "Setup aborted"
            exit 1
        fi
    fi

    # Save validation results
    local validation_file="$METADATA_DIR/validation_results.json"

    cat > "$validation_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "errors": $validation_errors,
  "warnings": $validation_warnings,
  "docker": {
    "running": $(docker ps &>/dev/null && echo "true" || echo "false"),
    "compose_available": $(docker compose version &>/dev/null && echo "true" || echo "false")
  },
  "ollama": {
    "service_active": $(systemctl is-active --quiet ollama && echo "true" || echo "false"),
    "models_installed": $(ollama list 2>/dev/null | tail -n +2 | wc -l)
  },
  "resources": {
    "disk_space_gb": $available_gb,
    "memory_gb": $total_mem_gb,
    "internet": $(ping -c 1 -W 2 8.8.8.8 &>/dev/null && echo "true" || echo "false")
  }
}
EOF

    print_success "Validation results saved to $validation_file"
}
#───────────────────────────────────────────────────────────────────────────────
# SUMMARY REPORT
#───────────────────────────────────────────────────────────────────────────────

generate_summary() {
    log_phase "11" "📊 Summary Report Generation"

    local summary_file="$METADATA_DIR/setup_summary.txt"
    local summary_json="$METADATA_DIR/setup_summary.json"

    # Gather data
    local total_services=0
    local service_names=()

    if [[ -f "$SERVICES_FILE" ]]; then
        total_services=$(jq -r '.services | length' "$SERVICES_FILE")
        mapfile -t service_names < <(jq -r '.services[].display_name' "$SERVICES_FILE")
    fi

    local ollama_models=()
    if command -v ollama &>/dev/null; then
        mapfile -t ollama_models < <(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
    fi

    # Generate text summary
    cat > "$summary_file" <<EOF
═══════════════════════════════════════════════════════════════════════════════
                          🎉 SETUP COMPLETE! 🎉
═══════════════════════════════════════════════════════════════════════════════

Setup Date:           $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname:             $(hostname)
Data Directory:       $DATA_ROOT
Metadata Directory:   $METADATA_DIR

───────────────────────────────────────────────────────────────────────────────
SYSTEM INFORMATION
───────────────────────────────────────────────────────────────────────────────

OS:                   $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
Kernel:               $(uname -r)
CPU:                  $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
CPU Cores:            $(nproc)
Memory:               $(free -h | awk '/^Mem:/{print $2}')
Disk Space:           $(df -h "$DATA_ROOT" | tail -1 | awk '{print $4}') available

EOF

    # GPU info if available
    if [[ -f "$SYSTEM_INFO_FILE" ]]; then
        local has_gpu=$(jq -r '.gpu.detected' "$SYSTEM_INFO_FILE" 2>/dev/null)

        if [[ "$has_gpu" == "true" ]]; then
            cat >> "$summary_file" <<EOF
GPU:                  NVIDIA GPU Detected
GPU Driver:           $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
CUDA Version:         $(nvidia-smi | grep "CUDA Version" | awk '{print $9}' 2>/dev/null)

EOF
        fi
    fi

    cat >> "$summary_file" <<EOF
───────────────────────────────────────────────────────────────────────────────
DOCKER ENVIRONMENT
───────────────────────────────────────────────────────────────────────────────

Docker Version:       $(docker --version | awk '{print $3}' | tr -d ',')
Docker Compose:       $(docker compose version --short)
Docker Root:          $(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

───────────────────────────────────────────────────────────────────────────────
OLLAMA INSTALLATION
───────────────────────────────────────────────────────────────────────────────

Ollama Version:       $(ollama --version 2>/dev/null | awk '{print $NF}')
Service Status:       $(systemctl is-active ollama)
Models Installed:     ${#ollama_models[@]}}

EOF

    if [[ ${#ollama_models[@]}} -gt 0 ]]; then
        cat >> "$summary_file" <<EOF
Installed Models:
EOF
        for model in "${ollama_models[@]}}"; do
            echo "  • $model" >> "$summary_file"
        done
        echo "" >> "$summary_file"
    fi

    cat >> "$summary_file" <<EOF
───────────────────────────────────────────────────────────────────────────────
SELECTED SERVICES
───────────────────────────────────────────────────────────────────────────────

Total Services:       $total_services

EOF

    if [[ ${#service_names[@] -gt 0 ]]; then
        cat >> "$summary_file" <<EOF
Service List:
EOF
        for service in "${service_names[@]"; do
            echo "  ✓ $service" >> "$summary_file"
        done
        echo "" >> "$summary_file"
    fi

    cat >> "$summary_file" <<EOF
───────────────────────────────────────────────────────────────────────────────
CONFIGURATION FILES
───────────────────────────────────────────────────────────────────────────────

System Info:          $SYSTEM_INFO_FILE
Service Selection:    $SERVICES_FILE
Environment Config:   $ENV_FILE
Directory Map:        $METADATA_DIR/directory_map.json
Validation Results:   $METADATA_DIR/validation_results.json
Setup Log:            $LOG_FILE

───────────────────────────────────────────────────────────────────────────────
NEXT STEPS
───────────────────────────────────────────────────────────────────────────────

1. Review Configuration:

   View your environment configuration:
   $ cat $ENV_FILE

   Review selected services:
   $ cat $SERVICES_FILE | jq .

2. Generate Docker Compose Files:

   Run the compose generator script (Script 2):
   $ sudo bash 2_generate_compose_files.sh

3. Deploy Services:

   Run the deployment script (Script 3):
   $ sudo bash 3_deploy_services.sh

4. Access Services:

   Services will be available at:
   • Traefik Dashboard:  https://traefik.$DOMAIN
   • Portainer:          https://portainer.$DOMAIN
   • Open WebUI:         https://openwebui.$DOMAIN
   • Other services:     https://<service>.$DOMAIN

5. Monitor Deployment:

   Check running containers:
   $ docker ps

   View service logs:
   $ docker compose -f $DATA_ROOT/compose/<service>.yml logs -f

   Check Ollama:
   $ ollama list
   $ systemctl status ollama

───────────────────────────────────────────────────────────────────────────────
IMPORTANT NOTES
───────────────────────────────────────────────────────────────────────────────

• Your environment file contains sensitive credentials
  Location: $ENV_FILE (permissions: 600)

• Backup your metadata directory regularly:
  $ tar -czf homelab-backup-\$(date +%Y%m%d).tar.gz $METADATA_DIR

• Default admin credentials are in $ENV_FILE
  Change them after first login!

• Traefik will automatically obtain Let's Encrypt SSL certificates
  Ensure your domain DNS is properly configured

• GPU acceleration is available for Ollama
  Test with: ollama run llama3.2

───────────────────────────────────────────────────────────────────────────────
TROUBLESHOOTING
───────────────────────────────────────────────────────────────────────────────

• Check setup log for errors:
  $ tail -100 $LOG_FILE

• Verify Docker network:
  $ docker network ls | grep homelab

• Test Ollama API:
  $ curl http://localhost:11434/api/tags

• Review system validation:
  $ cat $METADATA_DIR/validation_results.json | jq .

───────────────────────────────────────────────────────────────────────────────
SUPPORT & DOCUMENTATION
───────────────────────────────────────────────────────────────────────────────

For issues or questions:
• Review the setup log: $LOG_FILE
• Check service documentation in Docker Compose files
• Consult individual service documentation

═══════════════════════════════════════════════════════════════════════════════
                    🚀 Ready to generate compose files! 🚀
═══════════════════════════════════════════════════════════════════════════════

EOF

    # Generate JSON summary
    cat > "$summary_json" <<EOF
{
  "setup_completed": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "directories": {
    "data_root": "$DATA_ROOT",
    "metadata": "$METADATA_DIR"
  },
  "system": {
    "os": "$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)",
    "kernel": "$(uname -r)",
    "cpu_cores": $(nproc),
    "memory_gb": $(free -g | awk '/^Mem:/{print $2}'),
    "gpu_available": $(nvidia-smi &>/dev/null && echo "true" || echo "false")
  },
  "docker": {
    "version": "$(docker --version | awk '{print $3}' | tr -d ',')",
    "compose_version": "$(docker compose version --short)"
  },
  "ollama": {
    "version": "$(ollama --version 2>/dev/null | awk '{print $NF}')",
    "service_active": $(systemctl is-active --quiet ollama && echo "true" || echo "false"),
    "models_count": ${#ollama_models[@]},
    "models": [
EOF

    local first=true
    for model in "${ollama_models[@]}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$summary_json"
        fi
        first=false
        echo "      \"$model\"" >> "$summary_json"
    done

    cat >> "$summary_json" <<EOF

    ]
  },
  "services": {
    "total": $total_services,
    "names": [
EOF

    first=true
    for service in "${service_names[@]"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$summary_json"
        fi
        first=false
        echo "      \"$service\"" >> "$summary_json"
    done

    cat >> "$summary_json" <<EOF

    ]
  },
  "files": {
    "system_info": "$SYSTEM_INFO_FILE",
    "services": "$SERVICES_FILE",
    "environment": "$ENV_FILE",
    "directory_map": "$METADATA_DIR/directory_map.json",
    "validation": "$METADATA_DIR/validation_results.json",
    "log": "$LOG_FILE"
  },
  "next_steps": [
    "Review configuration files",
    "Run compose generator script",
    "Deploy services",
    "Access services via domain"
  ]
}
EOF

    # Display summary
    clear
    cat "$summary_file"

    print_success "Summary saved to:"
    print_success "  • Text: $summary_file"
    print_success "  • JSON: $summary_json"
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION FLOW
#───────────────────────────────────────────────────────────────────────────────

main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi

    # Initialize
    setup_logging

    # Display banner
    clear
    print_banner

    # Phase 1: Detect system
    detect_system

    # Phase 2: Collect domain info
    collect_domain_info

    # Phase 3: Update system
    update_system

    # Phase 4: Install Docker
    install_docker

    # Phase 5: Configure Docker
    configure_docker

    # Phase 6: Install Ollama
    install_ollama

    # Phase 7: Select services
    select_services

    # Phase 8: Collect configs
    collect_configurations

    # Phase 9: Create directories
    create_directory_structure

    # Phase 10: Validate system
    validate_system

    # Phase 11: Generate summary
    generate_summary

    # Completion message
    echo ""
    echo "$(printf '═%.0s' {1..80})"
    echo ""
    print_success "🎉 SETUP SCRIPT COMPLETED SUCCESSFULLY!"
    echo ""
    print_info "Next: Run the compose generator script:"
    echo ""
    echo "  ${CYAN}sudo bash 2_generate_compose_files.sh${NC}"
    echo ""
    echo "$(printf '═%.0s' {1..80})"
    echo ""
}

# Run main function
main "$@"

# Exit successfully
exit 0

#───────────────────────────────────────────────────────────────────────────────
# END OF SCRIPT 1: SYSTEM SETUP
#───────────────────────────────────────────────────────────────────────────────
