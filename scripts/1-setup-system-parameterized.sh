#!/bin/bash
# Script 1: Setup & Configuration (Parameterized)
# 
# NOTE: This script runs as root (required for system setup)
# STACK_USER_UID will own BASE_DIR for container permissions

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM - PARAMETERIZED SETUP               ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           Interactive Configuration + EBS Validation         ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Global variables (will be set by interactive_config)
BASE_DIR=""
DOCKER_NETWORK=""
DOMAIN_NAME=""
LOCALHOST=""
STACK_USER_UID=""
STACK_USER_GID=""
OPENCLAW_UID=""
OPENCLAW_GID=""

# Port variables (will be set by allocate_ports)
PROMETHEUS_PORT=""
GRAFANA_PORT=""
N8N_PORT=""
DIFY_PORT=""
ANYTHINGLLM_PORT=""
LITELLM_PORT=""
OPENWEBUI_PORT=""
MINIO_S3_PORT=""
MINIO_CONSOLE_PORT=""
SIGNAL_PORT=""
OPENCLAW_PORT=""
FLOWISE_PORT=""

# Detect and mount EBS volumes
detect_ebs_volumes() {
    print_header "EBS Volume Detection"
    
    echo "🔍 Scanning for available EBS volumes..."
    echo ""
    
    # List available block devices
    local devices=($(lsblk -d -n -o NAME,SIZE,TYPE | grep -E "^xvd|^sd|^nvme" | awk '{print $1}'))
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        print_error "No EBS volumes detected"
        print_info "Please attach EBS volumes to this instance first"
        exit 1
    fi
    
    echo "📋 Available EBS Volumes:"
    echo ""
    printf "%-15s %-10s %-15s %-30s\n" "DEVICE" "SIZE" "TYPE" "MOUNT POINT"
    echo "────────────────────────────────────────────────────────────────"
    
    local available_mounts=()
    
    for device in "${devices[@]}"; do
        local device_path="/dev/$device"
        local size=$(lsblk -d -n -o SIZE "$device_path")
        local mount_point=$(findmnt -n -o TARGET -S "$device_path" 2>/dev/null || echo "Not mounted")
        
        printf "%-15s %-10s %-15s %-30s\n" "$device_path" "$size" "EBS" "$mount_point"
        
        if [[ "$mount_point" != "Not mounted" ]]; then
            available_mounts+=("$mount_point")
        fi
    done
    
    echo ""
    
    # If no mounted volumes found, offer to mount
    if [[ ${#available_mounts[@]} -eq 0 ]]; then
        print_warning "No EBS volumes are currently mounted"
        echo ""
        echo "Available EBS devices to mount:"
        for device in "${devices[@]}"; do
            echo "  /dev/$device"
        done
        echo ""
        
        read -p "Enter device to mount (e.g., /dev/xvdf): " selected_device
        if [[ -z "$selected_device" ]]; then
            print_error "No device selected"
            exit 1
        fi
        
        if [[ ! -b "$selected_device" ]]; then
            print_error "Invalid device: $selected_device"
            exit 1
        fi
        
        read -p "Enter mount point (e.g., /mnt/data): " mount_point
        if [[ -z "$mount_point" ]]; then
            mount_point="/mnt/data"
        fi
        
        # Create mount point
        mkdir -p "$mount_point"
        
        # Mount the device
        if mount "$selected_device" "$mount_point"; then
            print_success "Mounted $selected_device at $mount_point"
            available_mounts+=("$mount_point")
        else
            print_error "Failed to mount $selected_device"
            exit 1
        fi
    fi
    
    echo ""
    echo "📋 Available Mount Points for Stack:"
    for i in "${!available_mounts[@]}"; do
        echo "  $((i+1)). ${available_mounts[$i]}"
    done
    echo ""
    
    while true; do
        read -p "Select mount point for this stack (1-${#available_mounts[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#available_mounts[@]} ]]; then
            BASE_DIR="${available_mounts[$((selection-1))]}"
            break
        else
            print_warning "Please enter a number between 1 and ${#available_mounts[@]}"
        fi
    done
    
    print_success "Selected EBS mount: $BASE_DIR"
}

# Interactive configuration
interactive_config() {
    print_header "Stack Configuration"
    
    # Show selected EBS volume
    print_info "Using EBS volume: $BASE_DIR"
    
    # Get current user UID/GID (not root)
    local current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
    local current_uid=$(id -u "$current_user" 2>/dev/null || echo "1000")
    local current_gid=$(id -g "$current_user" 2>/dev/null || echo "1000")
    
    read -p "Service owner UID [$current_uid]: " STACK_USER_UID
    STACK_USER_UID=${STACK_USER_UID:-$current_uid}
    
    read -p "Service owner GID [$current_gid]: " STACK_USER_GID
    STACK_USER_GID=${STACK_USER_GID:-$current_gid}
    
    read -p "Docker network name [ai_platform]: " DOCKER_NETWORK
    DOCKER_NETWORK=${DOCKER_NETWORK:-ai_platform}
    
    read -p "Domain name [ai.datasquiz.net]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-ai.datasquiz.net}
    
    read -p "Localhost for testing [localhost]: " LOCALHOST
    LOCALHOST=${LOCALHOST:-localhost}
    
    # OpenClaw gets next UID up
    OPENCLAW_UID=$((STACK_USER_UID + 1))
    OPENCLAW_GID=$((STACK_USER_GID + 1))
    
    print_success "Configuration collected"
    echo "   Base Directory: ${BASE_DIR}"
    echo "   User UID/GID: ${STACK_USER_UID}:${STACK_USER_GID}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
}

# EBS validation (enhanced)
validate_ebs_mount() {
    print_header "EBS Volume Validation"
    
    # Check it exists
    if [ ! -d "${BASE_DIR}" ]; then
        print_error "${BASE_DIR} does not exist"
        exit 1
    fi

    # Check it is a real mount point (not just local dir)
    if ! mountpoint -q "${BASE_DIR}"; then
        print_warning "${BASE_DIR} is not a dedicated mount point"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi

    # Check it is writable by the specified UID
    if ! sudo -u "#${STACK_USER_UID}" test -w "${BASE_DIR}"; then
        print_error "${BASE_DIR} is not writable by UID ${STACK_USER_UID}"
        exit 1
    fi

    # Check sufficient free space (minimum 20GB)
    local free_gb=$(df -BG "${BASE_DIR}" | awk 'NR==2 {gsub("G",""); print $4}')
    if [ "${free_gb}" -lt 20 ]; then
        print_error "Insufficient space: ${free_gb}GB free, 20GB required"
        exit 1
    fi

    print_success "EBS volume validated at ${BASE_DIR} (${free_gb}GB free)"
}

# Create directory structure
create_directories() {
    print_header "Creating Directory Structure"
    
    mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/logs" "${BASE_DIR}/config" "${BASE_DIR}/apparmor"
    mkdir -p "${BASE_DIR}/ssl/certs/${DOMAIN_NAME}"
    
    print_success "Directory structure created"
}

# Set ownership
set_ownership() {
    print_header "Setting Directory Ownership"
    
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}"
    
    print_success "Ownership set to ${STACK_USER_UID}:${STACK_USER_GID}"
}

# Port allocation (fixed with while-true loop)
allocate_ports() {
    print_header "Port Allocation"
    
    local services=(prometheus grafana n8n dify anythingllm litellm \
                    openwebui minio signal openclaw flowise)
    local default_ports=(5000 5001 5002 5003 5004 5005 5006 \
                         5007 5008 5009 5010 5011)

    for i in "${!services[@]}"; do
        local service=${services[$i]}
        local default_port=${default_ports[$i]}
        local port=""

        while true; do
            read -p "${service} port [${default_port}]: " port_input
            port=${port_input:-$default_port}

            if ss -tlnp | grep -q ":${port} "; then
                print_warning "Port ${port} is in use — choose another"
            else
                print_success "Port ${port} assigned to ${service}"
                break
            fi
        done

        # Export for later use in generate_env
        declare -g "${service^^}_PORT=${port}"
    done
}

# AppArmor template creation
create_apparmor_templates() {
    print_header "Creating AppArmor Templates"
    
    local profile_dir="${BASE_DIR}/apparmor"
    
    # Default profile template
    cat > "${profile_dir}/default.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # TODO: Future hardening - restrict per service to ${BASE_DIR}/data/${service_name}/**
  # Current: Allow access to entire stack data directory
  BASE_DIR_PLACEHOLDER/** rw,

  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,

  network,
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
EOF

    # OpenClaw profile template (allowlist-only)
    cat > "${profile_dir}/openclaw.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allowlist: only what OpenClaw needs
  BASE_DIR_PLACEHOLDER/data/openclaw/** rw,
  /tmp/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    # Tailscale profile template
    cat > "${profile_dir}/tailscale.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-tailscale flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  BASE_DIR_PLACEHOLDER/data/tailscale/** rw,
  /dev/net/tun rw,
  /var/run/tailscale/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    print_success "AppArmor templates created in ${profile_dir}"
}

# Environment generation
generate_env() {
    print_header "Generating Environment Configuration"
    
    cat > "${BASE_DIR}/config/.env" << EOF
# === Stack Configuration ===
BASE_DIR=${BASE_DIR}
DOCKER_NETWORK=${DOCKER_NETWORK}
DOMAIN_NAME=${DOMAIN_NAME}
LOCALHOST=${LOCALHOST}

# === User Identity ===
STACK_USER_UID=${STACK_USER_UID}
STACK_USER_GID=${STACK_USER_GID}
OPENCLAW_UID=${OPENCLAW_UID}
OPENCLAW_GID=${OPENCLAW_GID}

# === AppArmor Profile Names ===
APPARMOR_DEFAULT=${DOCKER_NETWORK}-default
APPARMOR_OPENCLAW=${DOCKER_NETWORK}-openclaw
APPARMOR_TAILSCALE=${DOCKER_NETWORK}-tailscale

# === Port Configuration ===
PROMETHEUS_PORT=${PROMETHEUS_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
N8N_PORT=${N8N_PORT}
DIFY_PORT=${DIFY_PORT}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
LITELLM_PORT=${LITELLM_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
MINIO_S3_PORT=${MINIO_S3_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
SIGNAL_PORT=${SIGNAL_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
FLOWISE_PORT=${FLOWISE_PORT}

# === Vector DB ===
VECTOR_DB=qdrant

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${DOMAIN_NAME}
EOF

    print_success "Configuration written to ${BASE_DIR}/config/.env"
}

# Validate configuration
validate_config() {
    print_header "Configuration Validation"
    
    local required_vars=(BASE_DIR DOCKER_NETWORK DOMAIN_NAME STACK_USER_UID STACK_USER_GID)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            print_error "Required variable $var not set"
            exit 1
        fi
    done
    
    # Validate .env file exists
    if [[ ! -f "${BASE_DIR}/config/.env" ]]; then
        print_error "Environment file not found"
        exit 1
    fi
    
    print_success "Configuration validated"
}

# Display summary
display_summary() {
    print_header "Setup Summary"
    
    echo "📊 Stack Configuration:"
    echo "   Base Directory: ${BASE_DIR}"
    echo "   User UID/GID: ${STACK_USER_UID}:${STACK_USER_GID}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
    echo ""
    echo "🔧 Configuration Files:"
    echo "   Environment: ${BASE_DIR}/config/.env"
    echo "   AppArmor Templates: ${BASE_DIR}/apparmor/"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Review the generated configuration"
    echo "   2. Run: bash 2-deploy-services.sh"
    echo "   3. Run: bash 3-configure-services.sh"
    echo ""
    print_success "Stack setup complete!"
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_banner
    
    # Execute setup phases
    detect_ebs_volumes
    interactive_config
    validate_ebs_mount
    create_directories
    set_ownership
    allocate_ports
    create_apparmor_templates
    generate_env
    validate_config
    display_summary
}

# Run main function
main "$@"
