#!/bin/bash
# 1-setup-system.sh - System preparation and configuration collection

SCRIPT_DIR=" $ (cd " $ (dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/mnt/data"
METADATA_DIR=" $ DATA_ROOT/metadata"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e " $ {GREEN}[INFO]${NC}  $ 1"; }
log_warn() { echo -e " $ {YELLOW}[WARN]${NC}  $ 1"; }
log_error() { echo -e " $ {RED}[ERROR]${NC}  $ 1"; }
log_step() { echo -e " $ {CYAN}[STEP]${NC}  $ 1"; }

show_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════╗
║  🚀 AIPlatformAutomation - System Setup v76.5.0       ║
╚════════════════════════════════════════════════════════╝
EOF
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if [ " $ EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Detect real user
    if [ -n "${SUDO_USER:-}" ]; then
        REAL_USER=" $ SUDO_USER"
    else
        REAL_USER=" $ USER"
    fi
    
    PUID= $ (id -u " $ REAL_USER")
    PGID= $ (id -g " $ REAL_USER")
    
    log_info "Running as: root (for  $ REAL_USER, UID= $ PUID, GID= $ PGID)"
}

detect_hardware() {
    log_step "🔍 Detecting hardware configuration..."
    
    CPU_CORES= $ (nproc)
    CPU_MODEL= $ (lscpu | grep "Model name" | cut -d: -f2 | xargs)
    RAM_GB= $ (free -g | awk '/^Mem:/{print  $ 2}')
    
    # GPU detection
    if command -v nvidia-smi &>/dev/null; then
        GPU_AVAILABLE="true"
        GPU_MODEL= $ (nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        GPU_MEMORY= $ (nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        GPU_DRIVER= $ (nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    else
        GPU_AVAILABLE="false"
        GPU_MODEL="None"
        GPU_MEMORY="0"
        GPU_DRIVER="N/A"
    fi
    
    cat << EOF

┌────────────────────────────────────────────────────┐
│   💻 HARDWARE DETECTION SUMMARY                    │
└────────────────────────────────────────────────────┘

  🖥️  CPU: $CPU_MODEL
  ⚙️  Cores: $CPU_CORES
  🧠 RAM: ${RAM_GB}GB
  🎮 GPU:  $ ([ " $ GPU_AVAILABLE" = "true" ] && echo "✅  $ GPU_MODEL ( $ {GPU_MEMORY}MB, Driver:  $ GPU_DRIVER)" || echo "❌ None detected")

EOF

    # Save to metadata
    mkdir -p " $ METADATA_DIR"
    cat > " $ METADATA_DIR/system_info.json" << EOJSON
{
  "cpu": {
    "model": " $ CPU_MODEL",
    "cores": $CPU_CORES
  },
  "ram_gb": $RAM_GB,
  "gpu": {
    "available":  $ GPU_AVAILABLE,
    "model": " $ GPU_MODEL",
    "memory_mb":  $ GPU_MEMORY,
    "driver": " $ GPU_DRIVER"
  },
  "timestamp": " $ (date -Iseconds)"
}
EOJSON
}

mount_ebs_volume() {
    log_step "💾 EBS Volume Detection and Mounting"
    
    # Check if /mnt/data already mounted
    if mountpoint -q " $ DATA_ROOT"; then
        log_info "/mnt/data already mounted"
        DEVICE= $ (df " $ DATA_ROOT" | tail -1 | awk '{print $1}')
        log_info "Current device:  $ DEVICE"
        return 0
    fi
    
    # Detect unmounted block devices
    ROOT_DEVICE= $ (lsblk -no PKNAME  $ (findmnt -n -o SOURCE /) | head -1)
    AVAILABLE_DEVICES= $ (lsblk -ndo NAME,SIZE,TYPE | grep disk | grep -v " $ ROOT_DEVICE" | grep -v "loop")
    
    if [ -z " $ AVAILABLE_DEVICES" ]; then
        log_warn "No additional block devices detected"
        log_info "Creating /mnt/data on root filesystem..."
        mkdir -p " $ DATA_ROOT"
        chown " $ PUID: $ PGID" " $ DATA_ROOT"
        return 0
    fi
    
    cat << 'EOF'

📦 Available Block Devices:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    
    echo " $ AVAILABLE_DEVICES" | nl -w2 -s') ' -v1
    echo
    
    while true; do
        read -p "Enter device number to mount at /mnt/data (or 0 to use root FS): " device_choice
        
        if [ " $ device_choice" = "0" ]; then
            mkdir -p " $ DATA_ROOT"
            chown " $ PUID: $ PGID" " $ DATA_ROOT"
            break
        fi
        
        DEVICE_NAME= $ (echo " $ AVAILABLE_DEVICES" | sed -n "${device_choice}p" | awk '{print  $ 1}')
        
        if [ -z " $ DEVICE_NAME" ]; then
            log_error "Invalid selection"
            continue
        fi
        
        DEVICE_PATH="/dev/ $ DEVICE_NAME"
        
        # Check if filesystem exists
        if ! blkid " $ DEVICE_PATH" &>/dev/null; then
            log_warn "No filesystem detected on  $ DEVICE_PATH"
            read -p "Format as ext4? [y/N]: " format_confirm
            
            if [[ " $ format_confirm" =~ ^[Yy]$ ]]; then
                log_info "Creating ext4 filesystem..."
                mkfs.ext4 -F " $ DEVICE_PATH"
            else
                continue
            fi
        fi
        
        # Mount
        mkdir -p " $ DATA_ROOT"
        mount " $ DEVICE_PATH" " $ DATA_ROOT"
        
        # Verify mount
        if ! mountpoint -q "$DATA_ROOT"; then
            log_error "Failed to mount $DEVICE_PATH"
            continue
        fi
        
        log_info "✅ Successfully mounted $DEVICE_PATH at  $ DATA_ROOT"
        
        # Add to fstab if not present
        if ! grep -q " $ DEVICE_PATH" /etc/fstab; then
            echo "$DEVICE_PATH   $ DATA_ROOT  ext4  defaults,nofail  0  2" >> /etc/fstab
            log_info "Added to /etc/fstab for persistent mounting"
        fi
        
        # Set ownership
        chown -R " $ PUID: $ PGID" " $ DATA_ROOT"
        break
    done
}

install_system_packages() {
    log_step "📦 Installing system dependencies..."
    
    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        jq \
        git \
        gnupg \
        ca-certificates \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        qrencode \
        rclone
    
    log_info "✅ System packages installed"
}

install_docker() {
    if command -v docker &>/dev/null; then
        log_info "Docker already installed:  $ (docker --version)"
        return 0
    fi
    
    log_step "🐳 Installing Docker..."
    
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker " $ REAL_USER"
    
    log_info "✅ Docker installed:  $ (docker --version)"
}

install_nvidia_toolkit() {
    if [ " $ GPU_AVAILABLE" != "true" ]; then
        return 0
    fi
    
    log_step "🎮 Installing NVIDIA Container Toolkit..."
    
    distribution=$(. /etc/os-release;echo  $ ID $ VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    
    # Test
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_info "✅ NVIDIA Container Toolkit installed and verified"
    else
        log_warn "⚠️  NVIDIA Container Toolkit installed but GPU not accessible in containers"
    fi
}

install_ollama() {
    if command -v ollama &>/dev/null; then
        log_info "Ollama already installed:  $ (ollama --version)"
        return 0
    fi
    
    log_step "🦙 Installing Ollama..."
    
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Start ollama service
    systemctl enable ollama
    systemctl start ollama
    
    # Wait for service
    sleep 5
    
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        log_info "✅ Ollama installed and running"
    else
        log_warn "⚠️  Ollama installed but service not responding"
    fi
}

# ============================================================================
# INTERACTIVE CONFIGURATION QUESTIONNAIRE
# ============================================================================

ask_network_configuration() {
    log_step "🌐 Network Configuration"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🌐 DOMAIN & NETWORK SETUP                        │
└────────────────────────────────────────────────────┘

EOF
    
    read -p "Enter domain name (or 'localhost' for local-only): " DOMAIN
    DOMAIN=" $ {DOMAIN:-localhost}"
    
    if [ "$DOMAIN" != "localhost" ]; then
        cat << 'EOF'

Public Access Method:

  1) 🔐 SWAG (Secure Web Application Gateway) - Let's Encrypt + nginx
  2) 🎛️  Nginx Proxy Manager - Web UI for proxy management
  3) ☁️  Cloudflare Tunnel - Zero-trust access
  4) ❌ None (local network only)

EOF
        
        while true; do
            read -p "Select proxy method [1-4]: " proxy_choice
            case  $ proxy_choice in
                1) PROXY_TYPE="swag"; break ;;
                2) PROXY_TYPE="nginx-proxy-manager"; break ;;
                3) PROXY_TYPE="cloudflare-tunnel"; break ;;
                4) PROXY_TYPE="none"; break ;;
                *) log_error "Invalid selection" ;;
            esac
        done
        
        if [ " $ PROXY_TYPE" != "none" ]; then
            read -p "Enter email for Let's Encrypt / notifications: " PROXY_EMAIL
        fi
    else
        PROXY_TYPE="none"
    fi
    
    # Save metadata
    cat > " $ METADATA_DIR/network_config.json" << EOJSON
{
  "domain": " $ DOMAIN",
  "proxy_type": " $ PROXY_TYPE",
  "proxy_email": " $ {PROXY_EMAIL:-}",
  "local_only":  $ ([ " $ DOMAIN" = "localhost" ] && echo "true" || echo "false")
}
EOJSON
    
    log_info "✅ Network configuration saved"
}

ask_service_selection() {
    log_step "🎯 Service Selection"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🎯 AI PLATFORM SERVICES                          │
└────────────────────────────────────────────────────┘

Select services to deploy (space-separated numbers):

  1) 🌐 OpenWebUI           - Modern LLM interface with RAG
  2) 🧠 AnythingLLM         - Document-focused AI assistant
  3) 🔧 Dify                - LLM application development platform
  4) 🔄 n8n                 - Workflow automation
  5) 💬 Flowise             - Drag-and-drop LLM chains
  6) 🦁 OpenClaw UI         - Channel-based AI (requires Signal)
  7) 🎨 ComfyUI             - Image generation workflows (requires GPU)

EOF
    
    read -p "Enter selections (e.g., 1 2 3 6): " selections
    
    SELECTED_SERVICES=()
    REQUIRES_SIGNAL=false
    
    for num in $selections; do
        case  $ num in
            1) SELECTED_SERVICES+=("openwebui") ;;
            2) SELECTED_SERVICES+=("anythingllm") ;;
            3) SELECTED_SERVICES+=("dify") ;;
            4) SELECTED_SERVICES+=("n8n") ;;
            5) SELECTED_SERVICES+=("flowise") ;;
            6)
                SELECTED_SERVICES+=("openclaw")
                REQUIRES_SIGNAL=true
                ;;
            7)
                if [ " $ GPU_AVAILABLE" = "true" ]; then
                    SELECTED_SERVICES+=("comfyui")
                else
                    log_warn "ComfyUI requires GPU - skipping"
                fi
                ;;
        esac
    done
    
    # Always include infrastructure services
    INFRASTRUCTURE_SERVICES=("postgres" "redis" "ollama" "litellm")
    
    log_info "Selected: ${SELECTED_SERVICES[*]}"
    
    # Save metadata
    cat > "$METADATA_DIR/selected_services.json" << EOJSON
{
  "infrastructure":  $ (printf '%s\n' " $ {INFRASTRUCTURE_SERVICES[@]}" | jq -R . | jq -s .),
  "applications":  $ (printf '%s\n' " $ {SELECTED_SERVICES[@]}" | jq -R . | jq -s .),
  "requires_signal":  $ REQUIRES_SIGNAL
}
EOJSON
}

ask_vectordb_selection() {
    log_step "🗄️  Vector Database Selection"
    
    # Check if any service needs vector DB
    NEEDS_VECTORDB=false
    for service in " $ {SELECTED_SERVICES[@]}"; do
        if [[ " $ service" =~ ^(anythingllm|dify) $  ]]; then
            NEEDS_VECTORDB=true
            break
        fi
    done
    
    if [ " $ NEEDS_VECTORDB" = "false" ]; then
        log_info "No services require vector database - skipping"
        echo '{"type": "none"}' > " $ METADATA_DIR/vectordb_config.json"
        return 0
    fi
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🗄️  VECTOR DATABASE SELECTION                    │
└────────────────────────────────────────────────────┘

  1) 📦 Qdrant       - Rust-based, fast, recommended for production
  2) 🐘 Milvus       - Scalable, feature-rich
  3) 🎨 ChromaDB     - Python-based, simple
  4) 🔍 Weaviate     - GraphQL API, semantic search

EOF
    
    while true; do
        read -p "Select vector database [1-4]: " vectordb_choice
        case  $ vectordb_choice in
            1) VECTORDB_TYPE="qdrant"; VECTORDB_PORT=6333; break ;;
            2) VECTORDB_TYPE="milvus"; VECTORDB_PORT=19530; break ;;
            3) VECTORDB_TYPE="chromadb"; VECTORDB_PORT=8000; break ;;
            4) VECTORDB_TYPE="weaviate"; VECTORDB_PORT=8080; break ;;
            *) log_error "Invalid selection" ;;
        esac
    done
    
    # Qdrant-specific config
    if [ " $ VECTORDB_TYPE" = "qdrant" ]; then
        read -sp "Set Qdrant API key (or press Enter to skip): " QDRANT_API_KEY
        echo
    fi
    
    # Save metadata
    cat > " $ METADATA_DIR/vectordb_config.json" << EOJSON
{
  "type": " $ VECTORDB_TYPE",
  "port":  $ VECTORDB_PORT,
  "host": "localhost",
  "connection_string": "http://localhost: $ VECTORDB_PORT",
  "api_key": "${QDRANT_API_KEY:-}"
}
EOJSON
    
    log_info "✅ Vector database:  $ VECTORDB_TYPE"
}

ask_llm_providers() {
    log_step "🤖 LLM Provider Configuration"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🤖 EXTERNAL LLM PROVIDERS                        │
└────────────────────────────────────────────────────┘

Select providers (space-separated, or '0' for local-only):

  1) 🧠 OpenAI (GPT-4, GPT-3.5)
  2) 🔷 Google Gemini (Gemini Pro, Ultra)
  3) 🟣 Anthropic Claude (Claude 3)
  4) 🌐 OpenRouter (Multi-provider proxy)
  5) ⚡ Groq (Fast inference)
  6) 🦙 Together AI (Open models)
  0) 🏠 Local only (Ollama)

EOF
    
    read -p "Enter selections: " provider_selections
    
    PROVIDERS=()
    
    if [ " $ provider_selections" = "0" ]; then
        log_info "Using local Ollama models only"
    else
        for num in $provider_selections; do
            case  $ num in
                1)
                    read -sp "Enter OpenAI API key: " OPENAI_KEY
                    echo
                    PROVIDERS+=('{"name":"openai","api_key":"'" $ OPENAI_KEY"'","models":["gpt-4","gpt-3.5-turbo"]}')
                    ;;
                2)
                    read -sp "Enter Google Gemini API key: " GEMINI_KEY
                    echo
                    PROVIDERS+=('{"name":"gemini","api_key":"'" $ GEMINI_KEY"'","models":["gemini-pro"]}')
                    ;;
                3)
                    read -sp "Enter Anthropic API key: " ANTHROPIC_KEY
                    echo
                    PROVIDERS+=('{"name":"anthropic","api_key":"'" $ ANTHROPIC_KEY"'","models":["claude-3-opus","claude-3-sonnet"]}')
                    ;;
                4)
                    read -sp "Enter OpenRouter API key: " OPENROUTER_KEY
                    echo
                    PROVIDERS+=('{"name":"openrouter","api_key":"'" $ OPENROUTER_KEY"'","base_url":"https://openrouter.ai/api/v1"}')
                    ;;
                5)
                    read -sp "Enter Groq API key: " GROQ_KEY
                    echo
                    PROVIDERS+=('{"name":"groq","api_key":"'" $ GROQ_KEY"'","models":["mixtral-8x7b","llama2-70b"]}')
                    ;;
                6)
                    read -sp "Enter Together AI API key: " TOGETHER_KEY
                    echo
                    PROVIDERS+=('{"name":"together","api_key":"'"$TOGETHER_KEY"'"}')
                    ;;
            esac
        done
    fi
    
    # Save metadata
    if [ ${#PROVIDERS[@]} -gt 0 ]; then
        PROVIDERS_JSON= $ (printf '%s\n' " $ {PROVIDERS[@]}" | jq -s .)
    else
        PROVIDERS_JSON="[]"
    fi
    
    cat > "$METADATA_DIR/llm_providers.json" << EOJSON
{
  "providers": $PROVIDERS_JSON,
  "local_only": $([ ${#PROVIDERS[@]} -eq 0 ] && echo "true" || echo "false")
}
EOJSON
    
    log_info "✅ Configured ${#PROVIDERS[@]} external providers"
}

ask_litellm_routing_strategy() {
    log_step "🔀 LiteLLM Routing Strategy"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🔀 LITELLM ROUTING STRATEGY                      │
└────────────────────────────────────────────────────┘

  1) 🎯 Simple Routing      - Direct model calls
  2) 🔄 Fallback Routing    - Primary → backup on failure
  3) ⚖️  Load Balancing      - Distribute across providers
  4) 💰 Cost-based          - Route to cheapest available

EOF
    
    while true; do
        read -p "Select routing strategy [1-4]: " routing_choice
        case  $ routing_choice in
            1) ROUTING_STRATEGY="simple"; break ;;
            2) ROUTING_STRATEGY="fallback"; break ;;
            3) ROUTING_STRATEGY="load-balancing"; break ;;
            4) ROUTING_STRATEGY="cost-based"; break ;;
            *) log_error "Invalid selection" ;;
        esac
    done
    
    # Additional config for fallback/load-balancing
    if [[ " $ ROUTING_STRATEGY" =~ ^(fallback|load-balancing)$ ]]; then
        cat << 'EOF'

Provider Priority Configuration:

EOF
        PROVIDER_WEIGHTS=()
        PROVIDERS_LIST= $ (jq -r '.providers[].name' " $ METADATA_DIR/llm_providers.json" 2>/dev/null)
        
        for provider in $PROVIDERS_LIST; do
            read -p "  Weight for  $ provider [1-10, default 5]: " weight
            weight= $ {weight:-5}
            PROVIDER_WEIGHTS+=('{"provider":"'" $ provider"'","weight":'" $ weight"'}')
        done
        
        WEIGHTS_JSON= $ (printf '%s\n' " $ {PROVIDER_WEIGHTS[@]}" | jq -s .)
    else
        WEIGHTS_JSON="[]"
    fi
    
    # Save metadata
    cat > " $ METADATA_DIR/litellm_routing.json" << EOJSON
{
  "strategy": " $ ROUTING_STRATEGY",
  "weights": $WEIGHTS_JSON,
  "retry_policy": {
    "max_retries": 3,
    "timeout_seconds": 60
  }
}
EOJSON
    
    log_info "✅ Routing strategy:  $ ROUTING_STRATEGY"
}

ask_ollama_models() {
    log_step "🦙 Ollama Model Selection"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   🦙 OLLAMA MODELS TO DOWNLOAD                     │
└────────────────────────────────────────────────────┘

Popular models (space-separated numbers):

  1) llama2:7b          (4.1GB)  - General purpose
  2) llama2:13b         (7.4GB)  - Better quality
  3) mistral:7b         (4.1GB)  - Fast & capable
  4) mixtral:8x7b       (26GB)   - MoE, high quality
  5) codellama:7b       (3.8GB)  - Code generation
  6) phi:2              (1.7GB)  - Lightweight
  7) neural-chat:7b     (4.1GB)  - Conversational
  8) Custom model name

  0) Skip (download later)

EOF
    
    read -p "Enter selections: " model_selections
    
    OLLAMA_MODELS=()
    
    if [ " $ model_selections" = "0" ]; then
        log_info "Skipping Ollama model downloads"
    else
        for num in $model_selections; do
            case  $ num in
                1) OLLAMA_MODELS+=("llama2:7b") ;;
                2) OLLAMA_MODELS+=("llama2:13b") ;;
                3) OLLAMA_MODELS+=("mistral:7b") ;;
                4) OLLAMA_MODELS+=("mixtral:8x7b") ;;
                5) OLLAMA_MODELS+=("codellama:7b") ;;
                6) OLLAMA_MODELS+=("phi:2") ;;
                7) OLLAMA_MODELS+=("neural-chat:7b") ;;
                8)
                    read -p "Enter custom model name: " custom_model
                    OLLAMA_MODELS+=(" $ custom_model")
                    ;;
            esac
        done
        
        # Download models
        log_info "Downloading ${#OLLAMA_MODELS[@]} models (this may take a while)..."
        for model in "${OLLAMA_MODELS[@]}"; do
            log_info "Pulling  $ model..."
            ollama pull " $ model"
        done
    fi
    
    # Save metadata
    cat > "$METADATA_DIR/ollama_models.json" << EOJSON
{
  "models":  $ (printf '%s\n' " $ {OLLAMA_MODELS[@]}" | jq -R . | jq -s .),
  "pulled_at": " $ (date -Iseconds)"
}
EOJSON
}

ask_signal_configuration() {
    # Only ask if OpenClaw or Signal-dependent services selected
    if [ " $ REQUIRES_SIGNAL" != "true" ]; then
        log_info "No services require Signal - skipping"
        echo '{"enabled": false}' > " $ METADATA_DIR/signal_config.json"
        return 0
    fi
    
    log_step "📱 Signal API Configuration"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   📱 SIGNAL MESSENGER INTEGRATION                  │
└────────────────────────────────────────────────────┘

Signal-API allows your AI services to send/receive messages via Signal.

⚠️  Requirements:
  • Signal account (phone number)
  • Smartphone with Signal app installed
  • Ability to scan QR code

EOF
    
    read -p "Configure Signal integration now? [Y/n]: " signal_confirm
    
    if [[ " $ signal_confirm" =~ ^[Nn]$ ]]; then
        log_warn "Signal configuration skipped - OpenClaw will not function"
        echo '{"enabled": false, "skipped": true}' > " $ METADATA_DIR/signal_config.json"
        return 0
    fi
    
    # Start signal-api container for pairing
    log_info "Starting Signal-API container for pairing..."
    
    mkdir -p " $ DATA_ROOT/data/signal-api"
    chown -R " $ PUID: $ PGID" " $ DATA_ROOT/data/signal-api"
    
    # Temporary container for pairing
    docker run -d \
        --name signal-api-setup \
        -p 8080:8080 \
        -v " $ DATA_ROOT/data/signal-api:/home/.local/share/signal-cli" \
        -e MODE=native \
        bbernhard/signal-cli-rest-api:latest
    
    sleep 10
    
    cat << 'EOF'

📱 Signal Pairing Methods:

  1) 📱 QR Code (scan with Signal app)
  2) 📞 Phone Number (SMS verification)

EOF
    
    read -p "Select pairing method [1-2]: " pairing_method
    
    case  $ pairing_method in
        1)
            # QR code pairing
            read -p "Enter device name for this AI platform: " DEVICE_NAME
            DEVICE_NAME=" $ {DEVICE_NAME:-AIPlatform}"
            
            log_info "Generating QR code..."
            QR_RESPONSE= $ (curl -s -X GET "http://localhost:8080/v1/qrcodelink?device_name= $ DEVICE_NAME")
            QR_URL= $ (echo " $ QR_RESPONSE" | jq -r '.url')
            
            if [ -z " $ QR_URL" ] || [ " $ QR_URL" = "null" ]; then
                log_error "Failed to generate QR code"
                docker stop signal-api-setup && docker rm signal-api-setup
                return 1
            fi
            
            # Generate QR code in terminal
            echo
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📱 Scan this QR code with Signal app:"
            echo "   Settings → Linked Devices → Link New Device"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo
            qrencode -t ANSIUTF8 " $ QR_URL"
            echo
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            read -p "Press Enter after scanning QR code..."
            
            # Wait for pairing confirmation
            log_info "Waiting for pairing confirmation..."
            sleep 5
            
            # Check if account registered
            ACCOUNTS= $ (curl -s http://localhost:8080/v1/accounts)
            PHONE_NUMBER= $ (echo " $ ACCOUNTS" | jq -r '.[0]' 2>/dev/null)
            
            if [ -z " $ PHONE_NUMBER" ] || [ " $ PHONE_NUMBER" = "null" ]; then
                log_error "Pairing failed or not completed"
                docker stop signal-api-setup && docker rm signal-api-setup
                return 1
            fi
            
            log_info "✅ Successfully paired with Signal:  $ PHONE_NUMBER"
            ;;
            
        2)
            # Phone number pairing
            read -p "Enter your phone number (with country code, e.g., +1234567890): " PHONE_NUMBER
            
            log_info "Registering phone number..."
            curl -X POST "http://localhost:8080/v1/register/ $ PHONE_NUMBER"
            
            read -p "Enter verification code sent to your phone: " VERIFICATION_CODE
            
            curl -X POST "http://localhost:8080/v1/register/ $ PHONE_NUMBER/verify/ $ VERIFICATION_CODE"
            
            log_info "✅ Phone number registered"
            ;;
    esac
    
    # Stop setup container
    docker stop signal-api-setup
    docker rm signal-api-setup
    
    # Generate webhook URL (will be used by OpenClaw)
    SIGNAL_WEBHOOK_URL="http://signal-api:8080"
    
    # Save metadata
    cat > " $ METADATA_DIR/signal_config.json" << EOJSON
{
  "enabled": true,
  "phone_number": " $ PHONE_NUMBER",
  "webhook_url": " $ SIGNAL_WEBHOOK_URL",
  "device_name": " $ {DEVICE_NAME:-}",
  "paired_at": " $ (date -Iseconds)"
}
EOJSON
    
    log_info "✅ Signal configuration saved"
}

ask_gdrive_configuration() {
    log_step "📁 Google Drive Integration"
    
    cat << 'EOF'

┌────────────────────────────────────────────────────┐
│   📁 GOOGLE DRIVE SYNC (Optional)                  │
└────────────────────────────────────────────────────┘

Sync documents from Google Drive for RAG processing.

EOF
    
    read -p "Configure Google Drive sync? [y/N]: " gdrive_confirm
    
    if [[ ! " $ gdrive_confirm" =~ ^[Yy]$ ]]; then
        echo '{"enabled": false}' > " $ METADATA_DIR/gdrive_config.json"
        return 0
    fi
    
    log_info "Setting up rclone for Google Drive..."
    
    mkdir -p " $ DATA_ROOT/config/rclone"
    
    cat << 'EOF'

Follow these steps:
1. Visit: https://rclone.org/drive/
2. Create OAuth credentials for desktop app
3. Copy Client ID and Client Secret

EOF
    
    read -p "Enter Google Drive Client ID: " GDRIVE_CLIENT_ID
    read -sp "Enter Google Drive Client Secret: " GDRIVE_CLIENT_SECRET
    echo
    
    # Run rclone config in interactive mode
    log_info "Opening rclone configuration..."
    log_warn "When prompted:"
    log_warn "  1. Choose 'n' for new remote"
    log_warn "  2. Name it 'gdrive'"
    log_warn "  3. Select 'Google Drive'"
    log_warn "  4. Enter the Client ID and Secret when asked"
    log_warn "  5. Follow OAuth flow in browser"
    
    read -p "Press Enter to continue..."
    
    RCLONE_CONFIG=" $ DATA_ROOT/config/rclone/rclone.conf" rclone config
    
    # Verify configuration
    if RCLONE_CONFIG=" $ DATA_ROOT/config/rclone/rclone.conf" rclone listremotes | grep -q "gdrive:"; then
        log_info "✅ Google Drive configured successfully"
        
        cat > " $ METADATA_DIR/gdrive_config.json" << EOJSON
{
  "enabled": true,
  "remote_name": "gdrive",
  "sync_interval_minutes": 30,
  "local_path": " $ DATA_ROOT/data/gdrive-sync",
  "configured_at": " $ (date -Iseconds)"
}
EOJSON
    else
        log_error "Google Drive configuration failed"
        echo '{"enabled": false, "error": "configuration_failed"}' > " $ METADATA_DIR/gdrive_config.json"
    fi
}

generate_litellm_config() {
    log_step "📝 Generating LiteLLM configuration file..."
    
    mkdir -p " $ DATA_ROOT/config"
    
    # Load metadata
    ROUTING_STRATEGY= $ (jq -r '.strategy' " $ METADATA_DIR/litellm_routing.json")
    PROVIDERS_JSON= $ (jq '.providers' " $ METADATA_DIR/llm_providers.json")
    
    # Start building config
    cat > " $ DATA_ROOT/config/litellm_config.yaml" << 'EOCONFIG'
# LiteLLM Configuration
# Generated by AIPlatformAutomation v76.5.0

model_list:
EOCONFIG
    
    # Add Ollama models
    OLLAMA_MODELS_LIST= $ (jq -r '.models[]' " $ METADATA_DIR/ollama_models.json" 2>/dev/null)
    for model in  $ OLLAMA_MODELS_LIST; do
        cat >> " $ DATA_ROOT/config/litellm_config.yaml" << EOMODEL
  - model_name: ${model//:/_}
    litellm_params:
      model: ollama/${model}
      api_base: http://ollama:11434
EOMODEL
    done
    
    # Add external providers
    echo " $ PROVIDERS_JSON" | jq -c '.[]' | while read -r provider; do
        PROVIDER_NAME= $ (echo " $ provider" | jq -r '.name')
        API_KEY= $ (echo " $ provider" | jq -r '.api_key')
        MODELS= $ (echo "$provider" | jq -r '.models[]?' 2>/dev/null)
        
        for model in  $ MODELS; do
            cat >> " $ DATA_ROOT/config/litellm_config.yaml" << EOMODEL
  - model_name: ${PROVIDER_NAME}_${model//-/_}
    litellm_params:
      model:  $ PROVIDER_NAME/ $ model
      api_key:  $ API_KEY
EOMODEL
        done
    done
    
    # Add routing config
    cat >> " $ DATA_ROOT/config/litellm_config.yaml" << EOROUTING

# Routing Configuration
router_settings:
  routing_strategy: $ROUTING_STRATEGY
  num_retries: 3
  timeout: 60
  fallback_models: true
EOROUTING
    
    log_info "✅ LiteLLM config generated: $DATA_ROOT/config/litellm_config.yaml"
}

show_configuration_summary() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════╗
║          ✅ SYSTEM SETUP COMPLETED                         ║
╚════════════════════════════════════════════════════════════╝

📦 Installed Components:
EOF
    
    echo "  ✓ Docker $(docker --version | cut -d' ' -f3)"
    echo "  ✓ Docker Compose $(docker compose version --short)"
    echo "  ✓ Ollama  $ (ollama --version | head -1)"
    [ " $ GPU_AVAILABLE" = "true" ] && echo "  ✓ NVIDIA Container Toolkit"
    
    echo
    echo "🎯 Selected Services ( $ (jq '.applications | length' " $ METADATA_DIR/selected_services.json")):"
    jq -r '.applications[]' "$METADATA_DIR/selected_services.json" | sed 's/^/  • /'
    
    echo
    echo "🌐 Network:"
    echo "  Domain:  $ (jq -r '.domain' " $ METADATA_DIR/network_config.json")"
    echo "  Proxy:  $ (jq -r '.proxy_type' " $ METADATA_DIR/network_config.json")"
    
    VECTORDB_TYPE= $ (jq -r '.type' " $ METADATA_DIR/vectordb_config.json" 2>/dev/null)
    if [ " $ VECTORDB_TYPE" != "none" ] && [ -n " $ VECTORDB_TYPE" ]; then
        echo
        echo "🗄️  Vector Database:  $ VECTORDB_TYPE"
    fi
    
    echo
    echo "🤖 LLM Providers:"
    PROVIDERS_COUNT= $ (jq '.providers | length' " $ METADATA_DIR/llm_providers.json")
    if [ " $ PROVIDERS_COUNT" -gt 0 ]; then
        jq -r '.providers[].name' "$METADATA_DIR/llm_providers.json" | sed 's/^/  • /'
    else
        echo "  • Local only (Ollama)"
    fi
    
    echo
    echo "🔀 LiteLLM Routing:  $ (jq -r '.strategy' " $ METADATA_DIR/litellm_routing.json")"
    
    SIGNAL_ENABLED= $ (jq -r '.enabled' " $ METADATA_DIR/signal_config.json" 2>/dev/null)
    if [ " $ SIGNAL_ENABLED" = "true" ]; then
        echo
        echo "📱 Signal: ✅ Configured ( $ (jq -r '.phone_number' " $ METADATA_DIR/signal_config.json"))"
    fi
    
    GDRIVE_ENABLED= $ (jq -r '.enabled' " $ METADATA_DIR/gdrive_config.json" 2>/dev/null)
    if [ " $ GDRIVE_ENABLED" = "true" ]; then
        echo "📁 Google Drive: ✅ Configured"
    fi
    
    cat << 'EOF'

💾 Data Structure:
  /mnt/data/
  ├── compose/         (Docker Compose files - will be generated)
  ├── env/             (Environment variables - will be generated)
  ├── data/            (Persistent service data)
  ├── config/          (Service configurations)
  └── metadata/        (Setup configuration)

📝 Configuration Files:
EOF
    
    ls -1 " $ METADATA_DIR"/*.json | sed 's|.*/|  • |'
    
    cat << 'EOF'

🚀 Next Steps:
  1. Review configuration in /mnt/data/metadata/
  2. Run: ./2-deploy-services.sh

EOF
}

main() {
    show_banner
    
    check_prerequisites
    detect_hardware
    mount_ebs_volume
    
    # Create directory structure
    mkdir -p " $ DATA_ROOT"/{compose,env,data,config,metadata,backups}
chown -R "$PUID:$PGID" "$DATA_ROOT"
    
    # Install system packages
    log_step "📦 Installing system packages..."
    apt-get update
    apt-get install -y curl wget jq git qrencode rclone docker.io docker-compose-plugin
    
    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker "$REAL_USER"
    fi
    
    # Install NVIDIA Container Toolkit if GPU present
    if [ "$GPU_AVAILABLE" = "true" ]; then
        log_step "🎮 Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
    fi
    
    # Install Ollama
    if ! command -v ollama &>/dev/null; then
        log_step "🦙 Installing Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
        
        # Start Ollama service
        systemctl enable ollama
        systemctl start ollama
        
        # Wait for Ollama to be ready
        sleep 5
    fi
    
    # Interactive configuration
    ask_network_configuration
    ask_proxy_selection
    ask_service_selection
    ask_vectordb_selection
    ask_llm_providers
    ask_litellm_routing_strategy
    ask_ollama_models
    ask_signal_configuration
    ask_gdrive_configuration
    
    # Generate configurations
    generate_litellm_config
    
    # Final summary
    show_configuration_summary
    
    log_info "✅ System setup complete!"
    log_info "Next: Run ./2-deploy-services.sh"
}

main "$@"
