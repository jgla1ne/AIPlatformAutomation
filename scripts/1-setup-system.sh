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

# Paths
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/setup.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"

# UI Functions
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║            AI PLATFORM AUTOMATION - SETUP                      ║"
    echo "║                      Version 4.0.0                               ║"
    echo "║                Configuration Collection Only                ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
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
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
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
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
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
        print_warn "State file corrupted - starting fresh"
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
    
    prompt_input "DOMAIN" "Enter your domain (e.g., example.com)" "" false "domain"
    echo "DOMAIN=$INPUT_RESULT" >> "$ENV_FILE"
    
    # Validate domain resolution
    echo ""
    print_info "Validating domain resolution..."
    if nslookup "$INPUT_RESULT" >/dev/null 2>&1; then
        local public_ip=$(nslookup "$INPUT_RESULT" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
        
        if [[ "$public_ip" == "$server_ip" ]]; then
            print_success "Domain resolves to this server: $public_ip"
            echo "DOMAIN_RESOLVES=true" >> "$ENV_FILE"
            echo "PUBLIC_IP=$server_ip" >> "$ENV_FILE"
        else
            print_warn "Domain resolves to different IP: $public_ip (server: $server_ip)"
            echo "DOMAIN_RESOLVES=false" >> "$ENV_FILE"
            echo "PUBLIC_IP=$server_ip" >> "$ENV_FILE"
        fi
    else
        print_warn "Domain does not resolve or DNS not configured"
        echo "DOMAIN_RESOLVES=false" >> "$ENV_FILE"
        echo "PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')" >> "$ENV_FILE"
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
        print_warn "Package manager not detected - skipping system update"
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
    docker network create ai-platform 2>/dev/null || true
    docker network create ai-platform-internal 2>/dev/null || true
    docker network create ai-platform-monitoring 2>/dev/null || true
    
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
    echo "  [1] Nginx Proxy Manager - Visual reverse proxy (RECOMMENDED)"
    echo "  [2] Traefik - Modern reverse proxy with auto SSL"
    echo "  [3] PostgreSQL - Relational database"
    echo "  [4] Redis - Cache and message queue"
    echo "  [5] Tailscale - VPN mesh network"
    echo ""
    
    # AI Applications
    echo "🤖 AI Applications:"
    echo "  [6] Open WebUI - Modern ChatGPT-like interface"
    echo "  [7] AnythingLLM - Document-based AI chat"
    echo "  [8] Dify - LLM application development platform"
    echo "  [9] n8n - Workflow automation platform"
    echo "  [10] Flowise - Visual LangChain builder"
    echo ""
    
    # LLM Infrastructure
    echo "🤖 LLM Infrastructure:"
    echo "  [11] Ollama - Local LLM runtime"
    echo "  [12] LiteLLM - Multi-provider proxy + routing"
    echo ""
    
    # Vector Databases
    echo "🧠 Vector Databases:"
    echo "  [13] Qdrant - High-performance vector DB (Recommended)"
    echo "  [14] Milvus - Distributed vector database"
    echo "  [15] ChromaDB - Simple Python-native DB"
    echo "  [16] Weaviate - GraphQL API with semantic search"
    echo ""
    
    # Communication & Integration
    echo "📱 Communication & Integration:"
    echo "  [17] Signal API - Private messaging"
    echo "  [18] OpenClaw UI - Multi-channel orchestration"
    echo ""
    
    # Monitoring
    echo "📊 Monitoring:"
    echo "  [19] Prometheus + Grafana - Metrics and visualization"
    echo ""
    
    # Storage
    echo "� Storage:"
    echo "  [20] MinIO - S3-compatible storage"
    echo ""
    
    echo "Select services (space-separated, e.g., '1 3 6'):"
    echo "Or enter 'all' to select all recommended services"
    echo ""
    
    local -A selected_map=(
        ["nginx-proxy-manager"]=1
        ["traefik"]=1
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
        ["qdrant"]=1
        ["milvus"]=1
        ["chroma"]=1
        ["weaviate"]=1
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
                if [[ $num -ge 1 ]] && [[ $num -le 20 ]]; then
                    local service_name
                    case $num in
                        1) service_name="nginx-proxy-manager" ;;
                        2) service_name="traefik" ;;
                        3) service_name="postgres" ;;
                        4) service_name="redis" ;;
                        5) service_name="tailscale" ;;
                        6) service_name="openwebui" ;;
                        7) service_name="anythingllm" ;;
                        8) service_name="dify" ;;
                        9) service_name="n8n" ;;
                        10) service_name="flowise" ;;
                        11) service_name="ollama" ;;
                        12) service_name="litellm" ;;
                        13) service_name="qdrant" ;;
                        14) service_name="milvus" ;;
                        15) service_name="chroma" ;;
                        16) service_name="weaviate" ;;
                        17) service_name="signal-api" ;;
                        18) service_name="openclaw" ;;
                        19) service_name="prometheus" ;;
                        20) service_name="minio" ;;
                        *) print_warn "Invalid selection: $num"; continue ;;
                    esac
                    
                    if [[ -n "${selected_map[$service_name]:-}" ]]; then
                        selected_map[$service_name]=1
                        print_success "Added: $service_name"
                    else
                        selected_map[$service_name]=0
                        print_info "Removed: $service_name"
                    fi
                else
                    print_warn "Invalid selection: $num (must be 1-11)"
                fi
            done
            break
        else
            print_error "Invalid selection. Please enter numbers 1-11 or 'all'"
        fi
    done
    
    # Convert selected services to array
    local selected_services=()
    for service in "${!selected_map[@]}"; do
        if [[ "${selected_map[$service]}" == "1" ]]; then
            selected_services+=("$service")
        fi
    done
    
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
    
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Services file not found: $SERVICES_FILE"
        exit 1
    fi
    
    local selected_services=($(jq -r '.services[].key' "$SERVICES_FILE"))
    
    echo ""
    print_header "🔍 Port Availability Check"
    echo ""
    
    # Port availability check
    local -A ports_to_check=(
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
            print_warn "Port $port is in use by $service (pid: $pid)"
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
    
    # Initialize environment file
    cat > "$ENV_FILE" <<EOF
# AI Platform Environment
# Generated: $(date -Iseconds)

# System Configuration
DATA_ROOT=$DATA_ROOT
METADATA_DIR=$METADATA_DIR
TIMEZONE=UTC
LOG_LEVEL=info

# Network Configuration
DOMAIN=${DOMAIN:-localhost}
PROXY_TYPE=${PROXY_TYPE:-none}
SSL_TYPE=${SSL_TYPE:-none}
SSL_EMAIL=${SSL_EMAIL:-}
EOF
    
    # Port configuration
    echo ""
    print_info "Port Configuration"
    echo ""
    
    # Custom port selection for major services
    local -A default_ports=(
        ["nginx-proxy-manager"]="80"
        ["traefik"]="80"
        ["caddy"]="80"
        ["openwebui"]="3000"
        ["anythingllm"]="3001"
        ["n8n"]="5678"
        ["dify"]="8080"
        ["ollama"]="11434"
        ["litellm"]="4000"
        ["prometheus"]="9090"
        ["grafana"]="3001"
        ["signal-api"]="8090"
        ["openclaw"]="18789"
        ["tailscale"]="8443"
        ["postgres"]="5432"
        ["redis"]="6379"
        ["qdrant"]="6333"
        ["milvus"]="19530"
        ["chroma"]="8000"
        ["weaviate"]="8080"
        ["minio"]="9000"
    )
    
    # Proxy port configuration
    if [[ " ${selected_services[*]} " =~ " nginx-proxy-manager " ]] || [[ " ${selected_services[*]} " =~ " traefik " ]] || [[ " ${selected_services[*]} " =~ " caddy " ]]; then
        echo ""
        print_info "Proxy Port Configuration"
        echo ""
        
        if [[ " ${selected_services[*]} " =~ " nginx-proxy-manager " ]]; then
            prompt_input "NGINX_PROXY_HTTP_PORT" "Nginx Proxy Manager HTTP port" "80" false
            echo "NGINX_PROXY_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "NGINX_PROXY_HTTPS_PORT" "Nginx Proxy Manager HTTPS port" "443" false
            echo "NGINX_PROXY_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        if [[ " ${selected_services[*]} " =~ " traefik " ]]; then
            prompt_input "TRAEFIK_HTTP_PORT" "Traefik HTTP port" "80" false
            echo "TRAEFIK_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "TRAEFIK_HTTPS_PORT" "Traefik HTTPS port" "443" false
            echo "TRAEFIK_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
        
        if [[ " ${selected_services[*]} " =~ " caddy " ]]; then
            prompt_input "CADDY_HTTP_PORT" "Caddy HTTP port" "80" false
            echo "CADDY_HTTP_PORT=$INPUT_RESULT" >> "$ENV_FILE"
            
            prompt_input "CADDY_HTTPS_PORT" "Caddy HTTPS port" "443" false
            echo "CADDY_HTTPS_PORT=$INPUT_RESULT" >> "$ENV_FILE"
        fi
    fi
    
    print_success "Proxy configuration completed"
    
    # Service port configuration
    for service_key in "${selected_services[@]}"; do
        case "$service_key" in
            "nginx-proxy-manager"|"traefik"|"caddy"|"openwebui"|"anythingllm"|"n8n"|"dify"|"ollama"|"litellm"|"prometheus"|"grafana"|"signal-api"|"openclaw"|"tailscale"|"postgres"|"redis"|"qdrant"|"milvus"|"chroma"|"weaviate"|"minio")
                local default_port="${default_ports[$service_key]:-3000}"
                prompt_input "${service_key^^}_PORT" "$service_key port" "$default_port" false
                echo "${service_key^^}_PORT=$INPUT_RESULT" >> "$ENV_FILE"
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
                        *) print_warn "Invalid model selection: $num" ;;
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
        
        local redis_password=$(generate_random_password 24)
        echo "REDIS_PASSWORD=$redis_password" >> "$ENV_FILE"
        echo "REDIS_PORT=6379" >> "$ENV_FILE"
        
        print_success "Redis configuration generated"
    fi
    
    # Vector Database Selection
    if [[ " ${selected_services[*]} " =~ " anythingllm " ]] || [[ " ${selected_services[*]} " =~ " dify " ]]; then
        echo ""
        print_header "🗄️ Vector Database Selection"
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
        echo "     - Complex setup"
        echo ""
        echo "  3) ChromaDB"
        echo "     - Simple setup"
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
        echo "Select providers to configure (space-separated):"
        echo "  1) OpenAI (GPT-4, GPT-3.5)"
        echo "  2) Anthropic (Claude 3)"
        echo "  3) Google (Gemini)"
        echo "  4) Groq (Fast Llama inference)"
        echo "  5) Mistral (Mistral AI)"
        echo "  6) All of the above"
        echo "  7) Skip API providers"
        echo ""
        
        while true; do
            echo -n -e "${YELLOW}Select providers [1-7]:${NC} "
            read -r llm_provider_selection
            
            # Handle space-separated input like "3 4" or "3,4" or "3-4"
            if [[ "$llm_provider_selection" =~ [,\ -] ]]; then
                # Multiple providers selected
                local selected_providers=("local")
                local provider_keys=()
                
                # Clean up the input and split by spaces, commas, or dashes
                local cleaned_input=$(echo "$llm_provider_selection" | tr ', ' ' ' ' ')
                
                for num in $cleaned_input; do
                    case $num in
                        1) 
                            selected_providers+=("openai")
                            provider_keys+=("OPENAI_API_KEY")
                            ;;
                        2) 
                            selected_providers+=("anthropic")
                            provider_keys+=("ANTHROPIC_API_KEY")
                            ;;
                        3) 
                            selected_providers+=("google")
                            provider_keys+=("GOOGLE_API_KEY")
                            ;;
                        4) 
                            selected_providers+=("groq")
                            provider_keys+=("GROQ_API_KEY")
                            ;;
                        5) 
                            selected_providers+=("mistral")
                            provider_keys+=("MISTRAL_API_KEY")
                            ;;
                        6) 
                            selected_providers+=("openai" "anthropic" "google" "groq" "mistral")
                            provider_keys+=("OPENAI_API_KEY" "ANTHROPIC_API_KEY" "GOOGLE_API_KEY" "GROQ_API_KEY" "MISTRAL_API_KEY")
                            ;;
                        *) print_warn "Invalid provider selection: $num" ;;
                    esac
                done
                
                if [[ ${#selected_providers[@]} -gt 1 ]]; then
                    local providers_str=$(IFS=','; echo "${selected_providers[*]}")
                    echo "LLM_PROVIDERS=$providers_str" >> "$ENV_FILE"
                    
                    # Prompt for API keys for selected providers
                    for key in "${provider_keys[@]}"; do
                        case $key in
                            "OPENAI_API_KEY") prompt_input "OPENAI_API_KEY" "OpenAI API key" "" false && echo "OPENAI_API_KEY=$INPUT_RESULT" >> "$ENV_FILE" ;;
                            "ANTHROPIC_API_KEY") prompt_input "ANTHROPIC_API_KEY" "Anthropic API key" "" false && echo "ANTHROPIC_API_KEY=$INPUT_RESULT" >> "$ENV_FILE" ;;
                            "GOOGLE_API_KEY") prompt_input "GOOGLE_API_KEY" "Google AI API key" "" false && echo "GOOGLE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE" ;;
                            "GROQ_API_KEY") prompt_input "GROQ_API_KEY" "Groq API key" "" false && echo "GROQ_API_KEY=$INPUT_RESULT" >> "$ENV_FILE" ;;
                            "MISTRAL_API_KEY") prompt_input "MISTRAL_API_KEY" "Mistral API key" "" false && echo "MISTRAL_API_KEY=$INPUT_RESULT" >> "$ENV_FILE" ;;
                        esac
                    done
                    
                    print_success "Providers configured: $providers_str"
                    break
                fi
            else
                # Single provider selection (original logic)
                case "$llm_provider_selection" in
                1)
                    echo "LLM_PROVIDERS=local,openai" >> "$ENV_FILE"
                    prompt_input "OPENAI_API_KEY" "OpenAI API key" "" false
                    echo "OPENAI_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Local + OpenAI providers configured"
                    break
                    ;;
                2)
                    echo "LLM_PROVIDERS=local,anthropic" >> "$ENV_FILE"
                    prompt_input "ANTHROPIC_API_KEY" "Anthropic API key" "" false
                    echo "ANTHROPIC_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Local + Anthropic providers configured"
                    break
                    ;;
                3)
                    echo "LLM_PROVIDERS=local,google" >> "$ENV_FILE"
                    prompt_input "GOOGLE_API_KEY" "Google AI API key" "" false
                    echo "GOOGLE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Local + Google providers configured"
                    break
                    ;;
                4)
                    echo "LLM_PROVIDERS=local,groq" >> "$ENV_FILE"
                    prompt_input "GROQ_API_KEY" "Groq API key" "" false
                    echo "GROQ_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Local + Groq providers configured"
                    break
                    ;;
                5)
                    echo "LLM_PROVIDERS=local,mistral" >> "$ENV_FILE"
                    prompt_input "MISTRAL_API_KEY" "Mistral API key" "" false
                    echo "MISTRAL_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "Local + Mistral providers configured"
                    break
                    ;;
                6)
                    echo "LLM_PROVIDERS=local,openai,anthropic,google,groq,mistral" >> "$ENV_FILE"
                    prompt_input "OPENAI_API_KEY" "OpenAI API key" "" false
                    echo "OPENAI_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "ANTHROPIC_API_KEY" "Anthropic API key" "" false
                    echo "ANTHROPIC_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "GOOGLE_API_KEY" "Google AI API key" "" false
                    echo "GOOGLE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "GROQ_API_KEY" "Groq API key" "" false
                    echo "GROQ_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    prompt_input "MISTRAL_API_KEY" "Mistral API key" "" false
                    echo "MISTRAL_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
                    print_success "All providers configured"
                    break
                    ;;
                7)
                    echo "LLM_PROVIDERS=local" >> "$ENV_FILE"
                    print_success "Local provider only"
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        fi
        done
        
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
        
        while true; do
            echo -n -e "${YELLOW}Select routing strategy [1-4]:${NC} "
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
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
        
        # LiteLLM core variables
        local litellm_master_key=$(generate_random_password 32)
        echo "LITELLM_MASTER_KEY=$litellm_master_key" >> "$ENV_FILE"
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
                    echo "SIGNAL_API_PAIRING_URL=http://localhost:8081/v1/generate_token" >> "$ENV_FILE"
                    print_success "Internal API pairing selected"
                    print_info "Pairing token will be available at: http://localhost:8081/v1/generate_token"
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
        
        echo "OPENCLAW_PORT=8082" >> "$ENV_FILE"
        echo "OPENCLAW_API_PORT=8083" >> "$ENV_FILE"
        
        # OpenClaw integration settings
        echo "OPENCLAW_ENABLE_SIGNAL=true" >> "$ENV_FILE"
        echo "OPENCLAW_ENABLE_LITELM=true" >> "$ENV_FILE"
        echo "OPENCLAW_ENABLE_N8N=true" >> "$ENV_FILE"
        
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

create_directory_structure() {
    log_phase "9" "📁" "Directory Structure Creation"
    
    print_info "Creating modular directory structure..."
    
    # Create directories
    mkdir -p "$DATA_ROOT"/{compose,env,config,metadata,data,logs,secrets}
    
    # Create config subdirectories
    mkdir -p "$DATA_ROOT/config"/{nginx,traefik,caddy,litellm,postgres,redis,qdrant,prometheus,grafana}
    
    print_success "Directory structure created"
    print_info "Base: $DATA_ROOT"
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
                echo "- Ollama: http://localhost:11434" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Ollama (Public): https://$DOMAIN/ollama" >> "$urls_file"
                ;;
            "openwebui")
                echo "- Open WebUI: http://localhost:3000" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Open WebUI (Public): https://$DOMAIN/openwebui" >> "$urls_file"
                ;;
            "anythingllm")
                echo "- AnythingLLM: http://localhost:3001" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- AnythingLLM (Public): https://$DOMAIN/anythingllm" >> "$urls_file"
                ;;
            "dify")
                echo "- Dify: http://localhost:8080" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Dify (Public): https://$DOMAIN/dify" >> "$urls_file"
                ;;
            "n8n")
                echo "- n8n: http://localhost:5678" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- n8n (Public): https://$DOMAIN/n8n" >> "$urls_file"
                ;;
            "flowise")
                echo "- Flowise: http://localhost:3002" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Flowise (Public): https://$DOMAIN/flowise" >> "$urls_file"
                ;;
            "litellm")
                echo "- LiteLLM: http://localhost:4000" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- LiteLLM (Public): https://$DOMAIN/litellm" >> "$urls_file"
                ;;
            "signal-api")
                echo "- Signal API: http://localhost:8090" >> "$urls_file"
                echo "- Signal QR: http://localhost:8090/v1/qrcode" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Signal API (Public): https://$DOMAIN/signal-api" >> "$urls_file"
                ;;
            "openclaw")
                echo "- OpenClaw: http://localhost:18789" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- OpenClaw (Public): https://$DOMAIN/openclaw" >> "$urls_file"
                ;;
            "prometheus")
                echo "- Prometheus: http://localhost:9090" >> "$urls_file"
                ;;
            "grafana")
                echo "- Grafana: http://localhost:3005" >> "$urls_file"
                [[ "${DOMAIN_RESOLVES:-false}" == "true" ]] && echo "- Grafana (Public): https://$DOMAIN/grafana" >> "$urls_file"
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
                echo "- MinIO: http://localhost:9000" >> "$urls_file"
                echo "- MinIO Console: http://localhost:9001" >> "$urls_file"
                ;;
        esac
    done
    
    echo "" >> "$urls_file"
    echo "Database Credentials:" >> "$urls_file"
    echo "" >> "$urls_file"
    echo "- PostgreSQL User: postgres" >> "$urls_file"
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
    
    # Display summary to user
    print_success "Setup summary generated: $summary_file"
    print_success "Service URLs saved: $urls_file"
    print_info "Review service URLs file for complete access information"
    
    # Display key information
    echo ""
    print_header "🔑 Key Information"
    echo ""
    print_info "Database Credentials:"
    echo "  • PostgreSQL User: postgres"
    echo "  • PostgreSQL Password: $(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • Redis Password: $(grep "^REDIS_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • Vector Database: ${VECTOR_DB:-qdrant}"
    echo ""
    
    print_info "Admin Credentials:"
    echo "  • Admin Password: $(grep "^ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo "  • Grafana Password: $(grep "^GRAFANA_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    [[ -n "${OPENCLAW_ADMIN_PASSWORD:-}" ]] && echo "  • OpenClaw Password: $(grep "^OPENCLAW_ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2)"
    echo ""
    
    print_info "Service Access:"
    echo "  • Open WebUI: http://localhost:3000"
    echo "  • LiteLLM: http://localhost:4000"
    echo "  • n8n: http://localhost:5678"
    echo "  • Dify: http://localhost:8080"
    echo "  • Grafana: http://localhost:3001"
    echo ""
    
    if [[ "${DOMAIN_RESOLVES:-false}" == "true" ]]; then
        print_success "Domain resolves correctly - public access available"
    else
        print_warn "Domain does not resolve - using local access"
    fi
    
    print_success "Summary generation completed"
}

# Main Execution
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Initialize
    setup_logging
    
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
    detect_system
    mark_phase_complete "detect_system"
    
    collect_domain_info
    mark_phase_complete "collect_domain_info"
    
    update_system
    mark_phase_complete "update_system"
    
    install_docker
    mark_phase_complete "install_docker"
    
    configure_docker
    mark_phase_complete "configure_docker"
    
    install_ollama
    mark_phase_complete "install_ollama"
    
    select_services
    mark_phase_complete "select_services"
    
    collect_configurations
    mark_phase_complete "collect_configurations"
    
    create_directory_structure
    mark_phase_complete "create_directory_structure"
    
    validate_system
    mark_phase_complete "validate_system"
    
    generate_summary
    mark_phase_complete "generate_summary"
    
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

# Run main function
main "$@"
