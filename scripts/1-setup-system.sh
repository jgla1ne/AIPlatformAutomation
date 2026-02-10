#!/bin/bash
#===============================================================================
# AI Platform Automation - Script 1: System Configuration Collection
#===============================================================================
# Purpose: Interactive wizard to collect all configuration for AI platform
# Version: 2.0.0
# Date: 2025-02-10
#
# This script:
#   1. Validates system requirements (Ubuntu 22.04/24.04, root, dependencies)
#   2. Detects hardware (CPU, RAM, GPU, storage)
#   3. Collects network configuration (IP, domain, Cloudflare)
#   4. Allows service selection with grouped categories
#   5. Configures LLM providers (OpenAI, Anthropic, Groq, etc.)
#   6. Generates secure credentials
#   7. Saves configuration for next scripts
#
# NO installations happen in this script - only configuration collection
#===============================================================================

set -euo pipefail

#===============================================================================
# SCRIPT METADATA
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.0.0"
LOG_FILE="${SCRIPT_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

#===============================================================================
# COLOR DEFINITIONS
#===============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

#===============================================================================
# CONFIGURATION ARRAYS
#===============================================================================
declare -A CONFIG
declare -A CREDENTIALS
declare -A LLM_PROVIDERS
declare -A SERVICE_PORTS
declare -A SERVICE_DEPENDENCIES

#===============================================================================
# DEFAULT CONFIGURATION
#===============================================================================
CONFIG["INSTALL_DIR"]="${PROJECT_ROOT}"
CONFIG["SCRIPTS_DIR"]="${SCRIPT_DIR}"
CONFIG["DATA_DIR"]="/mnt/data"
CONFIG["TIMEZONE"]="America/Toronto"
CONFIG["TELEMETRY"]="false"
CONFIG["USE_CLOUDFLARE"]="false"
CONFIG["ENABLE_SSL"]="false"

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  $1"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    log "INFO" "=== $1 ==="
}

print_section() {
    echo -e "\n${BLUE}${BOLD}▓▓▓ $1 ▓▓▓${NC}"
    log "INFO" "--- $1 ---"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "INFO" "$1"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    log "WARN" "$1"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

die() {
    print_error "$1"
    log "FATAL" "$1"
    exit 1
}

#===============================================================================
# SYSTEM VALIDATION FUNCTIONS
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo $0"
    fi
    log "INFO" "Root privileges confirmed"
}

check_os() {
    print_section "System Validation"
    
    # Check if Ubuntu
    if [ ! -f /etc/os-release ]; then
        die "Cannot detect OS. /etc/os-release not found."
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        die "This script requires Ubuntu. Detected: $ID"
    fi
    
    # Check version
    case "$VERSION_ID" in
        22.04|24.04)
            print_success "Ubuntu $VERSION_ID detected"
            CONFIG["OS_VERSION"]=$VERSION_ID
            ;;
        *)
            die "Ubuntu version $VERSION_ID not supported. Requires 22.04 or 24.04"
            ;;
    esac
    
    # Architecture check
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        die "Architecture $arch not supported. Requires x86_64"
    fi
    
    print_success "System architecture: $arch"
    CONFIG["ARCH"]=$arch
    
    log "INFO" "OS validation passed: Ubuntu ${CONFIG["OS_VERSION"]} $arch"
}

check_dependencies() {
    print_section "Checking Dependencies"
    
    local required_commands=(
        "curl"
        "wget"
        "git"
        "jq"
        "gpg"
        "apt-get"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
            print_warning "$cmd not found"
        else
            print_success "$cmd found"
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_warning "Installing missing dependencies: ${missing_commands[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_commands[@]}" || die "Failed to install dependencies"
        print_success "Dependencies installed"
    fi
    
    log "INFO" "All dependencies satisfied"
}

detect_gpu() {
    print_section "GPU Detection"
    
    CONFIG["GPU_AVAILABLE"]="false"
    CONFIG["GPU_TYPE"]="none"
    CONFIG["GPU_COUNT"]="0"
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        if [ "$gpu_count" -gt 0 ]; then
            CONFIG["GPU_AVAILABLE"]="true"
            CONFIG["GPU_TYPE"]="nvidia"
            CONFIG["GPU_COUNT"]=$gpu_count
            CONFIG["GPU_MODEL"]=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
            print_success "NVIDIA GPU detected: ${CONFIG["GPU_MODEL"]} (Count: $gpu_count)"
            log "INFO" "GPU: ${CONFIG["GPU_MODEL"]} x${gpu_count}"
        fi
    fi
    
    # Check for AMD GPU
    if [ "${CONFIG["GPU_AVAILABLE"]}" == "false" ] && command -v rocm-smi &> /dev/null; then
        if rocm-smi &> /dev/null; then
            CONFIG["GPU_AVAILABLE"]="true"
            CONFIG["GPU_TYPE"]="amd"
            print_success "AMD GPU detected (ROCm available)"
            log "INFO" "GPU: AMD ROCm"
        fi
    fi
    
    if [ "${CONFIG["GPU_AVAILABLE"]}" == "false" ]; then
        print_warning "No GPU detected - will use CPU for inference"
        print_info "GPU acceleration recommended for better performance"
        log "INFO" "No GPU detected - CPU mode"
    fi
}

detect_system_resources() {
    print_section "System Resources"
    
    # CPU info
    local cpu_cores=$(nproc)
    local cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    CONFIG["CPU_CORES"]=$cpu_cores
    CONFIG["CPU_MODEL"]=$cpu_model
    print_success "CPU: $cpu_model ($cpu_cores cores)"
    
    # Memory
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    CONFIG["TOTAL_RAM_GB"]=$total_ram
    print_success "RAM: ${total_ram}GB"
    
    if [ "$total_ram" -lt 8 ]; then
        print_warning "Low RAM detected. 16GB+ recommended for optimal performance"
    fi
    
    # Disk space
    local data_dir_disk=$(df -BG "${CONFIG["DATA_DIR"]}" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    CONFIG["AVAILABLE_DISK_GB"]=$data_dir_disk
    print_success "Available disk space at ${CONFIG["DATA_DIR"]}: ${data_dir_disk}GB"
    
    if [ "$data_dir_disk" -lt 100 ]; then
        print_warning "Low disk space. 500GB+ recommended for models and data"
    fi
    
    log "INFO" "Resources: ${cpu_cores}C/${total_ram}GB RAM/${data_dir_disk}GB disk"
}

generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

#===============================================================================
# BASIC INFO COLLECTION
#===============================================================================

collect_basic_info() {
    print_section "Basic System Information"
    
    # Detect public IP
    local detected_ip=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || echo "")
    
    echo ""
    read -p "Enter public IP address [$detected_ip]: " public_ip
    CONFIG["PUBLIC_IP"]="${public_ip:-$detected_ip}"
    
    if [ -z "${CONFIG["PUBLIC_IP"]}" ]; then
        print_warning "No public IP detected. Services will only be accessible locally."
    else
        print_success "Public IP: ${CONFIG["PUBLIC_IP"]}"
    fi
    
    # Admin email
    read -p "Enter admin email address: " admin_email
    while [ -z "$admin_email" ]; do
        print_warning "Email address is required"
        read -p "Enter admin email address: " admin_email
    done
    CONFIG["ADMIN_EMAIL"]=$admin_email
    print_success "Admin email: $admin_email"
    
    log "INFO" "Basic info collected: IP=${CONFIG["PUBLIC_IP"]}, Email=$admin_email"
}
#===============================================================================
# NETWORK CONFIGURATION
#===============================================================================

configure_network() {
    print_section "Network Configuration"
    
    echo ""
    print_info "Configure domain and SSL settings"
    echo ""
    
    # Domain configuration
    read -p "Do you have a domain name? (y/n): " has_domain
    if [[ "$has_domain" =~ ^[Yy]$ ]]; then
        read -p "Enter your domain (e.g., example.com): " domain
        while [ -z "$domain" ]; do
            print_warning "Domain cannot be empty"
            read -p "Enter your domain: " domain
        done
        CONFIG["DOMAIN"]=$domain
        CONFIG["HAS_DOMAIN"]="true"
        print_success "Domain: $domain"
        
        # Cloudflare configuration
        echo ""
        print_info "Cloudflare provides DDoS protection, caching, and SSL"
        read -p "Are you using Cloudflare? (y/n): " use_cf
        if [[ "$use_cf" =~ ^[Yy]$ ]]; then
            CONFIG["USE_CLOUDFLARE"]="true"
            
            read -p "Enter Cloudflare API Token: " cf_token
            while [ -z "$cf_token" ]; do
                print_warning "API token required for Cloudflare"
                read -p "Enter Cloudflare API Token: " cf_token
            done
            CREDENTIALS["CLOUDFLARE_API_TOKEN"]=$cf_token
            
            read -p "Enter Cloudflare Zone ID: " cf_zone
            while [ -z "$cf_zone" ]; do
                print_warning "Zone ID required"
                read -p "Enter Cloudflare Zone ID: " cf_zone
            done
            CREDENTIALS["CLOUDFLARE_ZONE_ID"]=$cf_zone
            
            print_success "Cloudflare configured"
        else
            CONFIG["USE_CLOUDFLARE"]="false"
        fi
        
        # SSL configuration
        echo ""
        read -p "Enable SSL/HTTPS with Let's Encrypt? (y/n): " enable_ssl
        if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
            CONFIG["ENABLE_SSL"]="true"
            CONFIG["SSL_EMAIL"]="${CONFIG["ADMIN_EMAIL"]}"
            print_success "SSL enabled - will use Let's Encrypt"
        else
            CONFIG["ENABLE_SSL"]="false"
            print_warning "SSL disabled - services will use HTTP"
        fi
    else
        CONFIG["HAS_DOMAIN"]="false"
        CONFIG["USE_CLOUDFLARE"]="false"
        CONFIG["ENABLE_SSL"]="false"
        print_info "No domain - services will be accessible via IP only"
    fi
    
    log "INFO" "Network configured: Domain=${CONFIG["DOMAIN"]:-none}, SSL=${CONFIG["ENABLE_SSL"]}"
}

configure_timezone() {
    print_section "Timezone Configuration"
    
    echo ""
    print_info "Current timezone: ${CONFIG["TIMEZONE"]}"
    echo ""
    echo "Common timezones:"
    echo "  1) America/New_York (EST)"
    echo "  2) America/Chicago (CST)"
    echo "  3) America/Denver (MST)"
    echo "  4) America/Los_Angeles (PST)"
    echo "  5) America/Toronto (EST)"
    echo "  6) Europe/London (GMT)"
    echo "  7) Europe/Paris (CET)"
    echo "  8) Asia/Tokyo (JST)"
    echo "  9) Keep current (${CONFIG["TIMEZONE"]})"
    echo ""
    
    read -p "Select timezone [1-9] or enter custom: " tz_choice
    
    case $tz_choice in
        1) CONFIG["TIMEZONE"]="America/New_York" ;;
        2) CONFIG["TIMEZONE"]="America/Chicago" ;;
        3) CONFIG["TIMEZONE"]="America/Denver" ;;
        4) CONFIG["TIMEZONE"]="America/Los_Angeles" ;;
        5) CONFIG["TIMEZONE"]="America/Toronto" ;;
        6) CONFIG["TIMEZONE"]="Europe/London" ;;
        7) CONFIG["TIMEZONE"]="Europe/Paris" ;;
        8) CONFIG["TIMEZONE"]="Asia/Tokyo" ;;
        9) ;; # Keep current
        *) 
            if [ -n "$tz_choice" ]; then
                CONFIG["TIMEZONE"]=$tz_choice
            fi
            ;;
    esac
    
    print_success "Timezone: ${CONFIG["TIMEZONE"]}"
    log "INFO" "Timezone set to ${CONFIG["TIMEZONE"]}"
}

configure_telemetry() {
    print_section "Telemetry & Analytics"
    
    echo ""
    print_info "Some services include telemetry for usage analytics and improvements."
    print_info "Disabling telemetry opts out where possible."
    echo ""
    
    read -p "Enable telemetry? (y/n) [n]: " enable_telemetry
    if [[ "$enable_telemetry" =~ ^[Yy]$ ]]; then
        CONFIG["TELEMETRY"]="true"
        print_success "Telemetry enabled"
    else
        CONFIG["TELEMETRY"]="false"
        print_success "Telemetry disabled"
    fi
    
    log "INFO" "Telemetry: ${CONFIG["TELEMETRY"]}"
}

#===============================================================================
# SERVICE SELECTION - ALL SERVICES WITH PROPER CATEGORIES
#===============================================================================

select_services() {
    print_header "Service Selection"
    
    echo ""
    print_info "Select which services to install"
    print_info "You can choose individual services or install complete stacks"
    echo ""
    
    # Initialize all services to false
    CONFIG["INSTALL_POSTGRES"]="false"
    CONFIG["INSTALL_REDIS"]="false"
    CONFIG["INSTALL_MINIO"]="false"
    CONFIG["INSTALL_TRAEFIK"]="false"
    CONFIG["INSTALL_OLLAMA"]="false"
    CONFIG["INSTALL_LITELLM"]="false"
    CONFIG["INSTALL_N8N"]="false"
    CONFIG["INSTALL_FLOWISE"]="false"
    CONFIG["INSTALL_OPENWEBUI"]="false"
    CONFIG["INSTALL_ANYTHINGLLM"]="false"
    CONFIG["INSTALL_LANGFUSE"]="false"
    CONFIG["INSTALL_DIFY"]="false"
    CONFIG["INSTALL_LIBRECHAT"]="false"
    CONFIG["INSTALL_PORTAINER"]="false"
    CONFIG["INSTALL_UPTIME_KUMA"]="false"
    CONFIG["INSTALL_MONITORING"]="false"
    CONFIG["INSTALL_SIGNAL"]="false"
    CONFIG["INSTALL_OPENCLAW"]="false"
    CONFIG["INSTALL_VECTORDB"]="false"
    
    # Quick install options
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    QUICK INSTALL OPTIONS                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  1) Full Stack    - Everything (recommended for production)"
    echo "  2) Minimal Stack - Core infrastructure + one AI interface"
    echo "  3) Custom        - Pick individual services"
    echo ""
    
    read -p "Select installation type [1-3]: " install_type
    
    case $install_type in
        1)
            select_full_stack
            return
            ;;
        2)
            select_minimal_stack
            return
            ;;
        3)
            select_custom_services
            return
            ;;
        *)
            print_warning "Invalid selection, using custom mode"
            select_custom_services
            return
            ;;
    esac
}

select_full_stack() {
    print_section "Full Stack Installation"
    
    CONFIG["INSTALL_POSTGRES"]="true"
    CONFIG["INSTALL_REDIS"]="true"
    CONFIG["INSTALL_MINIO"]="true"
    CONFIG["INSTALL_TRAEFIK"]="true"
    CONFIG["INSTALL_OLLAMA"]="true"
    CONFIG["INSTALL_LITELLM"]="true"
    CONFIG["INSTALL_N8N"]="true"
    CONFIG["INSTALL_FLOWISE"]="true"
    CONFIG["INSTALL_OPENWEBUI"]="true"
    CONFIG["INSTALL_ANYTHINGLLM"]="true"
    CONFIG["INSTALL_LANGFUSE"]="true"
    CONFIG["INSTALL_DIFY"]="true"
    CONFIG["INSTALL_LIBRECHAT"]="true"
    CONFIG["INSTALL_PORTAINER"]="true"
    CONFIG["INSTALL_UPTIME_KUMA"]="true"
    CONFIG["INSTALL_MONITORING"]="true"
    CONFIG["INSTALL_VECTORDB"]="true"
    
    CONFIG["VECTORDB_TYPE"]="qdrant"
    
    print_success "Full stack selected - all services will be installed"
    log "INFO" "Full stack installation selected"
}

select_minimal_stack() {
    print_section "Minimal Stack Installation"
    
    # Core infrastructure (required)
    CONFIG["INSTALL_POSTGRES"]="true"
    CONFIG["INSTALL_REDIS"]="true"
    CONFIG["INSTALL_TRAEFIK"]="true"
    CONFIG["INSTALL_OLLAMA"]="true"
    
    echo ""
    print_info "Core infrastructure selected: PostgreSQL, Redis, Traefik, Ollama"
    echo ""
    echo "Select ONE AI interface:"
    echo "  1) Open WebUI     - Clean, modern interface"
    echo "  2) AnythingLLM    - Document-focused"
    echo "  3) LibreChat      - ChatGPT-like experience"
    echo "  4) Dify           - Workflow-based builder"
    echo ""
    
    read -p "Select AI interface [1-4]: " ai_choice
    
    case $ai_choice in
        1) CONFIG["INSTALL_OPENWEBUI"]="true" ;;
        2) CONFIG["INSTALL_ANYTHINGLLM"]="true" ;;
        3) CONFIG["INSTALL_LIBRECHAT"]="true" ;;
        4) CONFIG["INSTALL_DIFY"]="true" ;;
        *) 
            print_warning "Invalid selection, defaulting to Open WebUI"
            CONFIG["INSTALL_OPENWEBUI"]="true"
            ;;
    esac
    
    # Optional: Add Portainer for management
    read -p "Add Portainer for Docker management? (y/n): " add_portainer
    if [[ "$add_portainer" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_PORTAINER"]="true"
    fi
    
    print_success "Minimal stack configured"
    log "INFO" "Minimal stack installation selected"
}

select_custom_services() {
    print_section "Custom Service Selection"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CORE INFRASTRUCTURE (Required)"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install PostgreSQL? (y/n) [y]: " install_pg
    CONFIG["INSTALL_POSTGRES"]="${install_pg:-y}"
    [[ "${CONFIG["INSTALL_POSTGRES"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_POSTGRES"]="true" || CONFIG["INSTALL_POSTGRES"]="false"
    
    read -p "Install Redis? (y/n) [y]: " install_redis
    CONFIG["INSTALL_REDIS"]="${install_redis:-y}"
    [[ "${CONFIG["INSTALL_REDIS"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_REDIS"]="true" || CONFIG["INSTALL_REDIS"]="false"
    
    read -p "Install MinIO (S3 storage)? (y/n) [y]: " install_minio
    CONFIG["INSTALL_MINIO"]="${install_minio:-y}"
    [[ "${CONFIG["INSTALL_MINIO"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_MINIO"]="true" || CONFIG["INSTALL_MINIO"]="false"
    
    read -p "Install Traefik (reverse proxy)? (y/n) [y]: " install_traefik
    CONFIG["INSTALL_TRAEFIK"]="${install_traefik:-y}"
    [[ "${CONFIG["INSTALL_TRAEFIK"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_TRAEFIK"]="true" || CONFIG["INSTALL_TRAEFIK"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "LLM INFERENCE"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install Ollama (local models)? (y/n) [y]: " install_ollama
    CONFIG["INSTALL_OLLAMA"]="${install_ollama:-y}"
    [[ "${CONFIG["INSTALL_OLLAMA"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_OLLAMA"]="true" || CONFIG["INSTALL_OLLAMA"]="false"
    
    read -p "Install LiteLLM (unified API)? (y/n) [y]: " install_litellm
    CONFIG["INSTALL_LITELLM"]="${install_litellm:-y}"
    [[ "${CONFIG["INSTALL_LITELLM"]}" =~ ^[Yy]$ ]] && CONFIG["INSTALL_LITELLM"]="true" || CONFIG["INSTALL_LITELLM"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AI CHAT INTERFACES"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install Open WebUI? (y/n): " install_openwebui
    [[ "$install_openwebui" =~ ^[Yy]$ ]] && CONFIG["INSTALL_OPENWEBUI"]="true" || CONFIG["INSTALL_OPENWEBUI"]="false"
    
    read -p "Install AnythingLLM? (y/n): " install_anythingllm
    [[ "$install_anythingllm" =~ ^[Yy]$ ]] && CONFIG["INSTALL_ANYTHINGLLM"]="true" || CONFIG["INSTALL_ANYTHINGLLM"]="false"
    
    read -p "Install LibreChat? (y/n): " install_librechat
    [[ "$install_librechat" =~ ^[Yy]$ ]] && CONFIG["INSTALL_LIBRECHAT"]="true" || CONFIG["INSTALL_LIBRECHAT"]="false"
    
    read -p "Install Dify? (y/n): " install_dify
    [[ "$install_dify" =~ ^[Yy]$ ]] && CONFIG["INSTALL_DIFY"]="true" || CONFIG["INSTALL_DIFY"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WORKFLOW & AUTOMATION"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install n8n (workflow automation)? (y/n): " install_n8n
    [[ "$install_n8n" =~ ^[Yy]$ ]] && CONFIG["INSTALL_N8N"]="true" || CONFIG["INSTALL_N8N"]="false"
    
    read -p "Install Flowise (visual AI flows)? (y/n): " install_flowise
    [[ "$install_flowise" =~ ^[Yy]$ ]] && CONFIG["INSTALL_FLOWISE"]="true" || CONFIG["INSTALL_FLOWISE"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "OBSERVABILITY & MONITORING"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install Langfuse (LLM observability)? (y/n): " install_langfuse
    [[ "$install_langfuse" =~ ^[Yy]$ ]] && CONFIG["INSTALL_LANGFUSE"]="true" || CONFIG["INSTALL_LANGFUSE"]="false"
    
    read -p "Install Uptime Kuma (uptime monitoring)? (y/n): " install_uptime
    [[ "$install_uptime" =~ ^[Yy]$ ]] && CONFIG["INSTALL_UPTIME_KUMA"]="true" || CONFIG["INSTALL_UPTIME_KUMA"]="false"
    
    read -p "Install Grafana/Prometheus monitoring? (y/n): " install_monitoring
    [[ "$install_monitoring" =~ ^[Yy]$ ]] && CONFIG["INSTALL_MONITORING"]="true" || CONFIG["INSTALL_MONITORING"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "MANAGEMENT & TOOLS"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install Portainer (Docker management)? (y/n): " install_portainer
    [[ "$install_portainer" =~ ^[Yy]$ ]] && CONFIG["INSTALL_PORTAINER"]="true" || CONFIG["INSTALL_PORTAINER"]="false"
    
    echo ""
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SPECIALIZED SERVICES"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "Install Signal Proxy (messaging)? (y/n): " install_signal
    [[ "$install_signal" =~ ^[Yy]$ ]] && CONFIG["INSTALL_SIGNAL"]="true" || CONFIG["INSTALL_SIGNAL"]="false"
    
    read -p "Install OpenClaw (AI agent framework)? (y/n): " install_openclaw
    [[ "$install_openclaw" =~ ^[Yy]$ ]] && CONFIG["INSTALL_OPENCLAW"]="true" || CONFIG["INSTALL_OPENCLAW"]="false"
    
    # Vector Database
    read -p "Install Vector Database? (y/n): " install_vectordb
    if [[ "$install_vectordb" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_VECTORDB"]="true"
        select_vector_db
    else
        CONFIG["INSTALL_VECTORDB"]="false"
    fi
    
    print_success "Custom service selection completed"
    log "INFO" "Custom services selected"
}

select_vector_db() {
    echo ""
    print_info "Select Vector Database:"
    echo "  1) Qdrant    - Fast, Rust-based (recommended)"
    echo "  2) Chroma    - Python-native, simple"
    echo "  3) Weaviate  - GraphQL API, enterprise features"
    echo ""
    
    read -p "Select vector DB [1-3]: " vectordb_choice
    
    case $vectordb_choice in
        1) CONFIG["VECTORDB_TYPE"]="qdrant" ;;
        2) CONFIG["VECTORDB_TYPE"]="chroma" ;;
        3) CONFIG["VECTORDB_TYPE"]="weaviate" ;;
        *)
            print_warning "Invalid selection, defaulting to Qdrant"
            CONFIG["VECTORDB_TYPE"]="qdrant"
            ;;
    esac
    
    print_success "Vector DB selected: ${CONFIG["VECTORDB_TYPE"]}"
}
#===============================================================================
# LLM PROVIDER CONFIGURATION - ALL MAJOR PROVIDERS
#===============================================================================

configure_llm_providers() {
    print_header "LLM Provider Configuration"

    echo ""
    print_info "Configure API keys for LLM providers"
    print_info "You can skip providers you don't plan to use"
    echo ""

    # Initialize provider status
    LLM_PROVIDERS["OPENAI"]="false"
    LLM_PROVIDERS["ANTHROPIC"]="false"
    LLM_PROVIDERS["GROQ"]="false"
    LLM_PROVIDERS["MISTRAL"]="false"
    LLM_PROVIDERS["COHERE"]="false"
    LLM_PROVIDERS["TOGETHER"]="false"
    LLM_PROVIDERS["PERPLEXITY"]="false"
    LLM_PROVIDERS["OPENROUTER"]="false"
    LLM_PROVIDERS["GOOGLE"]="false"
    LLM_PROVIDERS["XAI"]="false"
    LLM_PROVIDERS["HUGGINGFACE"]="false"

    configure_openai
    configure_anthropic
    configure_groq
    configure_mistral
    configure_cohere
    configure_together
    configure_perplexity
    configure_openrouter
    configure_google_ai
    configure_xai
    configure_huggingface

    # Web search APIs (for OpenClaw and other tools)
    configure_search_apis

    # Additional tool APIs
    configure_tool_apis
}

#===============================================================================
# OPENAI
#===============================================================================

configure_openai() {
    print_section "OpenAI Configuration"

    echo ""
    print_info "OpenAI provides GPT-4, GPT-4 Turbo, GPT-3.5"
    print_info "Get API key: https://platform.openai.com/api-keys"
    echo ""

    read -p "Configure OpenAI? (y/n): " config_openai
    if [[ "$config_openai" =~ ^[Yy]$ ]]; then
        read -p "Enter OpenAI API Key: " openai_key
        if [ -n "$openai_key" ]; then
            CREDENTIALS["OPENAI_API_KEY"]=$openai_key
            LLM_PROVIDERS["OPENAI"]="true"
            print_success "OpenAI configured"

            # Optional: Organization ID
            read -p "Enter OpenAI Organization ID (optional, press Enter to skip): " openai_org
            if [ -n "$openai_org" ]; then
                CREDENTIALS["OPENAI_ORG_ID"]=$openai_org
            fi

            log "INFO" "OpenAI provider configured"
        else
            print_warning "No API key provided - OpenAI skipped"
        fi
    else
        print_info "OpenAI skipped"
    fi
}

#===============================================================================
# ANTHROPIC (CLAUDE)
#===============================================================================

configure_anthropic() {
    print_section "Anthropic (Claude) Configuration"

    echo ""
    print_info "Anthropic provides Claude 3 (Opus, Sonnet, Haiku)"
    print_info "Get API key: https://console.anthropic.com/settings/keys"
    echo ""

    read -p "Configure Anthropic? (y/n): " config_anthropic
    if [[ "$config_anthropic" =~ ^[Yy]$ ]]; then
        read -p "Enter Anthropic API Key: " anthropic_key
        if [ -n "$anthropic_key" ]; then
            CREDENTIALS["ANTHROPIC_API_KEY"]=$anthropic_key
            LLM_PROVIDERS["ANTHROPIC"]="true"
            print_success "Anthropic configured"
            log "INFO" "Anthropic provider configured"
        else
            print_warning "No API key provided - Anthropic skipped"
        fi
    else
        print_info "Anthropic skipped"
    fi
}

#===============================================================================
# GROQ (FAST INFERENCE)
#===============================================================================

configure_groq() {
    print_section "Groq Configuration"

    echo ""
    print_info "Groq provides ultra-fast inference for Llama, Mixtral, Gemma"
    print_info "Get API key: https://console.groq.com/keys"
    echo ""

    read -p "Configure Groq? (y/n): " config_groq
    if [[ "$config_groq" =~ ^[Yy]$ ]]; then
        read -p "Enter Groq API Key: " groq_key
        if [ -n "$groq_key" ]; then
            CREDENTIALS["GROQ_API_KEY"]=$groq_key
            LLM_PROVIDERS["GROQ"]="true"
            print_success "Groq configured"
            log "INFO" "Groq provider configured"
        else
            print_warning "No API key provided - Groq skipped"
        fi
    else
        print_info "Groq skipped"
    fi
}

#===============================================================================
# MISTRAL AI
#===============================================================================

configure_mistral() {
    print_section "Mistral AI Configuration"

    echo ""
    print_info "Mistral AI provides Mistral Large, Medium, Small models"
    print_info "Get API key: https://console.mistral.ai/api-keys"
    echo ""

    read -p "Configure Mistral? (y/n): " config_mistral
    if [[ "$config_mistral" =~ ^[Yy]$ ]]; then
        read -p "Enter Mistral API Key: " mistral_key
        if [ -n "$mistral_key" ]; then
            CREDENTIALS["MISTRAL_API_KEY"]=$mistral_key
            LLM_PROVIDERS["MISTRAL"]="true"
            print_success "Mistral configured"
            log "INFO" "Mistral provider configured"
        else
            print_warning "No API key provided - Mistral skipped"
        fi
    else
        print_info "Mistral skipped"
    fi
}

#===============================================================================
# COHERE
#===============================================================================

configure_cohere() {
    print_section "Cohere Configuration"

    echo ""
    print_info "Cohere provides Command, Embed, Rerank models"
    print_info "Get API key: https://dashboard.cohere.com/api-keys"
    echo ""

    read -p "Configure Cohere? (y/n): " config_cohere
    if [[ "$config_cohere" =~ ^[Yy]$ ]]; then
        read -p "Enter Cohere API Key: " cohere_key
        if [ -n "$cohere_key" ]; then
            CREDENTIALS["COHERE_API_KEY"]=$cohere_key
            LLM_PROVIDERS["COHERE"]="true"
            print_success "Cohere configured"
            log "INFO" "Cohere provider configured"
        else
            print_warning "No API key provided - Cohere skipped"
        fi
    else
        print_info "Cohere skipped"
    fi
}

#===============================================================================
# TOGETHER AI
#===============================================================================

configure_together() {
    print_section "Together AI Configuration"

    echo ""
    print_info "Together AI provides 100+ open-source models"
    print_info "Get API key: https://api.together.xyz/settings/api-keys"
    echo ""

    read -p "Configure Together AI? (y/n): " config_together
    if [[ "$config_together" =~ ^[Yy]$ ]]; then
        read -p "Enter Together AI API Key: " together_key
        if [ -n "$together_key" ]; then
            CREDENTIALS["TOGETHER_API_KEY"]=$together_key
            LLM_PROVIDERS["TOGETHER"]="true"
            print_success "Together AI configured"
            log "INFO" "Together AI provider configured"
        else
            print_warning "No API key provided - Together AI skipped"
        fi
    else
        print_info "Together AI skipped"
    fi
}

#===============================================================================
# PERPLEXITY AI
#===============================================================================

configure_perplexity() {
    print_section "Perplexity AI Configuration"

    echo ""
    print_info "Perplexity provides online/offline models with citations"
    print_info "Get API key: https://www.perplexity.ai/settings/api"
    echo ""

    read -p "Configure Perplexity? (y/n): " config_perplexity
    if [[ "$config_perplexity" =~ ^[Yy]$ ]]; then
        read -p "Enter Perplexity API Key: " perplexity_key
        if [ -n "$perplexity_key" ]; then
            CREDENTIALS["PERPLEXITY_API_KEY"]=$perplexity_key
            LLM_PROVIDERS["PERPLEXITY"]="true"
            print_success "Perplexity configured"
            log "INFO" "Perplexity provider configured"
        else
            print_warning "No API key provided - Perplexity skipped"
        fi
    else
        print_info "Perplexity skipped"
    fi
}

#===============================================================================
# OPENROUTER
#===============================================================================

configure_openrouter() {
    print_section "OpenRouter Configuration"

    echo ""
    print_info "OpenRouter provides unified access to 200+ models"
    print_info "Get API key: https://openrouter.ai/keys"
    echo ""

    read -p "Configure OpenRouter? (y/n): " config_openrouter
    if [[ "$config_openrouter" =~ ^[Yy]$ ]]; then
        read -p "Enter OpenRouter API Key: " openrouter_key
        if [ -n "$openrouter_key" ]; then
            CREDENTIALS["OPENROUTER_API_KEY"]=$openrouter_key
            LLM_PROVIDERS["OPENROUTER"]="true"
            print_success "OpenRouter configured"
            log "INFO" "OpenRouter provider configured"
        else
            print_warning "No API key provided - OpenRouter skipped"
        fi
    else
        print_info "OpenRouter skipped"
    fi
}

#===============================================================================
# GOOGLE AI (GEMINI)
#===============================================================================

configure_google_ai() {
    print_section "Google AI (Gemini) Configuration"

    echo ""
    print_info "Google AI provides Gemini Pro and Gemini Ultra models"
    print_info "Get API key: https://makersuite.google.com/app/apikey"
    echo ""

    read -p "Configure Google AI? (y/n): " config_google
    if [[ "$config_google" =~ ^[Yy]$ ]]; then
        read -p "Enter Google AI API Key: " google_key
        if [ -n "$google_key" ]; then
            CREDENTIALS["GOOGLE_AI_API_KEY"]=$google_key
            LLM_PROVIDERS["GOOGLE"]="true"
            print_success "Google AI configured"
            log "INFO" "Google AI provider configured"
        else
            print_warning "No API key provided - Google AI skipped"
        fi
    else
        print_info "Google AI skipped"
    fi
}

#===============================================================================
# XAI (GROK)
#===============================================================================

configure_xai() {
    print_section "xAI (Grok) Configuration"

    echo ""
    print_info "xAI provides Grok models with real-time web access"
    print_info "Get API key: https://console.x.ai/"
    echo ""

    read -p "Configure xAI? (y/n): " config_xai
    if [[ "$config_xai" =~ ^[Yy]$ ]]; then
        read -p "Enter xAI API Key: " xai_key
        if [ -n "$xai_key" ]; then
            CREDENTIALS["XAI_API_KEY"]=$xai_key
            LLM_PROVIDERS["XAI"]="true"
            print_success "xAI configured"
            log "INFO" "xAI provider configured"
        else
            print_warning "No API key provided - xAI skipped"
        fi
    else
        print_info "xAI skipped"
    fi
}

#===============================================================================
# HUGGING FACE
#===============================================================================

configure_huggingface() {
    print_section "Hugging Face Configuration"

    echo ""
    print_info "Hugging Face provides access to thousands of open models"
    print_info "Get API key: https://huggingface.co/settings/tokens"
    echo ""

    read -p "Configure Hugging Face? (y/n): " config_hf
    if [[ "$config_hf" =~ ^[Yy]$ ]]; then
        read -p "Enter Hugging Face API Token: " hf_token
        if [ -n "$hf_token" ]; then
            CREDENTIALS["HUGGINGFACE_API_KEY"]=$hf_token
            LLM_PROVIDERS["HUGGINGFACE"]="true"
            print_success "Hugging Face configured"
            log "INFO" "Hugging Face provider configured"
        else
            print_warning "No API token provided - Hugging Face skipped"
        fi
    else
        print_info "Hugging Face skipped"
    fi
}

#===============================================================================
# WEB SEARCH APIs (for OpenClaw and AI agents)
#===============================================================================

configure_search_apis() {
    print_section "Web Search API Configuration"

    echo ""
    print_info "Configure web search APIs for AI agents and tools"
    print_info "These enable agents to search the web for current information"
    echo ""

    # Brave Search API
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Brave Search API (Recommended for OpenClaw)"
    print_info "Get API key: https://brave.com/search/api/"
    echo ""

    read -p "Configure Brave Search? (y/n): " config_brave
    if [[ "$config_brave" =~ ^[Yy]$ ]]; then
        read -p "Enter Brave Search API Key: " brave_key
        if [ -n "$brave_key" ]; then
            CREDENTIALS["BRAVE_API_KEY"]=$brave_key
            CONFIG["BRAVE_SEARCH_ENABLED"]="true"
            print_success "Brave Search configured"
            log "INFO" "Brave Search API configured"
        else
            print_warning "No API key provided - Brave Search skipped"
            CONFIG["BRAVE_SEARCH_ENABLED"]="false"
        fi
    else
        print_info "Brave Search skipped"
        CONFIG["BRAVE_SEARCH_ENABLED"]="false"
    fi

    # Serper API
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Serper API (Google Search API)"
    print_info "Get API key: https://serper.dev/api-key"
    echo ""

    read -p "Configure Serper? (y/n): " config_serper
    if [[ "$config_serper" =~ ^[Yy]$ ]]; then
        read -p "Enter Serper API Key: " serper_key
        if [ -n "$serper_key" ]; then
            CREDENTIALS["SERPER_API_KEY"]=$serper_key
            CONFIG["SERPER_ENABLED"]="true"
            print_success "Serper configured"
            log "INFO" "Serper API configured"
        else
            print_warning "No API key provided - Serper skipped"
            CONFIG["SERPER_ENABLED"]="false"
        fi
    else
        print_info "Serper skipped"
        CONFIG["SERPER_ENABLED"]="false"
    fi

    # SerpAPI
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "SerpAPI (Google Search)"
    print_info "Get API key: https://serpapi.com/manage-api-key"
    echo ""

    read -p "Configure SerpAPI? (y/n): " config_serpapi
    if [[ "$config_serpapi" =~ ^[Yy]$ ]]; then
        read -p "Enter SerpAPI Key: " serpapi_key
        if [ -n "$serpapi_key" ]; then
            CREDENTIALS["SERPAPI_KEY"]=$serpapi_key
            CONFIG["SERPAPI_ENABLED"]="true"
            print_success "SerpAPI configured"
            log "INFO" "SerpAPI configured"
        else
            print_warning "No API key provided - SerpAPI skipped"
            CONFIG["SERPAPI_ENABLED"]="false"
        fi
    else
        print_info "SerpAPI skipped"
        CONFIG["SERPAPI_ENABLED"]="false"
    fi
}

#===============================================================================
# ADDITIONAL TOOL APIs
#===============================================================================

configure_tool_apis() {
    print_section "Additional Tool APIs"

    echo ""
    print_info "Configure additional APIs for enhanced functionality"
    echo ""

    # Tavily Search API
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Tavily Search API (AI-optimized search)"
    print_info "Get API key: https://app.tavily.com/"
    echo ""

    read -p "Configure Tavily? (y/n): " config_tavily
    if [[ "$config_tavily" =~ ^[Yy]$ ]]; then
        read -p "Enter Tavily API Key: " tavily_key
        if [ -n "$tavily_key" ]; then
            CREDENTIALS["TAVILY_API_KEY"]=$tavily_key
            CONFIG["TAVILY_ENABLED"]="true"
            print_success "Tavily configured"
            log "INFO" "Tavily API configured"
        fi
    fi

    # Jina AI (Reader API)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Jina AI Reader API (webpage to LLM-friendly format)"
    print_info "Get API key: https://jina.ai/reader"
    echo ""

    read -p "Configure Jina Reader? (y/n): " config_jina
    if [[ "$config_jina" =~ ^[Yy]$ ]]; then
        read -p "Enter Jina API Key: " jina_key
        if [ -n "$jina_key" ]; then
            CREDENTIALS["JINA_API_KEY"]=$jina_key
            CONFIG["JINA_ENABLED"]="true"
            print_success "Jina Reader configured"
            log "INFO" "Jina Reader API configured"
        fi
    fi

    # Firecrawl (Web scraping)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Firecrawl API (web scraping for LLMs)"
    print_info "Get API key: https://firecrawl.dev/"
    echo ""

    read -p "Configure Firecrawl? (y/n): " config_firecrawl
    if [[ "$config_firecrawl" =~ ^[Yy]$ ]]; then
        read -p "Enter Firecrawl API Key: " firecrawl_key
        if [ -n "$firecrawl_key" ]; then
            CREDENTIALS["FIRECRAWL_API_KEY"]=$firecrawl_key
            CONFIG["FIRECRAWL_ENABLED"]="true"
            print_success "Firecrawl configured"
            log "INFO" "Firecrawl API configured"
        fi
    fi
}
#===============================================================================
# SERVICE CONFIGURATION FUNCTIONS
#===============================================================================

#===============================================================================
# N8N CONFIGURATION
#===============================================================================

configure_n8n() {
    print_section "n8n Configuration"

    # Port
    read -p "Enter n8n port [5678]: " n8n_port
    CONFIG["N8N_PORT"]="${n8n_port:-5678}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter n8n subdomain [n8n]: " n8n_subdomain
        CONFIG["N8N_SUBDOMAIN"]="${n8n_subdomain:-n8n}"
        CONFIG["N8N_URL"]="https://${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["N8N_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["N8N_PORT"]}"
    fi

    # Encryption key
    CONFIG["N8N_ENCRYPTION_KEY"]=$(generate_secret)

    # Basic auth
    read -p "Enable basic authentication? (y/n): " n8n_auth
    if [[ "$n8n_auth" =~ ^[Yy]$ ]]; then
        read -p "Enter n8n username: " n8n_user
        read -sp "Enter n8n password: " n8n_pass
        echo ""
        CREDENTIALS["N8N_BASIC_AUTH_USER"]=$n8n_user
        CREDENTIALS["N8N_BASIC_AUTH_PASSWORD"]=$n8n_pass
        CONFIG["N8N_BASIC_AUTH_ACTIVE"]="true"
    else
        CONFIG["N8N_BASIC_AUTH_ACTIVE"]="false"
    fi

    # Timezone
    CONFIG["N8N_TIMEZONE"]="${CONFIG["TIMEZONE"]}"

    print_success "n8n configured: ${CONFIG["N8N_URL"]}"
    log "INFO" "n8n configured on port ${CONFIG["N8N_PORT"]}"
}

#===============================================================================
# FLOWISE CONFIGURATION
#===============================================================================

configure_flowise() {
    print_section "Flowise Configuration"

    # Port
    read -p "Enter Flowise port [3000]: " flowise_port
    CONFIG["FLOWISE_PORT"]="${flowise_port:-3000}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Flowise subdomain [flowise]: " flowise_subdomain
        CONFIG["FLOWISE_SUBDOMAIN"]="${flowise_subdomain:-flowise}"
        CONFIG["FLOWISE_URL"]="https://${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["FLOWISE_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["FLOWISE_PORT"]}"
    fi

    # Username/password
    read -p "Enter Flowise username [admin]: " flowise_user
    CONFIG["FLOWISE_USERNAME"]="${flowise_user:-admin}"

    read -sp "Enter Flowise password: " flowise_pass
    echo ""
    CREDENTIALS["FLOWISE_PASSWORD"]=$flowise_pass

    # Secret key
    CONFIG["FLOWISE_SECRETKEY_OVERWRITE"]=$(generate_secret)

    # Database
    CONFIG["FLOWISE_DATABASE_PATH"]="${CONFIG["DATA_DIR"]}/flowise"

    print_success "Flowise configured: ${CONFIG["FLOWISE_URL"]}"
    log "INFO" "Flowise configured on port ${CONFIG["FLOWISE_PORT"]}"
}

#===============================================================================
# OPEN WEBUI CONFIGURATION
#===============================================================================

configure_openwebui() {
    print_section "Open WebUI Configuration"

    # Port
    read -p "Enter Open WebUI port [3001]: " openwebui_port
    CONFIG["OPENWEBUI_PORT"]="${openwebui_port:-3001}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Open WebUI subdomain [chat]: " openwebui_subdomain
        CONFIG["OPENWEBUI_SUBDOMAIN"]="${openwebui_subdomain:-chat}"
        CONFIG["OPENWEBUI_URL"]="https://${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["OPENWEBUI_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["OPENWEBUI_PORT"]}"
    fi

    # Ollama integration
    read -p "Enable Ollama integration? (y/n): " enable_ollama
    if [[ "$enable_ollama" =~ ^[Yy]$ ]]; then
        CONFIG["OPENWEBUI_OLLAMA_ENABLED"]="true"
        if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
            CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]="http://ollama:11434"
        else
            read -p "Enter external Ollama URL: " ollama_url
            CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]=$ollama_url
        fi
    else
        CONFIG["OPENWEBUI_OLLAMA_ENABLED"]="false"
    fi

    # Data directory
    CONFIG["OPENWEBUI_DATA_DIR"]="${CONFIG["DATA_DIR"]}/open-webui"

    # Webserver secret
    CONFIG["OPENWEBUI_WEBSERVER_SECRET"]=$(generate_secret)

    print_success "Open WebUI configured: ${CONFIG["OPENWEBUI_URL"]}"
    log "INFO" "Open WebUI configured on port ${CONFIG["OPENWEBUI_PORT"]}"
}

#===============================================================================
# ANYTHINGLLM CONFIGURATION
#===============================================================================

configure_anythingllm() {
    print_section "AnythingLLM Configuration"

    # Port
    read -p "Enter AnythingLLM port [3002]: " anythingllm_port
    CONFIG["ANYTHINGLLM_PORT"]="${anythingllm_port:-3002}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter AnythingLLM subdomain [anything]: " anythingllm_subdomain
        CONFIG["ANYTHINGLLM_SUBDOMAIN"]="${anythingllm_subdomain:-anything}"
        CONFIG["ANYTHINGLLM_URL"]="https://${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["ANYTHINGLLM_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["ANYTHINGLLM_PORT"]}"
    fi

    # Storage path
    CONFIG["ANYTHINGLLM_STORAGE_DIR"]="${CONFIG["DATA_DIR"]}/anythingllm"

    # Auth token
    CONFIG["ANYTHINGLLM_AUTH_TOKEN"]=$(generate_secret)

    # JWT secret
    CONFIG["ANYTHINGLLM_JWT_SECRET"]=$(generate_secret)

    print_success "AnythingLLM configured: ${CONFIG["ANYTHINGLLM_URL"]}"
    log "INFO" "AnythingLLM configured on port ${CONFIG["ANYTHINGLLM_PORT"]}"
}

#===============================================================================
# LANGFUSE CONFIGURATION
#===============================================================================

configure_langfuse() {
    print_section "Langfuse Configuration"

    # Port
    read -p "Enter Langfuse port [3003]: " langfuse_port
    CONFIG["LANGFUSE_PORT"]="${langfuse_port:-3003}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Langfuse subdomain [langfuse]: " langfuse_subdomain
        CONFIG["LANGFUSE_SUBDOMAIN"]="${langfuse_subdomain:-langfuse}"
        CONFIG["LANGFUSE_URL"]="https://${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["LANGFUSE_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["LANGFUSE_PORT"]}"
    fi

    # Database
    local db_pass=$(generate_secret)
    CREDENTIALS["LANGFUSE_DB_PASSWORD"]=$db_pass
    CONFIG["LANGFUSE_DATABASE_URL"]="postgresql://langfuse:${db_pass}@langfuse-db:5432/langfuse"

    # Secrets
    CONFIG["LANGFUSE_SALT"]=$(generate_secret)
    CONFIG["LANGFUSE_NEXTAUTH_SECRET"]=$(generate_secret)
    CONFIG["LANGFUSE_NEXTAUTH_URL"]="${CONFIG["LANGFUSE_URL"]}"

    # Telemetry
    CONFIG["LANGFUSE_TELEMETRY_ENABLED"]="${CONFIG["TELEMETRY_ENABLED"]}"

    print_success "Langfuse configured: ${CONFIG["LANGFUSE_URL"]}"
    log "INFO" "Langfuse configured on port ${CONFIG["LANGFUSE_PORT"]}"
}

#===============================================================================
# DIFY CONFIGURATION
#===============================================================================

configure_dify() {
    print_section "Dify Configuration"

    # Port
    read -p "Enter Dify port [3004]: " dify_port
    CONFIG["DIFY_PORT"]="${dify_port:-3004}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Dify subdomain [dify]: " dify_subdomain
        CONFIG["DIFY_SUBDOMAIN"]="${dify_subdomain:-dify}"
        CONFIG["DIFY_URL"]="https://${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["DIFY_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["DIFY_PORT"]}"
    fi

    # Secrets
    CONFIG["DIFY_SECRET_KEY"]=$(generate_secret)

    # Database
    local db_pass=$(generate_secret)
    CREDENTIALS["DIFY_DB_PASSWORD"]=$db_pass
    CONFIG["DIFY_DB_USERNAME"]="dify"
    CONFIG["DIFY_DB_DATABASE"]="dify"

    # Redis
    local redis_pass=$(generate_secret)
    CREDENTIALS["DIFY_REDIS_PASSWORD"]=$redis_pass

    # Storage
    CONFIG["DIFY_STORAGE_TYPE"]="local"
    CONFIG["DIFY_STORAGE_PATH"]="${CONFIG["DATA_DIR"]}/dify/storage"

    # Vector store
    if [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ]; then
        CONFIG["DIFY_VECTOR_STORE"]="${CONFIG["VECTORDB_TYPE"]}"
    else
        CONFIG["DIFY_VECTOR_STORE"]="weaviate"  # Default embedded
    fi

    print_success "Dify configured: ${CONFIG["DIFY_URL"]}"
    log "INFO" "Dify configured on port ${CONFIG["DIFY_PORT"]}"
}

#===============================================================================
# LIBRECHAT CONFIGURATION
#===============================================================================

configure_librechat() {
    print_section "LibreChat Configuration"

    # Port
    read -p "Enter LibreChat port [3005]: " librechat_port
    CONFIG["LIBRECHAT_PORT"]="${librechat_port:-3005}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter LibreChat subdomain [libre]: " librechat_subdomain
        CONFIG["LIBRECHAT_SUBDOMAIN"]="${librechat_subdomain:-libre}"
        CONFIG["LIBRECHAT_URL"]="https://${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["LIBRECHAT_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["LIBRECHAT_PORT"]}"
    fi

    # Host
    CONFIG["LIBRECHAT_HOST"]="0.0.0.0"
    CONFIG["LIBRECHAT_DOMAIN"]="${CONFIG["LIBRECHAT_URL"]}"

    # MongoDB
    local mongo_pass=$(generate_secret)
    CREDENTIALS["LIBRECHAT_MONGO_PASSWORD"]=$mongo_pass
    CONFIG["LIBRECHAT_MONGO_URI"]="mongodb://librechat:${mongo_pass}@librechat-mongo:27017/LibreChat?authSource=admin"

    # Secrets
    CONFIG["LIBRECHAT_CREDS_KEY"]=$(generate_secret)
    CONFIG["LIBRECHAT_CREDS_IV"]=$(openssl rand -hex 16)
    CONFIG["LIBRECHAT_JWT_SECRET"]=$(generate_secret)
    CONFIG["LIBRECHAT_JWT_REFRESH_SECRET"]=$(generate_secret)

    # Data directory
    CONFIG["LIBRECHAT_DATA_DIR"]="${CONFIG["DATA_DIR"]}/librechat"

    # Search (if Brave is configured)
    if [ "${CONFIG["BRAVE_SEARCH_ENABLED"]}" = "true" ]; then
        CONFIG["LIBRECHAT_SEARCH_ENABLED"]="true"
    else
        CONFIG["LIBRECHAT_SEARCH_ENABLED"]="false"
    fi

    print_success "LibreChat configured: ${CONFIG["LIBRECHAT_URL"]}"
    log "INFO" "LibreChat configured on port ${CONFIG["LIBRECHAT_PORT"]}"
}

#===============================================================================
# OLLAMA CONFIGURATION
#===============================================================================

configure_ollama() {
    print_section "Ollama Configuration"

    # Port
    read -p "Enter Ollama port [11434]: " ollama_port
    CONFIG["OLLAMA_PORT"]="${ollama_port:-11434}"

    # Data directory
    CONFIG["OLLAMA_DATA_DIR"]="${CONFIG["DATA_DIR"]}/ollama"

    # GPU support
    if [ "${CONFIG["HAS_GPU"]}" = "true" ]; then
        print_info "GPU detected: ${CONFIG["GPU_NAME"]}"
        CONFIG["OLLAMA_GPU_ENABLED"]="true"

        # GPU layers
        read -p "GPU layers to use (0=CPU only, -1=auto) [-1]: " gpu_layers
        CONFIG["OLLAMA_NUM_GPU"]="${gpu_layers:--1}"
    else
        CONFIG["OLLAMA_GPU_ENABLED"]="false"
        CONFIG["OLLAMA_NUM_GPU"]="0"
        print_warning "No GPU detected - Ollama will use CPU (slower)"
    fi

    # Host
    CONFIG["OLLAMA_HOST"]="0.0.0.0:${CONFIG["OLLAMA_PORT"]}"

    # Models to pre-download
    echo ""
    print_info "Select models to pre-download (comma-separated)"
    print_info "Examples: llama3.2,mistral,codellama"
    print_info "Leave empty to skip"
    read -p "Models: " ollama_models
    CONFIG["OLLAMA_MODELS"]=$ollama_models

    print_success "Ollama configured on port ${CONFIG["OLLAMA_PORT"]}"
    log "INFO" "Ollama configured with GPU=${CONFIG["OLLAMA_GPU_ENABLED"]}"
}

#===============================================================================
# UPTIME KUMA CONFIGURATION
#===============================================================================

configure_uptime_kuma() {
    print_section "Uptime Kuma Configuration"

    # Port
    read -p "Enter Uptime Kuma port [3006]: " kuma_port
    CONFIG["UPTIME_KUMA_PORT"]="${kuma_port:-3006}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Uptime Kuma subdomain [status]: " kuma_subdomain
        CONFIG["UPTIME_KUMA_SUBDOMAIN"]="${kuma_subdomain:-status}"
        CONFIG["UPTIME_KUMA_URL"]="https://${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["UPTIME_KUMA_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["UPTIME_KUMA_PORT"]}"
    fi

    # Data directory
    CONFIG["UPTIME_KUMA_DATA_DIR"]="${CONFIG["DATA_DIR"]}/uptime-kuma"

    print_success "Uptime Kuma configured: ${CONFIG["UPTIME_KUMA_URL"]}"
    log "INFO" "Uptime Kuma configured on port ${CONFIG["UPTIME_KUMA_PORT"]}"
}

#===============================================================================
# PORTAINER CONFIGURATION
#===============================================================================

configure_portainer() {
    print_section "Portainer Configuration"

    # Port
    read -p "Enter Portainer port [9000]: " portainer_port
    CONFIG["PORTAINER_PORT"]="${portainer_port:-9000}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter Portainer subdomain [portainer]: " portainer_subdomain
        CONFIG["PORTAINER_SUBDOMAIN"]="${portainer_subdomain:-portainer}"
        CONFIG["PORTAINER_URL"]="https://${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["PORTAINER_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["PORTAINER_PORT"]}"
    fi

    # Data directory
    CONFIG["PORTAINER_DATA_DIR"]="${CONFIG["DATA_DIR"]}/portainer"

    print_success "Portainer configured: ${CONFIG["PORTAINER_URL"]}"
    log "INFO" "Portainer configured on port ${CONFIG["PORTAINER_PORT"]}"
}

#===============================================================================
# VECTOR DATABASE CONFIGURATION
#===============================================================================

configure_vectordb_service() {
    if [ "${CONFIG["INSTALL_VECTORDB"]}" != "true" ]; then
        return
    fi

    print_section "Vector Database Configuration"

    case "${CONFIG["VECTORDB_TYPE"]}" in
        qdrant)
            configure_qdrant
            ;;
        chroma)
            configure_chroma
            ;;
        weaviate)
            configure_weaviate
            ;;
    esac
}

configure_qdrant() {
    print_info "Configuring Qdrant..."

    # Port
    read -p "Enter Qdrant port [6333]: " qdrant_port
    CONFIG["QDRANT_PORT"]="${qdrant_port:-6333}"

    # GRPC port
    CONFIG["QDRANT_GRPC_PORT"]="6334"

    # Data directory
    CONFIG["QDRANT_DATA_DIR"]="${CONFIG["DATA_DIR"]}/qdrant"

    # API key
    read -p "Set Qdrant API key? (y/n): " set_api_key
    if [[ "$set_api_key" =~ ^[Yy]$ ]]; then
        local api_key=$(generate_secret)
        CREDENTIALS["QDRANT_API_KEY"]=$api_key
        CONFIG["QDRANT_API_KEY_ENABLED"]="true"
        print_success "Qdrant API key generated"
    else
        CONFIG["QDRANT_API_KEY_ENABLED"]="false"
    fi

    CONFIG["QDRANT_URL"]="http://qdrant:${CONFIG["QDRANT_PORT"]}"

    print_success "Qdrant configured on port ${CONFIG["QDRANT_PORT"]}"
}

configure_chroma() {
    print_info "Configuring Chroma..."

    # Port
    read -p "Enter Chroma port [8000]: " chroma_port
    CONFIG["CHROMA_PORT"]="${chroma_port:-8000}"

    # Data directory
    CONFIG["CHROMA_DATA_DIR"]="${CONFIG["DATA_DIR"]}/chroma"

    # Auth
    read -p "Enable Chroma authentication? (y/n): " chroma_auth
    if [[ "$chroma_auth" =~ ^[Yy]$ ]]; then
        local token=$(generate_secret)
        CREDENTIALS["CHROMA_SERVER_AUTH_CREDENTIALS"]=$token
        CONFIG["CHROMA_SERVER_AUTH_PROVIDER"]="chromadb.auth.token.TokenAuthServerProvider"
        CONFIG["CHROMA_AUTH_ENABLED"]="true"
    else
        CONFIG["CHROMA_AUTH_ENABLED"]="false"
    fi

    CONFIG["CHROMA_URL"]="http://chroma:${CONFIG["CHROMA_PORT"]}"

    print_success "Chroma configured on port ${CONFIG["CHROMA_PORT"]}"
}

configure_weaviate() {
    print_info "Configuring Weaviate..."

    # Port
    read -p "Enter Weaviate port [8080]: " weaviate_port
    CONFIG["WEAVIATE_PORT"]="${weaviate_port:-8080}"

    # Data directory
    CONFIG["WEAVIATE_DATA_DIR"]="${CONFIG["DATA_DIR"]}/weaviate"

    # Authentication
    read -p "Enable Weaviate authentication? (y/n): " weaviate_auth
    if [[ "$weaviate_auth" =~ ^[Yy]$ ]]; then
        local api_key=$(generate_secret)
        CREDENTIALS["WEAVIATE_API_KEY"]=$api_key
        CONFIG["WEAVIATE_AUTHENTICATION_APIKEY_ENABLED"]="true"
        CONFIG["WEAVIATE_AUTHENTICATION_APIKEY_ALLOWED_KEYS"]=$api_key
    else
        CONFIG["WEAVIATE_AUTHENTICATION_APIKEY_ENABLED"]="false"
    fi

    # Anonymous access
    CONFIG["WEAVIATE_AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED"]="true"

    # Persistence
    CONFIG["WEAVIATE_PERSISTENCE_DATA_PATH"]="/var/lib/weaviate"

    CONFIG["WEAVIATE_URL"]="http://weaviate:${CONFIG["WEAVIATE_PORT"]}"

    print_success "Weaviate configured on port ${CONFIG["WEAVIATE_PORT"]}"
}

#===============================================================================
# OPENCLAW CONFIGURATION (if selected)
#===============================================================================

configure_openclaw_service() {
    if [ "${CONFIG["INSTALL_OPENCLAW"]}" != "true" ]; then
        return
    fi

    print_section "OpenClaw Configuration"

    # Port
    read -p "Enter OpenClaw port [8501]: " openclaw_port
    CONFIG["OPENCLAW_PORT"]="${openclaw_port:-8501}"

    # Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Enter OpenClaw subdomain [openclaw]: " openclaw_subdomain
        CONFIG["OPENCLAW_SUBDOMAIN"]="${openclaw_subdomain:-openclaw}"
        CONFIG["OPENCLAW_URL"]="https://${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["OPENCLAW_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["OPENCLAW_PORT"]}"
    fi

    # Data directory
    CONFIG["OPENCLAW_DATA_DIR"]="${CONFIG["DATA_DIR"]}/openclaw"

    # Web search integration
    if [ "${CONFIG["BRAVE_SEARCH_ENABLED"]}" = "true" ]; then
        CONFIG["OPENCLAW_SEARCH_PROVIDER"]="brave"
        print_success "OpenClaw will use Brave Search"
    elif [ "${CONFIG["SERPER_ENABLED"]}" = "true" ]; then
        CONFIG["OPENCLAW_SEARCH_PROVIDER"]="serper"
        print_success "OpenClaw will use Serper"
    elif [ "${CONFIG["TAVILY_ENABLED"]}" = "true" ]; then
        CONFIG["OPENCLAW_SEARCH_PROVIDER"]="tavily"
        print_success "OpenClaw will use Tavily"
    else
        print_warning "No web search API configured for OpenClaw"
        CONFIG["OPENCLAW_SEARCH_PROVIDER"]="none"
    fi

    print_success "OpenClaw configured: ${CONFIG["OPENCLAW_URL"]}"
    log "INFO" "OpenClaw configured on port ${CONFIG["OPENCLAW_PORT"]}"
}
#===============================================================================
# CONFIGURATION VALIDATION
#===============================================================================

validate_configuration() {
    print_header "Configuration Validation"

    local errors=0
    local warnings=0

    # Check critical configurations
    echo ""
    print_info "Validating configuration..."
    echo ""

    # Validate ports don't conflict
    validate_ports || ((errors++))

    # Validate domain configuration
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        validate_domain_config || ((warnings++))
    fi

    # Validate LLM providers
    validate_llm_providers || ((warnings++))

    # Validate service dependencies
    validate_service_dependencies || ((errors++))

    # Validate disk space
    validate_disk_space || ((warnings++))

    # Display results
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ $errors -eq 0 ]; then
        print_success "✓ Configuration validation passed"
    else
        print_error "✗ Configuration validation failed with $errors error(s)"
        return 1
    fi

    if [ $warnings -gt 0 ]; then
        print_warning "⚠ $warnings warning(s) detected"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log "INFO" "Configuration validation completed: errors=$errors warnings=$warnings"
    return 0
}

validate_ports() {
    print_info "Checking port conflicts..."

    local ports=()
    local port_services=()

    # Collect all configured ports
    [ "${CONFIG["INSTALL_N8N"]}" = "true" ] && ports+=("${CONFIG["N8N_PORT"]}") && port_services+=("n8n")
    [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ] && ports+=("${CONFIG["FLOWISE_PORT"]}") && port_services+=("Flowise")
    [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && ports+=("${CONFIG["OPENWEBUI_PORT"]}") && port_services+=("Open WebUI")
    [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ] && ports+=("${CONFIG["ANYTHINGLLM_PORT"]}") && port_services+=("AnythingLLM")
    [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ] && ports+=("${CONFIG["LANGFUSE_PORT"]}") && port_services+=("Langfuse")
    [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] && ports+=("${CONFIG["DIFY_PORT"]}") && port_services+=("Dify")
    [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ] && ports+=("${CONFIG["LIBRECHAT_PORT"]}") && port_services+=("LibreChat")
    [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ] && ports+=("${CONFIG["OLLAMA_PORT"]}") && port_services+=("Ollama")
    [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ] && ports+=("${CONFIG["UPTIME_KUMA_PORT"]}") && port_services+=("Uptime Kuma")
    [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ] && ports+=("${CONFIG["PORTAINER_PORT"]}") && port_services+=("Portainer")
    [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ] && ports+=("${CONFIG["OPENCLAW_PORT"]}") && port_services+=("OpenClaw")

    # Check for duplicates
    local seen_ports=()
    local conflicts=0

    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local service="${port_services[$i]}"

        # Check if port already seen
        for j in "${!seen_ports[@]}"; do
            if [ "${seen_ports[$j]}" = "$port" ]; then
                print_error "Port conflict: $port used by ${port_services[$j]} and $service"
                ((conflicts++))
            fi
        done

        seen_ports+=("$port")

        # Check if port is in use
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_warning "Port $port ($service) appears to be in use"
        fi
    done

    if [ $conflicts -gt 0 ]; then
        return 1
    fi

    print_success "No port conflicts detected"
    return 0
}

validate_domain_config() {
    print_info "Validating domain configuration..."

    local warnings=0

    # Check domain is valid
    if ! [[ "${CONFIG["DOMAIN"]}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_warning "Domain format may be invalid: ${CONFIG["DOMAIN"]}"
        ((warnings++))
    fi

    # Check DNS resolution
    if ! host "${CONFIG["DOMAIN"]}" >/dev/null 2>&1; then
        print_warning "Domain ${CONFIG["DOMAIN"]} does not resolve to an IP address"
        print_warning "Ensure DNS is configured before deploying"
        ((warnings++))
    else
        local resolved_ip=$(host "${CONFIG["DOMAIN"]}" | grep "has address" | awk '{print $4}' | head -n1)
        if [ -n "$resolved_ip" ] && [ "$resolved_ip" != "${CONFIG["PUBLIC_IP"]}" ]; then
            print_warning "Domain resolves to $resolved_ip but server IP is ${CONFIG["PUBLIC_IP"]}"
            ((warnings++))
        fi
    fi

    # Warn about Cloudflare SSL mode
    if [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
        print_info "Remember to set Cloudflare SSL mode to 'Full' or 'Full (strict)'"
    fi

    return $warnings
}

validate_llm_providers() {
    print_info "Checking LLM provider configuration..."

    local configured_count=0

    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" = "true" ]; then
            ((configured_count++))
        fi
    done

    if [ $configured_count -eq 0 ]; then
        print_warning "No LLM providers configured"
        print_warning "Services like Flowise, Open WebUI, etc. will need API keys added later"
        return 1
    else
        print_success "$configured_count LLM provider(s) configured"
    fi

    return 0
}

validate_service_dependencies() {
    print_info "Checking service dependencies..."

    local errors=0

    # Check Ollama dependency for Open WebUI
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && [ "${CONFIG["OPENWEBUI_OLLAMA_ENABLED"]}" = "true" ]; then
        if [ "${CONFIG["INSTALL_OLLAMA"]}" != "true" ] && [ -z "${CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]}" ]; then
            print_error "Open WebUI requires Ollama but no Ollama installation or URL configured"
            ((errors++))
        fi
    fi

    # Check vector DB for services that need it
    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] || [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        if [ "${CONFIG["INSTALL_VECTORDB"]}" != "true" ]; then
            print_warning "Services like Dify/AnythingLLM work best with a vector database"
        fi
    fi

    return $errors
}

validate_disk_space() {
    print_info "Checking disk space..."

    local available=$(df -BG "${CONFIG["DATA_DIR"]}" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ -z "$available" ]; then
        print_warning "Could not check disk space"
        return 1
    fi

    local required=20

    # Estimate requirements
    [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ] && required=$((required + 30))
    [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ] && required=$((required + 10))

    if [ "$available" -lt "$required" ]; then
        print_warning "Low disk space: ${available}GB available, ${required}GB recommended"
        return 1
    else
        print_success "Sufficient disk space: ${available}GB available"
    fi

    return 0
}

#===============================================================================
# CONFIGURATION FILE GENERATION
#===============================================================================

generate_config_file() {
    print_header "Generating Configuration Files"

    local config_file="${SCRIPT_DIR}/config.env"
    local secrets_file="${SCRIPT_DIR}/.secrets.env"

    print_info "Writing configuration to $config_file"

    # Create config.env
    cat > "$config_file" << 'EOF'
#===============================================================================
# AI INFRASTRUCTURE CONFIGURATION
# Generated by setup script
#===============================================================================

EOF

    # Add generation timestamp
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$config_file"
    echo "" >> "$config_file"

    # System Configuration
    cat >> "$config_file" << EOF
#===============================================================================
# SYSTEM CONFIGURATION
#===============================================================================

# Server
PUBLIC_IP=${CONFIG["PUBLIC_IP"]}
TIMEZONE=${CONFIG["TIMEZONE"]}
TELEMETRY_ENABLED=${CONFIG["TELEMETRY_ENABLED"]}

# Directories
BASE_DIR=${CONFIG["BASE_DIR"]}
DATA_DIR=${CONFIG["DATA_DIR"]}
BACKUP_DIR=${CONFIG["BACKUP_DIR"]}

# Hardware
HAS_GPU=${CONFIG["HAS_GPU"]}
GPU_NAME=${CONFIG["GPU_NAME"]:-}
TOTAL_RAM=${CONFIG["TOTAL_RAM"]}
CPU_CORES=${CONFIG["CPU_CORES"]}

EOF

    # Network Configuration
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# NETWORK CONFIGURATION
#===============================================================================

# Domain
HAS_DOMAIN=true
DOMAIN=${CONFIG["DOMAIN"]}

# Cloudflare
USE_CLOUDFLARE=${CONFIG["USE_CLOUDFLARE"]:-false}

# SSL
SSL_EMAIL=${CONFIG["SSL_EMAIL"]:-}

EOF
    else
        cat >> "$config_file" << EOF
#===============================================================================
# NETWORK CONFIGURATION
#===============================================================================

HAS_DOMAIN=false

EOF
    fi

    # Service Installation Flags
    cat >> "$config_file" << EOF
#===============================================================================
# SERVICE INSTALLATION FLAGS
#===============================================================================

INSTALL_N8N=${CONFIG["INSTALL_N8N"]:-false}
INSTALL_FLOWISE=${CONFIG["INSTALL_FLOWISE"]:-false}
INSTALL_OPENWEBUI=${CONFIG["INSTALL_OPENWEBUI"]:-false}
INSTALL_ANYTHINGLLM=${CONFIG["INSTALL_ANYTHINGLLM"]:-false}
INSTALL_LANGFUSE=${CONFIG["INSTALL_LANGFUSE"]:-false}
INSTALL_DIFY=${CONFIG["INSTALL_DIFY"]:-false}
INSTALL_LIBRECHAT=${CONFIG["INSTALL_LIBRECHAT"]:-false}
INSTALL_OLLAMA=${CONFIG["INSTALL_OLLAMA"]:-false}
INSTALL_UPTIME_KUMA=${CONFIG["INSTALL_UPTIME_KUMA"]:-false}
INSTALL_PORTAINER=${CONFIG["INSTALL_PORTAINER"]:-false}
INSTALL_COMFYUI=${CONFIG["INSTALL_COMFYUI"]:-false}
INSTALL_SIGNAL=${CONFIG["INSTALL_SIGNAL"]:-false}
INSTALL_OPENCLAW=${CONFIG["INSTALL_OPENCLAW"]:-false}
INSTALL_VECTORDB=${CONFIG["INSTALL_VECTORDB"]:-false}

# Vector Database
VECTORDB_TYPE=${CONFIG["VECTORDB_TYPE"]:-}

EOF

    # Write service-specific configurations
    write_service_configs "$config_file"

    # Create secrets file
    generate_secrets_file "$secrets_file"

    # Set permissions
    chmod 600 "$secrets_file"
    chmod 644 "$config_file"

    print_success "Configuration files generated"
    print_info "Config: $config_file"
    print_info "Secrets: $secrets_file"

    log "INFO" "Configuration files generated successfully"
}

write_service_configs() {
    local config_file="$1"

    # n8n
    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# N8N CONFIGURATION
#===============================================================================

N8N_PORT=${CONFIG["N8N_PORT"]}
N8N_URL=${CONFIG["N8N_URL"]}
N8N_SUBDOMAIN=${CONFIG["N8N_SUBDOMAIN"]:-}
N8N_ENCRYPTION_KEY=${CONFIG["N8N_ENCRYPTION_KEY"]}
N8N_BASIC_AUTH_ACTIVE=${CONFIG["N8N_BASIC_AUTH_ACTIVE"]:-false}
N8N_TIMEZONE=${CONFIG["N8N_TIMEZONE"]}

EOF
    fi

    # Flowise
    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# FLOWISE CONFIGURATION
#===============================================================================

FLOWISE_PORT=${CONFIG["FLOWISE_PORT"]}
FLOWISE_URL=${CONFIG["FLOWISE_URL"]}
FLOWISE_SUBDOMAIN=${CONFIG["FLOWISE_SUBDOMAIN"]:-}
FLOWISE_USERNAME=${CONFIG["FLOWISE_USERNAME"]}
FLOWISE_DATABASE_PATH=${CONFIG["FLOWISE_DATABASE_PATH"]}
FLOWISE_SECRETKEY_OVERWRITE=${CONFIG["FLOWISE_SECRETKEY_OVERWRITE"]}

EOF
    fi

    # Open WebUI
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# OPEN WEBUI CONFIGURATION
#===============================================================================

OPENWEBUI_PORT=${CONFIG["OPENWEBUI_PORT"]}
OPENWEBUI_URL=${CONFIG["OPENWEBUI_URL"]}
OPENWEBUI_SUBDOMAIN=${CONFIG["OPENWEBUI_SUBDOMAIN"]:-}
OPENWEBUI_DATA_DIR=${CONFIG["OPENWEBUI_DATA_DIR"]}
OPENWEBUI_OLLAMA_ENABLED=${CONFIG["OPENWEBUI_OLLAMA_ENABLED"]:-false}
OPENWEBUI_OLLAMA_BASE_URL=${CONFIG["OPENWEBUI_OLLAMA_BASE_URL"]:-}
OPENWEBUI_WEBSERVER_SECRET=${CONFIG["OPENWEBUI_WEBSERVER_SECRET"]}

EOF
    fi

    # AnythingLLM
    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# ANYTHINGLLM CONFIGURATION
#===============================================================================

ANYTHINGLLM_PORT=${CONFIG["ANYTHINGLLM_PORT"]}
ANYTHINGLLM_URL=${CONFIG["ANYTHINGLLM_URL"]}
ANYTHINGLLM_SUBDOMAIN=${CONFIG["ANYTHINGLLM_SUBDOMAIN"]:-}
ANYTHINGLLM_STORAGE_DIR=${CONFIG["ANYTHINGLLM_STORAGE_DIR"]}
ANYTHINGLLM_AUTH_TOKEN=${CONFIG["ANYTHINGLLM_AUTH_TOKEN"]}
ANYTHINGLLM_JWT_SECRET=${CONFIG["ANYTHINGLLM_JWT_SECRET"]}

EOF
    fi

    # Langfuse
    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# LANGFUSE CONFIGURATION
#===============================================================================

LANGFUSE_PORT=${CONFIG["LANGFUSE_PORT"]}
LANGFUSE_URL=${CONFIG["LANGFUSE_URL"]}
LANGFUSE_SUBDOMAIN=${CONFIG["LANGFUSE_SUBDOMAIN"]:-}
LANGFUSE_DATABASE_URL=${CONFIG["LANGFUSE_DATABASE_URL"]}
LANGFUSE_SALT=${CONFIG["LANGFUSE_SALT"]}
LANGFUSE_NEXTAUTH_SECRET=${CONFIG["LANGFUSE_NEXTAUTH_SECRET"]}
LANGFUSE_NEXTAUTH_URL=${CONFIG["LANGFUSE_NEXTAUTH_URL"]}
LANGFUSE_TELEMETRY_ENABLED=${CONFIG["LANGFUSE_TELEMETRY_ENABLED"]}

EOF
    fi

    # Dify
    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# DIFY CONFIGURATION
#===============================================================================

DIFY_PORT=${CONFIG["DIFY_PORT"]}
DIFY_URL=${CONFIG["DIFY_URL"]}
DIFY_SUBDOMAIN=${CONFIG["DIFY_SUBDOMAIN"]:-}
DIFY_SECRET_KEY=${CONFIG["DIFY_SECRET_KEY"]}
DIFY_DB_USERNAME=${CONFIG["DIFY_DB_USERNAME"]}
DIFY_DB_DATABASE=${CONFIG["DIFY_DB_DATABASE"]}
DIFY_STORAGE_TYPE=${CONFIG["DIFY_STORAGE_TYPE"]}
DIFY_STORAGE_PATH=${CONFIG["DIFY_STORAGE_PATH"]}
DIFY_VECTOR_STORE=${CONFIG["DIFY_VECTOR_STORE"]}

EOF
    fi

    # LibreChat
    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# LIBRECHAT CONFIGURATION
#===============================================================================

LIBRECHAT_PORT=${CONFIG["LIBRECHAT_PORT"]}
LIBRECHAT_URL=${CONFIG["LIBRECHAT_URL"]}
LIBRECHAT_SUBDOMAIN=${CONFIG["LIBRECHAT_SUBDOMAIN"]:-}
LIBRECHAT_HOST=${CONFIG["LIBRECHAT_HOST"]}
LIBRECHAT_DOMAIN=${CONFIG["LIBRECHAT_DOMAIN"]}
LIBRECHAT_MONGO_URI=${CONFIG["LIBRECHAT_MONGO_URI"]}
LIBRECHAT_CREDS_KEY=${CONFIG["LIBRECHAT_CREDS_KEY"]}
LIBRECHAT_CREDS_IV=${CONFIG["LIBRECHAT_CREDS_IV"]}
LIBRECHAT_JWT_SECRET=${CONFIG["LIBRECHAT_JWT_SECRET"]}
LIBRECHAT_JWT_REFRESH_SECRET=${CONFIG["LIBRECHAT_JWT_REFRESH_SECRET"]}
LIBRECHAT_DATA_DIR=${CONFIG["LIBRECHAT_DATA_DIR"]}
LIBRECHAT_SEARCH_ENABLED=${CONFIG["LIBRECHAT_SEARCH_ENABLED"]:-false}

EOF
    fi

    # Ollama
    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# OLLAMA CONFIGURATION
#===============================================================================

OLLAMA_PORT=${CONFIG["OLLAMA_PORT"]}
OLLAMA_HOST=${CONFIG["OLLAMA_HOST"]}
OLLAMA_DATA_DIR=${CONFIG["OLLAMA_DATA_DIR"]}
OLLAMA_GPU_ENABLED=${CONFIG["OLLAMA_GPU_ENABLED"]}
OLLAMA_NUM_GPU=${CONFIG["OLLAMA_NUM_GPU"]}
OLLAMA_MODELS=${CONFIG["OLLAMA_MODELS"]:-}

EOF
    fi

    # Uptime Kuma
    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# UPTIME KUMA CONFIGURATION
#===============================================================================

UPTIME_KUMA_PORT=${CONFIG["UPTIME_KUMA_PORT"]}
UPTIME_KUMA_URL=${CONFIG["UPTIME_KUMA_URL"]}
UPTIME_KUMA_SUBDOMAIN=${CONFIG["UPTIME_KUMA_SUBDOMAIN"]:-}
UPTIME_KUMA_DATA_DIR=${CONFIG["UPTIME_KUMA_DATA_DIR"]}

EOF
    fi

    # Portainer
    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# PORTAINER CONFIGURATION
#===============================================================================

PORTAINER_PORT=${CONFIG["PORTAINER_PORT"]}
PORTAINER_URL=${CONFIG["PORTAINER_URL"]}
PORTAINER_SUBDOMAIN=${CONFIG["PORTAINER_SUBDOMAIN"]:-}
PORTAINER_DATA_DIR=${CONFIG["PORTAINER_DATA_DIR"]}

EOF
    fi

    # Vector Database
    if [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ]; then
        case "${CONFIG["VECTORDB_TYPE"]}" in
            qdrant)
                cat >> "$config_file" << EOF
#===============================================================================
# QDRANT CONFIGURATION
#===============================================================================

QDRANT_PORT=${CONFIG["QDRANT_PORT"]}
QDRANT_GRPC_PORT=${CONFIG["QDRANT_GRPC_PORT"]}
QDRANT_DATA_DIR=${CONFIG["QDRANT_DATA_DIR"]}
QDRANT_URL=${CONFIG["QDRANT_URL"]}
QDRANT_API_KEY_ENABLED=${CONFIG["QDRANT_API_KEY_ENABLED"]:-false}

EOF
                ;;
            chroma)
                cat >> "$config_file" << EOF
#===============================================================================
# CHROMA CONFIGURATION
#===============================================================================

CHROMA_PORT=${CONFIG["CHROMA_PORT"]}
CHROMA_DATA_DIR=${CONFIG["CHROMA_DATA_DIR"]}
CHROMA_URL=${CONFIG["CHROMA_URL"]}
CHROMA_AUTH_ENABLED=${CONFIG["CHROMA_AUTH_ENABLED"]:-false}
CHROMA_SERVER_AUTH_PROVIDER=${CONFIG["CHROMA_SERVER_AUTH_PROVIDER"]:-}

EOF
                ;;
            weaviate)
                cat >> "$config_file" << EOF
#===============================================================================
# WEAVIATE CONFIGURATION
#===============================================================================

WEAVIATE_PORT=${CONFIG["WEAVIATE_PORT"]}
WEAVIATE_DATA_DIR=${CONFIG["WEAVIATE_DATA_DIR"]}
WEAVIATE_URL=${CONFIG["WEAVIATE_URL"]}
WEAVIATE_AUTHENTICATION_APIKEY_ENABLED=${CONFIG["WEAVIATE_AUTHENTICATION_APIKEY_ENABLED"]:-false}
WEAVIATE_AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=${CONFIG["WEAVIATE_AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED"]:-true}
WEAVIATE_PERSISTENCE_DATA_PATH=${CONFIG["WEAVIATE_PERSISTENCE_DATA_PATH"]}

EOF
                ;;
        esac
    fi

    # OpenClaw
    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        cat >> "$config_file" << EOF
#===============================================================================
# OPENCLAW CONFIGURATION
#===============================================================================

OPENCLAW_PORT=${CONFIG["OPENCLAW_PORT"]}
OPENCLAW_URL=${CONFIG["OPENCLAW_URL"]}
OPENCLAW_SUBDOMAIN=${CONFIG["OPENCLAW_SUBDOMAIN"]:-}
OPENCLAW_DATA_DIR=${CONFIG["OPENCLAW_DATA_DIR"]}
OPENCLAW_SEARCH_PROVIDER=${CONFIG["OPENCLAW_SEARCH_PROVIDER"]:-none}

EOF
    fi

    # LLM Provider Status
    cat >> "$config_file" << EOF
#===============================================================================
# LLM PROVIDER STATUS
#===============================================================================

OPENAI_CONFIGURED=${LLM_PROVIDERS["OPENAI"]:-false}
ANTHROPIC_CONFIGURED=${LLM_PROVIDERS["ANTHROPIC"]:-false}
GROQ_CONFIGURED=${LLM_PROVIDERS["GROQ"]:-false}
MISTRAL_CONFIGURED=${LLM_PROVIDERS["MISTRAL"]:-false}
COHERE_CONFIGURED=${LLM_PROVIDERS["COHERE"]:-false}
TOGETHER_CONFIGURED=${LLM_PROVIDERS["TOGETHER"]:-false}
PERPLEXITY_CONFIGURED=${LLM_PROVIDERS["PERPLEXITY"]:-false}
OPENROUTER_CONFIGURED=${LLM_PROVIDERS["OPENROUTER"]:-false}
GOOGLE_AI_CONFIGURED=${LLM_PROVIDERS["GOOGLE"]:-false}
XAI_CONFIGURED=${LLM_PROVIDERS["XAI"]:-false}
HUGGINGFACE_CONFIGURED=${LLM_PROVIDERS["HUGGINGFACE"]:-false}

# Search APIs
BRAVE_SEARCH_ENABLED=${CONFIG["BRAVE_SEARCH_ENABLED"]:-false}
SERPER_ENABLED=${CONFIG["SERPER_ENABLED"]:-false}
TAVILY_ENABLED=${CONFIG["TAVILY_ENABLED"]:-false}
JINA_ENABLED=${CONFIG["JINA_ENABLED"]:-false}
FIRECRAWL_ENABLED=${CONFIG["FIRECRAWL_ENABLED"]:-false}

EOF
}

generate_secrets_file() {
    local secrets_file="$1"

    print_info "Writing secrets to $secrets_file"

    cat > "$secrets_file" << 'EOF'
#===============================================================================
# SENSITIVE CREDENTIALS
# THIS FILE CONTAINS SECRETS - KEEP SECURE!
# Generated by setup script
#===============================================================================

EOF

    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$secrets_file"
    echo "" >> "$secrets_file"

    # Write all credentials
    for key in "${!CREDENTIALS[@]}"; do
        echo "${key}=${CREDENTIALS[$key]}" >> "$secrets_file"
    done

    print_success "Secrets file created (permissions: 600)"
    log "INFO" "Secrets file generated"
}
#===============================================================================
# CONFIGURATION SUMMARY
#===============================================================================

display_configuration_summary() {
    print_header "Configuration Summary"

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        INSTALLATION SUMMARY                                ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # System Information
    print_section "System Information"
    echo "  Public IP:           ${CONFIG["PUBLIC_IP"]}"
    echo "  Timezone:            ${CONFIG["TIMEZONE"]}"
    echo "  Data Directory:      ${CONFIG["DATA_DIR"]}"
    echo "  Backup Directory:    ${CONFIG["BACKUP_DIR"]}"
    echo "  GPU Available:       ${CONFIG["HAS_GPU"]}"
    [ "${CONFIG["HAS_GPU"]}" = "true" ] && echo "  GPU Model:           ${CONFIG["GPU_NAME"]}"
    echo "  Total RAM:           ${CONFIG["TOTAL_RAM"]}GB"
    echo "  CPU Cores:           ${CONFIG["CPU_CORES"]}"
    echo ""

    # Network Configuration
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        print_section "Network Configuration"
        echo "  Domain:              ${CONFIG["DOMAIN"]}"
        echo "  SSL Email:           ${CONFIG["SSL_EMAIL"]}"
        echo "  Using Cloudflare:    ${CONFIG["USE_CLOUDFLARE"]:-false}"
        echo ""
    fi

    # Services to Install
    print_section "Services to Install"
    local service_count=0

    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        echo "  ✓ n8n"
        echo "    URL: ${CONFIG["N8N_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        echo "  ✓ Flowise"
        echo "    URL: ${CONFIG["FLOWISE_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        echo "  ✓ Open WebUI"
        echo "    URL: ${CONFIG["OPENWEBUI_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        echo "  ✓ AnythingLLM"
        echo "    URL: ${CONFIG["ANYTHINGLLM_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        echo "  ✓ Langfuse"
        echo "    URL: ${CONFIG["LANGFUSE_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        echo "  ✓ Dify"
        echo "    URL: ${CONFIG["DIFY_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        echo "  ✓ LibreChat"
        echo "    URL: ${CONFIG["LIBRECHAT_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        echo "  ✓ Ollama"
        echo "    URL: ${CONFIG["OLLAMA_HOST"]}"
        [ -n "${CONFIG["OLLAMA_MODELS"]}" ] && echo "    Models: ${CONFIG["OLLAMA_MODELS"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        echo "  ✓ Uptime Kuma"
        echo "    URL: ${CONFIG["UPTIME_KUMA_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        echo "  ✓ Portainer"
        echo "    URL: ${CONFIG["PORTAINER_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ]; then
        echo "  ✓ ComfyUI"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_SIGNAL"]}" = "true" ]; then
        echo "  ✓ Signal Bridge"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        echo "  ✓ OpenClaw"
        echo "    URL: ${CONFIG["OPENCLAW_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ]; then
        echo "  ✓ Vector Database: ${CONFIG["VECTORDB_TYPE"]}"
        ((service_count++))
    fi

    echo ""
    echo "  Total Services: $service_count"
    echo ""

    # LLM Providers
    print_section "Configured LLM Providers"
    local provider_count=0

    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" = "true" ]; then
            echo "  ✓ $provider"
            ((provider_count++))
        fi
    done

    if [ $provider_count -eq 0 ]; then
        echo "  ⚠ No LLM providers configured"
    else
        echo ""
        echo "  Total Providers: $provider_count"
    fi
    echo ""

    # Additional APIs
    local api_configured=false

    if [ "${CONFIG["BRAVE_SEARCH_ENABLED"]}" = "true" ] || \
       [ "${CONFIG["SERPER_ENABLED"]}" = "true" ] || \
       [ "${CONFIG["TAVILY_ENABLED"]}" = "true" ] || \
       [ "${CONFIG["JINA_ENABLED"]}" = "true" ] || \
       [ "${CONFIG["FIRECRAWL_ENABLED"]}" = "true" ]; then

        print_section "Additional APIs"

        [ "${CONFIG["BRAVE_SEARCH_ENABLED"]}" = "true" ] && echo "  ✓ Brave Search" && api_configured=true
        [ "${CONFIG["SERPER_ENABLED"]}" = "true" ] && echo "  ✓ Serper" && api_configured=true
        [ "${CONFIG["TAVILY_ENABLED"]}" = "true" ] && echo "  ✓ Tavily" && api_configured=true
        [ "${CONFIG["JINA_ENABLED"]}" = "true" ] && echo "  ✓ Jina Reader" && api_configured=true
        [ "${CONFIG["FIRECRAWL_ENABLED"]}" = "true" ] && echo "  ✓ Firecrawl" && api_configured=true

        echo ""
    fi

    # Configuration Files
    print_section "Configuration Files"
    echo "  Config:              ${SCRIPT_DIR}/config.env"
    echo "  Secrets:             ${SCRIPT_DIR}/.secrets.env"
    echo "  Log:                 $LOG_FILE"
    echo ""

    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        READY TO PROCEED                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    log "INFO" "Configuration summary displayed"
}

#===============================================================================
# CONFIRMATION & FINAL CHECKS
#===============================================================================

confirm_installation() {
    echo ""
    print_warning "Please review the configuration above carefully."
    echo ""

    read -p "Proceed with installation? (yes/no): " confirm

    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Installation cancelled by user"
        log "INFO" "Installation cancelled by user"
        exit 0
    fi

    echo ""
    print_success "Installation confirmed!"
    log "INFO" "User confirmed installation"

    # Final warning for production
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        echo ""
        print_warning "⚠ IMPORTANT: Before proceeding, ensure:"
        echo "  1. DNS records point to this server (${CONFIG["PUBLIC_IP"]})"
        echo "  2. Ports 80 and 443 are open in firewall"
        if [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
            echo "  3. Cloudflare SSL mode is set to 'Full' or 'Full (strict)'"
        fi
        echo ""

        read -p "DNS and firewall configured? (yes/no): " dns_confirm

        if [[ ! "$dns_confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
            print_warning "Please configure DNS and firewall, then run the script again"
            log "INFO" "Installation paused for DNS/firewall configuration"
            exit 0
        fi
    fi

    echo ""
    print_info "Starting installation in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

#===============================================================================
# SAVE CONFIGURATION STATE
#===============================================================================

save_configuration_state() {
    local state_file="${SCRIPT_DIR}/.setup_state.json"

    print_info "Saving configuration state..."

    # Create JSON state file
    cat > "$state_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "setup_version": "$SCRIPT_VERSION",
  "status": "configured",
  "system": {
    "public_ip": "${CONFIG["PUBLIC_IP"]}",
    "has_gpu": ${CONFIG["HAS_GPU"]},
    "total_ram": ${CONFIG["TOTAL_RAM"]},
    "cpu_cores": ${CONFIG["CPU_CORES"]}
  },
  "services": {
    "n8n": ${CONFIG["INSTALL_N8N"]:-false},
    "flowise": ${CONFIG["INSTALL_FLOWISE"]:-false},
    "openwebui": ${CONFIG["INSTALL_OPENWEBUI"]:-false},
    "anythingllm": ${CONFIG["INSTALL_ANYTHINGLLM"]:-false},
    "langfuse": ${CONFIG["INSTALL_LANGFUSE"]:-false},
    "dify": ${CONFIG["INSTALL_DIFY"]:-false},
    "librechat": ${CONFIG["INSTALL_LIBRECHAT"]:-false},
    "ollama": ${CONFIG["INSTALL_OLLAMA"]:-false},
    "uptime_kuma": ${CONFIG["INSTALL_UPTIME_KUMA"]:-false},
    "portainer": ${CONFIG["INSTALL_PORTAINER"]:-false},
    "comfyui": ${CONFIG["INSTALL_COMFYUI"]:-false},
    "signal": ${CONFIG["INSTALL_SIGNAL"]:-false},
    "openclaw": ${CONFIG["INSTALL_OPENCLAW"]:-false},
    "vectordb": ${CONFIG["INSTALL_VECTORDB"]:-false}
  },
  "llm_providers": {
    "openai": ${LLM_PROVIDERS["OPENAI"]:-false},
    "anthropic": ${LLM_PROVIDERS["ANTHROPIC"]:-false},
    "groq": ${LLM_PROVIDERS["GROQ"]:-false},
    "mistral": ${LLM_PROVIDERS["MISTRAL"]:-false},
    "cohere": ${LLM_PROVIDERS["COHERE"]:-false},
    "together": ${LLM_PROVIDERS["TOGETHER"]:-false},
    "perplexity": ${LLM_PROVIDERS["PERPLEXITY"]:-false},
    "openrouter": ${LLM_PROVIDERS["OPENROUTER"]:-false},
    "google": ${LLM_PROVIDERS["GOOGLE"]:-false},
    "xai": ${LLM_PROVIDERS["XAI"]:-false},
    "huggingface": ${LLM_PROVIDERS["HUGGINGFACE"]:-false}
  }
}
EOF

    chmod 644 "$state_file"
    print_success "Configuration state saved"
    log "INFO" "Configuration state saved to $state_file"
}

#===============================================================================
# MAIN CONFIGURATION FLOW
#===============================================================================

run_interactive_setup() {
    print_header "AI Infrastructure Interactive Setup"

    echo ""
    echo "This wizard will guide you through configuring your AI infrastructure."
    echo "Press Ctrl+C at any time to cancel."
    echo ""

    sleep 2

    # Step 1: System Detection
    detect_system_info

    # Step 2: Network Configuration
    configure_network

    # Step 3: Service Selection
    select_services

    # Step 4: Service Configuration
    configure_selected_services

    # Step 5: LLM Providers
    configure_llm_providers

    # Step 6: Validate Configuration
    if ! validate_configuration; then
        print_error "Configuration validation failed"
        echo ""
        read -p "Continue anyway? (yes/no): " force_continue
        if [[ ! "$force_continue" =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Setup cancelled"
            exit 1
        fi
    fi

    # Step 7: Generate Configuration Files
    generate_config_file

    # Step 8: Display Summary
    display_configuration_summary

    # Step 9: Confirm Installation
    confirm_installation

    # Step 10: Save State
    save_configuration_state

    print_success "Configuration complete!"
    log "INFO" "Interactive setup completed successfully"
}

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

# Generate random secrets
generate_secret() {
    openssl rand -hex 32
}

# Generate JWT secret
generate_jwt_secret() {
    openssl rand -base64 32
}

# Generate encryption key
generate_encryption_key() {
    openssl rand -hex 16
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if port is available
is_port_available() {
    local port=$1
    ! netstat -tuln 2>/dev/null | grep -q ":$port "
}

# Validate email format
is_valid_email() {
    local email=$1
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# Validate domain format
is_valid_domain() {
    local domain=$1
    [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]
}

# Get free disk space in GB
get_free_disk_space() {
    local path=$1
    df -BG "$path" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//'
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$((bytes / 1073741824))GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$((bytes / 1048576))MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

# Cleanup on error
cleanup_on_error() {
    print_error "Setup interrupted or failed"
    log "ERROR" "Setup interrupted: $1"

    echo ""
    print_info "Cleaning up..."

    # Remove incomplete configuration files
    rm -f "${SCRIPT_DIR}/config.env.incomplete"
    rm -f "${SCRIPT_DIR}/.secrets.env.incomplete"

    echo ""
    print_info "You can run the setup script again to restart configuration"

    exit 1
}

# Trap errors
trap 'cleanup_on_error "Line $LINENO"' ERR
trap 'cleanup_on_error "User interrupt"' INT TERM

#===============================================================================
# USAGE INFORMATION
#===============================================================================

show_usage() {
    cat << EOF
╔════════════════════════════════════════════════════════════════════════════╗
║                    AI Infrastructure Setup Script                          ║
║                           Version $SCRIPT_VERSION                                   ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show script version
    -c, --config FILE       Load configuration from file
    -s, --silent            Run in non-interactive mode (requires config file)
    -d, --dry-run           Validate configuration without installing
    --skip-validation       Skip configuration validation
    --log-level LEVEL       Set log level (DEBUG, INFO, WARN, ERROR)

EXAMPLES:
    # Interactive setup (recommended for first-time users)
    $0

    # Load existing configuration
    $0 --config /path/to/config.env

    # Dry run to test configuration
    $0 --config /path/to/config.env --dry-run

    # Silent installation from config file
    $0 --config /path/to/config.env --silent

CONFIGURATION:
    This script will create:
    - config.env          : Main configuration file
    - .secrets.env        : Sensitive credentials (keep secure!)
    - .setup_state.json   : Setup state and metadata
    - setup.log           : Detailed setup log

SUPPORT:
    For issues and documentation, visit:
    https://github.com/yourusername/ai-infrastructure

EOF
}

show_version() {
    echo "AI Infrastructure Setup Script v$SCRIPT_VERSION"
    echo "Last updated: 2024-01-09"
}

#===============================================================================
# PARSE COMMAND LINE ARGUMENTS
#===============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--silent)
                SILENT_MODE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# MAIN SCRIPT ENTRY POINT
#===============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should NOT be run as root"
        print_info "Please run as a regular user with sudo privileges"
        exit 1
    fi

    # Check for sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        print_info "Please run: sudo -v"
        exit 1
    fi

    # Initialize logging
    initialize_logging

    log "INFO" "=== AI Infrastructure Setup Started ==="
    log "INFO" "Script version: $SCRIPT_VERSION"
    log "INFO" "Run by user: $USER"
    log "INFO" "Working directory: $SCRIPT_DIR"

    # Check prerequisites
    check_prerequisites

    # Load existing configuration if provided
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        print_info "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
        log "INFO" "Configuration loaded from $CONFIG_FILE"

        if [ "$SILENT_MODE" = true ]; then
            print_info "Running in silent mode..."
            # Skip to installation (handled by deploy.sh)
            print_success "Configuration loaded successfully"
            exit 0
        fi
    fi

    # Run interactive setup
    if [ "$SILENT_MODE" != true ]; then
        run_interactive_setup
    fi

    # Dry run exit
    if [ "$DRY_RUN" = true ]; then
        print_success "Dry run completed - configuration is valid"
        exit 0
    fi

    # Final message
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                   CONFIGURATION COMPLETE                                   ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    print_success "Setup configuration completed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Review the configuration files:"
    echo "     - ${SCRIPT_DIR}/config.env"
    echo "     - ${SCRIPT_DIR}/.secrets.env"
    echo ""
    echo "  2. Run the deployment script:"
    echo "     ./deploy.sh"
    echo ""
    print_warning "Keep .secrets.env secure - it contains sensitive credentials!"
    echo ""

    log "INFO" "=== AI Infrastructure Setup Completed Successfully ==="
}

#===============================================================================
# RUN MAIN FUNCTION
#===============================================================================

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
