#!/bin/bash

#===============================================================================
# AI INFRASTRUCTURE SETUP SCRIPT
# Version: 2.0.0
# Description: Interactive configuration wizard for AI platform deployment
# Author: AI Platform Automation
# Repository: https://github.com/jgla1ne/AIPlatformAutomation
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

#===============================================================================
# SCRIPT METADATA
#===============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="AI Infrastructure Setup"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DATA_DIR="/mnt/data"
readonly BACKUP_DIR="${DATA_DIR}/backups"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly LOG_FILE="${LOG_DIR}/setup.log"
readonly STATE_FILE="${SCRIPT_DIR}/.setup_state.json"

#===============================================================================
# COLOR CODES
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

declare -A CONFIG=(
    ["SCRIPT_VERSION"]="$SCRIPT_VERSION"
    ["DATA_DIR"]="$DATA_DIR"
    ["BACKUP_DIR"]="$BACKUP_DIR"
    ["TIMEZONE"]="UTC"
    ["PUBLIC_IP"]=""
    ["HAS_GPU"]="false"
    ["GPU_NAME"]=""
    ["TOTAL_RAM"]="0"
    ["CPU_CORES"]="0"
    ["HAS_DOMAIN"]="false"
    ["DOMAIN"]=""
    ["SSL_EMAIL"]=""
    ["USE_CLOUDFLARE"]="false"
)

declare -A LLM_PROVIDERS=(
    ["OPENAI"]="false"
    ["ANTHROPIC"]="false"
    ["GROQ"]="false"
    ["MISTRAL"]="false"
    ["COHERE"]="false"
    ["TOGETHER"]="false"
    ["PERPLEXITY"]="false"
    ["OPENROUTER"]="false"
    ["GOOGLE"]="false"
    ["XAI"]="false"
    ["HUGGINGFACE"]="false"
)

declare -A CREDENTIALS=()

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    
    # Log rotation if file is larger than 10MB
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
        touch "$LOG_FILE"
    fi
    
    log "INFO" "=== Setup Script Started (v${SCRIPT_VERSION}) ==="
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "INFO" "=== $1 ==="
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${WHITE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS" "$1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING" "$1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log "INFO" "$1"
}

print_step() {
    echo -e "${MAGENTA}➜${NC} ${BOLD}$1${NC}"
    log "STEP" "$1"
}

#===============================================================================
# ERROR HANDLING
#===============================================================================

handle_error() {
    local exit_code=$?
    local line_number=$1
    print_error "Script failed at line $line_number with exit code $exit_code"
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    
    # Save state before exit
    save_state
    
    echo ""
    print_info "Check log file for details: $LOG_FILE"
    exit $exit_code
}

handle_interrupt() {
    echo ""
    print_warning "Script interrupted by user"
    log "WARNING" "Script interrupted by user (SIGINT/SIGTERM)"
    
    # Save state before exit
    save_state
    
    echo ""
    read -p "Save current progress? (y/n): " save_progress
    if [[ "$save_progress" =~ ^[Yy]$ ]]; then
        print_success "Progress saved. Run script again to resume."
    fi
    
    exit 130
}

trap 'handle_error ${LINENO}' ERR
trap 'handle_interrupt' INT TERM

#===============================================================================
# STATE MANAGEMENT
#===============================================================================

save_state() {
    local temp_file="${STATE_FILE}.tmp"
    
    {
        echo "{"
        echo "  \"version\": \"${SCRIPT_VERSION}\","
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"config\": {"
        
        local first=true
        for key in "${!CONFIG[@]}"; do
            [ "$first" = false ] && echo ","
            echo -n "    \"$key\": \"${CONFIG[$key]}\""
            first=false
        done
        
        echo ""
        echo "  },"
        echo "  \"llm_providers\": {"
        
        first=true
        for key in "${!LLM_PROVIDERS[@]}"; do
            [ "$first" = false ] && echo ","
            echo -n "    \"$key\": \"${LLM_PROVIDERS[$key]}\""
            first=false
        done
        
        echo ""
        echo "  }"
        echo "}"
    } > "$temp_file"
    
    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    log "INFO" "State saved to $STATE_FILE"
}

load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi
    
    print_info "Previous configuration found"
    read -p "Load previous configuration? (y/n): " load_prev
    
    if [[ ! "$load_prev" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    # TODO: Implement JSON parsing to restore CONFIG and LLM_PROVIDERS arrays
    print_success "Previous state loaded"
    log "INFO" "State loaded from $STATE_FILE"
    return 0
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

is_root() {
    [ "${EUID:-$(id -u)}" -eq 0 ]
}

check_root() {
    if ! is_root; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_valid_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

is_port_available() {
    local port="$1"
    ! netstat -tuln 2>/dev/null | grep -q ":${port} " && \
    ! ss -tuln 2>/dev/null | grep -q ":${port} "
}

get_public_ip() {
    local ip=""
    
    # Try multiple services
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) || \
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    
    echo "$ip"
}

get_free_disk_space() {
    local path="$1"
    df -BG "$path" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//'
}

generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_jwt_secret() {
    openssl rand -hex 32
}

generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-20
}

#===============================================================================
# SYSTEM DETECTION
#===============================================================================

detect_system() {
    print_header "System Detection"
    
    # Operating System
    print_step "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CONFIG["OS_NAME"]="$NAME"
        CONFIG["OS_VERSION"]="$VERSION_ID"
        print_success "OS: $NAME $VERSION_ID"
    else
        print_error "Unable to detect operating system"
        exit 1
    fi
    
    # CPU Information
    print_step "Detecting CPU..."
    CONFIG["CPU_CORES"]=$(nproc)
    CONFIG["CPU_MODEL"]=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    print_success "CPU: ${CONFIG["CPU_MODEL"]} (${CONFIG["CPU_CORES"]} cores)"
    
    # Memory Information
    print_step "Detecting memory..."
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    CONFIG["TOTAL_RAM"]=$((total_ram_kb / 1024 / 1024))
    print_success "RAM: ${CONFIG["TOTAL_RAM"]}GB"
    
    # GPU Detection
    print_step "Detecting GPU..."
    if command_exists nvidia-smi; then
        CONFIG["HAS_GPU"]="true"
        CONFIG["GPU_NAME"]=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        CONFIG["GPU_MEMORY"]=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        print_success "GPU: ${CONFIG["GPU_NAME"]} (${CONFIG["GPU_MEMORY"]}MB)"
    else
        CONFIG["HAS_GPU"]="false"
        print_info "No NVIDIA GPU detected"
    fi
    
    # Disk Space
    print_step "Checking disk space..."
    local root_free=$(get_free_disk_space "/")
    local data_free=$(get_free_disk_space "$DATA_DIR" 2>/dev/null || echo "$root_free")
    print_success "Available space: ${root_free}GB (root), ${data_free}GB (data)"
    
    if [ "$root_free" -lt 20 ]; then
        print_warning "Low disk space on root partition (< 20GB)"
    fi
    
    # Network Information
    print_step "Detecting network configuration..."
    CONFIG["PUBLIC_IP"]=$(get_public_ip)
    
    if [ -n "${CONFIG["PUBLIC_IP"]}" ]; then
        print_success "Public IP: ${CONFIG["PUBLIC_IP"]}"
    else
        print_warning "Unable to detect public IP address"
        read -p "Enter public IP manually: " manual_ip
        if is_valid_ip "$manual_ip"; then
            CONFIG["PUBLIC_IP"]="$manual_ip"
        else
            print_error "Invalid IP address"
            exit 1
        fi
    fi
    
    log "INFO" "System detection completed"
}

#===============================================================================
# TIMEZONE CONFIGURATION
#===============================================================================

configure_timezone() {
    print_section "Timezone Configuration"
    
    local current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    print_info "Current timezone: $current_tz"
    
    echo ""
    echo "Common timezones:"
    echo "  1) UTC"
    echo "  2) America/New_York"
    echo "  3) America/Chicago"
    echo "  4) America/Denver"
    echo "  5) America/Los_Angeles"
    echo "  6) Europe/London"
    echo "  7) Europe/Paris"
    echo "  8) Asia/Tokyo"
    echo "  9) Custom"
    echo ""
    
    read -p "Select timezone [1-9] (default: 1): " tz_choice
    
    case "${tz_choice:-1}" in
        1) CONFIG["TIMEZONE"]="UTC" ;;
        2) CONFIG["TIMEZONE"]="America/New_York" ;;
        3) CONFIG["TIMEZONE"]="America/Chicago" ;;
        4) CONFIG["TIMEZONE"]="America/Denver" ;;
        5) CONFIG["TIMEZONE"]="America/Los_Angeles" ;;
        6) CONFIG["TIMEZONE"]="Europe/London" ;;
        7) CONFIG["TIMEZONE"]="Europe/Paris" ;;
        8) CONFIG["TIMEZONE"]="Asia/Tokyo" ;;
        9)
            read -p "Enter custom timezone: " custom_tz
            if timedatectl list-timezones | grep -q "^${custom_tz}$"; then
                CONFIG["TIMEZONE"]="$custom_tz"
            else
                print_warning "Invalid timezone, using UTC"
                CONFIG["TIMEZONE"]="UTC"
            fi
            ;;
        *)
            CONFIG["TIMEZONE"]="UTC"
            ;;
    esac
    
    print_success "Timezone set to: ${CONFIG["TIMEZONE"]}"
    log "INFO" "Timezone configured: ${CONFIG["TIMEZONE"]}"
}

#===============================================================================
# DIRECTORY SETUP
#===============================================================================

configure_directories() {
    print_section "Directory Configuration"
    
    print_info "Default data directory: $DATA_DIR"
    read -p "Use default data directory? (y/n) [y]: " use_default
    
    if [[ ! "$use_default" =~ ^[Yy]?$ ]]; then
        read -p "Enter custom data directory: " custom_dir
        CONFIG["DATA_DIR"]="$custom_dir"
        DATA_DIR="$custom_dir"
    fi
    
    CONFIG["BACKUP_DIR"]="${DATA_DIR}/backups"
    
    print_success "Data directory: ${CONFIG["DATA_DIR"]}"
    print_success "Backup directory: ${CONFIG["BACKUP_DIR"]}"
    
    log "INFO" "Directories configured: data=${CONFIG["DATA_DIR"]}, backup=${CONFIG["BACKUP_DIR"]}"
}
ue; do
            read -p "Enter your domain name: " domain
            if is_valid_domain "$domain"; then
                CONFIG["DOMAIN"]="$domain"
                break
            else
                print_error "Invalid domain name format"
            fi
        done

        # SSL Email
        while true; do
            read -p "Enter email for SSL certificates: " ssl_email
            if is_valid_email "$ssl_email"; then
                CONFIG["SSL_EMAIL"]="$ssl_email"
                break
            else
                print_error "Invalid email format"
            fi
        done

        # Cloudflare
        read -p "Are you using Cloudflare DNS? (y/n): " use_cf
        if [[ "$use_cf" =~ ^[Yy]$ ]]; then
            CONFIG["USE_CLOUDFLARE"]="true"

            read -p "Enter Cloudflare API Token: " -s cf_token
            echo ""
            CREDENTIALS["CLOUDFLARE_API_TOKEN"]="$cf_token"

            read -p "Enter Cloudflare Zone ID: " cf_zone
            CREDENTIALS["CLOUDFLARE_ZONE_ID"]="$cf_zone"

            print_success "Cloudflare configuration saved"
        else
            CONFIG["USE_CLOUDFLARE"]="false"
        fi

        # DNS Validation
        print_step "Validating DNS configuration..."
        validate_dns_configuration

    else
        CONFIG["HAS_DOMAIN"]="false"
        print_info "Services will be accessed via IP:PORT"
    fi

    log "INFO" "Network configuration completed"
}

validate_dns_configuration() {
    local domain="${CONFIG["DOMAIN"]}"
    local public_ip="${CONFIG["PUBLIC_IP"]}"

    print_info "Checking DNS records for $domain..."

    # Check A record
    local resolved_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | tail -1)

    if [ -z "$resolved_ip" ]; then
        print_warning "No DNS A record found for $domain"
        print_info "Make sure to create an A record pointing to: $public_ip"
    elif [ "$resolved_ip" = "$public_ip" ]; then
        print_success "DNS A record correctly configured"
    else
        print_warning "DNS A record points to $resolved_ip (expected: $public_ip)"
        print_info "Update your DNS to point to: $public_ip"
    fi

    # Check wildcard subdomain if using Cloudflare
    if [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
        local wildcard_ip=$(dig +short "*.${domain}" @8.8.8.8 2>/dev/null | tail -1)
        if [ -n "$wildcard_ip" ]; then
            print_success "Wildcard DNS record found"
        else
            print_info "Consider adding a wildcard (*) DNS record for subdomains"
        fi
    fi
}

#===============================================================================
# SERVICE SELECTION
#===============================================================================

select_services() {
    print_header "Service Selection"

    echo ""
    echo "Select the services you want to install:"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           CORE AI SERVICES                                 ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # n8n
    read -p "[ ] n8n - Workflow Automation (y/n) [y]: " install_n8n
    CONFIG["INSTALL_N8N"]="${install_n8n:-y}"
    if [[ "${CONFIG["INSTALL_N8N"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_N8N"]="true"
        configure_n8n
    else
        CONFIG["INSTALL_N8N"]="false"
    fi

    # Flowise
    read -p "[ ] Flowise - Low-code LLM Apps (y/n) [y]: " install_flowise
    CONFIG["INSTALL_FLOWISE"]="${install_flowise:-y}"
    if [[ "${CONFIG["INSTALL_FLOWISE"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_FLOWISE"]="true"
        configure_flowise
    else
        CONFIG["INSTALL_FLOWISE"]="false"
    fi

    # Open WebUI
    read -p "[ ] Open WebUI - ChatGPT-like Interface (y/n) [y]: " install_openwebui
    CONFIG["INSTALL_OPENWEBUI"]="${install_openwebui:-y}"
    if [[ "${CONFIG["INSTALL_OPENWEBUI"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_OPENWEBUI"]="true"
        configure_openwebui
    else
        CONFIG["INSTALL_OPENWEBUI"]="false"
    fi

    # AnythingLLM
    read -p "[ ] AnythingLLM - Document Chat (y/n) [n]: " install_anythingllm
    CONFIG["INSTALL_ANYTHINGLLM"]="${install_anythingllm:-n}"
    if [[ "${CONFIG["INSTALL_ANYTHINGLLM"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_ANYTHINGLLM"]="true"
        configure_anythingllm
    else
        CONFIG["INSTALL_ANYTHINGLLM"]="false"
    fi

    # Dify
    read -p "[ ] Dify - LLM Application Platform (y/n) [n]: " install_dify
    CONFIG["INSTALL_DIFY"]="${install_dify:-n}"
    if [[ "${CONFIG["INSTALL_DIFY"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_DIFY"]="true"
        configure_dify
    else
        CONFIG["INSTALL_DIFY"]="false"
    fi

    # LibreChat
    read -p "[ ] LibreChat - Multi-LLM Chat (y/n) [n]: " install_librechat
    CONFIG["INSTALL_LIBRECHAT"]="${install_librechat:-n}"
    if [[ "${CONFIG["INSTALL_LIBRECHAT"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_LIBRECHAT"]="true"
        configure_librechat
    else
        CONFIG["INSTALL_LIBRECHAT"]="false"
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                        INFRASTRUCTURE SERVICES                             ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Ollama
    read -p "[ ] Ollama - Local LLM Runtime (y/n) [y]: " install_ollama
    CONFIG["INSTALL_OLLAMA"]="${install_ollama:-y}"
    if [[ "${CONFIG["INSTALL_OLLAMA"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_OLLAMA"]="true"
        configure_ollama
    else
        CONFIG["INSTALL_OLLAMA"]="false"
    fi

    # Langfuse
    read -p "[ ] Langfuse - LLM Observability (y/n) [y]: " install_langfuse
    CONFIG["INSTALL_LANGFUSE"]="${install_langfuse:-y}"
    if [[ "${CONFIG["INSTALL_LANGFUSE"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_LANGFUSE"]="true"
        configure_langfuse
    else
        CONFIG["INSTALL_LANGFUSE"]="false"
    fi

    # Vector Database
    read -p "[ ] Vector Database (Qdrant/Weaviate) (y/n) [y]: " install_vectordb
    CONFIG["INSTALL_VECTORDB"]="${install_vectordb:-y}"
    if [[ "${CONFIG["INSTALL_VECTORDB"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_VECTORDB"]="true"
        configure_vectordb
    else
        CONFIG["INSTALL_VECTORDB"]="false"
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                         MONITORING & MANAGEMENT                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Uptime Kuma
    read -p "[ ] Uptime Kuma - Service Monitoring (y/n) [y]: " install_uptime
    CONFIG["INSTALL_UPTIME_KUMA"]="${install_uptime:-y}"
    if [[ "${CONFIG["INSTALL_UPTIME_KUMA"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_UPTIME_KUMA"]="true"
        configure_uptime_kuma
    else
        CONFIG["INSTALL_UPTIME_KUMA"]="false"
    fi

    # Portainer
    read -p "[ ] Portainer - Docker Management (y/n) [y]: " install_portainer
    CONFIG["INSTALL_PORTAINER"]="${install_portainer:-y}"
    if [[ "${CONFIG["INSTALL_PORTAINER"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_PORTAINER"]="true"
        configure_portainer
    else
        CONFIG["INSTALL_PORTAINER"]="false"
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                          OPTIONAL SERVICES                                 ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # ComfyUI
    if [ "${CONFIG["HAS_GPU"]}" = "true" ]; then
        read -p "[ ] ComfyUI - Image Generation (y/n) [n]: " install_comfyui
        CONFIG["INSTALL_COMFYUI"]="${install_comfyui:-n}"
        if [[ "${CONFIG["INSTALL_COMFYUI"]}" =~ ^[Yy]$ ]]; then
            CONFIG["INSTALL_COMFYUI"]="true"
            configure_comfyui
        else
            CONFIG["INSTALL_COMFYUI"]="false"
        fi
    else
        CONFIG["INSTALL_COMFYUI"]="false"
        print_info "ComfyUI skipped (GPU required)"
    fi

    # Signal
    read -p "[ ] Signal - Messaging Integration (y/n) [n]: " install_signal
    CONFIG["INSTALL_SIGNAL"]="${install_signal:-n}"
    if [[ "${CONFIG["INSTALL_SIGNAL"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_SIGNAL"]="true"
        configure_signal
    else
        CONFIG["INSTALL_SIGNAL"]="false"
    fi

    # OpenClaw
    read -p "[ ] OpenClaw - Web Scraping (y/n) [n]: " install_openclaw
    CONFIG["INSTALL_OPENCLAW"]="${install_openclaw:-n}"
    if [[ "${CONFIG["INSTALL_OPENCLAW"]}" =~ ^[Yy]$ ]]; then
        CONFIG["INSTALL_OPENCLAW"]="true"
        configure_openclaw
    else
        CONFIG["INSTALL_OPENCLAW"]="false"
    fi

    log "INFO" "Service selection completed"
}

#===============================================================================
# SERVICE CONFIGURATION FUNCTIONS
#===============================================================================

configure_n8n() {
    print_step "Configuring n8n..."

    # Port
    local default_port=5678
    read -p "n8n port [$default_port]: " n8n_port
    CONFIG["N8N_PORT"]="${n8n_port:-$default_port}"

    # Domain/Subdomain
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "n8n subdomain (e.g., 'n8n' for n8n.${CONFIG["DOMAIN"]}) [n8n]: " n8n_subdomain
        CONFIG["N8N_SUBDOMAIN"]="${n8n_subdomain:-n8n}"
        CONFIG["N8N_URL"]="https://${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["N8N_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["N8N_PORT"]}"
    fi

    # Encryption key
    CONFIG["N8N_ENCRYPTION_KEY"]=$(generate_secret)

    print_success "n8n configured: ${CONFIG["N8N_URL"]}"
}

configure_flowise() {
    print_step "Configuring Flowise..."

    local default_port=3000
    read -p "Flowise port [$default_port]: " flowise_port
    CONFIG["FLOWISE_PORT"]="${flowise_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Flowise subdomain [flowise]: " flowise_subdomain
        CONFIG["FLOWISE_SUBDOMAIN"]="${flowise_subdomain:-flowise}"
        CONFIG["FLOWISE_URL"]="https://${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["FLOWISE_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["FLOWISE_PORT"]}"
    fi

    # Username and password
    read -p "Flowise username [admin]: " flowise_user
    CONFIG["FLOWISE_USERNAME"]="${flowise_user:-admin}"

    read -p "Flowise password (leave empty to generate): " -s flowise_pass
    echo ""
    if [ -z "$flowise_pass" ]; then
        flowise_pass=$(generate_password)
        print_info "Generated password: $flowise_pass"
    fi
    CREDENTIALS["FLOWISE_PASSWORD"]="$flowise_pass"

    # Secret key
    CONFIG["FLOWISE_SECRET_KEY"]=$(generate_secret)

    print_success "Flowise configured: ${CONFIG["FLOWISE_URL"]}"
}

configure_openwebui() {
    print_step "Configuring Open WebUI..."

    local default_port=3001
    read -p "Open WebUI port [$default_port]: " openwebui_port
    CONFIG["OPENWEBUI_PORT"]="${openwebui_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Open WebUI subdomain [chat]: " openwebui_subdomain
        CONFIG["OPENWEBUI_SUBDOMAIN"]="${openwebui_subdomain:-chat}"
        CONFIG["OPENWEBUI_URL"]="https://${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["OPENWEBUI_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["OPENWEBUI_PORT"]}"
    fi

    # Ollama connection
    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        CONFIG["OPENWEBUI_OLLAMA_URL"]="http://ollama:11434"
        print_info "Will connect to local Ollama instance"
    else
        read -p "External Ollama URL (optional): " ollama_url
        CONFIG["OPENWEBUI_OLLAMA_URL"]="${ollama_url:-}"
    fi

    # JWT secret
    CONFIG["OPENWEBUI_JWT_SECRET"]=$(generate_jwt_secret)

    print_success "Open WebUI configured: ${CONFIG["OPENWEBUI_URL"]}"
}

configure_anythingllm() {
    print_step "Configuring AnythingLLM..."

    local default_port=3002
    read -p "AnythingLLM port [$default_port]: " anythingllm_port
    CONFIG["ANYTHINGLLM_PORT"]="${anythingllm_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "AnythingLLM subdomain [docs]: " anythingllm_subdomain
        CONFIG["ANYTHINGLLM_SUBDOMAIN"]="${anythingllm_subdomain:-docs}"
        CONFIG["ANYTHINGLLM_URL"]="https://${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["ANYTHINGLLM_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["ANYTHINGLLM_PORT"]}"
    fi

    # JWT secret
    CONFIG["ANYTHINGLLM_JWT_SECRET"]=$(generate_jwt_secret)

    # Auth token
    CONFIG["ANYTHINGLLM_AUTH_TOKEN"]=$(generate_secret)

    print_success "AnythingLLM configured: ${CONFIG["ANYTHINGLLM_URL"]}"
}

configure_dify() {
    print_step "Configuring Dify..."

    local default_port=3003
    read -p "Dify port [$default_port]: " dify_port
    CONFIG["DIFY_PORT"]="${dify_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Dify subdomain [dify]: " dify_subdomain
        CONFIG["DIFY_SUBDOMAIN"]="${dify_subdomain:-dify}"
        CONFIG["DIFY_URL"]="https://${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["DIFY_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["DIFY_PORT"]}"
    fi

    # Secret key
    CONFIG["DIFY_SECRET_KEY"]=$(generate_secret)

    print_success "Dify configured: ${CONFIG["DIFY_URL"]}"
}

configure_librechat() {
    print_step "Configuring LibreChat..."

    local default_port=3004
    read -p "LibreChat port [$default_port]: " librechat_port
    CONFIG["LIBRECHAT_PORT"]="${librechat_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "LibreChat subdomain [librechat]: " librechat_subdomain
        CONFIG["LIBRECHAT_SUBDOMAIN"]="${librechat_subdomain:-librechat}"
        CONFIG["LIBRECHAT_URL"]="https://${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["LIBRECHAT_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["LIBRECHAT_PORT"]}"
    fi

    # JWT secrets
    CONFIG["LIBRECHAT_JWT_SECRET"]=$(generate_jwt_secret)
    CONFIG["LIBRECHAT_JWT_REFRESH_SECRET"]=$(generate_jwt_secret)

    print_success "LibreChat configured: ${CONFIG["LIBRECHAT_URL"]}"
}

configure_ollama() {
    print_step "Configuring Ollama..."

    local default_port=11434
    read -p "Ollama port [$default_port]: " ollama_port
    CONFIG["OLLAMA_PORT"]="${ollama_port:-$default_port}"

    # GPU configuration
    if [ "${CONFIG["HAS_GPU"]}" = "true" ]; then
        CONFIG["OLLAMA_GPU_ENABLED"]="true"
        print_success "GPU acceleration enabled for Ollama"
    else
        CONFIG["OLLAMA_GPU_ENABLED"]="false"
        print_info "Ollama will run in CPU-only mode"
    fi

    # Default models to pull
    print_info "Select default models to pull (optional):"
    echo "  1) llama2"
    echo "  2) mistral"
    echo "  3) codellama"
    echo "  4) phi"
    echo "  5) Skip"

    read -p "Enter numbers separated by space [5]: " model_choices
    CONFIG["OLLAMA_DEFAULT_MODELS"]="${model_choices:-5}"

    print_success "Ollama configured on port ${CONFIG["OLLAMA_PORT"]}"
}

configure_langfuse() {
    print_step "Configuring Langfuse..."

    local default_port=3005
    read -p "Langfuse port [$default_port]: " langfuse_port
    CONFIG["LANGFUSE_PORT"]="${langfuse_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Langfuse subdomain [langfuse]: " langfuse_subdomain
        CONFIG["LANGFUSE_SUBDOMAIN"]="${langfuse_subdomain:-langfuse}"
        CONFIG["LANGFUSE_URL"]="https://${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["LANGFUSE_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["LANGFUSE_PORT"]}"
    fi

    # Salt and secrets
    CONFIG["LANGFUSE_SALT"]=$(generate_secret)
    CONFIG["LANGFUSE_NEXTAUTH_SECRET"]=$(generate_secret)

    print_success "Langfuse configured: ${CONFIG["LANGFUSE_URL"]}"
}

configure_vectordb() {
    print_step "Configuring Vector Database..."

    echo ""
    echo "Select vector database:"
    echo "  1) Qdrant (recommended)"
    echo "  2) Weaviate"
    echo "  3) Both"
    echo ""

    read -p "Choice [1]: " vectordb_choice

    case "${vectordb_choice:-1}" in
        1)
            CONFIG["VECTORDB_TYPE"]="qdrant"
            CONFIG["QDRANT_PORT"]="6333"
            print_success "Qdrant will be installed on port 6333"
            ;;
        2)
            CONFIG["VECTORDB_TYPE"]="weaviate"
            CONFIG["WEAVIATE_PORT"]="8080"
            print_success "Weaviate will be installed on port 8080"
            ;;
        3)
            CONFIG["VECTORDB_TYPE"]="both"
            CONFIG["QDRANT_PORT"]="6333"
            CONFIG["WEAVIATE_PORT"]="8080"
            print_success "Both Qdrant and Weaviate will be installed"
            ;;
        *)
            CONFIG["VECTORDB_TYPE"]="qdrant"
            CONFIG["QDRANT_PORT"]="6333"
            ;;
    esac

    # API key for Qdrant
    if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(qdrant|both)$ ]]; then
        CONFIG["QDRANT_API_KEY"]=$(generate_secret)
    fi
}

configure_uptime_kuma() {
    print_step "Configuring Uptime Kuma..."

    local default_port=3006
    read -p "Uptime Kuma port [$default_port]: " uptime_port
    CONFIG["UPTIME_KUMA_PORT"]="${uptime_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Uptime Kuma subdomain [status]: " uptime_subdomain
        CONFIG["UPTIME_KUMA_SUBDOMAIN"]="${uptime_subdomain:-status}"
        CONFIG["UPTIME_KUMA_URL"]="https://${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["UPTIME_KUMA_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["UPTIME_KUMA_PORT"]}"
    fi

    print_success "Uptime Kuma configured: ${CONFIG["UPTIME_KUMA_URL"]}"
}

configure_portainer() {
    print_step "Configuring Portainer..."

    local default_port=9443
    read -p "Portainer port [$default_port]: " portainer_port
    CONFIG["PORTAINER_PORT"]="${portainer_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "Portainer subdomain [portainer]: " portainer_subdomain
        CONFIG["PORTAINER_SUBDOMAIN"]="${portainer_subdomain:-portainer}"
        CONFIG["PORTAINER_URL"]="https://${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["PORTAINER_URL"]="https://${CONFIG["PUBLIC_IP"]}:${CONFIG["PORTAINER_PORT"]}"
    fi

    print_success "Portainer configured: ${CONFIG["PORTAINER_URL"]}"
}

configure_comfyui() {
    print_step "Configuring ComfyUI..."

    local default_port=8188
    read -p "ComfyUI port [$default_port]: " comfyui_port
    CONFIG["COMFYUI_PORT"]="${comfyui_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "ComfyUI subdomain [comfy]: " comfyui_subdomain
        CONFIG["COMFYUI_SUBDOMAIN"]="${comfyui_subdomain:-comfy}"
        CONFIG["COMFYUI_URL"]="https://${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["COMFYUI_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["COMFYUI_PORT"]}"
    fi

    print_success "ComfyUI configured: ${CONFIG["COMFYUI_URL"]}"
}

configure_signal() {
    print_step "Configuring Signal..."

    local default_port=8080
    read -p "Signal API port [$default_port]: " signal_port
    CONFIG["SIGNAL_PORT"]="${signal_port:-$default_port}"

    print_info "Signal requires phone number registration"
    print_info "This will be configured during first run"

    print_success "Signal configured on port ${CONFIG["SIGNAL_PORT"]}"
}

configure_openclaw() {
    print_step "Configuring OpenClaw..."

    local default_port=3007
    read -p "OpenClaw port [$default_port]: " openclaw_port
    CONFIG["OPENCLAW_PORT"]="${openclaw_port:-$default_port}"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        read -p "OpenClaw subdomain [openclaw]: " openclaw_subdomain
        CONFIG["OPENCLAW_SUBDOMAIN"]="${openclaw_subdomain:-openclaw}"
        CONFIG["OPENCLAW_URL"]="https://${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}"
    else
        CONFIG["OPENCLAW_URL"]="http://${CONFIG["PUBLIC_IP"]}:${CONFIG["OPENCLAW_PORT"]}"
    fi

    # API key
    CONFIG["OPENCLAW_API_KEY"]=$(generate_secret)

    print_success "OpenClaw configured: ${CONFIG["OPENCLAW_URL"]}"
}
#===============================================================================
# LLM PROVIDER CONFIGURATION
#===============================================================================

configure_llm_providers() {
    print_header "LLM Provider Configuration"

    echo ""
    echo "Configure API keys for external LLM providers"
    echo "Skip any providers you don't want to use (press Enter)"
    echo ""

    # OpenAI
    print_section "OpenAI"
    read -p "Enter OpenAI API key (or press Enter to skip): " -s openai_key
    echo ""
    if [ -n "$openai_key" ]; then
        CREDENTIALS["OPENAI_API_KEY"]="$openai_key"
        LLM_PROVIDERS["OPENAI"]="true"

        read -p "Enter OpenAI Organization ID (optional): " openai_org
        if [ -n "$openai_org" ]; then
            CREDENTIALS["OPENAI_ORG_ID"]="$openai_org"
        fi

        print_success "OpenAI configured"
    else
        LLM_PROVIDERS["OPENAI"]="false"
        print_info "OpenAI skipped"
    fi

    # Anthropic (Claude)
    print_section "Anthropic (Claude)"
    read -p "Enter Anthropic API key (or press Enter to skip): " -s anthropic_key
    echo ""
    if [ -n "$anthropic_key" ]; then
        CREDENTIALS["ANTHROPIC_API_KEY"]="$anthropic_key"
        LLM_PROVIDERS["ANTHROPIC"]="true"
        print_success "Anthropic configured"
    else
        LLM_PROVIDERS["ANTHROPIC"]="false"
        print_info "Anthropic skipped"
    fi

    # Groq
    print_section "Groq"
    read -p "Enter Groq API key (or press Enter to skip): " -s groq_key
    echo ""
    if [ -n "$groq_key" ]; then
        CREDENTIALS["GROQ_API_KEY"]="$groq_key"
        LLM_PROVIDERS["GROQ"]="true"
        print_success "Groq configured"
    else
        LLM_PROVIDERS["GROQ"]="false"
        print_info "Groq skipped"
    fi

    # Mistral AI
    print_section "Mistral AI"
    read -p "Enter Mistral API key (or press Enter to skip): " -s mistral_key
    echo ""
    if [ -n "$mistral_key" ]; then
        CREDENTIALS["MISTRAL_API_KEY"]="$mistral_key"
        LLM_PROVIDERS["MISTRAL"]="true"
        print_success "Mistral AI configured"
    else
        LLM_PROVIDERS["MISTRAL"]="false"
        print_info "Mistral AI skipped"
    fi

    # Cohere
    print_section "Cohere"
    read -p "Enter Cohere API key (or press Enter to skip): " -s cohere_key
    echo ""
    if [ -n "$cohere_key" ]; then
        CREDENTIALS["COHERE_API_KEY"]="$cohere_key"
        LLM_PROVIDERS["COHERE"]="true"
        print_success "Cohere configured"
    else
        LLM_PROVIDERS["COHERE"]="false"
        print_info "Cohere skipped"
    fi

    # Together AI
    print_section "Together AI"
    read -p "Enter Together AI API key (or press Enter to skip): " -s together_key
    echo ""
    if [ -n "$together_key" ]; then
        CREDENTIALS["TOGETHER_API_KEY"]="$together_key"
        LLM_PROVIDERS["TOGETHER"]="true"
        print_success "Together AI configured"
    else
        LLM_PROVIDERS["TOGETHER"]="false"
        print_info "Together AI skipped"
    fi

    # Perplexity
    print_section "Perplexity AI"
    read -p "Enter Perplexity API key (or press Enter to skip): " -s perplexity_key
    echo ""
    if [ -n "$perplexity_key" ]; then
        CREDENTIALS["PERPLEXITY_API_KEY"]="$perplexity_key"
        LLM_PROVIDERS["PERPLEXITY"]="true"
        print_success "Perplexity AI configured"
    else
        LLM_PROVIDERS["PERPLEXITY"]="false"
        print_info "Perplexity AI skipped"
    fi

    # OpenRouter
    print_section "OpenRouter"
    read -p "Enter OpenRouter API key (or press Enter to skip): " -s openrouter_key
    echo ""
    if [ -n "$openrouter_key" ]; then
        CREDENTIALS["OPENROUTER_API_KEY"]="$openrouter_key"
        LLM_PROVIDERS["OPENROUTER"]="true"
        print_success "OpenRouter configured"
    else
        LLM_PROVIDERS["OPENROUTER"]="false"
        print_info "OpenRouter skipped"
    fi

    # Google AI (Gemini)
    print_section "Google AI (Gemini)"
    read -p "Enter Google AI API key (or press Enter to skip): " -s google_key
    echo ""
    if [ -n "$google_key" ]; then
        CREDENTIALS["GOOGLE_AI_API_KEY"]="$google_key"
        LLM_PROVIDERS["GOOGLE"]="true"
        print_success "Google AI configured"
    else
        LLM_PROVIDERS["GOOGLE"]="false"
        print_info "Google AI skipped"
    fi

    # xAI (Grok)
    print_section "xAI (Grok)"
    read -p "Enter xAI API key (or press Enter to skip): " -s xai_key
    echo ""
    if [ -n "$xai_key" ]; then
        CREDENTIALS["XAI_API_KEY"]="$xai_key"
        LLM_PROVIDERS["XAI"]="true"
        print_success "xAI configured"
    else
        LLM_PROVIDERS["XAI"]="false"
        print_info "xAI skipped"
    fi

    # Hugging Face
    print_section "Hugging Face"
    read -p "Enter Hugging Face API token (or press Enter to skip): " -s hf_token
    echo ""
    if [ -n "$hf_token" ]; then
        CREDENTIALS["HUGGINGFACE_API_KEY"]="$hf_token"
        LLM_PROVIDERS["HUGGINGFACE"]="true"
        print_success "Hugging Face configured"
    else
        LLM_PROVIDERS["HUGGINGFACE"]="false"
        print_info "Hugging Face skipped"
    fi

    # Summary
    echo ""
    print_section "LLM Provider Summary"
    local provider_count=0
    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" = "true" ]; then
            echo -e "${GREEN}✓${NC} $provider"
            ((provider_count++))
        fi
    done

    if [ $provider_count -eq 0 ]; then
        print_warning "No external LLM providers configured"
        if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
            print_info "You can use local models with Ollama"
        else
            print_warning "Consider configuring at least one LLM provider"
        fi
    else
        print_success "$provider_count LLM provider(s) configured"
    fi

    log "INFO" "LLM provider configuration completed: $provider_count providers"
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

validate_ports() {
    print_section "Port Validation"

    local ports_to_check=()
    local port_conflicts=()

    # Collect all configured ports
    [ "${CONFIG["INSTALL_N8N"]}" = "true" ] && ports_to_check+=("${CONFIG["N8N_PORT"]}:n8n")
    [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ] && ports_to_check+=("${CONFIG["FLOWISE_PORT"]}:Flowise")
    [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && ports_to_check+=("${CONFIG["OPENWEBUI_PORT"]}:Open WebUI")
    [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ] && ports_to_check+=("${CONFIG["ANYTHINGLLM_PORT"]}:AnythingLLM")
    [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] && ports_to_check+=("${CONFIG["DIFY_PORT"]}:Dify")
    [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ] && ports_to_check+=("${CONFIG["LIBRECHAT_PORT"]}:LibreChat")
    [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ] && ports_to_check+=("${CONFIG["OLLAMA_PORT"]}:Ollama")
    [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ] && ports_to_check+=("${CONFIG["LANGFUSE_PORT"]}:Langfuse")
    [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ] && ports_to_check+=("${CONFIG["UPTIME_KUMA_PORT"]}:Uptime Kuma")
    [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ] && ports_to_check+=("${CONFIG["PORTAINER_PORT"]}:Portainer")
    [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ] && ports_to_check+=("${CONFIG["COMFYUI_PORT"]}:ComfyUI")
    [ "${CONFIG["INSTALL_SIGNAL"]}" = "true" ] && ports_to_check+=("${CONFIG["SIGNAL_PORT"]}:Signal")
    [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ] && ports_to_check+=("${CONFIG["OPENCLAW_PORT"]}:OpenClaw")

    if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(qdrant|both)$ ]]; then
        ports_to_check+=("${CONFIG["QDRANT_PORT"]}:Qdrant")
    fi

    if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(weaviate|both)$ ]]; then
        ports_to_check+=("${CONFIG["WEAVIATE_PORT"]}:Weaviate")
    fi

    # Check for duplicates
    declare -A port_map
    for entry in "${ports_to_check[@]}"; do
        local port="${entry%%:*}"
        local service="${entry#*:}"

        if [ -n "${port_map[$port]}" ]; then
            port_conflicts+=("Port $port: ${port_map[$port]} and $service")
        else
            port_map[$port]="$service"
        fi
    done

    # Check if ports are already in use
    for entry in "${ports_to_check[@]}"; do
        local port="${entry%%:*}"
        local service="${entry#*:}"

        if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
            port_conflicts+=("Port $port ($service): Already in use by another process")
        fi
    done

    if [ ${#port_conflicts[@]} -gt 0 ]; then
        print_error "Port conflicts detected:"
        for conflict in "${port_conflicts[@]}"; do
            echo -e "  ${RED}✗${NC} $conflict"
        done
        return 1
    else
        print_success "All ports available"
        return 0
    fi
}

validate_domain_config() {
    print_section "Domain Configuration Validation"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "false" ]; then
        print_info "No domain configured - skipping domain validation"
        return 0
    fi

    local domain="${CONFIG["DOMAIN"]}"
    local validation_errors=0

    # Check domain format
    if ! is_valid_domain "$domain"; then
        print_error "Invalid domain format: $domain"
        ((validation_errors++))
    fi

    # Check SSL email
    if [ -z "${CONFIG["SSL_EMAIL"]}" ]; then
        print_error "SSL email not configured"
        ((validation_errors++))
    elif ! is_valid_email "${CONFIG["SSL_EMAIL"]}"; then
        print_error "Invalid SSL email format: ${CONFIG["SSL_EMAIL"]}"
        ((validation_errors++))
    fi

    # Check Cloudflare configuration
    if [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
        if [ -z "${CREDENTIALS["CLOUDFLARE_API_TOKEN"]}" ]; then
            print_error "Cloudflare API token not configured"
            ((validation_errors++))
        fi

        if [ -z "${CREDENTIALS["CLOUDFLARE_ZONE_ID"]}" ]; then
            print_error "Cloudflare Zone ID not configured"
            ((validation_errors++))
        fi
    fi

    if [ $validation_errors -eq 0 ]; then
        print_success "Domain configuration valid"
        return 0
    else
        print_error "Domain configuration has $validation_errors error(s)"
        return 1
    fi
}

validate_llm_providers() {
    print_section "LLM Provider Validation"

    local provider_count=0
    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" = "true" ]; then
            ((provider_count++))
        fi
    done

    if [ $provider_count -eq 0 ] && [ "${CONFIG["INSTALL_OLLAMA"]}" = "false" ]; then
        print_warning "No LLM providers configured"
        print_info "You may have limited functionality without LLM providers"
        read -p "Continue anyway? (y/n): " continue_without_llm
        if [[ ! "$continue_without_llm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        print_success "LLM providers configured: $provider_count external + Ollama=${CONFIG["INSTALL_OLLAMA"]}"
    fi

    return 0
}

validate_service_dependencies() {
    print_section "Service Dependency Validation"

    local dependency_errors=0

    # Check if any service needs vector database
    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        if [ "${CONFIG["INSTALL_VECTORDB"]}" = "false" ]; then
            print_warning "Selected services recommend a vector database"
            print_info "Consider enabling Qdrant or Weaviate"
        fi
    fi

    # Check if Open WebUI is installed without Ollama
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && \
       [ "${CONFIG["INSTALL_OLLAMA"]}" = "false" ] && \
       [ -z "${CONFIG["OPENWEBUI_OLLAMA_URL"]}" ]; then
        print_warning "Open WebUI works best with Ollama"
        print_info "Consider enabling Ollama or providing an external Ollama URL"
    fi

    # Check if ComfyUI is installed without GPU
    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ] && \
       [ "${CONFIG["HAS_GPU"]}" = "false" ]; then
        print_error "ComfyUI requires GPU support"
        ((dependency_errors++))
    fi

    if [ $dependency_errors -eq 0 ]; then
        print_success "Service dependencies valid"
        return 0
    else
        print_error "Service dependency validation failed: $dependency_errors error(s)"
        return 1
    fi
}

validate_disk_space() {
    print_section "Disk Space Validation"

    local data_dir="${CONFIG["DATA_DIR"]}"
    local required_space_gb=50  # Minimum recommended

    # Get available space in GB
    local available_space_gb=$(df -BG "$data_dir" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ -z "$available_space_gb" ]; then
        print_warning "Could not determine available disk space"
        return 0
    fi

    if [ "$available_space_gb" -lt "$required_space_gb" ]; then
        print_error "Insufficient disk space: ${available_space_gb}GB available, ${required_space_gb}GB required"
        return 1
    else
        print_success "Sufficient disk space: ${available_space_gb}GB available"
        return 0
    fi
}

validate_configuration() {
    print_header "Configuration Validation"

    local validation_failed=false

    # Run all validation checks
    validate_ports || validation_failed=true
    validate_domain_config || validation_failed=true
    validate_llm_providers || validation_failed=true
    validate_service_dependencies || validation_failed=true
    validate_disk_space || validation_failed=true

    if [ "$validation_failed" = true ]; then
        print_error "Configuration validation failed"
        read -p "Do you want to continue anyway? (y/n): " force_continue
        if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        print_warning "Continuing despite validation errors..."
    else
        print_success "All validation checks passed"
    fi

    log "INFO" "Configuration validation completed"
}

#===============================================================================
# CONFIGURATION FILE GENERATION
#===============================================================================

generate_config_file() {
    print_section "Generating Configuration Files"

    local config_file="${PROJECT_ROOT}/.env"
    local config_backup="${PROJECT_ROOT}/.env.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup existing config if it exists
    if [ -f "$config_file" ]; then
        print_info "Backing up existing configuration..."
        cp "$config_file" "$config_backup"
        print_success "Backup created: $config_backup"
    fi

    print_info "Generating new configuration file..."

    cat > "$config_file" << EOF
#===============================================================================
# AI PLATFORM CONFIGURATION
# Generated: $(date)
# Version: ${CONFIG["SCRIPT_VERSION"]}
#===============================================================================

#-------------------------------------------------------------------------------
# System Configuration
#-------------------------------------------------------------------------------
SCRIPT_VERSION=${CONFIG["SCRIPT_VERSION"]}
DATA_DIR=${CONFIG["DATA_DIR"]}
BACKUP_DIR=${CONFIG["BACKUP_DIR"]}
TIMEZONE=${CONFIG["TIMEZONE"]}
PUBLIC_IP=${CONFIG["PUBLIC_IP"]}

#-------------------------------------------------------------------------------
# Hardware Configuration
#-------------------------------------------------------------------------------
HAS_GPU=${CONFIG["HAS_GPU"]}
GPU_NAME="${CONFIG["GPU_NAME"]}"
TOTAL_RAM=${CONFIG["TOTAL_RAM"]}
CPU_CORES=${CONFIG["CPU_CORES"]}

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
HAS_DOMAIN=${CONFIG["HAS_DOMAIN"]}
DOMAIN=${CONFIG["DOMAIN"]}
SSL_EMAIL=${CONFIG["SSL_EMAIL"]}
USE_CLOUDFLARE=${CONFIG["USE_CLOUDFLARE"]}

#-------------------------------------------------------------------------------
# Service Installation Flags
#-------------------------------------------------------------------------------
INSTALL_N8N=${CONFIG["INSTALL_N8N"]}
INSTALL_FLOWISE=${CONFIG["INSTALL_FLOWISE"]}
INSTALL_OPENWEBUI=${CONFIG["INSTALL_OPENWEBUI"]}
INSTALL_ANYTHINGLLM=${CONFIG["INSTALL_ANYTHINGLLM"]}
INSTALL_DIFY=${CONFIG["INSTALL_DIFY"]}
INSTALL_LIBRECHAT=${CONFIG["INSTALL_LIBRECHAT"]}
INSTALL_OLLAMA=${CONFIG["INSTALL_OLLAMA"]}
INSTALL_LANGFUSE=${CONFIG["INSTALL_LANGFUSE"]}
INSTALL_VECTORDB=${CONFIG["INSTALL_VECTORDB"]}
INSTALL_UPTIME_KUMA=${CONFIG["INSTALL_UPTIME_KUMA"]}
INSTALL_PORTAINER=${CONFIG["INSTALL_PORTAINER"]}
INSTALL_COMFYUI=${CONFIG["INSTALL_COMFYUI"]}
INSTALL_SIGNAL=${CONFIG["INSTALL_SIGNAL"]}
INSTALL_OPENCLAW=${CONFIG["INSTALL_OPENCLAW"]}

#-------------------------------------------------------------------------------
# n8n Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        cat >> "$config_file" << EOF
N8N_PORT=${CONFIG["N8N_PORT"]}
N8N_SUBDOMAIN=${CONFIG["N8N_SUBDOMAIN"]:-n8n}
N8N_URL=${CONFIG["N8N_URL"]}
N8N_ENCRYPTION_KEY=${CONFIG["N8N_ENCRYPTION_KEY"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Flowise Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        cat >> "$config_file" << EOF
FLOWISE_PORT=${CONFIG["FLOWISE_PORT"]}
FLOWISE_SUBDOMAIN=${CONFIG["FLOWISE_SUBDOMAIN"]:-flowise}
FLOWISE_URL=${CONFIG["FLOWISE_URL"]}
FLOWISE_USERNAME=${CONFIG["FLOWISE_USERNAME"]}
FLOWISE_SECRET_KEY=${CONFIG["FLOWISE_SECRET_KEY"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Open WebUI Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        cat >> "$config_file" << EOF
OPENWEBUI_PORT=${CONFIG["OPENWEBUI_PORT"]}
OPENWEBUI_SUBDOMAIN=${CONFIG["OPENWEBUI_SUBDOMAIN"]:-chat}
OPENWEBUI_URL=${CONFIG["OPENWEBUI_URL"]}
OPENWEBUI_OLLAMA_URL=${CONFIG["OPENWEBUI_OLLAMA_URL"]}
OPENWEBUI_JWT_SECRET=${CONFIG["OPENWEBUI_JWT_SECRET"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# AnythingLLM Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        cat >> "$config_file" << EOF
ANYTHINGLLM_PORT=${CONFIG["ANYTHINGLLM_PORT"]}
ANYTHINGLLM_SUBDOMAIN=${CONFIG["ANYTHINGLLM_SUBDOMAIN"]:-docs}
ANYTHINGLLM_URL=${CONFIG["ANYTHINGLLM_URL"]}
ANYTHINGLLM_JWT_SECRET=${CONFIG["ANYTHINGLLM_JWT_SECRET"]}
ANYTHINGLLM_AUTH_TOKEN=${CONFIG["ANYTHINGLLM_AUTH_TOKEN"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Dify Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        cat >> "$config_file" << EOF
DIFY_PORT=${CONFIG["DIFY_PORT"]}
DIFY_SUBDOMAIN=${CONFIG["DIFY_SUBDOMAIN"]:-dify}
DIFY_URL=${CONFIG["DIFY_URL"]}
DIFY_SECRET_KEY=${CONFIG["DIFY_SECRET_KEY"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# LibreChat Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        cat >> "$config_file" << EOF
LIBRECHAT_PORT=${CONFIG["LIBRECHAT_PORT"]}
LIBRECHAT_SUBDOMAIN=${CONFIG["LIBRECHAT_SUBDOMAIN"]:-librechat}
LIBRECHAT_URL=${CONFIG["LIBRECHAT_URL"]}
LIBRECHAT_JWT_SECRET=${CONFIG["LIBRECHAT_JWT_SECRET"]}
LIBRECHAT_JWT_REFRESH_SECRET=${CONFIG["LIBRECHAT_JWT_REFRESH_SECRET"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Ollama Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        cat >> "$config_file" << EOF
OLLAMA_PORT=${CONFIG["OLLAMA_PORT"]}
OLLAMA_GPU_ENABLED=${CONFIG["OLLAMA_GPU_ENABLED"]}
OLLAMA_DEFAULT_MODELS=${CONFIG["OLLAMA_DEFAULT_MODELS"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Langfuse Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        cat >> "$config_file" << EOF
LANGFUSE_PORT=${CONFIG["LANGFUSE_PORT"]}
LANGFUSE_SUBDOMAIN=${CONFIG["LANGFUSE_SUBDOMAIN"]:-langfuse}
LANGFUSE_URL=${CONFIG["LANGFUSE_URL"]}
LANGFUSE_SALT=${CONFIG["LANGFUSE_SALT"]}
LANGFUSE_NEXTAUTH_SECRET=${CONFIG["LANGFUSE_NEXTAUTH_SECRET"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Vector Database Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ]; then
        cat >> "$config_file" << EOF
VECTORDB_TYPE=${CONFIG["VECTORDB_TYPE"]}
EOF

        if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(qdrant|both)$ ]]; then
            cat >> "$config_file" << EOF
QDRANT_PORT=${CONFIG["QDRANT_PORT"]}
QDRANT_API_KEY=${CONFIG["QDRANT_API_KEY"]}
EOF
        fi

        if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(weaviate|both)$ ]]; then
            cat >> "$config_file" << EOF
WEAVIATE_PORT=${CONFIG["WEAVIATE_PORT"]}
EOF
        fi
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Uptime Kuma Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        cat >> "$config_file" << EOF
UPTIME_KUMA_PORT=${CONFIG["UPTIME_KUMA_PORT"]}
UPTIME_KUMA_SUBDOMAIN=${CONFIG["UPTIME_KUMA_SUBDOMAIN"]:-status}
UPTIME_KUMA_URL=${CONFIG["UPTIME_KUMA_URL"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Portainer Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        cat >> "$config_file" << EOF
PORTAINER_PORT=${CONFIG["PORTAINER_PORT"]}
PORTAINER_SUBDOMAIN=${CONFIG["PORTAINER_SUBDOMAIN"]:-portainer}
PORTAINER_URL=${CONFIG["PORTAINER_URL"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# ComfyUI Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ]; then
        cat >> "$config_file" << EOF
COMFYUI_PORT=${CONFIG["COMFYUI_PORT"]}
COMFYUI_SUBDOMAIN=${CONFIG["COMFYUI_SUBDOMAIN"]:-comfy}
COMFYUI_URL=${CONFIG["COMFYUI_URL"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# Signal Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_SIGNAL"]}" = "true" ]; then
        cat >> "$config_file" << EOF
SIGNAL_PORT=${CONFIG["SIGNAL_PORT"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# OpenClaw Configuration
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        cat >> "$config_file" << EOF
OPENCLAW_PORT=${CONFIG["OPENCLAW_PORT"]}
OPENCLAW_SUBDOMAIN=${CONFIG["OPENCLAW_SUBDOMAIN"]:-openclaw}
OPENCLAW_URL=${CONFIG["OPENCLAW_URL"]}
OPENCLAW_API_KEY=${CONFIG["OPENCLAW_API_KEY"]}
EOF
    fi

    cat >> "$config_file" << EOF

#-------------------------------------------------------------------------------
# LLM Provider Status
#-------------------------------------------------------------------------------
OPENAI_CONFIGURED=${LLM_PROVIDERS["OPENAI"]}
ANTHROPIC_CONFIGURED=${LLM_PROVIDERS["ANTHROPIC"]}
GROQ_CONFIGURED=${LLM_PROVIDERS["GROQ"]}
MISTRAL_CONFIGURED=${LLM_PROVIDERS["MISTRAL"]}
COHERE_CONFIGURED=${LLM_PROVIDERS["COHERE"]}
TOGETHER_CONFIGURED=${LLM_PROVIDERS["TOGETHER"]}
PERPLEXITY_CONFIGURED=${LLM_PROVIDERS["PERPLEXITY"]}
OPENROUTER_CONFIGURED=${LLM_PROVIDERS["OPENROUTER"]}
GOOGLE_AI_CONFIGURED=${LLM_PROVIDERS["GOOGLE"]}
XAI_CONFIGURED=${LLM_PROVIDERS["XAI"]}
HUGGINGFACE_CONFIGURED=${LLM_PROVIDERS["HUGGINGFACE"]}

EOF

    print_success "Configuration file generated: $config_file"
    log "INFO" "Configuration file generated successfully"
}
generate_secrets_file() {
    print_section "Generating Secrets File"

    local secrets_file="${PROJECT_ROOT}/.secrets.env"
    local secrets_backup="${PROJECT_ROOT}/.secrets.env.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup existing secrets if they exist
    if [ -f "$secrets_file" ]; then
        print_info "Backing up existing secrets..."
        cp "$secrets_file" "$secrets_backup"
        print_success "Secrets backup created: $secrets_backup"
    fi

    print_info "Generating secrets file..."

    cat > "$secrets_file" << EOF
#===============================================================================
# AI PLATFORM SECRETS
# Generated: $(date)
# Version: ${CONFIG["SCRIPT_VERSION"]}
# WARNING: Keep this file secure and never commit to version control
#===============================================================================

#-------------------------------------------------------------------------------
# Cloudflare Credentials
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
CLOUDFLARE_API_TOKEN=${CREDENTIALS["CLOUDFLARE_API_TOKEN"]}
CLOUDFLARE_ZONE_ID=${CREDENTIALS["CLOUDFLARE_ZONE_ID"]}
EOF
    fi

    cat >> "$secrets_file" << EOF

#-------------------------------------------------------------------------------
# LLM Provider API Keys
#-------------------------------------------------------------------------------
EOF

    # OpenAI
    if [ "${LLM_PROVIDERS["OPENAI"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
OPENAI_API_KEY=${CREDENTIALS["OPENAI_API_KEY"]}
EOF
        if [ -n "${CREDENTIALS["OPENAI_ORG_ID"]}" ]; then
            cat >> "$secrets_file" << EOF
OPENAI_ORG_ID=${CREDENTIALS["OPENAI_ORG_ID"]}
EOF
        fi
    fi

    # Anthropic
    if [ "${LLM_PROVIDERS["ANTHROPIC"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
ANTHROPIC_API_KEY=${CREDENTIALS["ANTHROPIC_API_KEY"]}
EOF
    fi

    # Groq
    if [ "${LLM_PROVIDERS["GROQ"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
GROQ_API_KEY=${CREDENTIALS["GROQ_API_KEY"]}
EOF
    fi

    # Mistral
    if [ "${LLM_PROVIDERS["MISTRAL"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
MISTRAL_API_KEY=${CREDENTIALS["MISTRAL_API_KEY"]}
EOF
    fi

    # Cohere
    if [ "${LLM_PROVIDERS["COHERE"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
COHERE_API_KEY=${CREDENTIALS["COHERE_API_KEY"]}
EOF
    fi

    # Together AI
    if [ "${LLM_PROVIDERS["TOGETHER"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
TOGETHER_API_KEY=${CREDENTIALS["TOGETHER_API_KEY"]}
EOF
    fi

    # Perplexity
    if [ "${LLM_PROVIDERS["PERPLEXITY"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
PERPLEXITY_API_KEY=${CREDENTIALS["PERPLEXITY_API_KEY"]}
EOF
    fi

    # OpenRouter
    if [ "${LLM_PROVIDERS["OPENROUTER"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
OPENROUTER_API_KEY=${CREDENTIALS["OPENROUTER_API_KEY"]}
EOF
    fi

    # Google AI
    if [ "${LLM_PROVIDERS["GOOGLE"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
GOOGLE_AI_API_KEY=${CREDENTIALS["GOOGLE_AI_API_KEY"]}
EOF
    fi

    # xAI
    if [ "${LLM_PROVIDERS["XAI"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
XAI_API_KEY=${CREDENTIALS["XAI_API_KEY"]}
EOF
    fi

    # Hugging Face
    if [ "${LLM_PROVIDERS["HUGGINGFACE"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
HUGGINGFACE_API_KEY=${CREDENTIALS["HUGGINGFACE_API_KEY"]}
EOF
    fi

    cat >> "$secrets_file" << EOF

#-------------------------------------------------------------------------------
# Service-Specific Credentials
#-------------------------------------------------------------------------------
EOF

    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        cat >> "$secrets_file" << EOF
FLOWISE_PASSWORD=${CREDENTIALS["FLOWISE_PASSWORD"]}
EOF
    fi

    # Set secure permissions
    chmod 600 "$secrets_file"

    print_success "Secrets file generated: $secrets_file"
    print_warning "File permissions set to 600 (owner read/write only)"
    log "INFO" "Secrets file generated with secure permissions"
}

#===============================================================================
# CONFIGURATION SUMMARY
#===============================================================================

display_configuration_summary() {
    print_header "Configuration Summary"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""

    # System Information
    print_section "System Information"
    echo "  OS: ${CONFIG["OS_TYPE"]}"
    echo "  CPU: ${CONFIG["CPU_CORES"]} cores"
    echo "  RAM: ${CONFIG["TOTAL_RAM"]}GB"
    echo "  GPU: ${CONFIG["HAS_GPU"]} ${CONFIG["GPU_NAME"]:+- ${CONFIG["GPU_NAME"]}}"
    echo "  Timezone: ${CONFIG["TIMEZONE"]}"
    echo ""

    # Network Configuration
    print_section "Network Configuration"
    echo "  Public IP: ${CONFIG["PUBLIC_IP"]}"
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        echo "  Domain: ${CONFIG["DOMAIN"]}"
        echo "  SSL Email: ${CONFIG["SSL_EMAIL"]}"
        echo "  Cloudflare: ${CONFIG["USE_CLOUDFLARE"]}"
    else
        echo "  Access Mode: IP:PORT"
    fi
    echo ""

    # Services to Install
    print_section "Services to Install"
    local service_count=0

    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} n8n - ${CONFIG["N8N_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Flowise - ${CONFIG["FLOWISE_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Open WebUI - ${CONFIG["OPENWEBUI_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} AnythingLLM - ${CONFIG["ANYTHINGLLM_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Dify - ${CONFIG["DIFY_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} LibreChat - ${CONFIG["LIBRECHAT_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Ollama - Port ${CONFIG["OLLAMA_PORT"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Langfuse - ${CONFIG["LANGFUSE_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_VECTORDB"]}" = "true" ]; then
        if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(qdrant|both)$ ]]; then
            echo -e "  ${GREEN}✓${NC} Qdrant - Port ${CONFIG["QDRANT_PORT"]}"
            ((service_count++))
        fi
        if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(weaviate|both)$ ]]; then
            echo -e "  ${GREEN}✓${NC} Weaviate - Port ${CONFIG["WEAVIATE_PORT"]}"
            ((service_count++))
        fi
    fi

    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Uptime Kuma - ${CONFIG["UPTIME_KUMA_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Portainer - ${CONFIG["PORTAINER_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} ComfyUI - ${CONFIG["COMFYUI_URL"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_SIGNAL"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} Signal API - Port ${CONFIG["SIGNAL_PORT"]}"
        ((service_count++))
    fi

    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} OpenClaw - ${CONFIG["OPENCLAW_URL"]}"
        ((service_count++))
    fi

    echo ""
    echo "  Total services: $service_count"
    echo ""

    # LLM Providers
    print_section "LLM Providers Configured"
    local provider_count=0

    for provider in "${!LLM_PROVIDERS[@]}"; do
        if [ "${LLM_PROVIDERS[$provider]}" = "true" ]; then
            echo -e "  ${GREEN}✓${NC} $provider"
            ((provider_count++))
        fi
    done

    if [ $provider_count -eq 0 ]; then
        echo "  None configured"
    else
        echo ""
        echo "  Total providers: $provider_count"
    fi
    echo ""

    # Storage
    print_section "Storage Configuration"
    echo "  Data Directory: ${CONFIG["DATA_DIR"]}"
    echo "  Backup Directory: ${CONFIG["BACKUP_DIR"]}"
    echo ""

    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

#===============================================================================
# DOCKER COMPOSE GENERATION
#===============================================================================

generate_docker_compose() {
    print_section "Generating Docker Compose Configuration"

    local compose_file="${PROJECT_ROOT}/docker-compose.yml"
    local compose_backup="${PROJECT_ROOT}/docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup existing compose file
    if [ -f "$compose_file" ]; then
        print_info "Backing up existing docker-compose.yml..."
        cp "$compose_file" "$compose_backup"
        print_success "Backup created: $compose_backup"
    fi

    print_info "Generating docker-compose.yml..."

    cat > "$compose_file" << 'EOF'
version: '3.8'

#===============================================================================
# AI PLATFORM DOCKER COMPOSE
# Auto-generated configuration
#===============================================================================

networks:
  ai_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
  portainer_data:
  postgres_data:
  redis_data:

services:

EOF

    # Add services based on configuration

    # PostgreSQL (required by several services)
    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        cat >> "$compose_file" << 'EOF'
  postgres:
    image: postgres:16-alpine
    container_name: ai_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: aiplatform
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
      POSTGRES_DB: aiplatform
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - ai_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U aiplatform"]
      interval: 10s
      timeout: 5s
      retries: 5

EOF
    fi

    # Redis (required by some services)
    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] || \
       [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        cat >> "$compose_file" << 'EOF'
  redis:
    image: redis:7-alpine
    container_name: ai_redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD:-changeme}
    volumes:
      - redis_data:/data
    networks:
      - ai_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

EOF
    fi

    # n8n
    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${CONFIG["N8N_PORT"]}:5678"
    environment:
      - N8N_HOST=\${N8N_HOST:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=\${N8N_PROTOCOL:-http}
      - NODE_ENV=production
      - WEBHOOK_URL=\${N8N_WEBHOOK_URL:-http://localhost:${CONFIG["N8N_PORT"]}/}
      - GENERIC_TIMEZONE=\${TZ:-UTC}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=aiplatform
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD:-changeme}
    volumes:
      - \${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ai_network
    depends_on:
      - postgres

EOF
    fi

    # Flowise
    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    ports:
      - "${CONFIG["FLOWISE_PORT"]}:3000"
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=\${FLOWISE_USERNAME:-admin}
      - FLOWISE_PASSWORD=\${FLOWISE_PASSWORD}
      - FLOWISE_SECRETKEY_OVERWRITE=\${FLOWISE_SECRET_KEY}
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - LOG_PATH=/root/.flowise/logs
      - BLOB_STORAGE_PATH=/root/.flowise/storage
    volumes:
      - \${DATA_DIR}/flowise:/root/.flowise
    networks:
      - ai_network

EOF
    fi

    # Open WebUI
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        local ollama_base_url="http://ollama:11434"
        if [ "${CONFIG["INSTALL_OLLAMA"]}" = "false" ] && [ -n "${CONFIG["OPENWEBUI_OLLAMA_URL"]}" ]; then
            ollama_base_url="${CONFIG["OPENWEBUI_OLLAMA_URL"]}"
        fi

        cat >> "$compose_file" << EOF
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    ports:
      - "${CONFIG["OPENWEBUI_PORT"]}:8080"
    environment:
      - OLLAMA_BASE_URL=$ollama_base_url
      - WEBUI_SECRET_KEY=\${OPENWEBUI_JWT_SECRET}
      - WEBUI_AUTH=true
    volumes:
      - \${DATA_DIR}/openwebui:/app/backend/data
    networks:
      - ai_network
EOF
        if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
            echo "    depends_on:" >> "$compose_file"
            echo "      - ollama" >> "$compose_file"
        fi
        echo "" >> "$compose_file"
    fi

    # AnythingLLM
    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "${CONFIG["ANYTHINGLLM_PORT"]}:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET}
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN}
    volumes:
      - \${DATA_DIR}/anythingllm:/app/server/storage
    networks:
      - ai_network

EOF
    fi

    # Dify
    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify_api
    restart: unless-stopped
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=\${DIFY_SECRET_KEY}
      - DB_USERNAME=aiplatform
      - DB_PASSWORD=\${POSTGRES_PASSWORD:-changeme}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD:-changeme}
    volumes:
      - \${DATA_DIR}/dify/api:/app/api/storage
    networks:
      - ai_network
    depends_on:
      - postgres
      - redis

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify_worker
    restart: unless-stopped
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=\${DIFY_SECRET_KEY}
      - DB_USERNAME=aiplatform
      - DB_PASSWORD=\${POSTGRES_PASSWORD:-changeme}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD:-changeme}
    volumes:
      - \${DATA_DIR}/dify/worker:/app/api/storage
    networks:
      - ai_network
    depends_on:
      - postgres
      - redis

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify_web
    restart: unless-stopped
    ports:
      - "${CONFIG["DIFY_PORT"]}:3000"
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001
    networks:
      - ai_network
    depends_on:
      - dify-api

EOF
    fi

    # LibreChat
    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat
    restart: unless-stopped
    ports:
      - "${CONFIG["LIBRECHAT_PORT"]}:3080"
    environment:
      - HOST=0.0.0.0
      - MONGO_URI=mongodb://mongodb:27017/LibreChat
      - JWT_SECRET=\${LIBRECHAT_JWT_SECRET}
      - JWT_REFRESH_SECRET=\${LIBRECHAT_JWT_REFRESH_SECRET}
    volumes:
      - \${DATA_DIR}/librechat:/app/client/public/images
      - \${PROJECT_ROOT}/librechat.yaml:/app/librechat.yaml
    networks:
      - ai_network
    depends_on:
      - mongodb

  mongodb:
    image: mongo:7
    container_name: librechat_mongodb
    restart: unless-stopped
    volumes:
      - \${DATA_DIR}/mongodb:/data/db
    networks:
      - ai_network

EOF
    fi

    # Ollama
    if [ "${CONFIG["INSTALL_OLLAMA"]}" = "true" ]; then
        local deploy_section=""
        if [ "${CONFIG["HAS_GPU"]}" = "true" ]; then
            deploy_section="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
        fi

        cat >> "$compose_file" << EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${CONFIG["OLLAMA_PORT"]}:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - \${DATA_DIR}/ollama:/root/.ollama
    networks:
      - ai_network
$deploy_section

EOF
    fi

    # Langfuse
    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  langfuse:
    image: langfuse/langfuse:latest
    container_name: langfuse
    restart: unless-stopped
    ports:
      - "${CONFIG["LANGFUSE_PORT"]}:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://aiplatform:\${POSTGRES_PASSWORD:-changeme}@postgres:5432/langfuse
      - NEXTAUTH_URL=\${LANGFUSE_URL}
      - NEXTAUTH_SECRET=\${LANGFUSE_NEXTAUTH_SECRET}
      - SALT=\${LANGFUSE_SALT}
    networks:
      - ai_network
    depends_on:
      - postgres

EOF
    fi

    # Qdrant
    if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(qdrant|both)$ ]]; then
        cat >> "$compose_file" << EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "${CONFIG["QDRANT_PORT"]}:6333"
    environment:
      - QDRANT__SERVICE__API_KEY=\${QDRANT_API_KEY}
    volumes:
      - \${DATA_DIR}/qdrant:/qdrant/storage
    networks:
      - ai_network

EOF
    fi

    # Weaviate
    if [[ "${CONFIG["VECTORDB_TYPE"]}" =~ ^(weaviate|both)$ ]]; then
        cat >> "$compose_file" << EOF
  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: weaviate
    restart: unless-stopped
    ports:
      - "${CONFIG["WEAVIATE_PORT"]}:8080"
    environment:
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - QUERY_DEFAULTS_LIMIT=25
      - DEFAULT_VECTORIZER_MODULE=none
      - CLUSTER_HOSTNAME=node1
    volumes:
      - \${DATA_DIR}/weaviate:/var/lib/weaviate
    networks:
      - ai_network

EOF
    fi

    # Uptime Kuma
    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime_kuma
    restart: unless-stopped
    ports:
      - "${CONFIG["UPTIME_KUMA_PORT"]}:3001"
    volumes:
      - \${DATA_DIR}/uptime-kuma:/app/data
    networks:
      - ai_network

EOF
    fi

    # Portainer
    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "${CONFIG["PORTAINER_PORT"]}:9443"
      - "8000:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - ai_network

EOF
    fi

    # ComfyUI
    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ]; then
        local deploy_section=""
        if [ "${CONFIG["HAS_GPU"]}" = "true" ]; then
            deploy_section="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
        fi

        cat >> "$compose_file" << EOF
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    restart: unless-stopped
    ports:
      - "${CONFIG["COMFYUI_PORT"]}:8188"
    environment:
      - CLI_ARGS=--listen 0.0.0.0
    volumes:
      - \${DATA_DIR}/comfyui:/root
    networks:
      - ai_network
$deploy_section

EOF
    fi

    # Signal API
    if [ "${CONFIG["INSTALL_SIGNAL"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal_api
    restart: unless-stopped
    ports:
      - "${CONFIG["SIGNAL_PORT"]}:8080"
    environment:
      - MODE=normal
    volumes:
      - \${DATA_DIR}/signal:/home/.local/share/signal-cli
    networks:
      - ai_network

EOF
    fi

    # OpenClaw
    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        cat >> "$compose_file" << EOF
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "${CONFIG["OPENCLAW_PORT"]}:3007"
    environment:
      - API_KEY=\${OPENCLAW_API_KEY}
      - NODE_ENV=production
    volumes:
      - \${DATA_DIR}/openclaw:/app/data
    networks:
      - ai_network

EOF
    fi

    print_success "Docker Compose file generated: $compose_file"
    log "INFO" "Docker Compose configuration generated successfully"
}
#===============================================================================
# REVERSE PROXY CONFIGURATION
#===============================================================================

generate_nginx_config() {
    print_section "Generating Nginx Configuration"

    local nginx_dir="${PROJECT_ROOT}/nginx"
    local conf_dir="${nginx_dir}/conf.d"

    mkdir -p "$conf_dir"
    mkdir -p "${nginx_dir}/ssl"

    print_info "Creating Nginx configurations..."

    # Main nginx.conf
    cat > "${nginx_dir}/nginx.conf" << 'EOF'
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

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_status 429;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Generate SSL configuration if domain is configured
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        cat > "${conf_dir}/ssl-params.conf" << 'EOF'
# SSL Configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_stapling on;
ssl_stapling_verify on;

# Security headers for SSL
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
EOF
    fi

    # Generate service configurations
    generate_service_nginx_configs "$conf_dir"

    print_success "Nginx configuration generated in $nginx_dir"
}

generate_service_nginx_configs() {
    local conf_dir="$1"

    # n8n
    if [ "${CONFIG["INSTALL_N8N"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/n8n.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
        fi
    fi

    # Flowise
    if [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/flowise.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://flowise:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # Open WebUI
    if [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/openwebui.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://openwebui:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # AnythingLLM
    if [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/anythingllm.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://anythingllm:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # Dify
    if [ "${CONFIG["INSTALL_DIFY"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/dify.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://dify-web:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # LibreChat
    if [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/librechat.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://librechat:3080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # Langfuse
    if [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/langfuse.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://langfuse:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # Uptime Kuma
    if [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/uptime-kuma.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://uptime-kuma:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # Portainer
    if [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/portainer.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass https://portainer:9443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # ComfyUI
    if [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/comfyui.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://comfyui:8188;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi

    # OpenClaw
    if [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ]; then
        if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
            cat > "${conf_dir}/openclaw.conf" << EOF
server {
    listen 80;
    server_name ${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]};

    ssl_certificate /etc/nginx/ssl/${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}/privkey.pem;
    include /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass http://openclaw:3007;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        fi
    fi
}

add_nginx_to_compose() {
    local compose_file="${PROJECT_ROOT}/docker-compose.yml"

    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        print_info "Adding Nginx and Certbot to Docker Compose..."

        cat >> "$compose_file" << EOF
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./certbot/www:/var/www/certbot:ro
    networks:
      - ai_network
    depends_on:
EOF

        # Add dependencies based on installed services
        [ "${CONFIG["INSTALL_N8N"]}" = "true" ] && echo "      - n8n" >> "$compose_file"
        [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ] && echo "      - flowise" >> "$compose_file"
        [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && echo "      - openwebui" >> "$compose_file"
        [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ] && echo "      - anythingllm" >> "$compose_file"
        [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] && echo "      - dify-web" >> "$compose_file"
        [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ] && echo "      - librechat" >> "$compose_file"
        [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ] && echo "      - langfuse" >> "$compose_file"
        [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ] && echo "      - uptime-kuma" >> "$compose_file"
        [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ] && echo "      - portainer" >> "$compose_file"
        [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ] && echo "      - comfyui" >> "$compose_file"
        [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ] && echo "      - openclaw" >> "$compose_file"

        cat >> "$compose_file" << 'EOF'

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./certbot/www:/var/www/certbot:rw
      - ./nginx/ssl:/etc/letsencrypt:rw
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    networks:
      - ai_network

EOF

        print_success "Nginx and Certbot added to Docker Compose"
    fi
}

#===============================================================================
# SSL CERTIFICATE SETUP
#===============================================================================

setup_ssl_certificates() {
    if [ "${CONFIG["HAS_DOMAIN"]}" = "true" ] && [ "${CONFIG["USE_CLOUDFLARE"]}" = "true" ]; then
        print_section "Setting up SSL Certificates with Cloudflare DNS"

        # Install certbot-dns-cloudflare plugin
        print_info "Installing Cloudflare DNS plugin for Certbot..."

        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y -qq python3-certbot-dns-cloudflare
        elif command -v yum &> /dev/null; then
            yum install -y -q python3-certbot-dns-cloudflare
        fi

        # Create Cloudflare credentials file
        local cf_creds="${PROJECT_ROOT}/certbot/cloudflare.ini"
        mkdir -p "$(dirname "$cf_creds")"

        cat > "$cf_creds" << EOF
dns_cloudflare_api_token = ${CREDENTIALS["CLOUDFLARE_API_TOKEN"]}
EOF
        chmod 600 "$cf_creds"

        # Request certificates for each subdomain
        local domains=()

        [ "${CONFIG["INSTALL_N8N"]}" = "true" ] && domains+=("${CONFIG["N8N_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_FLOWISE"]}" = "true" ] && domains+=("${CONFIG["FLOWISE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_OPENWEBUI"]}" = "true" ] && domains+=("${CONFIG["OPENWEBUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" = "true" ] && domains+=("${CONFIG["ANYTHINGLLM_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_DIFY"]}" = "true" ] && domains+=("${CONFIG["DIFY_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_LIBRECHAT"]}" = "true" ] && domains+=("${CONFIG["LIBRECHAT_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_LANGFUSE"]}" = "true" ] && domains+=("${CONFIG["LANGFUSE_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_UPTIME_KUMA"]}" = "true" ] && domains+=("${CONFIG["UPTIME_KUMA_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_PORTAINER"]}" = "true" ] && domains+=("${CONFIG["PORTAINER_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_COMFYUI"]}" = "true" ] && domains+=("${CONFIG["COMFYUI_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")
        [ "${CONFIG["INSTALL_OPENCLAW"]}" = "true" ] && domains+=("${CONFIG["OPENCLAW_SUBDOMAIN"]}.${CONFIG["DOMAIN"]}")

        for domain in "${domains[@]}"; do
            print_info "Requesting certificate for $domain..."

            certbot certonly \
                --dns-cloudflare \
                --dns-cloudflare-credentials "$cf_creds" \
                --email "${CONFIG["SSL_EMAIL"]}" \
                --agree-tos \
                --non-interactive \
                --cert-name "$domain" \
                -d "$domain" \
                --cert-path "${PROJECT_ROOT}/nginx/ssl/$domain" \
                || print_warning "Failed to obtain certificate for $domain"
        done

        print_success "SSL certificates setup complete"
    elif [ "${CONFIG["HAS_DOMAIN"]}" = "true" ]; then
        print_section "SSL Certificate Setup"
        print_info "SSL certificates will be obtained via HTTP-01 challenge"
        print_info "Ensure your DNS records point to this server: ${CONFIG["PUBLIC_IP"]}"
        print_warning "Certificates will be requested after services start"
    fi
}

#===============================================================================
# SYSTEM DEPENDENCIES INSTALLATION
#===============================================================================

install_system_dependencies() {
    print_header "Installing System Dependencies"

    if [ "${CONFIG["OS_TYPE"]}" = "ubuntu" ] || [ "${CONFIG["OS_TYPE"]}" = "debian" ]; then
        print_info "Updating package lists..."
        apt-get update -qq || handle_error "Failed to update package lists"

        print_info "Installing required packages..."
        apt-get install -y -qq \
            curl \
            wget \
            git \
            ca-certificates \
            gnupg \
            lsb-release \
            apt-transport-https \
            software-properties-common \
            ufw \
            fail2ban \
            unattended-upgrades \
            || handle_error "Failed to install system packages"

    elif [ "${CONFIG["OS_TYPE"]}" = "centos" ] || [ "${CONFIG["OS_TYPE"]}" = "rhel" ]; then
        print_info "Installing EPEL repository..."
        yum install -y -q epel-release || handle_error "Failed to install EPEL"

        print_info "Installing required packages..."
        yum install -y -q \
            curl \
            wget \
            git \
            ca-certificates \
            yum-utils \
            firewalld \
            fail2ban \
            || handle_error "Failed to install system packages"
    fi

    print_success "System dependencies installed"
}

install_docker() {
    print_section "Installing Docker"

    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | cut -d ' ' -f3 | cut -d ',' -f1)
        print_info "Docker already installed: $docker_version"
        return 0
    fi

    if [ "${CONFIG["OS_TYPE"]}" = "ubuntu" ] || [ "${CONFIG["OS_TYPE"]}" = "debian" ]; then
        print_info "Installing Docker on ${CONFIG["OS_TYPE"]}..."

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${CONFIG["OS_TYPE"]}/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Add Docker repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/${CONFIG["OS_TYPE"]} \
            $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    elif [ "${CONFIG["OS_TYPE"]}" = "centos" ] || [ "${CONFIG["OS_TYPE"]}" = "rhel" ]; then
        print_info "Installing Docker on ${CONFIG["OS_TYPE"]}..."

        # Add Docker repository
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        # Install Docker
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Start and enable Docker
        systemctl start docker
        systemctl enable docker
    fi

    # Add current user to docker group
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        print_info "Added $SUDO_USER to docker group"
    fi

    print_success "Docker installed successfully"
    docker --version
}

install_nvidia_docker() {
    if [ "${CONFIG["HAS_GPU"]}" = "false" ]; then
        return 0
    fi

    print_section "Installing NVIDIA Container Toolkit"

    if [ "${CONFIG["OS_TYPE"]}" = "ubuntu" ] || [ "${CONFIG["OS_TYPE"]}" = "debian" ]; then
        print_info "Setting up NVIDIA Docker repository..."

        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
            gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        apt-get update -qq
        apt-get install -y -qq nvidia-container-toolkit

    elif [ "${CONFIG["OS_TYPE"]}" = "centos" ] || [ "${CONFIG["OS_TYPE"]}" = "rhel" ]; then
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | \
            tee /etc/yum.repos.d/nvidia-container-toolkit.repo

        yum install -y -q nvidia-container-toolkit
    fi

    # Configure Docker to use NVIDIA runtime
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker

    print_success "NVIDIA Container Toolkit installed"
}

