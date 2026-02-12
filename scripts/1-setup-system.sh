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
    print_info "Domain Configuration"
    echo ""
    
    prompt_input "DOMAIN" "Enter your domain (e.g., example.com)" "" false "domain"
    echo "DOMAIN=$INPUT_RESULT" >> "$ENV_FILE"
    
    echo ""
    print_info "Proxy Selection"
    echo ""
    echo "Select reverse proxy:"
    echo "  1) Nginx (Traditional - Reliable, manual SSL config)"
    echo "  2) Traefik (Modern - Auto SSL with Docker labels)"
    echo "  3) Caddy (Automatic - Zero-config HTTPS)"
    echo "  4) None (Direct port access - Not recommended)"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Select option [1-4]:${NC} "
        read -r proxy_choice
        
        case "$proxy_choice" in
            1)
                echo "PROXY_TYPE=nginx" >> "$ENV_FILE"
                print_success "Nginx selected"
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
        print_info "SSL Configuration"
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
    
    # AI Applications Selection
    echo "🤖 AI Applications:"
    echo "  [1] Open WebUI - Modern ChatGPT-like interface"
    echo "  [2] AnythingLLM - Document-based AI chat"
    echo "  [3] Dify - LLM application development platform"
    echo "  [4] n8n - Workflow automation platform"
    echo "  [5] Flowise - Visual LangChain builder"
    echo ""
    
    # LLM Infrastructure Selection
    echo "🤖 LLM Infrastructure:"
    echo "  [6] Ollama - Local LLM runtime"
    echo "  [7] LiteLLM - Multi-provider proxy + routing"
    echo ""
    
    # Communication & Integration Selection
    echo "📱 Communication & Integration:"
    echo "  [8] Signal API - Private messaging"
    echo "  [9] OpenClaw UI - Multi-channel orchestration"
    echo ""
    
    # Vector Database Selection
    echo "🧠 Vector Database:"
    echo "  [10] Qdrant - High-performance vector DB"
    echo ""
    
    # Monitoring Selection
    echo "📊 Monitoring:"
    echo "  [11] Prometheus + Grafana - Metrics and visualization"
    echo ""
    
    echo "Select services (space-separated, e.g., '1 3 6'):"
    echo "Or enter 'all' to select all recommended services"
    echo ""
    
    local -A selected_map=(
        ["openwebui"]=1
        ["anythingllm"]=1
        ["dify"]=1
        ["n8n"]=1
        ["flowise"]=1
        ["ollama"]=1
        ["litellm"]=1
        ["signal-api"]=1
        ["openclaw"]=1
        ["qdrant"]=1
        ["prometheus"]=1
        ["grafana"]=1
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
                if [[ $num -ge 1 ]] && [[ $num -le 11 ]]; then
                    local service_name
                    case $num in
                        1) service_name="openwebui" ;;
                        2) service_name="anythingllm" ;;
                        3) service_name="dify" ;;
                        4) service_name="n8n" ;;
                        5) service_name="flowise" ;;
                        6) service_name="ollama" ;;
                        7) service_name="litellm" ;;
                        8) service_name="signal-api" ;;
                        9) service_name="openclaw" ;;
                        10) service_name="qdrant" ;;
                        11) service_name="prometheus" ;;
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
    local ports_to_check=(
        "80:HTTP"
        "443:HTTPS"
        "3000:OpenWebUI/Grafana/Langfuse"
        "3001:AnythingLLM"
        "5678:n8n"
        "6333:Qdrant"
        "6334:Qdrant GRPC"
        "8080:Dify"
        "11434:Ollama"
        "5432:PostgreSQL"
        "6379:Redis"
        "4000:LiteLLM"
        "9090:Prometheus"
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
        ["openwebui"]="3000"
        ["anythingllm"]="3001"
        ["n8n"]="5678"
        ["dify"]="8080"
        ["ollama"]="11434"
        ["litellm"]="4000"
        ["prometheus"]="9090"
        ["grafana"]="3001"
        ["signal-api"]="8090"
    )
    
    for service_key in "${selected_services[@]}"; do
        case "$service_key" in
            "openwebui"|"anythingllm"|"n8n"|"dify"|"ollama"|"litellm"|"prometheus"|"grafana"|"signal-api")
                local default_port="${default_ports[$service_key]:-3000}"
                prompt_input "${service_key^^}_PORT" "$service_key port" "$default_port" false
                echo "${service_key^^}_PORT=$INPUT_RESULT" >> "$ENV_FILE"
                ;;
        esac
    done
    
    # Database configuration
    if [[ " ${selected_services[*]} " =~ " postgres " ]]; then
        echo ""
        print_info "PostgreSQL Configuration"
        echo ""
        
        local postgres_password=$(generate_random_password 24)
        echo "POSTGRES_PASSWORD=$postgres_password" >> "$ENV_FILE"
        echo "POSTGRES_DB=aiplatform" >> "$ENV_FILE"
        echo "POSTGRES_USER=postgres" >> "$ENV_FILE"
        
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
    
    # Qdrant configuration
    if [[ " ${selected_services[*]} " =~ " qdrant " ]]; then
        echo ""
        print_info "Qdrant Configuration"
        echo ""
        
        local qdrant_api_key=$(generate_random_password 32)
        echo "QDRANT_API_KEY=$qdrant_api_key" >> "$ENV_FILE"
        echo "QDRANT_HTTP_PORT=6333" >> "$ENV_FILE"
        echo "QDRANT_GRPC_PORT=6334" >> "$ENV_FILE"
        
        print_success "Qdrant configuration generated"
    fi
    
    # LiteLLM configuration
    if [[ " ${selected_services[*]} " =~ " litellm " ]]; then
        echo ""
        print_header "🤖 LiteLLM Configuration"
        echo ""
        
        local litellm_master_key=$(generate_random_password 32)
        echo "LITELLM_MASTER_KEY=$litellm_master_key" >> "$ENV_FILE"
        
        print_info "Routing Strategy Selection"
        echo ""
        echo "Select LiteLLM routing strategy:"
        echo "  1) Simple Shuffle - Random selection"
        echo "  2) Cost-Based - Choose cheapest model first"
        echo "  3) Latency-Based - Choose fastest model"
        echo "  4) Usage-Based - Load balance across models"
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
        
        # External LLM providers
        echo ""
        print_info "External LLM Provider Configuration"
        echo ""
        print_info "Configure external providers (skip if not needed):"
        echo ""
        
        prompt_input "OPENAI_API_KEY" "OpenAI API Key (or skip)" "" false
        [[ -n "$INPUT_RESULT" ]] && echo "OPENAI_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "ANTHROPIC_API_KEY" "Anthropic API Key (or skip)" "" false
        [[ -n "$INPUT_RESULT" ]] && echo "ANTHROPIC_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "GOOGLE_API_KEY" "Google AI API Key (or skip)" "" false
        [[ -n "$INPUT_RESULT" ]] && echo "GOOGLE_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "GROQ_API_KEY" "Groq API Key (or skip)" "" false
        [[ -n "$INPUT_RESULT" ]] && echo "GROQ_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
        prompt_input "MISTRAL_API_KEY" "Mistral API Key (or skip)" "" false
        [[ -n "$INPUT_RESULT" ]] && echo "MISTRAL_API_KEY=$INPUT_RESULT" >> "$ENV_FILE"
        
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
        
        prompt_input "SIGNAL_PASSWORD" "Signal bot password" "$(generate_random_password 16)" true
        echo "SIGNAL_PASSWORD=$INPUT_RESULT" >> "$ENV_FILE"
        
        echo "SIGNAL_WEBHOOK_URL=http://signal-api:8090/v2/receive" >> "$ENV_FILE"
        
        print_success "Signal API configuration completed"
    fi
    
    # Google Drive integration
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
    
    local summary_file="$METADATA_DIR/setup_summary.txt"
    
    cat > "$summary_file" <<EOF
AI Platform Setup Summary
======================

Setup completed: $(date -Iseconds)
Script version: 4.0.0

Directories:
- Data: $DATA_ROOT
- Metadata: $METADATA_DIR
- Logs: $DATA_ROOT/logs

Configuration:
- Environment: $ENV_FILE
- Services: $SERVICES_FILE

Next Steps:
1. Review configuration in $ENV_FILE
2. Run: sudo bash 2-deploy-services.sh
3. Monitor deployment logs

Generated Files:
- Environment variables
- Service selections
- Directory structure
- System configuration
EOF
    
    print_success "Setup summary generated: $summary_file"
    print_info "Review the summary file for complete configuration details"
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
