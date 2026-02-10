#!/bin/bash
# ==============================================================================
# Script 1: System Setup and Base Configuration
# Version: 5.0 - Interactive Service Selection Framework
# Purpose: Complete system preparation for AI platform deployment
# Features: Service selection, proxy selection, vector DB selection, CPU/GPU handling
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION AND CONSTANTS
# ==============================================================================

# Script metadata
readonly SCRIPT_VERSION="5.0"
readonly SCRIPT_NAME="1-setup-system.sh"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths (Updated for modular architecture)
readonly BASE_DIR="/root/scripts"
readonly DATA_DIR="/mnt/data"
readonly AI_PLATFORM_DIR="${DATA_DIR}/ai-platform"
readonly BACKUP_DIR="${AI_PLATFORM_DIR}/backups"
readonly LOG_DIR="${AI_PLATFORM_DIR}/logs"
readonly CONFIG_DIR="${AI_PLATFORM_DIR}/config"
readonly DOCKER_DIR="${AI_PLATFORM_DIR}/docker"
readonly CONFIG_FILE="${CONFIG_DIR}/master.env"
readonly STATE_FILE="${BASE_DIR}/.setup_state"

# Service data directories
readonly POSTGRES_DATA="${DATA_DIR}/postgresql"
readonly OLLAMA_DATA="${DATA_DIR}/ollama"
readonly N8N_DATA="${DATA_DIR}/n8n"
readonly QDRANT_DATA="${DATA_DIR}/qdrant"

# Log files
readonly SETUP_LOG="${LOG_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"
readonly ERROR_LOG="${LOG_DIR}/setup_errors_$(date +%Y%m%d_%H%M%S).log"

# Network configuration
readonly DOCKER_NETWORK="ai-platform-network"
readonly SUBNET="172.20.0.0/16"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Timing
readonly START_TIME=$(date +%s)

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

setup_logging() {
    mkdir -p "${LOG_DIR}"
    exec 1> >(tee -a "$SETUP_LOG")
    exec 2> >(tee -a "$ERROR_LOG" >&2)
    log_info "Logging initialized - Setup: $SETUP_LOG, Errors: $ERROR_LOG"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SETUP_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*" | tee -a "$SETUP_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*" | tee -a "$SETUP_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] ✗ $*" | tee -a "$ERROR_LOG"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SETUP_LOG"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SETUP_LOG"
    fi
}

# ==============================================================================
# BANNER AND UI FUNCTIONS
# ==============================================================================

print_banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║         AI PLATFORM DEPLOYMENT AUTOMATION v${SCRIPT_VERSION}         ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║              Script 1: System Setup                        ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  $title${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}Progress:${NC} ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% - %s" "$percent" "$message"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# ==============================================================================
# STATE MANAGEMENT
# ==============================================================================

save_state() {
    local step=$1
    echo "CURRENT_STEP=$step" > "$STATE_FILE"
    log_debug "State saved: CURRENT_STEP=$step"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

clear_state() {
    rm -f "$STATE_FILE"
    log_debug "State cleared"
}

is_step_completed() {
    local step=$1
    local current_state=$(load_state)
    [ "$current_state" -ge "$step" ]
}

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

error_exit() {
    local message=$1
    local exit_code=${2:-1}
    log_error "$message"
    log_error "Setup failed at step: $(load_state)"
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    SETUP FAILED                            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}Error: $message${NC}"
    echo -e "${YELLOW}Check logs: $ERROR_LOG${NC}"
    echo ""
    exit "$exit_code"
}

cleanup_on_error() {
    log_warning "Performing cleanup due to error..."
    # Add any necessary cleanup here
    log_info "Cleanup completed"
}

trap 'cleanup_on_error' ERR

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root. Use: sudo $0"
    fi
    log_success "Running as root"
}

check_system_requirements() {
    log_step "Checking system requirements..."
    
    # Check OS
    if [ ! -f /etc/os-release ]; then
        error_exit "Cannot determine OS version"
    fi
    
    . /etc/os-release
    if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
        error_exit "Unsupported OS: $ID. This script supports Ubuntu/Debian only."
    fi
    log_success "OS: $PRETTY_NAME"
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 4 ]; then
        log_warning "System has only $cpu_cores CPU cores. Recommended: 4+"
    else
        log_success "CPU cores: $cpu_cores"
    fi
    
    # Check RAM
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 16 ]; then
        log_warning "System has only ${total_ram}GB RAM. Recommended: 16GB+"
    else
        log_success "RAM: ${total_ram}GB"
    fi
    
    # Check disk space
    local disk_space=$(df -BG "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${disk_space:-0}" -lt 100 ]; then
        log_warning "Only ${disk_space}GB available in $DATA_DIR. Recommended: 100GB+"
    else
        log_success "Disk space: ${disk_space}GB available"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "No internet connectivity detected"
    fi
    log_success "Internet connectivity: OK"
    
    log_success "System requirements check completed"
}

validate_domain_or_ip() {
    local input=$1
    # Check if it's an IP address
    if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    # Check if it's a domain/subdomain
    if [[ "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    return 1
}

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# SERVICE SELECTION FRAMEWORK
# ==============================================================================

collect_service_selection() {
    log_step "Collecting service selection..."
    
    # Create service selection directory
    mkdir -p "/mnt/data/ai-platform/config"
    
    # Initialize selection variables
    SELECTED_CORE_SERVICES=()
    SELECTED_AI_SERVICES=()
    SELECTED_OPTIONAL_SERVICES=()
    SELECTED_PROXY=""
    SELECTED_VECTOR_DB=""
    
    echo ""
    print_section "SERVICE SELECTION"
    
    # Core Infrastructure Selection
    echo -e "${CYAN}=== CORE INFRASTRUCTURE ===${NC}"
    echo "1) PostgreSQL (Database) - ${GREEN}[AUTO-SELECTED]${NC}"
    echo "2) Redis (Cache) - ${GREEN}[AUTO-SELECTED]${NC}"
    echo "3) LiteLLM (AI Gateway) - ${GREEN}[AUTO-SELECTED]${NC}"
    echo ""
    
    # Proxy Selection
    echo -e "${CYAN}=== REVERSE PROXY SELECTION ===${NC}"
    echo "4) Nginx (Traditional, battle-tested)"
    echo "5) Caddy (Automatic HTTPS, modern)"
    echo "6) Traefik (Advanced routing, containers)"
    echo ""
    
    while true; do
        read -p "Select reverse proxy (4-6): " proxy_choice
        case $proxy_choice in
            4) SELECTED_PROXY="nginx"; break ;;
            5) SELECTED_PROXY="caddy"; break ;;
            6) SELECTED_PROXY="traefik"; break ;;
            *) echo -e "${RED}Invalid choice. Please select 4-6.${NC}" ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}=== AI STACK SELECTION ===${NC}"
    echo "7) Dify (AI Platform - 4 services)"
    echo "8) n8n (Workflow automation)"
    echo "9) Open WebUI (Chat interface)"
    echo "10) Flowise (Visual LLM flow builder)"
    echo "11) AnythingLLM (Document-centric RAG)"
    echo "12) OpenClaw (RAG + Tailscale isolation)"
    echo "all) Install ALL AI services (recommended for full platform)"
    echo ""
    
    # AI Services Selection
    while true; do
        read -p "Select AI services (comma-separated, 7-12, or 'all'): " ai_choices
        
        if [ "$ai_choices" = "all" ]; then
            SELECTED_AI_SERVICES=("dify" "n8n" "open-webui" "flowise" "anythingllm" "openclaw")
            break
        fi
        
        IFS=',' read -ra CHOSEN_AI <<< "$ai_choices"
        valid=true
        
        for choice in "${CHOSEN_AI[@]}"; do
            choice=$(echo "$choice" | xargs) # trim whitespace
            case $choice in
                7) SELECTED_AI_SERVICES+=("dify") ;;
                8) SELECTED_AI_SERVICES+=("n8n") ;;
                9) SELECTED_AI_SERVICES+=("open-webui") ;;
                10) SELECTED_AI_SERVICES+=("flowise") ;;
                11) SELECTED_AI_SERVICES+=("anythingllm") ;;
                12) SELECTED_AI_SERVICES+=("openclaw") ;;
                *) valid=false; break ;;
            esac
        done
        
        if [ "$valid" = true ]; then
            break
        else
            echo -e "${RED}Invalid choices. Please select numbers 7-12 separated by commas, or 'all'.${NC}"
        fi
    done
    
    echo ""
    echo -e "${CYAN}=== VECTOR DATABASE SELECTION ===${NC}"
    echo "13) Qdrant (Performance-focused)"
    echo "14) ChromaDB (Simplicity-focused)"
    echo "15) Redis (as vector DB)"
    echo "16) Weaviate (Advanced queries)"
    echo ""
    
    while true; do
        read -p "Select vector database (13-16): " vector_choice
        case $vector_choice in
            13) SELECTED_VECTOR_DB="qdrant"; break ;;
            14) SELECTED_VECTOR_DB="chromadb"; break ;;
            15) SELECTED_VECTOR_DB="redis"; break ;;
            16) SELECTED_VECTOR_DB="weaviate"; break ;;
            *) echo -e "${RED}Invalid choice. Please select 13-16.${NC}" ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}=== OPTIONAL SERVICES ===${NC}"
    echo "17) Monitoring (Prometheus + Grafana + Loki)"
    echo "18) Storage (MinIO S3-compatible)"
    echo "19) Development (Jupyter + Code Server)"
    echo "20) Authentication (SuperTokens)"
    echo "21) Communication (Signal)"
    echo "22) Networking (Tailscale VPN)"
    echo "all) Install ALL optional services (recommended for full platform)"
    echo ""
    
    # Optional Services Selection
    while true; do
        read -p "Select optional services (comma-separated, 17-22, or 'all'): " optional_choices
        
        if [ "$optional_choices" = "all" ]; then
            SELECTED_OPTIONAL_SERVICES=("monitoring" "minio" "development" "supertokens" "signal" "tailscale")
            break
        fi
        
        IFS=',' read -ra CHOSEN_OPTIONAL <<< "$optional_choices"
        valid=true
        
        for choice in "${CHOSEN_OPTIONAL[@]}"; do
            choice=$(echo "$choice" | xargs) # trim whitespace
            case $choice in
                17) SELECTED_OPTIONAL_SERVICES+=("monitoring") ;;
                18) SELECTED_OPTIONAL_SERVICES+=("minio") ;;
                19) SELECTED_OPTIONAL_SERVICES+=("development") ;;
                20) SELECTED_OPTIONAL_SERVICES+=("supertokens") ;;
                21) SELECTED_OPTIONAL_SERVICES+=("signal") ;;
                22) SELECTED_OPTIONAL_SERVICES+=("tailscale") ;;
                *) valid=false; break ;;
            esac
        done
        
        if [ "$valid" = true ]; then
            break
        else
            echo -e "${RED}Invalid choices. Please select numbers 17-22 separated by commas, or 'all'.${NC}"
        fi
    done
    
    # Save selections to file
    cat > "/mnt/data/ai-platform/config/service-selection.env" << EOF
# Service Selection Configuration
SELECTED_PROXY=${SELECTED_PROXY}
SELECTED_VECTOR_DB=${SELECTED_VECTOR_DB}
SELECTED_AI_SERVICES=$(IFS=,; echo "${SELECTED_AI_SERVICES[*]}")
SELECTED_OPTIONAL_SERVICES=$(IFS=,; echo "${SELECTED_OPTIONAL_SERVICES[*]}")
AUTO_SELECTED_CORE_SERVICES=postgresql,redis,litellm
EOF
    
    log_success "Service selections saved"
    log_info "Selected proxy: ${SELECTED_PROXY}"
    log_info "Selected vector DB: ${SELECTED_VECTOR_DB}"
    log_info "Selected AI services: ${SELECTED_AI_SERVICES[*]}"
    log_info "Selected optional services: ${SELECTED_OPTIONAL_SERVICES[*]}"
}

detect_hardware_profile() {
    log_step "Detecting hardware profile..."
    
    # GPU Detection
    GPU_AVAILABLE=false
    GPU_TYPE=""
    GPU_MEMORY=""
    
    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_TYPE="nvidia"
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        log_success "NVIDIA GPU detected: ${GPU_MEMORY}MB"
    elif command -v rocm-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_TYPE="amd"
        log_success "AMD GPU detected"
    else
        log_info "No GPU detected - CPU-only mode"
    fi
    
    # CPU Detection
    CPU_CORES=$(nproc)
    CPU_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    
    # Determine hardware profile
    if [ "$GPU_AVAILABLE" = true ]; then
        if [ "$GPU_MEMORY" -gt 8000 ]; then
            HARDWARE_PROFILE="high-gpu"
        else
            HARDWARE_PROFILE="standard-gpu"
        fi
    else
        if [ "$CPU_MEMORY" -gt 16000 ]; then
            HARDWARE_PROFILE="high-cpu"
        else
            HARDWARE_PROFILE="standard-cpu"
        fi
    fi
    
    # Save hardware profile
    cat > "/mnt/data/ai-platform/config/hardware-profile.env" << EOF
# Hardware Profile Configuration
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_TYPE=${GPU_TYPE}
GPU_MEMORY=${GPU_MEMORY}
CPU_CORES=${CPU_CORES}
CPU_MEMORY=${CPU_MEMORY}
HARDWARE_PROFILE=${HARDWARE_PROFILE}
EOF
    
    log_success "Hardware profile: ${HARDWARE_PROFILE}"
}

# ==============================================================================
# STEP 6: INTERACTIVE QUESTIONNAIRE (MISSING - CRITICAL)
# ==============================================================================

step_6_interactive_questionnaire() {
    show_progress 6 27 "📋 Interactive Configuration"
    log_step "Starting interactive questionnaire..."
    
    # Domain/IP Configuration
    print_section "DOMAIN & NETWORK CONFIGURATION"
    while true; do
        read -p "Enter your domain or IP (e.g., ai.example.com or 192.168.1.100): " DOMAIN_NAME
        if validate_domain_or_ip "$DOMAIN_NAME"; then
            break
        else
            echo -e "${RED}Invalid domain or IP. Please try again.${NC}"
        fi
    done
    
    # SSL Mode Selection
    echo ""
    echo -e "${CYAN}🔒 SSL Certificate Mode:${NC}"
    echo "1) Caddy Auto-Let's Encrypt (recommended)"
    echo "2) Self-signed certificates"
    echo "3) No SSL (development only)"
    echo ""
    
    while true; do
        read -p "Select SSL mode (1-3): " ssl_choice
        case $ssl_choice in
            1) SSL_MODE="caddy-auto"; break ;;
            2) SSL_MODE="self-signed"; break ;;
            3) SSL_MODE="none"; break ;;
            *) echo -e "${RED}Invalid choice. Please select 1-3.${NC}" ;;
        esac
    done
    
    # SSL Email
    if [ "$SSL_MODE" != "none" ]; then
        while true; do
            read -p "Enter SSL certificate email: " SSL_EMAIL
            if validate_email "$SSL_EMAIL"; then
                break
            else
                echo -e "${RED}Invalid email address. Please try again.${NC}"
            fi
        done
    fi
    
    # Provider API Keys
    print_section "EXTERNAL LLM PROVIDERS"
    echo -e "${CYAN}🤖 Configure API keys (optional, press Enter to skip):${NC}"
    echo ""
    
    read -p "OpenAI API Key: " OPENAI_API_KEY
    read -p "Anthropic Claude API Key: " ANTHROPIC_API_KEY
    read -p "Google Gemini API Key: " GOOGLE_API_KEY
    read -p "Groq API Key: " GROQ_API_KEY
    read -p "OpenRouter API Key: " OPENROUTER_API_KEY
    read -p "DeepSeek API Key: " DEEPSEEK_API_KEY
    
    # Google Drive Authentication
    print_section "GOOGLE DRIVE INTEGRATION"
    echo -e "${CYAN}📁 Google Drive Authentication Method:${NC}"
    echo "1) OAuth2 (recommended)"
    echo "2) Service Account JSON"
    echo "3) Interactive Token Refresh"
    echo "4) Skip Google Drive"
    echo ""
    
    while true; do
        read -p "Select Google Drive auth method (1-4): " gdrive_choice
        case $gdrive_choice in
            1) 
                GDRIVE_AUTH_METHOD="oauth2"
                read -p "Enter Google Client ID: " GOOGLE_CLIENT_ID
                read -p "Enter Google Client Secret: " GOOGLE_CLIENT_SECRET
                break ;;
            2) 
                GDRIVE_AUTH_METHOD="service_account"
                read -p "Enter path to service account JSON: " GDRIVE_SERVICE_ACCOUNT_JSON
                break ;;
            3) 
                GDRIVE_AUTH_METHOD="token_refresh"
                read -p "Enter refresh token: " GDRIVE_REFRESH_TOKEN
                break ;;
            4) 
                GDRIVE_AUTH_METHOD="skip"
                break ;;
            *) echo -e "${RED}Invalid choice. Please select 1-4.${NC}" ;;
        esac
    done
    
    # Signal Integration
    print_section "SIGNAL INTEGRATION"
    echo -e "${CYAN}📱 Signal Registration Method:${NC}"
    echo "1) QR Code Generation"
    echo "2) API Key Registration"
    echo "3) Skip Signal"
    echo ""
    
    while true; do
        read -p "Select Signal registration method (1-3): " signal_choice
        case $signal_choice in
            1) 
                SIGNAL_AUTH_METHOD="qr_code"
                log_info "QR code will be generated during deployment"
                break ;;
            2) 
                SIGNAL_AUTH_METHOD="api_key"
                read -p "Enter Signal API key: " SIGNAL_API_KEY
                break ;;
            3) 
                SIGNAL_AUTH_METHOD="skip"
                break ;;
            *) echo -e "${RED}Invalid choice. Please select 1-3.${NC}" ;;
        esac
    done
    
    # Service Selection by Tier
    print_section "SERVICE SELECTION BY TIER"
    echo -e "${CYAN}🏗 Tier 1: Infrastructure (Auto-selected)${NC}"
    echo "   ✓ PostgreSQL (database)"
    echo "   ✓ Redis (cache)"
    echo "   ✓ Qdrant (vector DB)"
    echo "   ✓ SuperTokens (auth)"
    echo ""
    
    echo -e "${CYAN}🤖 Tier 2: AI Services${NC}"
    echo "1) LiteLLM (gateway) - [REQUIRED]"
    echo "2) Dify (platform) - [RECOMMENDED]"
    echo "3) n8n (automation)"
    echo "4) Open WebUI (chat)"
    echo "5) Flowise (workflows)"
    echo "all) All AI Services"
    echo ""
    
    while true; do
        read -p "Select AI services (1-5, or 'all'): " ai_choices
        
        if [ "$ai_choices" = "all" ]; then
            SELECTED_AI_SERVICES=("litellm" "dify" "n8n" "open-webui" "flowise")
            break
        fi
        
        IFS=',' read -ra CHOSEN_AI <<< "$ai_choices"
        valid=true
        SELECTED_AI_SERVICES=("litellm")  # Always include LiteLLM
        
        for choice in "${CHOSEN_AI[@]}"; do
            choice=$(echo "$choice" | xargs) # trim whitespace
            case $choice in
                2) SELECTED_AI_SERVICES+=("dify") ;;
                3) SELECTED_AI_SERVICES+=("n8n") ;;
                4) SELECTED_AI_SERVICES+=("open-webui") ;;
                5) SELECTED_AI_SERVICES+=("flowise") ;;
                *) valid=false; break ;;
            esac
        done
        
        if [ "$valid" = true ]; then
            break
        else
            echo -e "${RED}Invalid choices. Please select numbers 1-5 separated by commas, or 'all'.${NC}"
        fi
    done
    
    echo ""
    echo -e "${CYAN}🌐 Tier 3: Applications${NC}"
    echo "1) Caddy (proxy) - [REQUIRED]"
    echo "2) Monitoring (Prometheus + Grafana)"
    echo "all) All Applications"
    echo ""
    
    while true; do
        read -p "Select applications (1-2, or 'all'): " app_choices
        
        if [ "$app_choices" = "all" ]; then
            SELECTED_APPLICATIONS=("caddy" "monitoring")
            break
        fi
        
        IFS=',' read -ra CHOSEN_APP <<< "$app_choices"
        valid=true
        SELECTED_APPLICATIONS=("caddy")  # Always include Caddy
        
        for choice in "${CHOSEN_APP[@]}"; do
            choice=$(echo "$choice" | xargs) # trim whitespace
            case $choice in
                2) SELECTED_APPLICATIONS+=("monitoring") ;;
                *) valid=false; break ;;
            esac
        done
        
        if [ "$valid" = true ]; then
            break
        else
            echo -e "${RED}Invalid choices. Please select numbers 1-2 separated by commas, or 'all'.${NC}"
        fi
    done
    
    # Auto-generate all passwords
    log_info "Auto-generating secure passwords..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    POSTGRES_USER="aiplatform"
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    LITELLM_SALT_KEY=$(openssl rand -hex 32)
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    JWT_SECRET=$(openssl rand -base64 64)
    
    # Save selections to file
    cat > "${CONFIG_DIR}/service-selection.env" << EOF
# Service Selection Configuration
DOMAIN_NAME=${DOMAIN_NAME}
SSL_MODE=${SSL_MODE}
SSL_EMAIL=${SSL_EMAIL}
SELECTED_AI_SERVICES=$(IFS=,; echo "${SELECTED_AI_SERVICES[*]}")
SELECTED_APPLICATIONS=$(IFS=,; echo "${SELECTED_APPLICATIONS[*]}")
AUTO_SELECTED_CORE_SERVICES=postgresql,redis,qdrant,supertokens
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD}
SIGNAL_AUTH_METHOD=${SIGNAL_AUTH_METHOD}
EOF
    
    log_success "Interactive questionnaire completed"
    log_info "Domain: ${DOMAIN_NAME}"
    log_info "SSL Mode: ${SSL_MODE}"
    log_info "AI Services: ${SELECTED_AI_SERVICES[*]}"
    log_info "Applications: ${SELECTED_APPLICATIONS[*]}"
    log_info "Google Drive: ${GDRIVE_AUTH_METHOD}"
    log_info "Signal: ${SIGNAL_AUTH_METHOD}"
}

# ==============================================================================
# STEP FUNCTIONS - 27 STEP FRAMEWORK
# ==============================================================================

step_1_hardware_detection() {
    show_progress 1 27 "🔍 Hardware Detection & Profiling"
    log_step "Detecting hardware profile..."
    
    # GPU Detection
    GPU_AVAILABLE=false
    GPU_TYPE=""
    GPU_MEMORY=""
    
    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_TYPE="nvidia"
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        log_success "NVIDIA GPU detected: ${GPU_MEMORY}MB"
    elif command -v rocm-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_TYPE="amd"
        log_success "AMD GPU detected"
    else
        log_info "No GPU detected - CPU-only mode"
    fi
    
    # CPU Detection
    CPU_CORES=$(nproc)
    CPU_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    
    # Determine hardware profile
    if [ "$GPU_AVAILABLE" = true ]; then
        if [ "$GPU_MEMORY" -gt 8000 ]; then
            HARDWARE_PROFILE="high-gpu"
        else
            HARDWARE_PROFILE="standard-gpu"
        fi
    else
        if [ "$CPU_MEMORY" -gt 16000 ]; then
            HARDWARE_PROFILE="high-cpu"
        else
            HARDWARE_PROFILE="standard-cpu"
        fi
    fi
    
    # Save hardware profile
    mkdir -p "${CONFIG_DIR}"
    cat > "${CONFIG_DIR}/hardware-profile.env" << EOF
# Hardware Profile Configuration
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_TYPE=${GPU_TYPE}
GPU_MEMORY=${GPU_MEMORY}
CPU_CORES=${CPU_CORES}
CPU_MEMORY=${CPU_MEMORY}
HARDWARE_PROFILE=${HARDWARE_PROFILE}
EOF
    
    log_success "Hardware profile: ${HARDWARE_PROFILE}"
}

step_2_docker_installation() {
    show_progress 2 27 "🐳 Docker Engine Installation"
    log_step "Installing Docker and Docker Compose..."
    
    # Remove conflicting packages
    apt remove -y docker docker-engine docker.io containerd runc || true
    
    # Add Docker GPG key and repository
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Configure Docker daemon
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
    
    # Add user to docker group
    local target_user="${SUDO_USER:-$USER}"
    if ! groups "$target_user" | grep -q docker; then
        usermod -aG docker "$target_user"
        log_info "Added ${target_user} to docker group"
    fi
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker installed: $(docker --version)"
}

step_3_nvidia_toolkit() {
    show_progress 3 27 "🎮 NVIDIA Container Toolkit"
    log_step "Installing NVIDIA Container Toolkit..."
    
    if [ "$GPU_AVAILABLE" = true ] && [ "$GPU_TYPE" = "nvidia" ]; then
        # Add NVIDIA repository
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/ubuntu20.04/$(dpkg --print-architecture) /" | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
        
        # Install NVIDIA container toolkit
        apt update
        apt install -y nvidia-container-toolkit
        
        # Configure Docker runtime
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        
        # Test GPU passthrough
        if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
            log_success "NVIDIA GPU passthrough working"
        else
            log_warning "NVIDIA GPU passthrough test failed"
        fi
    else
        log_info "Skipping NVIDIA toolkit - no NVIDIA GPU detected"
    fi
}

step_4_ollama_installation() {
    show_progress 4 27 "🦙 Ollama Installation & Model Pull"
    log_step "Installing Ollama..."
    
    # Install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh
    
    # Configure Ollama environment
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=3"
Environment="OLLAMA_KEEP_ALIVE=5m"
EOF
    
    # Start and enable Ollama
    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama
    
    # Wait for Ollama to start
    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -s http://localhost:11434/api/tags &> /dev/null; then
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done
    
    if [ $retries -eq 0 ]; then
        log_error "Ollama failed to start"
        return 1
    fi
    
    # Pull default models based on hardware profile
    case $HARDWARE_PROFILE in
        "high-gpu")
            ollama pull llama2
            ollama pull codellama
            ollama pull mistral
            ;;
        "standard-gpu")
            ollama pull llama2
            ollama pull mistral
            ;;
        "high-cpu")
            ollama pull llama2
            ;;
        "standard-cpu")
            ollama pull tinyllama
            ;;
    esac
    
    log_success "Ollama installed and models pulled"
}

step_5_validation() {
    show_progress 5 27 "✅ Validation & Handoff"
    log_step "Validating installation..."
    
    # Verify Docker daemon
    if ! systemctl is-active --quiet docker; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Verify Docker Compose
    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose is not available"
        return 1
    fi
    
    # Verify GPU passthrough (if applicable)
    if [ "$GPU_AVAILABLE" = true ]; then
        if ! docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
            log_warning "GPU passthrough validation failed"
        else
            log_success "GPU passthrough validated"
        fi
    fi
    
    # Verify Ollama
    if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
        log_error "Ollama is not responding"
        return 1
    fi
    
    # Verify models
    local model_count=$(curl -s http://localhost:11434/api/tags | jq -r '.models | length' 2>/dev/null || echo "0")
    if [ "$model_count" -eq 0 ]; then
        log_warning "No Ollama models found"
    else
        log_success "Found $model_count Ollama models"
    fi
    
    log_success "Validation completed successfully"
    log_info "Ready for Script 2: Deploy Platform"
}

step_7_generate_master_env() {
    show_progress 7 27 "⚙️ master.env Generation"
    log_step "Generating master configuration file..."
    
    # Source service selections
    source "${CONFIG_DIR}/service-selection.env"
    
    cat > "$CONFIG_FILE" << EOF
# ==============================================================================
# AI Platform Configuration
# Generated: $(date)
# Version: ${SCRIPT_VERSION}
# ==============================================================================

# Domain and Network
DOMAIN_NAME="${DOMAIN_NAME}"
SSL_MODE="${SSL_MODE}"
SSL_EMAIL="${SSL_EMAIL}"
DOCKER_NETWORK="${DOCKER_NETWORK}"
SUBNET="${SUBNET}"

# Paths
BASE_DIR="${BASE_DIR}"
DATA_DIR="${DATA_DIR}"
AI_PLATFORM_DIR="${AI_PLATFORM_DIR}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_DIR="${LOG_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
DOCKER_DIR="${DOCKER_DIR}"

# PostgreSQL Configuration
POSTGRES_VERSION=16
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=aiplatform
POSTGRES_PORT=5432
POSTGRES_DATA=${POSTGRES_DATA}
POSTGRES_MAX_CONNECTIONS=200

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=6379
REDIS_DATA=${DATA_DIR}/redis

# Ollama Configuration
OLLAMA_HOST=0.0.0.0
OLLAMA_PORT=11434
OLLAMA_DATA=${OLLAMA_DATA}
OLLAMA_ORIGINS=*

# LiteLLM Configuration
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
LITELLM_PORT=4000

# Qdrant Configuration
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
Qdrant_DATA=${QDRANT_DATA}

# n8n Configuration
N8N_PORT=5678
N8N_DATA=${N8N_DATA}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${JWT_SECRET}

# External LLM Providers
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}

# Google Drive Integration
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}
GDRIVE_SERVICE_ACCOUNT_JSON=${GDRIVE_SERVICE_ACCOUNT_JSON:-}
GDRIVE_REFRESH_TOKEN=${GDRIVE_REFRESH_TOKEN:-}

# Signal Integration
SIGNAL_AUTH_METHOD=${SIGNAL_AUTH_METHOD}
SIGNAL_API_KEY=${SIGNAL_API_KEY:-}

# Service Selections
SELECTED_AI_SERVICES="${SELECTED_AI_SERVICES}"
SELECTED_APPLICATIONS="${SELECTED_APPLICATIONS}"
AUTO_SELECTED_CORE_SERVICES="${AUTO_SELECTED_CORE_SERVICES}"

# System Configuration
TZ=UTC
COMPOSE_PROJECT_NAME=ai-platform
EOF
    
    log_success "master.env generated successfully"
}

# ==============================================================================
# USER INPUT COLLECTION
# ==============================================================================

collect_user_input() {
    log_step "Collecting user configuration..."
    
    echo ""
    print_section "DOMAIN AND NETWORK CONFIGURATION"
    
    # Domain name (allow subdomain or IP)
    while true; do
        read -p "Enter your domain or subdomain (e.g., ai.example.com or 192.168.1.100): " DOMAIN_NAME
        if validate_domain_or_ip "$DOMAIN_NAME"; then
            break
        else
            echo -e "${RED}Invalid domain or IP. Please try again.${NC}"
        fi
    done
    
    # SSL email
    while true; do
        read -p "Enter SSL certificate email: " SSL_EMAIL
        if validate_email "$SSL_EMAIL"; then
            break
        else
            echo -e "${RED}Invalid email address. Please try again.${NC}"
        fi
    done
    
    # Auto-generate all passwords
    log_info "Auto-generating secure passwords..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    POSTGRES_USER="aiplatform"  # Can be overridden if needed
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    LITELLM_SALT_KEY=$(openssl rand -hex 32)
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log_success "User configuration collected"
    log_info "Domain: ${DOMAIN_NAME}"
    log_info "SSL Email: ${SSL_EMAIL}"
    log_info "PostgreSQL User: ${POSTGRES_USER}"
    log_info "All passwords auto-generated securely"
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# DIRECTORY STRUCTURE SETUP
# ==============================================================================

create_directory_structure() {
    log_step "Creating directory structure..."
    
    local directories=(
        "${BASE_DIR}"
        "${DATA_DIR}"
        "${BACKUP_DIR}"
        "${LOG_DIR}"
        "${POSTGRES_DATA}"
        "${OLLAMA_DATA}"
        "${N8N_DATA}"
        "${QDRANT_DATA}"
        "${BASE_DIR}/ssl"
        "${BASE_DIR}/scripts"
        "${BACKUP_DIR}/postgresql"
        "${BACKUP_DIR}/n8n"
        "${BACKUP_DIR}/qdrant"
        "${LOG_DIR}/postgresql"
        "${LOG_DIR}/ollama"
        "${LOG_DIR}/n8n"
        "${LOG_DIR}/qdrant"
        "${LOG_DIR}/nginx"
    )
    
    local total=${#directories[@]}
    local current=0
    
    for dir in "${directories[@]}"; do
        current=$((current + 1))
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || error_exit "Failed to create directory: $dir"
            log_debug "Created directory: $dir"
        fi
        show_progress $current $total "Creating directories..."
    done
    
    # Set proper permissions
    chmod 755 "${BASE_DIR}"
    chmod 700 "${DATA_DIR}"
    chmod 700 "${BACKUP_DIR}"
    chmod 755 "${LOG_DIR}"
    
    log_success "Directory structure created successfully"
    save_state 1
}

# ==============================================================================
# USER INPUT AND CONFIGURATION
# ==============================================================================

get_user_input() {
    log_step "Gathering configuration information..."
    
    echo ""
    echo -e "${YELLOW}Please provide the following information:${NC}"
    echo ""
    
    # Domain name
    while true; do
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        if validate_domain "$DOMAIN_NAME"; then
            break
        else
            echo -e "${RED}Invalid domain name. Please try again.${NC}"
        fi
    done
    
    # Email for SSL
    while true; do
        read -p "Enter email for SSL certificates: " SSL_EMAIL
        if validate_email "$SSL_EMAIL"; then
            break
        else
            echo -e "${RED}Invalid email address. Please try again.${NC}"
        fi
    done
    
    # PostgreSQL password
    while true; do
        read -sp "Enter PostgreSQL password (min 12 chars): " POSTGRES_PASSWORD
        echo ""
        if [ ${#POSTGRES_PASSWORD} -ge 12 ]; then
            read -sp "Confirm PostgreSQL password: " POSTGRES_PASSWORD_CONFIRM
            echo ""
            if [ "$POSTGRES_PASSWORD" = "$POSTGRES_PASSWORD_CONFIRM" ]; then
                break
            else
                echo -e "${RED}Passwords do not match. Please try again.${NC}"
            fi
        else
            echo -e "${RED}Password must be at least 12 characters. Please try again.${NC}"
        fi
    done
    
    # n8n encryption key
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
    log_info "Generated n8n encryption key"
    
    # JWT secret
    JWT_SECRET=$(openssl rand -base64 64)
    log_info "Generated JWT secret"
    
    # Timezone
    read -p "Enter timezone (default: UTC): " TIMEZONE
    TIMEZONE=${TIMEZONE:-UTC}
    
    # Port configuration
    echo ""
    echo -e "${YELLOW}Port Configuration (press Enter for defaults):${NC}"
    
    read -p "Ollama port (default: 11434): " OLLAMA_PORT
    OLLAMA_PORT=${OLLAMA_PORT:-11434}
    
    read -p "n8n port (default: 5678): " N8N_PORT
    N8N_PORT=${N8N_PORT:-5678}
    
    read -p "Qdrant HTTP port (default: 6333): " QDRANT_PORT
    QDRANT_PORT=${QDRANT_PORT:-6333}
    
    read -p "Qdrant gRPC port (default: 6334): " QDRANT_GRPC_PORT
    QDRANT_GRPC_PORT=${QDRANT_GRPC_PORT:-6334}
    
    read -p "PostgreSQL port (default: 5432): " POSTGRES_PORT
    POSTGRES_PORT=${POSTGRES_PORT:-5432}
    
    # OpenAI API key (optional)
    read -p "Enter OpenAI API key (optional, press Enter to skip): " OPENAI_API_KEY
    
    log_success "Configuration information collected"
}

create_config_file() {
    log_step "Creating configuration file..."
    
    cat > "$CONFIG_FILE" << EOF
# ==============================================================================
# AI Platform Configuration
# Generated: $(date)
# Version: ${SCRIPT_VERSION}
# ==============================================================================

# Domain and Network
DOMAIN_NAME="${DOMAIN_NAME}"
SSL_EMAIL="${SSL_EMAIL}"
DOCKER_NETWORK="${DOCKER_NETWORK}"
SUBNET="${SUBNET}"

# Paths
BASE_DIR="${BASE_DIR}"
DATA_DIR="${DATA_DIR}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_DIR="${LOG_DIR}"

# PostgreSQL Configuration
POSTGRES_VERSION=16
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=aiplatform
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DATA=${POSTGRES_DATA}
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_SHARED_BUFFERS=4GB
POSTGRES_EFFECTIVE_CACHE_SIZE=12GB
POSTGRES_MAINTENANCE_WORK_MEM=1GB
POSTGRES_CHECKPOINT_COMPLETION_TARGET=0.9
POSTGRES_WAL_BUFFERS=16MB
POSTGRES_DEFAULT_STATISTICS_TARGET=100
POSTGRES_RANDOM_PAGE_COST=1.1
POSTGRES_EFFECTIVE_IO_CONCURRENCY=200
POSTGRES_WORK_MEM=20MB
POSTGRES_MIN_WAL_SIZE=1GB
POSTGRES_MAX_WAL_SIZE=4GB

# Ollama Configuration
OLLAMA_VERSION=latest
OLLAMA_PORT=${OLLAMA_PORT}
OLLAMA_DATA=${OLLAMA_DATA}
OLLAMA_HOST=0.0.0.0
OLLAMA_ORIGINS=*
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=3
OLLAMA_KEEP_ALIVE=5m

# n8n Configuration
N8N_VERSION=latest
N8N_PORT=${N8N_PORT}
N8N_DATA=${N8N_DATA}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${JWT_SECRET}
N8N_PROTOCOL=https
N8N_HOST=\${DOMAIN_NAME}
N8N_EDITOR_BASE_URL=https://\${DOMAIN_NAME}
N8N_WEBHOOK_URL=https://\${DOMAIN_NAME}
WEBHOOK_URL=https://\${DOMAIN_NAME}
N8N_METRICS=true
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=${LOG_DIR}/n8n
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

# Qdrant Configuration
QDRANT_VERSION=latest
QDRANT_PORT=${QDRANT_PORT}
QDRANT_GRPC_PORT=${QDRANT_GRPC_PORT}
QDRANT_DATA=${QDRANT_DATA}
QDRANT_INIT_FILE_PATH=./qdrant-init.sh
QDRANT__LOG_LEVEL=INFO
QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=8

# API Keys (Optional)
OPENAI_API_KEY=${OPENAI_API_KEY:-}

# System Configuration
TZ=${TIMEZONE}
COMPOSE_PROJECT_NAME=ai-platform

# Resource Limits
POSTGRES_MEM_LIMIT=8g
OLLAMA_MEM_LIMIT=16g
N8N_MEM_LIMIT=4g
QDRANT_MEM_LIMIT=8g

# Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE="0 2 * * *"

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090

EOF

    chmod 600 "$CONFIG_FILE"
    log_success "Configuration file created: $CONFIG_FILE"
    save_state 2
}

# ==============================================================================
# SYSTEM UPDATES AND PACKAGES
# ==============================================================================

update_system() {
    log_step "Updating system packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get update || error_exit "Failed to update package lists"
    apt-get upgrade -y || error_exit "Failed to upgrade packages"
    apt-get dist-upgrade -y || error_exit "Failed to dist-upgrade"
    apt-get autoremove -y || log_warning "Failed to autoremove packages"
    apt-get autoclean -y || log_warning "Failed to autoclean"
    
    log_success "System packages updated"
    save_state 3
}

install_essential_packages() {
    log_step "Installing essential packages..."
    
    local packages=(
        curl
        wget
        git
        vim
        nano
        htop
        iotop
        nethogs
        net-tools
        dnsutils
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
        apt-transport-https
        build-essential
        jq
        unzip
        zip
        python3
        python3-pip
        python3-venv
        certbot
        python3-certbot-nginx
        ufw
        fail2ban
        logrotate
        rsync
        screen
        tmux
    )
    
    local total=${#packages[@]}
    local current=0
    
    for package in "${packages[@]}"; do
        current=$((current + 1))
        if ! dpkg -l | grep -q "^ii  $package "; then
            apt-get install -y "$package" || log_warning "Failed to install $package"
        fi
        show_progress $current $total "Installing packages..."
    done
    
    log_success "Essential packages installed"
    save_state 4
}

# ==============================================================================
# DOCKER INSTALLATION
# ==============================================================================

install_docker() {
    log_step "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        log_info "Docker already installed: $(docker --version)"
        return 0
    fi
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Verify installation
    if ! docker run hello-world &> /dev/null; then
        error_exit "Docker installation verification failed"
    fi
    
    log_success "Docker installed: $(docker --version)"
    save_state 5
}

configure_docker() {
    log_step "Configuring Docker..."
    
    # Create Docker daemon configuration
    mkdir -p /etc/docker
    
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.17.0.0/12",
      "size": 24
    }
  ]
}
EOF
    
    # Restart Docker to apply configuration
    systemctl restart docker
    
    log_success "Docker configured"
    save_state 6
}

create_docker_network() {
    log_step "Creating Docker network..."
    
    if docker network ls | grep -q "$DOCKER_NETWORK"; then
        log_info "Docker network already exists: $DOCKER_NETWORK"
    else
        docker network create \
            --driver bridge \
            --subnet "$SUBNET" \
            "$DOCKER_NETWORK" || error_exit "Failed to create Docker network"
        log_success "Docker network created: $DOCKER_NETWORK"
    fi
    
    save_state 7
}

# ==============================================================================
# FIREWALL CONFIGURATION
# ==============================================================================

configure_firewall() {
    log_step "Configuring firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp comment 'SSH'
    
    # Allow HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Allow service ports (only from localhost)
    ufw allow from 127.0.0.1 to any port ${POSTGRES_PORT} proto tcp comment 'PostgreSQL local'
    ufw allow from 127.0.0.1 to any port ${OLLAMA_PORT} proto tcp comment 'Ollama local'
    ufw allow from 127.0.0.1 to any port ${N8N_PORT} proto tcp comment 'n8n local'
    ufw allow from 127.0.0.1 to any port ${QDRANT_PORT} proto tcp comment 'Qdrant local'
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured and enabled"
    save_state 8
}

# ==============================================================================
# FAIL2BAN CONFIGURATION
# ==============================================================================

configure_fail2ban() {
    log_step "Configuring Fail2ban..."
    
    # Create local jail configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = ${SSL_EMAIL}
sendername = Fail2Ban

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
EOF
    
    # Start and enable Fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    log_success "Fail2ban configured and enabled"
    save_state 9
}
# ==============================================================================
# SSL CERTIFICATE GENERATION
# ==============================================================================

generate_ssl_certificates() {
    log_step "Generating SSL certificates..."
    
    local ssl_dir="${BASE_DIR}/ssl"
    
    # Check if domain resolves to this server
    local server_ip=$(curl -s ifconfig.me)
    local domain_ip=$(dig +short "$DOMAIN_NAME" | head -n1)
    
    if [ "$server_ip" != "$domain_ip" ]; then
        log_warning "Domain does not resolve to this server ($server_ip vs $domain_ip)"
        log_info "Generating self-signed certificates for development..."
        
        # Generate self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
            -keyout "${ssl_dir}/privkey.pem" \
            -out "${ssl_dir}/fullchain.pem" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN_NAME}" \
            2>/dev/null || error_exit "Failed to generate self-signed certificate"
        
        log_success "Self-signed certificates generated"
    else
        log_info "Domain resolves correctly. Requesting Let's Encrypt certificate..."
        
        # Stop any service that might be using port 80
        systemctl stop nginx 2>/dev/null || true
        
        # Request certificate
        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" \
            -d "$DOMAIN_NAME" \
            -d "*.${DOMAIN_NAME}" \
            --preferred-challenges http \
            || log_warning "Failed to obtain Let's Encrypt certificate, falling back to self-signed"
        
        if [ -f "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem" ]; then
            # Link certificates
            ln -sf "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem" "${ssl_dir}/fullchain.pem"
            ln -sf "/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem" "${ssl_dir}/privkey.pem"
            
            # Setup auto-renewal
            cat > /etc/cron.d/certbot-renewal << EOF
0 0,12 * * * root certbot renew --quiet --post-hook "systemctl reload nginx"
EOF
            
            log_success "Let's Encrypt certificates obtained and configured"
        else
            # Fallback to self-signed
            openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
                -keyout "${ssl_dir}/privkey.pem" \
                -out "${ssl_dir}/fullchain.pem" \
                -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN_NAME}" \
                2>/dev/null || error_exit "Failed to generate fallback certificate"
            
            log_success "Self-signed certificates generated as fallback"
        fi
    fi
    
    # Set proper permissions
    chmod 600 "${ssl_dir}/privkey.pem"
    chmod 644 "${ssl_dir}/fullchain.pem"
    
    save_state 10
}

# ==============================================================================
# POSTGRESQL INITIALIZATION SCRIPTS
# ==============================================================================

create_postgresql_init_script() {
    log_step "Creating PostgreSQL initialization scripts..."
    
    local init_dir="${BASE_DIR}/postgresql-init"
    mkdir -p "$init_dir"
    
    # Main initialization script
    cat > "${init_dir}/01-init-database.sql" << 'EOF'
-- ==============================================================================
-- PostgreSQL Initialization Script
-- Purpose: Create database structure for AI Platform
-- ==============================================================================

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS ai_platform;
CREATE SCHEMA IF NOT EXISTS n8n;
CREATE SCHEMA IF NOT EXISTS qdrant_metadata;

-- Set search path
ALTER DATABASE aiplatform SET search_path TO ai_platform, public;

-- ==============================================================================
-- AI Platform Tables
-- ==============================================================================

-- Users table
CREATE TABLE IF NOT EXISTS ai_platform.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);

-- API Keys table
CREATE TABLE IF NOT EXISTS ai_platform.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES ai_platform.users(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE
);

-- Conversations table
CREATE TABLE IF NOT EXISTS ai_platform.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES ai_platform.users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    model VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Messages table
CREATE TABLE IF NOT EXISTS ai_platform.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES ai_platform.conversations(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Embeddings table
CREATE TABLE IF NOT EXISTS ai_platform.embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content TEXT NOT NULL,
    embedding vector(1536),
    metadata JSONB,
    source VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Workflow executions table
CREATE TABLE IF NOT EXISTS ai_platform.workflow_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id VARCHAR(100) NOT NULL,
    user_id UUID REFERENCES ai_platform.users(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL,
    input_data JSONB,
    output_data JSONB,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP WITH TIME ZONE,
    duration_ms INTEGER
);

-- System metrics table
CREATE TABLE IF NOT EXISTS ai_platform.system_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    metric_type VARCHAR(100) NOT NULL,
    metric_value NUMERIC,
    metadata JSONB,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Audit log table
CREATE TABLE IF NOT EXISTS ai_platform.audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES ai_platform.users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100),
    resource_id UUID,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- Indexes
-- ==============================================================================

-- Users indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON ai_platform.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON ai_platform.users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON ai_platform.users(is_active);

-- API Keys indexes
CREATE INDEX IF NOT EXISTS idx_api_keys_user ON ai_platform.api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON ai_platform.api_keys(is_active);

-- Conversations indexes
CREATE INDEX IF NOT EXISTS idx_conversations_user ON ai_platform.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created ON ai_platform.conversations(created_at DESC);

-- Messages indexes
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON ai_platform.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON ai_platform.messages(created_at DESC);

-- Embeddings indexes
CREATE INDEX IF NOT EXISTS idx_embeddings_source ON ai_platform.embeddings(source);
CREATE INDEX IF NOT EXISTS idx_embeddings_vector ON ai_platform.embeddings USING ivfflat (embedding vector_cosine_ops);

-- Workflow executions indexes
CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow ON ai_platform.workflow_executions(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_user ON ai_platform.workflow_executions(user_id);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_status ON ai_platform.workflow_executions(status);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_started ON ai_platform.workflow_executions(started_at DESC);

-- System metrics indexes
CREATE INDEX IF NOT EXISTS idx_system_metrics_type ON ai_platform.system_metrics(metric_type);
CREATE INDEX IF NOT EXISTS idx_system_metrics_recorded ON ai_platform.system_metrics(recorded_at DESC);

-- Audit log indexes
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON ai_platform.audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON ai_platform.audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON ai_platform.audit_log(created_at DESC);

-- ==============================================================================
-- Functions and Triggers
-- ==============================================================================

-- Updated timestamp trigger function
CREATE OR REPLACE FUNCTION ai_platform.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
DROP TRIGGER IF EXISTS update_users_updated_at ON ai_platform.users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON ai_platform.users
    FOR EACH ROW
    EXECUTE FUNCTION ai_platform.update_updated_at_column();

DROP TRIGGER IF EXISTS update_conversations_updated_at ON ai_platform.conversations;
CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON ai_platform.conversations
    FOR EACH ROW
    EXECUTE FUNCTION ai_platform.update_updated_at_column();

-- Function to calculate conversation duration
CREATE OR REPLACE FUNCTION ai_platform.calculate_workflow_duration()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.finished_at IS NOT NULL AND NEW.started_at IS NOT NULL THEN
        NEW.duration_ms = EXTRACT(EPOCH FROM (NEW.finished_at - NEW.started_at)) * 1000;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS calculate_workflow_execution_duration ON ai_platform.workflow_executions;
CREATE TRIGGER calculate_workflow_execution_duration
    BEFORE UPDATE OF finished_at ON ai_platform.workflow_executions
    FOR EACH ROW
    EXECUTE FUNCTION ai_platform.calculate_workflow_duration();

-- ==============================================================================
-- Initial Data
-- ==============================================================================

-- Insert default admin user (password: ChangeMeImmediately123!)
INSERT INTO ai_platform.users (email, username, password_hash, is_admin)
VALUES (
    'admin@localhost',
    'admin',
    crypt('ChangeMeImmediately123!', gen_salt('bf', 10)),
    true
) ON CONFLICT (email) DO NOTHING;

-- ==============================================================================
-- Permissions
-- ==============================================================================

-- Grant schema usage
GRANT USAGE ON SCHEMA ai_platform TO aiplatform;
GRANT USAGE ON SCHEMA n8n TO aiplatform;
GRANT USAGE ON SCHEMA qdrant_metadata TO aiplatform;

-- Grant table permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ai_platform TO aiplatform;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA n8n TO aiplatform;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA qdrant_metadata TO aiplatform;

-- Grant sequence permissions
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ai_platform TO aiplatform;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA n8n TO aiplatform;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA ai_platform GRANT ALL ON TABLES TO aiplatform;
ALTER DEFAULT PRIVILEGES IN SCHEMA n8n GRANT ALL ON TABLES TO aiplatform;

EOF

    # Performance tuning script
    cat > "${init_dir}/02-performance-tuning.sql" << EOF
-- ==============================================================================
-- PostgreSQL Performance Tuning
-- ==============================================================================

-- Adjust planner settings
ALTER SYSTEM SET random_page_cost = '1.1';
ALTER SYSTEM SET effective_io_concurrency = '200';
ALTER SYSTEM SET default_statistics_target = '100';

-- Memory settings (these should match docker-compose environment variables)
ALTER SYSTEM SET shared_buffers = '${POSTGRES_SHARED_BUFFERS:-4GB}';
ALTER SYSTEM SET effective_cache_size = '${POSTGRES_EFFECTIVE_CACHE_SIZE:-12GB}';
ALTER SYSTEM SET maintenance_work_mem = '${POSTGRES_MAINTENANCE_WORK_MEM:-1GB}';
ALTER SYSTEM SET work_mem = '${POSTGRES_WORK_MEM:-20MB}';

-- WAL settings
ALTER SYSTEM SET wal_buffers = '${POSTGRES_WAL_BUFFERS:-16MB}';
ALTER SYSTEM SET min_wal_size = '${POSTGRES_MIN_WAL_SIZE:-1GB}';
ALTER SYSTEM SET max_wal_size = '${POSTGRES_MAX_WAL_SIZE:-4GB}';
ALTER SYSTEM SET checkpoint_completion_target = '${POSTGRES_CHECKPOINT_COMPLETION_TARGET:-0.9}';

-- Connection settings
ALTER SYSTEM SET max_connections = '${POSTGRES_MAX_CONNECTIONS:-200}';

-- Logging
ALTER SYSTEM SET log_statement = 'mod';
ALTER SYSTEM SET log_duration = 'on';
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET log_min_duration_statement = '1000';

-- Enable auto vacuum
ALTER SYSTEM SET autovacuum = 'on';
ALTER SYSTEM SET autovacuum_max_workers = '4';
ALTER SYSTEM SET autovacuum_naptime = '30s';

SELECT pg_reload_conf();
EOF

    # Maintenance script
    cat > "${init_dir}/03-maintenance-functions.sql" << 'EOF'
-- ==============================================================================
-- Maintenance Functions
-- ==============================================================================

-- Function to clean old audit logs
CREATE OR REPLACE FUNCTION ai_platform.cleanup_old_audit_logs(days_to_keep INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM ai_platform.audit_log
    WHERE created_at < CURRENT_TIMESTAMP - (days_to_keep || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to clean old metrics
CREATE OR REPLACE FUNCTION ai_platform.cleanup_old_metrics(days_to_keep INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM ai_platform.system_metrics
    WHERE recorded_at < CURRENT_TIMESTAMP - (days_to_keep || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get database statistics
CREATE OR REPLACE FUNCTION ai_platform.get_database_stats()
RETURNS TABLE (
    table_name TEXT,
    row_count BIGINT,
    total_size TEXT,
    index_size TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || tablename AS table_name,
        n_live_tup AS row_count,
        pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
        pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename)) AS index_size
    FROM pg_stat_user_tables
    WHERE schemaname = 'ai_platform'
    ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to analyze query performance
CREATE OR REPLACE FUNCTION ai_platform.get_slow_queries()
RETURNS TABLE (
    query TEXT,
    calls BIGINT,
    total_time DOUBLE PRECISION,
    mean_time DOUBLE PRECISION,
    max_time DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        substring(pg_stat_statements.query, 1, 100) AS query,
        pg_stat_statements.calls,
        pg_stat_statements.total_exec_time AS total_time,
        pg_stat_statements.mean_exec_time AS mean_time,
        pg_stat_statements.max_exec_time AS max_time
    FROM pg_stat_statements
    WHERE pg_stat_statements.mean_exec_time > 100
    ORDER BY pg_stat_statements.mean_exec_time DESC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

EOF

    log_success "PostgreSQL initialization scripts created"
    save_state 11
}

# ==============================================================================
# OLLAMA SETUP
# ==============================================================================

create_ollama_init_script() {
    log_step "Creating Ollama initialization script..."
    
    cat > "${BASE_DIR}/ollama-init.sh" << 'EOF'
#!/bin/bash
# ==============================================================================
# Ollama Initialization Script
# Purpose: Download and configure initial models
# ==============================================================================

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
LOG_FILE="/var/log/ollama-init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

wait_for_ollama() {
    log "Waiting for Ollama to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            log "Ollama is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log "ERROR: Ollama failed to start"
    return 1
}

pull_model() {
    local model=$1
    log "Pulling model: $model"
    
    if curl -s -X POST "$OLLAMA_HOST/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$model\"}" | grep -q "success"; then
        log "Successfully pulled: $model"
        return 0
    else
        log "WARNING: Failed to pull $model"
        return 1
    fi
}

main() {
    log "Starting Ollama initialization..."
    
    wait_for_ollama || exit 1
    
    # Pull essential models
    pull_model "llama2:7b"
    pull_model "mistral:7b"
    pull_model "nomic-embed-text"
    
    # List available models
    log "Available models:"
    curl -s "$OLLAMA_HOST/api/tags" | jq -r '.models[].name' | tee -a "$LOG_FILE"
    
    log "Ollama initialization complete"
}

main "$@"
EOF

    chmod +x "${BASE_DIR}/ollama-init.sh"
    log_success "Ollama initialization script created"
    save_state 12
}

# ==============================================================================
# QDRANT SETUP
# ==============================================================================

create_qdrant_init_script() {
    log_step "Creating Qdrant initialization script..."
    
    cat > "${BASE_DIR}/qdrant-init.sh" << 'EOF'
#!/bin/bash
# ==============================================================================
# Qdrant Initialization Script
# Purpose: Create initial collections and configurations
# ==============================================================================

set -e

QDRANT_HOST="${QDRANT_HOST:-http://localhost:6333}"
LOG_FILE="/var/log/qdrant-init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

wait_for_qdrant() {
    log "Waiting for Qdrant to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$QDRANT_HOST/collections" > /dev/null 2>&1; then
            log "Qdrant is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log "ERROR: Qdrant failed to start"
    return 1
}

create_collection() {
    local name=$1
    local vector_size=$2
    local distance=${3:-Cosine}
    
    log "Creating collection: $name (size: $vector_size, distance: $distance)"
    
    if curl -s -X PUT "$QDRANT_HOST/collections/$name" \
        -H "Content-Type: application/json" \
        -d "{
            \"vectors\": {
                \"size\": $vector_size,
                \"distance\": \"$distance\"
            },
            \"optimizers_config\": {
                \"indexing_threshold\": 10000
            },
            \"replication_factor\": 1
        }" | grep -q "true"; then
        log "Successfully created collection: $name"
        return 0
    else
        log "WARNING: Failed to create collection $name (may already exist)"
        return 1
    fi
}

main() {
    log "Starting Qdrant initialization..."
    
    wait_for_qdrant || exit 1
    
    # Create collections for different embedding models
    create_collection "embeddings_openai" 1536 "Cosine"
    create_collection "embeddings_nomic" 768 "Cosine"
    create_collection "embeddings_ollama" 4096 "Cosine"
    create_collection "documents" 1536 "Cosine"
    create_collection "conversations" 1536 "Cosine"
    
    # List collections
    log "Available collections:"
    curl -s "$QDRANT_HOST/collections" | jq -r '.result.collections[].name' | tee -a "$LOG_FILE"
    
    log "Qdrant initialization complete"
}

main "$@"
EOF

    chmod +x "${BASE_DIR}/qdrant-init.sh"
    log_success "Qdrant initialization script created"
    save_state 13
}
# ==============================================================================
# N8N WORKFLOW INITIALIZATION
# ==============================================================================

create_n8n_workflows() {
    log_step "Creating n8n workflow templates..."

    local workflow_dir="${N8N_DATA}/workflows"
    mkdir -p "$workflow_dir"

    # Health check workflow
    cat > "${workflow_dir}/health-check-workflow.json" << 'EOF'
{
  "name": "System Health Check",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "minutes",
              "minutesInterval": 5
            }
          ]
        }
      },
      "name": "Schedule Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "url": "=http://ollama:11434/api/tags",
        "options": {}
      },
      "name": "Check Ollama",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [450, 200]
    },
    {
      "parameters": {
        "url": "=http://qdrant:6333/collections",
        "options": {}
      },
      "name": "Check Qdrant",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [450, 400]
    },
    {
      "parameters": {
        "operation": "executeQuery",
        "query": "SELECT COUNT(*) as user_count FROM ai_platform.users;"
      },
      "name": "Check PostgreSQL",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2,
      "position": [450, 600],
      "credentials": {
        "postgres": {
          "id": "1",
          "name": "PostgreSQL account"
        }
      }
    },
    {
      "parameters": {
        "conditions": {
          "number": [
            {
              "value1": "={{$json.statusCode}}",
              "operation": "equal",
              "value2": 200
            }
          ]
        }
      },
      "name": "All Healthy",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [650, 300]
    },
    {
      "parameters": {
        "operation": "insert",
        "table": "ai_platform.system_metrics",
        "columns": "metric_type, metric_value, metadata",
        "additionalFields": {}
      },
      "name": "Log Health Status",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2,
      "position": [850, 300],
      "credentials": {
        "postgres": {
          "id": "1",
          "name": "PostgreSQL account"
        }
      }
    }
  ],
  "connections": {
    "Schedule Trigger": {
      "main": [
        [
          {
            "node": "Check Ollama",
            "type": "main",
            "index": 0
          },
          {
            "node": "Check Qdrant",
            "type": "main",
            "index": 0
          },
          {
            "node": "Check PostgreSQL",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Check Ollama": {
      "main": [
        [
          {
            "node": "All Healthy",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "All Healthy": {
      "main": [
        [
          {
            "node": "Log Health Status",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "active": true,
  "settings": {},
  "id": "health-check-workflow"
}
EOF

    # Backup workflow
    cat > "${workflow_dir}/backup-workflow.json" << 'EOF'
{
  "name": "Automated Backup",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hours",
              "hoursInterval": 24
            }
          ]
        }
      },
      "name": "Daily Schedule",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "command": "/root/scripts/backup.sh"
      },
      "name": "Run Backup Script",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [450, 300]
    },
    {
      "parameters": {
        "operation": "insert",
        "table": "ai_platform.audit_log",
        "columns": "action, resource_type, details"
      },
      "name": "Log Backup",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2,
      "position": [650, 300],
      "credentials": {
        "postgres": {
          "id": "1",
          "name": "PostgreSQL account"
        }
      }
    }
  ],
  "connections": {
    "Daily Schedule": {
      "main": [
        [
          {
            "node": "Run Backup Script",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Run Backup Script": {
      "main": [
        [
          {
            "node": "Log Backup",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "active": true,
  "settings": {},
  "id": "backup-workflow"
}
EOF

    log_success "n8n workflow templates created"
    save_state 14
}

# ==============================================================================
# DOCKER COMPOSE FILE GENERATION (FULLY CORRECTED)
# ==============================================================================

generate_docker_compose() {
    log_step "Generating Docker Compose configuration..."

    cat > "$DOCKER_COMPOSE_FILE" << EOF
# ==============================================================================
# Docker Compose Configuration for AI Platform
# Version: 4.0 - Comprehensive Audit Remediation
# Generated: $(date)
# ==============================================================================

version: '3.8'

networks:
  ${DOCKER_NETWORK}:
    driver: bridge
    ipam:
      config:
        - subnet: ${SUBNET}

volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      device: ${POSTGRES_DATA}
      o: bind
  ollama_data:
    driver: local
    driver_opts:
      type: none
      device: ${OLLAMA_DATA}
      o: bind
  n8n_data:
    driver: local
    driver_opts:
      type: none
      device: ${N8N_DATA}
      o: bind
  qdrant_data:
    driver: local
    driver_opts:
      type: none
      device: ${QDRANT_DATA}
      o: bind

services:
  # ============================================================================
  # PostgreSQL Database
  # ============================================================================
  postgres:
    image: pgvector/pgvector:${POSTGRES_VERSION:-pg16}
    container_name: ai-platform-postgres
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - postgres
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
      # Performance tuning
      POSTGRES_SHARED_BUFFERS: ${POSTGRES_SHARED_BUFFERS:-4GB}
      POSTGRES_EFFECTIVE_CACHE_SIZE: ${POSTGRES_EFFECTIVE_CACHE_SIZE:-12GB}
      POSTGRES_MAINTENANCE_WORK_MEM: ${POSTGRES_MAINTENANCE_WORK_MEM:-1GB}
      POSTGRES_WORK_MEM: ${POSTGRES_WORK_MEM:-20MB}
      POSTGRES_WAL_BUFFERS: ${POSTGRES_WAL_BUFFERS:-16MB}
      POSTGRES_MIN_WAL_SIZE: ${POSTGRES_MIN_WAL_SIZE:-1GB}
      POSTGRES_MAX_WAL_SIZE: ${POSTGRES_MAX_WAL_SIZE:-4GB}
      POSTGRES_CHECKPOINT_COMPLETION_TARGET: ${POSTGRES_CHECKPOINT_COMPLETION_TARGET:-0.9}
      POSTGRES_MAX_CONNECTIONS: ${POSTGRES_MAX_CONNECTIONS:-200}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${BASE_DIR}/postgresql-init:/docker-entrypoint-initdb.d:ro
      - ${BACKUP_DIR}/postgres:/backups
      - ${LOG_DIR}/postgres:/var/log/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    shm_size: 256mb
    command:
      - "postgres"
      - "-c"
      - "shared_preload_libraries=pg_stat_statements"
      - "-c"
      - "pg_stat_statements.track=all"
      - "-c"
      - "max_connections=\${POSTGRES_MAX_CONNECTIONS:-200}"
      - "-c"
      - "shared_buffers=\${POSTGRES_SHARED_BUFFERS:-4GB}"
      - "-c"
      - "effective_cache_size=\${POSTGRES_EFFECTIVE_CACHE_SIZE:-12GB}"
      - "-c"
      - "maintenance_work_mem=\${POSTGRES_MAINTENANCE_WORK_MEM:-1GB}"
      - "-c"
      - "work_mem=\${POSTGRES_WORK_MEM:-20MB}"
      - "-c"
      - "wal_buffers=\${POSTGRES_WAL_BUFFERS:-16MB}"
      - "-c"
      - "min_wal_size=\${POSTGRES_MIN_WAL_SIZE:-1GB}"
      - "-c"
      - "max_wal_size=\${POSTGRES_MAX_WAL_SIZE:-4GB}"
      - "-c"
      - "checkpoint_completion_target=\${POSTGRES_CHECKPOINT_COMPLETION_TARGET:-0.9}"
      - "-c"
      - "random_page_cost=1.1"
      - "-c"
      - "effective_io_concurrency=200"
      - "-c"
      - "log_statement=mod"
      - "-c"
      - "log_duration=on"
      - "-c"
      - "log_line_prefix=%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "
      - "-c"
      - "log_min_duration_statement=1000"
    deploy:
      resources:
        limits:
          cpus: '${POSTGRES_CPU_LIMIT:-4.0}'
          memory: ${POSTGRES_MEMORY_LIMIT:-16G}
        reservations:
          cpus: '${POSTGRES_CPU_RESERVATION:-2.0}'
          memory: ${POSTGRES_MEMORY_RESERVATION:-8G}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ============================================================================
  # Ollama LLM Service
  # ============================================================================
  ollama:
    image: ollama/ollama:${OLLAMA_VERSION:-latest}
    container_name: ai-platform-ollama
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - ollama
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    environment:
      OLLAMA_HOST: 0.0.0.0:11434
      OLLAMA_ORIGINS: "*"
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-4}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-3}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
    volumes:
      - ollama_data:/root/.ollama
      - ${LOG_DIR}/ollama:/var/log/ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '${OLLAMA_CPU_LIMIT:-8.0}'
          memory: ${OLLAMA_MEMORY_LIMIT:-32G}
        reservations:
          cpus: '${OLLAMA_CPU_RESERVATION:-4.0}'
          memory: ${OLLAMA_MEMORY_RESERVATION:-16G}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ============================================================================
  # n8n Workflow Automation
  # ============================================================================
  n8n:
    image: n8nio/n8n:${N8N_VERSION:-latest}
    container_name: ai-platform-n8n
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - n8n
    ports:
      - "127.0.0.1:${N8N_PORT}:5678"
    environment:
      # Basic configuration
      N8N_HOST: ${DOMAIN_NAME}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: https://${DOMAIN_NAME}/

      # Security
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_JWT_AUTH_ACTIVE: "true"
      N8N_JWT_AUTH_HEADER: "Authorization"
      N8N_JWT_AUTH_HEADER_VALUE_PREFIX: "Bearer"

      # Database connection
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_POSTGRESDB_SCHEMA: n8n

      # Execution
      EXECUTIONS_DATA_SAVE_ON_ERROR: "all"
      EXECUTIONS_DATA_SAVE_ON_SUCCESS: "all"
      EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS: "true"
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 336  # 14 days

      # Timezone
      GENERIC_TIMEZONE: ${TIMEZONE:-America/New_York}
      TZ: ${TIMEZONE:-America/New_York}

      # Logging
      N8N_LOG_LEVEL: ${N8N_LOG_LEVEL:-info}
      N8N_LOG_OUTPUT: console,file
      N8N_LOG_FILE_LOCATION: /home/node/.n8n/logs/
      N8N_LOG_FILE_COUNT_MAX: 10
      N8N_LOG_FILE_SIZE_MAX: 10

      # Performance
      N8N_CONCURRENCY_PRODUCTION_LIMIT: ${N8N_CONCURRENCY_LIMIT:-10}

      # External services
      N8N_METRICS: "true"
      N8N_DIAGNOSTICS_ENABLED: "true"
    volumes:
      - n8n_data:/home/node/.n8n
      - ${LOG_DIR}/n8n:/home/node/.n8n/logs
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
    depends_on:
      postgres:
        condition: service_healthy
      ollama:
        condition: service_healthy
      qdrant:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '${N8N_CPU_LIMIT:-2.0}'
          memory: ${N8N_MEMORY_LIMIT:-4G}
        reservations:
          cpus: '${N8N_CPU_RESERVATION:-1.0}'
          memory: ${N8N_MEMORY_RESERVATION:-2G}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ============================================================================
  # Qdrant Vector Database
  # ============================================================================
  qdrant:
    image: qdrant/qdrant:${QDRANT_VERSION:-latest}
    container_name: ai-platform-qdrant
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - qdrant
    ports:
      - "127.0.0.1:${QDRANT_PORT}:6333"
      - "127.0.0.1:${QDRANT_GRPC_PORT:-6334}:6334"
    environment:
      QDRANT__SERVICE__GRPC_PORT: ${QDRANT_GRPC_PORT:-6334}
      QDRANT__SERVICE__HTTP_PORT: 6333
      QDRANT__LOG_LEVEL: ${QDRANT_LOG_LEVEL:-INFO}
      QDRANT__STORAGE__STORAGE_PATH: /qdrant/storage
      QDRANT__STORAGE__SNAPSHOTS_PATH: /qdrant/snapshots
      QDRANT__STORAGE__ON_DISK_PAYLOAD: "true"
      QDRANT__STORAGE__WAL__WAL_CAPACITY_MB: 32
      QDRANT__STORAGE__OPTIMIZERS__DEFAULT_SEGMENT_NUMBER: 2
      QDRANT__SERVICE__MAX_REQUEST_SIZE_MB: 32
      QDRANT__SERVICE__MAX_WORKERS: ${QDRANT_MAX_WORKERS:-4}
    volumes:
      - qdrant_data:/qdrant/storage
      - ${BACKUP_DIR}/qdrant:/qdrant/snapshots
      - ${LOG_DIR}/qdrant:/qdrant/logs
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:6333/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '${QDRANT_CPU_LIMIT:-4.0}'
          memory: ${QDRANT_MEMORY_LIMIT:-8G}
        reservations:
          cpus: '${QDRANT_CPU_RESERVATION:-2.0}'
          memory: ${QDRANT_MEMORY_RESERVATION:-4G}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ============================================================================
  # Nginx Reverse Proxy
  # ============================================================================
  nginx:
    image: nginx:${NGINX_VERSION:-alpine}
    container_name: ai-platform-nginx
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - nginx
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAIN_NAME: ${DOMAIN_NAME}
      N8N_PORT: ${N8N_PORT}
      OLLAMA_PORT: ${OLLAMA_PORT}
      QDRANT_PORT: ${QDRANT_PORT}
    volumes:
      - ${BASE_DIR}/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${BASE_DIR}/nginx/conf.d:/etc/nginx/conf.d:ro
      - ${BASE_DIR}/ssl:/etc/nginx/ssl:ro
      - ${LOG_DIR}/nginx:/var/log/nginx
      - ${BASE_DIR}/nginx/html:/usr/share/nginx/html:ro
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    depends_on:
      - n8n
      - ollama
      - qdrant
    deploy:
      resources:
        limits:
          cpus: '${NGINX_CPU_LIMIT:-1.0}'
          memory: ${NGINX_MEMORY_LIMIT:-512M}
        reservations:
          cpus: '${NGINX_CPU_RESERVATION:-0.5}'
          memory: ${NGINX_MEMORY_RESERVATION:-256M}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ============================================================================
  # Redis Cache (for session management and caching)
  # ============================================================================
  redis:
    image: redis:${REDIS_VERSION:-alpine}
    container_name: ai-platform-redis
    restart: unless-stopped
    networks:
      ${DOCKER_NETWORK}:
        aliases:
          - redis
    ports:
      - "127.0.0.1:6379:6379"
    command: >
      redis-server
      --appendonly yes
      --appendfsync everysec
      --maxmemory ${REDIS_MAXMEMORY:-2gb}
      --maxmemory-policy allkeys-lru
      --save 900 1
      --save 300 10
      --save 60 10000
    volumes:
      - ${DATA_DIR}/redis:/data
      - ${LOG_DIR}/redis:/var/log/redis
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '${REDIS_CPU_LIMIT:-1.0}'
          memory: ${REDIS_MEMORY_LIMIT:-2G}
        reservations:
          cpus: '${REDIS_CPU_RESERVATION:-0.5}'
          memory: ${REDIS_MEMORY_RESERVATION:-1G}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

EOF

    log_success "Docker Compose configuration generated"
    save_state 15
}

# ==============================================================================
# NGINX CONFIGURATION
# ==============================================================================

generate_nginx_config() {
    log_step "Generating Nginx configuration..."

    local nginx_dir="${BASE_DIR}/nginx"
    mkdir -p "${nginx_dir}/conf.d" "${nginx_dir}/html"

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

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Buffers
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;

    # Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml application/atom+xml image/svg+xml
               text/x-component text/x-cross-domain-policy;
    gzip_disable "msie6";

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Site configuration
    cat > "${nginx_dir}/conf.d/default.conf" << EOF
# ==============================================================================
# AI Platform Nginx Configuration
# ==============================================================================

# Upstream definitions
upstream n8n_backend {
    server n8n:5678;
    keepalive 32;
}

upstream ollama_backend {
    server ollama:11434;
    keepalive 32;
}

upstream qdrant_backend {
    server qdrant:6333;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME};

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Root location
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    # n8n workflow automation
    location /n8n/ {
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;

        proxy_pass http://n8n_backend/;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade \$http_upgrade;

        proxy_buffering off;
        proxy_cache_bypass \$http_upgrade;

        proxy_connect_timeout 90s;
        proxy_send_timeout 90s;
        proxy_read_timeout 90s;
    }

    # Ollama API
    location /ollama/ {
        limit_req zone=api burst=50 nodelay;

        proxy_pass http://ollama_backend/;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_request_buffering off;

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        client_max_body_size 100M;
    }

    # Qdrant vector database
    location /qdrant/ {
        limit_req zone=api burst=100 nodelay;

        proxy_pass http://qdrant_backend/;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Status endpoint (restricted to localhost)
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    # Create default index.html
    cat > "${nginx_dir}/html/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Platform</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            text-align: center;
            padding: 2rem;
            max-width: 800px;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        p {
            font-size: 1.2rem;
            margin-bottom: 2rem;
            opacity: 0.9;
        }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1.5rem;
            margin-top: 3rem;
        }
        .service {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            padding: 2rem;
            border-radius: 15px;
            transition: transform 0.3s ease, background 0.3s ease;
        }
        .service:hover {
            transform: translateY(-5px);
            background: rgba(255,255,255,0.2);
        }
        .service h3 {
            margin-bottom: 0.5rem;
            font-size: 1.5rem;
        }
        .service p {
            font-size: 0.9rem;
            margin-bottom: 1rem;
        }
        .service a {
            display: inline-block;
            padding: 0.5rem 1rem;
            background: rgba(255,255,255,0.2);
            color: #fff;
            text-decoration: none;
            border-radius: 5px;
            transition: background 0.3s ease;
        }
        .service a:hover {
            background: rgba(255,255,255,0.3);
        }
        .status {
            margin-top: 3rem;
            padding: 1rem;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
        }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #4ade80;
            margin-right: 0.5rem;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 AI Platform</h1>
        <p>Your comprehensive AI development and deployment environment</p>

        <div class="services">
            <div class="service">
                <h3>n8n</h3>
                <p>Workflow Automation</p>
                <a href="/n8n/">Access n8n</a>
            </div>
            <div class="service">
                <h3>Ollama</h3>
                <p>LLM Service</p>
                <a href="/ollama/api/tags">View Models</a>
            </div>
            <div class="service">
                <h3>Qdrant</h3>
                <p>Vector Database</p>
                <a href="/qdrant/collections">View Collections</a>
            </div>
        </div>

        <div class="status">
            <span class="status-indicator"></span>
            <span>All systems operational</span>
        </div>
    </div>
</body>
</html>
EOF

    log_success "Nginx configuration generated"
    save_state 16
}
# ==============================================================================
# SYSTEMD SERVICE CONFIGURATION
# ==============================================================================

create_systemd_service() {
    log_step "Creating systemd service..."

    cat > /etc/systemd/system/ai-platform.service << EOF
[Unit]
Description=AI Platform Docker Compose Services
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${BASE_DIR}
EnvironmentFile=${CONFIG_FILE}

# Pre-start checks
ExecStartPre=/usr/bin/docker network inspect ${DOCKER_NETWORK} || /usr/bin/docker network create --driver bridge --subnet ${SUBNET} ${DOCKER_NETWORK}
ExecStartPre=/bin/sleep 2

# Start services
ExecStart=/usr/bin/docker compose -f ${DOCKER_COMPOSE_FILE} up -d

# Health check after start
ExecStartPost=/bin/sleep 10
ExecStartPost=${BASE_DIR}/health-check.sh

# Stop services
ExecStop=/usr/bin/docker compose -f ${DOCKER_COMPOSE_FILE} down

# Reload services
ExecReload=/usr/bin/docker compose -f ${DOCKER_COMPOSE_FILE} restart

# Restart policy
Restart=on-failure
RestartSec=30s

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ai-platform

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable ai-platform.service

    log_success "Systemd service created and enabled"
    save_state 17
}

# ==============================================================================
# BACKUP SCRIPT GENERATION
# ==============================================================================

create_backup_script() {
    log_step "Creating backup script..."

    cat > "${BASE_DIR}/backup.sh" << 'EOF'
#!/bin/bash
# ==============================================================================
# AI Platform Backup Script
# ==============================================================================

set -euo pipefail

# Configuration
BACKUP_BASE="/mnt/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${BACKUP_BASE}/backup.log"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create timestamped backup directory
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"
mkdir -p "${BACKUP_DIR}"

log "Starting backup to ${BACKUP_DIR}"

# ==============================================================================
# PostgreSQL Backup
# ==============================================================================
log "Backing up PostgreSQL..."
docker exec ai-platform-postgres pg_dumpall -U "${POSTGRES_USER}" | \
    gzip > "${BACKUP_DIR}/postgres_full_${TIMESTAMP}.sql.gz" || \
    error_exit "PostgreSQL backup failed"

# Individual database backup with custom format
docker exec ai-platform-postgres pg_dump -U "${POSTGRES_USER}" \
    -Fc -f "/backups/postgres_${POSTGRES_DB}_${TIMESTAMP}.dump" \
    "${POSTGRES_DB}" || log "WARNING: Custom format backup failed"

log "PostgreSQL backup completed"

# ==============================================================================
# Ollama Models Backup
# ==============================================================================
log "Backing up Ollama models..."
OLLAMA_BACKUP="${BACKUP_DIR}/ollama_${TIMESTAMP}.tar.gz"
tar czf "${OLLAMA_BACKUP}" -C /mnt/data/ollama . || \
    log "WARNING: Ollama backup failed"

log "Ollama backup completed"

# ==============================================================================
# n8n Data Backup
# ==============================================================================
log "Backing up n8n data..."
N8N_BACKUP="${BACKUP_DIR}/n8n_${TIMESTAMP}.tar.gz"
tar czf "${N8N_BACKUP}" -C /mnt/data/n8n . || \
    log "WARNING: n8n backup failed"

log "n8n backup completed"

# ==============================================================================
# Qdrant Snapshot
# ==============================================================================
log "Creating Qdrant snapshot..."
docker exec ai-platform-qdrant curl -X POST \
    "http://localhost:6333/snapshots" || \
    log "WARNING: Qdrant snapshot failed"

# Copy Qdrant data
QDRANT_BACKUP="${BACKUP_DIR}/qdrant_${TIMESTAMP}.tar.gz"
tar czf "${QDRANT_BACKUP}" -C /mnt/data/qdrant . || \
    log "WARNING: Qdrant backup failed"

log "Qdrant backup completed"

# ==============================================================================
# Configuration Backup
# ==============================================================================
log "Backing up configuration files..."
CONFIG_BACKUP="${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz"
tar czf "${CONFIG_BACKUP}" \
    /root/scripts/config.env \
    /root/scripts/docker-compose.yml \
    /root/scripts/nginx \
    /root/scripts/ssl \
    /root/scripts/postgresql-init \
    2>/dev/null || log "WARNING: Config backup incomplete"

log "Configuration backup completed"

# ==============================================================================
# Verification
# ==============================================================================
log "Verifying backups..."
for file in "${BACKUP_DIR}"/*.{gz,dump}; do
    if [ -f "$file" ]; then
        size=$(du -h "$file" | cut -f1)
        log "  - $(basename "$file"): $size"
    fi
done

# Calculate total backup size
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "Total backup size: ${TOTAL_SIZE}"

# ==============================================================================
# Cleanup Old Backups
# ==============================================================================
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_BASE}" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true

REMAINING=$(find "${BACKUP_BASE}" -maxdepth 1 -type d | wc -l)
log "Remaining backup sets: $((REMAINING - 1))"

# ==============================================================================
# Backup Completion
# ==============================================================================
log "Backup completed successfully"

# Optional: Upload to remote storage
if [ -n "${BACKUP_REMOTE_PATH:-}" ]; then
    log "Uploading to remote storage..."
    rsync -az --delete "${BACKUP_DIR}/" "${BACKUP_REMOTE_PATH}/" || \
        log "WARNING: Remote upload failed"
fi

exit 0
EOF

    chmod +x "${BASE_DIR}/backup.sh"

    # Create backup cron job
    cat > /etc/cron.d/ai-platform-backup << EOF
# AI Platform automated backups
0 2 * * * root ${BASE_DIR}/backup.sh >> ${LOG_DIR}/backup.log 2>&1
EOF

    log_success "Backup script created with daily cron job"
    save_state 18
}

# ==============================================================================
# HEALTH CHECK SCRIPT
# ==============================================================================

create_health_check_script() {
    log_step "Creating health check script..."

    cat > "${BASE_DIR}/health-check.sh" << 'EOF'
#!/bin/bash
# ==============================================================================
# AI Platform Health Check Script
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
TIMEOUT=10
ERRORS=0

# Logging
log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
    ERRORS=$((ERRORS + 1))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_info() {
    echo -e "ℹ $*"
}

echo "========================================"
echo "AI Platform Health Check"
echo "========================================"
echo ""

# ==============================================================================
# Docker Status
# ==============================================================================
echo "Docker Status:"
if systemctl is-active --quiet docker; then
    log_success "Docker service is running"
else
    log_error "Docker service is not running"
fi

# ==============================================================================
# Container Status
# ==============================================================================
echo ""
echo "Container Status:"

check_container() {
    local name=$1
    local port=$2

    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "unknown")
        if [ "$status" = "healthy" ]; then
            log_success "$name is running and healthy"
        elif [ "$status" = "unknown" ]; then
            log_warning "$name is running (no health check configured)"
        else
            log_error "$name is running but unhealthy (status: $status)"
        fi
    else
        log_error "$name is not running"
    fi
}

check_container "ai-platform-postgres" "5432"
check_container "ai-platform-ollama" "11434"
check_container "ai-platform-n8n" "5678"
check_container "ai-platform-qdrant" "6333"
check_container "ai-platform-nginx" "443"
check_container "ai-platform-redis" "6379"

# ==============================================================================
# Service Endpoints
# ==============================================================================
echo ""
echo "Service Endpoints:"

check_endpoint() {
    local name=$1
    local url=$2

    if curl -sf --max-time "$TIMEOUT" "$url" > /dev/null 2>&1; then
        log_success "$name is accessible"
    else
        log_error "$name is not accessible at $url"
    fi
}

check_endpoint "Ollama API" "http://localhost:11434/api/tags"
check_endpoint "Qdrant API" "http://localhost:6333/collections"
check_endpoint "n8n Web" "http://localhost:5678/healthz"
check_endpoint "Nginx" "http://localhost/health"

# ==============================================================================
# PostgreSQL Connection
# ==============================================================================
echo ""
echo "PostgreSQL Status:"

if docker exec ai-platform-postgres pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
    log_success "PostgreSQL is accepting connections"

    # Check database
    if docker exec ai-platform-postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Database ${POSTGRES_DB} is accessible"
    else
        log_error "Cannot access database ${POSTGRES_DB}"
    fi

    # Check extensions
    EXTENSIONS=$(docker exec ai-platform-postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('vector', 'pg_stat_statements', 'uuid-ossp');" | xargs)
    if [ "$EXTENSIONS" -eq 3 ]; then
        log_success "All required PostgreSQL extensions are installed"
    else
        log_warning "Some PostgreSQL extensions may be missing (found: $EXTENSIONS/3)"
    fi
else
    log_error "PostgreSQL is not accepting connections"
fi

# ==============================================================================
# Ollama Models
# ==============================================================================
echo ""
echo "Ollama Models:"

MODELS=$(docker exec ai-platform-ollama ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
if [ "$MODELS" -gt 0 ]; then
    log_success "$MODELS model(s) installed"
    docker exec ai-platform-ollama ollama list 2>/dev/null | tail -n +2 | while read -r line; do
        echo "  - $(echo "$line" | awk '{print $1}')"
    done
else
    log_warning "No Ollama models installed"
fi

# ==============================================================================
# Qdrant Collections
# ==============================================================================
echo ""
echo "Qdrant Collections:"

COLLECTIONS=$(curl -sf "http://localhost:6333/collections" 2>/dev/null | jq -r '.result.collections | length' || echo "0")
if [ "$COLLECTIONS" -gt 0 ]; then
    log_success "$COLLECTIONS collection(s) configured"
    curl -sf "http://localhost:6333/collections" 2>/dev/null | jq -r '.result.collections[].name' | while read -r collection; do
        echo "  - $collection"
    done
else
    log_warning "No Qdrant collections found"
fi

# ==============================================================================
# Disk Space
# ==============================================================================
echo ""
echo "Disk Space:"

DISK_USAGE=$(df -h /mnt/data | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    log_success "Disk usage: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -lt 90 ]; then
    log_warning "Disk usage: ${DISK_USAGE}% (consider cleanup)"
else
    log_error "Disk usage: ${DISK_USAGE}% (critical - cleanup required)"
fi

df -h /mnt/data | tail -1

# ==============================================================================
# Memory Usage
# ==============================================================================
echo ""
echo "Memory Usage:"

MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
if [ "$MEMORY_USAGE" -lt 80 ]; then
    log_success "Memory usage: ${MEMORY_USAGE}%"
elif [ "$MEMORY_USAGE" -lt 90 ]; then
    log_warning "Memory usage: ${MEMORY_USAGE}%"
else
    log_error "Memory usage: ${MEMORY_USAGE}% (high)"
fi

free -h | grep -E "Mem|Swap"

# ==============================================================================
# Network Connectivity
# ==============================================================================
echo ""
echo "Network:"

if docker network inspect ai-platform-network > /dev/null 2>&1; then
    CONTAINERS=$(docker network inspect ai-platform-network | jq -r '.[0].Containers | length')
    log_success "Docker network configured ($CONTAINERS containers)"
else
    log_error "Docker network not found"
fi

# ==============================================================================
# SSL Certificates
# ==============================================================================
echo ""
echo "SSL Certificates:"

if [ -f "/root/scripts/ssl/fullchain.pem" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in /root/scripts/ssl/fullchain.pem | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

    if [ "$DAYS_LEFT" -gt 30 ]; then
        log_success "SSL certificate valid (expires in $DAYS_LEFT days)"
    elif [ "$DAYS_LEFT" -gt 7 ]; then
        log_warning "SSL certificate expires in $DAYS_LEFT days"
    else
        log_error "SSL certificate expires in $DAYS_LEFT days (renewal needed)"
    fi
else
    log_error "SSL certificate not found"
fi

# ==============================================================================
# Recent Logs
# ==============================================================================
echo ""
echo "Recent Errors (last 10):"

if [ -f "/mnt/data/logs/setup_errors_"*.log ]; then
    RECENT_ERRORS=$(tail -10 /mnt/data/logs/setup_errors_*.log 2>/dev/null | wc -l)
    if [ "$RECENT_ERRORS" -eq 0 ]; then
        log_success "No recent errors in logs"
    else
        log_warning "$RECENT_ERRORS recent error entries"
        tail -5 /mnt/data/logs/setup_errors_*.log 2>/dev/null | sed 's/^/  /'
    fi
else
    log_info "No error logs found"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================"
if [ $ERRORS -eq 0 ]; then
    log_success "All health checks passed"
    exit 0
else
    log_error "$ERRORS health check(s) failed"
    exit 1
fi
EOF

    chmod +x "${BASE_DIR}/health-check.sh"

    log_success "Health check script created"
    save_state 19
}

# ==============================================================================
# MONITORING SCRIPT
# ==============================================================================

create_monitoring_script() {
    log_step "Creating monitoring script..."

    cat > "${BASE_DIR}/monitor.sh" << 'EOF'
#!/bin/bash
# ==============================================================================
# AI Platform Monitoring Script
# ==============================================================================

set -euo pipefail

# Configuration
METRICS_FILE="/mnt/data/logs/metrics_$(date +%Y%m%d).json"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85
ALERT_THRESHOLD_DISK=80

# Collect metrics
collect_metrics() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # System metrics
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100)}')
    local disk_usage=$(df -h /mnt/data | tail -1 | awk '{print $5}' | sed 's/%//')

    # Container metrics
    local containers_running=$(docker ps --format '{{.Names}}' | wc -l)
    local containers_total=$(docker ps -a --format '{{.Names}}' | wc -l)

    # Service-specific metrics
    local postgres_connections=$(docker exec ai-platform-postgres psql -U "${POSTGRES_USER}" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
    local ollama_models=$(docker exec ai-platform-ollama ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
    local qdrant_collections=$(curl -sf "http://localhost:6333/collections" 2>/dev/null | jq -r '.result.collections | length' || echo "0")

    # Create JSON metrics
    cat >> "$METRICS_FILE" << JSON
{
  "timestamp": "$timestamp",
  "system": {
    "cpu_usage": $cpu_usage,
    "memory_usage": $mem_usage,
    "disk_usage": $disk_usage
  },
  "containers": {
    "running": $containers_running,
    "total": $containers_total
  },
  "services": {
    "postgres_connections": $postgres_connections,
    "ollama_models": $ollama_models,
    "qdrant_collections": $qdrant_collections
  }
}
JSON

    # Check thresholds and alert
    if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        echo "ALERT: High CPU usage: ${cpu_usage}%"
    fi

    if (( $(echo "$mem_usage > $ALERT_THRESHOLD_MEM" | bc -l) )); then
        echo "ALERT: High memory usage: ${mem_usage}%"
    fi

    if [ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]; then
        echo "ALERT: High disk usage: ${disk_usage}%"
    fi
}

# Main execution
collect_metrics

# Cleanup old metrics (keep 30 days)
find /mnt/data/logs -name "metrics_*.json" -mtime +30 -delete 2>/dev/null || true

exit 0
EOF

    chmod +x "${BASE_DIR}/monitor.sh"

    # Create monitoring cron job
    cat > /etc/cron.d/ai-platform-monitor << EOF
# AI Platform monitoring (every 5 minutes)
*/5 * * * * root ${BASE_DIR}/monitor.sh >> ${LOG_DIR}/monitor.log 2>&1
EOF

    log_success "Monitoring script created with cron job"
    save_state 20
}

# ==============================================================================
# FINAL VERIFICATION AND STARTUP
# ==============================================================================

verify_and_start_services() {
    log_step "Verifying configuration and starting services..."

    # Verify all required files exist
    local required_files=(
        "$CONFIG_FILE"
        "$DOCKER_COMPOSE_FILE"
        "${BASE_DIR}/postgresql-init/01-init-db.sql"
        "${BASE_DIR}/ollama-init.sh"
        "${BASE_DIR}/qdrant-init.sh"
        "${BASE_DIR}/backup.sh"
        "${BASE_DIR}/health-check.sh"
        "${BASE_DIR}/monitor.sh"
        "${BASE_DIR}/nginx/nginx.conf"
        "${BASE_DIR}/nginx/conf.d/default.conf"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error_exit "Required file not found: $file"
        fi
    done

    log_success "All required files verified"

    # Create Docker network if it doesn't exist
    if ! docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
        log_info "Creating Docker network..."
        docker network create --driver bridge --subnet "$SUBNET" "$DOCKER_NETWORK" || \
            error_exit "Failed to create Docker network"
    fi

    # Pull all required images
    log_info "Pulling Docker images (this may take a while)..."
    docker compose -f "$DOCKER_COMPOSE_FILE" pull || \
        log_warning "Some images failed to pull, will try to use existing/build"

    # Start services
    log_info "Starting AI Platform services..."
    if systemctl start ai-platform.service; then
        log_success "Services started via systemd"
    else
        log_warning "Systemd start failed, trying docker compose directly..."
        docker compose -f "$DOCKER_COMPOSE_FILE" up -d || \
            error_exit "Failed to start services"
    fi

    # Wait for services to be ready
    log_info "Waiting for services to be ready (this may take a minute)..."
    sleep 30

    # Initialize services
    log_info "Initializing Ollama models..."
    "${BASE_DIR}/ollama-init.sh" || log_warning "Ollama initialization had issues"

    log_info "Initializing Qdrant collections..."
    "${BASE_DIR}/qdrant-init.sh" || log_warning "Qdrant initialization had issues"

    # Run health check
    log_info "Running health check..."
    if "${BASE_DIR}/health-check.sh"; then
        log_success "Health check passed"
    else
        log_warning "Some health checks failed, review output above"
    fi

    save_state 21
}

# ==============================================================================
# FINAL SUMMARY AND NEXT STEPS
# ==============================================================================

display_summary() {
    log_step "Setup Complete!"

    echo ""
    echo "========================================"
    echo "AI Platform Setup Summary"
    echo "========================================"
    echo ""
    echo "Services:"
    echo "  • PostgreSQL:  localhost:${POSTGRES_PORT}"
    echo "  • Ollama:      localhost:${OLLAMA_PORT}"
    echo "  • n8n:         https://${DOMAIN_NAME}/n8n/"
    echo "  • Qdrant:      https://${DOMAIN_NAME}/qdrant/"
    echo "  • Web Portal:  https://${DOMAIN_NAME}/"
    echo ""
    echo "Directories:"
    echo "  • Base:        ${BASE_DIR}"
    echo "  • Data:        ${DATA_DIR}"
    echo "  • Logs:        ${LOG_DIR}"
    echo "  • Backups:     ${BACKUP_DIR}"
    echo ""
    echo "Credentials:"
    echo "  • PostgreSQL User:     ${POSTGRES_USER}"
    echo "  • PostgreSQL Password: ${POSTGRES_PASSWORD}"
    echo "  • PostgreSQL Database: ${POSTGRES_DB}"
    echo "  • n8n User:            ${N8N_BASIC_AUTH_USER}"
    echo "  • n8n Password:        ${N8N_BASIC_AUTH_PASSWORD}"
    echo ""
    echo "Management Commands:"
    echo "  • Check status:   systemctl status ai-platform"
    echo "  • View logs:      docker compose -f ${DOCKER_COMPOSE_FILE} logs -f"
    echo "  • Health check:   ${BASE_DIR}/health-check.sh"
    echo "  • Backup:         ${BASE_DIR}/backup.sh"
    echo "  • Stop services:  systemctl stop ai-platform"
    echo "  • Start services: systemctl start ai-platform"
    echo ""
    echo "Automated Tasks:"
    echo "  • Daily backups at 2:00 AM"
    echo "  • Metrics collection every 5 minutes"
    echo "  • SSL certificate auto-renewal (if Let's Encrypt)"
    echo ""
    echo "Next Steps:"
    echo "  1. Review the health check output above"
    echo "  2. Access n8n web interface and import workflows"
    echo "  3. Verify Ollama models are downloaded"
    echo "  4. Test Qdrant collections"
    echo "  5. Run: ${SCRIPT_DIR}/2-configure-services.sh"
    echo ""
    echo "Documentation:"
    echo "  • Setup log:  ${SETUP_LOG}"
    echo "  • Error log:  ${ERROR_LOG}"
    echo ""
    echo "========================================"
    echo ""

    # Save completion marker
    echo "SETUP_COMPLETE=true" >> "$STATE_FILE"
    echo "SETUP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$STATE_FILE"

    log_success "Setup completed successfully!"
    log_info "System is ready for configuration (Script 2)"
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

main() {
    log_step "Starting AI Platform Setup (Script 1)..."
    log_info "Script Version: $SCRIPT_VERSION"
    log_info "Execution Time: $(date)"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root"
    fi

    # Check system requirements
    check_system_requirements

    # Collect service selection and hardware profile
    collect_service_selection
    detect_hardware_profile

    # Collect user configuration
    collect_user_input

    # Load or create state
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        log_info "Resuming from step ${CURRENT_STEP:-1}"
    else
        CURRENT_STEP=1
    fi

    # Execute setup steps
    [ "${CURRENT_STEP:-1}" -le 1 ] && { step_1_hardware_detection; save_state 1; }
    [ "${CURRENT_STEP:-1}" -le 2 ] && { step_2_docker_installation; save_state 2; }
    [ "${CURRENT_STEP:-1}" -le 3 ] && { step_3_nvidia_toolkit; save_state 3; }
    [ "${CURRENT_STEP:-1}" -le 4 ] && { step_4_ollama_installation; save_state 4; }
    [ "${CURRENT_STEP:-1}" -le 5 ] && { step_5_validation; save_state 5; }
    [ "${CURRENT_STEP:-1}" -le 6 ] && { step_6_interactive_questionnaire; save_state 6; }
    [ "${CURRENT_STEP:-1}" -le 7 ] && { step_7_generate_master_env; save_state 7; }
    [ "${CURRENT_STEP:-1}" -le 8 ] && { step_8_service_env_files; save_state 8; }
    [ "${CURRENT_STEP:-1}" -le 9 ] && { step_9_postgresql_init; save_state 9; }
    [ "${CURRENT_STEP:-1}" -le 10 ] && { step_10_redis_config; save_state 10; }
    [ "${CURRENT_STEP:-1}" -le 11 ] && { step_11_litellm_config; save_state 11; }
    [ "${CURRENT_STEP:-1}" -le 12 ] && { step_12_dify_config; save_state 12; }
    [ "${CURRENT_STEP:-1}" -le 13 ] && { step_13_caddyfile_gen; save_state 13; }
    [ "${CURRENT_STEP:-1}" -le 14 ] && { step_14_monitoring_config; save_state 14; }
    [ "${CURRENT_STEP:-1}" -le 15 ] && { step_15_convenience_scripts; save_state 15; }
    [ "${CURRENT_STEP:-1}" -le 16 ] && { step_16_deploy_services; save_state 16; }
    [ "${CURRENT_STEP:-1}" -le 17 ] && { step_17_verification_summary; save_state 17; }

    log_info "All setup steps completed successfully!"

    # Clean up
    rm -f "$STATE_FILE"

    return 0
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

# Trap errors and cleanup
trap 'error_exit "Script interrupted at line $LINENO"' ERR INT TERM

# Run main function
main "$@"

exit 0
