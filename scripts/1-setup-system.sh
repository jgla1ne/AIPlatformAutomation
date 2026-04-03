#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup & Input Collection
# PURPOSE: Complete system setup, input gathering, and platform.conf generation
# README: Grounded in unified README.md Golden Success Criteria
# =============================================================================
# USAGE:   bash scripts/1-setup-system.sh [tenant_id] [options]
# OPTIONS: --ingest-from <file>    Ingest credentials from existing .env file
#          --preserve-secrets       Preserve existing secrets from .env
#          --generate-new          Generate new secrets for all services
#          --deployment-mode <mode> Set deployment mode (minimal|standard|full)
#          --template FILE         Use template file for configuration
#          --dry-run               Show what would be configured
#          --save-template FILE    Save configuration as reusable template
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-INTERACTIVE MODE (P3 fix)
# =============================================================================
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE="/tmp/ai-platform-setup.log"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner() { 
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  🚀 AI Platform — Interactive Setup 🚀                        ║"
    echo "║                    Script 1 of 4                        ║"
    echo "║              Complete Configuration Wizard               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# ENHANCED UX INPUT FUNCTIONS
# =============================================================================
safe_read() {
    # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME [VALIDATION_PATTERN]
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local validation_pattern="${4:-}"
    local value
    local attempts=0
    local max_attempts=3

    # Check for env var override first
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ✨ ${prompt}: ${value} (from environment)"
        if [[ -n "$validation_pattern" && ! "$value" =~ $validation_pattern ]]; then
            fail "Environment variable $varname doesn't match required pattern"
        fi
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input with validation
        while [[ $attempts -lt $max_attempts ]]; do
            if [[ -n "$default" ]]; then
                read -rp "  🎯 ${prompt} [${default}]: " value
            else
                read -rp "  🎯 ${prompt}: " value
            fi
            
            value="${value:-${default}}"
            
            # Validate if pattern provided
            if [[ -n "$validation_pattern" && ! "$value" =~ $validation_pattern ]]; then
                echo "  ❌ Invalid format. Please try again."
                ((attempts++))
                continue
            fi
            
            break
        done
        
        if [[ $attempts -eq $max_attempts ]]; then
            fail "Maximum validation attempts reached for $varname"
        fi
    else
        # Non-TTY — use default silently
        value="${default}"
        echo "  🎯 ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

safe_read_yesno() {
    local prompt="$1"
    local default="${2:-n}"
    local value
    local attempts=0
    local max_attempts=3

    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -n "$default" ]]; then
            read -rp "  🤔 ${prompt} [Y/n]: " value
        else
            read -rp "  🤔 ${prompt} [y/N]: " value
        fi
        
        value="${value:-${default}}"
        
        case "${value,,}" in
            y|yes) 
                value="true" 
                echo "  ✅ ${prompt}: $value"
                printf -v "${3:-value}" '%s' "$value"
                return 0
                ;;
            n|no) 
                value="false"
                echo "  ✅ ${prompt}: $value"
                printf -v "${3:-value}" '%s' "$value"
                return 0
                ;;
            *) 
                echo "  ❌ Please enter 'y' or 'n'"
                ((attempts++))
                ;;
        esac
    done
    
    fail "Maximum attempts reached for yes/no prompt"
}

safe_read_password() {
    local prompt="$1"
    local varname="$2"
    local value
    local confirm
    
    while true; do
        read -rsp "  🔐 ${prompt}: " value
        echo ""
        read -rsp "  🔐 Confirm ${prompt}: " confirm
        echo ""
        
        if [[ "$value" == "$confirm" && -n "$value" ]]; then
            break
        elif [[ -z "$value" ]]; then
            echo "  ❌ Password cannot be empty"
        else
            echo "  ❌ Passwords do not match"
        fi
    done
    
    printf -v "${varname}" '%s' "${value}"
}

# =============================================================================
# SYSTEM DETECTION (README §4.2)
# =============================================================================
detect_system() {
    log "🔍 Detecting system capabilities..."
    
    # GPU Detection
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_TYPE="nvidia"
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        log "✅ NVIDIA GPU detected: ${GPU_MEMORY}MB"
    elif command -v rocm-smi >/dev/null 2>&1; then
        GPU_TYPE="rocm"
        GPU_MEMORY="unknown"
        log "✅ AMD GPU detected (ROCm)"
    else
        GPU_TYPE="none"
        GPU_MEMORY="0"
        log "ℹ️  No GPU detected - CPU-only mode"
    fi
    
    # Memory Detection
    TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    AVAILABLE_RAM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    log "💾 Memory: ${TOTAL_RAM}MB total, ${AVAILABLE_RAM}MB available"
    
    # Disk Space
    if [[ -d "/mnt" ]]; then
        DISK_SPACE=$(df -h /mnt | awk 'NR==2{print $4}')
        log "💿 Disk space available on /mnt: ${DISK_SPACE}"
    fi
    
    # Network MTU
    if command -v ip >/dev/null 2>&1; then
        HOST_MTU=$(ip link show | grep -E '^[0-9]+:' | head -1 | awk '{print $5}' | cut -d':' -f1)
        log "🌐 Host MTU: ${HOST_MTU}"
    fi
}

# =============================================================================
# IDENTITY COLLECTION (README §4.1)
# =============================================================================
collect_identity() {
    section "🏷️  PLATFORM IDENTITY"
    
    echo "  📋 Configure your platform identity and domain settings"
    echo ""
    
    safe_read "Platform prefix (for naming)" "ai" "PLATFORM_PREFIX" "^[a-z0-9_-]+$"
    safe_read "Tenant ID (unique identifier)" "" "TENANT_ID" "^[a-zA-Z0-9_-]+$"
    safe_read "Primary domain (e.g., example.com)" "" "DOMAIN" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    safe_read "Organization name" "AI Platform" "ORGANIZATION"
    safe_read "Admin email" "admin@${DOMAIN}" "ADMIN_EMAIL" "^[^@]+@[^@]+\.[^@]+$"
    
    echo ""
    echo "  📊 Identity Summary:"
    echo "    Platform: ${PLATFORM_PREFIX}"
    echo "    Tenant: ${TENANT_ID}"
    echo "    Domain: ${DOMAIN}"
    echo "    Organization: ${ORGANIZATION}"
    echo "    Admin: ${ADMIN_EMAIL}"
    echo ""
    
    safe_read_yesno "Confirm identity configuration" "y" IDENTITY_CONFIRMED
    if [[ "$IDENTITY_CONFIRMED" != "true" ]]; then
        fail "Identity configuration cancelled"
    fi
}

# =============================================================================
# STORAGE CONFIGURATION (README §4.2) - CORRECTED EBS DETECTION
# =============================================================================
configure_storage() {
    section "💾 STORAGE CONFIGURATION"
    
    echo "  📋 Storage Options:"
    echo "    • Auto-detect Amazon EBS volumes"
    echo "    • List available volumes for selection"
    echo "    • Format and mount selected volume"
    echo "    • Fallback to OS disk if no EBS found"
    echo ""
    
    safe_read_yesno "Use EBS volume (auto-detect)" "true" USE_EBS
    
    if [[ "$USE_EBS" == "true" ]]; then
        detect_and_select_ebs
    else
        echo "Using OS disk for storage"
        EBS_DEVICE=""
    fi
    
    # Always create mount point
    local mount_point="/mnt/${TENANT_ID}"
    echo "Creating mount point: $mount_point"
    mkdir -p "$mount_point"
    chmod 755 "$mount_point"
    
    # Format and mount if EBS selected
    if [[ -n "$EBS_DEVICE" ]]; then
        format_and_mount_ebs
    fi
    
    ok "Storage configuration complete"
}

# CORRECTED EBS detection using fdisk and Amazon EBS identification
detect_and_select_ebs() {
    echo "Available block devices:"
    local count=1
    
    # Use fdisk to detect Amazon EBS volumes specifically
    fdisk -l 2>/dev/null | grep -A 1 "Amazon Elastic Block Store" | while read -r line; do
        if [[ "$line" =~ ^/dev/ ]]; then
            local device=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $3,$4}')
            
            # Check if device is already mounted
            if ! findmnt "$device" >/dev/null 2>&1; then
                echo "  [$count] $device ${size} (unmounted — available)"
                count=$((count + 1))
            else
                echo "  [X] $device ${size} (mounted - unavailable)"
            fi
        fi
    done
    
    echo "  [$count] Use existing /mnt/${TENANT_ID}/ on OS disk (no separate volume)"
    
    safe_read "Select EBS volume [1-$count, or 0 for OS disk]" "0" EBS_CHOICE
    
    if [[ "$EBS_CHOICE" =~ ^[1-9]$ ]]; then
        # Extract device from fdisk output
        EBS_DEVICE=$(fdisk -l 2>/dev/null | grep -A 1 "Amazon Elastic Block Store" | grep "^/dev/" | sed -n "${EBS_CHOICE}p" | awk '{print $1}')
        echo "Selected EBS device: $EBS_DEVICE"
    else
        echo "Using OS disk for storage"
        EBS_DEVICE=""
    fi
}

# Format and mount EBS volume
format_and_mount_ebs() {
    if [[ -n "$EBS_DEVICE" ]] && [[ -b "$EBS_DEVICE" ]]; then
        echo "Formatting EBS volume: $EBS_DEVICE"
        safe_read "CONFIRM: Format $EBS_DEVICE as ext4? [yes/N]: " "" FORMAT_CONFIRM
        
        if [[ "$FORMAT_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
            mkfs.ext4 -F "$EBS_DEVICE" || fail "Failed to format $EBS_DEVICE"
            echo "EBS volume formatted successfully"
        else
            fail "EBS volume formatting cancelled"
        fi
        
        # Mount EBS volume
        echo "Mounting EBS volume..."
        mkdir -p "/mnt/${TENANT_ID}"
        mount "$EBS_DEVICE" "/mnt/${TENANT_ID}" || fail "Failed to mount EBS volume"
        
        # Add to fstab
        local uuid=$(blkid -s UUID -o value "$EBS_DEVICE")
        local fstab_entry="UUID=$uuid  /mnt/${TENANT_ID}  ext4  defaults,nofail  0  0"
        
        if ! grep -q "UUID=$uuid" /etc/fstab; then
            echo "$fstab_entry" >> /etc/fstab
            systemctl daemon-reload
            echo "Added to fstab: $fstab_entry"
        fi
        
        echo "EBS volume mounted successfully"
        echo "Mount point: /mnt/${TENANT_ID}"
        echo "Device: $EBS_DEVICE (UUID: $uuid)"
    else
        fail "Invalid EBS device: $EBS_DEVICE"
    fi
}

# =============================================================================
# STACK PRESET SELECTION (README §4.3)
# =============================================================================
select_stack_preset() {
    section "🎚️  STACK PRESET SELECTION"
    
    echo "  📋 Choose your platform complexity and features"
    echo ""
    
    echo "  🔹 MINIMAL STACK:"
    echo "     • PostgreSQL + Redis (infrastructure)"
    echo "     • LiteLLM + Ollama (LLM services)"
    echo "     • OpenWebUI (web interface)"
    echo "     • Qdrant (vector database)"
    echo "     • Resource usage: ~4GB RAM, ~20GB disk"
    echo ""
    
    echo "  🔹 DEVELOPMENT STACK:"
    echo "     • All Minimal features"
    echo "     • Code Server (IDE)"
    echo "     • Development tools"
    echo "     • Resource usage: ~6GB RAM, ~30GB disk"
    echo ""
    
    echo "  🔹 STANDARD STACK:"
    echo "     • All Development features"
    echo "     • N8N (workflow automation)"
    echo "     • Flowise (AI workflow builder)"
    echo "     • Grafana + Prometheus (monitoring)"
    echo "     • Resource usage: ~8GB RAM, ~50GB disk"
    echo ""
    
    echo "  🔹 FULL STACK:"
    echo "     • All Standard features"
    echo "     • All web interfaces (LibreChat, OpenClaw, AnythingLLM)"
    echo "     • All automation tools (Dify, SignalBot)"
    echo "     • Complete monitoring and logging"
    echo "     • Resource usage: ~16GB RAM, ~100GB disk"
    echo ""
    
    echo "  🔹 CUSTOM STACK:"
    echo "     • Select individual services"
    echo "     • Full control over components"
    echo ""
    
    safe_read "Stack preset [1-5]" "3" "STACK_PRESET" "^[1-5]$"
    
    case "$STACK_PRESET" in
        1) STACK_NAME="minimal" ;;
        2) STACK_NAME="development" ;;
        3) STACK_NAME="standard" ;;
        4) STACK_NAME="full" ;;
        5) STACK_NAME="custom" ;;
    esac
    
    echo "  ✅ Selected: ${STACK_NAME^} Stack"
    
    if [[ "$STACK_PRESET" == "5" ]]; then
        configure_custom_stack
    else
        apply_preset_defaults
    fi
}

apply_preset_defaults() {
    log "🎯 Applying ${STACK_NAME^} stack defaults..."
    
    case "$STACK_NAME" in
        minimal)
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ;;
        development)
            # Minimal + Code Server
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ;;
        standard)
            # Development + N8N + Flowise + Monitoring
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_N8N="true"
            ENABLE_FLOWISE="true"
            ENABLE_GRAFANA="true"
            ENABLE_PROMETHEUS="true"
            ;;
        full)
            # Standard + All remaining services
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_N8N="true"
            ENABLE_FLOWISE="true"
            ENABLE_GRAFANA="true"
            ENABLE_PROMETHEUS="true"
            ENABLE_LIBRECHAT="true"
            ENABLE_OPENCLAW="true"
            ENABLE_ANYTHINGLLM="true"
            ENABLE_DIFY="true"
            ENABLE_SIGNALBOT="true"
            ENABLE_AUTHENTIK="true"
            ;;
    esac
}

configure_custom_stack() {
    section "🔧 CUSTOM STACK CONFIGURATION"
    
    echo "  📋 Select individual services to enable"
    echo ""
    
    # Infrastructure Services
    echo "  🏗️  Infrastructure Services:"
    safe_read_yesno "PostgreSQL (database)" "true" "ENABLE_POSTGRES"
    safe_read_yesno "Redis (cache)" "true" "ENABLE_REDIS"
    echo ""
    
    # LLM Services
    echo "  🤖 LLM Services:"
    safe_read_yesno "Ollama (local models)" "true" "ENABLE_OLLAMA"
    safe_read_yesno "LiteLLM (gateway)" "true" "ENABLE_LITELLM"
    echo ""
    
    # Web Interfaces
    echo "  🌐 Web Interfaces:"
    safe_read_yesno "OpenWebUI (chat interface)" "true" "ENABLE_OPENWEBUI"
    safe_read_yesno "LibreChat (multi-provider chat)" "false" "ENABLE_LIBRECHAT"
    safe_read_yesno "OpenClaw (private gateway)" "false" "ENABLE_OPENCLAW"
    safe_read_yesno "AnythingLLM (document chat)" "false" "ENABLE_ANYTHINGLLM"
    echo ""
    
    # Vector Databases
    echo "  🔍 Vector Databases:"
    safe_read_yesno "Qdrant (vector DB)" "true" "ENABLE_QDRANT"
    safe_read_yesno "Weaviate (vector DB)" "false" "ENABLE_WEAVIATE"
    safe_read_yesno "ChromaDB (vector DB)" "false" "ENABLE_CHROMA"
    safe_read_yesno "Milvus (vector DB)" "false" "ENABLE_MILVUS"
    echo ""
    
    # Automation
    echo "  ⚙️  Automation:"
    safe_read_yesno "N8N (workflow automation)" "false" "ENABLE_N8N"
    safe_read_yesno "Flowise (AI workflows)" "false" "ENABLE_FLOWISE"
    safe_read_yesno "Dify (LLM ops)" "false" "ENABLE_DIFY"
    echo ""
    
    # Development
    echo "  💻 Development:"
    safe_read_yesno "Code Server (IDE)" "false" "ENABLE_CODE_SERVER"
    echo ""
    
    # Monitoring
    echo "  📊 Monitoring:"
    safe_read_yesno "Grafana (dashboards)" "false" "ENABLE_GRAFANA"
    safe_read_yesno "Prometheus (metrics)" "false" "ENABLE_PROMETHEUS"
    echo ""
    
    # Authentication
    echo "  🔐 Authentication:"
    safe_read_yesno "Authentik (SSO)" "false" "ENABLE_AUTHENTIK"
    echo ""
    
    # Additional Services
    echo "  📡 Additional:"
    safe_read_yesno "SignalBot (messaging)" "false" "ENABLE_SIGNALBOT"
}

# =============================================================================
# LLM GATEWAY CONFIGURATION (README §4.4)
# =============================================================================
configure_llm_gateway() {
    section "🤖 LLM GATEWAY CONFIGURATION"
    
    echo "  📋 Configure LLM service gateway and model access"
    echo ""
    
    echo "  🔹 LITELLM (Recommended for multi-provider):"
    echo "     • Unified API for multiple LLM providers"
    echo "     • Load balancing and failover"
    echo "     • Cost tracking and rate limiting"
    echo ""
    
    echo "  🔹 BIFROST (Advanced gateway):"
    echo "     • Enterprise features"
    echo "     • Advanced routing"
    echo "     • Enhanced security"
    echo ""
    
    echo "  🔹 DIRECT OLLAMA (Simple setup):"
    echo "     • Direct access to local models"
    echo "     • No gateway overhead"
    echo "     • Single provider only"
    echo ""
    
    safe_read "LLM Gateway type" "litellm" "LLM_GATEWAY_TYPE" "^(litellm|bifrost|direct)$"
    
    case "$LLM_GATEWAY_TYPE" in
        litellm)
            configure_litellm_gateway
            ;;
        bifrost)
            configure_bifrost_gateway
            ;;
        direct)
            configure_direct_ollama
            ;;
    esac
}

configure_litellm_gateway() {
    echo ""
    log "🎯 Configuring LiteLLM Gateway..."
    
    safe_read "LiteLLM API key (auto-generated)" "$(gen_secret)" "LITELLM_MASTER_KEY"
    safe_read "LiteLLM routing strategy" "least-busy" "LITELLM_ROUTING_STRATEGY" "^(least-busy|weighted|simple)$"
    safe_read "Enable request logging" "true" "LITELLM_ENABLE_LOGGING"
    safe_read "Enable cost tracking" "true" "LITELLM_ENABLE_COST_TRACKING"
    
    echo ""
    echo "  📊 LiteLLM Configuration Summary:"
    echo "    Gateway Type: LiteLLM"
    echo "    Master Key: ${LITELLM_MASTER_KEY:0:10}..."
    echo "    Routing: ${LITELLM_ROUTING_STRATEGY}"
    echo "    Logging: ${LITELLM_ENABLE_LOGGING}"
    echo "    Cost Tracking: ${LITELLM_ENABLE_COST_TRACKING}"
}

configure_bifrost_gateway() {
    echo ""
    log "🎯 Configuring Bifrost Gateway..."
    
    safe_read "Bifrost admin token" "$(gen_secret)" "BIFROST_ADMIN_TOKEN"
    safe_read "Bifrost API key" "$(gen_secret)" "BIFROST_API_KEY"
    safe_read "Bifrost port" "8000" "BIFROST_PORT" "^[0-9]+$"
    
    echo ""
    echo "  📊 Bifrost Configuration Summary:"
    echo "    Gateway Type: Bifrost"
    echo "    Admin Token: ${BIFROST_ADMIN_TOKEN:0:10}..."
    echo "    API Key: ${BIFROST_API_KEY:0:10}..."
    echo "    Port: ${BIFROST_PORT}"
}

configure_direct_ollama() {
    echo ""
    log "🎯 Configuring Direct Ollama Access..."
    
    safe_read "Ollama host" "localhost" "OLLAMA_HOST"
    safe_read "Ollama port" "11434" "OLLAMA_PORT" "^[0-9]+$"
    
    echo ""
    echo "  📊 Direct Ollama Configuration Summary:"
    echo "    Gateway Type: Direct Ollama"
    echo "    Host: ${OLLAMA_HOST}"
    echo "    Port: ${OLLAMA_PORT}"
}

# =============================================================================
# VECTOR DATABASE CONFIGURATION (README §4.5)
# =============================================================================
configure_vector_database() {
    section "🔍 VECTOR DATABASE CONFIGURATION"
    
    echo "  📋 Configure vector database for AI memory and search"
    echo ""
    
    echo "  🔹 QDRANT (Recommended):"
    echo "     • High-performance vector search"
    echo "     • Built-in filtering and metadata"
    echo "     • Easy integration"
    echo ""
    
    echo "  🔹 WEAVIATE (Enterprise):"
    echo "     • GraphQL API"
    echo "     • Advanced filtering"
    echo "     • Multi-modal support"
    echo ""
    
    echo "  🔹 CHROMADB (Lightweight):"
    echo "     • Simple setup"
    echo "     • Good for development"
    echo "     • Python-focused"
    echo ""
    
    echo "  🔹 MILVUS (Scale):"
    echo "     • Distributed architecture"
    echo "     • Massive scale"
    echo "     • Cloud-native"
    echo ""
    
    safe_read "Vector database" "qdrant" "VECTOR_DB_TYPE" "^(qdrant|weaviate|chroma|milvus)$"
    
    case "$VECTOR_DB_TYPE" in
        qdrant)
            configure_qdrant
            ;;
        weaviate)
            configure_weaviate
            ;;
        chroma)
            configure_chroma
            ;;
        milvus)
            configure_milvus
            ;;
    esac
}

configure_qdrant() {
    echo ""
    log "🎯 Configuring Qdrant..."
    
    safe_read "Qdrant port" "6333" "QDRANT_PORT" "^[0-9]+$"
    safe_read "Qdrant API key" "$(gen_secret)" "QDRANT_API_KEY"
    safe_read "Enable collection management" "true" "QDRANT_ENABLE_COLLECTIONS"
    
    echo ""
    echo "  📊 Qdrant Configuration Summary:"
    echo "    Database: Qdrant"
    echo "    Port: ${QDRANT_PORT}"
    echo "    API Key: ${QDRANT_API_KEY:0:10}..."
    echo "    Collection Management: ${QDRANT_ENABLE_COLLECTIONS}"
}

configure_weaviate() {
    echo ""
    log "🎯 Configuring Weaviate..."
    
    safe_read "Weaviate port" "8080" "WEAVIATE_PORT" "^[0-9]+$"
    safe_read "Weaviate API key" "$(gen_secret)" "WEAVIATE_API_KEY"
    safe_read "Enable authentication" "true" "WEAVIATE_ENABLE_AUTH"
    
    echo ""
    echo "  📊 Weaviate Configuration Summary:"
    echo "    Database: Weaviate"
    echo "    Port: ${WEAVIATE_PORT}"
    echo "    API Key: ${WEAVIATE_API_KEY:0:10}..."
    echo "    Authentication: ${WEAVIATE_ENABLE_AUTH}"
}

configure_chroma() {
    echo ""
    log "🎯 Configuring ChromaDB..."
    
    safe_read "ChromaDB port" "8000" "CHROMA_PORT" "^[0-9]+$"
    safe_read "ChromaDB auth token" "$(gen_secret)" "CHROMA_AUTH_TOKEN"
    
    echo ""
    echo "  📊 ChromaDB Configuration Summary:"
    echo "    Database: ChromaDB"
    echo "    Port: ${CHROMA_PORT}"
    echo "    Auth Token: ${CHROMA_AUTH_TOKEN:0:10}..."
}

configure_milvus() {
    echo ""
    log "🎯 Configuring Milvus..."
    
    safe_read "Milvus port" "19530" "MILVUS_PORT" "^[0-9]+$"
    safe_read "Milvus API key" "$(gen_secret)" "MILVUS_API_KEY"
    
    echo ""
    echo "  📊 Milvus Configuration Summary:"
    echo "    Database: Milvus"
    echo "    Port: ${MILVUS_PORT}"
    echo "    API Key: ${MILVUS_API_KEY:0:10}..."
}

# =============================================================================
# TLS CONFIGURATION (README §4.6)
# =============================================================================
configure_tls() {
    section "🔐 TLS CERTIFICATE CONFIGURATION"
    
    echo "  📋 Configure SSL/TLS certificates for secure access"
    echo ""
    
    echo "  🔹 LET'S ENCRYPT (Recommended for production):"
    echo "     • Automatic certificate issuance"
    echo "     • Free certificates"
    echo "     • Requires public DNS and domain"
    echo "     • Automatic renewal"
    echo ""
    
    echo "  🔹 MANUAL CERTIFICATES:"
    echo "     • Use existing certificates"
    echo "     • Full control over certificates"
    echo "     • Manual renewal required"
    echo ""
    
    echo "  🔹 SELF-SIGNED (Development):"
    echo "     • Quick setup for testing"
    echo "     • Browser warnings expected"
    echo "     • Not for production"
    echo ""
    
    echo "  🔹 NO TLS (HTTP only):"
    echo "     • Unencrypted connections"
    echo "     • Not recommended for production"
    echo "     • For testing only"
    echo ""
    
    safe_read "TLS mode [1-4]" "1" "TLS_MODE_CHOICE" "^[1-4]$"
    
    case "$TLS_MODE_CHOICE" in
        1)
            TLS_MODE="letsencrypt"
            configure_letsencrypt
            ;;
        2)
            TLS_MODE="manual"
            configure_manual_tls
            ;;
        3)
            TLS_MODE="selfsigned"
            configure_selfsigned_tls
            ;;
        4)
            TLS_MODE="none"
            configure_no_tls
            ;;
    esac
}

configure_letsencrypt() {
    echo ""
    log "🎯 Configuring Let's Encrypt..."
    
    safe_read "Email for Let's Encrypt" "${ADMIN_EMAIL}" "LETSENCRYPT_EMAIL"
    safe_read "Enable staging mode (testing)" "false" "LETSENCRYPT_STAGING"
    safe_read "Auto-renew certificates" "true" "LETSENCRYPT_AUTO_RENEW"
    
    # Enhanced DNS validation with mission control
    echo ""
    log "🔍 Running enhanced DNS validation for ${DOMAIN}..."
    validate_dns_setup "$DOMAIN"
    
    # Additional Let's Encrypt specific checks
    echo ""
    log "🔍 Let's Encrypt specific validation..."
    
    # Check if port 80 is available (required for HTTP-01 challenge)
    if ss -tlnp 2>/dev/null | grep -q ":80 "; then
        warn "Port 80 is already in use - Let's Encrypt HTTP-01 challenge may fail"
        safe_read_yesno "Continue with port 80 in use?" "false" "CONTINUE_PORT80"
        if [[ "$CONTINUE_PORT80" != "true" ]]; then
            fail "Let's Encrypt requires port 80 for HTTP-01 challenge"
        fi
    else
        echo "✅ Port 80 is available for Let's Encrypt HTTP-01 challenge"
    fi
    
    # Check if port 443 is available
    if ss -tlnp 2>/dev/null | grep -q ":443 "; then
        warn "Port 443 is already in use - HTTPS may conflict"
        safe_read_yesno "Continue with port 443 in use?" "false" "CONTINUE_PORT443"
        if [[ "$CONTINUE_PORT443" != "true" ]]; then
            fail "Port 443 is required for HTTPS"
        fi
    else
        echo "✅ Port 443 is available for HTTPS"
    fi
    
    echo "✅ Let's Encrypt configuration validated"
}

configure_manual_tls() {
    echo ""
    log "🎯 Configuring Manual TLS..."
    
    safe_read "Certificate file path" "/etc/ssl/certs/${DOMAIN}.crt" "TLS_CERT_FILE"
    safe_read "Private key file path" "/etc/ssl/private/${DOMAIN}.key" "TLS_KEY_FILE"
    
    # Validate files exist
    if [[ ! -f "$TLS_CERT_FILE" ]]; then
        warn "Certificate file not found: ${TLS_CERT_FILE}"
        warn "Please ensure certificate files exist before deployment"
    fi
    
    if [[ ! -f "$TLS_KEY_FILE" ]]; then
        warn "Private key file not found: ${TLS_KEY_FILE}"
        warn "Please ensure certificate files exist before deployment"
    fi
    
    echo ""
    echo "  📊 Manual TLS Configuration Summary:"
    echo "    TLS Mode: Manual"
    echo "    Certificate: ${TLS_CERT_FILE}"
    echo "    Private Key: ${TLS_KEY_FILE}"
}

configure_selfsigned_tls() {
    echo ""
    log "🎯 Configuring Self-Signed TLS..."
    
    safe_read "Certificate validity days" "365" "SELF_SIGNED_DAYS" "^[0-9]+$"
    safe_read "Country code" "US" "CERT_COUNTRY" "^[A-Z]{2}$"
    safe_read "State/Province" "California" "CERT_STATE"
    safe_read "City" "San Francisco" "CERT_CITY"
    safe_read "Organization" "${ORGANIZATION}" "CERT_ORG"
    
    echo ""
    echo "  📊 Self-Signed TLS Configuration Summary:"
    echo "    TLS Mode: Self-Signed"
    echo "    Validity: ${SELF_SIGNED_DAYS} days"
    echo "    Country: ${CERT_COUNTRY}"
    echo "    State: ${CERT_STATE}"
    echo "    City: ${CERT_CITY}"
    echo "    Organization: ${CERT_ORG}"
}

configure_no_tls() {
    echo ""
    log "⚠️  Configuring No TLS..."
    
    warn "TLS disabled - all connections will be HTTP"
    warn "Not recommended for production use"
    
    safe_read_yesno "Confirm TLS disabled" "false" "CONFIRM_NO_TLS"
    if [[ "$CONFIRM_NO_TLS" != "true" ]]; then
        fail "TLS configuration cancelled"
    fi
    
    echo ""
    echo "  📊 No TLS Configuration Summary:"
    echo "    TLS Mode: None (HTTP only)"
    echo "    Warning: Not secure for production"
}

# =============================================================================
# API KEY COLLECTION (README §4.7)
# =============================================================================
collect_api_keys() {
    section "🔑 API KEY COLLECTION"
    
    echo "  📋 Configure API keys for LLM providers"
    echo "  🔐 Keys are encrypted and stored securely"
    echo ""
    
    # OpenAI
    echo "  🤖 OpenAI Configuration:"
    safe_read_yesno "Enable OpenAI" "false" "ENABLE_OPENAI"
    if [[ "$ENABLE_OPENAI" == "true" ]]; then
        safe_read "OpenAI API key" "" "OPENAI_API_KEY" "^sk-[A-Za-z0-9]+$"
        safe_read "OpenAI organization ID" "" "OPENAI_ORG_ID"
        safe_read "OpenAI models" "gpt-4,gpt-3.5-turbo" "OPENAI_MODELS"
    fi
    echo ""
    
    # Anthropic
    echo "  🧠 Anthropic Configuration:"
    safe_read_yesno "Enable Anthropic Claude" "false" "ENABLE_ANTHROPIC"
    if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
        safe_read "Anthropic API key" "" "ANTHROPIC_API_KEY" "^sk-ant-[A-Za-z0-9_-]+$"
        safe_read "Anthropic models" "claude-3-sonnet-20240229,claude-3-haiku-20240307" "ANTHROPIC_MODELS"
    fi
    echo ""
    
    # Google
    echo "  🔍 Google AI Configuration:"
    safe_read_yesno "Enable Google AI" "false" "ENABLE_GOOGLE"
    if [[ "$ENABLE_GOOGLE" == "true" ]]; then
        safe_read "Google AI API key" "" "GOOGLE_AI_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Google models" "gemini-pro,gemini-pro-vision" "GOOGLE_MODELS"
    fi
    echo ""
    
    # Groq
    echo "  ⚡ Groq Configuration:"
    safe_read_yesno "Enable Groq" "false" "ENABLE_GROQ"
    if [[ "$ENABLE_GROQ" == "true" ]]; then
        safe_read "Groq API key" "" "GROQ_API_KEY" "^gsk_[A-Za-z0-9_-]+$"
        safe_read "Groq models" "llama2-70b-4096,mixtral-8x7b-32768" "GROQ_MODELS"
    fi
    echo ""
    
    # Cohere
    echo "  🔗 Cohere Configuration:"
    safe_read_yesno "Enable Cohere" "false" "ENABLE_COHERE"
    if [[ "$ENABLE_COHERE" == "true" ]]; then
        safe_read "Cohere API key" "" "COHERE_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Cohere models" "command,command-nightly,command-light" "COHERE_MODELS"
    fi
    echo ""
    
    # Hugging Face
    echo "  🤗 Hugging Face Configuration:"
    safe_read_yesno "Enable Hugging Face" "false" "ENABLE_HUGGINGFACE"
    if [[ "$ENABLE_HUGGINGFACE" == "true" ]]; then
        safe_read "Hugging Face API key" "" "HUGGINGFACE_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Hugging Face models" "microsoft/DialoGPT-medium,google/flan-t5-base" "HUGGINGFACE_MODELS"
    fi
    echo ""
    
    # Local Models (Ollama)
    echo "  🦙 Local Models Configuration:"
    safe_read_yesno "Enable local models" "true" "ENABLE_LOCAL_MODELS"
    if [[ "$ENABLE_LOCAL_MODELS" == "true" ]]; then
        safe_read "Default Ollama models" "llama3.1:8b,mistral:7b" "OLLAMA_MODELS"
        safe_read "Auto-download models" "true" "OLLAMA_AUTO_DOWNLOAD"
    fi
}

# =============================================================================
# PORT CONFIGURATION WITH HEALTH VALIDATION (README §4.6) - ENHANCED
# =============================================================================
configure_ports() {
    section "🔌 PORT CONFIGURATION WITH HEALTH VALIDATION"
    
    echo "  📋 Port Management:"
    echo "    • Check for port conflicts before assignment"
    echo "    • Mission control health validation for services"
    echo "    • Dynamic port allocation for conflicts"
    echo ""
    
    # Check port conflicts first
    check_port_conflicts
    
    echo "Configuring service ports..."
    
    # Infrastructure ports
    safe_read "PostgreSQL port" "${POSTGRES_PORT:-5432}" "POSTGRES_PORT"
    safe_read "Redis port" "${REDIS_PORT:-6379}" "REDIS_PORT"
    
    # Service ports
    safe_read "LiteLLM port" "${LITELLM_PORT:-4000}" "LITELLM_PORT"
    safe_read "Ollama port" "${OLLAMA_PORT:-11434}" "OLLAMA_PORT"
    safe_read "OpenWebUI port" "${OPENWEBUI_PORT:-3000}" "OPENWEBUI_PORT"
    safe_read "Qdrant port" "${QDRANT_PORT:-6333}" "QDRANT_PORT"
    
    if [[ "$N8N_ENABLED" == "true" ]]; then
        safe_read "n8n port" "${N8N_PORT:-5678}" "N8N_PORT"
    fi
    
    if [[ "$CODESERVER_ENABLED" == "true" ]]; then
        safe_read "Code Server port" "${CODESERVER_PORT:-8443}" "CODESERVER_PORT"
    fi
    
    # Mission control port health validation
    echo ""
    echo "Running mission control port health checks..."
    
    # Check if ports are available (pre-deployment validation)
    local all_ports_available=true
    
    for service_port in "POSTGRES:${POSTGRES_PORT}" "REDIS:${REDIS_PORT}" "LITELLM:${LITELLM_PORT}" "OLLAMA:${OLLAMA_PORT}" "OPENWEBUI:${OPENWEBUI_PORT}" "QDRANT:${QDRANT_PORT}"; do
        local service=$(echo "$service_port" | cut -d: -f1)
        local port=$(echo "$service_port" | cut -d: -f2)
        
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "❌ Port $port is already in use (conflict for $service)"
            all_ports_available=false
        else
            echo "✅ Port $port is available for $service"
        fi
    done
    
    if [[ "$all_ports_available" != "true" ]]; then
        echo ""
        echo "⚠️  Port conflicts detected. You can:"
        echo "   1. Change conflicting ports above"
        echo "   2. Stop conflicting processes"
        echo "   3. Continue and let deployment handle conflicts"
        
        safe_read "Continue with current port configuration?" "n" "CONTINUE_WITH_CONFLICTS"
        if [[ "$CONTINUE_WITH_CONFLICTS" != "yes" ]]; then
            fail "Port configuration cancelled due to conflicts"
        fi
    fi
    
    ok "Port configuration complete"
}

# Enhanced port conflict detection
check_port_conflicts() {
    echo "Checking for port conflicts..."
    
    # Collect all required ports from platform.conf
    local required_ports=()
    
    # Infrastructure ports
    [[ "${POSTGRES_ENABLED}" == "true" ]] && required_ports+=("${POSTGRES_PORT:-5432}")
    [[ "${REDIS_ENABLED}" == "true" ]] && required_ports+=("${REDIS_PORT:-6379}")
    
    # Service ports
    [[ "${LITELLM_ENABLED}" == "true" ]] && required_ports+=("${LITELLM_PORT:-4000}")
    [[ "${OLLAMA_ENABLED}" == "true" ]] && required_ports+=("${OLLAMA_PORT:-11434}")
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && required_ports+=("${OPENWEBUI_PORT:-3000}")
    [[ "${QDRANT_ENABLED}" == "true" ]] && required_ports+=("${QDRANT_PORT:-6333}")
    [[ "${N8N_ENABLED}" == "true" ]] && required_ports+=("${N8N_PORT:-5678}")
    [[ "${CODESERVER_ENABLED}" == "true" ]] && required_ports+=("${CODESERVER_PORT:-8443}")
    
    # Check each port against currently listening ports
    local conflicts=()
    for port in "${required_ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            local pid=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | awk '{print $7}')
            local process=$(ps -p "$pid" -o comm= 2>/dev/null)
            conflicts+=("Port $port: already in use by $process (PID $pid)")
        fi
    done
    
    # Report conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "❌ PORT CONFLICTS DETECTED:"
        printf '%s\n' "${conflicts[@]}"
        echo ""
        echo "Options:"
        echo "  1. Change conflicting ports in platform.conf"
        echo "  2. Stop conflicting processes"
        echo "  3. Use different tenant ID"
    else
        echo "✅ No port conflicts detected for required ports"
        echo "Required ports: ${required_ports[*]}"
    fi
}

# Mission Control Port Health Check (for Scripts 2, 3)
check_port_health() {
    local port="$1"
    local service="$2"
    local timeout="${3:-30}"
    
    echo "Checking port health for $service (port $port)..."
    
    # Check if port is listening
    local waited=0
    while ! ss -tlnp 2>/dev/null | grep -q ":$port "; do
        if [[ $waited -ge $timeout ]]; then
            echo "❌ Port $port not available for $service after ${timeout}s"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    # Check service health endpoint if available
    case "$service" in
        "postgres")
            if docker exec "${TENANT_PREFIX}-postgres" pg_isready -U postgres >/dev/null 2>&1; then
                echo "✅ PostgreSQL health check passed"
            else
                echo "❌ PostgreSQL health check failed"
                return 1
            fi
            ;;
        "redis")
            if docker exec "${TENANT_PREFIX}-redis" redis-cli ping | grep -q PONG; then
                echo "✅ Redis health check passed"
            else
                echo "❌ Redis health check failed"
                return 1
            fi
            ;;
        "ollama")
            if curl -s "http://localhost:${port}/api/tags" >/dev/null; then
                echo "✅ Ollama health check passed"
            else
                echo "❌ Ollama health check failed"
                return 1
            fi
            ;;
        "litellm")
            if curl -s "http://localhost:${port}/health" >/dev/null; then
                echo "✅ LiteLLM health check passed"
            else
                echo "❌ LiteLLM health check failed"
                return 1
            fi
            ;;
        *)
            echo "✅ Port $port is available for $service"
            ;;
    esac
    
    return 0
}

# =============================================================================
# DNS VALIDATION FUNCTIONS (README §4.5) - ENHANCED
# =============================================================================

# Enhanced DNS validation with mission control integration
validate_dns_setup() {
    local domain="$1"
    
    echo "=== DNS VALIDATION FOR $domain ==="
    
    # Step 1: Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo "❌ Invalid domain format: $domain"
        return 1
    fi
    echo "✅ Domain format is valid"
    
    # Step 2: DNS resolution test
    echo "Testing DNS resolution..."
    if dig +short "$domain" >/dev/null 2>&1; then
        echo "✅ DNS resolution successful"
    else
        echo "❌ DNS resolution failed"
        return 1
    fi
    
    # Step 3: Get public IP and compare
    echo "Detecting public IP..."
    local public_ip
    public_ip=$(curl -s https://ifconfig.me 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null)
    
    if [[ -z "$public_ip" ]]; then
        echo "❌ Could not detect public IP"
        return 1
    fi
    echo "Detected public IP: $public_ip"
    
    # Step 4: Compare domain resolution with public IP
    echo "Comparing domain resolution with public IP..."
    local domain_ip
    domain_ip=$(dig +short "$domain" | head -1)
    
    if [[ "$domain_ip" == "$public_ip" ]]; then
        echo "✅ Domain resolves to this server's public IP"
    else
        echo "⚠️  Domain resolves to $domain_ip, but this server's public IP is $public_ip"
        echo "   This may indicate a DNS configuration issue"
        safe_read_yesno "Continue despite IP mismatch?" "false" "CONTINUE_IP_MISMATCH"
        if [[ "$CONTINUE_IP_MISMATCH" != "true" ]]; then
            return 1
        fi
    fi
    
    # Step 5: Test reverse DNS (optional)
    echo "Testing reverse DNS lookup..."
    local reverse_dns
    if reverse_dns=$(dig -x "$public_ip" +short 2>/dev/null); then
        echo "Reverse DNS: $public_ip → $reverse_dns"
        if [[ "$reverse_dns" != "$domain" ]]; then
            echo "⚠️  Reverse DNS mismatch: $public_ip → $reverse_dns (expected $domain)"
        fi
    else
        echo "Reverse DNS lookup failed for $public_ip"
    fi
    
    echo "=== DNS VALIDATION COMPLETE ==="
    return 0
}

# DNS health check for mission control
check_dns_health() {
    local domain="$1"
    local timeout="${2:-30}"
    
    echo "Checking DNS health for $domain..."
    
    local waited=0
    while [[ $waited -lt $timeout ]]; do
        if dig +short "$domain" >/dev/null 2>&1; then
            echo "✅ DNS resolution working for $domain"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    echo "❌ DNS resolution failed after ${timeout}s"
    return 1
}

# =============================================================================
# TLS CONFIGURATION WITH DNS VALIDATION (README §4.7) - ENHANCED
# =============================================================================
configure_tls() {
    section "� TLS CONFIGURATION WITH DNS VALIDATION"
    
    echo "  🔐 TLS Configuration:"
    echo "    • Certificate management with DNS validation"
    echo "    • Automatic certificate renewal"
    echo ""
    
    # Identity Summary
    echo "  🏷️  IDENTITY:"
    echo "    Platform: ${PLATFORM_PREFIX}"
    echo "    Tenant: ${TENANT_ID}"
    echo "    Domain: ${DOMAIN}"
    echo "    Organization: ${ORGANIZATION}"
    echo "    Admin Email: ${ADMIN_EMAIL}"
    echo ""
    
    # Storage Summary
    echo "  💾 STORAGE:"
    echo "    Data Directory: ${DATA_DIR}"
    echo "    EBS Volume: ${USE_EBS}"
    if [[ "$USE_EBS" == "true" ]]; then
        echo "    Device Pattern: ${EBS_DEVICE_PATTERN}"
        echo "    Filesystem: ${EBS_FILESYSTEM}"
    fi
    echo ""
    
    # Stack Summary
    echo "  🎚️  STACK:"
    echo "    Preset: ${STACK_NAME^}"
    echo "    Enabled Services:"
    [[ "$ENABLE_POSTGRES" == "true" ]] && echo "      • PostgreSQL"
    [[ "$ENABLE_REDIS" == "true" ]] && echo "      • Redis"
    [[ "$ENABLE_OLLAMA" == "true" ]] && echo "      • Ollama"
    [[ "$ENABLE_LITELLM" == "true" ]] && echo "      • LiteLLM"
    [[ "$ENABLE_OPENWEBUI" == "true" ]] && echo "      • OpenWebUI"
    [[ "$ENABLE_QDRANT" == "true" ]] && echo "      • Qdrant"
    [[ "$ENABLE_CODE_SERVER" == "true" ]] && echo "      • Code Server"
    [[ "$ENABLE_N8N" == "true" ]] && echo "      • N8N"
    [[ "$ENABLE_FLOWISE" == "true" ]] && echo "      • Flowise"
    [[ "$ENABLE_GRAFANA" == "true" ]] && echo "      • Grafana"
    [[ "$ENABLE_PROMETHEUS" == "true" ]] && echo "      • Prometheus"
    [[ "$ENABLE_LIBRECHAT" == "true" ]] && echo "      • LibreChat"
    [[ "$ENABLE_OPENCLAW" == "true" ]] && echo "      • OpenClaw"
    [[ "$ENABLE_ANYTHINGLLM" == "true" ]] && echo "      • AnythingLLM"
    [[ "$ENABLE_DIFY" == "true" ]] && echo "      • Dify"
    [[ "$ENABLE_SIGNALBOT" == "true" ]] && echo "      • SignalBot"
    [[ "$ENABLE_AUTHENTIK" == "true" ]] && echo "      • Authentik"
    echo ""
    
    # LLM Gateway Summary
    echo "  🤖 LLM GATEWAY:"
    echo "    Type: ${LLM_GATEWAY_TYPE^}"
    case "$LLM_GATEWAY_TYPE" in
        litellm)
            echo "    Routing: ${LITELLM_ROUTING_STRATEGY}"
            echo "    Logging: ${LITELLM_ENABLE_LOGGING}"
            ;;
        bifrost)
            echo "    Port: ${BIFROST_PORT}"
            ;;
        direct)
            echo "    Host: ${OLLAMA_HOST}:${OLLAMA_PORT}"
            ;;
    esac
    echo ""
    
    # Vector Database Summary
    echo "  🔍 VECTOR DATABASE:"
    echo "    Type: ${VECTOR_DB_TYPE^}"
    case "$VECTOR_DB_TYPE" in
        qdrant)
            echo "    Port: ${QDRANT_PORT}"
            ;;
        weaviate)
            echo "    Port: ${WEAVIATE_PORT}"
            ;;
        chroma)
            echo "    Port: ${CHROMA_PORT}"
            ;;
        milvus)
            echo "    Port: ${MILVUS_PORT}"
            ;;
    esac
    echo ""
    
    # TLS Summary
    echo "  🔐 TLS:"
    echo "    Mode: ${TLS_MODE^}"
    case "$TLS_MODE" in
        letsencrypt)
            echo "    Email: ${LETSENCRYPT_EMAIL}"
            echo "    Staging: ${LETSENCRYPT_STAGING}"
            ;;
        manual)
            echo "    Certificate: ${TLS_CERT_FILE}"
            ;;
        selfsigned)
            echo "    Validity: ${SELF_SIGNED_DAYS} days"
            ;;
        none)
            echo "    ⚠️  HTTP only - not secure"
            ;;
    esac
    echo ""
    
    # API Keys Summary
    echo "  🔑 API KEYS:"
    local provider_count=0
    [[ "$ENABLE_OPENAI" == "true" ]] && { echo "    • OpenAI: ✅"; ((provider_count++)); }
    [[ "$ENABLE_ANTHROPIC" == "true" ]] && { echo "    • Anthropic: ✅"; ((provider_count++)); }
    [[ "$ENABLE_GOOGLE" == "true" ]] && { echo "    • Google AI: ✅"; ((provider_count++)); }
    [[ "$ENABLE_GROQ" == "true" ]] && { echo "    • Groq: ✅"; ((provider_count++)); }
    [[ "$ENABLE_COHERE" == "true" ]] && { echo "    • Cohere: ✅"; ((provider_count++)); }
    [[ "$ENABLE_HUGGINGFACE" == "true" ]] && { echo "    • Hugging Face: ✅"; ((provider_count++)); }
    [[ "$ENABLE_LOCAL_MODELS" == "true" ]] && { echo "    • Local Models: ✅"; ((provider_count++)); }
    
    if [[ $provider_count -eq 0 ]]; then
        echo "    ⚠️  No LLM providers configured"
    else
        echo "    Total providers: ${provider_count}"
    fi
    echo ""
    
    # System Resources
    echo "  💻 SYSTEM RESOURCES:"
    echo "    GPU: ${GPU_TYPE^}"
    [[ "$GPU_TYPE" != "none" ]] && echo "    GPU Memory: ${GPU_MEMORY}MB"
    echo "    RAM: ${TOTAL_RAM}MB total, ${AVAILABLE_RAM}MB available"
    echo "    Disk: ${DISK_SPACE} available"
    echo ""
    
    # Final Confirmation
    echo "  🎯 CONFIGURATION COMPLETE"
    echo "    All settings have been collected and validated"
    echo "    Ready to generate platform.conf and deploy"
    echo ""
    
    safe_read_yesno "Confirm and save configuration" "y" "CONFIRM_CONFIG"
    if [[ "$CONFIRM_CONFIG" != "true" ]]; then
        fail "Configuration cancelled by user"
    fi
}

# =============================================================================
# PLATFORM.CONF GENERATION (README §4.10)
# =============================================================================
write_platform_conf() {
    section "📝 GENERATING PLATFORM.CONF"
    
    local config_file="${DATA_DIR}/config/platform.conf"
    local temp_file="/tmp/platform.conf.$$"
    
    log "🎯 Generating comprehensive configuration file..."
    
    # Create temporary file
    cat > "$temp_file" << EOF
# =============================================================================
# AI Platform Configuration - Generated by Script 1
# Platform: ${PLATFORM_PREFIX}
# Tenant: ${TENANT_ID}
# Domain: ${DOMAIN}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

# =============================================================================
# IDENTITY CONFIGURATION
# =============================================================================
PLATFORM_PREFIX="${PLATFORM_PREFIX}"
TENANT_ID="${TENANT_ID}"
DOMAIN="${DOMAIN}"
ORGANIZATION="${ORGANIZATION}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================
DATA_DIR="${DATA_DIR}"
USE_EBS="${USE_EBS}"
EBS_DEVICE_PATTERN="${EBS_DEVICE_PATTERN:-/dev/sd[f-z]}"
EBS_FILESYSTEM="${EBS_FILESYSTEM:-ext4}"
EBS_MOUNT_OPTS="${EBS_MOUNT_OPTS:-defaults,noatime}"

# =============================================================================
# STACK CONFIGURATION
# =============================================================================
STACK_PRESET="${STACK_PRESET}"
STACK_NAME="${STACK_NAME}"

# Infrastructure Services
ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
ENABLE_REDIS="${ENABLE_REDIS:-false}"

# LLM Services
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
ENABLE_LITELLM="${ENABLE_LITELLM:-false}"

# Web Interfaces
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
ENABLE_LIBRECHAT="${ENABLE_LIBRECHAT:-false}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"

# Vector Databases
ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
ENABLE_CHROMA="${ENABLE_CHROMA:-false}"
ENABLE_MILVUS="${ENABLE_MILVUS:-false}"

# Automation
ENABLE_N8N="${ENABLE_N8N:-false}"
ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
ENABLE_DIFY="${ENABLE_DIFY:-false}"

# Development
ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"

# Monitoring
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"

# Authentication
ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"

# Additional Services
ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"

# =============================================================================
# LLM GATEWAY CONFIGURATION
# =============================================================================
LLM_GATEWAY_TYPE="${LLM_GATEWAY_TYPE}"

# LiteLLM Configuration
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-$(gen_secret)}"
LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-least-busy}"
LITELLM_ENABLE_LOGGING="${LITELLM_ENABLE_LOGGING:-true}"
LITELLM_ENABLE_COST_TRACKING="${LITELLM_ENABLE_COST_TRACKING:-true}"

# Bifrost Configuration
BIFROST_ADMIN_TOKEN="${BIFROST_ADMIN_TOKEN:-$(gen_secret)}"
BIFROST_API_KEY="${BIFROST_API_KEY:-$(gen_secret)}"
BIFROST_PORT="${BIFROST_PORT:-8000}"

# Direct Ollama Configuration
OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

# =============================================================================
# VECTOR DATABASE CONFIGURATION
# =============================================================================
VECTOR_DB_TYPE="${VECTOR_DB_TYPE}"

# Qdrant Configuration
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_API_KEY="${QDRANT_API_KEY:-$(gen_secret)}"
QDRANT_ENABLE_COLLECTIONS="${QDRANT_ENABLE_COLLECTIONS:-true}"

# Weaviate Configuration
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
WEAVIATE_API_KEY="${WEAVIATE_API_KEY:-$(gen_secret)}"
WEAVIATE_ENABLE_AUTH="${WEAVIATE_ENABLE_AUTH:-true}"

# ChromaDB Configuration
CHROMA_PORT="${CHROMA_PORT:-8000}"
CHROMA_AUTH_TOKEN="${CHROMA_AUTH_TOKEN:-$(gen_secret)}"

# Milvus Configuration
MILVUS_PORT="${MILVUS_PORT:-19530}"
MILVUS_API_KEY="${MILVUS_API_KEY:-$(gen_secret)}"

# =============================================================================
# TLS CONFIGURATION
# =============================================================================
TLS_MODE="${TLS_MODE}"

# Let's Encrypt Configuration
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-${ADMIN_EMAIL}}"
LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
LETSENCRYPT_AUTO_RENEW="${LETSENCRYPT_AUTO_RENEW:-true}"

# Manual TLS Configuration
TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/ssl/certs/${DOMAIN}.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/ssl/private/${DOMAIN}.key}"

# Self-Signed TLS Configuration
SELF_SIGNED_DAYS="${SELF_SIGNED_DAYS:-365}"
CERT_COUNTRY="${CERT_COUNTRY:-US}"
CERT_STATE="${CERT_STATE:-California}"
CERT_CITY="${CERT_CITY:-San Francisco}"
CERT_ORG="${CERT_ORG:-${ORGANIZATION}}"

# =============================================================================
# API KEY CONFIGURATION
# =============================================================================

# OpenAI Configuration
ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_ORG_ID="${OPENAI_ORG_ID:-}"
OPENAI_MODELS="${OPENAI_MODELS:-gpt-4,gpt-3.5-turbo}"

# Anthropic Configuration
ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
ANTHROPIC_MODELS="${ANTHROPIC_MODELS:-claude-3-sonnet-20240229,claude-3-haiku-20240307}"

# Google AI Configuration
ENABLE_GOOGLE="${ENABLE_GOOGLE:-false}"
GOOGLE_AI_API_KEY="${GOOGLE_AI_API_KEY:-}"
GOOGLE_MODELS="${GOOGLE_MODELS:-gemini-pro,gemini-pro-vision}"

# Groq Configuration
ENABLE_GROQ="${ENABLE_GROQ:-false}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
GROQ_MODELS="${GROQ_MODELS:-llama2-70b-4096,mixtral-8x7b-32768}"

# Cohere Configuration
ENABLE_COHERE="${ENABLE_COHERE:-false}"
COHERE_API_KEY="${COHERE_API_KEY:-}"
COHERE_MODELS="${COHERE_MODELS:-command,command-nightly,command-light}"

# Hugging Face Configuration
ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE:-false}"
HUGGINGFACE_API_KEY="${HUGGINGFACE_API_KEY:-}"
HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-microsoft/DialoGPT-medium,google/flan-t5-base}"

# Local Models Configuration
ENABLE_LOCAL_MODELS="${ENABLE_LOCAL_MODELS:-true}"
OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1:8b,mistral:7b}"
OLLAMA_AUTO_DOWNLOAD="${OLLAMA_AUTO_DOWNLOAD:-true}"

# =============================================================================
# PORT CONFIGURATION
# =============================================================================

# Core Infrastructure Ports
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"

# LLM Service Ports
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"

# Web Interface Ports
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
LIBRECHAT_PORT="${LIBRECHAT_PORT:-3080}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3081}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3082}"

# Vector Database Ports
QDRANT_PORT="${QDRANT_PORT:-6333}"
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
CHROMA_PORT="${CHROMA_PORT:-8000}"
MILVUS_PORT="${MILVUS_PORT:-19530}"

# Automation Ports
N8N_PORT="${N8N_PORT:-5678}"
FLOWISE_PORT="${FLOWISE_PORT:-3000}"
DIFY_PORT="${DIFY_PORT:-3001}"

# Development Ports
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"

# Monitoring Ports
GRAFANA_PORT="${GRAFANA_PORT:-3001}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

# Authentication Ports
AUTHENTIK_PORT="${AUTHENTIK_PORT:-9000}"

# Additional Ports
SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"

# =============================================================================
# SYSTEM CONFIGURATION
# =============================================================================

# Docker Configuration
DOCKER_NETWORK="${TENANT_ID}-network"
COMPOSE_FILE="${DATA_DIR}/config/docker-compose.yml"

# Logging Configuration
LOG_DIR="${DATA_DIR}/logs"
LOG_LEVEL="info"

# GPU Configuration
GPU_TYPE="${GPU_TYPE:-none}"
GPU_MEMORY="${GPU_MEMORY:-0}"

# Memory Configuration
TOTAL_RAM="${TOTAL_RAM}"
AVAILABLE_RAM="${AVAILABLE_RAM}"

# Network Configuration
HOST_MTU="${HOST_MTU:-1500}"

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

# Generate secure passwords
POSTGRES_PASSWORD="$(gen_password)"
REDIS_PASSWORD="$(gen_password)"
N8N_ENCRYPTION_KEY="$(gen_secret)"
GRAFANA_ADMIN_PASSWORD="$(gen_password)"

# Export all variables
export POSTGRES_PASSWORD
export REDIS_PASSWORD
export N8N_ENCRYPTION_KEY
export GRAFANA_ADMIN_PASSWORD

# =============================================================================
# END OF CONFIGURATION
# =============================================================================
EOF

    # Move to final location
    mkdir -p "$(dirname "$config_file")"
    mv "$temp_file" "$config_file"
    
    # Set permissions
    chmod 600 "$config_file"
    
    echo "  ✅ Configuration saved to: $config_file"
    echo "  📊 Total variables: $(grep -c '^[A-Z_]*=' "$config_file")"
    echo "  🔐 File permissions: 600 (secure)"
}

# =============================================================================
# TENANT USER CREATION (README §4.11)
# =============================================================================
create_tenant_user() {
    section "👤 TENANT USER CREATION"
    
    local username="${PLATFORM_PREFIX}${TENANT_ID}"
    
    echo "  📋 Creating system user for tenant: ${TENANT_ID}"
    echo ""
    
    # Check if user already exists
    if id "$username" >/dev/null 2>&1; then
        echo "  ✅ User '$username' already exists"
        echo "  🔄 Updating user groups and permissions..."
        
        # Add to docker group
        usermod -aG docker "$username" 2>/dev/null || {
            warn "Could not add user to docker group"
            warn "Manual intervention may be required"
        }
        
        # Update home directory
        usermod -d "/home/$username" "$username" 2>/dev/null || true
        
    else
        echo "  👤 Creating new user: $username"
        
        # Create user with home directory
        useradd -m -s /bin/bash "$username" || {
            fail "Failed to create user $username"
        }
        
        # Add to docker group
        usermod -aG docker "$username" || {
            warn "Could not add user to docker group"
            warn "Manual intervention may be required"
        }
        
        echo "  ✅ User '$username' created successfully"
    fi
    
    # Create user directories
    echo ""
    echo "  📁 Setting up user directories..."
    
    local user_home="/home/$username"
    local user_config="$user_home/.ai-platform"
    
    mkdir -p "$user_config/logs" "$user_config/data"
    chown -R "$username:$username" "$user_home"
    
    # Create user's .env file with essential variables
    cat > "$user_config/.env" << EOF
# AI Platform Environment for $username
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Basic Configuration
PLATFORM_PREFIX="${PLATFORM_PREFIX}"
TENANT_ID="${TENANT_ID}"
DOMAIN="${DOMAIN}"
DATA_DIR="${DATA_DIR}"

# Essential Paths
CONFIG_DIR="${DATA_DIR}/config"
LOG_DIR="${DATA_DIR}/logs"
COMPOSE_FILE="${DATA_DIR}/config/docker-compose.yml"

# Docker Configuration
DOCKER_NETWORK="${DOCKER_NETWORK}"
EOF
    
    chown "$username:$username" "$user_config/.env"
    chmod 600 "$user_config/.env"
    
    echo "  ✅ User setup complete"
    echo "  🏠 Home directory: $user_home"
    echo "  📁 Config directory: $user_config"
    echo "  🔐 .env file: $user_config/.env"
    echo ""
    echo "  📋 USER SUMMARY:"
    echo "    Username: $username"
    echo "    UID: $(id -u "$username")"
    echo "    Groups: $(id -Gn "$username" | tr ' ' ',')"
    echo "    Shell: $(getent passwd "$username" | cut -d: -f7)"
    echo ""
    echo "  🎯 User '$username' is ready for platform management"
}

# =============================================================================
# INTERACTIVE COLLECTION FUNCTIONS
# =============================================================================
run_interactive_collection() {
    banner
    
    detect_system
    collect_identity
    configure_storage
    select_stack_preset
    configure_llm_gateway
    configure_vector_database
    configure_tls
    collect_api_keys
    configure_ports
    show_configuration_summary
    write_platform_conf
    create_tenant_user
}

# =============================================================================
# TEMPLATE GENERATION
# =============================================================================

save_configuration_template() {
    local template_path="${1:-}"
    
    if [[ -z "$template_path" ]]; then
        # Default template location (outside git repo)
        template_path="${HOME}/.ai-platform-templates/${TENANT_ID}-template.conf"
    fi
    
    # Create template directory if it doesn't exist
    mkdir -p "$(dirname "$template_path")"
    
    log "💾 Saving configuration template: $template_path"
    
    # Create template file with all configuration variables (excluding secrets)
    cat > "$template_path" << EOF
# =============================================================================
# AI Platform Configuration Template
# Generated: $(date)
# Tenant: ${TENANT_ID}
# =============================================================================
# USAGE: bash scripts/1-setup-system.sh ${TENANT_ID} --template "$template_path"
# =============================================================================

# =============================================================================
# IDENTITY CONFIGURATION
# =============================================================================
PLATFORM_PREFIX="${PLATFORM_PREFIX}"
TENANT_ID="${TENANT_ID}"
DOMAIN="${DOMAIN}"
ORGANIZATION="${ORGANIZATION}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================
USE_EBS="${USE_EBS}"
EBS_DEVICE="${EBS_DEVICE}"
EBS_MOUNT_POINT="${EBS_MOUNT_POINT}"
DATA_DIR="${DATA_DIR}"

# =============================================================================
# STACK PRESET CONFIGURATION
# =============================================================================
STACK_PRESET="${STACK_PRESET}"

# =============================================================================
# LLM GATEWAY CONFIGURATION
# =============================================================================
ENABLE_LITELLM="${ENABLE_LITELLM}"
ENABLE_BIFROST="${ENABLE_BIFROST}"
ENABLE_DIRECT_OLLAMA="${ENABLE_DIRECT_OLLAMA}"

# =============================================================================
# VECTOR DATABASE CONFIGURATION
# =============================================================================
VECTOR_DB="${VECTOR_DB}"

# =============================================================================
# TLS CONFIGURATION
# =============================================================================
TLS_MODE="${TLS_MODE}"
TLS_EMAIL="${TLS_EMAIL:-}"
TLS_CERT_PATH="${TLS_CERT_PATH:-}"
TLS_KEY_PATH="${TLS_KEY_PATH:-}"

# =============================================================================
# SERVICE PORTS CONFIGURATION
# =============================================================================
POSTGRES_PORT="${POSTGRES_PORT}"
REDIS_PORT="${REDIS_PORT}"
OLLAMA_PORT="${OLLAMA_PORT}"
LITELLM_PORT="${LITELLM_PORT}"
OPENWEBUI_PORT="${OPENWEBUI_PORT}"
QDRANT_PORT="${QDRANT_PORT}"
WEAVIATE_PORT="${WEAVIATE_PORT}"
CHROMADB_PORT="${CHROMADB_PORT}"
MILVUS_PORT="${MILVUS_PORT}"
N8N_PORT="${N8N_PORT}"
FLOWISEAI_PORT="${FLOWISEAI_PORT}"
LANGFLOW_PORT="${LANGFLOW_PORT}"
CODE_SERVER_PORT="${CODE_SERVER_PORT}"
CONTINUE_DEV_PORT="${CONTINUE_DEV_PORT}"
MEM0_PORT="${MEM0_PORT}"
NGINX_PORT="${NGINX_PORT}"
CADDY_HTTP_PORT="${CADDY_HTTP_PORT}"
CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT}"

# =============================================================================
# SERVICE ENABLEMENT FLAGS
# =============================================================================
ENABLE_POSTGRES="${ENABLE_POSTGRES}"
ENABLE_REDIS="${ENABLE_REDIS}"
ENABLE_OLLAMA="${ENABLE_OLLAMA}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI}"
ENABLE_QDRANT="${ENABLE_QDRANT}"
ENABLE_WEAVIATE="${ENABLE_WEAVIATE}"
ENABLE_CHROMADB="${ENABLE_CHROMADB}"
ENABLE_MILVUS="${ENABLE_MILVUS}"
ENABLE_N8N="${ENABLE_N8N}"
ENABLE_FLOWISEAI="${ENABLE_FLOWISEAI}"
ENABLE_LANGFLOW="${ENABLE_LANGFLOW}"
ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER}"
ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV}"
ENABLE_MEM0="${ENABLE_MEM0}"
ENABLE_NGINX="${ENABLE_NGINX}"
ENABLE_CADDY="${ENABLE_CADDY}"

# =============================================================================
# LLM PROVIDER CONFIGURATION (API KEYS - SECURE)
# =============================================================================
# Note: API keys are stored in platform.conf for security
# Template shows which providers are enabled
ENABLE_OPENAI="${ENABLE_OPENAI}"
ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC}"
ENABLE_GOOGLE="${ENABLE_GOOGLE}"
ENABLE_GROQ="${ENABLE_GROQ}"
ENABLE_COHERE="${ENABLE_COHERE}"
ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE}"
ENABLE_OLLAMA_PROVIDER="${ENABLE_OLLAMA_PROVIDER}"

# =============================================================================
# END OF TEMPLATE
# =============================================================================
# This template can be used to recreate the same configuration:
# bash scripts/1-setup-system.sh ${TENANT_ID} --template "$template_path"
# =============================================================================
EOF

    # Set secure permissions
    chmod 600 "$template_path"
    
    ok "Configuration template saved to: $template_path"
    ok "Template permissions set to 600 (secure)"
    
    echo ""
    echo "📋 TEMPLATE USAGE:"
    echo "  To reuse this configuration:"
    echo "    bash scripts/1-setup-system.sh ${TENANT_ID} --template '$template_path'"
    echo ""
    echo "  To edit the template:"
    echo "    nano '$template_path'"
    echo ""
    echo "  Template location (outside git repo):"
    echo "    ${HOME}/.ai-platform-templates/"
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local template_file=""
    local preserve_secrets=false
    local generate_new=false
    local deployment_mode=""
    local dry_run=false
    local save_template=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ingest-from)
                template_file="$2"
                shift 2
                ;;
            --preserve-secrets)
                preserve_secrets=true
                shift
                ;;
            --generate-new)
                generate_new=true
                shift
                ;;
            --deployment-mode)
                deployment_mode="$2"
                shift 2
                ;;
            --template)
                template_file="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --save-template)
                save_template="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$tenant_id" ]]; then
                    tenant_id="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Display banner
    banner
    
    # Set up tenant-specific logging
    local TENANT_LOG_FILE="/tmp/ai-platform-setup-$(date +%Y%m%d-%H%M%S).log"
    
    log "🚀 === Script 1: System Setup & Input Collection ==="
    log "📋 Version: ${SCRIPT_VERSION}"
    log "👤 Tenant: $tenant_id"
    log "🔧 Dry-run: ${dry_run}"
    log "📥 Template file: ${template_file}"
    log "🔒 Preserve secrets: ${preserve_secrets}"
    log "🆕 Generate new: ${generate_new}"
    log "🎯 Deployment mode: ${deployment_mode}"
    log "💾 Save template: ${save_template}"
    
    # Run interactive collection or template processing
    if [[ -n "$template_file" ]]; then
        log "📄 Processing template file: $template_file"
        # TODO: Implement template processing
        fail "Template processing not yet implemented"
    else
        run_interactive_collection
    fi
    
    # Create idempotency marker
    mkdir -p "${DATA_DIR}/.configured"
    touch "${DATA_DIR}/.configured/setup-system"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              🎉 SYSTEM SETUP COMPLETE 🎉                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✅ All configuration collected and validated"
    echo "  ✅ platform.conf generated: ${DATA_DIR}/config/platform.conf"
    echo "  ✅ Tenant user created: ${PLATFORM_PREFIX}${TENANT_ID}"
    echo "  ✅ Directory structure created: ${DATA_DIR}"
    echo "  ✅ Ready for Script 2: Deployment Engine"
    echo ""
    echo "  📋 NEXT STEPS:"
    echo "    1. Review configuration: cat ${DATA_DIR}/config/platform.conf"
    echo "    2. Run deployment: bash scripts/2-deploy-services.sh ${TENANT_ID}"
    echo "    3. Monitor services: bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo ""
    echo "  🔐 IMPORTANT:"
    echo "    • All API keys are stored securely in platform.conf"
    echo "    • File permissions are set to 600 (owner read only)"
    echo "    • Keep this configuration file secure and backed up"
    echo ""
    
    # Template generation prompt
    if [[ -z "$template_file" ]]; then
        echo ""
        echo "💾 SAVE CONFIGURATION TEMPLATE?"
        echo "  Save your configuration as a reusable template for future deployments:"
        echo ""
        
        # Default template path
        local default_template="${HOME}/.ai-platform-templates/${TENANT_ID}-template.conf"
        
        safe_read_yesno "Save configuration template to ${default_template}?" "true" "SAVE_TEMPLATE"
        
        if [[ "$SAVE_TEMPLATE" == "true" ]]; then
            safe_read "Template path (or press Enter for default):" "$default_template" "CUSTOM_TEMPLATE_PATH"
            save_configuration_template "$CUSTOM_TEMPLATE_PATH"
        else
            echo ""
            echo "ℹ️  Template not saved. You can create one later by running:"
            echo "    bash scripts/1-setup-system.sh ${TENANT_ID} --save-template <path>"
        fi
    fi
    
    # If save template was specified via command line
    if [[ -n "$save_template" ]]; then
        save_configuration_template "$save_template"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
