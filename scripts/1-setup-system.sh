#!/bin/bash
#===============================================================================
# AI Platform Automation - Script 1: System Setup & Configuration Collection
#===============================================================================
# Purpose: Collect all configuration, validate dependencies, prepare environment
# Author: AI Platform Automation
# Version: 3.0.0
# Branch: main
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

#===============================================================================
# CONSTANTS & GLOBALS
#===============================================================================

readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="/root/scripts"
readonly DATA_DIR="/mnt/data"
readonly LOG_DIR="${BASE_DIR}/logs"
readonly CONFIG_FILE="${BASE_DIR}/.env.master"
readonly STATE_FILE="${BASE_DIR}/.setup_state"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USER_CANCEL=2
readonly EXIT_VALIDATION_FAILED=3

# Global associative arrays
declare -A CONFIG=(
    ["INSTALL_POSTGRES"]="false"
    ["INSTALL_N8N"]="false"
    ["INSTALL_FLOWISE"]="false"
    ["INSTALL_LITELLM"]="false"
    ["INSTALL_OLLAMA"]="false"
    ["INSTALL_LANGFUSE"]="false"
    ["INSTALL_DIFY"]="false"
    ["INSTALL_OPENWEBUI"]="false"
    ["INSTALL_ANYTHINGLLM"]="false"
    ["INSTALL_OPENCLAW"]="false"
    ["INSTALL_MINIO"]="false"
    ["INSTALL_SIGNAL_API"]="false"
    ["INSTALL_TAILSCALE"]="false"
    ["INSTALL_VECTORDB"]="false"
    ["GDRIVE_ENABLED"]="false"
    ["USE_DOMAIN"]="false"
)

declare -A CREDENTIALS=()
declare -A LLM_PROVIDERS=()
declare -a SELECTED_SERVICES=()

#===============================================================================
# SIGNAL HANDLING
#===============================================================================

trap cleanup_on_exit EXIT
trap handle_interrupt INT TERM

cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ $exit_code -ne $EXIT_USER_CANCEL ]; then
        log "ERROR" "Script exited with error code: $exit_code"
        echo -e "\n${RED}Setup interrupted or failed. Check log: ${LOG_FILE}${NC}"
    fi
}

handle_interrupt() {
    echo -e "\n${YELLOW}⚠️  Setup interrupted by user${NC}"
    log "WARN" "User interrupted setup"
    exit $EXIT_USER_CANCEL
}

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    log "INFO" "$1"
}

print_section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}\n"
    log "INFO" "Section: $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "INFO" "Success: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARN" "$1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log "INFO" "$1"
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit $EXIT_ERROR
    fi
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra ADDR <<< "$ip"
        [[ ${ADDR[0]} -le 255 && ${ADDR[1]} -le 255 && ${ADDR[2]} -le 255 && ${ADDR[3]} -le 255 ]]
        return $?
    fi
    return 1
}

validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    return 1
}

validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_phone() {
    local phone=$1
    if [[ $phone =~ ^\+[0-9]{10,15}$ ]]; then
        return 0
    fi
    return 1
}

check_port_available() {
    local port=$1
    if command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

check_dependencies() {
    print_section "Checking System Dependencies"
    
    local missing_deps=()
    local deps=(
        "curl"
        "wget"
        "git"
        "jq"
        "openssl"
        "gpg"
        "systemctl"
    )
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
            print_warning "Missing: $dep"
        else
            print_success "Found: $dep"
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        read -p "Install missing dependencies now? (y/n): " install_deps
        if [[ $install_deps =~ ^[Yy]$ ]]; then
            apt-get update
            apt-get install -y "${missing_deps[@]}"
            print_success "Dependencies installed"
        else
            print_error "Cannot proceed without required dependencies"
            exit $EXIT_ERROR
        fi
    else
        print_success "All dependencies satisfied"
    fi
}

check_disk_space() {
    print_section "Checking Disk Space"
    
    local required_space_gb=50
    local available_space_gb
    available_space_gb=$(df -BG "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ -z "$available_space_gb" ]; then
        print_warning "Could not determine disk space"
        return
    fi
    
    print_info "Available space: ${available_space_gb}GB"
    print_info "Required space: ${required_space_gb}GB"
    
    if [ "$available_space_gb" -lt "$required_space_gb" ]; then
        print_warning "Low disk space. Recommended: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        read -p "Continue anyway? (y/n): " continue_low_space
        if [[ ! $continue_low_space =~ ^[Yy]$ ]]; then
            exit $EXIT_USER_CANCEL
        fi
    else
        print_success "Sufficient disk space available"
    fi
}

detect_public_ip() {
    print_section "Detecting Public IP"
    
    local ip
    ip=$(curl -s -4 --max-time 5 icanhazip.com || curl -s -4 --max-time 5 ifconfig.me || curl -s -4 --max-time 5 api.ipify.org || echo "")
    
    if [ -n "$ip" ] && validate_ip "$ip"; then
        CONFIG["PUBLIC_IP"]=$ip
        print_success "Detected public IP: $ip"
    else
        print_warning "Could not auto-detect public IP"
        while true; do
            read -p "Enter public IP manually: " manual_ip
            if validate_ip "$manual_ip"; then
                CONFIG["PUBLIC_IP"]=$manual_ip
                print_success "Using IP: $manual_ip"
                break
            else
                print_error "Invalid IP address format"
            fi
        done
    fi
}

detect_gpu() {
    print_section "Detecting GPU"
    
    if lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
        if command -v nvidia-smi &> /dev/null; then
            print_success "NVIDIA GPU detected with drivers"
            CONFIG["OLLAMA_GPU_ENABLED"]="true"
        else
            print_warning "NVIDIA GPU detected but drivers not installed"
            CONFIG["OLLAMA_GPU_ENABLED"]="false"
            print_info "NVIDIA Docker runtime can be installed in Script 2"
        fi
    else
        print_info "No NVIDIA GPU detected, using CPU mode"
        CONFIG["OLLAMA_GPU_ENABLED"]="false"
    fi
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

generate_secret() {
    openssl rand -hex 32
}

save_state() {
    declare -p CONFIG CREDENTIALS LLM_PROVIDERS SELECTED_SERVICES > "$STATE_FILE" 2>/dev/null || true
    log "INFO" "State saved to $STATE_FILE"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        log "INFO" "State loaded from $STATE_FILE"
        return 0
    fi
    return 1
}

#===============================================================================
# NETWORK CONFIGURATION
#===============================================================================

configure_network() {
    print_header "Network Configuration"
    
    # Domain or IP
    read -p "Do you have a domain name? (y/n): " has_domain
    if [[ $has_domain =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter domain name (e.g., ai.example.com): " domain
            if validate_domain "$domain"; then
                CONFIG["DOMAIN"]=$domain
                CONFIG["USE_DOMAIN"]="true"
                print_success "Domain: $domain"
                break
            else
                print_error "Invalid domain format"
            fi
        done
    else
        CONFIG["USE_DOMAIN"]="false"
        CONFIG["DOMAIN"]=""
        print_info "Will use IP-based access: ${CONFIG["PUBLIC_IP"]}"
    fi
    
    # SSL Configuration
    if [[ "${CONFIG["USE_DOMAIN"]}" == "true" ]]; then
        echo ""
        echo "SSL Certificate Options:"
        echo "  1) Let's Encrypt - Free, auto-renewal (RECOMMENDED)"
        echo "  2) Self-signed - For testing/internal use"
        echo ""
        read -p "Select SSL mode (1-2): " ssl_choice
        
        case $ssl_choice in
            1)
                CONFIG["SSL_MODE"]="letsencrypt"
                while true; do
                    read -p "Enter email for Let's Encrypt notifications: " le_email
                    if validate_email "$le_email"; then
                        CONFIG["SSL_EMAIL"]=$le_email
                        print_success "Let's Encrypt enabled"
                        break
                    else
                        print_error "Invalid email format"
                    fi
                done
                ;;
            2)
                CONFIG["SSL_MODE"]="selfsigned"
                print_info "Will use self-signed certificates"
                ;;
            *)
                print_error "Invalid choice, using self-signed"
                CONFIG["SSL_MODE"]="selfsigned"
                ;;
        esac
    else
        CONFIG["SSL_MODE"]="selfsigned"
        CONFIG["SSL_EMAIL"]=""
        print_info "Will use self-signed certificates for IP access"
    fi
    
    # Proxy Selection
    print_section "Reverse Proxy Selection"
    
    echo "Select reverse proxy:"
    echo "  1) Caddy - Automatic HTTPS, simpler configuration (RECOMMENDED)"
    echo "  2) Nginx - Traditional, more control"
    echo ""
    
    read -p "Enter choice (1-2): " proxy_choice
    
    case $proxy_choice in
        1)
            CONFIG["PROXY_TYPE"]="caddy"
            print_success "Selected: Caddy"
            ;;
        2)
            CONFIG["PROXY_TYPE"]="nginx"
            print_success "Selected: Nginx"
            ;;
        *)
            print_error "Invalid choice, defaulting to Caddy"
            CONFIG["PROXY_TYPE"]="caddy"
            ;;
    esac
    
    # Port Configuration
    print_section "Port Configuration"
    
    CONFIG["PROXY_HTTP_PORT"]="80"
    CONFIG["PROXY_HTTPS_PORT"]="443"
    
    read -p "Use custom ports? (y/n): " custom_ports
    if [[ $custom_ports =~ ^[Yy]$ ]]; then
        while true; do
            read -p "HTTP port [80]: " http_port
            http_port=${http_port:-80}
            if validate_port "$http_port" && check_port_available "$http_port"; then
                CONFIG["PROXY_HTTP_PORT"]=$http_port
                break
            else
                print_error "Invalid or in-use port"
            fi
        done
        
        while true; do
            read -p "HTTPS port [443]: " https_port
            https_port=${https_port:-443}
            if validate_port "$https_port" && check_port_available "$https_port"; then
                CONFIG["PROXY_HTTPS_PORT"]=$https_port
                break
            else
                print_error "Invalid or in-use port"
            fi
        done
    fi
    
    print_success "HTTP port: ${CONFIG["PROXY_HTTP_PORT"]}"
    print_success "HTTPS port: ${CONFIG["PROXY_HTTPS_PORT"]}"
}
#===============================================================================
# SERVICE SELECTION - GROUPED
#===============================================================================

select_services() {
    print_header "AI Platform Service Selection"

    print_info "Services are organized into 3 groups:"
    echo ""

    # GROUP 1: CORE INFRASTRUCTURE
    print_section "Group 1: Core Infrastructure"
    echo "Essential services for LLM operations:"
    echo ""
    echo "  1) Ollama           - Local LLM runtime (CPU/GPU support)"
    echo "  2) LiteLLM          - Unified LLM proxy & routing"
    echo "  3) AnythingLLM      - Document chat with RAG"
    echo "  4) Tailscale        - Zero-config VPN (RECOMMENDED)"
    echo ""
    echo "  99) Install ALL Core services"
    echo "   0) Skip this group"
    echo ""

    read -p "Enter numbers (space-separated, e.g., '1 2 4') or 99 for all: " core_choices

    if [ "$core_choices" == "99" ]; then
        CONFIG["INSTALL_OLLAMA"]="true"
        CONFIG["INSTALL_LITELLM"]="true"
        CONFIG["INSTALL_ANYTHINGLLM"]="true"
        CONFIG["INSTALL_TAILSCALE"]="true"
        SELECTED_SERVICES+=("Ollama" "LiteLLM" "AnythingLLM" "Tailscale")
        print_success "Selected: ALL Core services"
    elif [ "$core_choices" != "0" ]; then
        for choice in $core_choices; do
            case $choice in
                1)
                    CONFIG["INSTALL_OLLAMA"]="true"
                    SELECTED_SERVICES+=("Ollama")
                    ;;
                2)
                    CONFIG["INSTALL_LITELLM"]="true"
                    SELECTED_SERVICES+=("LiteLLM")
                    ;;
                3)
                    CONFIG["INSTALL_ANYTHINGLLM"]="true"
                    SELECTED_SERVICES+=("AnythingLLM")
                    ;;
                4)
                    CONFIG["INSTALL_TAILSCALE"]="true"
                    SELECTED_SERVICES+=("Tailscale")
                    ;;
                *)
                    print_warning "Invalid choice: $choice"
                    ;;
            esac
        done
    fi

    # GROUP 2: AI APPLICATION STACK
    print_section "Group 2: AI Application Stack"
    echo "User-facing AI applications and orchestration:"
    echo ""
    echo "  1) N8N              - Workflow automation platform"
    echo "  2) Flowise          - Low-code LLM orchestration"
    echo "  3) Dify             - LLM app development platform"
    echo "  4) OpenWebUI        - ChatGPT-like interface"
    echo "  5) OpenClaw         - Legal document processing"
    echo ""
    echo "  99) Install ALL AI Stack services"
    echo "   0) Skip this group"
    echo ""

    read -p "Enter numbers (space-separated) or 99 for all: " stack_choices

    if [ "$stack_choices" == "99" ]; then
        CONFIG["INSTALL_N8N"]="true"
        CONFIG["INSTALL_FLOWISE"]="true"
        CONFIG["INSTALL_DIFY"]="true"
        CONFIG["INSTALL_OPENWEBUI"]="true"
        CONFIG["INSTALL_OPENCLAW"]="true"
        SELECTED_SERVICES+=("N8N" "Flowise" "Dify" "OpenWebUI" "OpenClaw")
        print_success "Selected: ALL AI Stack services"
    elif [ "$stack_choices" != "0" ]; then
        for choice in $stack_choices; do
            case $choice in
                1)
                    CONFIG["INSTALL_N8N"]="true"
                    SELECTED_SERVICES+=("N8N")
                    ;;
                2)
                    CONFIG["INSTALL_FLOWISE"]="true"
                    SELECTED_SERVICES+=("Flowise")
                    ;;
                3)
                    CONFIG["INSTALL_DIFY"]="true"
                    SELECTED_SERVICES+=("Dify")
                    ;;
                4)
                    CONFIG["INSTALL_OPENWEBUI"]="true"
                    SELECTED_SERVICES+=("OpenWebUI")
                    ;;
                5)
                    CONFIG["INSTALL_OPENCLAW"]="true"
                    SELECTED_SERVICES+=("OpenClaw")
                    ;;
                *)
                    print_warning "Invalid choice: $choice"
                    ;;
            esac
        done
    fi

    # GROUP 3: OPTIONAL SERVICES
    print_section "Group 3: Optional Services"
    echo "Monitoring, storage, and integrations:"
    echo ""
    echo "  1) Langfuse         - LLM tracing and analytics"
    echo "  2) MinIO            - S3-compatible object storage"
    echo "  3) Signal-API       - Signal messaging integration"
    echo ""
    echo "  99) Install ALL Optional services"
    echo "   0) Skip this group"
    echo ""

    read -p "Enter numbers (space-separated) or 99 for all: " optional_choices

    if [ "$optional_choices" == "99" ]; then
        CONFIG["INSTALL_LANGFUSE"]="true"
        CONFIG["INSTALL_MINIO"]="true"
        CONFIG["INSTALL_SIGNAL_API"]="true"
        SELECTED_SERVICES+=("Langfuse" "MinIO" "Signal-API")
        print_success "Selected: ALL Optional services"
    elif [ "$optional_choices" != "0" ]; then
        for choice in $optional_choices; do
            case $choice in
                1)
                    CONFIG["INSTALL_LANGFUSE"]="true"
                    SELECTED_SERVICES+=("Langfuse")
                    ;;
                2)
                    CONFIG["INSTALL_MINIO"]="true"
                    SELECTED_SERVICES+=("MinIO")
                    ;;
                3)
                    CONFIG["INSTALL_SIGNAL_API"]="true"
                    SELECTED_SERVICES+=("Signal-API")
                    ;;
                *)
                    print_warning "Invalid choice: $choice"
                    ;;
            esac
        done
    fi

    # Validation
    if [ ${#SELECTED_SERVICES[@]} -eq 0 ]; then
        print_error "No services selected"
        read -p "Retry service selection? (y/n): " retry
        if [[ $retry =~ ^[Yy]$ ]]; then
            SELECTED_SERVICES=()
            select_services
            return
        else
            print_error "Cannot proceed without services"
            exit $EXIT_USER_CANCEL
        fi
    fi

    # Auto-enable PostgreSQL if needed
    if [[ "${CONFIG["INSTALL_N8N"]}" == "true" ]] || \
       [[ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ]] || \
       [[ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ]] || \
       [[ "${CONFIG["INSTALL_DIFY"]}" == "true" ]] || \
       [[ "${CONFIG["INSTALL_OPENCLAW"]}" == "true" ]]; then
        CONFIG["INSTALL_POSTGRES"]="true"
        print_info "PostgreSQL auto-enabled (required by selected services)"
        if [[ ! " ${SELECTED_SERVICES[*]} " =~ " PostgreSQL " ]]; then
            SELECTED_SERVICES+=("PostgreSQL")
        fi
    fi

    # Summary
    echo ""
    print_success "Selected services (${#SELECTED_SERVICES[@]}):"
    for svc in "${SELECTED_SERVICES[@]}"; do
        echo "  - $svc"
    done
    echo ""

    read -p "Proceed with this selection? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        SELECTED_SERVICES=()
        # Reset all service flags
        for key in "${!CONFIG[@]}"; do
            if [[ $key == INSTALL_* ]]; then
                CONFIG[$key]="false"
            fi
        done
        select_services
    fi
}

#===============================================================================
# VECTOR DATABASE SELECTION
#===============================================================================

select_vector_db() {
    print_header "Vector Database Configuration"

    # Check if vector DB is needed
    if [[ "${CONFIG["INSTALL_OPENCLAW"]}" != "true" ]] && \
       [[ "${CONFIG["INSTALL_FLOWISE"]}" != "true" ]] && \
       [[ "${CONFIG["INSTALL_ANYTHINGLLM"]}" != "true" ]]; then
        print_info "No services requiring vector database selected"
        CONFIG["INSTALL_VECTORDB"]="false"
        return
    fi

    echo "Select vector database (required for RAG and embeddings):"
    echo ""
    echo "  1) Qdrant   - Rust-based, fastest, RECOMMENDED"
    echo "  2) Chroma   - Python-based, easy integration"
    echo "  3) Weaviate - GraphQL API, advanced features"
    echo "  0) Skip - Install vector DB later"
    echo ""

    read -p "Enter choice (0-3): " vdb_choice

    case $vdb_choice in
        1)
            CONFIG["VECTORDB_TYPE"]="qdrant"
            CONFIG["VECTORDB_PORT"]="6333"
            CONFIG["INSTALL_VECTORDB"]="true"
            CREDENTIALS["QDRANT_API_KEY"]=$(generate_secret)
            SELECTED_SERVICES+=("Qdrant")
            print_success "Selected: Qdrant"
            ;;
        2)
            CONFIG["VECTORDB_TYPE"]="chroma"
            CONFIG["VECTORDB_PORT"]="8000"
            CONFIG["INSTALL_VECTORDB"]="true"
            CREDENTIALS["CHROMA_AUTH_TOKEN"]=$(generate_secret)
            SELECTED_SERVICES+=("Chroma")
            print_success "Selected: Chroma"
            ;;
        3)
            CONFIG["VECTORDB_TYPE"]="weaviate"
            CONFIG["VECTORDB_PORT"]="8080"
            CONFIG["INSTALL_VECTORDB"]="true"
            CREDENTIALS["WEAVIATE_API_KEY"]=$(generate_secret)
            SELECTED_SERVICES+=("Weaviate")
            print_success "Selected: Weaviate"
            ;;
        0)
            CONFIG["INSTALL_VECTORDB"]="false"
            print_warning "Skipping vector database - RAG features will be limited"
            ;;
        *)
            print_error "Invalid choice"
            select_vector_db
            ;;
    esac
}

#===============================================================================
# SERVICE-SPECIFIC CONFIGURATION
#===============================================================================

configure_postgres() {
    CONFIG["POSTGRES_PORT"]="5432"
    CONFIG["POSTGRES_USER"]="postgres"
    CREDENTIALS["POSTGRES_PASSWORD"]=$(generate_password 32)
    log "INFO" "PostgreSQL configured"
}

configure_signal_api() {
    print_section "Signal-API Configuration"

    while true; do
        read -p "Enter phone number (format: +61410594574): " signal_number
        if validate_phone "$signal_number"; then
            CONFIG["SIGNAL_PHONE_NUMBER"]=$signal_number
            print_success "Phone number: $signal_number"
            break
        else
            print_error "Invalid phone number format (must start with + and contain 10-15 digits)"
        fi
    done

    CONFIG["SIGNAL_API_PORT"]="8090"

    print_info "Signal pairing QR code will be available after deployment at:"
    if [ -n "${CONFIG["DOMAIN"]}" ]; then
        echo "  https://${CONFIG["DOMAIN"]}:${CONFIG["PROXY_HTTPS_PORT"]}/signal-api/v1/qrcodelink"
    else
        echo "  https://${CONFIG["PUBLIC_IP"]}:${CONFIG["PROXY_HTTPS_PORT"]}/signal-api/v1/qrcodelink"
    fi
}

configure_tailscale() {
    print_section "Tailscale Configuration"

    print_info "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
    echo ""

    read -p "Enter Tailscale auth key: " ts_auth_key
    CONFIG["TAILSCALE_AUTH_KEY"]=$ts_auth_key

    read -p "Configure Tailscale API access? (optional, y/n): " configure_api
    if [[ $configure_api =~ ^[Yy]$ ]]; then
        print_info "Get API key from: https://login.tailscale.com/admin/settings/keys"
        read -p "Enter Tailscale API key: " ts_api_key
        CONFIG["TAILSCALE_API_KEY"]=$ts_api_key
        print_success "Tailscale API configured"
    else
        CONFIG["TAILSCALE_API_KEY"]=""
    fi

    print_success "Tailscale configured (IP will be retrieved after installation)"
}

configure_gdrive() {
    print_section "Google Drive Configuration"

    read -p "Configure Google Drive sync? (y/n): " setup_gdrive
    if [[ ! $setup_gdrive =~ ^[Yy]$ ]]; then
        CONFIG["GDRIVE_ENABLED"]="false"
        return
    fi

    CONFIG["GDRIVE_ENABLED"]="true"
    CONFIG["GDRIVE_MOUNT_PATH"]="${DATA_DIR}/gdrive"

    echo ""
    echo "Google Drive authentication methods:"
    echo "  1) Service Account JSON file (RECOMMENDED for automation)"
    echo "  2) OAuth2 URL-based authentication (interactive)"
    echo "  3) Folder ID + Shared Secret (legacy)"
    echo ""

    read -p "Select method (1-3): " gdrive_method

    case $gdrive_method in
        1)
            CONFIG["GDRIVE_AUTH_METHOD"]="service_account"
            read -p "Enter path to service account JSON file: " json_path
            if [ -f "$json_path" ]; then
                CONFIG["GDRIVE_SERVICE_ACCOUNT_JSON"]="$json_path"
                print_success "Service account JSON: $json_path"
            else
                print_error "File not found: $json_path"
                configure_gdrive
                return
            fi
            ;;
        2)
            CONFIG["GDRIVE_AUTH_METHOD"]="oauth"
            print_info "OAuth authentication will be completed in Script 2"
            print_info "You'll receive a URL to authorize access"
            ;;
        3)
            CONFIG["GDRIVE_AUTH_METHOD"]="folder_secret"
            read -p "Enter Google Drive folder ID: " folder_id
            CONFIG["GDRIVE_FOLDER_ID"]="$folder_id"
            read -p "Enter folder shared secret: " folder_secret
            CONFIG["GDRIVE_FOLDER_SECRET"]="$folder_secret"
            print_success "Folder ID configured"
            ;;
        *)
            print_error "Invalid choice"
            configure_gdrive
            return
            ;;
    esac

    read -p "Sync interval in minutes [60]: " sync_interval
    CONFIG["GDRIVE_SYNC_INTERVAL"]="${sync_interval:-60}"

    print_success "Google Drive sync configured"
}
configure_ollama() {
    print_section "Ollama Model Selection"

    CONFIG["OLLAMA_PORT"]="11434"
    CONFIG["OLLAMA_HOST"]="0.0.0.0"

    if [ "${CONFIG["OLLAMA_GPU_ENABLED"]}" == "true" ]; then
        print_info "GPU detected - models will run with GPU acceleration"
    else
        print_warning "No GPU detected - models will run on CPU (slower)"
    fi

    echo ""
    echo "Select Ollama models to download (models can be added later):"
    echo ""
    echo "  Lightweight (1-3B parameters):"
    echo "   1) llama3.2:1b               - 1.3GB"
    echo "   2) llama3.2:3b               - 2GB"
    echo "   3) phi3:mini                 - 2.3GB"
    echo ""
    echo "  Medium (7-9B parameters):"
    echo "   4) llama3.1:8b               - 4.7GB"
    echo "   5) mistral:7b                - 4.1GB"
    echo "   6) gemma2:9b                 - 5.5GB"
    echo ""
    echo "  Large (70B+ parameters, GPU REQUIRED):"
    echo "   7) llama3.1:70b              - 40GB"
    echo "   8) mixtral:8x7b              - 26GB"
    echo "   9) codellama:34b             - 19GB"
    echo ""
    echo "  Specialized:"
    echo "   10) nomic-embed-text          - 274MB (embeddings only)"
    echo "   11) llama3.1:8b-instruct-q4   - 4.7GB (quantized)"
    echo ""
    echo "   0) Skip - Install Ollama but download models later"
    echo ""

    read -p "Enter model numbers (space-separated, e.g., '1 4 10') or 0: " model_choices

    if [ "$model_choices" == "0" ]; then
        CONFIG["OLLAMA_MODELS"]="none"
        print_warning "No models selected. Install later with: ollama pull <model>"
        return
    fi

    local selected_models=()
    local total_size=0

    for choice in $model_choices; do
        case $choice in
            1)
                selected_models+=("llama3.2:1b")
                ((total_size+=2))
                ;;
            2)
                selected_models+=("llama3.2:3b")
                ((total_size+=2))
                ;;
            3)
                selected_models+=("phi3:mini")
                ((total_size+=3))
                ;;
            4)
                selected_models+=("llama3.1:8b")
                ((total_size+=5))
                ;;
            5)
                selected_models+=("mistral:7b")
                ((total_size+=5))
                ;;
            6)
                selected_models+=("gemma2:9b")
                ((total_size+=6))
                ;;
            7)
                if [ "${CONFIG["OLLAMA_GPU_ENABLED"]}" != "true" ]; then
                    print_warning "llama3.1:70b requires GPU, skipping"
                else
                    selected_models+=("llama3.1:70b")
                    ((total_size+=40))
                fi
                ;;
            8)
                if [ "${CONFIG["OLLAMA_GPU_ENABLED"]}" != "true" ]; then
                    print_warning "mixtral:8x7b requires GPU, skipping"
                else
                    selected_models+=("mixtral:8x7b")
                    ((total_size+=26))
                fi
                ;;
            9)
                if [ "${CONFIG["OLLAMA_GPU_ENABLED"]}" != "true" ]; then
                    print_warning "codellama:34b requires GPU, skipping"
                else
                    selected_models+=("codellama:34b")
                    ((total_size+=20))
                fi
                ;;
            10)
                selected_models+=("nomic-embed-text")
                ((total_size+=1))
                ;;
            11)
                selected_models+=("llama3.1:8b-instruct-q4_K_M")
                ((total_size+=5))
                ;;
            *)
                print_warning "Invalid choice: $choice"
                ;;
        esac
    done

    if [ ${#selected_models[@]} -eq 0 ]; then
        print_error "No valid models selected"
        configure_ollama
        return
    fi

    CONFIG["OLLAMA_MODELS"]=$(IFS=,; echo "${selected_models[*]}")

    print_success "Selected ${#selected_models[@]} models"
    print_warning "Estimated download size: ~${total_size}GB"
    print_info "Models will be downloaded during Script 2 deployment"
}

configure_llm_providers() {
    print_section "LLM Provider API Keys"

    print_info "Configure API keys for external LLM providers (optional)"
    print_info "Press Enter to skip any provider"
    echo ""

    local providers=(
        "OPENAI_API_KEY:OpenAI (GPT-4, GPT-3.5)"
        "ANTHROPIC_API_KEY:Anthropic (Claude)"
        "COHERE_API_KEY:Cohere"
        "MISTRAL_API_KEY:Mistral AI"
        "GROQ_API_KEY:Groq"
        "TOGETHER_API_KEY:Together AI"
        "REPLICATE_API_TOKEN:Replicate"
        "HUGGINGFACE_API_KEY:HuggingFace"
    )

    for provider in "${providers[@]}"; do
        IFS=':' read -r key_name display_name <<< "$provider"
        read -sp "Enter ${display_name} key (or press Enter to skip): " api_key
        echo ""
        if [ -n "$api_key" ]; then
            LLM_PROVIDERS["$key_name"]=$api_key
            print_success "${display_name} configured"
        fi
    done

    if [ ${#LLM_PROVIDERS[@]} -eq 0 ]; then
        print_warning "No external LLM providers configured"
        print_info "You can add them later in ${CONFIG_FILE}"
    else
        print_success "Configured ${#LLM_PROVIDERS[@]} LLM providers"
    fi
}

configure_n8n() {
    CONFIG["N8N_PORT"]="5678"

    while true; do
        read -p "Enter N8N admin email: " n8n_email
        if validate_email "$n8n_email"; then
            CREDENTIALS["N8N_ADMIN_EMAIL"]=$n8n_email
            break
        else
            print_error "Invalid email format"
        fi
    done

    CREDENTIALS["N8N_ADMIN_PASSWORD"]=$(generate_password 16)
    CREDENTIALS["N8N_ENCRYPTION_KEY"]=$(generate_secret)
    CREDENTIALS["N8N_DB_PASSWORD"]=$(generate_password 32)
    CONFIG["N8N_DB_NAME"]="n8n"

    if [ "${CONFIG["USE_DOMAIN"]}" == "true" ]; then
        CREDENTIALS["N8N_WEBHOOK_URL"]="https://${CONFIG["DOMAIN"]}:${CONFIG["PROXY_HTTPS_PORT"]}/n8n/"
    else
        CREDENTIALS["N8N_WEBHOOK_URL"]="https://${CONFIG["PUBLIC_IP"]}:${CONFIG["PROXY_HTTPS_PORT"]}/n8n/"
    fi

    log "INFO" "N8N configured"
}

configure_flowise() {
    CONFIG["FLOWISE_PORT"]="3000"
    CREDENTIALS["FLOWISE_PASSWORD"]=$(generate_password 16)
    CREDENTIALS["FLOWISE_API_KEY"]=$(generate_secret)
    CREDENTIALS["FLOWISE_DB_PASSWORD"]=$(generate_password 32)
    CONFIG["FLOWISE_DB_NAME"]="flowise"
    log "INFO" "Flowise configured"
}

configure_litellm() {
    CONFIG["LITELLM_PORT"]="4000"
    CREDENTIALS["LITELLM_MASTER_KEY"]=$(generate_secret)
    log "INFO" "LiteLLM configured"
}

configure_langfuse() {
    CONFIG["LANGFUSE_PORT"]="3001"
    CREDENTIALS["LANGFUSE_SALT"]=$(generate_secret)
    CREDENTIALS["LANGFUSE_SECRET_KEY"]=$(generate_secret)
    CREDENTIALS["LANGFUSE_PUBLIC_KEY"]=$(generate_secret)
    CREDENTIALS["LANGFUSE_DB_PASSWORD"]=$(generate_password 32)
    CONFIG["LANGFUSE_DB_NAME"]="langfuse"
    log "INFO" "Langfuse configured"
}

configure_dify() {
    CONFIG["DIFY_PORT"]="3002"
    CREDENTIALS["DIFY_SECRET_KEY"]=$(generate_secret)
    CREDENTIALS["DIFY_DB_PASSWORD"]=$(generate_password 32)
    CONFIG["DIFY_DB_NAME"]="dify"
    log "INFO" "Dify configured"
}

configure_openwebui() {
    CONFIG["OPENWEBUI_PORT"]="3003"
    log "INFO" "OpenWebUI configured"
}

configure_anythingllm() {
    CONFIG["ANYTHINGLLM_PORT"]="3004"
    CREDENTIALS["ANYTHINGLLM_AUTH_TOKEN"]=$(generate_secret)
    log "INFO" "AnythingLLM configured"
}

configure_openclaw() {
    CONFIG["OPENCLAW_PORT"]="8080"
    CREDENTIALS["OPENCLAW_DB_PASSWORD"]=$(generate_password 32)
    CONFIG["OPENCLAW_DB_NAME"]="openclaw"

    if [ "${CONFIG["INSTALL_VECTORDB"]}" == "true" ]; then
        CONFIG["OPENCLAW_VECTORDB_URL"]="http://vectordb:${CONFIG["VECTORDB_PORT"]}"
    else
        print_warning "OpenClaw selected without vector database - RAG features disabled"
        CONFIG["OPENCLAW_VECTORDB_URL"]=""
    fi

    log "INFO" "OpenClaw configured"
}

configure_minio() {
    CONFIG["MINIO_PORT"]="9000"
    CONFIG["MINIO_CONSOLE_PORT"]="9001"
    CONFIG["MINIO_REGION"]="us-east-1"
    CREDENTIALS["MINIO_ROOT_USER"]="admin"
    CREDENTIALS["MINIO_ROOT_PASSWORD"]=$(generate_password 20)
    log "INFO" "MinIO configured"
}
#===============================================================================
# CONFIGURATION SAVE
#===============================================================================

save_configuration() {
    print_header "Saving Configuration"

    # Create .env.master
    cat > "$CONFIG_FILE" <<'ENVEOF'
#===============================================================================
# AI Platform Automation - Master Configuration
#===============================================================================
# Generated: $(date)
# Version: ${SCRIPT_VERSION}
#===============================================================================

#===============================================================================
# SYSTEM
#===============================================================================
ENVEOF

    cat >> "$CONFIG_FILE" <<EOF
PUBLIC_IP=${CONFIG["PUBLIC_IP"]}
DOMAIN=${CONFIG["DOMAIN"]:-}
USE_DOMAIN=${CONFIG["USE_DOMAIN"]}
SSL_MODE=${CONFIG["SSL_MODE"]}
SSL_EMAIL=${CONFIG["SSL_EMAIL"]:-}

#===============================================================================
# NETWORK
#===============================================================================
PROXY_TYPE=${CONFIG["PROXY_TYPE"]}
PROXY_HTTP_PORT=${CONFIG["PROXY_HTTP_PORT"]}
PROXY_HTTPS_PORT=${CONFIG["PROXY_HTTPS_PORT"]}

#===============================================================================
# DIRECTORIES
#===============================================================================
BASE_DIR=${BASE_DIR}
DATA_DIR=${DATA_DIR}
LOG_DIR=${LOG_DIR}
EOF

    if [ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ]; then
        cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# POSTGRESQL
#===============================================================================
POSTGRES_PORT=${CONFIG["POSTGRES_PORT"]}
POSTGRES_USER=${CONFIG["POSTGRES_USER"]}
POSTGRES_PASSWORD=${CREDENTIALS["POSTGRES_PASSWORD"]}
EOF
    fi

    if [ "${CONFIG["INSTALL_VECTORDB"]}" == "true" ]; then
        cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# VECTOR DATABASE
#===============================================================================
VECTORDB_TYPE=${CONFIG["VECTORDB_TYPE"]}
VECTORDB_PORT=${CONFIG["VECTORDB_PORT"]}
EOF

        case "${CONFIG["VECTORDB_TYPE"]}" in
            qdrant)
                echo "QDRANT_API_KEY=${CREDENTIALS["QDRANT_API_KEY"]}" >> "$CONFIG_FILE"
                ;;
            chroma)
                echo "CHROMA_AUTH_TOKEN=${CREDENTIALS["CHROMA_AUTH_TOKEN"]}" >> "$CONFIG_FILE"
                ;;
            weaviate)
                echo "WEAVIATE_API_KEY=${CREDENTIALS["WEAVIATE_API_KEY"]}" >> "$CONFIG_FILE"
                ;;
        esac
    fi

    # Add service configurations for each selected service
    [ "${CONFIG["INSTALL_N8N"]}" == "true" ] && add_n8n_config
    [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ] && add_flowise_config
    [ "${CONFIG["INSTALL_LITELLM"]}" == "true" ] && add_litellm_config
    [ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ] && add_langfuse_config
    [ "${CONFIG["INSTALL_DIFY"]}" == "true" ] && add_dify_config
    [ "${CONFIG["INSTALL_OPENWEBUI"]}" == "true" ] && add_openwebui_config
    [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" == "true" ] && add_anythingllm_config
    [ "${CONFIG["INSTALL_OPENCLAW"]}" == "true" ] && add_openclaw_config
    [ "${CONFIG["INSTALL_MINIO"]}" == "true" ] && add_minio_config
    [ "${CONFIG["INSTALL_SIGNAL_API"]}" == "true" ] && add_signal_config
    [ "${CONFIG["INSTALL_TAILSCALE"]}" == "true" ] && add_tailscale_config
    [ "${CONFIG["GDRIVE_ENABLED"]}" == "true" ] && add_gdrive_config
    [ "${CONFIG["INSTALL_OLLAMA"]}" == "true" ] && add_ollama_config

    if [ ${#LLM_PROVIDERS[@]} -gt 0 ]; then
        cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# LLM PROVIDER KEYS
#===============================================================================
EOF
        for key in "${!LLM_PROVIDERS[@]}"; do
            echo "${key}=${LLM_PROVIDERS[$key]}" >> "$CONFIG_FILE"
        done
    fi

    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved: $CONFIG_FILE"

    create_credentials_file

    print_success "✓ Script 1 Complete!"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Setup Summary${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Services selected: ${#SELECTED_SERVICES[@]}"
    for svc in "${SELECTED_SERVICES[@]}"; do
        echo "  ✓ $svc"
    done
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Review configuration: cat $CONFIG_FILE"
    echo "  2. Review credentials:   cat ${BASE_DIR}/CREDENTIALS.txt"
    echo "  3. Run deployment:       ./2-deploy-services.sh"
    echo ""
}

# Helper functions for adding configs
add_n8n_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# N8N
#===============================================================================
N8N_PORT=${CONFIG["N8N_PORT"]}
N8N_ADMIN_EMAIL=${CREDENTIALS["N8N_ADMIN_EMAIL"]}
N8N_ADMIN_PASSWORD=${CREDENTIALS["N8N_ADMIN_PASSWORD"]}
N8N_ENCRYPTION_KEY=${CREDENTIALS["N8N_ENCRYPTION_KEY"]}
N8N_WEBHOOK_URL=${CREDENTIALS["N8N_WEBHOOK_URL"]}
N8N_DB_NAME=${CONFIG["N8N_DB_NAME"]}
N8N_DB_PASSWORD=${CREDENTIALS["N8N_DB_PASSWORD"]}
EOF
}

add_flowise_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# FLOWISE
#===============================================================================
FLOWISE_PORT=${CONFIG["FLOWISE_PORT"]}
FLOWISE_PASSWORD=${CREDENTIALS["FLOWISE_PASSWORD"]}
FLOWISE_API_KEY=${CREDENTIALS["FLOWISE_API_KEY"]}
FLOWISE_DB_NAME=${CONFIG["FLOWISE_DB_NAME"]}
FLOWISE_DB_PASSWORD=${CREDENTIALS["FLOWISE_DB_PASSWORD"]}
EOF
}

add_litellm_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# LITELLM
#===============================================================================
LITELLM_PORT=${CONFIG["LITELLM_PORT"]}
LITELLM_MASTER_KEY=${CREDENTIALS["LITELLM_MASTER_KEY"]}
EOF
}

add_langfuse_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# LANGFUSE
#===============================================================================
LANGFUSE_PORT=${CONFIG["LANGFUSE_PORT"]}
LANGFUSE_SALT=${CREDENTIALS["LANGFUSE_SALT"]}
LANGFUSE_SECRET_KEY=${CREDENTIALS["LANGFUSE_SECRET_KEY"]}
LANGFUSE_PUBLIC_KEY=${CREDENTIALS["LANGFUSE_PUBLIC_KEY"]}
LANGFUSE_DB_NAME=${CONFIG["LANGFUSE_DB_NAME"]}
LANGFUSE_DB_PASSWORD=${CREDENTIALS["LANGFUSE_DB_PASSWORD"]}
EOF
}

add_dify_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# DIFY
#===============================================================================
DIFY_PORT=${CONFIG["DIFY_PORT"]}
DIFY_SECRET_KEY=${CREDENTIALS["DIFY_SECRET_KEY"]}
DIFY_DB_NAME=${CONFIG["DIFY_DB_NAME"]}
DIFY_DB_PASSWORD=${CREDENTIALS["DIFY_DB_PASSWORD"]}
EOF
}

add_openwebui_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# OPENWEBUI
#===============================================================================
OPENWEBUI_PORT=${CONFIG["OPENWEBUI_PORT"]}
EOF
}

add_anythingllm_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# ANYTHINGLLM
#===============================================================================
ANYTHINGLLM_PORT=${CONFIG["ANYTHINGLLM_PORT"]}
ANYTHINGLLM_AUTH_TOKEN=${CREDENTIALS["ANYTHINGLLM_AUTH_TOKEN"]}
EOF
}

add_openclaw_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# OPENCLAW
#===============================================================================
OPENCLAW_PORT=${CONFIG["OPENCLAW_PORT"]}
OPENCLAW_DB_NAME=${CONFIG["OPENCLAW_DB_NAME"]}
OPENCLAW_DB_PASSWORD=${CREDENTIALS["OPENCLAW_DB_PASSWORD"]}
OPENCLAW_VECTORDB_URL=${CONFIG["OPENCLAW_VECTORDB_URL"]}
EOF
}

add_minio_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# MINIO
#===============================================================================
MINIO_PORT=${CONFIG["MINIO_PORT"]}
MINIO_CONSOLE_PORT=${CONFIG["MINIO_CONSOLE_PORT"]}
MINIO_ROOT_USER=${CREDENTIALS["MINIO_ROOT_USER"]}
MINIO_ROOT_PASSWORD=${CREDENTIALS["MINIO_ROOT_PASSWORD"]}
MINIO_REGION=${CONFIG["MINIO_REGION"]}
EOF
}

add_signal_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# SIGNAL API
#===============================================================================
SIGNAL_API_PORT=${CONFIG["SIGNAL_API_PORT"]}
SIGNAL_PHONE_NUMBER=${CONFIG["SIGNAL_PHONE_NUMBER"]}
EOF
}

add_tailscale_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# TAILSCALE
#===============================================================================
TAILSCALE_AUTH_KEY=${CONFIG["TAILSCALE_AUTH_KEY"]}
TAILSCALE_API_KEY=${CONFIG["TAILSCALE_API_KEY"]:-}
EOF
}

add_gdrive_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# GOOGLE DRIVE
#===============================================================================
GDRIVE_ENABLED=${CONFIG["GDRIVE_ENABLED"]}
GDRIVE_MOUNT_PATH=${CONFIG["GDRIVE_MOUNT_PATH"]}
GDRIVE_AUTH_METHOD=${CONFIG["GDRIVE_AUTH_METHOD"]}
GDRIVE_SERVICE_ACCOUNT_JSON=${CONFIG["GDRIVE_SERVICE_ACCOUNT_JSON"]:-}
GDRIVE_FOLDER_ID=${CONFIG["GDRIVE_FOLDER_ID"]:-}
GDRIVE_FOLDER_SECRET=${CONFIG["GDRIVE_FOLDER_SECRET"]:-}
GDRIVE_SYNC_INTERVAL=${CONFIG["GDRIVE_SYNC_INTERVAL"]}
EOF
}

add_ollama_config() {
    cat >> "$CONFIG_FILE" <<EOF

#===============================================================================
# OLLAMA
#===============================================================================
OLLAMA_PORT=${CONFIG["OLLAMA_PORT"]}
OLLAMA_HOST=${CONFIG["OLLAMA_HOST"]}
OLLAMA_MODELS=${CONFIG["OLLAMA_MODELS"]}
OLLAMA_GPU_ENABLED=${CONFIG["OLLAMA_GPU_ENABLED"]}
EOF
}

create_credentials_file() {
    local creds_file="${BASE_DIR}/CREDENTIALS.txt"

    cat > "$creds_file" <<'CREDEOF'
═══════════════════════════════════════════════════════════════════════════════
AI Platform Automation - Generated Credentials
═══════════════════════════════════════════════════════════════════════════════
CREDEOF

    echo "Generated: $(date)" >> "$creds_file"
    echo "" >> "$creds_file"
    echo "⚠️  KEEP THIS FILE SECURE - DO NOT SHARE PUBLICLY" >> "$creds_file"
    echo "" >> "$creds_file"

    [ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ] && add_postgres_creds "$creds_file"
    [ "${CONFIG["INSTALL_N8N"]}" == "true" ] && add_n8n_creds "$creds_file"
    [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ] && add_flowise_creds "$creds_file"
    [ "${CONFIG["INSTALL_LITELLM"]}" == "true" ] && add_litellm_creds "$creds_file"
    [ "${CONFIG["INSTALL_MINIO"]}" == "true" ] && add_minio_creds "$creds_file"

    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$creds_file"

    chmod 600 "$creds_file"
    print_success "Credentials file: $creds_file"
}

add_postgres_creds() {
    cat >> "$1" <<EOF
═══ PostgreSQL ═══
Password: ${CREDENTIALS["POSTGRES_PASSWORD"]}

EOF
}

add_n8n_creds() {
    cat >> "$1" <<EOF
═══ N8N ═══
Email: ${CREDENTIALS["N8N_ADMIN_EMAIL"]}
Password: ${CREDENTIALS["N8N_ADMIN_PASSWORD"]}

EOF
}

add_flowise_creds() {
    cat >> "$1" <<EOF
═══ Flowise ═══
Password: ${CREDENTIALS["FLOWISE_PASSWORD"]}
API Key: ${CREDENTIALS["FLOWISE_API_KEY"]}

EOF
}

add_litellm_creds() {
    cat >> "$1" <<EOF
═══ LiteLLM ═══
Master Key: ${CREDENTIALS["LITELLM_MASTER_KEY"]}

EOF
}

add_minio_creds() {
    cat >> "$1" <<EOF
═══ MinIO ═══
User: ${CREDENTIALS["MINIO_ROOT_USER"]}
Password: ${CREDENTIALS["MINIO_ROOT_PASSWORD"]}

EOF
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    check_root
    setup_logging

    print_header "AI Platform Automation Setup - v${SCRIPT_VERSION}"

    # System checks
    check_dependencies
    check_disk_space
    detect_public_ip
    detect_gpu

    # Configuration flow
    configure_network
    select_services
    select_vector_db

    # Service-specific configuration (only for selected services)
    [ "${CONFIG["INSTALL_POSTGRES"]}" == "true" ] && configure_postgres
    [ "${CONFIG["INSTALL_SIGNAL_API"]}" == "true" ] && configure_signal_api
    [ "${CONFIG["INSTALL_TAILSCALE"]}" == "true" ] && configure_tailscale
    configure_gdrive
    [ "${CONFIG["INSTALL_OLLAMA"]}" == "true" ] && configure_ollama
    configure_llm_providers

    [ "${CONFIG["INSTALL_N8N"]}" == "true" ] && configure_n8n
    [ "${CONFIG["INSTALL_FLOWISE"]}" == "true" ] && configure_flowise
    [ "${CONFIG["INSTALL_LITELLM"]}" == "true" ] && configure_litellm
    [ "${CONFIG["INSTALL_LANGFUSE"]}" == "true" ] && configure_langfuse
    [ "${CONFIG["INSTALL_DIFY"]}" == "true" ] && configure_dify
    [ "${CONFIG["INSTALL_OPENWEBUI"]}" == "true" ] && configure_openwebui
    [ "${CONFIG["INSTALL_ANYTHINGLLM"]}" == "true" ] && configure_anythingllm
    [ "${CONFIG["INSTALL_OPENCLAW"]}" == "true" ] && configure_openclaw
    [ "${CONFIG["INSTALL_MINIO"]}" == "true" ] && configure_minio

    # Save everything
    save_configuration
}

main "$@"

