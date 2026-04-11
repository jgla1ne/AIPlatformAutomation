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

# Allow interactive mode to continue even if individual commands fail
set -uo pipefail

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
# ENHANCED MENU SELECTION FUNCTIONS
# =============================================================================
select_menu_option() {
    local title="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    
    # Handle non-TTY case (piped input) - use default option
    if [[ ! -t 0 ]]; then
        # Try to read from piped input
        local choice
        if read -t 5 choice 2>/dev/null; then
            # Validate choice
            if [[ "$choice" =~ ^[1-9]$ ]] && [[ $choice -le $count ]]; then
                return $((choice-1))
            fi
        fi
        # Default to first option if no valid input
        echo "  🎯 $title (auto-selecting option 1: ${options[0]})"
        return 0
    fi
    
    # Real TTY - show menu
    echo "  🎯 $title:"
    echo ""
    
    local i=1
    for option in "${options[@]}"; do
        echo "    $i) $option"
        ((i++))
    done
    echo ""
    
    while true; do
        read -rp "  🎯 Select option [1-$count]: " choice
        
        if [[ "$choice" =~ ^[1-9]$ ]] && [[ $choice -le $count ]]; then
            echo "  ✅ Selected: ${options[$((choice-1))]}"
            return $((choice-1))
        else
            echo "  ❌ Invalid selection. Please enter a number between 1 and $count"
        fi
    done
}

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
                echo -n "  🎯 ${prompt} [${default}]: "
                read -r value
                if [[ -z "$value" ]]; then
                    value="$default"
                fi
            else
                echo -n "  🎯 ${prompt}: "
                read -r value
            fi
            
            # Check if value is empty for required fields
            if [[ -z "$value" && -z "$default" ]]; then
                echo "  ❌ This field is required. Please enter a value."
                ((attempts++))
                continue
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
        # Non-TTY — try to read from piped input first, then use default
        if read -t 5 value 2>/dev/null; then
            # Successfully read from pipe
            value="${value:-${default}}"
            echo "  🎯 ${prompt}: ${value} (pipelined input)"
        else
            # No piped input, use default
            value="${default}"
            echo "  🎯 ${prompt}: ${value} (default — non-interactive mode)"
        fi
    fi

    printf -v "${varname}" '%s' "${value}"
}

safe_read_yesno() {
    local prompt="$1"
    local default="${2:-n}"
    local varname="$3"
    local value
    local attempts=0
    local max_attempts=3

    # Convert boolean defaults to y/n
    case "${default,,}" in
        true|yes) default="y" ;;
        false|no) default="n" ;;
    esac

    # Real TTY - show prompt and wait for input
    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -n "$default" ]]; then
            if [[ "$default" == "y" ]]; then
                echo -n "  🤔 ${prompt} [Y/n]: "
                if ! read -r value 2>/dev/null; then
                    echo ""
                    echo "  ⏰ Input timeout - using default: $default"
                    value="$default"
                fi
            else
                echo -n "  🤔 ${prompt} [y/N]: "
                if ! read -r value 2>/dev/null; then
                    echo ""
                    echo "  ⏰ Input timeout - using default: $default"
                    value="$default"
                fi
            fi
        else
            echo -n "  🤔 ${prompt} [y/N]: "
            if ! read -r value 2>/dev/null; then
                echo ""
                echo "  ⏰ Input timeout - using default: n"
                value="n"
            fi
        fi
        
        value="${value:-${default}}"
        
        case "${value,,}" in
            y|yes) 
                value="true" 
                echo "  ✅ ${prompt}: $value"
                printf -v "${varname}" '%s' "$value"
                return 0
                ;;
            n|no) 
                value="false"
                echo "  ✅ ${prompt}: $value"
                printf -v "${varname}" '%s' "$value"
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
    
    safe_read_yesno "Confirm identity configuration" "y" "IDENTITY_CONFIRMED"
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
    
    # Direct to EBS detection and selection
    detect_and_select_ebs
    
    # Create mount point directory
    mkdir -p "/mnt/${TENANT_ID}"
    
    # Set data directory
    DATA_DIR="/mnt/${TENANT_ID}"
    
    # Set defaults for EBS configuration
    EBS_DEVICE_PATTERN="${EBS_DEVICE_PATTERN:-/dev/sd[f-z]}"
    EBS_FILESYSTEM="${EBS_FILESYSTEM:-ext4}"
    
    log "OK: Storage configuration complete"
}

# CORRECTED EBS detection using fdisk and Amazon EBS identification
detect_and_select_ebs() {
    echo ""
    echo "🔍 Scanning for Amazon EBS volumes..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local count=1
    local devices=()
    local descriptions=()
    
    # Use fdisk -l to find EBS volumes by looking for "Amazon Elastic Block Store"
    while IFS= read -r line; do
        if [[ "$line" =~ ^Disk\ /dev/.*:\ .* ]]; then
            local disk=$(echo "$line" | awk '{print $2}' | sed 's/://')
            local size=$(echo "$line" | awk '{print $3}' | sed 's/,//')
            
            # Check if this is an EBS volume by examining its description
            if fdisk -l "$disk" 2>/dev/null | grep -q "Amazon Elastic Block Store"; then
                devices+=("$disk")
                descriptions+=("$disk - Amazon EBS Volume ($size)")
                ((count++))
            fi
        fi
    done < <(fdisk -l 2>/dev/null | grep "^Disk /dev/")
    
    # Add OS disk option
    devices+=("")
    descriptions+=("Use existing /mnt/${TENANT_ID}/ on OS disk (no separate volume)")
    
    # Use menu system for selection
    if [[ ${#devices[@]} -gt 1 ]]; then
        select_menu_option "EBS Volume Selection" "${descriptions[@]}"
        local choice=$?
        
        if [[ $choice -eq $((${#devices[@]}-1)) ]]; then
            echo "✅ Selected: OS disk storage"
            EBS_DEVICE=""
            USE_EBS="false"
        else
            EBS_DEVICE="${devices[$choice]}"
            echo "✅ Selected: $EBS_DEVICE"
            USE_EBS="true"
            # Format and mount the selected EBS volume
            format_and_mount_ebs
        fi
    else
        echo ""
        echo "⚠️  No EBS volumes found."
        echo "   This is normal if running on local instances or non-AWS environments."
        echo "   Will use OS disk for storage."
        echo ""
        EBS_DEVICE=""
        USE_EBS="false"
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
    
    select_menu_option "Stack Preset Selection" \
        "MINIMAL - PostgreSQL + Redis + LiteLLM + Ollama + OpenWebUI + Qdrant (~4GB RAM)" \
        "DEVELOPMENT - All Minimal + Code Server + Dev tools (~6GB RAM)" \
        "STANDARD - All Development + N8N + Flowise + Grafana + Prometheus (~8GB RAM)" \
        "FULL - All Standard + All web interfaces + Complete monitoring (~16GB RAM)" \
        "CUSTOM - Select individual services (full control)"
    local preset_choice=$?
    
    case $preset_choice in
        0) STACK_PRESET="1"; STACK_NAME="minimal" ;;
        1) STACK_PRESET="2"; STACK_NAME="development" ;;
        2) STACK_PRESET="3"; STACK_NAME="standard" ;;
        3) STACK_PRESET="4"; STACK_NAME="full" ;;
        4) STACK_PRESET="5"; STACK_NAME="custom" ;;
    esac
    
    echo ""
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
    
    select_menu_option "LLM Gateway Selection" \
        "LITELLM - Unified API for multiple providers with load balancing" \
        "BIFROST - Advanced gateway with enterprise features" \
        "DIRECT OLLAMA - Simple direct access to local models"
    local gateway_choice=$?
    
    case $gateway_choice in
        0) LLM_GATEWAY_TYPE="litellm" ;;
        1) LLM_GATEWAY_TYPE="bifrost" ;;
        2) LLM_GATEWAY_TYPE="direct" ;;
    esac
    
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
    
    # Use menu selection for routing strategy
    select_menu_option "LiteLLM Load Balancing Strategy" \
        "cost-optimized (Prefer local models, fallback to external)" \
        "least-busy (Route to least busy model)" \
        "weighted (Weighted round-robin)" \
        "simple (Round-robin)" \
        "performance-first (Prefer fastest response time)"
    local routing_choice=$?
    case $routing_choice in
        0) LITELLM_ROUTING_STRATEGY="cost-optimized" ;;
        1) LITELLM_ROUTING_STRATEGY="least-busy" ;;
        2) LITELLM_ROUTING_STRATEGY="weighted" ;;
        3) LITELLM_ROUTING_STRATEGY="simple" ;;
        4) LITELLM_ROUTING_STRATEGY="performance-first" ;;
    esac
    
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
    
    select_menu_option "Vector Database Selection" \
        "QDRANT - High-performance vector search with built-in filtering" \
        "WEAVIATE - Enterprise GraphQL API with multi-modal support" \
        "CHROMADB - Lightweight Python-focused database" \
        "MILVUS - Distributed cloud-native massive scale database"
    local vector_choice=$?
    
    case $vector_choice in
        0) VECTOR_DB_TYPE="qdrant" ;;
        1) VECTOR_DB_TYPE="weaviate" ;;
        2) VECTOR_DB_TYPE="chroma" ;;
        3) VECTOR_DB_TYPE="milvus" ;;
    esac
    
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
    
    select_menu_option "TLS Certificate Selection" \
        "LET'S ENCRYPT - Automatic free certificates for production" \
        "MANUAL CERTIFICATES - Use existing certificates with manual renewal" \
        "SELF-SIGNED - Quick setup for development/testing" \
        "HTTP ONLY - No HTTPS (not recommended for production)" \
        "HTTPS REDIRECT - Force all HTTP traffic to HTTPS"
    local tls_choice=$?
    
    case $tls_choice in
        0) TLS_MODE="letsencrypt" ;;
        1) TLS_MODE="manual" ;;
        2) TLS_MODE="selfsigned" ;;
        3) TLS_MODE="none" ;;
        4) TLS_MODE="letsencrypt"; HTTP_TO_HTTPS_REDIRECT="true" ;;
    esac
    
    # Ask about HTTP to HTTPS redirect (unless already set)
    if [[ "$TLS_MODE" != "none" && "$HTTP_TO_HTTPS_REDIRECT" != "true" ]]; then
        echo ""
        safe_read_yesno "Enable HTTP to HTTPS redirect" "true" "HTTP_TO_HTTPS_REDIRECT"
    elif [[ "$TLS_MODE" == "none" ]]; then
        HTTP_TO_HTTPS_REDIRECT="false"
    fi
    
    case "$TLS_MODE" in
        letsencrypt)
            configure_letsencrypt
            ;;
        manual)
            configure_manual_tls
            ;;
        selfsigned)
            configure_selfsigned_tls
            ;;
        none)
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
    
    # Now configure individual providers first
    
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
    
    # OpenRouter
    echo "  🌐 OpenRouter Configuration:"
    safe_read_yesno "Enable OpenRouter" "false" "ENABLE_OPENROUTER"
    if [[ "$ENABLE_OPENROUTER" == "true" ]]; then
        safe_read "OpenRouter API key" "" "OPENROUTER_API_KEY" "^sk-or-[A-Za-z0-9_-]+$"
        safe_read "OpenRouter models" "anthropic/claude-3-sonnet,openai/gpt-4" "OPENROUTER_MODELS"
    fi
    echo ""
    
    # Local Models (Ollama)
    echo "  🦙 Local Models Configuration:"
    safe_read_yesno "Enable local models" "true" "ENABLE_LOCAL_MODELS"
    if [[ "$ENABLE_LOCAL_MODELS" == "true" ]]; then
        select_ollama_models
        safe_read_yesno "Auto-download models" "true" "OLLAMA_AUTO_DOWNLOAD"
    fi
    echo ""
    
    # Preferred LLM Provider for routing (after model configuration)
    echo "  🎯 Select your preferred LLM provider for LiteLLM routing priority:"
    echo "     This determines which provider gets first priority when multiple are available"
    echo ""
    select_menu_option "Preferred LLM Provider (Routing Priority)" \
        "OpenAI - GPT-4 and GPT-3.5 models" \
        "Anthropic Claude - Claude 3 family" \
        "Google AI - Gemini models" \
        "Groq - Fast inference with Llama models" \
        "Cohere - Command models" \
        "Hugging Face - Open model hub" \
        "Local Ollama - Self-hosted models" \
        "OpenRouter - Multi-provider aggregator"
    local preferred_provider_choice=$?
    
    case $preferred_provider_choice in
        0) PREFERRED_LLM_PROVIDER="openai" ;;
        1) PREFERRED_LLM_PROVIDER="anthropic" ;;
        2) PREFERRED_LLM_PROVIDER="google" ;;
        3) PREFERRED_LLM_PROVIDER="groq" ;;
        4) PREFERRED_LLM_PROVIDER="cohere" ;;
        5) PREFERRED_LLM_PROVIDER="huggingface" ;;
        6) PREFERRED_LLM_PROVIDER="ollama" ;;
        7) PREFERRED_LLM_PROVIDER="openrouter" ;;
    esac
    
    echo ""
    echo "  ✅ Preferred provider for routing: ${PREFERRED_LLM_PROVIDER^}"
    echo ""
}

# =============================================================================
# OLLAMA MODEL SELECTION
# =============================================================================
select_ollama_models() {
    echo ""
    echo "  🦙 Available Ollama Models:"
    echo ""
    
    # Model groups
    echo "  📦 Small Models (< 4GB RAM):"
    echo "    1) Llama 3.1 8B - General purpose, good balance"
    echo "    2) Mistral 7B - Fast, efficient for most tasks"
    echo "    3) Phi-3 Mini 3.8B - Microsoft's compact model"
    echo "    4) Gemma 2B - Google's lightweight model"
    echo ""
    
    echo "  📦 Medium Models (4-8GB RAM):"
    echo "    5) Llama 3.1 70B - High performance, larger context"
    echo "    6) Mixtral 8x7B - Mixture of experts, excellent reasoning"
    echo "    7) Qwen 72B - Strong multilingual capabilities"
    echo ""
    
    echo "  📦 Large Models (8-16GB+ RAM):"
    echo "    8) CodeLlama 70B - Specialized for code generation"
    echo "    9) Llama 3 8B Chat - Optimized for conversations"
    echo "   10) Deepseek Coder 33B - Advanced coding assistant"
    echo ""
    
    echo "  🎯 Select models (comma-separated numbers, e.g., 1,3,5):"
    echo -n "  🎯 Models selection [1-10]: "
    read -r selection
    
    if [[ -z "$selection" ]]; then
        selection="1,2"  # Default: Llama 3.1 8B + Mistral 7B
    fi
    
    # Convert selection to model names
    local models=""
    IFS=',' read -ra selections <<< "$selection"
    for num in "${selections[@]}"; do
        case "${num// /}" in
            1) models="${models:+$models,}llama3.1:8b" ;;
            2) models="${models:+$models,}mistral:7b" ;;
            3) models="${models:+$models,}phi3:mini" ;;
            4) models="${models:+$models,}gemma:2b" ;;
            5) models="${models:+$models,}llama3.1:70b" ;;
            6) models="${models:+$models,}mixtral:8x7b" ;;
            7) models="${models:+$models,}qwen:72b" ;;
            8) models="${models:+$models,}codellama:70b" ;;
            9) models="${models:+$models,}llama3:8b" ;;
            10) models="${models:+$models,}deepseek-coder:33b" ;;
            *) echo "  ⚠️  Invalid selection: $num (skipping)" ;;
        esac
    done
    
    if [[ -n "$models" ]]; then
        OLLAMA_MODELS="$models"
        echo "  ✅ Selected models: $OLLAMA_MODELS"
    else
        OLLAMA_MODELS="llama3.1:8b,mistral:7b"
        echo "  ⚠️  No valid models selected, using defaults: $OLLAMA_MODELS"
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

# =============================================================================
# PROXY CONFIGURATION (README §4.8)
# =============================================================================
configure_proxy() {
    section "🌐 PROXY CONFIGURATION"
    
    echo "  📋 Configure proxy settings for external access"
    echo ""
    
    safe_read_yesno "Enable proxy server" "false" "ENABLE_PROXY"
    if [[ "$ENABLE_PROXY" == "true" ]]; then
        echo ""
        select_menu_option "Proxy Type" \
            "NGINX - High performance web server" \
            "CADDY - Automatic HTTPS with Let's Encrypt"
        local proxy_type_choice=$?
        
        case $proxy_type_choice in
            0) PROXY_TYPE="nginx" ;;
            1) PROXY_TYPE="caddy" ;;
        esac
        
        echo ""
        echo "  🔄 Routing Configuration:"
        select_menu_option "Routing Method" \
            "PATH_BASED - Use URL paths (e.g., /ollama, /webui)" \
            "SUBDOMAIN - Use subdomains (e.g., ollama.domain.com)"
        local routing_choice=$?
        
        case $routing_choice in
            0) PROXY_ROUTING="path_based" ;;
            1) PROXY_ROUTING="subdomain" ;;
        esac
        
        echo ""
        safe_read "Proxy HTTP port" "80" "PROXY_HTTP_PORT" "^[0-9]+$"
        safe_read "Proxy HTTPS port" "443" "PROXY_HTTPS_PORT" "^[0-9]+$"
        
        if [[ "$TLS_MODE" != "none" ]]; then
            safe_read_yesno "Force HTTPS redirect" "true" "PROXY_FORCE_HTTPS"
        else
            PROXY_FORCE_HTTPS="false"
        fi
        
        echo ""
        echo "  ✅ Proxy Configuration:"
        echo "    Type: ${PROXY_TYPE^}"
        echo "    Routing: ${PROXY_ROUTING/_/ }"
        echo "    HTTP Port: $PROXY_HTTP_PORT"
        echo "    HTTPS Port: $PROXY_HTTPS_PORT"
        echo "    Force HTTPS: $PROXY_FORCE_HTTPS"
    else
        echo "  ℹ️  Proxy disabled - services will be accessed directly via ports"
    fi
    echo ""
}

# =============================================================================
# GOOGLE DRIVE INTEGRATION (README §4.9)
# =============================================================================
configure_google_drive() {
    section "📁 GOOGLE DRIVE INTEGRATION"
    
    echo "  📋 Configure Google Drive backup and sync"
    echo ""
    
    safe_read_yesno "Enable Google Drive integration" "false" "ENABLE_GDRIVE"
    if [[ "$ENABLE_GDRIVE" == "true" ]]; then
        echo ""
        safe_read "Google Drive Folder ID" "" "GDRIVE_FOLDER_ID"
        safe_read "Google Drive Folder Name [AI Platform]" "AI Platform" "GDRIVE_FOLDER_NAME"
        
        echo ""
        echo "  ✅ Google Drive Configuration:"
        echo "    Folder ID: ${GDRIVE_FOLDER_ID:-Not set}"
        echo "    Folder Name: $GDRIVE_FOLDER_NAME"
    else
        echo "  ℹ️  Google Drive integration disabled"
    fi
    echo ""
}

# =============================================================================
# SIGNAL-BOT CONFIGURATION (README §4.13)
# =============================================================================
configure_signalbot() {
    section "📡 SIGNAL-BOT CONFIGURATION"
    
    echo "  📋 Configure Signal bot for notifications"
    echo ""
    
    safe_read_yesno "Enable Signal bot" "false" "ENABLE_SIGNALBOT"
    if [[ "$ENABLE_SIGNALBOT" == "true" ]]; then
        echo ""
        safe_read "Signal phone number (E.164 format, e.g., +15551234567)" "" "SIGNAL_PHONE" "^\+[1-9][0-9]{1,14}$"
        safe_read "Signal recipient number (E.164 format)" "" "SIGNAL_RECIPIENT" "^\+[1-9][0-9]{1,14}$"
        safe_read "Signal bot port" "8080" "SIGNALBOT_PORT" "^[0-9]+$"
        
        echo ""
        echo "  ✅ Signal Bot Configuration:"
        echo "    Phone Number: $SIGNAL_PHONE"
        echo "    Recipient: $SIGNAL_RECIPIENT"
        echo "    Port: $SIGNALBOT_PORT"
    else
        echo "  ℹ️  Signal bot disabled"
    fi
    echo ""
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
# CONFIGURATION SUMMARY DISPLAY
# =============================================================================
display_configuration_summary() {
    section "🔐 CONFIGURATION SUMMARY"
    
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
    
    # Ensure DATA_DIR is set correctly based on TENANT_ID
    if [[ -z "${DATA_DIR:-}" || -z "${TENANT_ID:-}" ]]; then
        DATA_DIR="/mnt/${TENANT_ID:-default}"
        log "⚠️  TENANT_ID was empty, using default directory: $DATA_DIR"
    fi
    
    # Create the directory structure if it doesn't exist
    mkdir -p "${DATA_DIR}/config"
    mkdir -p "${DATA_DIR}/data"
    mkdir -p "${DATA_DIR}/logs"
    mkdir -p "${DATA_DIR}/.configured"
    
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
# INGESTION CONFIGURATION
# =============================================================================
ENABLE_INGESTION="${ENABLE_INGESTION:-false}"
INGESTION_METHOD="${INGESTION_METHOD:-rclone}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_POLL_INTERVAL="${RCLONE_POLL_INTERVAL:-5}"
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-4}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-8}"
RCLONE_VFS_CACHE="${RCLONE_VFS_CACHE:-writes}"
GDRIVE_CREDENTIALS_FILE="${GDRIVE_CREDENTIALS_FILE:-}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_CONTAINER="${AZURE_CONTAINER:-}"
AZURE_ACCESS_KEY="${AZURE_ACCESS_KEY:-}"
LOCAL_INGESTION_PATH="${LOCAL_INGESTION_PATH:-/mnt/${TENANT_ID}/ingestion}"

# =============================================================================
# LLM GATEWAY CONFIGURATION
# =============================================================================
LLM_GATEWAY_TYPE="${LLM_GATEWAY_TYPE}"

# LiteLLM Configuration
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-$(gen_secret)}"
LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-cost-optimized}"
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
# DERIVED CONFIGURATION (computed at generation time — do not edit manually)
# =============================================================================

# Container naming prefix
TENANT_PREFIX="${PLATFORM_PREFIX}-${TENANT_ID}"
BASE_DOMAIN="${DOMAIN}"
PROXY_EMAIL="${ADMIN_EMAIL}"

# Directory aliases (Script 2/3 compatibility)
BASE_DIR="${DATA_DIR}"
CONFIG_DIR="${DATA_DIR}/config"
CONFIGURED_DIR="${DATA_DIR}/.configured"

# Process ownership (current user UID/GID)
PUID="$(id -u)"
PGID="$(id -g)"

# Database credentials (Postgres uses TENANT_ID for user+db)
POSTGRES_USER="${TENANT_ID}"
POSTGRES_DB="${TENANT_ID}"

# Ollama default model (first in list)
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b}"

# Application secrets (generated once, stable across deploys)
LITELLM_UI_PASSWORD="$(gen_password)"
OPENWEBUI_SECRET="$(gen_secret)"
FLOWISE_USERNAME="admin"
FLOWISE_PASSWORD="$(gen_password)"
FLOWISE_SECRETKEY_OVERWRITE="$(gen_secret)"
DIFY_SECRET_KEY="$(gen_secret)"

# N8N webhook URL
N8N_WEBHOOK_URL="http://${DOMAIN}/"

# API key aliases (Script 2 uses GOOGLE_API_KEY / OPENROUTER_API_KEY)
GOOGLE_API_KEY="${GOOGLE_AI_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# =============================================================================
# SERVICE _ENABLED FLAGS (Script 2/3 compatibility — mirrors ENABLE_* above)
# =============================================================================
POSTGRES_ENABLED="${ENABLE_POSTGRES:-false}"
REDIS_ENABLED="${ENABLE_REDIS:-false}"
OLLAMA_ENABLED="${ENABLE_OLLAMA:-false}"
LITELLM_ENABLED="${ENABLE_LITELLM:-false}"
OPENWEBUI_ENABLED="${ENABLE_OPENWEBUI:-false}"
QDRANT_ENABLED="${ENABLE_QDRANT:-false}"
WEAVIATE_ENABLED="${ENABLE_WEAVIATE:-false}"
N8N_ENABLED="${ENABLE_N8N:-false}"
FLOWISE_ENABLED="${ENABLE_FLOWISE:-false}"
DIFY_ENABLED="${ENABLE_DIFY:-false}"
GRAFANA_ENABLED="${ENABLE_GRAFANA:-false}"
PROMETHEUS_ENABLED="${ENABLE_PROMETHEUS:-false}"
CADDY_ENABLED="${ENABLE_CADDY:-false}"
AUTHENTIK_ENABLED="${ENABLE_AUTHENTIK:-false}"
SIGNALBOT_ENABLED="${ENABLE_SIGNALBOT:-false}"
OPENCLAW_ENABLED="${ENABLE_OPENCLAW:-false}"
BIFROST_ENABLED="${ENABLE_BIFROST:-false}"
ANYTHINGLLM_ENABLED="${ENABLE_ANYTHINGLLM:-false}"

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
    
    # Check if running as root for user creation
    if [[ $EUID -ne 0 ]]; then
        warn "User creation requires root privileges"
        warn "Current user: $(whoami) (UID: $EUID)"
        warn "Skipping user creation - will use current user"
        username=$(whoami)
        user_home="$HOME"
        user_config="$user_home/.ai-platform"
        
        echo "  🏠 Using current user: $username"
        echo "  📁 Config directory: $user_config"
    else
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
            if useradd -m -s /bin/bash "$username" 2>/dev/null; then
                echo "  ✅ User '$username' created successfully"
            else
                warn "Failed to create user $username"
                warn "Manual intervention may be required"
                echo "  ⚠️  Continuing without user creation..."
                username=$(whoami)
                user_home="$HOME"
            fi
            
            # Add to docker group
            if [[ "$username" != "$(whoami)" ]]; then
                usermod -aG docker "$username" 2>/dev/null || {
                    warn "Could not add user to docker group"
                    warn "Manual intervention may be required"
                }
            fi
        fi
    fi
    
    # Set user home directory
    if [[ "$username" == "$(whoami)" ]]; then
        user_home="$HOME"
    else
        user_home="/home/$username"
    fi
    user_config="$user_home/.ai-platform"
    
    # Create user directories
    echo ""
    echo "  📁 Setting up user directories..."
    
    mkdir -p "$user_config/logs" "$user_config/data" 2>/dev/null || {
        warn "Could not create directories in $user_home"
        warn "Using fallback: $DATA_DIR"
        user_config="$DATA_DIR"
        mkdir -p "$user_config/logs" "$user_config/data"
    }
    
    # Set ownership only if running as root and not current user
    if [[ $EUID -eq 0 && "$username" != "$(whoami)" ]]; then
        chown -R "$username:$username" "$user_home" 2>/dev/null || {
            warn "Could not set ownership for $username"
        }
    fi
    
    # Create user's .env file with essential variables
    if [[ ! -d "$user_config" ]]; then
        warn "Config directory $user_config does not exist"
        warn "Skipping .env file creation"
    else
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
    
    # Set permissions only if file was created
    if [[ -f "$user_config/.env" ]]; then
        # Set ownership only if running as root and not current user
        if [[ $EUID -eq 0 && "$username" != "$(whoami)" ]]; then
            chown "$username:$username" "$user_config/.env" 2>/dev/null || {
                warn "Could not set ownership for .env file"
            }
        fi
        chmod 600 "$user_config/.env"
        echo "  🔐 .env file: $user_config/.env"
    fi
    fi
    
    echo "  ✅ User setup complete"
    echo "  🏠 Home directory: $user_home"
    echo "  📁 Config directory: $user_config"
    if [[ -f "$user_config/.env" ]]; then
        echo "  🔐 .env file: $user_config/.env"
    fi
    echo ""
    echo "  📋 USER SUMMARY:"
    echo "    Username: $username"
    if [[ "$username" == "$(whoami)" ]]; then
        echo "    UID: $EUID"
    else
        echo "    UID: $(id -u "$username" 2>/dev/null || echo "N/A")"
    fi
    if [[ "$username" == "$(whoami)" ]]; then
        echo "    Groups: $(id -Gn | tr ' ' ',')"
    else
        echo "    Groups: $(id -Gn "$username" 2>/dev/null | tr ' ' ',' || echo "N/A")"
    fi
    if [[ "$username" == "$(whoami)" ]]; then
        echo "    Shell: $SHELL"
    else
        echo "    Shell: $(getent passwd "$username" 2>/dev/null | cut -d: -f7 || echo "N/A")"
    fi
    echo ""
    echo "  🎯 User '$username' is ready for platform management"
}

# =============================================================================
# PORT HEALTH CHECKS (README COMPLIANCE)
# =============================================================================
check_port_conflicts() {
    echo "Checking for port conflicts..."
    
    # Define default ports (only used for conflict checking)
    local DEFAULT_POSTGRES_PORT=5432
    local DEFAULT_REDIS_PORT=6379
    local DEFAULT_OLLAMA_PORT=11434
    local DEFAULT_LITELLM_PORT=4000
    local DEFAULT_OPENWEBUI_PORT=3000
    local DEFAULT_QDRANT_PORT=6333
    local DEFAULT_WEAVIATE_PORT=8080
    local DEFAULT_CHROMADB_PORT=8000
    local DEFAULT_MILVUS_PORT=19530
    
    local required_ports=()
    local port_names=()
    
    # Collect all required ports from enabled services using defaults
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_POSTGRES_PORT")
        port_names+=("PostgreSQL")
    fi
    
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_REDIS_PORT")
        port_names+=("Redis")
    fi
    
    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_LITELLM_PORT")
        port_names+=("LiteLLM")
    fi
    
    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_OLLAMA_PORT")
        port_names+=("Ollama")
    fi
    
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_OPENWEBUI_PORT")
        port_names+=("OpenWebUI")
    fi
    
    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_QDRANT_PORT")
        port_names+=("Qdrant")
    fi
    
    if [[ "${ENABLE_WEAVIATE:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_WEAVIATE_PORT")
        port_names+=("Weaviate")
    fi
    
    if [[ "${ENABLE_CHROMADB:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_CHROMADB_PORT")
        port_names+=("ChromaDB")
    fi
    
    if [[ "${ENABLE_MILVUS:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_MILVUS_PORT")
        port_names+=("Milvus")
    fi
    
    # Check each port for conflicts
    local conflicts=0
    for i in "${!required_ports[@]}"; do
        local port="${required_ports[$i]}"
        local name="${port_names[$i]}"
        
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "  ❌ CONFLICT: $name port $port is already in use"
            conflicts=$((conflicts + 1))
        else
            echo "  ✅ OK: $name port $port is available"
        fi
    done
    
    if [[ $conflicts -gt 0 ]]; then
        fail "Found $conflicts port conflicts. Please resolve before proceeding."
    fi
    
    ok "All required ports are available"
}

# =============================================================================
# DNS VALIDATION (README COMPLIANCE)
# =============================================================================
validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        fail "Invalid domain format: $domain"
    fi
    
    # Test DNS resolution
    if ! nslookup "$domain" >/dev/null 2>&1; then
        warn "Domain $domain does not resolve in DNS"
        return 1
    fi
    
    ok "Domain $domain is valid and resolves"
    return 0
}

test_dns_resolution() {
    local domain="$1"
    echo "=== DNS VALIDATION FOR $domain ==="
    
    # Validate domain format
    validate_domain "$domain" || return 1
    
    # Detect public IP
    local public_ip
    public_ip=$(curl -s http://checkip.amazonaws.com/ 2>/dev/null || curl -s http://icanhazip.com/ 2>/dev/null)
    
    if [[ -z "$public_ip" ]]; then
        warn "Could not detect public IP"
        return 1
    fi
    
    # Check domain resolution
    local domain_ip
    domain_ip=$(nslookup "$domain" | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
    
    if [[ "$domain_ip" != "$public_ip" ]]; then
        warn "Domain IP ($domain_ip) does not match public IP ($public_ip)"
        warn "DNS may not be properly configured for this domain"
        return 1
    fi
    
    ok "DNS validation successful for $domain"
    return 0
}

# =============================================================================
# SERVICE SUMMARY HEALTH CHECK (README COMPLIANCE)
# =============================================================================
display_service_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📊 SERVICE CONFIGURATION SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "  🏷️  Platform Identity:"
    echo "    Platform: $PLATFORM_PREFIX"
    echo "    Tenant: $TENANT_ID"
    echo "    Domain: $DOMAIN"
    echo "    Organization: $ORGANIZATION"
    echo "    Admin: $ADMIN_EMAIL"
    echo ""
    
    echo "  💾 Storage Configuration:"
    if [[ -n "$EBS_DEVICE" ]]; then
        echo "    EBS Device: $EBS_DEVICE"
        echo "    Mount Point: /mnt/$TENANT_ID"
    else
        echo "    Storage: OS disk (/mnt/$TENANT_ID)"
    fi
    echo ""
    
    echo "  🚀 Stack Configuration:"
    echo "    Preset: $STACK_PRESET"
    echo "    LLM Gateway: ${LLM_GATEWAY_TYPE:-none}"
    echo "    Vector DB: ${VECTOR_DB_TYPE:-none}"
    echo ""
    
    echo "  🔐 TLS Configuration:"
    echo "    Mode: $TLS_MODE"
    case "$TLS_MODE" in
        "letsencrypt")
            echo "    Domain: $DOMAIN"
            echo "    Email: $ADMIN_EMAIL"
            ;;
        "provided")
            echo "    Cert: $TLS_CERT_PATH"
            echo "    Key: $TLS_KEY_PATH"
            ;;
    esac
    echo ""
    
    echo "  🌐 Enabled Services & Ports:"
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        echo "    ✅ PostgreSQL: ${POSTGRES_PORT:-5432}"
    fi
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        echo "    ✅ Redis: ${REDIS_PORT:-6379}"
    fi
    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        echo "    ✅ LiteLLM: ${LITELLM_PORT:-4000}"
    fi
    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        echo "    ✅ Ollama: ${OLLAMA_PORT:-11434}"
    fi
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        echo "    ✅ OpenWebUI: ${OPENWEBUI_PORT:-3000}"
    fi
    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        echo "    ✅ Qdrant: ${QDRANT_PORT:-6333}"
    fi
    if [[ "${ENABLE_WEAVIATE:-false}" == "true" ]]; then
        echo "    ✅ Weaviate: ${WEAVIATE_PORT:-8080}"
    fi
    if [[ "${ENABLE_CHROMADB:-false}" == "true" ]]; then
        echo "    ✅ ChromaDB: ${CHROMADB_PORT:-8000}"
    fi
    if [[ "${ENABLE_MILVUS:-false}" == "true" ]]; then
        echo "    ✅ Milvus: ${MILVUS_PORT:-19530}"
    fi
    echo ""
    
    echo "  🔑 LLM Providers:"
    echo "    Preferred: ${PREFERRED_LLM_PROVIDER:-none}"
    if [[ "$ENABLE_OPENAI" == "true" ]]; then
        echo "    ✅ OpenAI"
    fi
    if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
        echo "    ✅ Anthropic"
    fi
    if [[ "$ENABLE_GOOGLE" == "true" ]]; then
        echo "    ✅ Google"
    fi
    if [[ "$ENABLE_GROQ" == "true" ]]; then
        echo "    ✅ Groq"
    fi
    if [[ "$ENABLE_COHERE" == "true" ]]; then
        echo "    ✅ Cohere"
    fi
    if [[ "$ENABLE_HUGGINGFACE" == "true" ]]; then
        echo "    ✅ Hugging Face"
    fi
    if [[ "$ENABLE_LOCAL_MODELS" == "true" ]]; then
        echo "    ✅ Local Models: ✅"
    fi
    if [[ "$ENABLE_OPENROUTER" == "true" ]]; then
        echo "    ✅ OpenRouter"
    fi
    echo ""
    
    echo "  📡 Additional Services:"
    if [[ "$ENABLE_SIGNALBOT" == "true" ]]; then
        echo "    ✅ Signal Bot: ${SIGNALBOT_PORT:-8080}"
    fi
    if [[ "$ENABLE_GDRIVE" == "true" ]]; then
        echo "    ✅ Google Drive: ${GDRIVE_FOLDER_NAME:-AI Platform}"
    fi
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# ENHANCED PORT CONFIGURATION WITH OVERRIDES
# =============================================================================
configure_ports() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🌐 PORT CONFIGURATION WITH HEALTH VALIDATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📋 Configure service ports with conflict detection"
    echo ""
    
    # Check port conflicts first
    check_port_conflicts
    
    # Allow per-service port overrides using defaults
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        safe_read "PostgreSQL port [5432]" "5432" "POSTGRES_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        safe_read "Redis port [6379]" "6379" "REDIS_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        safe_read "LiteLLM port [4000]" "4000" "LITELLM_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        safe_read "Ollama port [11434]" "11434" "OLLAMA_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        safe_read "OpenWebUI port [3000]" "3000" "OPENWEBUI_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        safe_read "Qdrant port [6333]" "6333" "QDRANT_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_WEAVIATE:-false}" == "true" ]]; then
        safe_read "Weaviate port [8080]" "8080" "WEAVIATE_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_CHROMADB:-false}" == "true" ]]; then
        safe_read "ChromaDB port [8000]" "8000" "CHROMADB_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_MILVUS:-false}" == "true" ]]; then
        safe_read "Milvus port [19530]" "19530" "MILVUS_PORT" "^[0-9]+$"
    fi
    
    # Final port conflict check after overrides
    check_port_conflicts
    
    ok "Port configuration complete"
}

# =============================================================================
# MAIN INTERACTIVE INPUT COLLECTION (ENHANCED) FUNCTIONS
# =============================================================================
run_interactive_collection() {
    banner
    
    detect_system
    collect_identity
    configure_storage
    select_stack_preset
    configure_llm_gateway
    configure_vector_database
    
    # Initialize TLS_MODE before validation
    TLS_MODE="none"
    
    # DNS Validation before TLS (README compliance)
    if [[ "$TLS_MODE" == "letsencrypt" ]] || [[ "$TLS_MODE" == "provided" ]]; then
        test_dns_resolution "$DOMAIN" || warn "DNS validation failed - TLS may not work properly"
    fi
    
    configure_tls
    collect_api_keys
    configure_ports
    configure_proxy
    configure_google_drive
    configure_signalbot
    
    # Service Summary Health Check (README compliance)
    display_service_summary
    
    # =============================================================================
    # INGESTION CONFIGURATION (README §4.7)
    # =============================================================================
    configure_ingestion
    
    # =============================================================================
    # TEMPLATE GENERATION
    # =============================================================================
    save_configuration_template
    
    write_platform_conf
    create_tenant_user
}

# =============================================================================
# INGESTION CONFIGURATION (README §4.7)
# =============================================================================
configure_ingestion() {
    section "🔄 INGESTION CONFIGURATION"
    
    echo "  📋 Configure automated data ingestion pipeline"
    echo "    • Rclone for cloud storage synchronization"
    echo "    • Automated processing and indexing"
    echo "    • Support for multiple providers (GDrive, S3, Azure)"
    echo ""
    
    safe_read_yesno "Enable automated ingestion pipeline" "false" "ENABLE_INGESTION"
    
    if [[ "$ENABLE_INGESTION" == "true" ]]; then
        echo ""
        echo "  🔹 Ingestion Providers:"
        echo "    1) Rclone (Google Drive, S3, Azure, etc.)"
        echo "    2) Google Drive (direct)"
        echo "    3) AWS S3 (direct)"
        echo "    4) Azure Blob (direct)"
        echo "    5) Local filesystem"
        
        safe_read "Ingestion method [1-5]" "1" "INGESTION_METHOD" "^[1-5]$"
        
        case "$INGESTION_METHOD" in
            1)
                safe_read "Rclone remote name" "gdrive" "RCLONE_REMOTE"
                safe_read "Sync interval (minutes)" "5" "RCLONE_POLL_INTERVAL" "^[0-9]+$"
                safe_read "Parallel transfers" "4" "RCLONE_TRANSFERS" "^[0-9]+$"
                safe_read "Parallel checkers" "8" "RCLONE_CHECKERS" "^[0-9]+$"
                safe_read "VFS cache mode" "writes" "RCLONE_VFS_CACHE" "^(writes|off|full)$"
                
                echo ""
                echo "  📋 Rclone Configuration Methods:"
                echo "    1) Paste JSON credentials directly"
                echo "    2) Provide file path to credentials"
                
                safe_read "Credentials input method [1-2]" "1" "RCLONE_CRED_METHOD" "^[1-2]$"
                
                case "$RCLONE_CRED_METHOD" in
                    1)
                        echo ""
                        echo "  📋 Paste your Rclone configuration JSON:"
                        echo "    (Press Enter on empty line to finish)"
                        echo ""
                        
                        local json_content=""
                        local line
                        while true; do
                            if [[ -t 0 ]]; then
                                read -r line
                                [[ -z "$line" ]] && break
                                json_content+="$line"$'\n'
                            else
                                # For piped input, read all at once
                                json_content=$(cat)
                                break
                            fi
                        done
                        
                        # Save JSON to file
                        local rclone_conf_dir="/mnt/${TENANT_ID}/config"
                        mkdir -p "$rclone_conf_dir"
                        echo "$json_content" > "${rclone_conf_dir}/rclone.conf"
                        chmod 600 "${rclone_conf_dir}/rclone.conf"
                        
                        echo ""
                        echo "  ✅ Rclone configuration saved to: ${rclone_conf_dir}/rclone.conf"
                        ;;
                    2)
                        safe_read "Rclone configuration file path" "/mnt/${TENANT_ID}/config/rclone.conf" "RCLONE_CONFIG_FILE"
                        
                        if [[ ! -f "$RCLONE_CONFIG_FILE" ]]; then
                            fail "Rclone configuration file not found: $RCLONE_CONFIG_FILE"
                        fi
                        
                        # Copy to standard location
                        local rclone_conf_dir="/mnt/${TENANT_ID}/config"
                        mkdir -p "$rclone_conf_dir"
                        cp "$RCLONE_CONFIG_FILE" "${rclone_conf_dir}/rclone.conf"
                        chmod 600 "${rclone_conf_dir}/rclone.conf"
                        
                        echo "  ✅ Rclone configuration copied to: ${rclone_conf_dir}/rclone.conf"
                        ;;
                esac
                
                echo ""
                echo "  📋 Rclone Configuration Summary:"
                echo "    Remote: ${RCLONE_REMOTE}"
                echo "    Sync Interval: ${RCLONE_POLL_INTERVAL} minutes"
                echo "    Transfers: ${RCLONE_TRANSFERS} parallel"
                echo "    Checkers: ${RCLONE_CHECKERS} parallel"
                echo "    VFS Cache: ${RCLONE_VFS_CACHE}"
                echo "    Config: ${rclone_conf_dir}/rclone.conf"
                ;;
            2)
                safe_read "Google Drive credentials JSON path" "/mnt/${TENANT_ID}/config/gdrive-credentials.json" "GDRIVE_CREDENTIALS_FILE"
                ;;
            3)
                safe_read "AWS S3 bucket name" "" "AWS_S3_BUCKET"
                safe_read "AWS region" "us-east-1" "AWS_REGION"
                safe_read "AWS access key ID" "" "AWS_ACCESS_KEY_ID"
                safe_read "AWS secret access key" "" "AWS_SECRET_ACCESS_KEY"
                ;;
            4)
                safe_read "Azure storage account" "" "AZURE_STORAGE_ACCOUNT"
                safe_read "Azure container name" "" "AZURE_CONTAINER"
                safe_read "Azure access key" "" "AZURE_ACCESS_KEY"
                ;;
            5)
                safe_read "Local source path" "/mnt/${TENANT_ID}/ingestion" "LOCAL_INGESTION_PATH"
                ;;
        esac
        
        # Confirmation
        echo ""
        safe_read_yesno "Confirm ingestion configuration" "true" "INGESTION_CONFIRMED"
        if [[ "$INGESTION_CONFIRMED" != "true" ]]; then
            warn "Ingestion configuration cancelled"
            ENABLE_INGESTION="false"
        fi
    else
        echo "Ingestion disabled - manual data loading only"
    fi
    
    ok "Ingestion configuration complete"
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
EBS_DEVICE="${EBS_DEVICE:-}"
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
VECTOR_DB_TYPE="${VECTOR_DB_TYPE:-none}"

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
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
CHROMADB_PORT="${CHROMADB_PORT:-8000}"
MILVUS_PORT="${MILVUS_PORT:-19530}"
N8N_PORT="${N8N_PORT:-5678}"
FLOWISEAI_PORT="${FLOWISEAI_PORT:-3000}"
LANGFLOW_PORT="${LANGFLOW_PORT:-4000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
CONTINUE_DEV_PORT="${CONTINUE_DEV_PORT:-3000}"
MEM0_PORT="${MEM0_PORT:-8080}"
NGINX_PORT="${NGINX_PORT:-80}"
CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"

# =============================================================================
# SERVICE ENABLEMENT FLAGS
# =============================================================================
ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
ENABLE_REDIS="${ENABLE_REDIS:-false}"
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
ENABLE_CHROMADB="${ENABLE_CHROMADB:-false}"
ENABLE_MILVUS="${ENABLE_MILVUS:-false}"
ENABLE_N8N="${ENABLE_N8N:-false}"
ENABLE_FLOWISEAI="${ENABLE_FLOWISEAI:-false}"
ENABLE_LANGFLOW="${ENABLE_LANGFLOW:-false}"
ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV:-false}"
ENABLE_MEM0="${ENABLE_MEM0:-false}"
ENABLE_NGINX="${ENABLE_NGINX:-false}"
ENABLE_CADDY="${ENABLE_CADDY:-false}"

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
# SERVICE VARIABLE INITIALIZATION - ALIGNED WITH .env
# =============================================================================
initialize_service_variables() {
    # Platform Identity (from .env)
    PLATFORM_PREFIX="${PLATFORM_PREFIX:-ai-}"
    TENANT_ID="${TENANT_ID:-}"
    DOMAIN="${DOMAIN:-}"
    ORGANIZATION="${ORGANIZATION:-}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-}"
    DATA_ROOT="${DATA_ROOT:-/mnt/data/}"
    PROJECT_PREFIX="${PROJECT_PREFIX:-ai-}"
    
    # Tenant User Configuration
    TENANT_UID="${TENANT_UID:-1001}"
    TENANT_GID="${TENANT_GID:-1001}"
    
    # Service Ownership UIDs (Pragmatic Exception Pattern)
    POSTGRES_UID="${POSTGRES_UID:-70}"
    PROMETHEUS_UID="${PROMETHEUS_UID:-65534}"
    GRAFANA_UID="${GRAFANA_UID:-472}"
    N8N_UID="${N8N_UID:-1000}"
    QDRANT_UID="${QDRANT_UID:-1000}"
    REDIS_UID="${REDIS_UID:-999}"
    OPENWEBUI_UID="${OPENWEBUI_UID:-1000}"
    ANYTHINGLLM_UID="${ANYTHINGLLM_UID:-1000}"
    OLLAMA_UID="${OLLAMA_UID:-1001}"
    FLOWISE_UID="${FLOWISE_UID:-1000}"
    LITELLM_UID="${LITELLM_UID:-1000}"
    AUTHENTIK_UID="${AUTHENTIK_UID:-1000}"
    CADDY_UID="${CADDY_UID:-1000}"
    
    # Service Flags (complete list from .env)
    ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
    ENABLE_REDIS="${ENABLE_REDIS:-false}"
    ENABLE_CADDY="${ENABLE_CADDY:-false}"
    ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
    ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
    ENABLE_LOCALAI="${ENABLE_LOCALAI:-false}"
    ENABLE_VLLM="${ENABLE_VLLM:-false}"
    ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
    ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
    ENABLE_DIFY="${ENABLE_DIFY:-false}"
    ENABLE_N8N="${ENABLE_N8N:-false}"
    ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
    ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
    ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
    ENABLE_PINECONE="${ENABLE_PINECONE:-false}"
    ENABLE_CHROMADB="${ENABLE_CHROMADB:-false}"
    ENABLE_MILVUS="${ENABLE_MILVUS:-false}"
    ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
    ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
    ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
    ENABLE_SIGNAL="${ENABLE_SIGNAL:-false}"
    ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
    ENABLE_RCLONE="${ENABLE_RCLONE:-false}"
    ENABLE_MINIO="${ENABLE_MINIO:-false}"
    ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
    ENABLE_SEARXNG="${ENABLE_SEARXNG:-false}"
    
    # Vector Database Configuration
    PINECONE_PROJECT_ID="${PINECONE_PROJECT_ID:-}"
    
    # Service URLs (internal Docker network)
    OLLAMA_INTERNAL_URL="http://ollama:11434"
    OLLAMA_BASE_URL="http://ollama:11434"
    OPENAI_INTERNAL_URL="https://api.openai.com/v1"
    ANTHROPIC_INTERNAL_URL="https://api.anthropic.com"
    LOCALAI_INTERNAL_URL="http://localai:8080"
    VLLM_INTERNAL_URL="http://vllm:8000"
    LITELLM_INTERNAL_URL="http://litellm:4000"
    QDRANT_INTERNAL_URL="http://qdrant:6333"
    WEAVIATE_INTERNAL_URL="http://weaviate:8080"
    PINECONE_INTERNAL_URL="https://pinecone.io"
    CHROMADB_INTERNAL_URL="http://chromadb:8000"
    MILVUS_INTERNAL_URL="http://milvus:19530"
    REDIS_INTERNAL_URL="redis://redis:6379"
    POSTGRES_INTERNAL_URL="postgresql://postgres:5432"
    N8N_INTERNAL_URL="http://n8n:5678"
    
    # Service API endpoints
    OLLAMA_API_ENDPOINT="http://ollama:11434/api/tags"
    LITELLM_API_ENDPOINT="http://litellm:4000/v1"
    QDRANT_API_ENDPOINT="http://qdrant:6333"
    
    # Project Configuration
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"
    DOCKER_NETWORK="${DOCKER_NETWORK:-}"
    
    # Hardware Configuration
    GPU_TYPE="${GPU_TYPE:-cpu}"
    GPU_COUNT="${GPU_COUNT:-0}"
    OLLAMA_GPU_LAYERS="${OLLAMA_GPU_LAYERS:-auto}"
    CPU_CORES="${CPU_CORES:-2}"
    TOTAL_RAM_GB="${TOTAL_RAM_GB:-8}"
    
    # Ollama Configuration
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b}"
    OLLAMA_MODELS="${OLLAMA_MODELS:-qwen2.5:7b,llama3.1:8b}"
    
    # LLM Providers
    LLM_PROVIDERS="${LLM_PROVIDERS:-local}"
    OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
    GROQ_API_KEY="${GROQ_API_KEY:-}"
    OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
    
    # LiteLLM Routing Strategy
    LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-cost-optimized}"
    LITELLM_INTERNAL_PORT="${LITELLM_INTERNAL_PORT:-4000}"
    
    # Internal Service Ports
    CADDY_INTERNAL_HTTP_PORT="${CADDY_INTERNAL_HTTP_PORT:-80}"
    CADDY_INTERNAL_HTTPS_PORT="${CADDY_INTERNAL_HTTPS_PORT:-443}"
    OLLAMA_INTERNAL_PORT="${OLLAMA_INTERNAL_PORT:-11434}"
    QDRANT_INTERNAL_PORT="${QDRANT_INTERNAL_PORT:-6333}"
    QDRANT_INTERNAL_HTTP_PORT="${QDRANT_INTERNAL_HTTP_PORT:-6333}"
    OPENWEBUI_INTERNAL_PORT="${OPENWEBUI_INTERNAL_PORT:-8081}"
    OPENCLAW_INTERNAL_PORT="${OPENCLAW_INTERNAL_PORT:-18789}"
    SIGNAL_INTERNAL_PORT="${SIGNAL_INTERNAL_PORT:-8080}"
    N8N_INTERNAL_PORT="${N8N_INTERNAL_PORT:-5678}"
    FLOWISE_INTERNAL_PORT="${FLOWISE_INTERNAL_PORT:-3000}"
    ANYTHINGLLM_INTERNAL_PORT="${ANYTHINGLLM_INTERNAL_PORT:-3001}"
    GRAFANA_INTERNAL_PORT="${GRAFANA_INTERNAL_PORT:-3000}"
    PROMETHEUS_INTERNAL_PORT="${PROMETHEUS_INTERNAL_PORT:-9090}"
    MINIO_INTERNAL_PORT="${MINIO_INTERNAL_PORT:-9000}"
    MINIO_CONSOLE_INTERNAL_PORT="${MINIO_CONSOLE_INTERNAL_PORT:-9001}"
    POSTGRES_INTERNAL_PORT="${POSTGRES_INTERNAL_PORT:-5432}"
    REDIS_INTERNAL_PORT="${REDIS_INTERNAL_PORT:-6379}"
    
    # Database Configuration
    POSTGRES_USER="${POSTGRES_USER:-}"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
    POSTGRES_DB="${POSTGRES_DB:-}"
    DB_USER="${DB_USER:-}"
    DB_PASSWORD="${DB_PASSWORD:-}"
    
    # Redis Configuration
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    
    # n8n Configuration
    N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE:-false}"
    N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-}"
    N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-}"
    
    # Flowise Configuration
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-}"
    
    # LiteLLM Configuration
    LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
    LITELLM_DATABASE_URL="${LITELLM_DATABASE_URL:-postgresql://postgres:password@localhost:5432/litellm}"
    LITELLM_ENABLE_LOGGING="${LITELLM_ENABLE_LOGGING:-true}"
    
    # AnythingLLM Configuration
    ANYTHINGLLM_STORAGE_PATH="${ANYTHINGLLM_STORAGE_PATH:-}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
    
    # Qdrant Configuration
    QDRANT_API_KEY="${QDRANT_API_KEY:-}"
    QDRANT_COLLECTION_NAME="${QDRANT_COLLECTION_NAME:-}"
    
    # Grafana Configuration
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
    GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
    
    # Authentik Configuration
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
    AUTHENTIK_ADMIN_TOKEN="${AUTHENTIK_ADMIN_TOKEN:-}"
    
    # MinIO Configuration
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"
    MINIO_BUCKET="${MINIO_BUCKET:-}"
    
    # Dify Configuration
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
    DIFY_DATABASE_URL="${DIFY_DATABASE_URL:-}"
    
    # Network & Security
    TLS_MODE="${TLS_MODE:-none}"
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
    LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
    LETSENCRYPT_AUTO_RENEW="${LETSENCRYPT_AUTO_RENEW:-true}"
    HTTP_TO_HTTPS_REDIRECT="${HTTP_TO_HTTPS_REDIRECT:-false}"
    
    # Proxy Configuration
    ENABLE_PROXY="${ENABLE_PROXY:-false}"
    PROXY_TYPE="${PROXY_TYPE:-nginx}"
    PROXY_ROUTING="${PROXY_ROUTING:-path_based}"
    PROXY_HTTP_PORT="${PROXY_HTTP_PORT:-80}"
    PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
    PROXY_FORCE_HTTPS="${PROXY_FORCE_HTTPS:-false}"
    
    # Google Drive Integration
    ENABLE_GDRIVE="${ENABLE_GDRIVE:-false}"
    GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID:-}"
    GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME:-AI Platform}"
    
    # Search APIs
    SEARXNG_SECRET_KEY="${SEARXNG_SECRET_KEY:-}"
    
    # Additional Service Ports
    WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
    CHROMADB_PORT="${CHROMADB_PORT:-8000}"
    MILVUS_PORT="${MILVUS_PORT:-19530}"
    CODESERVER_PORT="${CODESERVER_PORT:-8443}"
    
    # Self-signed TLS
    SELF_SIGNED_DAYS="${SELF_SIGNED_DAYS:-365}"
    
    # Manual TLS
    TLS_CERT_FILE="${TLS_CERT_FILE:-}"
    TLS_KEY_FILE="${TLS_KEY_FILE:-}"
    
    # Network Configuration
    LOCALHOST="${LOCALHOST:-localhost}"
    
    # Service Passwords and Secrets
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"
    N8N_API_KEY="${N8N_API_KEY:-}"
    N8N_USER="${N8N_USER:-}"
    N8N_PASSWORD="${N8N_PASSWORD:-}"
    FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY:-}"
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-}"
    LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
    LITELLM_SALT_KEY="${LITELLM_SALT_KEY:-}"
    ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY:-}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
    ANYTHINGLLM_AUTH_TOKEN="${ANYTHINGLLM_AUTH_TOKEN:-}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
    QDRANT_API_KEY="${QDRANT_API_KEY:-}"
    QDRANT_VECTOR_SIZE="${QDRANT_VECTOR_SIZE:-768}"
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-}"
    GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-}"
    GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-}"
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
    AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL:-}"
    AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD:-}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
    DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY:-}"
    
    # Google Drive Integration (added GDRIVE_FOLDER_ID)
    GDRIVE_AUTH_METHOD="${GDRIVE_AUTH_METHOD:-service_account}"
    GDRIVE_CLIENT_ID="${GDRIVE_CLIENT_ID:-}"
    GDRIVE_CLIENT_SECRET="${GDRIVE_CLIENT_SECRET:-}"
    GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME:-}"
    GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID:-}"  # Added as requested
    GDRIVE_TOKEN="${GDRIVE_TOKEN:-service_account_valid}"
    
    # Rclone Configuration
    RCLONE_AUTH_METHOD="${RCLONE_AUTH_METHOD:-service_account}"
    RCLONE_CONFIG_PATH="${RCLONE_CONFIG_PATH:-}"
    RCLONE_GDRIVE_ROOT_ID="${RCLONE_GDRIVE_ROOT_ID:-}"
    
    # Search APIs
    SEARCH_PROVIDER="${SEARCH_PROVIDER:-multiple}"
    BRAVE_API_KEY="${BRAVE_API_KEY:-}"
    SERPAPI_KEY="${SERPAPI_KEY:-}"
    SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
    CUSTOM_SEARCH_URL="${CUSTOM_SEARCH_URL:-}"
    CUSTOM_SEARCH_KEY="${CUSTOM_SEARCH_KEY:-}"
    
    # Proxy Configuration (added for user selection)
    PROXY_TYPE="${PROXY_TYPE:-caddy}"
    ROUTING_METHOD="${ROUTING_METHOD:-subdomain}"
    SSL_TYPE="${SSL_TYPE:-selfsigned}"
    CUSTOM_PROXY_IMAGE="${CUSTOM_PROXY_IMAGE:-}"
    HTTP_PROXY="${HTTP_PROXY:-}"
    HTTPS_PROXY="${HTTPS_PROXY:-}"
    NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,.local}"
    HTTP_TO_HTTPS_REDIRECT="${HTTP_TO_HTTPS_REDIRECT:-true}"
    
    # OpenClaw Configuration
    OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-}"
    OPENCLAW_ADMIN_USER="${OPENCLAW_ADMIN_USER:-}"
    OPENCLAW_SECRET="${OPENCLAW_SECRET:-}"
    OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
    OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-openclaw:latest}"
    
    # External Ports
    CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
    CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
    N8N_PORT="${N8N_PORT:-5678}"
    FLOWISE_PORT="${FLOWISE_PORT:-3000}"
    OPENWEBUI_PORT="${OPENWEBUI_PORT:-8081}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
    LITELLM_PORT="${LITELLM_PORT:-4000}"
    GRAFANA_PORT="${GRAFANA_PORT:-3002}"
    PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
    OLLAMA_PORT="${OLLAMA_PORT:-11434}"
    QDRANT_PORT="${QDRANT_PORT:-6333}"
    SIGNAL_PORT="${SIGNAL_PORT:-8080}"
    OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
    RCLONE_PORT="${RCLONE_PORT:-5572}"
    
    # Additional Variables
    SSL_EMAIL="${SSL_EMAIL:-}"
    GPU_DEVICE="${GPU_DEVICE:-cpu}"
    TENANT_DIR="${TENANT_DIR:-}"
    MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
    MINIO_PORT="${MINIO_PORT:-9000}"
    
    # Authentik Redis Configuration
    AUTHENTIK_REDIS__HOST="${AUTHENTIK_REDIS__HOST:-redis}"
    
    # Dify Storage Configuration
    DIFY_STORAGE_TYPE="${DIFY_STORAGE_TYPE:-local}"
    DIFY_STORAGE_LOCAL_ROOT="${DIFY_STORAGE_LOCAL_ROOT:-/data}"
    
    # Infrastructure Services
    ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
    ENABLE_POSTGRESQL="${ENABLE_POSTGRESQL:-false}"  # Alias for compatibility
    ENABLE_REDIS="${ENABLE_REDIS:-false}"
    
    # LLM Services
    ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    ENABLE_BIFROST="${ENABLE_BIFROST:-false}"
    ENABLE_DIRECT_OLLAMA="${ENABLE_DIRECT_OLLAMA:-false}"
    
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
    ENABLE_FLOWISEAI="${ENABLE_FLOWISEAI:-false}"
    ENABLE_LANGFLOW="${ENABLE_LANGFLOW:-false}"
    ENABLE_DIFY="${ENABLE_DIFY:-false}"
    ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
    
    # Development
    ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
    ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV:-false}"
    
    # Monitoring
    ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
    ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
    
    # Authentication
    ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
    
    # Additional Services
    ENABLE_MEM0="${ENABLE_MEM0:-false}"
    ENABLE_NGINX="${ENABLE_NGINX:-false}"
    ENABLE_CADDY="${ENABLE_CADDY:-false}"
    
    # LLM Providers
    PREFERRED_LLM_PROVIDER="${PREFERRED_LLM_PROVIDER:-ollama}"
    ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
    ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
    ENABLE_GOOGLE="${ENABLE_GOOGLE:-false}"
    ENABLE_GROQ="${ENABLE_GROQ:-false}"
    ENABLE_COHERE="${ENABLE_COHERE:-false}"
    ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE:-false}"
    ENABLE_OLLAMA_PROVIDER="${ENABLE_OLLAMA_PROVIDER:-false}"
    ENABLE_LOCAL_MODELS="${ENABLE_LOCAL_MODELS:-false}"
    ENABLE_OPENROUTER="${ENABLE_OPENROUTER:-false}"
    
    # Additional Services
    ENABLE_GDRIVE="${ENABLE_GDRIVE:-false}"
    ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
    
    # Port variables
    SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"
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
    
    # Initialize all service enable variables to prevent unbound variable errors
    initialize_service_variables
    
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
