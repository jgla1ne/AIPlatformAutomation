#!/usr/bin/env bash

################################################################################
# SCRIPT 1 v100.0.0 - SYSTEM SETUP & CONFIGURATION GENERATION
# PURPOSE: Prepare system, collect choices, generate configs (NO DEPLOYMENT)
################################################################################

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"
readonly ACTUAL_USER="${SUDO_USER:-$USER}"
readonly ACTUAL_HOME=$(eval echo "~$ACTUAL_USER")

# Default paths
readonly DATA_DIR="${ROOT_PATH}/data"
readonly CONFIG_DIR="${ROOT_PATH}/config"
readonly STACK_DIR="${ROOT_PATH}/stacks"
readonly LOG_DIR="${ROOT_PATH}/logs"

# Log file
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Service selections (will be populated by user)
declare -A SERVICE_ENABLED
declare -A SERVICE_PORTS
declare -A SERVICE_CONFIGS

# ============================================================================
# LOGGING
# ============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$LOG_DIR"
    touch "$LOG_FILE"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_step() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ STEP $1/${2}: ${3}${NC}"
    log "STEP $1/$2: $3"
}

log_success() {
    echo -e "${GREEN}✓ $*${NC}"
    log "SUCCESS: $*"
}

log_warning() {
    echo -e "${YELLOW}⚠ $*${NC}"
    log "WARNING: $*"
}

log_error() {
    echo -e "${RED}✗ ERROR: $*${NC}"
    log "ERROR: $*"
}

# ============================================================================
# PRINT HEADER
# ============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                                ║${NC}"
    echo -e "${BOLD}${CYAN}║         AI PLATFORM SETUP v100.0.0 - CONFIGURATION             ║${NC}"
    echo -e "${BOLD}${CYAN}║         (System Prep + Config Generation - No Deployment)      ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                                ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# STEP 1: PREREQUISITES CHECK
# ============================================================================

check_prerequisites() {
    log_step "1" "25" "CHECKING PREREQUISITES"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
        exit 1
    fi
    
    if [[ -z "$ACTUAL_USER" || "$ACTUAL_USER" == "root" ]]; then
        log_error "Cannot determine actual user. Do not run as root directly."
        exit 1
    fi
    
    log_success "Running as: $ACTUAL_USER (sudo)"
}

# ============================================================================
# STEP 2: SYSTEM HEALTH CHECK
# ============================================================================

system_health_check() {
    log_step "2" "25" "SYSTEM HEALTH CHECK"
    
    echo ""
    echo -e "${CYAN}Checking system requirements...${NC}"
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warning "OS is $ID (recommended: Ubuntu 22.04+)"
    else
        log_success "OS: Ubuntu $VERSION_ID"
    fi
    
    # Check RAM
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 8 ]]; then
        log_warning "RAM: ${total_ram}GB (recommended: 16GB+)"
    else
        log_success "RAM: ${total_ram}GB"
    fi
    
    # Check disk space
    local free_space=$(df -BG "$ROOT_PATH" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space -lt 50 ]]; then
        log_warning "Free space: ${free_space}GB (recommended: 100GB+)"
    else
        log_success "Free space: ${free_space}GB"
    fi
    
    # Check GPU
    if command -v nvidia-smi &>/dev/null; then
        local gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        log_success "GPU: $gpu_info"
        HAS_GPU=true
    else
        log_warning "No NVIDIA GPU detected (CPU-only mode)"
        HAS_GPU=false
    fi
    
    # Check ports in use
    echo ""
    echo -e "${CYAN}Checking port availability...${NC}"
    
    local common_ports=(80 443 5432 6379 8080 8443 11434)
    local ports_in_use=()
    
    for port in "${common_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            ports_in_use+=("$port")
        fi
    done
    
    if [[ ${#ports_in_use[@]} -gt 0 ]]; then
        log_warning "Ports already in use: ${ports_in_use[*]}"
        echo "  (You'll be able to choose alternative ports)"
    else
        log_success "All common ports available"
    fi
    
    echo ""
    read -p "Continue with setup? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        log_error "Setup cancelled by user"
        exit 0
    fi
}

# ============================================================================
# STEP 3: INSTALL SYSTEM PACKAGES
# ============================================================================

install_system_packages() {
    log_step "3" "25" "INSTALLING SYSTEM PACKAGES"
    
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        jq \
        gnupg \
        lsb-release \
        ca-certificates \
        software-properties-common \
        apt-transport-https \
        apparmor \
        apparmor-utils \
        rsync \
        unzip
    
    log_success "System packages installed"
}

# ============================================================================
# STEP 4: INSTALL DOCKER
# ============================================================================

install_docker() {
    log_step "4" "25" "INSTALLING DOCKER"
    
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_warning "Docker already installed (version $docker_version)"
        return 0
    fi
    
    # Add Docker repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker installed"
}

# ============================================================================
# STEP 5: CONFIGURE DOCKER FOR USER
# ============================================================================

configure_docker_user() {
    log_step "5" "25" "CONFIGURING DOCKER FOR USER"
    
    if ! getent group docker > /dev/null; then
        groupadd docker
    fi
    
    usermod -aG docker "$ACTUAL_USER"
    
    log_success "User added to docker group"
    log_warning "User must logout/login for docker group to take effect"
}

# ============================================================================
# STEP 6: INSTALL NVIDIA CONTAINER TOOLKIT (IF GPU)
# ============================================================================

install_nvidia_toolkit() {
    log_step "6" "25" "INSTALLING NVIDIA CONTAINER TOOLKIT"
    
    if [[ "$HAS_GPU" != "true" ]]; then
        log_warning "No GPU detected, skipping NVIDIA toolkit"
        return 0
    fi
    
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_warning "NVIDIA Container Toolkit already configured"
        return 0
    fi
    
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
    
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    
    log_success "NVIDIA Container Toolkit installed"
}

# ============================================================================
# STEP 7: INSTALL TAILSCALE
# ============================================================================

install_tailscale() {
    log_step "7" "25" "INSTALLING TAILSCALE"
    
    if command -v tailscale &>/dev/null; then
        local ts_version=$(tailscale version | head -1)
        log_warning "Tailscale already installed ($ts_version)"
        return 0
    fi
    
    curl -fsSL https://tailscale.com/install.sh | sh
    
    log_success "Tailscale installed"
    log_warning "Run 'sudo tailscale up' after setup to configure"
}

# ============================================================================
# STEP 8: CONFIGURE APPARMOR
# ============================================================================

configure_apparmor() {
    log_step "8" "25" "CONFIGURING APPARMOR"
    
    if ! systemctl is-active --quiet apparmor; then
        log_warning "AppArmor is not active, skipping"
        return 0
    fi
    
    log "AppArmor is active"
    
    systemctl stop docker 2>/dev/null || true
    
    aa-remove-unknown 2>/dev/null || true
    
    systemctl restart apparmor
    
    systemctl start docker
    
    if systemctl is-active --quiet docker; then
        log_success "AppArmor configured, Docker restarted"
    else
        log_error "Docker failed to start after AppArmor configuration"
        return 1
    fi
}

# ============================================================================
# STEP 9: CREATE DIRECTORY STRUCTURE
# ============================================================================

create_directory_structure() {
    log_step "9" "25" "CREATING DIRECTORY STRUCTURE"
    
    # Core directories
    sudo -u "$ACTUAL_USER" mkdir -p \
        "$DATA_DIR" \
        "$CONFIG_DIR" \
        "$STACK_DIR"/{core,automation,optional} \
        "$LOG_DIR"
    
    # Service-specific data directories (will create only for enabled services later)
    sudo -u "$ACTUAL_USER" mkdir -p \
        "$DATA_DIR"/.tmp
    
    # Set ownership
    chown -R "$ACTUAL_USER:$ACTUAL_USER" \
        "$DATA_DIR" \
        "$CONFIG_DIR" \
        "$STACK_DIR" \
        "$LOG_DIR"
    
    log_success "Directory structure created"
}

# ============================================================================
# STEP 10: SELECT REVERSE PROXY
# ============================================================================

select_reverse_proxy() {
    log_step "10" "25" "SELECT REVERSE PROXY"
    
    echo ""
    echo -e "${BOLD}${CYAN}Choose Reverse Proxy:${NC}"
    echo "  1. Caddy  (automatic HTTPS, simpler config)"
    echo "  2. Nginx  (more control, manual SSL)"
    echo "  3. None   (direct access, no proxy)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-3] (default: 1): " proxy_choice
        proxy_choice="${proxy_choice:-1}"
        
        case "$proxy_choice" in
            1)
                REVERSE_PROXY="caddy"
                SERVICE_ENABLED[caddy]=true
                log_success "Selected: Caddy"
                break
                ;;
            2)
                REVERSE_PROXY="nginx"
                SERVICE_ENABLED[nginx]=true
                log_success "Selected: Nginx"
                break
                ;;
            3)
                REVERSE_PROXY="none"
                log_success "Selected: No reverse proxy"
                break
                ;;
            *)
                log_error "Invalid choice"
                ;;
        esac
    done
    
    # Proxy port configuration
    if [[ "$REVERSE_PROXY" != "none" ]]; then
        echo ""
        echo -e "${CYAN}Configure proxy ports (80/443 will be used by $REVERSE_PROXY):${NC}"
        
        read -p "HTTP port [80]: " http_port
        SERVICE_PORTS[proxy_http]="${http_port:-80}"
        
        read -p "HTTPS port [443]: " https_port
        SERVICE_PORTS[proxy_https]="${https_port:-443}"
    fi
}

# ============================================================================
# STEP 11: SELECT CORE SERVICES
# ============================================================================

select_core_services() {
    log_step "11" "25" "SELECT CORE SERVICES"
    
    echo ""
    echo -e "${BOLD}${CYAN}Core Services (LLM Stack):${NC}"
    echo ""
    
    # Ollama (required)
    SERVICE_ENABLED[ollama]=true
    read -p "Ollama port [11434]: " port
    SERVICE_PORTS[ollama]="${port:-11434}"
    log_success "Ollama enabled on port ${SERVICE_PORTS[ollama]}"
    
    # Open WebUI (required)
    SERVICE_ENABLED[webui]=true
    read -p "Open WebUI port [8080]: " port
    SERVICE_PORTS[webui]="${port:-8080}"
    log_success "Open WebUI enabled on port ${SERVICE_PORTS[webui]}"
    
    # LiteLLM
    read -p "Enable LiteLLM proxy? (y/n) [y]: " enable
    if [[ "${enable:-y}" == "y" ]]; then
        SERVICE_ENABLED[litellm]=true
        read -p "LiteLLM port [4000]: " port
        SERVICE_PORTS[litellm]="${port:-4000}"
        log_success "LiteLLM enabled on port ${SERVICE_PORTS[litellm]}"
    fi
    
    # PostgreSQL
    read -p "Enable PostgreSQL? (y/n) [y]: " enable
    if [[ "${enable:-y}" == "y" ]]; then
        SERVICE_ENABLED[postgres]=true
        read -p "PostgreSQL port [5432]: " port
        SERVICE_PORTS[postgres]="${port:-5432}"
        log_success "PostgreSQL enabled on port ${SERVICE_PORTS[postgres]}"
    fi
    
    # Redis
    read -p "Enable Redis? (y/n) [y]: " enable
    if [[ "${enable:-y}" == "y" ]]; then
        SERVICE_ENABLED[redis]=true
        read -p "Redis port [6379]: " port
        SERVICE_PORTS[redis]="${port:-6379}"
        log_success "Redis enabled on port ${SERVICE_PORTS[redis]}"
    fi
}

# ============================================================================
# STEP 12: SELECT AUTOMATION SERVICES
# ============================================================================

select_automation_services() {
    log_step "12" "25" "SELECT AUTOMATION SERVICES"
    
    echo ""
    echo -e "${BOLD}${CYAN}Automation Services:${NC}"
    echo ""
    
    # Tailscale (already installed, just configure)
    echo ""
    echo -e "${CYAN}Tailscale Configuration:${NC}"
    read -p "Tailscale HTTPS port [8443]: " ts_port
    SERVICE_PORTS[tailscale_https]="${ts_port:-8443}"
    log_success "Tailscale will use port ${SERVICE_PORTS[tailscale_https]} for HTTPS"
    
    # Signal-API
    read -p "Enable Signal-API notifications? (y/n) [n]: " enable
    if [[ "${enable:-n}" == "y" ]]; then
        SERVICE_ENABLED[signal_api]=true
        read -p "Signal-API port [8082]: " port
        SERVICE_PORTS[signal_api]="${port:-8082}"
        read -p "Signal phone number (with country code, e.g., +1234567890): " phone
        SERVICE_CONFIGS[signal_phone]="$phone"
        log_success "Signal-API enabled on port ${SERVICE_PORTS[signal_api]}"
    fi
    
    # Google Drive Sync
    read -p "Enable Google Drive backup sync? (y/n) [n]: " enable
    if [[ "${enable:-n}" == "y" ]]; then
        SERVICE_ENABLED[gdrive_sync]=true
        read -p "Google Drive folder ID: " folder_id
        SERVICE_CONFIGS[gdrive_folder_id]="$folder_id"
        read -p "Service account JSON path (leave empty to configure later): " json_path
        SERVICE_CONFIGS[gdrive_json_path]="$json_path"
        log_success "Google Drive sync enabled"
    fi
    
    # Platform Health Monitoring
    read -p "Enable platform health monitoring? (y/n) [y]: " enable
    if [[ "${enable:-y}" == "y" ]]; then
        SERVICE_ENABLED[health_monitor]=true
        log_success "Health monitoring enabled"
    fi
}

# ============================================================================
# STEP 13: SELECT OPTIONAL SERVICES
# ============================================================================

select_optional_services() {
    log_step "13" "25" "SELECT OPTIONAL SERVICES"
    
    echo ""
    echo -e "${BOLD}${CYAN}Optional Services:${NC}"
    echo ""
    
    # Langfuse
    read -p "Enable Langfuse (LLM observability)? (y/n) [n]: " enable
    if [[ "${enable:-n}" == "y" ]]; then
        SERVICE_ENABLED[langfuse]=true
        read -p "Langfuse port [3000]: " port
        SERVICE_PORTS[langfuse]="${port:-3000}"
        log_success "Langfuse enabled on port ${SERVICE_PORTS[langfuse]}"
    fi
    
    # N8N
    read -p "Enable N8N (workflow automation)? (y/n) [n]: " enable
    if [[ "${enable:-n}" == "y" ]]; then
        SERVICE_ENABLED[n8n]=true
        read -p "N8N port [5678]: " port
        SERVICE_PORTS[n8n]="${port:-5678}"
        log_success "N8N enabled on port ${SERVICE_PORTS[n8n]}"
    fi
    
    # Qdrant
    read -p "Enable Qdrant (vector database)? (y/n) [n]: " enable
    if [[ "${enable:-n}" == "y" ]]; then
        SERVICE_ENABLED[qdrant]=true
        read -p "Qdrant port [6333]: " port
        SERVICE_PORTS[qdrant]="${port:-6333}"
        log_success "Qdrant enabled on port ${SERVICE_PORTS[qdrant]}"
    fi
}

# ============================================================================
# STEP 14: SELECT OLLAMA MODELS
# ============================================================================

select_ollama_models() {
    log_step "14" "25" "SELECT OLLAMA MODELS"
    
    echo ""
    echo -e "${BOLD}${CYAN}Available Ollama models (type name or number):${NC}"
    echo ""
    echo "  1. llama3.2       - Meta Llama 3.2 (3B)"
    echo "  2. llama3.2:1b    - Meta Llama 3.2 (1B)"
    echo "  3. llama3.1       - Meta Llama 3.1 (8B)"
    echo "  4. qwen2.5-coder  - Qwen 2.5 Coder (7B)"
    echo "  5. mistral        - Mistral 7B"
    echo "  6. phi3           - Microsoft Phi-3 (3.8B)"
    echo "  7. gemma2         - Google Gemma 2 (9B)"
    echo "  8. deepseek-coder - DeepSeek Coder (6.7B)"
    echo ""
    
    read -p "Enter model names or numbers (space-separated) [1 4]: " model_input
    model_input="${model_input:-1 4}"
    
    # Convert numbers to names
    declare -A model_map=(
        ["1"]="llama3.2"
        ["2"]="llama3.2:1b"
        ["3"]="llama3.1"
        ["4"]="qwen2.5-coder"
        ["5"]="mistral"
        ["6"]="phi3"
        ["7"]="gemma2"
        ["8"]="deepseek-coder"
    )
    
    OLLAMA_MODELS=""
    for item in $model_input; do
        if [[ -n "${model_map[$item]:-}" ]]; then
            OLLAMA_MODELS="$OLLAMA_MODELS ${model_map[$item]}"
        else
            OLLAMA_MODELS="$OLLAMA_MODELS $item"
        fi
    done
    
    OLLAMA_MODELS=$(echo "$OLLAMA_MODELS" | xargs)
    
    log_success "Selected models: $OLLAMA_MODELS"
}

# ============================================================================
# STEP 15: COLLECT EXTERNAL API KEYS
# ============================================================================

collect_api_keys() {
    log_step "15" "25" "COLLECT EXTERNAL API KEYS"
    
    echo ""
    echo -e "${BOLD}${CYAN}External LLM Provider API Keys (leave empty to skip):${NC}"
    echo ""
    
    read -sp "OpenAI API Key: " openai_key
    echo ""
    API_KEYS[openai]="$openai_key"
    
    read -sp "Anthropic API Key: " anthropic_key
    echo ""
    API_KEYS[anthropic]="$anthropic_key"
    
    read -sp "Google AI (Gemini) API Key: " google_key
    echo ""
    API_KEYS[google]="$google_key"
    
    read -sp "Groq API Key: " groq_key
    echo ""
    API_KEYS[groq]="$groq_key"
    
    read -sp "DeepSeek API Key: " deepseek_key
    echo ""
    API_KEYS[deepseek]="$deepseek_key"
    
    read -sp "OpenRouter API Key: " openrouter_key
    echo ""
    API_KEYS[openrouter]="$openrouter_key"
    
    log_success "API keys collected (can be added later to .env)"
}

# ============================================================================
# STEP 16: GENERATE SECRETS
# ============================================================================

generate_secrets() {
    log_step "16" "25" "GENERATING SECRETS"
    
    SECRETS[postgres_password]=$(openssl rand -hex 32)
    SECRETS[litellm_master_key]=$(openssl rand -hex 32)
    SECRETS[litellm_salt_key]=$(openssl rand -hex 16)
    SECRETS[webui_secret_key]=$(openssl rand -hex 32)
    SECRETS[webui_jwt_secret]=$(openssl rand -hex 32)
    SECRETS[redis_password]=$(openssl rand -hex 32)
    
    if [[ "${SERVICE_ENABLED[n8n]:-false}" == "true" ]]; then
        SECRETS[n8n_encryption_key]=$(openssl rand -hex 32)
    fi
    
    if [[ "${SERVICE_ENABLED[langfuse]:-false}" == "true" ]]; then
        SECRETS[langfuse_salt]=$(openssl rand -hex 32)
        SECRETS[nextauth_secret]=$(openssl rand -hex 32)
    fi
    
    log_success "All secrets generated"
}

# ============================================================================
# STEP 17: GENERATE ENVIRONMENT FILE
# ============================================================================

generate_env_file() {
    log_step "17" "25" "GENERATING ENVIRONMENT FILE"
    
    local env_file="${ROOT_PATH}/.env"
    
    sudo -u "$ACTUAL_USER" touch "$env_file"
    
    cat > "$env_file" <<EOF
# AI Platform Environment Configuration v100.0.0
# Auto-generated on $(date)
# WARNING: Contains sensitive secrets - protect this file (chmod 600)

# ============================================================================
# SYSTEM PATHS
# ============================================================================
ROOT_PATH=${ROOT_PATH}
DATA_DIR=${DATA_DIR}
CONFIG_DIR=${CONFIG_DIR}
STACK_DIR=${STACK_DIR}
LOG_DIR=${LOG_DIR}

# ============================================================================
# REVERSE PROXY CONFIGURATION
# ============================================================================
REVERSE_PROXY=${REVERSE_PROXY}
PROXY_HTTP_PORT=${SERVICE_PORTS[proxy_http]:-80}
PROXY_HTTPS_PORT=${SERVICE_PORTS[proxy_https]:-443}

# ============================================================================
# CORE SERVICES - PORTS
# ============================================================================
OLLAMA_PORT=${SERVICE_PORTS[ollama]}
WEBUI_PORT=${SERVICE_PORTS[webui]}
LITELLM_PORT=${SERVICE_PORTS[litellm]:-4000}
POSTGRES_PORT=${SERVICE_PORTS[postgres]:-5432}
REDIS_PORT=${SERVICE_PORTS[redis]:-6379}

# ============================================================================
# AUTOMATION SERVICES - PORTS
# ============================================================================
TAILSCALE_HTTPS_PORT=${SERVICE_PORTS[tailscale_https]}
SIGNAL_API_PORT=${SERVICE_PORTS[signal_api]:-8082}

# ============================================================================
# OPTIONAL SERVICES - PORTS
# ============================================================================
LANGFUSE_PORT=${SERVICE_PORTS[langfuse]:-3000}
N8N_PORT=${SERVICE_PORTS[n8n]:-5678}
QDRANT_PORT=${SERVICE_PORTS[qdrant]:-6333}

# ============================================================================
# SERVICE ENABLEMENT FLAGS
# ============================================================================
ENABLE_LITELLM=${SERVICE_ENABLED[litellm]:-false}
ENABLE_POSTGRES=${SERVICE_ENABLED[postgres]:-false}
ENABLE_REDIS=${SERVICE_ENABLED[redis]:-false}
ENABLE_CADDY=${SERVICE_ENABLED[caddy]:-false}
ENABLE_NGINX=${SERVICE_ENABLED[nginx]:-false}
ENABLE_SIGNAL_API=${SERVICE_ENABLED[signal_api]:-false}
ENABLE_GDRIVE_SYNC=${SERVICE_ENABLED[gdrive_sync]:-false}
ENABLE_HEALTH_MONITOR=${SERVICE_ENABLED[health_monitor]:-false}
ENABLE_LANGFUSE=${SERVICE_ENABLED[langfuse]:-false}
ENABLE_N8N=${SERVICE_ENABLED[n8n]:-false}
ENABLE_QDRANT=${SERVICE_ENABLED[qdrant]:-false}

# ============================================================================
# POSTGRESQL CONFIGURATION
# ============================================================================
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${SECRETS[postgres_password]}
POSTGRES_DB=aiplatform
DATABASE_URL=postgresql://aiplatform:${SECRETS[postgres_password]}@postgres:${SERVICE_PORTS[postgres]:-5432}/aiplatform

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
REDIS_HOST=redis
REDIS_PORT=${SERVICE_PORTS[redis]:-6379}
REDIS_PASSWORD=${SECRETS[redis_password]}

# ============================================================================
# LITELLM CONFIGURATION
# ============================================================================
LITELLM_MASTER_KEY=${SECRETS[litellm_master_key]}
LITELLM_SALT_KEY=${SECRETS[litellm_salt_key]}
LITELLM_DATABASE_URL=postgresql://aiplatform:${SECRETS[postgres_password]}@postgres:${SERVICE_PORTS[postgres]:-5432}/aiplatform

# ============================================================================
# OPEN WEBUI CONFIGURATION
# ============================================================================
WEBUI_SECRET_KEY=${SECRETS[webui_secret_key]}
WEBUI_JWT_SECRET_KEY=${SECRETS[webui_jwt_secret]}
OLLAMA_BASE_URL=http://ollama:${SERVICE_PORTS[ollama]}

# ============================================================================
# EXTERNAL LLM PROVIDER API KEYS
# ============================================================================
OPENAI_API_KEY=${API_KEYS[openai]:-}
ANTHROPIC_API_KEY=${API_KEYS[anthropic]:-}
GOOGLE_API_KEY=${API_KEYS[google]:-}
GROQ_API_KEY=${API_KEYS[groq]:-}
DEEPSEEK_API_KEY=${API_KEYS[deepseek]:-}
OPENROUTER_API_KEY=${API_KEYS[openrouter]:-}

# ============================================================================
# OLLAMA MODELS
# ============================================================================
OLLAMA_MODELS="${OLLAMA_MODELS}"

# ============================================================================
# TAILSCALE CONFIGURATION
# ============================================================================
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-ai-platform}
TAILSCALE_AUTH_KEY=

# ============================================================================
# SIGNAL-API CONFIGURATION
# ============================================================================
SIGNAL_PHONE_NUMBER=${SERVICE_CONFIGS[signal_phone]:-}

# ============================================================================
# GOOGLE DRIVE BACKUP CONFIGURATION
# ============================================================================
GDRIVE_FOLDER_ID=${SERVICE_CONFIGS[gdrive_folder_id]:-}
GDRIVE_SERVICE_ACCOUNT_JSON=${SERVICE_CONFIGS[gdrive_json_path]:-}

# ============================================================================
# LANGFUSE CONFIGURATION (if enabled)
# ============================================================================
LANGFUSE_PUBLIC_KEY=
LANGFUSE_SECRET_KEY=
LANGFUSE_HOST=https://cloud.langfuse.com
SALT=${SECRETS[langfuse_salt]:-}
NEXTAUTH_SECRET=${SECRETS[nextauth_secret]:-}
NEXTAUTH_URL=http://localhost:${SERVICE_PORTS[langfuse]:-3000}

# ============================================================================
# N8N CONFIGURATION (if enabled)
# ============================================================================
N8N_ENCRYPTION_KEY=${SECRETS[n8n_encryption_key]:-}
N8N_HOST=localhost
N8N_PORT=${SERVICE_PORTS[n8n]:-5678}
N8N_PROTOCOL=http

# ============================================================================
# DOCKER COMPOSE SETTINGS
# ============================================================================
COMPOSE_PROJECT_NAME=ai-platform
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# ============================================================================
# GPU CONFIGURATION
# ============================================================================
HAS_GPU=${HAS_GPU}
EOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$env_file"
    chmod 600 "$env_file"
    
    log_success "Environment file created: $env_file"
}

# ============================================================================
# STEP 18: GENERATE LITELLM CONFIG
# ============================================================================

generate_litellm_config() {
    log_step "18" "25" "GENERATING LITELLM CONFIGURATION"
    
    if [[ "${SERVICE_ENABLED[litellm]:-false}" != "true" ]]; then
        log_warning "LiteLLM not enabled, skipping config"
        return 0
    fi
    
    sudo -u "$ACTUAL_USER" mkdir -p "${CONFIG_DIR}/litellm"
    local config_file="${CONFIG_DIR}/litellm/config.yaml"
    
    cat > "$config_file" <<EOF
# LiteLLM Configuration v100.0.0
# Auto-generated on $(date)

model_list:
EOF
    
    # Add Ollama models
    for model in $OLLAMA_MODELS; do
        local clean_name="${model//:/-}"
        cat >> "$config_file" <<EOF
  - model_name: ollama/${clean_name}
    litellm_params:
      model: ollama/${model}
      api_base: http://ollama:${SERVICE_PORTS[ollama]}
      stream: true
      max_tokens: 4096
      
EOF
    done
    
    # Add external providers (only if API keys provided)
    if [[ -n "${API_KEYS[openai]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
      max_tokens: 16384
      
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
      max_tokens: 16384
      
EOF
    fi
    
    if [[ -n "${API_KEYS[anthropic]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
      max_tokens: 8192
      
  - model_name: claude-3-5-haiku
    litellm_params:
      model: anthropic/claude-3-5-haiku-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
      max_tokens: 8192
      
EOF
    fi
    
    if [[ -n "${API_KEYS[google]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash-exp
      api_key: os.environ/GOOGLE_API_KEY
      max_tokens: 8192
      
EOF
    fi
    
    if [[ -n "${API_KEYS[groq]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: llama-3.3-70b
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: os.environ/GROQ_API_KEY
      max_tokens: 32768
      
EOF
    fi
    
    if [[ -n "${API_KEYS[deepseek]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: os.environ/DEEPSEEK_API_KEY
      max_tokens: 8192
      
EOF
    fi
    
    if [[ -n "${API_KEYS[openrouter]:-}" ]]; then
        cat >> "$config_file" <<EOF
  - model_name: openrouter-auto
    litellm_params:
      model: openrouter/auto
      api_key: os.environ/OPENROUTER_API_KEY
      max_tokens: 4096
      
EOF
    fi
    
    # Add router settings
    cat >> "$config_file" <<EOF

router_settings:
  routing_strategy: simple-shuffle
EOF
    
    if [[ "${SERVICE_ENABLED[redis]:-false}" == "true" ]]; then
        cat >> "$config_file" <<EOF
  redis_host: redis
  redis_port: ${SERVICE_PORTS[redis]}
EOF
    fi
    
    cat >> "$config_file" <<EOF
  num_retries: 3
  timeout: 600
  fallbacks:
    - ollama/${OLLAMA_MODELS%% *}

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
EOF
    
    if [[ "${SERVICE_ENABLED[postgres]:-false}" == "true" ]]; then
        cat >> "$config_file" <<EOF
  database_url: os.environ/LITELLM_DATABASE_URL
  store_model_in_db: true
EOF
    fi
    
    if [[ "${SERVICE_ENABLED[redis]:-false}" == "true" ]]; then
        cat >> "$config_file" <<EOF
  cache: true
  cache_params:
    type: redis
    host: redis
    port: ${SERVICE_PORTS[redis]}
    password: os.environ/REDIS_PASSWORD
    ttl: 3600
EOF
    fi
    
    cat >> "$config_file" <<EOF

litellm_settings:
  drop_params: true
  set_verbose: false
  json_logs: true
  request_timeout: 600
  telemetry: false
EOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$config_file"
    chmod 644 "$config_file"
    
    log_success "LiteLLM configuration created"
}

# ============================================================================
# STEP 19: GENERATE PROXY CONFIG
# ============================================================================

generate_proxy_config() {
    log_step "19" "25" "GENERATING REVERSE PROXY CONFIGURATION"
    
    if [[ "$REVERSE_PROXY" == "none" ]]; then
        log_warning "No reverse proxy selected, skipping"
        return 0
    fi
    
    if [[ "$REVERSE_PROXY" == "caddy" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${CONFIG_DIR}/caddy"
        local config_file="${CONFIG_DIR}/caddy/Caddyfile"
        
        cat > "$config_file" <<EOF
# Caddy Configuration v100.0.0
# Auto-generated on $(date)

:${SERVICE_PORTS[proxy_http]} {
    # Open WebUI
    handle /webui/* {
        uri strip_prefix /webui
        reverse_proxy webui:${SERVICE_PORTS[webui]}
    }
    
    # LiteLLM API
    handle /api/* {
        reverse_proxy litellm:${SERVICE_PORTS[litellm]:-4000}
    }
    
    # Ollama API
    handle /ollama/* {
        uri strip_prefix /ollama
        reverse_proxy ollama:${SERVICE_PORTS[ollama]}
    }
    
    # Default to WebUI
    handle {
        reverse_proxy webui:${SERVICE_PORTS[webui]}
    }
}
EOF
        
        chown "$ACTUAL_USER:$ACTUAL_USER" "$config_file"
        chmod 644 "$config_file"
        
        log_success "Caddy configuration created"
        
    elif [[ "$REVERSE_PROXY" == "nginx" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${CONFIG_DIR}/nginx"
        local config_file="${CONFIG_DIR}/nginx/nginx.conf"
        
        cat > "$config_file" <<EOF
# Nginx Configuration v100.0.0
# Auto-generated on $(date)

events {
    worker_connections 1024;
}

http {
    upstream webui {
        server webui:${SERVICE_PORTS[webui]};
    }
    
    upstream litellm {
        server litellm:${SERVICE_PORTS[litellm]:-4000};
    }
    
    upstream ollama {
        server ollama:${SERVICE_PORTS[ollama]};
    }
    
    server {
        listen ${SERVICE_PORTS[proxy_http]};
        
        location /webui/ {
            proxy_pass http://webui/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        
        location /api/ {
            proxy_pass http://litellm/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        
        location /ollama/ {
            proxy_pass http://ollama/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        
        location / {
            proxy_pass http://webui;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF
        
        chown "$ACTUAL_USER:$ACTUAL_USER" "$config_file"
        chmod 644 "$config_file"
        
        log_success "Nginx configuration created"
    fi
}

# ============================================================================
# STEP 20: GENERATE TAILSCALE CONFIG
# ============================================================================

generate_tailscale_config() {
    log_step "20" "25" "GENERATING TAILSCALE CONFIGURATION"
    
    sudo -u "$ACTUAL_USER" mkdir -p "${CONFIG_DIR}/tailscale"
    local config_file="${CONFIG_DIR}/tailscale/config.sh"
    
    cat > "$config_file" <<EOF
#!/usr/bin/env bash
# Tailscale Configuration Script v100.0.0
# Run this after initial setup to configure Tailscale

# Configure Tailscale with HTTPS on port ${SERVICE_PORTS[tailscale_https]}
sudo tailscale up \\
    --hostname="${TAILSCALE_HOSTNAME:-ai-platform}" \\
    --accept-routes \\
    --accept-dns \\
    --ssh \\
    --operator="$ACTUAL_USER"

# Enable HTTPS (requires Tailscale configured domain)
sudo tailscale serve https:${SERVICE_PORTS[tailscale_https]} / http://localhost:${SERVICE_PORTS[webui]}

echo "Tailscale configured!"
echo "Access your platform at: https://\$(tailscale status | grep '${TAILSCALE_HOSTNAME:-ai-platform}' | awk '{print \$1}'):${SERVICE_PORTS[tailscale_https]}"
EOF
    
    chmod +x "$config_file"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$config_file"
    
    log_success "Tailscale configuration script created"
    log_warning "Run: bash ${config_file} after setup completes"
}

# ============================================================================
# STEP 21: GENERATE GDRIVE SYNC CONFIG
# ============================================================================

generate_gdrive_config() {
    log_step "21" "25" "GENERATING GOOGLE DRIVE SYNC CONFIGURATION"
    
    if [[ "${SERVICE_ENABLED[gdrive_sync]:-false}" != "true" ]]; then
        log_warning "Google Drive sync not enabled, skipping"
        return 0
    fi
    
    sudo -u "$ACTUAL_USER" mkdir -p "${CONFIG_DIR}/gdrive"
    local config_file="${CONFIG_DIR}/gdrive/rclone.conf"
    
    cat > "$config_file" <<EOF
# Rclone Configuration for Google Drive Backup
# Configure manually with: rclone config
# Or place your service account JSON and configure programmatically

[gdrive]
type = drive
scope = drive
service_account_file = ${SERVICE_CONFIGS[gdrive_json_path]:-/path/to/service-account.json}
EOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$config_file"
    chmod 600 "$config_file"
    
    # Create sync script
    local sync_script="${ROOT_PATH}/scripts/gdrive-sync.sh"
    
    cat > "$sync_script" <<'SYNCEOF'
#!/usr/bin/env bash
# Google Drive Backup Sync Script v100.0.0

source "$(dirname "$0")/../.env"

LOG_FILE="${LOG_DIR}/gdrive-sync-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting Google Drive backup sync..."

if [[ -z "$GDRIVE_FOLDER_ID" ]]; then
    log "ERROR: GDRIVE_FOLDER_ID not configured"
    exit 1
fi

# Backup data directory
rclone sync \
    --config="${CONFIG_DIR}/gdrive/rclone.conf" \
    --drive-shared-with-me \
    --exclude=".tmp/**" \
    --log-file="$LOG_FILE" \
    "${DATA_DIR}" \
    "gdrive:${GDRIVE_FOLDER_ID}"

log "Backup sync complete"
SYNCEOF
    
    chmod +x "$sync_script"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$sync_script"
    
    log_success "Google Drive sync configuration created"
}

# ============================================================================
# STEP 22: GENERATE SYSTEMD SERVICES
# ============================================================================

generate_systemd_services() {
    log_step "22" "25" "GENERATING SYSTEMD SERVICE FILES"
    
    # Health Monitor Service
    if [[ "${SERVICE_ENABLED[health_monitor]:-false}" == "true" ]]; then
        cat > /etc/systemd/system/ai-platform-health.service <<EOF
[Unit]
Description=AI Platform Health Check
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${ACTUAL_USER}
WorkingDirectory=${ROOT_PATH}
ExecStart=/usr/bin/bash ${ROOT_PATH}/scripts/health-check.sh
StandardOutput=append:${LOG_DIR}/health-check.log
StandardError=append:${LOG_DIR}/health-check.log

[Install]
WantedBy=multi-user.target
EOF

        cat > /etc/systemd/system/ai-platform-health.timer <<EOF
[Unit]
Description=AI Platform Health Check Timer
Requires=ai-platform-health.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        log_success "Health monitor systemd service created"
    fi
    
    # GDrive Sync Service
    if [[ "${SERVICE_ENABLED[gdrive_sync]:-false}" == "true" ]]; then
        cat > /etc/systemd/system/gdrive-sync.service <<EOF
[Unit]
Description=Google Drive Backup Sync
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${ACTUAL_USER}
WorkingDirectory=${ROOT_PATH}
ExecStart=/usr/bin/bash ${ROOT_PATH}/scripts/gdrive-sync.sh
StandardOutput=append:${LOG_DIR}/gdrive-sync.log
StandardError=append:${LOG_DIR}/gdrive-sync.log

[Install]
WantedBy=multi-user.target
EOF

        cat > /etc/systemd/system/gdrive-sync.timer <<EOF
[Unit]
Description=Google Drive Backup Sync Timer
Requires=gdrive-sync.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        log_success "GDrive sync systemd service created"
    fi
    
    systemctl daemon-reload
}

# ============================================================================
# STEP 23: CREATE HELPER SCRIPTS
# ============================================================================

create_helper_scripts() {
    log_step "23" "25" "CREATING HELPER SCRIPTS"
    
    sudo -u "$ACTUAL_USER" mkdir -p "${ROOT_PATH}/scripts"
    
    # Health Check Script
    cat > "${ROOT_PATH}/scripts/health-check.sh" <<'HEALTHEOF'
#!/usr/bin/env bash
# Health Check Script v100.0.0

source "$(dirname "$0")/../.env"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "=== AI Platform Health Check ==="

# Check Docker daemon
if ! docker info &>/dev/null; then
    log "ERROR: Docker daemon not running"
    exit 1
fi

# Check containers
declare -a required_containers=("ollama" "webui")

if [[ "$ENABLE_LITELLM" == "true" ]]; then
    required_containers+=("litellm")
fi

if [[ "$ENABLE_POSTGRES" == "true" ]]; then
    required_containers+=("postgres")
fi

if [[ "$ENABLE_REDIS" == "true" ]]; then
    required_containers+=("redis")
fi

if [[ "$ENABLE_CADDY" == "true" ]]; then
    required_containers+=("caddy")
fi

if [[ "$ENABLE_NGINX" == "true" ]]; then
    required_containers+=("nginx")
fi

if [[ "$ENABLE_SIGNAL_API" == "true" ]]; then
    required_containers+=("signal-api")
fi

all_healthy=true

for container in "${required_containers[@]}"; do
    if docker ps --filter "name=ai-platform-${container}" --filter "status=running" | grep -q "${container}"; then
        log "✓ ${container} is running"
    else
        log "✗ ${container} is NOT running"
        all_healthy=false
    fi
done

# Check disk space
free_space=$(df -BG "${ROOT_PATH}" | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ $free_space -lt 10 ]]; then
    log "WARNING: Low disk space: ${free_space}GB remaining"
fi

if $all_healthy; then
    log "=== All services healthy ==="
    exit 0
else
    log "=== Some services unhealthy ==="
    exit 1
fi
HEALTHEOF
    
    chmod +x "${ROOT_PATH}/scripts/health-check.sh"
    chown "$ACTUAL_USER:$ACTUAL_USER" "${ROOT_PATH}/scripts/health-check.sh"
    
    log_success "Helper scripts created"
}

# ============================================================================
# STEP 24: CREATE SERVICE DATA DIRECTORIES
# ============================================================================

create_service_directories() {
    log_step "24" "25" "CREATING SERVICE-SPECIFIC DIRECTORIES"
    
    # Create data directories only for enabled services
    sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/ollama"
    sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/open-webui"
    
    if [[ "${SERVICE_ENABLED[litellm]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/litellm"
    fi
    
    if [[ "${SERVICE_ENABLED[postgres]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/postgres"
    fi
    
    if [[ "${SERVICE_ENABLED[redis]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/redis"
    fi
    
    if [[ "${SERVICE_ENABLED[caddy]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/caddy"
    fi
    
    if [[ "${SERVICE_ENABLED[nginx]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/nginx"
    fi
    
    if [[ "${SERVICE_ENABLED[signal_api]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/signal-api"
    fi
    
    if [[ "${SERVICE_ENABLED[langfuse]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/langfuse"
    fi
    
    if [[ "${SERVICE_ENABLED[n8n]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/n8n"
    fi
    
    if [[ "${SERVICE_ENABLED[qdrant]:-false}" == "true" ]]; then
        sudo -u "$ACTUAL_USER" mkdir -p "${DATA_DIR}/qdrant"
    fi
    
    log_success "Service directories created"
}

# ============================================================================
# STEP 25: FINAL SUMMARY
# ============================================================================

show_configuration_summary() {
    log_step "25" "25" "CONFIGURATION SUMMARY"
    
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                                                                  ║${NC}"
    echo -e "${BOLD}${GREEN}║       🎉 AI PLATFORM CONFIGURATION COMPLETE 🎉                   ║${NC}"
    echo -e "${BOLD}${GREEN}║                                                                  ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD}📋 CONFIGURATION SUMMARY:${NC}"
    echo ""
    
    echo -e "${BOLD}Reverse Proxy:${NC} $REVERSE_PROXY"
    if [[ "$REVERSE_PROXY" != "none" ]]; then
        echo "  • HTTP Port: ${SERVICE_PORTS[proxy_http]}"
        echo "  • HTTPS Port: ${SERVICE_PORTS[proxy_https]}"
    fi
    echo ""
    
    echo -e "${BOLD}Core Services:${NC}"
    echo "  • Ollama (port ${SERVICE_PORTS[ollama]})"
    echo "  • Open WebUI (port ${SERVICE_PORTS[webui]})"
    [[ "${SERVICE_ENABLED[litellm]:-false}" == "true" ]] && echo "  • LiteLLM (port ${SERVICE_PORTS[litellm]})"
    [[ "${SERVICE_ENABLED[postgres]:-false}" == "true" ]] && echo "  • PostgreSQL (port ${SERVICE_PORTS[postgres]})"
    [[ "${SERVICE_ENABLED[redis]:-false}" == "true" ]] && echo "  • Redis (port ${SERVICE_PORTS[redis]})"
    echo ""
    
    echo -e "${BOLD}Automation Services:${NC}"
    echo "  • Tailscale (HTTPS port ${SERVICE_PORTS[tailscale_https]})"
    [[ "${SERVICE_ENABLED[signal_api]:-false}" == "true" ]] && echo "  • Signal-API (port ${SERVICE_PORTS[signal_api]})"
    [[ "${SERVICE_ENABLED[gdrive_sync]:-false}" == "true" ]] && echo "  • Google Drive Sync (enabled)"
    [[ "${SERVICE_ENABLED[health_monitor]:-false}" == "true" ]] && echo "  • Health Monitor (enabled)"
    echo ""
    
    if [[ "${SERVICE_ENABLED[langfuse]:-false}" == "true" ]] || \
       [[ "${SERVICE_ENABLED[n8n]:-false}" == "true" ]] || \
       [[ "${SERVICE_ENABLED[qdrant]:-false}" == "true" ]]; then
        echo -e "${BOLD}Optional Services:${NC}"
        [[ "${SERVICE_ENABLED[langfuse]:-false}" == "true" ]] && echo "  • Langfuse (port ${SERVICE_PORTS[langfuse]})"
        [[ "${SERVICE_ENABLED[n8n]:-false}" == "true" ]] && echo "  • N8N (port ${SERVICE_PORTS[n8n]})"
        [[ "${SERVICE_ENABLED[qdrant]:-false}" == "true" ]] && echo "  • Qdrant (port ${SERVICE_PORTS[qdrant]})"
        echo ""
    fi
    
    echo -e "${BOLD}Ollama Models Selected:${NC}"
    for model in $OLLAMA_MODELS; do
        echo "  • $model"
    done
    echo ""
    
    echo -e "${CYAN}${BOLD}📁 KEY FILES GENERATED:${NC}"
    echo "  • Environment:        ${ROOT_PATH}/.env"
    [[ "${SERVICE_ENABLED[litellm]:-false}" == "true" ]] && echo "  • LiteLLM Config:     ${CONFIG_DIR}/litellm/config.yaml"
    [[ "$REVERSE_PROXY" == "caddy" ]] && echo "  • Caddy Config:       ${CONFIG_DIR}/caddy/Caddyfile"
    [[ "$REVERSE_PROXY" == "nginx" ]] && echo "  • Nginx Config:       ${CONFIG_DIR}/nginx/nginx.conf"
    echo "  • Tailscale Setup:    ${CONFIG_DIR}/tailscale/config.sh"
    [[ "${SERVICE_ENABLED[gdrive_sync]:-false}" == "true" ]] && echo "  • GDrive Sync Script: ${ROOT_PATH}/scripts/gdrive-sync.sh"
    echo "  • Health Check:       ${ROOT_PATH}/scripts/health-check.sh"
    echo "  • Logs:               ${LOG_DIR}/"
    echo ""
    
    echo -e "${CYAN}${BOLD}🚀 NEXT STEP:${NC}"
    echo "  Run deployment script:"
    echo "  ${BOLD}sudo bash scripts/2-deploy-services.sh${NC}"
    echo ""
    
    echo -e "${YELLOW}${BOLD}⚠️  BEFORE DEPLOYMENT:${NC}"
    echo "  1. Review generated .env file"
    echo "  2. Add any missing API keys to .env"
    echo "  3. Configure Tailscale auth key in .env (if needed)"
    echo "  4. Review service configurations in ${CONFIG_DIR}/"
    echo ""
    
    echo -e "${CYAN}Setup log: ${LOG_FILE}${NC}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Initialize
    declare -A API_KEYS
    declare -A SECRETS
    
    setup_logging
    print_header
    
    # Execute all steps
    check_prerequisites                  # Step 1
    system_health_check                  # Step 2
    install_system_packages              # Step 3
    install_docker                       # Step 4
    configure_docker_user                # Step 5
    install_nvidia_toolkit               # Step 6
    install_tailscale                    # Step 7
    configure_apparmor                   # Step 8
    create_directory_structure           # Step 9
    select_reverse_proxy                 # Step 10
    select_core_services                 # Step 11
    select_automation_services           # Step 12
    select_optional_services             # Step 13
    select_ollama_models                 # Step 14
    collect_api_keys                     # Step 15
    generate_secrets                     # Step 16
    generate_env_file                    # Step 17
    generate_litellm_config              # Step 18
    generate_proxy_config                # Step 19
    generate_tailscale_config            # Step 20
    generate_gdrive_config               # Step 21
    generate_systemd_services            # Step 22
    create_helper_scripts                # Step 23
    create_service_directories           # Step 24
    show_configuration_summary           # Step 25
    
    log_success "Configuration completed successfully!"
    log_warning "User must logout/login for docker group changes"
    log_warning "Run Script 2 to deploy services"
    
    exit 0
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Check log: $LOG_FILE"' ERR

# Run main
main "$@"
