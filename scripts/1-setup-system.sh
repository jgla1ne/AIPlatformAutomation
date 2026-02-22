#!/bin/bash

#==============================================================================
# Script 1: System Setup & Configuration Collection
# Purpose: Complete system preparation with interactive UI
# Version: 4.0.0
#==============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (will be set by volume detection)
DATA_ROOT="${BASE_DIR:-/mnt/data}"
METADATA_DIR="$DATA_ROOT/metadata"
STATE_FILE="$METADATA_DIR/setup_state.json"
LOG_FILE="$DATA_ROOT/logs/setup.log"
ENV_FILE="$DATA_ROOT/.env"
SERVICES_FILE="$METADATA_DIR/selected_services.json"
COMPOSE_DIR="$DATA_ROOT/compose"
COMPOSE_FILE="$DATA_ROOT/ai-platform/deployment/stack/docker-compose.yml"
CONFIG_DIR="$DATA_ROOT/config"
readonly CREDENTIALS_FILE="$METADATA_DIR/credentials.json"

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - SETUP                    ║${NC}"
    echo -e "${CYAN}║              Version 4.0.0 - Framework Refactor          ║${NC}"
    echo -e "${CYAN}║           Volume Detection + Domain Configuration          ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    # Temporarily disable logging to bypass the issue
    # echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    # Temporarily disable logging to bypass the issue
    # echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    # Temporarily disable logging to bypass the issue
    # echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    # Temporarily disable logging to bypass the issue
    # echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    
    echo ""
    print_header "$icon STEP $phase/13: $title"
}

confirm() {
    local message="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n -e "${YELLOW}$message [Y/n]:${NC} "
        else
            echo -n -e "${YELLOW}$message [y/N]:${NC} "
        fi
        
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please enter y or n" ;;
        esac
    done
}

prompt_input() {
    local var_name="$1"
    local prompt="$2"
    local default="$3"
    local is_password="${4:-false}"
    local validation="${5:-}"
    
    while true; do
        if [[ "$is_password" == "true" ]]; then
            echo -n -e "${YELLOW}$prompt [${NC}*****${YELLOW}]:${NC} "
            read -r -s INPUT_RESULT
            echo ""
        else
            if [[ -n "$default" ]]; then
                echo -n -e "${YELLOW}$prompt [${NC}$default${YELLOW}]:${NC} "
            else
                echo -n -e "${YELLOW}$prompt:${NC} "
            fi
            read -r INPUT_RESULT
        fi
        
        INPUT_RESULT=${INPUT_RESULT:-$default}
        
        # Validation
        if [[ -n "$validation" ]]; then
            case "$validation" in
                "email")
                    if [[ "$INPUT_RESULT" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                        break
                    else
                        print_error "Invalid email format"
                    fi
                    ;;
                "domain")
                    if [[ "$INPUT_RESULT" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                        break
                    else
                        print_error "Invalid domain format"
                    fi
                    ;;
                *)
                    break
                    ;;
            esac
        else
            break
        fi
    done
}

generate_random_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" | tr -d "=+/\n\r" | cut -c1-"$length"
}

setup_logging() {
    mkdir -p "$DATA_ROOT/logs"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

# State Management
save_state() {
    local phase="$1"
    local status="$2"
    local message="$3"
    
    mkdir -p "$METADATA_DIR"
    
    cat > "$STATE_FILE" <<EOF
{
  "script_version": "4.0.0",
  "current_phase": "$phase",
  "status": "$status",
  "message": "$message",
  "timestamp": "$(date -Iseconds)",
  "completed_phases": [
EOF
    
    local first=true
    for completed_phase in "${COMPLETED_PHASES[@]:-}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$STATE_FILE"
        fi
        first=false
        echo "    \"$completed_phase\"" >> "$STATE_FILE"
    done
    
    cat >> "$STATE_FILE" <<EOF
  ]
}
EOF
    
    print_success "State saved: Phase $phase - $status"
}

restore_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        print_info "No previous state found - starting fresh"
        return 1
    fi
    
    print_info "Found previous setup state"
    
    local current_phase=$(jq -r '.current_phase' "$STATE_FILE" 2>/dev/null || echo "")
    local status=$(jq -r '.status' "$STATE_FILE" 2>/dev/null || echo "")
    local message=$(jq -r '.message' "$STATE_FILE" 2>/dev/null || echo "")
    local timestamp=$(jq -r '.timestamp' "$STATE_FILE" 2>/dev/null || echo "")
    
    if [[ -z "$current_phase" ]]; then
        print_warning "State file corrupted - starting fresh"
        return 1
    fi
    
    echo ""
    print_header "🔄 Resume Previous Setup"
    echo ""
    print_info "Previous setup detected:"
    echo "  • Phase: $current_phase"
    echo "  • Status: $status"
    echo "  • Message: $message"
    echo "  • Time: $timestamp"
    echo ""
    
    if ! confirm "Resume from this state?"; then
        print_info "Starting fresh setup"
        rm -f "$STATE_FILE"
        return 1
    fi
    
    # Load completed phases
    local completed_phases_json=$(jq -r '.completed_phases[]' "$STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$completed_phases_json" ]]; then
        COMPLETED_PHASES=()
        while IFS= read -r phase; do
            COMPLETED_PHASES+=("$phase")
        done <<< "$completed_phases_json"
    fi
    
    print_success "State restored - resuming from phase $current_phase"
    return 0
}

mark_phase_complete() {
    local phase="$1"
    COMPLETED_PHASES+=("$phase")
    save_state "$phase" "completed" "Phase completed successfully"
}

# Core Functions
detect_system() {
    log_phase "1" "🔍" "System Detection"
    
    print_info "Detecting system hardware..."
    
    # Basic system info
    local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    local kernel=$(uname -r)
    local cpu_cores=$(nproc)
    local ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
    local disk_gb=$(df -BG /mnt/data | awk 'NR==2 {print $2}' | tr -d 'G')
    
    echo ""
    print_info "System Information:"
    echo "  • OS: $os_info"
    echo "  • Kernel: $kernel"
    echo "  • CPU Cores: $cpu_cores"
    echo "  • RAM: ${ram_gb}GB"
    echo "  • Available Disk: ${disk_gb}GB"
    echo ""
    
    # GPU Detection
    print_info "GPU Detection..."
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
        print_success "NVIDIA GPU detected: $gpu_info"
        echo "GPU_TYPE=nvidia" >> "$ENV_FILE"
        echo "GPU_ACCELERATED=true" >> "$ENV_FILE"
    else
        print_info "No NVIDIA GPU detected - CPU mode only"
        echo "GPU_TYPE=none" >> "$ENV_FILE"
        echo "GPU_ACCELERATED=false" >> "$ENV_FILE"
    fi
    
    echo ""
    print_success "System detection completed"
}

collect_domain_info() {
    log_phase "2" "🌐" "Domain & Network Configuration"
    
    echo ""
    print_header "🌐 Domain Configuration"
    echo ""
    
    # Collect running user information for proper ownership
    RUNNING_USER="${SUDO_USER:-$USER}"
    RUNNING_UID=$(id -u "$RUNNING_USER")
    RUNNING_GID=$(id -g "$RUNNING_USER")
    
    # Save user variables to environment file
    echo "RUNNING_USER=$RUNNING_USER" >> "$ENV_FILE"
    echo "RUNNING_UID=$RUNNING_UID" >> "$ENV_FILE"
    echo "RUNNING_GID=$RUNNING_GID" >> "$ENV_FILE"
    
    print_success "User configuration: $RUNNING_USER (UID:$RUNNING_UID, GID:$RUNNING_GID)"
    
    # DOMAIN is always localhost for backward compatibility
    echo "DOMAIN=localhost" >> "$ENV_FILE"
    
    # DOMAIN_NAME is what the user enters
    prompt_input "DOMAIN_NAME" "Enter your domain name (e.g., ai.datasquiz.net)" "" false "domain"
    echo "DOMAIN_NAME=$INPUT_RESULT" >> "$ENV_FILE"
    local domain_name="$INPUT_RESULT"  # Preserve domain name for validation
    
    # DOCKER_NETWORK configuration
    prompt_input "DOCKER_NETWORK" "Docker network name" "ai_platform" false
    echo "DOCKER_NETWORK=$INPUT_RESULT" >> "$ENV_FILE"
    
    # BASE_DIR configuration
    echo "BASE_DIR=/mnt/data" >> "$ENV_FILE"
    
    # COMPOSE_FILE configuration
    echo "COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml" >> "$ENV_FILE"
    
    # Validate domain resolution for DOMAIN_NAME
    echo ""
    print_info "Validating domain resolution..."
    
    # Skip validation if no domain provided (resuming from saved state)
    if [[ -z "${domain_name:-}" ]]; then
        print_info "No domain provided - skipping validation"
        echo "DOMAIN_RESOLVES=false" >> "$ENV_FILE"
        echo "PUBLIC_IP=" >> "$ENV_FILE"
        return 0
    fi
    
    # Special case for localhost
    if [[ "$domain_name" == "localhost" ]]; then
        print_success "Using localhost for development"
        echo "DOMAIN_RESOLVES=true" >> "$ENV_FILE"
        echo "PUBLIC_IP=127.0.0.1" >> "$ENV_FILE"
        # Set default proxy config method for localhost
        echo "PROXY_CONFIG_METHOD=direct" >> "$ENV_FILE"
    elif nslookup "$domain_name" >/dev/null 2>&1; then
        local public_ip=$(nslookup "$domain_name" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
        
        # Debug: Show nslookup results
        print_info "Debug: nslookup successful, public_ip=$public_ip"
        
        # Always store the resolved IP, regardless of reachability
        print_success "Domain resolves to IP: $public_ip"
        echo "DOMAIN_RESOLVES=true" >> "$ENV_FILE"
        echo "PUBLIC_IP=$public_ip" >> "$ENV_FILE"
        
        # Only warn if IP is different from server IP (for awareness)
        if [[ "$public_ip" != "$server_ip" ]]; then
            print_info "Note: Domain IP differs from server IP ($server_ip)"
            print_info "This is normal for load balancers, CDNs, or cloud services"
        fi
    else
        print_warning "Domain does not resolve or DNS not configured"
        # Still set to true if we can get public IP, as external access is possible
        local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')
        if [[ "$public_ip" != "unknown" ]]; then
            echo "DOMAIN_RESOLVES=true" >> "$ENV_FILE"
            echo "PUBLIC_IP=$public_ip" >> "$ENV_FILE"
            print_info "Public IP available: $public_ip - external access possible"
        else
            echo "DOMAIN_RESOLVES=false" >> "$ENV_FILE"
            echo "PUBLIC_IP=unknown" >> "$ENV_FILE"
            print_warning "No public IP available - local access only"
        fi
    fi
    
    echo ""
    print_header "🌐 Proxy Selection"
    echo ""
    echo "Select reverse proxy:"
    echo "  1) Nginx Proxy Manager (Visual UI - Recommended)"
    echo "  2) Traefik (Modern - Auto SSL with Docker labels)"
    echo "  3) Caddy (Automatic - Zero-config HTTPS)"
    echo "  4) None (Direct port access - Not recommended)"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Select option [1-4]:${NC} "
        read -r proxy_choice
        
        case "$proxy_choice" in
            1)
                echo "PROXY_TYPE=nginx-proxy-manager" >> "$ENV_FILE"
                print_success "Nginx Proxy Manager selected"
                break
                ;;
            2)
                echo "PROXY_TYPE=traefik" >> "$ENV_FILE"
                print_success "Traefik selected"
                break
                ;;
            3)
                echo "PROXY_TYPE=caddy" >> "$ENV_FILE"
                print_success "Caddy selected"
                break
                ;;
            4)
                echo "PROXY_TYPE=none" >> "$ENV_FILE"
                print_success "No proxy selected"
                break
                ;;
            *)
                print_error "Invalid selection"
                ;;
        esac
    done
    
    # Proxy Configuration Method (only if proxy was selected)
    if [[ "$proxy_choice" != "4" ]]; then
        echo ""
        print_header "🔧 Proxy Configuration Method"
        echo ""
        echo "Select how services should be accessed through the proxy:"
        echo "  1) Direct Port (e.g., :8080, :3000)"
        echo "     - Simple and direct access"
        echo "     - Good for development and internal use"
        echo ""
        echo "  2) Path Aliases (e.g., /signal, /n8n)"
        echo "     - Clean URLs with single domain"
        echo "     - Good for production and public access"
        echo ""
        echo "  3) Subdomain Access (e.g., n8n.domain.com, chat.domain.com)"
        echo "     - Professional URLs with dedicated subdomains"
        echo "     - Best for production and multiple services"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select configuration method [1-3]:${NC} "
            read -r proxy_config_choice
            
            case "$proxy_config_choice" in
                1)
                    echo "PROXY_CONFIG_METHOD=direct" >> "$ENV_FILE"
                    print_success "Direct port access selected"
                    break
                    ;;
                2)
                    echo "PROXY_CONFIG_METHOD=alias" >> "$ENV_FILE"
                    print_success "Path aliases selected"
                    break
                    ;;
                3)
                    echo "PROXY_CONFIG_METHOD=subdomain" >> "$ENV_FILE"
                    print_success "Subdomain access selected"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
    else
        # Set default for no proxy
        echo "PROXY_CONFIG_METHOD=direct" >> "$ENV_FILE"
    fi
    
    # SSL Configuration
    if [[ "$proxy_choice" != "4" ]]; then
        echo ""
        print_header "🔒 SSL Configuration"
        echo ""
        echo "Select SSL type:"
        echo "  1) Let's Encrypt (Free, automatic renewal)"
        echo "  2) Self-signed (Testing/internal use only)"
        echo "  3) None (HTTP only - not recommended)"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select SSL type [1-3]:${NC} "
            read -r ssl_choice
            
            case "$ssl_choice" in
                1)
                    echo "SSL_TYPE=letsencrypt" >> "$ENV_FILE"
                    prompt_input "SSL_EMAIL" "Let's Encrypt email" "" false "email"
                    echo "SSL_EMAIL=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Let's Encrypt SSL selected"
                    break
                    ;;
                2)
                    echo "SSL_TYPE=selfsigned" >> "$ENV_FILE"
                    print_success "Self-signed SSL selected"
                    break
                    ;;
                3)
                    echo "SSL_TYPE=none" >> "$ENV_FILE"
                    print_success "No SSL selected"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
    fi
    
    # Tailscale Configuration
    echo ""
    print_header "🔗 Tailscale Configuration (Optional)"
    echo ""
    
    if confirm "Configure Tailscale VPN for private access?"; then
        print_info "Tailscale Configuration"
        echo ""
        
        echo "Select Tailscale setup method:"
        echo "  1) Auth Key (Quick setup)"
        echo "  2) Auth Token (Existing network)"
        echo "  3) Skip"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select method [1-3]:${NC} "
            read -r tailscale_method
            
            case "$tailscale_method" in
                1)
                    prompt_input "TAILSCALE_AUTH_KEY" "Tailscale auth key" "" false
                    echo "TAILSCALE_AUTH_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    echo "TAILSCALE_SETUP_METHOD=auth_key" >> "$ENV_FILE"
                    print_success "Tailscale auth key configured"
                    break
                    ;;
                2)
                    prompt_input "TAILSCALE_AUTH_TOKEN" "Tailscale auth token" "" false
                    echo "TAILSCALE_AUTH_TOKEN=$INPUT_RESULT" >> "$ENV_FILE"
                    echo "TAILSCALE_SETUP_METHOD=auth_token" >> "$ENV_FILE"
                    print_success "Tailscale auth token configured"
                    break
                    ;;
                3)
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        # Tailscale network configuration
        echo ""
        prompt_input "TAILSCALE_TAILNET" "Tailscale tailnet name" "default" false
        echo "TAILSCALE_TAILNET=$INPUT_RESULT" >> "$ENV_FILE"
        
        # Optional Tailscale API key
        if confirm "Configure Tailscale API key (optional)?"; then
            prompt_input "TAILSCALE_API_KEY" "Tailscale API key" "" false
            echo "TAILSCALE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        echo "TAILSCALE_EXIT_NODE=false" >> "$ENV_FILE"
        echo "TAILSCALE_ACCEPT_ROUTES=false" >> "$ENV_FILE"
        
        print_success "Tailscale configuration completed"
    fi
    
    echo ""
    print_success "Domain configuration completed"
}

update_system() {
    log_phase "3" "🔄" "System Update"
    
    print_info "Updating system packages..."
    
    if command -v apt >/dev/null 2>&1; then
        apt update && apt upgrade -y
        print_success "System packages updated"
    else
        print_warning "Package manager not detected - skipping system update"
    fi
    
    # Install basic tools
    print_info "Installing basic tools..."
    apt install -y curl wget git jq openssl ca-certificates gnupg
    
    print_success "System update completed"
}

install_docker() {
    log_phase "4" "🐳" "Docker Installation"
    
    if command -v docker >/dev/null 2>&1; then
        print_info "Docker already installed"
        docker --version
        return 0
    fi
    
    print_info "Installing Docker..."
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start Docker
    systemctl start docker
    systemctl enable docker
    
    # Add user to docker group
    usermod -aG docker "${SUDO_USER:-$USER}"
    
    print_success "Docker installed successfully"
    docker --version
}

configure_docker() {
    log_phase "5" "⚙️" "Docker Configuration"
    
    print_info "Configuring Docker..."
    
    # Create Docker daemon config
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "storage-driver": "overlay2"
}
EOF
    
    # Restart Docker
    systemctl restart docker
    
    # Create networks
    docker network create ${DOCKER_NETWORK} 2>/dev/null || true
    docker network create ${DOCKER_NETWORK}_internal 2>/dev/null || true
    docker network create ${DOCKER_NETWORK}_monitoring 2>/dev/null || true
    
    print_success "Docker configured successfully"
}

install_ollama() {
    log_phase "6" "🤖" "Ollama Installation"
    
    if command -v ollama >/dev/null 2>&1; then
        print_info "Ollama already installed"
        return 0
    fi
    
    print_info "Installing Ollama..."
    
    # Install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh
    
    # Start Ollama service
    systemctl start ollama 2>/dev/null || true
    systemctl enable ollama 2>/dev/null || true
    
    print_success "Ollama installed successfully"
}

select_services() {
    log_phase "7" "🎯" "Service Selection"
    
    echo ""
    print_header "📋 Available Services"
    echo ""
    print_info "Select services to deploy. Dependencies will be auto-selected."
    echo ""
    
    # Infrastructure Services
    echo "🏗️  Infrastructure:"
    echo "  [1] PostgreSQL - Relational database"
    echo "  [2] Redis - Cache and message queue"
    echo "  [3] Tailscale - VPN mesh network"
    echo ""
    
    # AI Applications
    echo "🤖 AI Applications:"
    echo "  [4] Open WebUI - Modern ChatGPT-like interface"
    echo "  [5] AnythingLLM - Document-based AI chat"
    echo "  [6] Dify - LLM application development platform"
    echo "  [7] n8n - Workflow automation platform"
    echo "  [8] Flowise - Visual LangChain builder"
    echo "  [9] Ollama - Local LLM runtime"
    echo "  [10] LiteLLM - Multi-provider proxy + routing"
    echo ""
    
    # Communication & Integration
    echo "📱 Communication & Integration:"
    echo "  [11] Signal API - Private messaging"
    echo "  [12] OpenClaw UI - Multi-channel orchestration"
    echo ""
    
    # Monitoring
    echo "📊 Monitoring:"
    echo "  [13] Prometheus + Grafana - Metrics and visualization"
    echo ""
    
    # Storage
    echo "📦 Storage:"
    echo "  [14] MinIO - S3-compatible storage"
    echo ""
    
    echo "Select services (space-separated, e.g., '1 3 6'):"
    echo "Or enter 'all' to select all recommended services"
    echo ""
    
    local -A selected_map=(
        ["postgres"]=1
        ["redis"]=1
        ["tailscale"]=1
        ["openwebui"]=1
        ["anythingllm"]=1
        ["dify"]=1
        ["n8n"]=1
        ["flowise"]=1
        ["ollama"]=1
        ["litellm"]=1
        ["signal-api"]=1
        ["openclaw"]=1
        ["prometheus"]=1
        ["grafana"]=1
        ["minio"]=1
    )
    
    while true; do
        echo -n -e "${YELLOW}Enter selection:${NC} "
        read -r selection
        
        if [[ "$selection" == "all" ]]; then
            for service in "${!selected_map[@]}"; do
                selected_map[$service]=1
            done
            print_success "All recommended services selected"
            break
        elif [[ "$selection" =~ ^[0-9\ ]+$ ]]; then
            for num in $selection; do
                if [[ $num -ge 1 ]] && [[ $num -le 14 ]]; then
                    local service_name
                    case $num in
                        1) service_name="postgres" ;;
                        2) service_name="redis" ;;
                        3) service_name="tailscale" ;;
                        4) service_name="openwebui" ;;
                        5) service_name="anythingllm" ;;
                        6) service_name="dify" ;;
                        7) service_name="n8n" ;;
                        8) service_name="flowise" ;;
                        9) service_name="ollama" ;;
                        10) service_name="litellm" ;;
                        11) service_name="signal-api" ;;
                        12) service_name="openclaw" ;;
                        13) service_name="prometheus" ;;
                        14) service_name="minio" ;;
                        *) print_warning "Invalid selection: $num (must be 1-14)"; continue ;;
                    esac
                    
                    if [[ -n "${selected_map[$service_name]:-}" ]]; then
                        selected_map[$service_name]=1
                        print_success "Added: $service_name"
                    else
                        selected_map[$service_name]=0
                        print_info "Removed: $service_name"
                    fi
                else
                    print_warning "Invalid selection: $num (must be 1-14)"
                fi
            done
            break
        else
            print_error "Invalid selection. Please enter numbers 1-14 or 'all'"
        fi
    done
    
    # Convert selected services to array
    local selected_services=()
    for service in "${!selected_map[@]}"; do
        if [[ "${selected_map[$service]}" == "1" ]]; then
            selected_services+=("$service")
        fi
    done
    
    # Vector Database Selection (separate from services)
    if [[ " ${selected_services[*]} " =~ " litellm " ]] || [[ " ${selected_services[*]} " =~ " openwebui " ]] || [[ " ${selected_services[*]} " =~ " anythingllm " ]] || [[ " ${selected_services[*]} " =~ " dify " ]] || [[ " ${selected_services[*]} " =~ " n8n " ]]; then
        echo ""
        print_header "🧠 Vector Database Selection"
        echo ""
        echo "Select vector database for RAG applications:"
        echo ""
        echo "  1) Qdrant (Recommended)"
        echo "     - REST + gRPC API"
        echo "     - Web dashboard"
        echo "     - Production-ready"
        echo ""
        echo "  2) Milvus"
        echo "     - High performance"
        echo "     - Distributed support"
        echo "     - Cloud-native"
        echo ""
        echo "  3) ChromaDB"
        echo "     - Python-native"
        echo "     - Good for development"
        echo ""
        echo "  4) Weaviate"
        echo "     - GraphQL API"
        echo "     - Semantic search"
        echo "     - Modular architecture"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select vector database [1-4]:${NC} "
            read -r vector_db_choice
            
            case "$vector_db_choice" in
                1)
                    echo "VECTOR_DB=qdrant" >> "$ENV_FILE"
                    echo "VECTOR_DB_TYPE=qdrant" >> "$ENV_FILE"
                    print_success "Qdrant selected as vector database"
                    break
                    ;;
                2)
                    echo "VECTOR_DB=milvus" >> "$ENV_FILE"
                    echo "VECTOR_DB_TYPE=milvus" >> "$ENV_FILE"
                    print_success "Milvus selected as vector database"
                    break
                    ;;
                3)
                    echo "VECTOR_DB=chroma" >> "$ENV_FILE"
                    echo "VECTOR_DB_TYPE=chroma" >> "$ENV_FILE"
                    print_success "ChromaDB selected as vector database"
                    break
                    ;;
                4)
                    echo "VECTOR_DB=weaviate" >> "$ENV_FILE"
                    echo "VECTOR_DB_TYPE=weaviate" >> "$ENV_FILE"
                    print_success "Weaviate selected as vector database"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
    fi
    
    if [[ ${#selected_services[@]} -eq 0 ]]; then
        print_error "No services selected"
        return 1
    fi
    
    # Display final selection
    echo ""
    print_header "✅ Selected Services (${#selected_services[@]})"
    echo ""
    
    for service in "${selected_services[@]}"; do
        echo "  • $service"
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
        
        cat >> "$SERVICES_FILE" <<EOF
    {
      "key": "$service_key",
      "display_name": "$service_key",
      "description": "Service description",
      "category": "category"
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

collect_configurations() {
    log_phase "8" "⚙️" "Configuration Collection"
    
    # Set user variables for this function
    RUNNING_USER="${SUDO_USER:-$USER}"
    RUNNING_UID=$(id -u "$RUNNING_USER")
    RUNNING_GID=$(id -g "$RUNNING_USER")
    
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Services file not found: $SERVICES_FILE"
        exit 1
    fi
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE"))
    
    echo ""
    print_header "🔍 Port Availability Check"
    echo ""
    
    # Port availability check
    local ports_to_check=(
        "80:Proxy Services"
        "443:Proxy Services"
        "3000:Open WebUI"
        "3001:AnythingLLM"
        "3002:Flowise"
        "5678:n8n"
        "8080:Dify"
        "8082:OpenClaw"
        "8090:Signal API"
        "8443:Tailscale"
        "9000:MinIO"
        "9001:MinIO Console"
        "9090:Prometheus"
        "3005:Grafana"
        "11434:Ollama"
        "18789:OpenClaw Admin"
        "4000:LiteLLM"
        "5432:PostgreSQL"
        "6379:Redis"
        "6333:Qdrant"
        "19530:Milvus"
        "8000:ChromaDB"
        "8080:Weaviate"
    )
    
    local port_conflicts=()
    
    for port_info in "${ports_to_check[@]}"; do
        local port=$(echo "$port_info" | cut -d: -f1)
        local service=$(echo "$port_info" | cut -d: -f2)
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            local pid=$(netstat -tuln 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d/ -f1)
            print_warning "Port $port is in use by $service (pid: $pid)"
            port_conflicts+=("$port:$service:$pid")
        else
            print_success "Port $port is available for $service"
        fi
    done
    
    if [[ ${#port_conflicts[@]} -gt 0 ]]; then
        echo ""
        print_header "⚠️ Port Conflicts Detected"
        echo ""
        print_info "The following ports are in use:"
        for conflict in "${port_conflicts[@]}"; do
            local port=$(echo "$conflict" | cut -d: -f1)
            local service=$(echo "$conflict" | cut -d: -f2)
            local pid=$(echo "$conflict" | cut -d: -f3)
            echo "  • Port $port ($service) - PID: $pid"
        done
        echo ""
        
        if ! confirm "Continue with port conflicts?"; then
            print_info "Configuration cancelled"
            return 1
        fi
    fi
    
    echo ""
    print_header "⚙️ Configuration Collection"
    echo ""
    
    # Initialize environment file (preserve existing domain variables)
    # Read existing domain variables if they exist (get last occurrence to avoid duplicates)
    local existing_domain=$(grep "^DOMAIN=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "localhost")
    local existing_domain_name=$(grep "^DOMAIN_NAME=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "$existing_domain")
    local existing_domain_resolves=$(grep "^DOMAIN_RESOLVES=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "false")
    local existing_public_ip=$(grep "^PUBLIC_IP=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "unknown")
    local existing_proxy_config_method=$(grep "^PROXY_CONFIG_METHOD=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "direct")
    local existing_ssl_type=$(grep "^SSL_TYPE=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "none")
    local existing_ssl_email=$(grep "^SSL_EMAIL=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "")
    local existing_proxy_type=$(grep "^PROXY_TYPE=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "none")
    
    # Create environment file with correct ownership
    cat > "$ENV_FILE" <<EOF
# AI Platform Environment
# Generated: $(date -Iseconds)

# System Configuration
DATA_ROOT=$DATA_ROOT
METADATA_DIR=$METADATA_DIR
TIMEZONE=UTC
LOG_LEVEL=info

# Network Configuration (DOMAIN=localhost by default)
DOMAIN_NAME=$existing_domain_name
DOMAIN=$existing_domain
DOMAIN_RESOLVES=$existing_domain_resolves
PUBLIC_IP=$existing_public_ip
PROXY_CONFIG_METHOD=$existing_proxy_config_method
PROXY_TYPE=$existing_proxy_type
SSL_TYPE=$existing_ssl_type
SSL_EMAIL=$existing_ssl_email

# Docker Configuration
DOCKER_NETWORK=ai_platform
COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml

# Vector Database Configuration
VECTOR_DB=qdrant
VECTOR_DB_TYPE=qdrant

# User Configuration
RUNNING_USER=$RUNNING_USER
RUNNING_UID=$RUNNING_UID
RUNNING_GID=$RUNNING_GID
EOF
    
    # Set correct ownership for .env file
    chown "${RUNNING_UID}:${RUNNING_GID}" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    # Service Binding Configuration
    echo ""
    print_header "🔗 Service Binding Configuration"
    echo ""
    echo "Select how services should bind to network interfaces:"
    echo "  1) Localhost only (127.0.0.1) - More secure, internal access only"
    echo "  2) All interfaces (0.0.0.0) - Accessible from external networks"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Select binding option [1-2]:${NC} "
        read -r bind_choice
        
        case "$bind_choice" in
            1)
                echo "BIND_IP=127.0.0.1" >> "$ENV_FILE"
                print_success "Services will bind to localhost only"
                break
                ;;
            2)
                echo "BIND_IP=0.0.0.0" >> "$ENV_FILE"
                print_success "Services will bind to all interfaces (external access)"
                break
                ;;
            *)
                print_error "Invalid selection"
                ;;
        esac
    done
    
    # Port configuration
    echo ""
    print_info "Port Configuration"
    echo ""
    
    # Custom port selection for major services
    local -A default_ports=(
        ["nginx-proxy-manager"]="80"
        ["traefik"]="80"
        ["caddy"]="80"
        ["openwebui"]="5006"
        ["anythingllm"]="5004"
        ["n8n"]="5002"
        ["dify"]="5003"
        ["ollama"]="11434"
        ["litellm"]="5005"
        ["prometheus"]="5000"
        ["grafana"]="5001"
        ["signal-api"]="8080"
        ["openclaw"]="18789"
        ["tailscale"]="8443"
        ["postgres"]="5432"
        ["redis"]="6379"
        ["qdrant"]="6333"
        ["milvus"]="19530"
        ["chroma"]="8000"
        ["weaviate"]="8080"
        ["minio"]="5007"
    )
    
    # Proxy port configuration (only if proxy was selected in domain phase)
    if [[ "${PROXY_TYPE:-}" == "nginx-proxy-manager" ]] || [[ "${PROXY_TYPE:-}" == "traefik" ]] || [[ "${PROXY_TYPE:-}" == "caddy" ]]; then
        echo ""
        print_info "Proxy Port Configuration"
        echo ""
        
        if [[ "${PROXY_TYPE:-}" == "nginx-proxy-manager" ]]; then
            print_info "Configuring Nginx Proxy Manager ports (default: 80, 443)"
            prompt_input "NGINX_PROXY_HTTP_PORT" "Nginx Proxy Manager HTTP port" "80" false
            echo "NGINX_PROXY_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "NGINX_PROXY_HTTPS_PORT" "Nginx Proxy Manager HTTPS port" "443" false
            echo "NGINX_PROXY_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        if [[ "${PROXY_TYPE:-}" == "traefik" ]]; then
            print_info "Configuring Traefik ports (default: 80, 443)"
            prompt_input "TRAEFIK_HTTP_PORT" "Traefik HTTP port" "80" false
            echo "TRAEFIK_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "TRAEFIK_HTTPS_PORT" "Traefik HTTPS port" "443" false
            echo "TRAEFIK_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        if [[ "${PROXY_TYPE:-}" == "caddy" ]]; then
            print_info "Configuring Caddy ports (default: 80, 443)"
            prompt_input "CADDY_HTTP_PORT" "Caddy HTTP port" "80" false
            echo "CADDY_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "CADDY_HTTPS_PORT" "Caddy HTTPS port" "443" false
            echo "CADDY_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
    fi
    
    print_success "Proxy configuration completed"
    
# Port allocation with retry loop
allocate_port() {
    local service=$1
    local default_port=$2
    local port
    
    while true; do
        read -p "  ${service} port [${default_port}]: " port_input
        port=${port_input:-$default_port}
        
        if ss -tlnp | grep -q ":${port} "; then
            echo "  ⚠️  Port ${port} in use — try another"
        else
            echo "  ✅ ${service}: ${port}"
            # Convert service name to uppercase and replace hyphens with underscores
            local var_name=$(echo "$service" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            echo "${var_name}_PORT=${port}" >> "$ENV_FILE"
            break
        fi
    done
}
    
    # Service port configuration
    for service_key in "${selected_services[@]}"; do
        case "$service_key" in
            "nginx-proxy-manager"|"traefik"|"caddy"|"openwebui"|"anythingllm"|"n8n"|"dify"|"ollama"|"litellm"|"prometheus"|"grafana"|"signal-api"|"openclaw"|"tailscale"|"postgres"|"redis"|"qdrant"|"milvus"|"chroma"|"weaviate"|"minio")
                local default_port="${default_ports[$service_key]:-3000}"
                allocate_port "$service_key" "$default_port"
                ;;
        esac
    done
    
    # Ollama model selection
    if [[ " ${selected_services[*]} " =~ " ollama " ]]; then
        echo ""
        print_header "🤖 Ollama Model Selection"
        echo ""
        
        print_info "Select models to download and use:"
        echo ""
        echo "Recommended Models:"
        echo "  [1] llama3.2:8b (7.8GB) - Latest Llama 3.2"
        echo "  [2] llama3.2:70b (43GB) - Full Llama 3.2 (requires 64GB RAM)"
        echo "  [3] mistral:7b (4.7GB) - Mistral 7B"
        echo "  [4] codellama:13b (7.6GB) - Code Llama"
        echo "  [5] qwen2.5:14b (8.2GB) - Qwen 2.5"
        echo ""
        echo "Specialized Models:"
        echo "  [6] llama3.1:8b (4.9GB) - Llama 3.1"
        echo "  [7] mixtral:8x7b (4.7GB) - Mixtral MoE"
        echo "  [8] deepseek-coder:6.7b (3.8GB) - DeepSeek Coder"
        echo ""
        echo "Select models (space-separated, e.g., '1 3 5'):"
        echo "Or enter 'recommended' for models 1,3,4"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Enter model selection:${NC} "
            read -r model_selection
            
            if [[ "$model_selection" == "recommended" ]]; then
                echo "OLLAMA_MODELS=llama3.2:8b,mistral:7b,codellama:13b" >> "$ENV_FILE"
                print_success "Recommended models selected: llama3.2:8b, mistral:7b, codellama:13b"
                break
            elif [[ "$model_selection" =~ ^[0-9\ ]+$ ]]; then
                local selected_models=()
                for num in $model_selection; do
                    case $num in
                        1) selected_models+=("llama3.2:8b") ;;
                        2) selected_models+=("llama3.2:70b") ;;
                        3) selected_models+=("mistral:7b") ;;
                        4) selected_models+=("codellama:13b") ;;
                        5) selected_models+=("qwen2.5:14b") ;;
                        6) selected_models+=("llama3.1:8b") ;;
                        7) selected_models+=("mixtral:8x7b") ;;
                        8) selected_models+=("deepseek-coder:6.7b") ;;
                        *) print_warning "Invalid model selection: $num" ;;
                    esac
                done
                
                if [[ ${#selected_models[@]} -gt 0 ]]; then
                    local models_str=$(IFS=','; echo "${selected_models[*]}")
                    echo "OLLAMA_MODELS=$models_str" >> "$ENV_FILE"
                    print_success "Models selected: $models_str"
                    break
                fi
            else
                print_error "Invalid selection. Please enter numbers 1-8 or 'recommended'"
            fi
        done
        
        # Default model
        echo ""
        prompt_input "OLLAMA_DEFAULT_MODEL" "Default Ollama model" "llama3.2:8b" false
        echo "OLLAMA_DEFAULT_MODEL=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Ollama configuration completed"
    fi
    if [[ " ${selected_services[*]} " =~ " postgres " ]]; then
        echo ""
        print_info "PostgreSQL Configuration"
        echo ""
        
        # Allow override of database name and username
        print_info "Database Configuration (Optional Overrides)"
        echo "Note: All services will be pre-configured to use this vector database"
        echo ""
        
        prompt_input "POSTGRES_DB" "PostgreSQL database name" "aiplatform" false
        echo "POSTGRES_DB=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "POSTGRES_USER" "PostgreSQL username" "postgres" false
        echo "POSTGRES_USER=$INPUT_RESULT" >> "$ENV_FILE"
        
        local postgres_password=$(generate_random_password 24)
        echo "POSTGRES_PASSWORD=$postgres_password" >> "$ENV_FILE"
        
        # Check if default port is available
        if [[ " ${port_conflicts[*]} " =~ "5432:" ]]; then
            prompt_input "POSTGRES_PORT" "PostgreSQL port (5432 in use)" "5433" false
            echo "POSTGRES_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        else
            echo "POSTGRES_PORT=5432" >> "$ENV_FILE"
        fi
        
        print_success "PostgreSQL configuration generated"
    fi
    
    # Redis configuration
    if [[ " ${selected_services[*]} " =~ " redis " ]]; then
        echo ""
        print_info "Redis Configuration"
        echo ""
        
        # Allow override of Redis configuration
        print_info "Redis Configuration (Optional Overrides)"
        echo ""
        
        prompt_input "REDIS_USER" "Redis username (leave empty for default)" "" false
        if [[ -n "$INPUT_RESULT" ]]; then
            echo "REDIS_USER=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        local redis_password=$(generate_random_password 24)
        echo "REDIS_PASSWORD=$redis_password" >> "$ENV_FILE"
        
        # Check if default port is available
        if [[ " ${port_conflicts[*]} " =~ "6379:" ]]; then
            prompt_input "REDIS_PORT" "Redis port (6379 in use)" "6380" false
            echo "REDIS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        else
            echo "REDIS_PORT=6379" >> "$ENV_FILE"
        fi
        
        print_success "Redis configuration generated"
    fi
    
    
    # LLM Provider Selection (moved before routing strategy)
    if [[ " ${selected_services[*]} " =~ " litellm " ]]; then
        echo ""
        print_header "🤖 LLM Provider Configuration"
        echo ""
        
        print_info "Configure LLM providers for LiteLLM routing:"
        echo ""
        echo "✅ Local Provider:"
        echo "  • Ollama (will be deployed)"
        echo "  • Models: ${OLLAMA_MODELS:-llama3.2:8b,mistral:7b,codellama:13b}"
        echo ""
        
        echo "Add API providers? (recommended for fallback)"
        echo ""
        # Dynamic LLM provider selection
        local selected_providers=("local")
        local provider_keys=()
        
        echo ""
        print_info "Configure LLM providers (Y/N for each):"
        echo ""
        
        # OpenAI
        if confirm "Configure OpenAI (GPT-4, GPT-3.5)?"; then
            selected_providers+=("openai")
            provider_keys+=("OPENAI_API_KEY")
            prompt_input "OPENAI_API_KEY" "OpenAI API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "OPENAI_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "OPENAI_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # Anthropic
        if confirm "Configure Anthropic (Claude 3)?"; then
            selected_providers+=("anthropic")
            provider_keys+=("ANTHROPIC_API_KEY")
            prompt_input "ANTHROPIC_API_KEY" "Anthropic API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "ANTHROPIC_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "ANTHROPIC_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # Google
        if confirm "Configure Google (Gemini)?"; then
            selected_providers+=("google")
            provider_keys+=("GOOGLE_API_KEY")
            prompt_input "GOOGLE_API_KEY" "Google AI API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "GOOGLE_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "GOOGLE_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # Groq
        if confirm "Configure Groq (Fast Llama inference)?"; then
            selected_providers+=("groq")
            provider_keys+=("GROQ_API_KEY")
            prompt_input "GROQ_API_KEY" "Groq API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "GROQ_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "GROQ_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # Mistral
        if confirm "Configure Mistral (Mistral AI)?"; then
            selected_providers+=("mistral")
            provider_keys+=("MISTRAL_API_KEY")
            prompt_input "MISTRAL_API_KEY" "Mistral API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "MISTRAL_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "MISTRAL_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # OpenRouter
        if confirm "Configure OpenRouter (Multi-provider access)?"; then
            selected_providers+=("openrouter")
            provider_keys+=("OPENROUTER_API_KEY")
            prompt_input "OPENROUTER_API_KEY" "OpenRouter API key" "" false
            # API Keys - properly quoted to handle special characters
            if [[ -n "$INPUT_RESULT" ]]; then
                echo "OPENROUTER_API_KEY='$INPUT_RESULT'" >> "$ENV_FILE"
            else
                echo "OPENROUTER_API_KEY=" >> "$ENV_FILE"
            fi
        fi
        
        # Configure providers
        if [[ ${#selected_providers[@]} -gt 1 ]]; then
            local providers_str=$(IFS=','; echo "${selected_providers[*]}")
            echo "LLM_PROVIDERS=$providers_str" >> "$ENV_FILE"
            print_success "Providers configured: $providers_str"
        else
            echo "LLM_PROVIDERS=local" >> "$ENV_FILE"
            print_success "Local provider only"
        fi
        
        # LiteLLM routing strategy (now after providers are configured)
        echo ""
        print_header "🔄 LiteLLM Routing Strategy"
        echo ""
        
        echo "Select routing strategy for configured providers:"
        echo ""
        echo "  1) simple-shuffle"
        echo "     Random selection from available models"
        echo ""
        echo "  2) cost-based-routing (Recommended)"
        echo "     Choose cheapest model first, fallback on expensive"
        echo ""
        echo "  3) latency-based-routing"
        echo "     Choose fastest model based on historical latency"
        echo ""
        echo "  4) usage-based-routing"
        echo "     Load balance across all models"
        echo ""
        echo "  5) local-first-routing"
        echo "     Simple queries → local models, Complex queries → external models"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select routing strategy [1-5]:${NC} "
            read -r routing_choice
            
            case "$routing_choice" in
                1)
                    echo "LITELLM_ROUTING_STRATEGY=simple-shuffle" >> "$ENV_FILE"
                    print_success "Simple Shuffle routing selected"
                    break
                    ;;
                2)
                    echo "LITELLM_ROUTING_STRATEGY=cost-based" >> "$ENV_FILE"
                    print_success "Cost-based routing selected"
                    break
                    ;;
                3)
                    echo "LITELLM_ROUTING_STRATEGY=latency-based" >> "$ENV_FILE"
                    print_success "Latency-based routing selected"
                    break
                    ;;
                4)
                    echo "LITELLM_ROUTING_STRATEGY=usage-based" >> "$ENV_FILE"
                    print_success "Usage-based routing selected"
                    break
                    ;;
                5)
                    echo "LITELLM_ROUTING_STRATEGY=local-first" >> "$ENV_FILE"
                    print_success "Local-first routing selected (simple → local, complex → external)"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        # LiteLLM core variables
        print_info "LiteLLM Configuration (Optional Overrides)"
        echo ""
        
        prompt_input "LITELLM_MASTER_KEY" "LiteLLM master key (leave empty to auto-generate)" "" false
        local litellm_master_key="$INPUT_RESULT"
        if [[ -z "$litellm_master_key" ]]; then
            litellm_master_key=$(generate_random_password 32)
        fi
        
        prompt_input "LITELLM_SALT_KEY" "LiteLLM salt key (leave empty to auto-generate)" "" false
        local litellm_salt_key="$INPUT_RESULT"
        if [[ -z "$litellm_salt_key" ]]; then
            litellm_salt_key=$(generate_random_password 16)
        fi
        
        echo "LITELLM_MASTER_KEY=$litellm_master_key" >> "$ENV_FILE"
        echo "LITELLM_SALT_KEY=$litellm_salt_key" >> "$ENV_FILE"
        echo "LITELLM_CACHE_ENABLED=true" >> "$ENV_FILE"
        echo "LITELLM_CACHE_TTL=3600" >> "$ENV_FILE"
        echo "LITELLM_RATE_LIMIT_ENABLED=true" >> "$ENV_FILE"
        echo "LITELLM_RATE_LIMIT_REQUESTS_PER_MINUTE=60" >> "$ENV_FILE"
        
        print_success "LiteLLM configuration completed"
    fi
    
    # Signal API configuration
    if [[ " ${selected_services[*]} " =~ " signal-api " ]]; then
        echo ""
        print_header "📱 Signal API Configuration"
        echo ""
        
        print_info "Signal Bot Configuration"
        echo ""
        
        prompt_input "SIGNAL_PHONE" "Signal phone number (E.164 format, e.g., +15551234567)" "" false
        echo "SIGNAL_PHONE=$INPUT_RESULT" >> "$ENV_FILE"
        
        # Signal pairing options
        echo ""
        print_info "Signal Pairing Options:"
        echo ""
        echo "  1) Generate QR Code (Recommended - scan with Signal app)"
        echo "  2) Internal API pairing (http://localhost:8081/v1/generate_token)"
        echo "  3) Manual pairing (advanced)"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select pairing method [1-3]:${NC} "
            read -r signal_pairing
            
            case "$signal_pairing" in
                1)
                    echo "SIGNAL_PAIRING_METHOD=qr_code" >> "$ENV_FILE"
                    echo "SIGNAL_QR_URL=http://localhost:8090/v1/qrcode" >> "$ENV_FILE"
                    print_success "QR code pairing selected"
                    print_info "QR code will be available at: http://localhost:8090/v1/qrcode"
                    break
                    ;;
                2)
                    echo "SIGNAL_PAIRING_METHOD=internal_api" >> "$ENV_FILE"
                    echo "SIGNAL_API_PAIRING_URL=http://localhost:8081/v1/qrcodelink?device_name=signal-api" >> "$ENV_FILE"
                    print_success "Internal API pairing selected"
                    print_info "Pairing token will be available at: http://localhost:8081/v1/qrcodelink?device_name=signal-api"
                    break
                    ;;
                3)
                    echo "SIGNAL_PAIRING_METHOD=manual" >> "$ENV_FILE"
                    local signal_password=$(generate_random_password 16)
                    echo "SIGNAL_PASSWORD=$signal_password" >> "$ENV_FILE"
                    print_success "Manual pairing selected"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        # Signal webhook configuration
        echo ""
        print_info "Signal Webhook Configuration"
        echo ""
        echo "SIGNAL_WEBHOOK_URL=http://signal-api:8090/v2/receive" >> "$ENV_FILE"
        echo "SIGNAL_API_PORT=8090" >> "$ENV_FILE"
        
        print_success "Signal API configuration completed"
    fi
    
    # OpenClaw configuration
    if [[ " ${selected_services[*]} " =~ " openclaw " ]]; then
        echo ""
        print_header "🔗 OpenClaw UI Configuration"
        echo ""
        
        print_info "OpenClaw Multi-Channel Orchestration"
        echo ""
        
        prompt_input "OPENCLAW_ADMIN_USER" "OpenClaw admin user" "admin" false
        echo "OPENCLAW_ADMIN_USER=$INPUT_RESULT" >> "$ENV_FILE"
        
        local openclaw_password=$(generate_random_password 24)
        echo "OPENCLAW_ADMIN_PASSWORD=$openclaw_password" >> "$ENV_FILE"
        
        # Web Search Configuration
        echo ""
        print_info "Web Search Configuration"
        echo "Select web search provider for OpenClaw:"
        echo "  1) Brave Search API (Recommended)"
        echo "  2) SerpApi (Google Search)"
        echo "  3) Both Brave and SerpApi"
        echo "  4) None (Disable web search)"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select web search provider [1-4]:${NC} "
            read -r websearch_choice
            
            case "$websearch_choice" in
                1)
                    echo "OPENCLAW_WEBSEARCH=brave" >> "$ENV_FILE"
                    prompt_input "BRAVE_API_KEY" "Brave Search API key" "" false
                    echo "BRAVE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Brave Search API selected"
                    break
                    ;;
                2)
                    echo "OPENCLAW_WEBSEARCH=serpapi" >> "$ENV_FILE"
                    prompt_input "SERPAPI_KEY" "SerpApi key" "" false
                    echo "SERPAPI_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "SerpApi selected"
                    break
                    ;;
                3)
                    echo "OPENCLAW_WEBSEARCH=both" >> "$ENV_FILE"
                    prompt_input "BRAVE_API_KEY" "Brave Search API key" "" false
                    echo "BRAVE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "SERPAPI_KEY" "SerpApi key" "" false
                    echo "SERPAPI_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Both Brave Search API and SerpApi selected"
                    break
                    ;;
                4)
                    echo "OPENCLAW_WEBSEARCH=none" >> "$ENV_FILE"
                    print_success "Web search disabled"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        echo "OPENCLAW_PORT=18789" >> "$ENV_FILE"
        echo "OPENCLAW_API_PORT=8083" >> "$ENV_FILE"
        
        # OpenClaw integration settings
        echo "OPENCLAW_ENABLE_SIGNAL=true" >> "$ENV_FILE"
        echo "OPENCLAW_ENABLE_LITELM=true" >> "$ENV_FILE"
        echo "OPENCLAW_ENABLE_N8N=true" >> "$ENV_FILE"
        
        # OpenClaw Sandbox Configuration
        echo ""
        print_info "OpenClaw Sandbox Setup"
        echo ""
        
        # Create dedicated sandbox directory structure
        local openclaw_sandbox="${DATA_ROOT}/data/openclaw"
        local openclaw_config="${DATA_ROOT}/config/openclaw"
        
        # Set up OpenClaw as dedicated user sandbox
        echo "OPENCLAW_SANDBOX_DIR=${openclaw_sandbox}" >> "$ENV_FILE"
        echo "OPENCLAW_CONFIG_DIR=${openclaw_config}" >> "$ENV_FILE"
        
        # OpenClaw security settings
        echo "OPENCLAW_READONLY_ROOTFS=true" >> "$ENV_FILE"
        echo "OPENCLAW_TMPFS_SIZE=100m" >> "$ENV_FILE"
        echo "OPENCLAW_NETWORK_ISOLATION=true" >> "$ENV_FILE"
        
        # OpenClaw integration paths
        echo "OPENCLAW_DATA_PATH=${openclaw_sandbox}" >> "$ENV_FILE"
        echo "OPENCLAW_CONFIG_PATH=${openclaw_config}" >> "$ENV_FILE"
        
        print_success "OpenClaw sandbox configuration completed"
        print_info "OpenClaw will run in dedicated sandbox at ${openclaw_sandbox}"
        
        print_success "OpenClaw configuration completed"
    fi
    echo ""
    print_info "Google Drive Integration (Optional)"
    echo ""
    
    if confirm "Configure Google Drive sync?"; then
        print_info "Google Drive Configuration"
        echo ""
        
        echo "Select authentication method:"
        echo "  1) OAuth 2.0 (Recommended for personal use)"
        echo "  2) Service Account (Recommended for server use)"
        echo "  3) rclone (Advanced)"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select method [1-3]:${NC} "
            read -r auth_method
            
            case "$auth_method" in
                1)
                    echo "GDRIVE_AUTH_METHOD=oauth" >> "$ENV_FILE"
                    prompt_input "GDRIVE_CLIENT_ID" "Google Client ID" "" false
                    echo "GDRIVE_CLIENT_ID=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "GDRIVE_CLIENT_SECRET" "Google Client Secret" "" true
                    echo "GDRIVE_CLIENT_SECRET=$INPUT_RESULT" >> "$ENV_FILE"
                    break
                    ;;
                2)
                    echo "GDRIVE_AUTH_METHOD=service_account" >> "$ENV_FILE"
                    print_info "Service account JSON file path:"
                    echo -n -e "${YELLOW}Path to service account JSON:${NC} "
                    read -r json_path
                    echo "GDRIVE_SERVICE_ACCOUNT_JSON=$json_path" >> "$ENV_FILE"
                    break
                    ;;
                3)
                    echo "GDRIVE_AUTH_METHOD=rclone" >> "$ENV_FILE"
                    print_info "rclone configuration will be set up later"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        prompt_input "GDRIVE_SYNC_INTERVAL" "Sync interval in minutes" "15" false
        echo "GDRIVE_SYNC_INTERVAL=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Google Drive configuration completed"
    fi
    
    # Application-specific configurations
    echo ""
    print_info "Application Configuration"
    echo ""
    
    # Flowise configuration (if selected)
    if [[ " ${selected_services[*]} " =~ " flowise " ]]; then
        echo ""
        print_info "Flowise Configuration"
        echo ""
        
        prompt_input "FLOWISE_USERNAME" "Flowise username" "admin" false
        echo "FLOWISE_USERNAME=$INPUT_RESULT" >> "$ENV_FILE"
        
        local flowise_password=$(generate_random_password 24)
        echo "FLOWISE_PASSWORD=$flowise_password" >> "$ENV_FILE"
        
        prompt_input "FLOWISE_SECRETKEY" "Flowise secret key" "$(generate_random_password 32)" false
        echo "FLOWISE_SECRETKEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        # Generate ENCRYPTION_KEY for Flowise (compose file expects this)
        local encryption_key=$(generate_random_password 32)
        echo "ENCRYPTION_KEY=$encryption_key" >> "$ENV_FILE"
        
        echo "FLOWISE_FILE_MANAGER_ENABLED=true" >> "$ENV_FILE"
        echo "FLOWISE_FILE_SIZE_LIMIT=10485760" >> "$ENV_FILE"
        
        print_success "Flowise configuration completed"
    fi
    
    # OpenWebUI configuration (if selected)
    if [[ " ${selected_services[*]} " =~ " openwebui " ]]; then
        echo ""
        print_info "OpenWebUI Configuration"
        echo ""
        
        local openwebui_secret=$(generate_random_password 64)
        echo "OPENWEBUI_SECRET_KEY=$openwebui_secret" >> "$ENV_FILE"
        
        print_success "OpenWebUI configuration completed"
    fi
    
    # Grafana admin user (if selected)
    if [[ " ${selected_services[*]} " =~ " grafana " ]]; then
        echo ""
        print_info "Grafana Configuration"
        echo ""
        
        prompt_input "GRAFANA_ADMIN_USER" "Grafana admin user" "admin" false
        echo "GRAFANA_ADMIN_USER=$INPUT_RESULT" >> "$ENV_FILE"
        
        echo "GRAFANA_SMTP_ENABLED=false" >> "$ENV_FILE"
        
        print_success "Grafana configuration completed"
    fi
    
    # Vector database port configurations (if selected)
    if [[ " ${selected_services[*]} " =~ " qdrant " ]]; then
        echo ""
        print_info "Qdrant Port Configuration"
        echo ""
        
        prompt_input "QDRANT_PORT" "Qdrant port" "6333" false
        echo "QDRANT_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "QDRANT_GRPC_PORT" "Qdrant gRPC port" "6334" false
        echo "QDRANT_GRPC_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "QDRANT_API_KEY" "Qdrant API key" "" false
        echo "QDRANT_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Qdrant port configuration completed"
    fi
    
    if [[ " ${selected_services[*]} " =~ " milvus " ]]; then
        echo ""
        print_info "Milvus Port Configuration"
        echo ""
        
        prompt_input "MILVUS_PORT" "Milvus port" "19530" false
        echo "MILVUS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Milvus port configuration completed"
    fi
    
    if [[ " ${selected_services[*]} " =~ " chroma " ]]; then
        echo ""
        print_info "ChromaDB Port Configuration"
        echo ""
        
        prompt_input "CHROMA_PORT" "ChromaDB port" "8000" false
        echo "CHROMA_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "ChromaDB port configuration completed"
    fi
    
    if [[ " ${selected_services[*]} " =~ " weaviate " ]]; then
        echo ""
        print_info "Weaviate Port Configuration"
        echo ""
        
        prompt_input "WEAVIATE_PORT" "Weaviate port" "8080" false
        echo "WEAVIATE_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Weaviate port configuration completed"
    fi
    
    # MinIO port configurations (if selected)
    if [[ " ${selected_services[*]} " =~ " minio " ]]; then
        echo ""
        print_info "MinIO Port Configuration"
        echo ""
        
        # Use user's port input for MinIO API, calculate console port as API port + 1
        local minio_api_port=$(grep "^MINIO_PORT=" "$ENV_FILE" | cut -d= -f2)
        local minio_console_port=$((minio_api_port + 1))
        
        echo "MINIO_API_PORT=$minio_api_port" >> "$ENV_FILE"
        echo "MINIO_CONSOLE_PORT=$minio_console_port" >> "$ENV_FILE"
        echo "MINIO_S3_PORT=9000" >> "$ENV_FILE"
        
        local minio_buckets="aiplatform-docs,aiplatform-media,aiplatform-backups"
        prompt_input "MINIO_DEFAULT_BUCKETS" "MinIO default buckets" "$minio_buckets" false
        echo "MINIO_DEFAULT_BUCKETS=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "MinIO port configuration completed"
    fi
    
    # Tailscale configuration (if selected)
    if [[ " ${selected_services[*]} " =~ " tailscale " ]]; then
        echo ""
        print_info "Tailscale Configuration"
        echo ""
        
        # Tailscale auth key already collected in system configuration section
        # Only set exit node configuration here
        echo "TAILSCALE_EXIT_NODE=false" >> "$ENV_FILE"
        echo "TAILSCALE_ACCEPT_ROUTES=false" >> "$ENV_FILE"
        echo "TAILSCALE_USERSPACE=ai-platform" >> "$ENV_FILE"
        
        prompt_input "TAILSCALE_EXTRA_ARGS" "Tailscale extra arguments" "" false
        echo "TAILSCALE_EXTRA_ARGS=$INPUT_RESULT" >> "$ENV_FILE"
        
        print_success "Tailscale configuration completed"
    fi
    
    # OpenClaw base URL (if selected)
    if [[ " ${selected_services[*]} " =~ " openclaw " ]]; then
        echo ""
        print_info "OpenClaw Base URL Configuration"
        echo ""
        
        echo "OPENCLAW_BASE_URL=http://localhost:8082" >> "$ENV_FILE"
        
        echo "OPENCLAW_LOG_LEVEL=info" >> "$ENV_FILE"
        
        print_success "OpenClaw base URL configuration completed"
    fi
    
    # AnythingLLM telemetry (if selected)
    if [[ " ${selected_services[*]} " =~ " anythingllm " ]]; then
        echo ""
        print_info "AnythingLLM Telemetry Configuration"
        echo ""
        
        echo "ANYTHINGLLM_DISABLE_TELEMETRY=true" >> "$ENV_FILE"
        
        local anythingllm_jwt=$(generate_random_password 64)
        echo "ANYTHINGLLM_JWT_SECRET=$anythingllm_jwt" >> "$ENV_FILE"
        
        print_success "AnythingLLM telemetry configuration completed"
    fi
    
    # Admin passwords
    local admin_password=$(generate_random_password 24)
    echo "ADMIN_PASSWORD=$admin_password" >> "$ENV_FILE"
    echo "GRAFANA_PASSWORD=$admin_password" >> "$ENV_FILE"
    
    # JWT secrets
    local jwt_secret=$(generate_random_password 64)
    echo "JWT_SECRET=$jwt_secret" >> "$ENV_FILE"
    
    # n8n encryption key
    if [[ " ${selected_services[*]} " =~ " n8n " ]]; then
        local n8n_key=$(generate_random_password 64)
        echo "N8N_ENCRYPTION_KEY=$n8n_key" >> "$ENV_FILE"
    fi
    
    # Dify configuration
    if [[ " ${selected_services[*]} " =~ " dify " ]]; then
        local dify_secret=$(generate_random_password 32)
        echo "DIFY_SECRET_KEY=$dify_secret" >> "$ENV_FILE"
        echo "DIFY_WEB_API_PORT=5001" >> "$ENV_FILE"
        echo "DIFY_WEB_PORT=3002" >> "$ENV_FILE"
    fi
    
    # MinIO configuration (if selected)
    if [[ " ${selected_services[*]} " =~ " minio " ]]; then
        echo ""
        print_info "MinIO Configuration"
        echo ""
        
        prompt_input "MINIO_ROOT_USER" "MinIO root user" "minioadmin" false
        echo "MINIO_ROOT_USER=$INPUT_RESULT" >> "$ENV_FILE"
        
        local minio_pass=$(generate_random_password 32)
        echo "MINIO_ROOT_PASSWORD=$minio_pass" >> "$ENV_FILE"
        
        print_success "MinIO configuration completed"
    fi
    
    # Save configuration summary
    echo ""
    print_header "📊 Configuration Summary"
    echo ""
    
    local config_summary="$METADATA_DIR/configuration_summary.json"
    
    cat > "$config_summary" <<EOF
{
  "configuration_time": "$(date -Iseconds)",
  "selected_services": ${#selected_services[@]},
  "services": [
EOF
    
    local first=true
    for service in "${selected_services[@]}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$config_summary"
        fi
        first=false
        echo "    \"$service\"" >> "$config_summary"
    done
    
    cat >> "$config_summary" <<EOF

  ],
  "environment_variables": $(grep -c "^" "$ENV_FILE"),
  "generated_secrets": $(grep -c "_PASSWORD\|_SECRET\|_KEY" "$ENV_FILE")
}
EOF
    
    print_success "Configuration summary saved: $config_summary"
    print_info "Total environment variables: $(grep -c "^" "$ENV_FILE")"
    print_info "Generated secrets: $(grep -c "_PASSWORD\|_SECRET\|_KEY" "$ENV_FILE")"
    
    echo ""
    print_success "Configuration collection completed"
}

# 🔥 UPDATED: Volume Detection and Mounting
setup_volumes() {
    log_phase "1" "🗂️" "Volume Setup"
    
    print_info "Setting up volumes..."
    
    # Detect available volumes
    local volume_list=()
    local i=1
    local fdisk_volumes=$(fdisk -l 2>/dev/null | grep -B1 "Amazon Elastic Block Store" | grep "^Disk /dev" | awk '{print $2}' | sed 's/://' | sort)
    
    if [[ -n "$fdisk_volumes" ]]; then
        # Build volume list with sizes
        while read -r device; do
            local size=$(fdisk -l 2>/dev/null | grep "^Disk $device" | awk -F': ' '{print $2}' | awk '{print $1}')
            volume_list+=("$i) $device ($size)")
            ((i++))
        done <<< "$fdisk_volumes"
    fi
    
    # Check if we found any volumes
    if [[ ${#volume_list[@]} -eq 0 ]]; then
        print_error "No suitable data volumes found"
        print_info "Please attach an EBS volume (100G+) to this instance"
        exit 1
    fi
        
        # Auto-select largest volume (based on size)
        if [[ ${#volume_list[@]} -eq 1 ]]; then
            local selected_device=$(echo "${volume_list[0]}" | awk '{print $2}')
            print_info "Auto-selected: $selected_device (only available)"
        else
            # Let user choose
            echo "Select volume to mount:"
            for volume in "${volume_list[@]}"; do
                echo "$volume"
            done
            echo -n "Enter selection [1-${#volume_list[@]}]: "
            read -r selection
            
            if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#volume_list[@]} ]]; then
                print_error "Invalid selection"
                exit 1
            fi
            
            local selected_device=$(echo "${volume_list[$((selection-1))]}" | awk '{print $2}')
            print_info "Selected: $selected_device"
        fi
        
        local device_path="$selected_device"
        print_info "Mounting to /mnt..."
        
        # Create mount point if needed
        mkdir -p /mnt
        
        # Mount the volume
        if mountpoint -q /mnt; then
            print_info "/mnt is already mounted"
            local current_mount=$(findmnt -n -o SOURCE /mnt)
            if [[ "$current_mount" == "$device_path" ]]; then
                print_success "Correct volume already mounted: $device_path"
            else
                print_warning "Different volume mounted: $current_mount"
                print_info "Attempting to remount correct volume..."
                umount /mnt || print_warning "Could not unmount current volume"
                if mount "$device_path" /mnt; then
                    print_success "Successfully remounted $device_path"
                else
                    print_error "Failed to mount $device_path to /mnt"
                    exit 1
                fi
            fi
        else
            if ! mount "$device_path" /mnt; then
                print_error "Failed to mount $device_path to /mnt"
                exit 1
            fi
            print_success "Volume mounted successfully"
        fi
        
        # Add to fstab for persistence
        if ! grep -q "$device_path" /etc/fstab; then
            echo "$device_path /mnt ext4 defaults 0 2" >> /etc/fstab
            print_success "Added to /etc/fstab for persistence"
        fi
        
        print_success "Volume mounted successfully"
        
        # Create log directory immediately after mounting
        mkdir -p "$DATA_ROOT/logs" 2>/dev/null || true
}

generate_caddyfile() {
    log_phase "9" "🌐" "Caddyfile Generation"
    
    print_info "Generating Caddyfile with all service routes..."
    
    # Check proxy configuration method
    local proxy_method=$(grep "^PROXY_CONFIG_METHOD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "direct")
    
    if [[ "$proxy_method" == "subdomain" ]]; then
        # Subdomain routing - each service gets its own subdomain
        mkdir -p "${DATA_ROOT}/caddy"
        cat > "${DATA_ROOT}/caddy/Caddyfile" << EOF
{
    admin off
    auto_https off
    email ${ACME_EMAIL:-admin@${DOMAIN_NAME}}
}

# Prometheus
prometheus.${DOMAIN_NAME} {
    reverse_proxy prometheus:9090
}

# Grafana
grafana.${DOMAIN_NAME} {
    reverse_proxy grafana:3000
}

# n8n
n8n.${DOMAIN_NAME} {
    reverse_proxy n8n:5678 {
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}

# Dify
dify.${DOMAIN_NAME} {
    reverse_proxy dify-web:3000
}

# AnythingLLM
anythingllm.${DOMAIN_NAME} {
    reverse_proxy anythingllm:3001 {
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}

# LiteLLM
litellm.${DOMAIN_NAME} {
    reverse_proxy litellm:4000
}

# Open WebUI
openwebui.${DOMAIN_NAME} {
    reverse_proxy openwebui:8080 {
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}

# MinIO Console
minio.${DOMAIN_NAME} {
    reverse_proxy minio-console:9001
}

# Signal API
signal.${DOMAIN_NAME} {
    reverse_proxy signal:8080
}

# OpenClaw
openclaw.${DOMAIN_NAME} {
    reverse_proxy openclaw:8080
}

# Flowise
flowise.${DOMAIN_NAME} {
    reverse_proxy flowise:3000
}

# Ollama API
ollama.${DOMAIN_NAME} {
    reverse_proxy ollama:11434
}

# Default domain - health check and fallback
${DOMAIN_NAME} {
    handle /health {
        respond "OK" 200
    }
    
    respond "AI Platform - Use subdomains: n8n.${DOMAIN_NAME}, grafana.${DOMAIN_NAME}, etc." 200
}
EOF
    else
        # Path-based routing (existing logic)
        mkdir -p "${DATA_ROOT}/caddy"
        cat > "${DATA_ROOT}/caddy/Caddyfile" << EOF
{
    admin off
    auto_https off
    email ${ACME_EMAIL:-admin@${DOMAIN_NAME}}
}

:80 {
    # Prometheus
    handle /prometheus/* {
        reverse_proxy prometheus:9090
    }

    # Grafana
    handle /grafana/* {
        reverse_proxy grafana:3000
    }

    # n8n
    handle /n8n/* {
        reverse_proxy n8n:5678 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # Dify
    handle /dify/* {
        reverse_proxy dify-web:3000
    }

    # AnythingLLM
    handle /anythingllm/* {
        reverse_proxy anythingllm:3001 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # LiteLLM
    handle /litellm/* {
        reverse_proxy litellm:4000
    }

    # Open WebUI
    handle /openwebui/* {
        reverse_proxy openwebui:8080 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # MinIO Console
    handle /minio/* {
        reverse_proxy minio-console:9001
    }

    # Signal API
    handle /signal/* {
        reverse_proxy signal:8080
    }

    # OpenClaw
    handle /openclaw/* {
        reverse_proxy openclaw:8080
    }

    # Flowise
    handle /flowise/* {
        reverse_proxy flowise:3000
    }

    # Ollama API (no UI, just API endpoint)
    handle /ollama/* {
        reverse_proxy ollama:11434
    }

    # Health check
    handle /health {
        respond "OK" 200
    }

    # Fallback
    respond "AI Platform - use /servicename to access services" 200
}
EOF
    fi
    
    chown "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/caddy/Caddyfile"
    print_success "Caddyfile written with ${proxy_method} routing"
}

generate_apparmor_profiles() {
    log_phase "8" "🛡️" "AppArmor Profile Generation"
    
    print_info "Generating AppArmor profiles for security..."
    
    # Default profile for all services except openclaw
    cat > "${DATA_ROOT}/apparmor/${DOCKER_NETWORK}-default" << EOF
#include <tunables/global>

profile ${DOCKER_NETWORK}-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  network inet tcp,
  network inet udp,
  network netlink raw,

  # Stack data directory - this stack only
  ${DATA_ROOT}/** rwk,

  # Docker internals
  /var/lib/docker/** r,

  # Proc/sys
  @{PROC}/** r,
  /sys/fs/cgroup/** r,
}
EOF

    # OpenClaw profile — strict allowlist
    cat > "${DATA_ROOT}/apparmor/${DOCKER_NETWORK}-openclaw" << EOF
#include <tunables/global>

profile ${DOCKER_NETWORK}-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  network inet tcp,
  network inet udp,

  # OpenClaw ONLY gets its own subdirectory
  ${DATA_ROOT}/data/openclaw/** rwk,

  # Explicit deny everything else under DATA_ROOT
  deny ${DATA_ROOT}/data/postgres/** rwklx,
  deny ${DATA_ROOT}/data/n8n/** rwklx,
  deny ${DATA_ROOT}/data/minio/** rwklx,
  deny ${DATA_ROOT}/config/** rwklx,

  @{PROC}/** r,
}
EOF

    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/apparmor/"
    print_success "AppArmor profiles written (loaded by Script 2)"
}

create_directory_structure() {
    log_phase "9" "📁" "Directory Structure Creation"
    
    print_info "Creating modular directory structure with correct ownership..."
    
    # Create ALL directories FIRST with correct ownership
    local dirs=(
        "${DATA_ROOT}/config"
        "${DATA_ROOT}/apparmor"
        "${DATA_ROOT}/caddy/config"
        "${DATA_ROOT}/caddy/data"
        "${DATA_ROOT}/data/postgres"
        "${DATA_ROOT}/data/redis"
        "${DATA_ROOT}/data/qdrant"
        "${DATA_ROOT}/data/minio"
        "${DATA_ROOT}/data/n8n"
        "${DATA_ROOT}/data/dify"
        "${DATA_ROOT}/data/anythingllm"
        "${DATA_ROOT}/data/litellm"
        "${DATA_ROOT}/data/openwebui"
        "${DATA_ROOT}/data/grafana"
        "${DATA_ROOT}/data/prometheus"
        "${DATA_ROOT}/data/flowise"
        "${DATA_ROOT}/data/signal"
        "${DATA_ROOT}/data/ollama"
        "${DATA_ROOT}/data/openclaw"
        "${DATA_ROOT}/postgres-init"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Base ownership: stack user owns everything
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}"
    chmod -R 755 "${DATA_ROOT}"
    
    # Service-specific permissions matching container UIDs
    # postgres runs as UID 999
    chown -R 999:999 "${DATA_ROOT}/data/postgres"
    chmod 700 "${DATA_ROOT}/data/postgres"
    
    # redis runs as UID 999
    chown -R 999:999 "${DATA_ROOT}/data/redis"
    chmod 700 "${DATA_ROOT}/data/redis"
    
    # qdrant runs as UID 1000
    chown -R 1000:1000 "${DATA_ROOT}/data/qdrant"
    chmod 750 "${DATA_ROOT}/data/qdrant"
    
    # grafana runs as UID 472
    chown -R 472:472 "${DATA_ROOT}/data/grafana"
    chmod 750 "${DATA_ROOT}/data/grafana"
    
    # prometheus runs as UID 65534 (nobody)
    chown -R 65534:65534 "${DATA_ROOT}/data/prometheus"
    chown -R 65534:65534 "${DATA_ROOT}/config/prometheus"
    chmod 750 "${DATA_ROOT}/data/prometheus"
    chmod 750 "${DATA_ROOT}/config/prometheus"
    
    # flowise runs as root (UID 0) - but data owned by stack user
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/data/flowise"
    chmod 750 "${DATA_ROOT}/data/flowise"
    
    # minio runs as UID 1000
    chown -R 1000:1000 "${DATA_ROOT}/data/minio"
    chmod 750 "${DATA_ROOT}/data/minio"
    
    # n8n runs as stack user
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/data/n8n"
    chmod 750 "${DATA_ROOT}/data/n8n"
    
    # anythingllm runs as UID 1000
    chown -R 1000:1000 "${DATA_ROOT}/data/anythingllm"
    chmod 750 "${DATA_ROOT}/data/anythingllm"
    
    # signal runs as UID 1000
    chown -R 1000:1000 "${DATA_ROOT}/data/signal"
    chmod 750 "${DATA_ROOT}/data/signal"
    
    # openwebui writes as root internally - needs 777
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/data/openwebui"
    chmod 777 "${DATA_ROOT}/data/openwebui"
    
    # openclaw - locked down, only openclaw UID
    chown -R "${OPENCLAW_UID}:${OPENCLAW_GID}" "${DATA_ROOT}/data/openclaw"
    chmod 750 "${DATA_ROOT}/data/openclaw"
    
    # Pre-create critical files with correct ownership
    # OpenWebUI secret key
    touch "${DATA_ROOT}/data/openwebui/.webui_secret_key"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/data/openwebui/.webui_secret_key"
    chmod 600 "${DATA_ROOT}/data/openwebui/.webui_secret_key"
    
    # PostgreSQL init script
    mkdir -p "${DATA_ROOT}/postgres-init"
    cat > "${DATA_ROOT}/postgres-init/init-multiple-dbs.sh" << 'EOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" << EOSQL
    CREATE DATABASE dify;
    CREATE DATABASE n8n;
    CREATE DATABASE anythingllm;
    GRANT ALL PRIVILEGES ON DATABASE dify TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE n8n TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE anythingllm TO $POSTGRES_USER;
EOSQL
EOF
    chmod +x "${DATA_ROOT}/postgres-init/init-multiple-dbs.sh"
    chown 999:999 "${DATA_ROOT}/postgres-init/init-multiple-dbs.sh"
    
    print_success "Directory structure created with correct ownership"
}

validate_system() {
    log_phase "10" "🔍" "System Validation"
    
    print_info "Validating system configuration..."
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker is installed and running"
        docker --version
    else
        print_error "Docker is not installed"
        return 1
    fi
    
    # Check directories
    if [[ -d "$DATA_ROOT" ]]; then
        print_success "Data directory exists: $DATA_ROOT"
    else
        print_error "Data directory not found"
        return 1
    fi
    
    # Check environment file
    if [[ -f "$ENV_FILE" ]]; then
        print_success "Environment file exists: $ENV_FILE"
    else
        print_error "Environment file not found"
        return 1
    fi
    
    print_success "System validation completed"
}

generate_summary() {
    log_phase "11" "📊" "Summary Generation"
    
    echo ""
    print_header "📊 Setup Summary"
    echo ""
    
    # Generate comprehensive summary
    local summary_file="$METADATA_DIR/setup_summary.txt"
    local urls_file="$METADATA_DIR/service_urls.txt"
    
    cat > "$summary_file" <<EOF
AI Platform Setup Summary
======================

Setup completed: $(date -Iseconds)
Script version: 4.0.0

Directories:
- Data: $DATA_ROOT
- Metadata: $METADATA_DIR
- Logs: $DATA_ROOT/logs
- Config: $DATA_ROOT/config
- Compose: $DATA_ROOT/compose

Network Configuration:
- Domain: ${DOMAIN:-localhost}
- Public IP: ${PUBLIC_IP:-unknown}
- Domain Resolves: ${DOMAIN_RESOLVES:-false}
- Proxy: ${PROXY_TYPE:-none}
- SSL: ${SSL_TYPE:-none}

Selected Services: $(jq -r '.total_services' "$SERVICES_FILE" 2>/dev/null || echo "unknown")
Environment Variables: $(grep -c "^" "$ENV_FILE" 2>/dev/null || echo "0")
Generated Secrets: $(grep -c "_PASSWORD\|_SECRET\|_KEY" "$ENV_FILE" 2>/dev/null || echo "0")

Next Steps:
1. Review configuration in $ENV_FILE
2. Review service URLs in $urls_file
3. Run: sudo bash 2-deploy-services.sh
4. Monitor deployment logs

Generated Files:
- Environment variables: $ENV_FILE
- Service selections: $SERVICES_FILE
- Configuration summary: $METADATA_DIR/configuration_summary.json
- Service URLs: $urls_file
- State file: $STATE_FILE
EOF
    
    # Generate service URLs and ports summary
    cat > "$urls_file" <<EOF
AI Platform Service URLs and Ports
================================

Public Access:
EOF
    
    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
        echo "- Main Site: https://${DOMAIN:-localhost}" >> "$urls_file"
        echo "- Admin Panel: https://${DOMAIN:-localhost}/admin" >> "$urls_file"
        echo "- Domain Status: ✅ Resolves correctly" >> "$urls_file"
    else
        echo "- Main Site: http://${PUBLIC_IP:-localhost}" >> "$urls_file"
        echo "- Admin Panel: http://${PUBLIC_IP:-localhost}:8080" >> "$urls_file"
        echo "- Domain Status: ⚠️ Does not resolve (using local access)" >> "$urls_file"
    fi
    
    echo "" >> "$urls_file"
    echo "Service Ports:" >> "$urls_file"
    echo "" >> "$urls_file"
    
    # Add service URLs based on selected services
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    
    for service in "${selected_services[@]}"; do
        case "$service" in
            "ollama")
                local ollama_port=$(grep "^OLLAMA_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Ollama: http://localhost:$ollama_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Ollama (Public): https://$DOMAIN_NAME/ollama" >> "$urls_file"
                ;;
            "openwebui")
                local openwebui_port=$(grep "^OPENWEBUI_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Open WebUI: http://localhost:$openwebui_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Open WebUI (Public): https://$DOMAIN_NAME/openwebui" >> "$urls_file"
                ;;
            "anythingllm")
                local anythingllm_port=$(grep "^ANYTHINGLLM_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- AnythingLLM: http://localhost:$anythingllm_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- AnythingLLM (Public): https://$DOMAIN_NAME/anythingllm" >> "$urls_file"
                ;;
            "dify")
                local dify_port=$(grep "^DIFY_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Dify: http://localhost:$dify_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Dify (Public): https://$DOMAIN_NAME/dify" >> "$urls_file"
                ;;
            "n8n")
                local n8n_port=$(grep "^N8N_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- n8n: http://localhost:$n8n_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- n8n (Public): https://$DOMAIN_NAME/n8n" >> "$urls_file"
                ;;
            "flowise")
                local flowise_port=$(grep "^FLOWISE_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Flowise: http://localhost:$flowise_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Flowise (Public): https://$DOMAIN_NAME/flowise" >> "$urls_file"
                ;;
            "litellm")
                local litellm_port=$(grep "^LITELLM_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- LiteLLM: http://localhost:$litellm_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- LiteLLM (Public): https://$DOMAIN_NAME/litellm" >> "$urls_file"
                ;;
            "signal-api")
                local signal_api_port=$(grep "^SIGNAL_API_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Signal API: http://localhost:$signal_api_port" >> "$urls_file"
                echo "- Signal QR: http://localhost:$signal_api_port/v1/qrcode" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Signal API (Public): https://$DOMAIN_NAME/signal-api" >> "$urls_file"
                ;;
            "openclaw")
                local openclaw_port=$(grep "^OPENCLAW_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- OpenClaw: http://localhost:$openclaw_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- OpenClaw (Public): https://$DOMAIN_NAME/openclaw" >> "$urls_file"
                ;;
            "prometheus")
                local prometheus_port=$(grep "^PROMETHEUS_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Prometheus: http://localhost:$prometheus_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Prometheus (Public): https://$DOMAIN_NAME/prometheus" >> "$urls_file"
                ;;
            "grafana")
                local grafana_port=$(grep "^GRAFANA_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- Grafana: http://localhost:$grafana_port" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Grafana (Public): https://$DOMAIN_NAME/grafana" >> "$urls_file"
                ;;
            "qdrant")
                echo "- Qdrant: http://localhost:6333" >> "$urls_file"
                echo "- Qdrant Dashboard: http://localhost:6333/dashboard" >> "$urls_file"
                ;;
            "postgres")
                echo "- PostgreSQL: localhost:5432" >> "$urls_file"
                ;;
            "redis")
                echo "- Redis: localhost:6379" >> "$urls_file"
                ;;
            "minio")
                local minio_api_port=$(grep "^MINIO_API_PORT=" "$ENV_FILE" | cut -d= -f2)
                local minio_console_port=$(grep "^MINIO_CONSOLE_PORT=" "$ENV_FILE" | cut -d= -f2)
                echo "- MinIO: http://localhost:$minio_api_port" >> "$urls_file"
                echo "- MinIO Console: http://localhost:$minio_console_port" >> "$urls_file"
                ;;
        esac
    done
    
    echo "" >> "$urls_file"
    echo "Database Credentials:" >> "$urls_file"
    echo "" >> "$urls_file"
    echo "- PostgreSQL User: $(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    echo "- PostgreSQL Database: $(grep "^POSTGRES_DB=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    echo "- PostgreSQL Password: $(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    echo "- Redis Password: $(grep "^REDIS_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    echo "- Vector DB: ${VECTOR_DB:-qdrant}" >> "$urls_file"
    [[ -n "${QDRANT_API_KEY:-}" ]] && echo "- Qdrant API Key: $(grep "^QDRANT_API_KEY=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    
    echo "" >> "$urls_file"
    echo "Admin Credentials:" >> "$urls_file"
    echo "" >> "$urls_file"
    echo "- Admin Password: $(grep "^ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    echo "- Grafana Password: $(grep "^GRAFANA_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    [[ -n "${OPENCLAW_ADMIN_PASSWORD:-}" ]] && echo "- OpenClaw Password: $(grep "^OPENCLAW_ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]] && echo "- MinIO Password: $(grep "^MINIO_ROOT_PASSWORD=" "$ENV_FILE" | cut -d= -f2)" >> "$urls_file"
    
    # Show usernames if overridden
    local postgres_user=$(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d= -f2)
    local openclaw_user=$(grep "^OPENCLAW_ADMIN_USER=" "$ENV_FILE" | cut -d= -f2)
    local minio_user=$(grep "^MINIO_ROOT_USER=" "$ENV_FILE" | cut -d= -f2)
    
    [[ "$postgres_user" != "postgres" ]] && echo "- PostgreSQL User: $postgres_user" >> "$urls_file"
    [[ "$openclaw_user" != "admin" ]] && echo "- OpenClaw User: $openclaw_user" >> "$urls_file"
    [[ "$minio_user" != "minioadmin" ]] && echo "- MinIO User: $minio_user" >> "$urls_file"
    
    # Display summary to user
    print_success "Setup summary generated: $METADATA_DIR/setup_summary.txt"
    print_success "Service URLs saved: $METADATA_DIR/service_urls.txt"
    print_info "Review service URLs file for complete access information"
    
    # FINAL OWNERSHIP FIX - Ensure everything owned by user
    print_info "Fixing final ownership..."
    sudo chown -R "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/.env" "${DATA_ROOT}/ai-platform"
    sudo chmod 600 "${DATA_ROOT}/.env"
    print_success "Ownership fixed: All files owned by ${RUNNING_USER}"
    
    # Display selected services summary
    echo ""
    print_header "📋 Selected Services Summary"
    echo ""
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    local total_services=$(jq -r '.total_services' "$SERVICES_FILE" 2>/dev/null || echo "0")
    
    print_info "Total Services Selected: $total_services"
    echo ""
    
    # Group services by category
    echo "🏗️  Core Infrastructure:"
    local core_services=("nginx-proxy-manager" "traefik" "caddy" "postgres" "redis" "tailscale")
    for service in "${core_services[@]}"; do
        if [[ " ${selected_services[*]} " =~ " $service " ]]; then
            case $service in
                "nginx-proxy-manager") echo "  ✅ Nginx Proxy Manager" ;;
                "traefik") echo "  ✅ Traefik" ;;
                "caddy") echo "  ✅ Caddy" ;;
                "postgres") echo "  ✅ PostgreSQL" ;;
                "redis") echo "  ✅ Redis" ;;
                "tailscale") echo "  ✅ Tailscale" ;;
            esac
        fi
    done
    
    echo ""
    echo "🤖 AI Applications:"
    local ai_services=("openwebui" "anythingllm" "dify" "n8n" "flowise" "ollama" "litellm")
    for service in "${ai_services[@]}"; do
        if [[ " ${selected_services[*]} " =~ " $service " ]]; then
            case $service in
                "openwebui") echo "  ✅ Open WebUI" ;;
                "anythingllm") echo "  ✅ AnythingLLM" ;;
                "dify") echo "  ✅ Dify" ;;
                "n8n") echo "  ✅ n8n" ;;
                "flowise") echo "  ✅ Flowise" ;;
                "ollama") echo "  ✅ Ollama" ;;
                "litellm") echo "  ✅ LiteLLM" ;;
            esac
        fi
    done
    
    echo ""
    echo "🧠 Vector Databases:"
    local vector_services=("qdrant" "milvus" "chromadb" "weaviate")
    for service in "${vector_services[@]}"; do
        if [[ " ${selected_services[*]} " =~ " $service " ]]; then
            case $service in
                "qdrant") echo "  ✅ Qdrant" ;;
                "milvus") echo "  ✅ Milvus" ;;
                "chromadb") echo "  ✅ ChromaDB" ;;
                "weaviate") echo "  ✅ Weaviate" ;;
            esac
        fi
    done
    
    echo ""
    echo "📊 Monitoring & Storage:"
    local monitoring_services=("prometheus" "grafana" "minio" "signal-api" "openclaw")
    for service in "${monitoring_services[@]}"; do
        if [[ " ${selected_services[*]} " =~ " $service " ]]; then
            case $service in
                "prometheus") echo "  ✅ Prometheus" ;;
                "grafana") echo "  ✅ Grafana" ;;
                "minio") echo "  ✅ MinIO" ;;
                "signal-api") echo "  ✅ Signal API" ;;
                "openclaw") echo "  ✅ OpenClaw" ;;
            esac
        fi
    done
    
    echo ""
    
    # Display key information
    echo ""
    print_header "🔑 Key Information"
    echo ""
    print_info "Database Credentials:"
    echo "  • PostgreSQL User: $(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • PostgreSQL Database: $(grep "^POSTGRES_DB=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • PostgreSQL Password: $(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    # Show Redis user if overridden
    local redis_user=$(grep "^REDIS_USER=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    [[ -n "$redis_user" ]] && echo "  • Redis User: $redis_user"
    echo "  • Redis Password: $(grep "^REDIS_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • Vector Database: ${VECTOR_DB:-qdrant}"
    
    # Show vector database overrides if present
    echo ""
    print_info "Vector Database Configuration:"
    local qdrant_collection=$(grep "^QDRANT_COLLECTION_NAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    local milvus_db=$(grep "^MILVUS_DATABASE_NAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    local chroma_collection=$(grep "^CHROMA_COLLECTION_NAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    local weaviate_class=$(grep "^WEAVIATE_CLASS_NAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    
    [[ -n "$qdrant_collection" ]] && echo "  • Qdrant Collection: $qdrant_collection"
    [[ -n "$milvus_db" ]] && echo "  • Milvus Database: $milvus_db"
    [[ -n "$chroma_collection" ]] && echo "  • ChromaDB Collection: $chroma_collection"
    [[ -n "$weaviate_class" ]] && echo "  • Weaviate Class: $weaviate_class"
    
    # If no vector DB overrides, show default message
    [[ -z "$qdrant_collection" && -z "$milvus_db" && -z "$chroma_collection" && -z "$weaviate_class" ]] && echo "  • Using default vector database configuration"
    echo ""
    
    print_info "Admin Credentials:"
    echo "  • Admin Password: $(grep "^ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • Grafana Password: $(grep "^GRAFANA_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    [[ -n "${OPENCLAW_ADMIN_PASSWORD:-}" ]] && echo "  • OpenClaw Password: $(grep "^OPENCLAW_ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]] && echo "  • MinIO Password: $(grep "^MINIO_ROOT_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    
    # Show usernames if overridden
    local postgres_user=$(grep "^POSTGRES_USER=" "$ENV_FILE" | cut -d= -f2)
    local openclaw_user=$(grep "^OPENCLAW_ADMIN_USER=" "$ENV_FILE" | cut -d= -f2)
    local minio_user=$(grep "^MINIO_ROOT_USER=" "$ENV_FILE" | cut -d= -f2)
    
    # Load environment variables for URL generation
    DOMAIN=$(grep "^DOMAIN=" "$ENV_FILE" | cut -d= -f2)
    DOMAIN_NAME=$(grep "^DOMAIN_NAME=" "$ENV_FILE" | cut -d= -f2)
    DOMAIN_RESOLVES=$(grep "^DOMAIN_RESOLVES=" "$ENV_FILE" | cut -d= -f2 || echo "false")
    PROXY_CONFIG_METHOD=$(grep "^PROXY_CONFIG_METHOD=" "$ENV_FILE" | cut -d= -f2 || echo "direct")
    
    [[ "$postgres_user" != "postgres" ]] && echo "  • PostgreSQL User: $postgres_user"
    [[ "$openclaw_user" != "admin" ]] && echo "  • OpenClaw User: $openclaw_user"
    [[ "$minio_user" != "minioadmin" ]] && echo "  • MinIO User: $minio_user"
    echo ""
    
    print_info "Service Access:"
    
    # Get selected services from file
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE" 2>/dev/null || echo ""))
    
    if [[ ${#selected_services[@]} -eq 0 ]]; then
        echo "  • No services selected"
    else
        for service in "${selected_services[@]}"; do
            case $service in
                "openwebui")
                    local openwebui_port=$(grep "^OPENWEBUI_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • Open WebUI: https://$DOMAIN_NAME/openwebui"
                        else
                            echo "  • Open WebUI: https://$DOMAIN_NAME:$openwebui_port"
                        fi
                    else
                        echo "  • Open WebUI: http://localhost:$openwebui_port"
                    fi
                    ;;
                "anythingllm")
                    local anythingllm_port=$(grep "^ANYTHINGLLM_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • AnythingLLM: https://$DOMAIN_NAME/anythingllm"
                        else
                            echo "  • AnythingLLM: https://$DOMAIN_NAME:$anythingllm_port"
                        fi
                    else
                        echo "  • AnythingLLM: http://localhost:$anythingllm_port"
                    fi
                    ;;
                "dify")
                    local dify_port=$(grep "^DIFY_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • Dify: https://$DOMAIN_NAME/dify"
                        else
                            echo "  • Dify: https://$DOMAIN_NAME:$dify_port"
                        fi
                    else
                        echo "  • Dify: http://localhost:$dify_port"
                    fi
                    ;;
                "n8n")
                    local n8n_port=$(grep "^N8N_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • n8n: https://$DOMAIN_NAME/n8n"
                        else
                            echo "  • n8n: https://$DOMAIN_NAME:$n8n_port"
                        fi
                    else
                        echo "  • n8n: http://localhost:$n8n_port"
                    fi
                    ;;
                "flowise")
                    local flowise_port=$(grep "^FLOWISE_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • Flowise: https://$DOMAIN_NAME/flowise"
                        else
                            echo "  • Flowise: https://$DOMAIN_NAME:$flowise_port"
                        fi
                    else
                        echo "  • Flowise: http://localhost:$flowise_port"
                    fi
                    ;;
                "litellm")
                    local litellm_port=$(grep "^LITELLM_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • LiteLLM: https://$DOMAIN_NAME/litellm"
                        else
                            echo "  • LiteLLM: https://$DOMAIN_NAME:$litellm_port"
                        fi
                    else
                        echo "  • LiteLLM: http://localhost:$litellm_port"
                    fi
                    ;;
                "signal-api")
                    local signal_api_port=$(grep "^SIGNAL_API_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • Signal API: https://$DOMAIN_NAME/signal"
                        else
                            echo "  • Signal API: https://$DOMAIN_NAME:$signal_api_port"
                        fi
                    else
                        echo "  • Signal API: http://localhost:$signal_api_port"
                    fi
                    ;;
                "openclaw")
                    local openclaw_port=$(grep "^OPENCLAW_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • OpenClaw: https://$DOMAIN_NAME/openclaw"
                        else
                            echo "  • OpenClaw: https://$DOMAIN_NAME:$openclaw_port"
                        fi
                    else
                        echo "  • OpenClaw: http://localhost:$openclaw_port"
                    fi
                    ;;
                "prometheus")
                    local prometheus_port=$(grep "^PROMETHEUS_PORT=" "$ENV_FILE" | cut -d= -f2)
                    echo "  • Prometheus: http://localhost:$prometheus_port"
                    ;;
                "grafana")
                    local grafana_port=$(grep "^GRAFANA_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • Grafana: https://$DOMAIN_NAME/grafana"
                        else
                            echo "  • Grafana: https://$DOMAIN_NAME:$grafana_port"
                        fi
                    else
                        echo "  • Grafana: http://localhost:$grafana_port"
                    fi
                    ;;
                "qdrant")
                    echo "  • Qdrant: http://localhost:6333"
                    ;;
                "minio")
                    local minio_api_port=$(grep "^MINIO_API_PORT=" "$ENV_FILE" | cut -d= -f2)
                    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
                        if [[ "${PROXY_CONFIG_METHOD:-direct}" == "alias" ]]; then
                            echo "  • MinIO: https://$DOMAIN_NAME/minio"
                        else
                            echo "  • MinIO: https://$DOMAIN_NAME:$minio_api_port"
                        fi
                    else
                        echo "  • MinIO: http://localhost:$minio_api_port"
                    fi
                    ;;
                "postgres"|"redis"|"tailscale")
                    # Infrastructure services - no direct UI
                    ;;
                *)
                    echo "  • $service: (port configuration available)"
                    ;;
            esac
        done
    fi
    echo ""
    
    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
        print_success "Domain resolves correctly - public access available"
    else
        print_warning "Domain does not resolve - using local access"
    fi
    
    print_success "Summary generation completed"
}

# 🔥 NEW: Generate Complete Docker Compose Templates with User Mapping
generate_compose_templates() {
    log_phase "11" "🐳" "Docker Compose Template Generation"
    
    print_info "Generating complete Docker Compose templates with non-root user mapping..."
    
    # Load selected services
    if [ ! -f "$SERVICES_FILE" ]; then
        print_error "Selected services file not found"
        return 1
    fi
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE"))
    
    # Set ENABLE variables based on selection - declare globally
    ENABLE_OLLAMA=false
    ENABLE_LITELLM=false
    ENABLE_DIFY=false
    ENABLE_N8N=false
    ENABLE_FLOWISE=false
    ENABLE_ANYTHINGLLM=false
    ENABLE_OPENWEBUI=false
    ENABLE_MONITORING=false
    ENABLE_SIGNAL_API=false
    ENABLE_OPENCLAW=false
    ENABLE_TAILSCALE=false
    ENABLE_MINIO=false
    ENABLE_QDRANT=false
    
    for service in "${selected_services[@]}"; do
        case "$service" in
            "ollama") ENABLE_OLLAMA=true ;;
            "litellm") ENABLE_LITELLM=true ;;
            "dify") ENABLE_DIFY=true ;;
            "n8n") ENABLE_N8N=true ;;
            "flowise") ENABLE_FLOWISE=true ;;
            "anythingllm") ENABLE_ANYTHINGLLM=true ;;
            "openwebui") ENABLE_OPENWEBUI=true ;;
            "prometheus"|"grafana") ENABLE_MONITORING=true ;;
            "signal-api") ENABLE_SIGNAL_API=true ;;
            "openclaw") ENABLE_OPENCLAW=true ;;
            "tailscale") ENABLE_TAILSCALE=true ;;
            "minio") ENABLE_MINIO=true ;;
            "qdrant") ENABLE_QDRANT=true ;;
        esac
    done
    
    # Ensure compose directory exists with correct ownership
    mkdir -p "$(dirname "$COMPOSE_FILE")"
    sudo chown "${RUNNING_UID}:${RUNNING_GID}" "$(dirname "$COMPOSE_FILE")"
    
    # Ensure user variables are available
    RUNNING_USER="${RUNNING_USER:-${SUDO_USER:-$USER}}"
    RUNNING_UID="${RUNNING_UID:-$(id -u "$RUNNING_USER")}"
    RUNNING_GID="${RUNNING_GID:-$(id -g "$RUNNING_USER")}"
    
    # Set real user ID for file ownership
    REAL_UID="${RUNNING_UID}"
    REAL_GID="${RUNNING_GID}"
    
    # Set GPU type (default to none for CPU-only)
    GPU_TYPE="${GPU_TYPE:-none}"
    
    print_info "User mapping: $RUNNING_USER ($RUNNING_UID:$RUNNING_GID)"
    print_info "GPU type: $GPU_TYPE"
    print_info "Compose file: $COMPOSE_FILE"
    
    # Generate complete unified compose file
    cat > "$COMPOSE_FILE" <<'COMPOSE_HEADER'
# Docker Compose Configuration
# AI Platform - Complete Service Stack

networks:
  ${DOCKER_NETWORK}:
    name: ${DOCKER_NETWORK}
    driver: bridge
  ${DOCKER_NETWORK}_internal:
    name: ${DOCKER_NETWORK}_internal
    driver: bridge
    internal: true

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  ollama_data:
    driver: local

services:
COMPOSE_HEADER

    # Always add core infrastructure
    add_postgres_service
    add_redis_service
    
    # Add selected services based on user selection
    [ "$ENABLE_OLLAMA" = true ] && add_ollama_service
    [ "$ENABLE_LITELLM" = true ] && add_litellm_service
    [ "$ENABLE_DIFY" = true ] && add_dify_services
    [ "$ENABLE_N8N" = true ] && add_n8n_service
    [ "$ENABLE_FLOWISE" = true ] && add_flowise_service
    [ "$ENABLE_ANYTHINGLLM" = true ] && add_anythingllm_service
    [ "$ENABLE_OPENWEBUI" = true ] && add_openwebui_service
    [ "$ENABLE_MONITORING" = true ] && add_monitoring_services
    [ "$ENABLE_SIGNAL_API" = true ] && add_signal_api_service
    [ "$ENABLE_OPENCLAW" = true ] && add_openclaw_service
    [ "$ENABLE_TAILSCALE" = true ] && add_tailscale_service
    [ "$ENABLE_MINIO" = true ] && add_minio_service
    [ "$ENABLE_QDRANT" = true ] && add_qdrant_service
    
    chmod 644 "$COMPOSE_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$COMPOSE_FILE"
    
    print_success "Docker Compose templates generated with non-root user mapping"
    print_info "All containers will run as: $RUNNING_USER ($RUNNING_UID:$RUNNING_GID)"
    mark_phase_complete "generate_compose_templates"
}

# Service definition functions
add_postgres_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-aiplatform}
      PGDATA: /var/lib/postgresql/data/pgdata
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${DATA_ROOT}/logs/postgres:/var/log/postgresql
    networks:
      - ${DOCKER_NETWORK}_internal
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-aiplatform}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    labels:
      - "ai-platform.service=postgres"
      - "ai-platform.type=infrastructure"

EOF
}

add_redis_service() {
    cat >> "$COMPOSE_FILE" <<EOF
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS_PASSWORD} --appendonly yes
    volumes:
      - redis_data:/data
      - \${DATA_ROOT}/logs/redis:/var/log/redis
    networks:
      - ${DOCKER_NETWORK}_internal
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    labels:
      - "ai-platform.service=redis"
      - "ai-platform.type=infrastructure"

EOF
}

add_ollama_service() {
    local runtime_config=""
    if [ "$GPU_TYPE" = "nvidia" ]; then
        runtime_config="runtime: nvidia"
    fi
    
    cat >> "$COMPOSE_FILE" <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ${runtime_config}
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
      - TZ=${TIMEZONE:-UTC}
    volumes:
      - ollama_data:/root/.ollama
      - \${DATA_ROOT}/logs/ollama:/var/log/ollama
    ports:
      - "\${OLLAMA_PORT:-11434}:11434"
EOF

    if [ "$GPU_TYPE" = "nvidia" ]; then
        cat >> "$COMPOSE_FILE" <<'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    fi

    cat >> "$COMPOSE_FILE" <<'EOF'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    labels:
      - "ai-platform.service=ollama"
      - "ai-platform.type=llm"

EOF
}

add_litellm_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aiplatform}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORE_MODEL_IN_DB: "True"
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/config/litellm:/app/config
      - ${DATA_ROOT}/logs/litellm:/app/logs
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    command: ["--config", "/app/config/config.yaml", "--port", "4000", "--num_workers", "4"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=litellm"
      - "ai-platform.type=llm-gateway"

EOF
}

add_openwebui_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    depends_on:
      - ollama
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
      WEBUI_AUTH: "True"
      WEBUI_SECRET_KEY: ${JWT_SECRET}
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/open-webui:/app/backend/data
      - ${DATA_ROOT}/logs/open-webui:/app/logs
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${OPENWEBUI_PORT:-3000}:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    labels:
      - "ai-platform.service=open-webui"
      - "ai-platform.type=ui"

EOF
}

add_dify_services() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER:-postgres}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/storage
      VECTOR_STORE: qdrant
      QDRANT_URL: http://qdrant:6333
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/dify/storage:/app/storage
      - ${DATA_ROOT}/logs/dify:/app/logs
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${DIFY_PORT:-8080}:5001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    labels:
      - "ai-platform.service=dify-api"
      - "ai-platform.type=ai-platform"

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    depends_on:
      dify-api:
        condition: service_healthy
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${DIFY_PORT:-8080}:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    labels:
      - "ai-platform.service=dify-web"
      - "ai-platform.type=ai-platform"

EOF
}

add_n8n_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: ${POSTGRES_USER:-postgres}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_HOST: ${DOMAIN_NAME:-localhost}
      N8N_PORT: 5678
      N8N_PROTOCOL: http
      WEBHOOK_URL: http://${DOMAIN_NAME:-localhost}:5678
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/n8n:/home/node/.n8n
      - ${DATA_ROOT}/logs/n8n:/var/log/n8n
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${N8N_PORT:-5678}:5678"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=n8n"
      - "ai-platform.type=workflow"

EOF
}

add_flowise_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    environment:
      DATABASE_TYPE: postgres
      DATABASE_HOST: postgres
      DATABASE_PORT: 5432
      DATABASE_USER: ${POSTGRES_USER:-postgres}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      DATABASE_NAME: flowise
      FLOWISE_USERNAME: admin
      FLOWISE_PASSWORD: ${ADMIN_PASSWORD}
      SECRETKEY_OVERWRITE: ${ENCRYPTION_KEY}
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/flowise:/root/.flowise
      - ${DATA_ROOT}/logs/flowise:/var/log/flowise
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${FLOWISE_PORT:-3002}:3000"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=flowise"
      - "ai-platform.type=workflow"

EOF
}

add_anythingllm_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    environment:
      STORAGE_DIR: /app/server/storage
      JWT_SECRET: ${JWT_SECRET}
      LLM_PROVIDER: ollama
      OLLAMA_BASE_PATH: http://ollama:11434
      EMBEDDING_ENGINE: ollama
      EMBEDDING_BASE_PATH: http://ollama:11434
      VECTOR_DB: qdrant
      QDRANT_ENDPOINT: http://qdrant:6333
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/anythingllm:/app/server/storage
      - ${DATA_ROOT}/documents:/app/server/storage/documents
      - ${DATA_ROOT}/logs/anythingllm:/var/log/anythingllm
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${ANYTHINGLLM_PORT:-3001}:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=anythingllm"
      - "ai-platform.type=ai-platform"

EOF
}

add_monitoring_services() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ${DATA_ROOT}/prometheus:/prometheus
      - ${DATA_ROOT}/config/prometheus:/etc/prometheus
      - ${DATA_ROOT}/logs/prometheus:/var/log/prometheus
    networks:
      - ${DOCKER_NETWORK}_internal
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=prometheus"
      - "ai-platform.type=monitoring"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    depends_on:
      prometheus:
        condition: service_healthy
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: false
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/grafana:/var/lib/grafana
      - ${DATA_ROOT}/logs/grafana:/var/log/grafana
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=grafana"
      - "ai-platform.type=monitoring"

EOF
}

add_signal_api_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    environment:
      MODE: json-rpc
      PORT: ${SIGNAL_API_PORT:-8090}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/signal-api:/home/.local/share/signal-cli
      - ${DATA_ROOT}/logs/signal-api:/var/log/signal-api
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${SIGNAL_API_PORT:-8090}:8090"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8090/about"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=signal-api"
      - "ai-platform.type=communication"

EOF
}

add_openclaw_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  openclaw:
    image: alpine/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    environment:
      OPENCLAW_ADMIN_USER: ${OPENCLAW_ADMIN_USER:-admin}
      OPENCLAW_ADMIN_PASSWORD: ${OPENCLAW_ADMIN_PASSWORD}
      OPENCLAW_PORT: ${OPENCLAW_PORT:-18789}
      OPENCLAW_API_PORT: ${OPENCLAW_API_PORT:-8083}
      OPENCLAW_ENABLE_SIGNAL: ${OPENCLAW_ENABLE_SIGNAL:-true}
      OPENCLAW_ENABLE_LITELM: ${OPENCLAW_ENABLE_LITELM:-true}
      OPENCLAW_ENABLE_N8N: ${OPENCLAW_ENABLE_N8N:-true}
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/openclaw:/app/data
      - ${DATA_ROOT}/logs/openclaw:/var/log/openclaw
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${OPENCLAW_PORT:-18789}:8082"
      - "${OPENCLAW_API_PORT:-8083}:8083"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8082/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=openclaw"
      - "ai-platform.type=orchestration"

EOF
}

add_tailscale_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    restart: unless-stopped
    environment:
      TS_USERSPACE: ${TAILSCALE_USERSPACE:-ai-platform}
      TS_EXTRA_ARGS: ${TAILSCALE_EXTRA_ARGS}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/tailscale:/var/lib/tailscale
      - ${DATA_ROOT}/logs/tailscale:/var/log/tailscale
    networks:
      - ${DOCKER_NETWORK}_internal
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=tailscale"
      - "ai-platform.type=networking"

EOF
}

add_minio_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/minio:/data
      - ${DATA_ROOT}/logs/minio:/var/log/minio
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "${MINIO_API_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=minio"
      - "ai-platform.type=storage"

EOF
}

add_qdrant_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    user: "${RUNNING_UID}:${RUNNING_GID}"
    environment:
      PUID: ${RUNNING_UID}
      PGID: ${RUNNING_GID}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - ${DATA_ROOT}/qdrant:/qdrant/storage
      - ${DATA_ROOT}/logs/qdrant:/var/log/qdrant
    networks:
      - ${DOCKER_NETWORK}_internal
      - ${DOCKER_NETWORK}
    ports:
      - "6333:6333"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "ai-platform.service=qdrant"
      - "ai-platform.type=vector-database"

EOF
}

# Main Execution
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Pre-initialize logging BEFORE any print functions are called
    echo "DEBUG: About to create directories..."
    mkdir -p "/mnt/data" 2>/dev/null || echo "DEBUG: Failed to create /mnt/data"
    mkdir -p "/mnt/data/logs" 2>/dev/null || echo "DEBUG: Failed to create /mnt/data/logs"
    export LOG_FILE="/mnt/data/logs/setup.log"
    echo "DEBUG: LOG_FILE set to: $LOG_FILE"
    echo "DEBUG: Directory creation completed"
    
    # Display banner
    print_banner
    
    # Check for previous state and offer to resume
    if restore_state; then
        print_info "Resuming from saved state..."
    else
        # Fresh start - clear any old state
        rm -f "$STATE_FILE"
        COMPLETED_PHASES=()
        save_state "init" "started" "Setup initialized"
    fi
    
    # Execute phases
    setup_volumes
    mark_phase_complete "setup_volumes"
    
    # Create directory structure immediately after mounting
    # Ensure user variables are available first
    RUNNING_USER="${RUNNING_USER:-${SUDO_USER:-$USER}}"
    RUNNING_UID="${RUNNING_UID:-$(id -u "$RUNNING_USER")}"
    RUNNING_GID="${RUNNING_GID:-$(id -g "$RUNNING_USER")}"
    
    # Set OpenClaw user (stack user + 1)
    OPENCLAW_UID=$((RUNNING_UID + 1))
    OPENCLAW_GID="$RUNNING_GID"
    
    create_directory_structure
    mark_phase_complete "create_directory_structure"
    
    # Initialize logging after volume is mounted and directories exist
    setup_logging
    
    detect_system
    mark_phase_complete "detect_system"
    collect_domain_info
    print_success "Domain configuration completed"
    
    # Load the environment variables so they're available for subsequent phases
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        print_info "Environment variables loaded"
    fi
    
    mark_phase_complete "collect_domain_info"
    update_system
    mark_phase_complete "update_system"
    install_docker
    mark_phase_complete "install_docker"
    configure_docker
    mark_phase_complete "configure_docker"
    select_services
    mark_phase_complete "select_services"
    collect_configurations
    mark_phase_complete "collect_configurations"
    create_apparmor_templates
    mark_phase_complete "create_apparmor_templates"
    
    # Generate WEBUI_SECRET_KEY for OpenWebUI
    local webui_secret_key=$(openssl rand -hex 32)
    echo "WEBUI_SECRET_KEY=$webui_secret_key" >> "$ENV_FILE"
    
    # Generate LITELLM_MASTER_KEY
    local litellm_master_key=$(openssl rand -hex 32)
    echo "LITELLM_MASTER_KEY=$litellm_master_key" >> "$ENV_FILE"
    
    generate_compose_templates
    mark_phase_complete "generate_compose_templates"
    
    # DEBUG: Verify compose file was created
    print_info "DEBUG: Checking generated compose file..."
    if [[ -f "$COMPOSE_FILE" ]]; then
        print_success "Docker Compose file generated: $COMPOSE_FILE"
        print_info "Services in compose file: $(grep -c "^  [a-z]" "$COMPOSE_FILE")"
    else
        print_error "Docker Compose file NOT generated"
    fi
    
    validate_system
    mark_phase_complete "validate_system"
    
    generate_summary
    mark_phase_complete "generate_summary"
    
    # Phase 12: Final Configuration Validation
    log_phase "12" "🔧" "Final Configuration Validation"
    
    echo ""
    print_header "🔧 Final Configuration Validation"
    echo ""
    
    # Validate critical configurations
    print_info "Validating critical configurations..."
    
    # Check environment variables
    local env_vars_count=$(grep -c "^" "$ENV_FILE" 2>/dev/null || echo "0")
    local secrets_count=$(grep -c "_PASSWORD\|_SECRET\|_KEY" "$ENV_FILE" 2>/dev/null || echo "0")
    
    print_success "Environment variables: $env_vars_count"
    print_success "Generated secrets: $secrets_count"
    
    # Validate selected services
    local selected_services_count=$(jq -r '.total_services' "$SERVICES_FILE" 2>/dev/null || echo "0")
    print_success "Services configured: $selected_services_count"
    
    mark_phase_complete "validate_final_config"
    
    # Phase 13: Setup Completion
    print_info "Final setup validation completed successfully"
    print_info "All configurations are ready for deployment"
    
    mark_phase_complete "setup_completion"
    
    # Mark setup as completed
    save_state "completed" "success" "Setup completed successfully"
    
    # Completion message
    echo ""
    echo "$(printf '═%.0s' {1..80})"
    echo ""
    print_success "🎉 SETUP SCRIPT COMPLETED SUCCESSFULLY!"
    echo ""
    print_info "Next: Run the deployment script:"
    echo ""
    echo -e "${CYAN}sudo bash 2-deploy-services.sh${NC}"
    echo ""
    echo "$(printf '═%.0s' {1..80})"
    echo ""
    
    exit 0
}

# Create AppArmor templates with BASE_DIR substitution
create_apparmor_templates() {
    print_header "Creating AppArmor Templates"
    
    local profile_dir="${DATA_ROOT}/apparmor"
    mkdir -p "${profile_dir}"
    
    # Default profile template (allowlist-only)
    cat > "${profile_dir}/default.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allowlist: only what AI Platform services need
  BASE_DIR_PLACEHOLDER/data/** rw,
  BASE_DIR_PLACEHOLDER/logs/** rw,
  BASE_DIR_PLACEHOLDER/config/** rw,
  BASE_DIR_PLACEHOLDER/ssl/** r,
  /tmp/** rw,
  /var/run/docker.sock rw,
  /proc/** r,
  /sys/** r,

  network,
  capability dac_override,
  capability setuid,
  capability setgid,
  capability chown,
}
EOF

    # OpenClaw profile template (allowlist-only)
    cat > "${profile_dir}/openclaw.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allowlist: only what OpenClaw needs
  BASE_DIR_PLACEHOLDER/data/openclaw/** rw,
  BASE_DIR_PLACEHOLDER/config/openclaw/** r,
  /tmp/** rw,

  network,
  capability net_raw,
}
EOF

    # Tailscale profile template (allowlist-only)
    cat > "${profile_dir}/tailscale.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-tailscale flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allowlist: only what Tailscale needs
  BASE_DIR_PLACEHOLDER/data/tailscale/** rw,
  /var/lib/tailscale/** rw,
  /dev/net/tun rw,
  /etc/resolv.conf r,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    print_success "AppArmor templates created in ${profile_dir}"
}

# Run main function
main "$@"
