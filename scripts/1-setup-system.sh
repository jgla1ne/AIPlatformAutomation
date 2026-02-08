#!/usr/bin/env bash

################################################################################
# SCRIPT 1 v98.6.0 - AI PLATFORM SYSTEM INITIALIZATION
# FIXES:
# - Removed readonly from port constants (allows .env override)
# - Fixed script completion (was exiting at step 17)
# - Fixed LiteLLM config generation (now actually writes file)
# - Added custom port selection
# - Added numbered model selection
# - Fixed log location (~/ai-platform-logs/)
# - Fixed platform.env malformed comment
################################################################################

set -uo pipefail

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="98.6.0"
readonly SCRIPT_NAME="1-setup-system.sh"
readonly LOG_DIR="$HOME/ai-platform-logs"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d_%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"
readonly DATA_PATH="/mnt/data/ai-platform"
readonly SECRETS_PATH="${ROOT_PATH}/.secrets"
readonly CONFIG_PATH="${ROOT_PATH}/config"
readonly LOGS_PATH="${ROOT_PATH}/logs"

# Progress tracking
TOTAL_STEPS=25
CURRENT_STEP=0

# Configuration variables
DOMAIN_NAME=""
SSL_EMAIL=""
VECTOR_DB=""
REVERSE_PROXY=""
CLOUD_PROVIDER=""
ENABLE_GDRIVE_SYNC="false"
ENABLE_SIGNAL="false"
ENABLE_MONITORING="false"
ENABLE_N8N="false"
TAILSCALE_AUTH_KEY=""
TAILSCALE_API_KEY=""
GPU_ENABLED="false"
GDRIVE_AUTH_METHOD=""
GDRIVE_SERVICE_ACCOUNT_JSON=""
GDRIVE_CLIENT_ID=""
GDRIVE_CLIENT_SECRET=""
GDRIVE_SYNC_PATH="/mnt/data/gdrive"
CUSTOM_PORTS="false"

# Port allocations (NOT readonly - allows customization)
OLLAMA_PORT=11434
LITELLM_PORT=4000
OPENWEBUI_PORT=8080
OPENCLAW_PORT=8001
POSTGRES_PORT=5432
REDIS_PORT=6379
LANGFUSE_PORT=3000
N8N_PORT=5678
GRAFANA_PORT=3001
PROMETHEUS_PORT=9090
SIGNAL_CLI_PORT=8080
TAILSCALE_PORT=8443
QDRANT_PORT=6333
MILVUS_PORT=19530
WEAVIATE_PORT=8082
PGVECTOR_PORT=5433

# LLM Provider variables
ANTHROPIC_API_KEY=""
OPENAI_API_KEY=""
GOOGLE_API_KEY=""
MISTRAL_API_KEY=""
GROQ_API_KEY=""
XAI_API_KEY=""
PERPLEXITY_API_KEY=""
DEEPSEEK_API_KEY=""

# Ollama models array
declare -a OLLAMA_MODELS=()

# ============================================================================
# LOGGING & UI FUNCTIONS
# ============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$LOGS_PATH"
    
    # Delete old logs (keep only last 5)
    cd "$LOG_DIR"
    ls -t setup-*.log 2>/dev/null | tail -n +6 | xargs -r rm --
    cd - > /dev/null
    
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
}

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗ ERROR:${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $*"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo ""
    echo -e "${BOLD}${CYAN}⚙️  [$CURRENT_STEP/$TOTAL_STEPS] $* (${percentage}%)${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_header() {
    clear
    echo -e "${BOLD}${MAGENTA}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║        🤖 AI PLATFORM AUTOMATION - SYSTEM SETUP v${SCRIPT_VERSION}      ║"
    echo "║                                                                ║"
    echo "║  Comprehensive AI Infrastructure Deployment                    ║"
    echo "║  • Ollama • LiteLLM • Open WebUI • PostgreSQL • Redis         ║"
    echo "║  • Langfuse • Tailscale • Vector DBs • Monitoring             ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        log_error "This script requires Ubuntu or Debian"
        exit 1
    fi
    
    local version_ok=false
    if [[ "$ID" == "ubuntu" ]]; then
        if [[ "${VERSION_ID}" =~ ^(20.04|22.04|24.04)$ ]]; then
            version_ok=true
        fi
    elif [[ "$ID" == "debian" ]]; then
        if [[ "${VERSION_ID}" =~ ^(11|12)$ ]]; then
            version_ok=true
        fi
    fi
    
    if [[ "$version_ok" == "false" ]]; then
        log_warning "OS version ${VERSION_ID} not officially supported"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "OS validated: $PRETTY_NAME"
}

check_disk_space() {
    local required_gb=50
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_gb -lt $required_gb ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        exit 1
    fi
    
    log_success "Disk space: ${available_gb}GB available"
}

check_memory() {
    local required_mb=4096
    local available_mb=$(free -m | awk 'NR==2 {print $2}')
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_warning "Low memory: ${available_mb}MB (${required_mb}MB recommended)"
    else
        log_success "Memory: ${available_mb}MB available"
    fi
}

check_internet() {
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        log_error "No internet connectivity"
        exit 1
    fi
    log_success "Internet connectivity verified"
}

check_port_availability() {
    local default_ports=(
        11434 4000 8080 8001 5432 6379 3000 8443
    )
    
    local conflicts=0
    
    for port in "${default_ports[@]}"; do
        if ss -tuln | grep -q ":${port} "; then
            log_warning "Port $port already in use"
            conflicts=$((conflicts + 1))
        fi
    done
    
    if [[ $conflicts -gt 0 ]]; then
        log_warning "$conflicts port conflict(s) detected"
        read -p "Customize ports to avoid conflicts? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            CUSTOM_PORTS="true"
        fi
    else
        log_success "All default ports available"
    fi
}

# ============================================================================
# PORT CUSTOMIZATION
# ============================================================================

customize_ports() {
    if [[ "$CUSTOM_PORTS" != "true" ]]; then
        return 0
    fi
    
    print_step "Custom Port Configuration"
    
    log_info "Configure custom ports (press Enter to keep default)"
    echo ""
    
    read -p "$(echo -e ${CYAN}❯${NC}) Ollama port [$OLLAMA_PORT]: " port
    [[ -n "$port" ]] && OLLAMA_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) LiteLLM port [$LITELLM_PORT]: " port
    [[ -n "$port" ]] && LITELLM_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Open WebUI port [$OPENWEBUI_PORT]: " port
    [[ -n "$port" ]] && OPENWEBUI_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) OpenClaw port [$OPENCLAW_PORT]: " port
    [[ -n "$port" ]] && OPENCLAW_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) PostgreSQL port [$POSTGRES_PORT]: " port
    [[ -n "$port" ]] && POSTGRES_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Redis port [$REDIS_PORT]: " port
    [[ -n "$port" ]] && REDIS_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Langfuse port [$LANGFUSE_PORT]: " port
    [[ -n "$port" ]] && LANGFUSE_PORT="$port"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Tailscale port [$TAILSCALE_PORT]: " port
    [[ -n "$port" ]] && TAILSCALE_PORT="$port"
    
    log_success "Custom ports configured"
}

# ============================================================================
# GPU DETECTION
# ============================================================================

detect_gpu_capability() {
    print_step "GPU Detection"
    
    GPU_ENABLED="false"
    
    if command -v nvidia-smi &> /dev/null; then
        log_info "NVIDIA GPU detected:"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | while read line; do
            log_info "  $line"
        done
        GPU_ENABLED="true"
        log_success "GPU acceleration will be enabled"
    else
        log_info "No NVIDIA GPU detected - CPU-only mode"
    fi
}

# ============================================================================
# DOMAIN & SSL CONFIGURATION
# ============================================================================

validate_domain() {
    print_step "Domain & SSL Configuration"
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Enter your domain name (e.g., ai.example.com): " domain
        domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | xargs)
        
        # Accept subdomains (ai.datasquiz.net, api.example.com, etc.)
        if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$ ]]; then
            log_error "Invalid domain name format"
            log_info "Examples: example.com, ai.example.com, api.sub.example.com"
            continue
        fi
        
        DOMAIN_NAME="$domain"
        log_success "Domain: $DOMAIN_NAME"
        break
    done
    
    # DNS resolution check (non-blocking)
    log_info "Checking DNS resolution..."
    if host "$DOMAIN_NAME" &> /dev/null; then
        local resolved_ip=$(host "$DOMAIN_NAME" | grep "has address" | head -1 | awk '{print $4}')
        log_success "Domain resolves to: $resolved_ip"
    else
        log_warning "DNS does not resolve yet (configure after setup)"
    fi
    
    # SSL Email
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Enter email for SSL certificates: " email
        email=$(echo "$email" | xargs)
        
        if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid email format"
            continue
        fi
        
        SSL_EMAIL="$email"
        log_success "SSL Email: $SSL_EMAIL"
        break
    done
}

# ============================================================================
# DOCKER INSTALLATION
# ============================================================================

install_docker() {
    print_step "Docker Installation"
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_success "Docker already installed: v$docker_version"
        
        if docker compose version &> /dev/null; then
            local compose_version=$(docker compose version | awk '{print $4}')
            log_success "Docker Compose already installed: v$compose_version"
            return 0
        fi
    fi
    
    log_info "Installing Docker..."
    
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl enable docker
    systemctl start docker
    
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
        log_info "Added $SUDO_USER to docker group (re-login required)"
    fi
    
    log_success "Docker installed successfully"
}

# ============================================================================
# TAILSCALE INSTALLATION
# ============================================================================

install_tailscale_properly() {
    print_step "Tailscale VPN Setup"
    
    log_info "Installing Tailscale..."
    
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    
    apt-get update
    apt-get install -y tailscale
    
    systemctl enable tailscaled
    systemctl start tailscaled
    
    log_success "Tailscale installed"
    
    echo ""
    log_info "Tailscale requires authentication keys from https://login.tailscale.com/admin/settings/keys"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Enter Tailscale Auth Key (tskey-auth-...): " auth_key
        auth_key=$(echo "$auth_key" | xargs)
        
        if [[ ! "$auth_key" =~ ^tskey-auth- ]]; then
            log_error "Invalid auth key format (must start with 'tskey-auth-')"
            continue
        fi
        
        TAILSCALE_AUTH_KEY="$auth_key"
        log_success "Auth key accepted"
        break
    done
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Enter Tailscale API Key (tskey-api-...): " api_key
        api_key=$(echo "$api_key" | xargs)
        
        if [[ ! "$api_key" =~ ^tskey-api- ]]; then
            log_error "Invalid API key format (must start with 'tskey-api-')"
            continue
        fi
        
        TAILSCALE_API_KEY="$api_key"
        log_success "API key accepted"
        break
    done
    
    log_info "Authenticating with Tailscale..."
    if tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes --accept-dns=false; then
        log_success "Tailscale authenticated successfully"
        
        local tailscale_ip=$(tailscale ip -4)
        log_info "Tailscale IP: $tailscale_ip"
    else
        log_error "Tailscale authentication failed"
        exit 1
    fi
    
    mkdir -p "$SECRETS_PATH"
    cat > "$SECRETS_PATH/tailscale.env" <<EOF
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
TAILSCALE_API_KEY=${TAILSCALE_API_KEY}
TAILSCALE_PORT=${TAILSCALE_PORT}
TAILSCALE_HOSTNAME=$(hostname)
TAILSCALE_IP=${tailscale_ip}
EOF
    chmod 600 "$SECRETS_PATH/tailscale.env"
    
    log_success "Tailscale configuration saved"
}

# ============================================================================
# VECTOR DATABASE SELECTION
# ============================================================================

select_vector_database() {
    print_step "Vector Database Selection"
    
    echo "Available vector databases:"
    echo "  1) Qdrant (Recommended - Rust-based, fastest)"
    echo "  2) Milvus (Feature-rich, enterprise-grade)"
    echo "  3) Weaviate (GraphQL API, semantic search)"
    echo "  4) pgvector (PostgreSQL extension)"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Select vector database [1-4]: " choice
        
        case $choice in
            1) VECTOR_DB="qdrant"; log_success "Selected: Qdrant"; break ;;
            2) VECTOR_DB="milvus"; log_success "Selected: Milvus"; break ;;
            3) VECTOR_DB="weaviate"; log_success "Selected: Weaviate"; break ;;
            4) VECTOR_DB="pgvector"; log_success "Selected: pgvector"; break ;;
            *) log_error "Invalid choice" ;;
        esac
    done
}

# ============================================================================
# REVERSE PROXY SELECTION
# ============================================================================

select_reverse_proxy() {
    print_step "Reverse Proxy Selection"
    
    echo "Available reverse proxies:"
    echo "  1) Traefik (Recommended - automatic SSL, service discovery)"
    echo "  2) Nginx (Traditional, manual configuration)"
    echo "  3) Caddy (Automatic HTTPS, simple config)"
    echo "  4) None (Direct port access only)"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Select reverse proxy [1-4]: " choice
        
        case $choice in
            1) REVERSE_PROXY="traefik"; log_success "Selected: Traefik"; break ;;
            2) REVERSE_PROXY="nginx"; log_success "Selected: Nginx"; break ;;
            3) REVERSE_PROXY="caddy"; log_success "Selected: Caddy"; break ;;
            4) REVERSE_PROXY="none"; log_success "No reverse proxy"; break ;;
            *) log_error "Invalid choice" ;;
        esac
    done
}

# ============================================================================
# CLOUD PROVIDER SELECTION
# ============================================================================

select_cloud_provider() {
    print_step "Cloud Provider Selection"
    
    echo "Detected cloud providers (for optimizations):"
    echo "  1) AWS"
    echo "  2) Google Cloud"
    echo "  3) Azure"
    echo "  4) DigitalOcean"
    echo "  5) Hetzner"
    echo "  6) OVH"
    echo "  7) Bare Metal / Other"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Select provider [1-7]: " choice
        
        case $choice in
            1) CLOUD_PROVIDER="aws"; break ;;
            2) CLOUD_PROVIDER="gcp"; break ;;
            3) CLOUD_PROVIDER="azure"; break ;;
            4) CLOUD_PROVIDER="digitalocean"; break ;;
            5) CLOUD_PROVIDER="hetzner"; break ;;
            6) CLOUD_PROVIDER="ovh"; break ;;
            7) CLOUD_PROVIDER="bare-metal"; break ;;
            *) log_error "Invalid choice" ;;
        esac
    done
    
    log_success "Cloud provider: $CLOUD_PROVIDER"
}

# ============================================================================
# ADDITIONAL SERVICES
# ============================================================================

configure_additional_services() {
    print_step "Additional Services"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enable n8n workflow automation? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && ENABLE_N8N="true" && log_success "n8n will be installed"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enable monitoring (Grafana + Prometheus)? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && ENABLE_MONITORING="true" && log_success "Monitoring will be installed"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enable Signal-CLI notifications? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && ENABLE_SIGNAL="true" && log_success "Signal-CLI will be installed"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enable Google Drive sync? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && ENABLE_GDRIVE_SYNC="true" && log_success "Google Drive sync will be configured"
}

# ============================================================================
# SIGNAL-CLI CONFIGURATION
# ============================================================================

configure_signal_cli() {
    print_step "Signal-CLI Configuration"
    
    log_info "Signal-CLI will be configured in Docker Compose"
    log_info "Post-setup: Register device with 'docker exec -it signal-cli signal-cli -u +PHONE link'"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enter phone number for Signal (e.g., +33612345678): " signal_phone
    SIGNAL_PHONE="$signal_phone"
    
    log_success "Signal-CLI configured for: $SIGNAL_PHONE"
}

# ============================================================================
# GOOGLE DRIVE SYNC
# ============================================================================

configure_google_drive_sync() {
    print_step "Google Drive Sync Configuration"
    
    echo ""
    log_info "Google Drive authentication methods:"
    echo "  1) Service Account (JSON file) - Recommended for automation"
    echo "  2) OAuth2 (Browser login) - For personal accounts"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}❯${NC}) Select auth method [1-2]: " choice
        
        case $choice in
            1)
                GDRIVE_AUTH_METHOD="service-account"
                log_success "Using Service Account authentication"
                
                while true; do
                    read -p "$(echo -e ${CYAN}❯${NC}) Enter path to service account JSON file: " json_path
                    json_path=$(eval echo "$json_path")
                    
                    if [[ ! -f "$json_path" ]]; then
                        log_error "File not found: $json_path"
                        continue
                    fi
                    
                    if ! jq empty "$json_path" 2>/dev/null; then
                        log_error "Invalid JSON file"
                        continue
                    fi
                    
                    mkdir -p "$SECRETS_PATH"
                    cp "$json_path" "$SECRETS_PATH/gdrive-service-account.json"
                    chmod 600 "$SECRETS_PATH/gdrive-service-account.json"
                    
                    GDRIVE_SERVICE_ACCOUNT_JSON="$SECRETS_PATH/gdrive-service-account.json"
                    log_success "Service account JSON saved"
                    break
                done
                break
                ;;
            2)
                GDRIVE_AUTH_METHOD="oauth2"
                log_success "Using OAuth2 authentication"
                
                log_info "Create OAuth credentials at: https://console.cloud.google.com/apis/credentials"
                echo ""
                
                read -p "$(echo -e ${CYAN}❯${NC}) Enter OAuth2 Client ID: " client_id
                GDRIVE_CLIENT_ID="$client_id"
                
                read -p "$(echo -e ${CYAN}❯${NC}) Enter OAuth2 Client Secret: " client_secret
                GDRIVE_CLIENT_SECRET="$client_secret"
                
                log_success "OAuth2 credentials saved"
                log_info "You'll need to complete browser authentication after deployment"
                break
                ;;
            *)
                log_error "Invalid choice"
                ;;
        esac
    done
    
    read -p "$(echo -e ${CYAN}❯${NC}) Enter local sync path [${GDRIVE_SYNC_PATH}]: " sync_path
    [[ -n "$sync_path" ]] && GDRIVE_SYNC_PATH="$sync_path"
    
    log_success "Google Drive sync path: $GDRIVE_SYNC_PATH"
}

# ============================================================================
# LLM PROVIDER CONFIGURATION
# ============================================================================

configure_llm_providers() {
    print_step "External LLM Providers"
    
    log_info "Configure API keys for external LLM providers (leave empty to skip)"
    echo ""
    
    read -p "$(echo -e ${CYAN}❯${NC}) Anthropic API Key (sk-ant-...): " key
    [[ -n "$key" ]] && ANTHROPIC_API_KEY="$key" && log_success "Anthropic configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) OpenAI API Key (sk-...): " key
    [[ -n "$key" ]] && OPENAI_API_KEY="$key" && log_success "OpenAI configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Google AI API Key: " key
    [[ -n "$key" ]] && GOOGLE_API_KEY="$key" && log_success "Google AI configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Mistral API Key: " key
    [[ -n "$key" ]] && MISTRAL_API_KEY="$key" && log_success "Mistral configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Groq API Key (gsk_...): " key
    [[ -n "$key" ]] && GROQ_API_KEY="$key" && log_success "Groq configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) xAI API Key: " key
    [[ -n "$key" ]] && XAI_API_KEY="$key" && log_success "xAI configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) Perplexity API Key: " key
    [[ -n "$key" ]] && PERPLEXITY_API_KEY="$key" && log_success "Perplexity configured"
    
    read -p "$(echo -e ${CYAN}❯${NC}) DeepSeek API Key: " key
    [[ -n "$key" ]] && DEEPSEEK_API_KEY="$key" && log_success "DeepSeek configured"
}

# ============================================================================
# OLLAMA MODEL SELECTION (NUMBERED)
# ============================================================================

select_ollama_models() {
    print_step "Ollama Model Selection"
    
    log_info "Select models to pre-pull (downloads during first deploy)"
    echo ""
    
    # Model menu
    local -a model_menu=(
        "deepseek-coder:6.7b|Code generation (4.4GB)"
        "codellama:13b|Meta code model (7.4GB)"
        "starcoder2:15b|Advanced coding (9GB)"
        "llama3.2:3b|Fast chat (2GB)"
        "llama3.1:8b|Balanced chat (4.7GB)"
        "mixtral:8x7b|High quality (26GB)"
        "qwen2.5:7b|Multilingual (4.7GB)"
        "mxbai-embed-large|Text embeddings (669MB)"
        "nomic-embed-text|Lightweight embeddings (274MB)"
        "llava:7b|Image understanding (4.7GB)"
    )
    
    echo -e "${BOLD}Available models:${NC}"
    for i in "${!model_menu[@]}"; do
        IFS='|' read -r model_name description <<< "${model_menu[$i]}"
        printf "  %2d) %-25s - %s\n" "$((i+1))" "$model_name" "$description"
    done
    echo ""
    
    log_info "Enter model numbers (comma-separated, e.g., 1,4,8) or press Enter to skip:"
    read -p "$(echo -e ${CYAN}❯${NC}) Models: " selection
    
    if [[ -n "$selection" ]]; then
        IFS=',' read -ra selected <<< "$selection"
        for num in "${selected[@]}"; do
            num=$(echo "$num" | xargs)
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#model_menu[@]} ]]; then
                IFS='|' read -r model_name _ <<< "${model_menu[$((num-1))]}"
                OLLAMA_MODELS+=("$model_name")
                log_success "Added: $model_name"
            else
                log_warning "Invalid selection: $num"
            fi
        done
    fi
    
    if [[ ${#OLLAMA_MODELS[@]} -eq 0 ]]; then
        log_warning "No models selected - you can pull them later with 'ollama pull <model>'"
    else
        log_success "Selected ${#OLLAMA_MODELS[@]} model(s)"
    fi
}

# ============================================================================
# LITELLM CONFIGURATION GENERATION (FIXED)
# ============================================================================

generate_litellm_config() {
    print_step "Generating LiteLLM Configuration"
    
    mkdir -p "$CONFIG_PATH"
    
    # Generate config file
    cat > "$CONFIG_PATH/litellm-config.yaml" <<EOF
model_list:
  # Ollama local models
EOF
    
    # Add selected Ollama models
    for model in "${OLLAMA_MODELS[@]}"; do
        local model_name="${model%%:*}"
        cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  - model_name: ${model_name}
    litellm_params:
      model: ollama/${model}
      api_base: http://ollama:${OLLAMA_PORT}
  
EOF
    done
    
    # Add external providers
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: \${ANTHROPIC_API_KEY}
  
EOF
    fi
    
    if [[ -n "$OPENAI_API_KEY" ]]; then
        cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: \${OPENAI_API_KEY}
  
EOF
    fi
    
    if [[ -n "$GROQ_API_KEY" ]]; then
        cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  - model_name: llama-3.1-70b-groq
    litellm_params:
      model: groq/llama-3.1-70b-versatile
      api_key: \${GROQ_API_KEY}
  
EOF
    fi
    
    # Add settings
    cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
litellm_settings:
  drop_params: true
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
  
general_settings:
  master_key: \${LITELLM_MASTER_KEY}
  database_url: postgresql://litellm:\${POSTGRES_PASSWORD}@postgres:${POSTGRES_PORT}/litellm
  
router_settings:
  routing_strategy: simple-shuffle
  model_group_alias:
    gpt-4: [ollama/llama3.1:8b]
    gpt-3.5-turbo: [ollama/llama3.2:3b]
EOF
    
    chmod 644 "$CONFIG_PATH/litellm-config.yaml"
    
    log_success "LiteLLM configuration generated: $CONFIG_PATH/litellm-config.yaml"
}

# ============================================================================
# SECRETS GENERATION
# ============================================================================

generate_secrets() {
    print_step "Generating Secrets"
    
    mkdir -p "$SECRETS_PATH"
    chmod 700 "$SECRETS_PATH"
    
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    LITELLM_MASTER_KEY=$(openssl rand -hex 32)
    LANGFUSE_SALT=$(openssl rand -hex 16)
    NEXTAUTH_SECRET=$(openssl rand -hex 32)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    log_success "All secrets generated"
}

# ============================================================================
# ENVIRONMENT FILE CREATION (FIXED)
# ============================================================================

create_environment_files() {
    print_step "Creating Environment Files"
    
    # Main .env file
    cat > "${ROOT_PATH}/.env" <<EOF
# AI Platform Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE

# Domain & SSL
DOMAIN_NAME=${DOMAIN_NAME}
SSL_EMAIL=${SSL_EMAIL}

# Infrastructure
VECTOR_DB=${VECTOR_DB}
REVERSE_PROXY=${REVERSE_PROXY}
CLOUD_PROVIDER=${CLOUD_PROVIDER}
GPU_ENABLED=${GPU_ENABLED}

# Service Ports
OLLAMA_PORT=${OLLAMA_PORT}
LITELLM_PORT=${LITELLM_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
POSTGRES_PORT=${POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT}
LANGFUSE_PORT=${LANGFUSE_PORT}
N8N_PORT=${N8N_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}

# Database Credentials
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# LiteLLM
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}

# Langfuse
LANGFUSE_SALT=${LANGFUSE_SALT}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Data Paths
DATA_PATH=${DATA_PATH}
SECRETS_PATH=${SECRETS_PATH}
CONFIG_PATH=${CONFIG_PATH}
EOF
    
    # Platform config (FIXED: No malformed comments)
    cat > "${ROOT_PATH}/platform.env" <<EOF
# Platform Features Configuration
# Generated: $(date)

# Optional Services
ENABLE_N8N=${ENABLE_N8N}
ENABLE_MONITORING=${ENABLE_MONITORING}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
ENABLE_GDRIVE_SYNC=${ENABLE_GDRIVE_SYNC}

# Google Drive Configuration
GDRIVE_AUTH_METHOD=${GDRIVE_AUTH_METHOD}
GDRIVE_SYNC_PATH=${GDRIVE_SYNC_PATH}
GDRIVE_SERVICE_ACCOUNT_JSON=${GDRIVE_SERVICE_ACCOUNT_JSON}
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET}

# Signal-CLI Configuration
SIGNAL_PHONE=${SIGNAL_PHONE:-}
EOF
    
    # LLM providers
    cat > "${SECRETS_PATH}/llm-providers.env" <<EOF
# External LLM Provider API Keys
# Generated: $(date)

ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
GOOGLE_API_KEY=${GOOGLE_API_KEY}
MISTRAL_API_KEY=${MISTRAL_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
XAI_API_KEY=${XAI_API_KEY}
PERPLEXITY_API_KEY=${PERPLEXITY_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
EOF
    
    chmod 600 "${ROOT_PATH}/.env"
    chmod 600 "${ROOT_PATH}/platform.env"
    chmod 600 "${SECRETS_PATH}/llm-providers.env"
    
    log_success "Environment files created"
}

# ============================================================================
# DEPLOYMENT SUMMARY (FIXED)
# ============================================================================

show_deployment_summary() {
    print_step "Deployment Configuration Summary"
    
    # Source configs (non-conflicting way)
    [[ -f "${ROOT_PATH}/.env" ]] && set -a && source "${ROOT_PATH}/.env" && set +a
    [[ -f "${ROOT_PATH}/platform.env" ]] && set -a && source "${ROOT_PATH}/platform.env" && set +a
    [[ -f "${SECRETS_PATH}/tailscale.env" ]] && set -a && source "${SECRETS_PATH}/tailscale.env" && set +a
    
    echo -e "${BOLD}  CONFIGURATION SUMMARY${NC}"
    echo ""
    
    echo -e "${CYAN}CORE INFRASTRUCTURE:${NC}"
    echo "  • Domain: ${DOMAIN_NAME}"
    echo "  • SSL Email: ${SSL_EMAIL}"
    echo "  • Vector DB: ${VECTOR_DB}"
    echo "  • Reverse Proxy: ${REVERSE_PROXY}"
    echo "  • Cloud Provider: ${CLOUD_PROVIDER}"
    echo "  • GPU Enabled: ${GPU_ENABLED}"
    echo ""
    
    echo -e "${CYAN}SERVICES:${NC}"
    echo "  • Ollama: http://localhost:${OLLAMA_PORT}"
    echo "  • LiteLLM: http://localhost:${LITELLM_PORT}"
    echo "  • Open WebUI: http://localhost:${OPENWEBUI_PORT}"
    echo "  • OpenClaw: http://localhost:${OPENCLAW_PORT}"
    echo "  • Langfuse: http://localhost:${LANGFUSE_PORT}"
    echo "  • PostgreSQL: localhost:${POSTGRES_PORT}"
    echo "  • Redis: localhost:${REDIS_PORT}"
    
    [[ "$ENABLE_N8N" == "true" ]] && echo "  • n8n: http://localhost:${N8N_PORT}"
    [[ "$ENABLE_MONITORING" == "true" ]] && echo "  • Grafana: http://localhost:${GRAFANA_PORT}"
    [[ "$ENABLE_MONITORING" == "true" ]] && echo "  • Prometheus: http://localhost:${PROMETHEUS_PORT}"
    echo ""
    
    echo -e "${CYAN}TAILSCALE:${NC}"
    echo "  • Hostname: ${TAILSCALE_HOSTNAME:-$(hostname)}"
    echo "  • IP: ${TAILSCALE_IP:-pending}"
    echo "  • Port: ${TAILSCALE_PORT}"
    echo ""
    
    if [[ "$ENABLE_GDRIVE_SYNC" == "true" ]]; then
        echo -e "${CYAN}GOOGLE DRIVE:${NC}"
        echo "  • Auth Method: ${GDRIVE_AUTH_METHOD}"
        echo "  • Sync Path: ${GDRIVE_SYNC_PATH}"
        echo ""
    fi
    
    echo -e "${CYAN}OLLAMA MODELS (${#OLLAMA_MODELS[@]}):${NC}"
    if [[ ${#OLLAMA_MODELS[@]} -gt 0 ]]; then
        for model in "${OLLAMA_MODELS[@]}"; do
            echo "  • $model"
        done
    else
        echo "  • None selected"
    fi
    echo ""
    
    echo -e "${CYAN}EXTERNAL PROVIDERS:${NC}"
    [[ -n "$ANTHROPIC_API_KEY" ]] && echo "  • Anthropic ✓"
    [[ -n "$OPENAI_API_KEY" ]] && echo "  • OpenAI ✓"
    [[ -n "$GOOGLE_API_KEY" ]] && echo "  • Google AI ✓"
    [[ -n "$MISTRAL_API_KEY" ]] && echo "  • Mistral ✓"
    [[ -n "$GROQ_API_KEY" ]] && echo "  • Groq ✓"
    [[ -n "$XAI_API_KEY" ]] && echo "  • xAI ✓"
    [[ -n "$PERPLEXITY_API_KEY" ]] && echo "  • Perplexity ✓"
    [[ -n "$DEEPSEEK_API_KEY" ]] && echo "  • DeepSeek ✓"
    echo ""
}

# ============================================================================
# FINAL STEPS
# ============================================================================

finalize_setup() {
    print_step "Finalizing Setup"
    
    # Create data directories
    mkdir -p "$DATA_PATH"/{ollama,postgres,redis,langfuse,n8n,grafana,prometheus}
    chown -R 1000:1000 "$DATA_PATH"
    
    # Create compose directory
    mkdir -p "${ROOT_PATH}/compose"
    
    # Copy litellm config to accessible location
    if [[ -f "$CONFIG_PATH/litellm-config.yaml" ]]; then
        cp "$CONFIG_PATH/litellm-config.yaml" "$DATA_PATH/litellm-config.yaml"
        log_success "LiteLLM config deployed"
    fi
    
    log_success "Setup finalized"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Setup logging
    setup_logging
    
    # Print header
    print_header
    
    # Preflight checks
    print_step "Preflight Checks"
    check_root
    check_os
    check_disk_space
    check_memory
    check_internet
    check_port_availability
    
    # Custom ports if needed
    customize_ports
    
    # GPU detection
    detect_gpu_capability
    
    # Domain & SSL
    validate_domain
    
    # Docker installation
    install_docker
    
    # Tailscale
    install_tailscale_properly
    
    # Vector database
    select_vector_database
    
    # Reverse proxy
    select_reverse_proxy
    
    # Cloud provider
    select_cloud_provider
    
    # Additional services
    configure_additional_services
    
    # Optional configs
    [[ "$ENABLE_SIGNAL" = "true" ]] && configure_signal_cli
    [[ "$ENABLE_GDRIVE_SYNC" = "true" ]] && configure_google_drive_sync
    
    # External LLM providers
    configure_llm_providers
    
    # Ollama models (numbered selection)
    select_ollama_models
    
    # Generate LiteLLM config (FIXED)
    generate_litellm_config
    
    # Generate secrets
    generate_secrets
    
    # Create environment files (FIXED)
    create_environment_files
    
    # Show summary (FIXED)
    show_deployment_summary
    
    # Finalize
    finalize_setup
    
    # Success message
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  ✅ SYSTEM INITIALIZATION COMPLETE  ${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${YELLOW}NEXT STEPS:${NC}"
    echo "  1. Review configuration: cat ${ROOT_PATH}/.env"
    echo "  2. Run deployment: sudo bash scripts/2-deploy-core.sh"
    echo "  3. Access services via Tailscale or domain"
    echo ""
    echo "Log saved to: $LOG_FILE"
    echo ""
    
    exit 0
}

# Execute
main "$@"
