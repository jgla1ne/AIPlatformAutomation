#!/bin/bash

#==============================================================================
# Script 1: System Setup & Validation (COMPLETE VERSION)
# Purpose: Comprehensive system setup with all integrations
# Features: Hardware detection, Signal API, Google Drive, Vector DB,
#           LLM routing, UI selection, storage, networking
#==============================================================================

set -euo pipefail

# Color definitions
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
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DATA_DIR="/mnt/data"
readonly CONFIG_DIR="$DATA_DIR/config"
readonly METADATA_FILE="$DATA_DIR/.platform_metadata.json"
readonly ENV_FILE="$DATA_DIR/.env"

# Configuration state
declare -A PLATFORM_CONFIG

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         🚀 AI Platform - System Setup                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_phase() {
    echo ""
    echo -e "${BLUE}${BOLD}[PHASE $1] $2${NC}"
}

print_box_start() {
    echo "┌────────────────────────────────────────────────────────────┐"
}

print_box_line() {
    printf "│ %-58s │\n" "$1"
}

print_box_end() {
    echo "└────────────────────────────────────────────────────────────┘"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}  ℹ${NC} $1"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}$prompt${NC} [${BOLD}$default${NC}]: "
    else
        echo -ne "${CYAN}$prompt${NC}: "
    fi
    read -r response
    echo "${response:-$default}"
}

prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")
    
    echo -e "${CYAN}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    
    local choice
    while true; do
        echo -ne "${CYAN}Select [1-${#options[@]}]${NC}: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        print_error "Invalid selection. Try again."
    done
}

check_port_available() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    fi
    return 0
}

#------------------------------------------------------------------------------
# Phase 1: Hardware Detection
#------------------------------------------------------------------------------

detect_hardware() {
    print_phase "1" "🔍 Hardware Detection"
    print_box_start
    
    # CPU Detection
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    PLATFORM_CONFIG[cpu_cores]=$cpu_cores
    print_box_line "CPU: $cpu_model ($cpu_cores cores)"
    
    # RAM Detection
    local ram_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_total_gb=$((ram_total_kb / 1024 / 1024))
    local ram_available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local ram_available_gb=$((ram_available_kb / 1024 / 1024))
    PLATFORM_CONFIG[ram_total_gb]=$ram_total_gb
    print_box_line "RAM: ${ram_total_gb}GB (${ram_available_gb}GB available)"
    
    # GPU Detection
    PLATFORM_CONFIG[gpu_available]="false"
    PLATFORM_CONFIG[gpu_name]="None"
    PLATFORM_CONFIG[gpu_memory]="0"
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
            local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
            gpu_memory=$((gpu_memory / 1024))
            PLATFORM_CONFIG[gpu_available]="true"
            PLATFORM_CONFIG[gpu_name]="$gpu_name"
            PLATFORM_CONFIG[gpu_memory]="$gpu_memory"
            print_box_line "GPU: $gpu_name (${gpu_memory}GB VRAM) ✓"
        else
            print_box_line "GPU: No GPU detected ❌"
        fi
    else
        print_box_line "GPU: nvidia-smi not found ❌"
    fi
    
    # Storage Detection
    local storage_device=$(lsblk -d -o NAME,TYPE | grep disk | grep nvme | head -n1 | awk '{print $1}')
    if [[ -n "$storage_device" ]]; then
        local storage_size=$(lsblk -b -d -o SIZE,NAME | grep "$storage_device" | awk '{print $1/1024/1024/1024}')
        PLATFORM_CONFIG[storage_device]="/dev/$storage_device"
        PLATFORM_CONFIG[storage_size_gb]="${storage_size%.*}"
        print_box_line "Storage: ${storage_size%.*}GB EBS (gp3)"
    else
        print_box_line "Storage: Detection failed ❌"
        PLATFORM_CONFIG[storage_device]=""
        PLATFORM_CONFIG[storage_size_gb]="0"
    fi
    
    # Network Detection
    local public_ip=$(curl -s ifconfig.me || echo "Unknown")
    PLATFORM_CONFIG[public_ip]="$public_ip"
    print_box_line "Public IP: $public_ip"
    
    print_box_end
}

#------------------------------------------------------------------------------
# Phase 2: Dependency Installation
#------------------------------------------------------------------------------

install_dependencies() {
    print_phase "2" "📦 Dependency Installation"
    
    # Update system
    print_info "Updating system packages..."
    sudo apt-get update -qq > /dev/null 2>&1
    sudo apt-get upgrade -y -qq > /dev/null 2>&1
    print_success "System packages updated"
    
    # Install essential tools
    print_info "Installing essential tools..."
    sudo apt-get install -y -qq \
        curl wget git jq htop net-tools \
        ca-certificates gnupg lsb-release \
        build-essential python3-pip > /dev/null 2>&1
    print_success "Essential tools installed"
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        print_info "Installing Docker Engine..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh > /dev/null 2>&1
        sudo usermod -aG docker ubuntu
        sudo systemctl enable docker > /dev/null 2>&1
        sudo systemctl start docker > /dev/null 2>&1
        rm /tmp/get-docker.sh
    fi
    local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    PLATFORM_CONFIG[docker_version]="$docker_version"
    print_success "Docker Engine $docker_version installed"
    
    # Install Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_info "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose > /dev/null 2>&1
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    local compose_version=$(docker-compose --version | awk '{print $4}' | tr -d 'v,')
    PLATFORM_CONFIG[compose_version]="$compose_version"
    print_success "Docker Compose $compose_version installed"
    
    # Configure NVIDIA Container Toolkit
    if [[ "${PLATFORM_CONFIG[gpu_available]}" == "true" ]]; then
        if ! dpkg -l | grep -q nvidia-container-toolkit; then
            print_info "Installing NVIDIA Container Toolkit..."
            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
            sudo apt-get update -qq > /dev/null 2>&1
            sudo apt-get install -y -qq nvidia-container-toolkit > /dev/null 2>&1
            sudo nvidia-ctk runtime configure --runtime=docker > /dev/null 2>&1
            sudo systemctl restart docker
            print_success "NVIDIA Container Toolkit configured"
        else
            print_success "NVIDIA Container Toolkit already configured"
        fi
    fi
    
    # Install Node.js (for Signal CLI and n8n)
    if ! command -v node &> /dev/null; then
        print_info "Installing Node.js LTS..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - > /dev/null 2>&1
        sudo apt-get install -y -qq nodejs > /dev/null 2>&1
        print_success "Node.js $(node --version) installed"
    else
        print_success "Node.js $(node --version) already installed"
    fi
}

#------------------------------------------------------------------------------
# Phase 3: Storage Configuration
#------------------------------------------------------------------------------

configure_storage() {
    print_phase "3" "💾 Storage Configuration"
    
    # Create base directories
    sudo mkdir -p "$DATA_DIR"
    
    # Mount EBS volume
    if [[ -n "${PLATFORM_CONFIG[storage_device]}" ]] && [[ "${PLATFORM_CONFIG[storage_device]}" != "" ]]; then
        if ! mountpoint -q "$DATA_DIR"; then
            print_info "Mounting EBS volume..."
            local device="${PLATFORM_CONFIG[storage_device]}"
            
            # Check if filesystem exists
            if ! sudo file -s "$device" | grep -q filesystem; then
                print_info "Creating ext4 filesystem..."
                sudo mkfs -t ext4 "$device" > /dev/null 2>&1
            fi
            
            sudo mount "$device" "$DATA_DIR"
            
            # Add to fstab
            local uuid=$(sudo blkid -s UUID -o value "$device")
            if ! grep -q "$uuid" /etc/fstab 2>/dev/null; then
                echo "UUID=$uuid $DATA_DIR ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
            fi
            print_success "EBS volume mounted at $DATA_DIR"
        else
            print_success "EBS volume already mounted"
        fi
    fi
    
    # Create comprehensive directory structure
    print_info "Creating directory structure..."
    
    local directories=(
        # Core services
        "$CONFIG_DIR"
        "$DATA_DIR/compose"
        "$DATA_DIR/traefik/config"
        "$DATA_DIR/traefik/letsencrypt"
        
        # LLM services
        "$DATA_DIR/ollama/models"
        "$DATA_DIR/open-webui/data"
        "$DATA_DIR/anythingllm/storage"
        "$DATA_DIR/dify/data"
        "$DATA_DIR/librechat/data"
        
        # Vector databases
        "$DATA_DIR/qdrant/storage"
        "$DATA_DIR/weaviate/data"
        "$DATA_DIR/milvus/data"
        
        # Workflow & automation
        "$DATA_DIR/n8n/data"
        "$DATA_DIR/n8n/.n8n"
        
        # AI generation
        "$DATA_DIR/stable-diffusion/models"
        "$DATA_DIR/stable-diffusion/outputs"
        "$DATA_DIR/comfyui/models"
        "$DATA_DIR/comfyui/outputs"
        
        # Signal API
        "$DATA_DIR/signal-cli/config"
        "$DATA_DIR/signal-cli/data"
        
        # Google Drive
        "$DATA_DIR/gdrive/credentials"
        "$DATA_DIR/gdrive/sync"
        
        # LiteLLM
        "$DATA_DIR/litellm/config"
        "$DATA_DIR/litellm/logs"
        
        # Backups & logs
        "$DATA_DIR/backups"
        "$DATA_DIR/logs"
    )
    
    for dir in "${directories[@]}"; do
        sudo mkdir -p "$dir"
    done
    
    print_success "Directory structure created (${#directories[@]} directories)"
    
    # Set ownership
    sudo chown -R ubuntu:ubuntu "$DATA_DIR"
    sudo chmod -R 755 "$DATA_DIR"
    print_success "Permissions configured"
}

#------------------------------------------------------------------------------
# Phase 4: Network Setup
#------------------------------------------------------------------------------

setup_network() {
    print_phase "4" "🌐 Network Setup"
    
    # Create Docker network
    if ! docker network ls | grep -q ai_platform; then
        docker network create \
            --driver bridge \
            --subnet=172.28.0.0/16 \
            --opt com.docker.network.bridge.name=br-ai-platform \
            ai_platform > /dev/null 2>&1
        print_success "Docker network 'ai_platform' created"
    else
        print_success "Docker network 'ai_platform' exists"
    fi
    
    # Check port availability
    print_info "Checking port availability..."
    local required_ports=(80 443 3000 5678 6333 7860 8080 11434)
    local ports_ok=true
    
    for port in "${required_ports[@]}"; do
        if ! check_port_available "$port"; then
            print_warning "Port $port is already in use"
            ports_ok=false
        fi
    done
    
    if $ports_ok; then
        print_success "All required ports available"
    else
        print_warning "Some ports are in use - may need configuration"
    fi
    
    # Configure Traefik
    print_info "Configuring Traefik reverse proxy..."
    
    cat > "$DATA_DIR/traefik/traefik.yml" <<'EOF'
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: ai_platform
  file:
    directory: "/etc/traefik/config"
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO
  
accessLog:
  filePath: "/var/log/traefik/access.log"
EOF
    
    print_success "Traefik configuration created"
}

#------------------------------------------------------------------------------
# Phase 5: Signal API Configuration
#------------------------------------------------------------------------------

configure_signal_api() {
    print_phase "5" "📱 Signal API Configuration"
    
    echo ""
    local use_signal=$(prompt_input "Enable Signal API integration? (yes/no)" "no")
    
    if [[ "$use_signal" =~ ^[Yy] ]]; then
        PLATFORM_CONFIG[signal_enabled]="true"
        
        # Install Signal CLI
        print_info "Installing Signal CLI..."
        
        if [[ ! -d "$DATA_DIR/signal-cli" ]]; then
            cd /tmp
            wget -q https://github.com/AsamK/signal-cli/releases/download/v0.12.8/signal-cli-0.12.8-Linux.tar.gz
            tar xf signal-cli-0.12.8-Linux.tar.gz -C "$DATA_DIR/"
            mv "$DATA_DIR/signal-cli-0.12.8" "$DATA_DIR/signal-cli-bin"
            rm signal-cli-0.12.8-Linux.tar.gz
            cd - > /dev/null
        fi
        print_success "Signal CLI installed"
        
        # Configuration
        local phone_number=$(prompt_input "Signal phone number (with country code, e.g., +1234567890)" "")
        PLATFORM_CONFIG[signal_phone]="$phone_number"
        
        if [[ -n "$phone_number" ]]; then
            print_info "Registering Signal number..."
            print_warning "You will receive a verification code via SMS"
            
            "$DATA_DIR/signal-cli-bin/bin/signal-cli" -a "$phone_number" register > /dev/null 2>&1 || true
            
            local verification_code=$(prompt_input "Enter verification code" "")
            "$DATA_DIR/signal-cli-bin/bin/signal-cli" -a "$phone_number" verify "$verification_code" > /dev/null 2>&1 || true
            
            print_success "Signal API configured"
        fi
    else
        PLATFORM_CONFIG[signal_enabled]="false"
        print_info "Signal API skipped"
    fi
}

#------------------------------------------------------------------------------
# Phase 6: Google Drive Integration
#------------------------------------------------------------------------------

configure_google_drive() {
    print_phase "6" "☁️ Google Drive Integration"
    
    echo ""
    local use_gdrive=$(prompt_input "Enable Google Drive backup? (yes/no)" "no")
    
    if [[ "$use_gdrive" =~ ^[Yy] ]]; then
        PLATFORM_CONFIG[gdrive_enabled]="true"
        
        print_info "Installing rclone..."
        if ! command -v rclone &> /dev/null; then
            curl -s https://rclone.org/install.sh | sudo bash > /dev/null 2>&1
        fi
        print_success "rclone installed"
        
        print_warning "Manual step required:"
        echo "  1. Run: rclone config"
        echo "  2. Create a new remote named 'gdrive'"
        echo "  3. Select Google Drive"
        echo "  4. Follow OAuth flow"
        echo ""
        
        local gdrive_folder=$(prompt_input "Google Drive backup folder name" "ai-platform-backups")
        PLATFORM_CONFIG[gdrive_folder]="$gdrive_folder"
        
        # Create backup script
        cat > "$DATA_DIR/scripts/backup-to-gdrive.sh" <<'EOF'
#!/bin/bash
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="platform-backup-$BACKUP_DATE.tar.gz"
cd /mnt/data
tar czf "/tmp/$BACKUP_NAME" \
    --exclude='./ollama/models' \
    --exclude='./stable-diffusion/models' \
    ./config ./compose
rclone copy "/tmp/$BACKUP_NAME" "gdrive:ai-platform-backups/"
rm "/tmp/$BACKUP_NAME"
EOF
        chmod +x "$DATA_DIR/scripts/backup-to-gdrive.sh"
        
        print_success "Google Drive backup configured"
    else
        PLATFORM_CONFIG[gdrive_enabled]="false"
        print_info "Google Drive integration skipped"
    fi
}

#------------------------------------------------------------------------------
# Phase 7: Vector Database Selection
#------------------------------------------------------------------------------

configure_vector_db() {
    print_phase "7" "🗄️ Vector Database Selection"
    
    echo ""
    local vector_db=$(prompt_select "Select vector database:" \
        "Qdrant (recommended)" \
        "Weaviate" \
        "Milvus" \
        "Skip")
    
    case "$vector_db" in
        "Qdrant"*)
            PLATFORM_CONFIG[vector_db]="qdrant"
            PLATFORM_CONFIG[vector_db_port]="6333"
            print_success "Qdrant selected"
            ;;
        "Weaviate"*)
            PLATFORM_CONFIG[vector_db]="weaviate"
            PLATFORM_CONFIG[vector_db_port]="8080"
            print_success "Weaviate selected"
            ;;
        "Milvus"*)
            PLATFORM_CONFIG[vector_db]="milvus"
            PLATFORM_CONFIG[vector_db_port]="19530"
            print_success "Milvus selected"
            ;;
        *)
            PLATFORM_CONFIG[vector_db]="none"
            print_info "Vector database skipped"
            ;;
    esac
}

#------------------------------------------------------------------------------
# Phase 8: LLM Routing Strategy (LiteLLM)
#------------------------------------------------------------------------------

configure_llm_routing() {
    print_phase "8" "🧠 LLM Routing Strategy (LiteLLM)"
    
    echo ""
    local use_litellm=$(prompt_input "Enable LiteLLM routing? (yes/no)" "yes")
    
    if [[ "$use_litellm" =~ ^[Yy] ]]; then
        PLATFORM_CONFIG[litellm_enabled]="true"
        
        # Provider selection
        echo ""
        print_info "Select LLM providers (comma-separated numbers):"
        echo "  1. OpenAI"
        echo "  2. Anthropic (Claude)"
        echo "  3. Local Ollama"
        echo "  4. Azure OpenAI"
        echo "  5. Google (Gemini)"
        
        local providers=$(prompt_input "Providers" "1,3")
        
        # API keys
        local openai_key=""
        local anthropic_key=""
        local azure_key=""
        local google_key=""
        
        if [[ "$providers" =~ "1" ]]; then
            openai_key=$(prompt_input "OpenAI API Key" "")
        fi
        if [[ "$providers" =~ "2" ]]; then
            anthropic_key=$(prompt_input "Anthropic API Key" "")
        fi
        if [[ "$providers" =~ "4" ]]; then
            azure_key=$(prompt_input "Azure OpenAI API Key" "")
        fi
        if [[ "$providers" =~ "5" ]]; then
            google_key=$(prompt_input "Google API Key" "")
        fi
        
        # Create LiteLLM config
        cat > "$DATA_DIR/litellm/config/config.yaml" <<EOF
model_list:
EOF
        
        if [[ -n "$openai_key" ]]; then
            cat >> "$DATA_DIR/litellm/config/config.yaml" <<EOF
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: $openai_key
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: $openai_key
EOF
        fi
        
        if [[ -n "$anthropic_key" ]]; then
            cat >> "$DATA_DIR/litellm/config/config.yaml" <<EOF
  - model_name: claude-3
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: $anthropic_key
EOF
        fi
        
        if [[ "$providers" =~ "3" ]]; then
            cat >> "$DATA_DIR/litellm/config/config.yaml" <<EOF
  - model_name: llama2
    litellm_params:
      model: ollama/llama2
      api_base: http://ollama:11434
EOF
        fi
        
        cat >> "$DATA_DIR/litellm/config/config.yaml" <<'EOF'

litellm_settings:
  drop_params: true
  set_verbose: true
  request_timeout: 600
  fallbacks:
    - ["gpt-4", "gpt-3.5-turbo", "llama2"]
  
router_settings:
  routing_strategy: usage-based-routing
  redis_host: redis
  redis_port: 6379
EOF
        
        print_success "LiteLLM configuration created"
    else
        PLATFORM_CONFIG[litellm_enabled]="false"
        print_info "LiteLLM routing skipped"
    fi
}

#------------------------------------------------------------------------------
# Phase 9: OpenClaw UI Selection
#------------------------------------------------------------------------------

configure_ui_selection() {
    print_phase "9" "🖥️ UI Selection"
    
    echo ""
    print_info "Select UIs to deploy (comma-separated numbers):"
    echo "  1. Open WebUI (Ollama web interface)"
    echo "  2. AnythingLLM (Document chat)"
    echo "  3. Dify (Workflow builder)"
    echo "  4. LibreChat (Multi-provider chat)"
    echo "  5. All of the above"
    
    local ui_selection=$(prompt_input "UIs" "1,2,3")
    
    PLATFORM_CONFIG[ui_openwebui]="false"
    PLATFORM_CONFIG[ui_anythingllm]="false"
    PLATFORM_CONFIG[ui_dify]="false"
    PLATFORM_CONFIG[ui_librechat]="false"
    
    if [[ "$ui_selection" =~ "5" ]] || [[ "$ui_selection" =~ "1" ]]; then
        PLATFORM_CONFIG[ui_openwebui]="true"
        print_success "Open WebUI enabled"
    fi
    if [[ "$ui_selection" =~ "5" ]] || [[ "$ui_selection" =~ "2" ]]; then
        PLATFORM_CONFIG[ui_anythingllm]="true"
        print_success "AnythingLLM enabled"
    fi
    if [[ "$ui_selection" =~ "5" ]] || [[ "$ui_selection" =~ "3" ]]; then
        PLATFORM_CONFIG[ui_dify]="true"
        print_success "Dify enabled"
    fi
    if [[ "$ui_selection" =~ "5" ]] || [[ "$ui_selection" =~ "4" ]]; then
        PLATFORM_CONFIG[ui_librechat]="true"
        print_success "LibreChat enabled"
    fi
}

#------------------------------------------------------------------------------
# Phase 10: AnythingLLM Configuration
#------------------------------------------------------------------------------

configure_anythingllm() {
    if [[ "${PLATFORM_CONFIG[ui_anythingllm]}" == "true" ]]; then
        print_phase "10" "📚 AnythingLLM Configuration"
        
        # Create default workspace
        mkdir -p "$DATA_DIR/anythingllm/storage/documents"
        mkdir -p "$DATA_DIR/anythingllm/storage/vector-cache"
        mkdir -p "$DATA_DIR/anythingllm/storage/lancedb"
        
        # Set environment variables
        PLATFORM_CONFIG[anythingllm_storage]="$DATA_DIR/anythingllm/storage"
        
        print_success "AnythingLLM storage configured"
    fi
}

#------------------------------------------------------------------------------
# Phase 11: Dify Configuration
#------------------------------------------------------------------------------

configure_dify() {
    if [[ "${PLATFORM_CONFIG[ui_dify]}" == "true" ]]; then
        print_phase "11" "⚙️ Dify Configuration"
        
        # Generate secret keys
        local dify_secret=$(openssl rand -hex 32)
        PLATFORM_CONFIG[dify_secret_key]="$dify_secret"
        
        # Create database directories
        mkdir -p "$DATA_DIR/dify/data/postgres"
        mkdir -p "$DATA_DIR/dify/data/redis"
        
        print_success "Dify configuration created"
    fi
}

#------------------------------------------------------------------------------
# Phase 12: Environment File Generation
#------------------------------------------------------------------------------

generate_env_file() {
    print_phase "12" "📝 Environment Configuration"
    
    print_info "Generating .env file..."
    
    cat > "$ENV_FILE" <<EOF
# AI Platform Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# System
PLATFORM_ID=${PLATFORM_CONFIG[platform_id]:-unknown}
DATA_DIR=$DATA_DIR
COMPOSE_PROJECT_NAME=ai_platform

# Hardware
GPU_AVAILABLE=${PLATFORM_CONFIG[gpu_available]:-false}
CPU_CORES=${PLATFORM_CONFIG[cpu_cores]:-4}

# Network
PUBLIC_IP=${PLATFORM_CONFIG[public_ip]:-unknown}

# Signal API
SIGNAL_ENABLED=${PLATFORM_CONFIG[signal_enabled]:-false}
SIGNAL_PHONE=${PLATFORM_CONFIG[signal_phone]:-}

# Google Drive
GDRIVE_ENABLED=${PLATFORM_CONFIG[gdrive_enabled]:-false}
GDRIVE_FOLDER=${PLATFORM_CONFIG[gdrive_folder]:-}

# Vector Database
VECTOR_DB=${PLATFORM_CONFIG[vector_db]:-none}
VECTOR_DB_PORT=${PLATFORM_CONFIG[vector_db_port]:-6333}

# LiteLLM
LITELLM_ENABLED=${PLATFORM_CONFIG[litellm_enabled]:-false}

# UIs
UI_OPENWEBUI=${PLATFORM_CONFIG[ui_openwebui]:-false}
UI_ANYTHINGLLM=${PLATFORM_CONFIG[ui_anythingllm]:-false}
UI_DIFY=${PLATFORM_CONFIG[ui_dify]:-false}
UI_LIBRECHAT=${PLATFORM_CONFIG[ui_librechat]:-false}

# Dify
DIFY_SECRET_KEY=${PLATFORM_CONFIG[dify_secret_key]:-}

# Ports
TRAEFIK_PORT=80
TRAEFIK_SECURE_PORT=443
OLLAMA_PORT=11434
OPENWEBUI_PORT=3000
N8N_PORT=5678
QDRANT_PORT=6333
EOF

    chmod 600 "$ENV_FILE"
    print_success "Environment file created at $ENV_FILE"
}

#------------------------------------------------------------------------------
# Phase 13: Metadata Generation
#------------------------------------------------------------------------------

generate_metadata() {
    print_phase "13" "📋 Platform Metadata"
    
    # Generate platform ID
    PLATFORM_CONFIG[platform_id]="ai-prod-$(date +%Y%m%d)-$(openssl rand -hex 3)"
    local setup_date=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    # Create metadata JSON
    cat > "$METADATA_FILE" <<EOF
{
  "platform_id": "${PLATFORM_CONFIG[platform_id]}",
  "setup_date": "$setup_date",
  "hardware": {
    "cpu_cores": ${PLATFORM_CONFIG[cpu_cores]},
    "ram_total_gb": ${PLATFORM_CONFIG[ram_total_gb]},
    "gpu_available": ${PLATFORM_CONFIG[gpu_available]},
    "gpu_name": "${PLATFORM_CONFIG[gpu_name]}",
    "gpu_memory_gb": ${PLATFORM_CONFIG[gpu_memory]},
    "storage_size_gb": ${PLATFORM_CONFIG[storage_size_gb]}
  },
  "software": {
    "docker_version": "${PLATFORM_CONFIG[docker_version]}",
    "compose_version": "${PLATFORM_CONFIG[compose_version]}"
  },
  "configuration": {
    "signal_enabled": ${PLATFORM_CONFIG[signal_enabled]:-false},
    "gdrive_enabled": ${PLATFORM_CONFIG[gdrive_enabled]:-false},
    "vector_db": "${PLATFORM_CONFIG[vector_db]:-none}",
    "litellm_enabled": ${PLATFORM_CONFIG[litellm_enabled]:-false},
    "ui_openwebui": ${PLATFORM_CONFIG[ui_openwebui]:-false},
    "ui_anythingllm": ${PLATFORM_CONFIG[ui_anythingllm]:-false},
    "ui_dify": ${PLATFORM_CONFIG[ui_dify]:-false},
    "ui_librechat": ${PLATFORM_CONFIG[ui_librechat]:-false}
  },
  "services_deployed": [],
  "last_updated": "$setup_date"
}
EOF
    
    print_box_start
    print_box_line "Platform ID: ${PLATFORM_CONFIG[platform_id]}"
    print_box_line "Setup Date: $setup_date"
    print_box_line "GPU Available: $([ "${PLATFORM_CONFIG[gpu_available]}" == "true" ] && echo "Yes" || echo "No")"
    print_box_line "Vector DB: ${PLATFORM_CONFIG[vector_db]:-None}"
    print_box_line "LiteLLM: $([ "${PLATFORM_CONFIG[litellm_enabled]}" == "true" ] && echo "Enabled" || echo "Disabled")"
    print_box_line "Storage Path: $DATA_DIR"
    print_box_end
    
    print_success "Metadata saved to $METADATA_FILE"
}

#------------------------------------------------------------------------------
# Final Success Summary
#------------------------------------------------------------------------------

print_final_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            ✅ SYSTEM READY FOR DEPLOYMENT                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "  • Platform ID: ${PLATFORM_CONFIG[platform_id]}"
    echo "  • GPU: $([ "${PLATFORM_CONFIG[gpu_available]}" == "true" ] && echo "✓ Available" || echo "✗ Not available")"
    echo "  • Vector DB: ${PLATFORM_CONFIG[vector_db]:-None}"
    echo "  • LiteLLM: $([ "${PLATFORM_CONFIG[litellm_enabled]}" == "true" ] && echo "✓ Enabled" || echo "✗ Disabled")"
    echo "  • Signal API: $([ "${PLATFORM_CONFIG[signal_enabled]}" == "true" ] && echo "✓ Enabled" || echo "✗ Disabled")"
    echo "  • Google Drive: $([ "${PLATFORM_CONFIG[gdrive_enabled]}" == "true" ] && echo "✓ Enabled" || echo "✗ Disabled")"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Review configuration in: $ENV_FILE"
    echo "  2. Run deployment: ${CYAN}./scripts/2-deploy-core.sh${NC}"
    echo ""
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    print_header
    
    detect_hardware
    install_dependencies
    configure_storage
    setup_network
    configure_signal_api
    configure_google_drive
    configure_vector_db
    configure_llm_routing
    configure_ui_selection
    configure_anythingllm
    configure_dify
    generate_env_file
    generate_metadata
    
    print_final_success
}

# Run main function
main "$@"
