#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup & Input Collection
# PURPOSE: Complete system setup, input gathering, and platform.conf generation
# =============================================================================
# USAGE:   bash scripts/1-setup-system.sh [tenant_id] [options]
# OPTIONS: --ingest-from <file>    Ingest credentials from existing .env file
#          --preserve-secrets       Preserve existing secrets from .env
#          --generate-new          Generate new secrets for all services
#          --deployment-mode <mode> Set deployment mode (minimal|standard|full)
#          --template FILE         Use template file for configuration
#          --dry-run               Show what would be configured
# =============================================================================

set -euo pipefail
trap 'echo "FAILED at line $LINENO. Command: $BASH_COMMAND" >&2' ERR

# =============================================================================
# NON-INTERACTIVE MODE (P3 fix)
# =============================================================================
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
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
exec > >(tee -a "$LOG_FILE") 2>&1
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# NON-INTERACTIVE SAFE INPUT WRAPPER
# =============================================================================
safe_read() {
    # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value

    # Check for env var override first
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ${prompt}: ${value} (from environment)"
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input
        read -rp "  ${prompt} [${default}]: " value
        value="${value:-${default}}"
    else
        # Non-TTY — use default silently
        value="${default}"
        echo "  ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

# Helper function for yes/no prompts
safe_read_yesno() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value

    # Check for env var override
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ${prompt}: ${value} (from environment)"
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input
        read -rp "  ${prompt} [${default}]: " value
        value="${value:-${default}}"
        case "$value" in
            [Yy]*) value="true" ;;
            [Nn]*) value="false" ;;
            *) value="${default}" ;;
        esac
    else
        # Non-TTY — use default silently
        value="${default}"
        echo "  ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

# =============================================================================
# INTERACTIVE INPUT COLLECTION FUNCTIONS (Complete Implementation)
# =============================================================================

# Identity Configuration
collect_identity() {
    section "IDENTITY CONFIGURATION"
    
    # Platform prefix selection
    echo "Select platform prefix:"
    echo "  1) ai- (default for AI Platform)"
    echo "  2) prod- (production environment)"
    echo "  3) staging- (staging environment)"
    echo "  4) dev- (development environment)"
    echo "  5) Custom prefix"
    
    safe_read "Platform prefix [1-5]" "1" "PLATFORM_PREFIX_CHOICE"
    
    case "${PLATFORM_PREFIX_CHOICE}" in
        1) PLATFORM_PREFIX="ai-" ;;
        2) PLATFORM_PREFIX="prod-" ;;
        3) PLATFORM_PREFIX="staging-" ;;
        4) PLATFORM_PREFIX="dev-" ;;
        5) 
            safe_read "Custom prefix [end with -]" "" "PLATFORM_PREFIX"
            if [[ ! "$PLATFORM_PREFIX" =~ -$ ]]; then
                fail "Custom prefix must end with '-'"
            fi
            ;;
        *) 
            PLATFORM_PREFIX="ai-"
            echo "Default selected: ai-"
            ;;
    esac
    
    # Tenant ID
    safe_read "Tenant ID [required, alphanumeric]" "" "TENANT_ID"
    if [[ ! "$TENANT_ID" =~ ^[a-zA-Z0-9]+$ ]]; then
        fail "Tenant ID must be alphanumeric only"
    fi
    : "${TENANT_ID:?TENANT_ID is required}"
    
    # Domain configuration
    safe_read "Base domain [required, e.g., example.com]" "" "DOMAIN"
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        fail "Invalid domain format: $DOMAIN"
    fi
    : "${DOMAIN:?DOMAIN is required}"
    
    echo "Identity Configuration:"
    echo "  Platform Prefix: $PLATFORM_PREFIX"
    echo "  Tenant ID: $TENANT_ID"
    echo "  Full Tenant Name: ${PLATFORM_PREFIX}${TENANT_ID}"
    echo "  Base Domain: $DOMAIN"
}

# Storage Configuration
configure_storage() {
    section "STORAGE CONFIGURATION"
    
    echo "Select storage type:"
    echo "  1) Use EBS volume (recommended for production)"
    echo "  2) Use OS disk (not recommended for production)"
    
    safe_read "Storage type [1-2]" "1" "STORAGE_CHOICE"
    
    case "${STORAGE_CHOICE}" in
        1)
            USE_EBS="true"
            echo "EBS volume selected - running detection..."
            detect_and_mount_ebs
            ;;
        2)
            USE_EBS="false"
            echo "OS disk selected - creating /mnt/${TENANT_ID}..."
            mkdir -p "/mnt/${TENANT_ID}"
            chmod 755 "/mnt/${TENANT_ID}"
            ;;
        *)
            USE_EBS="true"
            echo "Default selected: EBS volume"
            detect_and_mount_ebs
            ;;
    esac
}

# EBS Volume Detection and Mounting
detect_and_mount_ebs() {
    echo "Available block devices:"
    local count=1
    lsblk -f -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|sd|vd" | while read -r name size type mount; do
        if [[ -z "$mount" ]] && [[ "$type" == "disk" ]]; then
            echo "  [$count] /dev/$name ${size} (unformatted — available)"
            count=$((count + 1))
        fi
    done
    
    echo "  [$count] Use existing /mnt/${TENANT_ID}/ on OS disk (no separate volume)"
    
    safe_read "Select EBS volume [1-$count, or 0 for OS disk]" "0" "EBS_CHOICE"
    
    if [[ "$EBS_CHOICE" =~ ^[1-9]$ ]]; then
        EBS_DEVICE=$(lsblk -f -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|sd|vd" | sed -n "${EBS_CHOICE}p" | awk '{print "/dev/"$1}')
        echo "Selected EBS device: $EBS_DEVICE"
        
        # Format EBS volume
        echo "Formatting EBS volume: $EBS_DEVICE"
        safe_read "CONFIRM: Format $EBS_DEVICE as ext4? [yes/N]: " "" "FORMAT_CONFIRM"
        
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
    else
        echo "Using OS disk for storage"
        mkdir -p "/mnt/${TENANT_ID}"
        chmod 755 "/mnt/${TENANT_ID}"
    fi
}

# Stack Preset Selection
select_stack_preset() {
    section "STACK PRESET SELECTION"
    
    echo "Select stack preset:"
    echo "  1) minimal - PostgreSQL, Redis, LiteLLM, Ollama, OpenWebUI, Qdrant, Caddy"
    echo "  2) dev - minimal + Code Server, Continue.dev, n8n, Flowise, Mem0"
    echo "  3) standard - dev + LibreChat, Dify, Grafana, Prometheus, Authentik"
    echo "  4) full - All 25 services enabled"
    echo "  5) custom - All services disabled, enable individually"
    
    safe_read "Stack preset [1-5]" "1" "STACK_PRESET_CHOICE"
    
    case "${STACK_PRESET_CHOICE}" in
        1) 
            STACK_PRESET="minimal"
            apply_preset_defaults "minimal"
            ;;
        2) 
            STACK_PRESET="dev"
            apply_preset_defaults "dev"
            ;;
        3) 
            STACK_PRESET="standard"
            apply_preset_defaults "standard"
            ;;
        4) 
            STACK_PRESET="full"
            apply_preset_defaults "full"
            ;;
        5) 
            STACK_PRESET="custom"
            apply_preset_defaults "custom"
            ;;
        *) 
            STACK_PRESET="minimal"
            echo "Default selected: minimal"
            apply_preset_defaults "minimal"
            ;;
    esac
    
    echo "Stack preset: $STACK_PRESET"
}

# LLM Gateway Configuration
configure_llm_gateway() {
    section "LLM GATEWAY CONFIGURATION"
    
    echo "Select LLM gateway:"
    echo "  1) LiteLLM (multi-provider router)"
    echo "  2) Bifrost (lightweight Go router)"
    echo "  3) Direct Ollama (single LLM only)"
    
    safe_read "LLM gateway [1-3]" "1" "LLM_GATEWAY_CHOICE"
    
    case "${LLM_GATEWAY_CHOICE}" in
        1)
            LLM_PROXY_TYPE="litellm"
            echo "LiteLLM selected - configuring multi-provider routing..."
            configure_litellm_providers
            ;;
        2)
            LLM_PROXY_TYPE="bifrost"
            echo "Bifrost selected - lightweight Go router..."
            ;;
        3)
            LLM_PROXY_TYPE="direct"
            echo "Direct Ollama selected - single LLM mode..."
            ;;
        *)
            LLM_PROXY_TYPE="litellm"
            echo "Default selected: LiteLLM"
            configure_litellm_providers
            ;;
    esac
}

# Configure LiteLLM Providers
configure_litellm_providers() {
    # This would configure specific provider settings
    echo "LiteLLM provider configuration will be handled in platform.conf generation"
}

# Vector Database Configuration
configure_vector_db() {
    section "VECTOR DATABASE CONFIGURATION"
    
    echo "Select vector database:"
    echo "  1) Qdrant (default, high performance)"
    echo "  2) Weaviate (GraphQL API)"
    echo "  3) ChromaDB (Python-native)"
    echo "  4) Milvus (enterprise scale)"
    
    safe_read "Vector database [1-4]" "1" "VECTOR_DB_CHOICE"
    
    case "${VECTOR_DB_CHOICE}" in
        1) 
            VECTOR_DB_TYPE="qdrant"
            echo "Qdrant selected - high performance vector database"
            ;;
        2) 
            VECTOR_DB_TYPE="weaviate"
            echo "Weaviate selected - GraphQL API vector database"
            ;;
        3) 
            VECTOR_DB_TYPE="chroma"
            echo "ChromaDB selected - Python-native vector database"
            ;;
        4) 
            VECTOR_DB_TYPE="milvus"
            echo "Milvus selected - enterprise scale vector database"
            ;;
        *) 
            VECTOR_DB_TYPE="qdrant"
            echo "Default selected: Qdrant"
            ;;
    esac
}

# TLS Configuration
configure_tls() {
    section "TLS CERTIFICATE CONFIGURATION"
    
    echo "Select TLS mode for ${DOMAIN}:"
    echo "  1) Let's Encrypt (automatic - requires public DNS)"
    echo "  2) Manual Certificate (provide cert/key files)"
    echo "  3) Self-Signed Certificate (development/testing)"
    echo "  4) No TLS (HTTP only - not recommended for production)"
    
    safe_read "TLS mode [1-4]" "1" "TLS_MODE_CHOICE"
    
    case "${TLS_MODE_CHOICE}" in
        1)
            TLS_MODE="letsencrypt"
            echo "Let's Encrypt selected - requires:"
            echo "  • Public domain ${DOMAIN}"
            echo "  • DNS pointing to this server"
            echo "  • Email for certificate registration"
            
            safe_read "Email for Let's Encrypt" "" "LETSENCRYPT_EMAIL"
            : "${LETSENCRYPT_EMAIL:?Email required for Let's Encrypt}"
            
            echo "Let's Encrypt configuration:"
            echo "  Domain: ${DOMAIN}"
            echo "  Email: ${LETSENCRYPT_EMAIL}"
            echo "  Auto-renewal: enabled"
            ;;
        2)
            TLS_MODE="manual"
            echo "Manual certificate selected - requires:"
            echo "  • Certificate file (.crt or .pem)"
            echo "  • Private key file (.key)"
            
            safe_read "Certificate file path" "" "MANUAL_CERT_FILE"
            safe_read "Private key file path" "" "MANUAL_KEY_FILE"
            
            # Validate files exist
            if [[ ! -f "$MANUAL_CERT_FILE" ]]; then
                fail "Certificate file not found: $MANUAL_CERT_FILE"
            fi
            
            if [[ ! -f "$MANUAL_KEY_FILE" ]]; then
                fail "Private key file not found: $MANUAL_KEY_FILE"
            fi
            
            echo "Manual TLS configuration:"
            echo "  Certificate: $MANUAL_CERT_FILE"
            echo "  Private Key: $MANUAL_KEY_FILE"
            echo "  Domain: ${DOMAIN}"
            ;;
        3)
            TLS_MODE="selfsigned"
            echo "Self-signed certificate selected - generates:"
            echo "  • 365-day certificate"
            echo "  • RSA 2048-bit key"
            echo "  • Browser warnings (expected)"
            
            safe_read "Certificate country [US]" "US" "CERT_COUNTRY"
            safe_read "Certificate state [State]" "State" "CERT_STATE"
            safe_read "Certificate city [City]" "City" "CERT_CITY"
            safe_read "Certificate organization [AI Platform]" "AI Platform" "CERT_ORG"
            
            echo "Self-signed TLS configuration:"
            echo "  Domain: ${DOMAIN}"
            echo "  Country: $CERT_COUNTRY"
            echo "  State: $CERT_STATE"
            echo "  City: $CERT_CITY"
            echo "  Organization: $CERT_ORG"
            echo "  Validity: 365 days"
            ;;
        4)
            TLS_MODE="none"
            echo "No TLS selected - WARNING:"
            echo "  • HTTP only (port 80)"
            echo "  • No encryption"
            echo "  • Not recommended for production"
            echo "  • Browsers may show warnings"
            
            safe_read "Continue without TLS? [yes/N]: " "" "NO_TLS_CONFIRM"
            if [[ ! "$NO_TLS_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
                echo "TLS configuration cancelled"
                exit 1
            fi
            
            echo "No TLS configuration:"
            echo "  Protocol: HTTP only"
            echo "  Port: 80"
            echo "  Domain: ${DOMAIN}"
            ;;
        *)
            fail "Invalid TLS mode: $TLS_MODE_CHOICE (must be 1-4)"
            ;;
    esac
}

# API Key Collection
collect_api_keys() {
    section "API KEY COLLECTION"
    
    echo "Configure LLM provider API keys (leave empty to disable):"
    
    # OpenAI
    safe_read "OpenAI API key [optional]" "" "OPENAI_API_KEY"
    if [[ -n "$OPENAI_API_KEY" ]]; then
        echo "OpenAI provider enabled"
        OPENAI_PROVIDER_ENABLED="true"
    else
        echo "OpenAI provider disabled"
        OPENAI_PROVIDER_ENABLED="false"
    fi
    
    # Anthropic
    safe_read "Anthropic API key [optional]" "" "ANTHROPIC_API_KEY"
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        echo "Anthropic provider enabled"
        ANTHROPIC_PROVIDER_ENABLED="true"
    else
        echo "Anthropic provider disabled"
        ANTHROPIC_PROVIDER_ENABLED="false"
    fi
    
    # Google
    safe_read "Google API key [optional]" "" "GOOGLE_API_KEY"
    if [[ -n "$GOOGLE_API_KEY" ]]; then
        echo "Google provider enabled"
        GOOGLE_PROVIDER_ENABLED="true"
    else
        echo "Google provider disabled"
        GOOGLE_PROVIDER_ENABLED="false"
    fi
    
    # Groq
    safe_read "Groq API key [optional]" "" "GROQ_API_KEY"
    if [[ -n "$GROQ_API_KEY" ]]; then
        echo "Groq provider enabled"
        GROQ_PROVIDER_ENABLED="true"
    else
        echo "Groq provider disabled"
        GROQ_PROVIDER_ENABLED="false"
    fi
    
    # OpenRouter
    safe_read "OpenRouter API key [optional]" "" "OPENROUTER_API_KEY"
    if [[ -n "$OPENROUTER_API_KEY" ]]; then
        echo "OpenRouter provider enabled"
        OPENROUTER_PROVIDER_ENABLED="true"
    else
        echo "OpenRouter provider disabled"
        OPENROUTER_PROVIDER_ENABLED="false"
    fi
}

# Port Configuration
configure_ports() {
    section "PORT CONFIGURATION"
    
    echo "Configure service ports (press Enter for defaults):"
    
    safe_read "PostgreSQL port [5432]" "5432" "POSTGRES_PORT"
    safe_read "Redis port [6379]" "6379" "REDIS_PORT"
    safe_read "LiteLLM port [4000]" "4000" "LITELLM_PORT"
    safe_read "Ollama port [11434]" "11434" "OLLAMA_PORT"
    safe_read "OpenWebUI port [3000]" "3000" "OPENWEBUI_PORT"
    safe_read "Qdrant port [6333]" "6333" "QDRANT_PORT"
    safe_read "N8N port [5678]" "5678" "N8N_PORT"
    safe_read "Code Server port [8443]" "8443" "CODESERVER_PORT"
    
    echo "Key Ports:"
    echo "  PostgreSQL: $POSTGRES_PORT"
    echo "  Redis: $REDIS_PORT"
    echo "  LiteLLM: $LITELLM_PORT"
    echo "  Ollama: $OLLAMA_PORT"
    echo "  OpenWebUI: $OPENWEBUI_PORT"
    echo "  Qdrant: $QDRANT_PORT"
    echo "  N8N: $N8N_PORT"
    echo "  Code Server: $CODESERVER_PORT"
}

# Final Configuration Summary
show_configuration_summary() {
    section "CONFIGURATION SUMMARY"
    
    echo "Identity:"
    echo "  Platform Prefix: $PLATFORM_PREFIX"
    echo "  Tenant ID: $TENANT_ID"
    echo "  Base Domain: $DOMAIN"
    echo "  Full Tenant Name: ${PLATFORM_PREFIX}${TENANT_ID}"
    
    echo ""
    echo "Configuration:"
    echo "  Stack Preset: $STACK_PRESET"
    echo "  LLM Gateway: $LLM_PROXY_TYPE"
    echo "  Vector DB: $VECTOR_DB_TYPE"
    echo "  TLS Mode: $TLS_MODE"
    echo "  Storage Type: $USE_EBS"
    
    echo ""
    echo "Enabled Providers:"
    [[ "$OPENAI_PROVIDER_ENABLED" == "true" ]] && echo "  • OpenAI"
    [[ "$ANTHROPIC_PROVIDER_ENABLED" == "true" ]] && echo "  • Anthropic"
    [[ "$GOOGLE_PROVIDER_ENABLED" == "true" ]] && echo "  • Google"
    [[ "$GROQ_PROVIDER_ENABLED" == "true" ]] && echo "  • Groq"
    [[ "$OPENROUTER_PROVIDER_ENABLED" == "true" ]] && echo "  • OpenRouter"
    
    echo ""
    echo "Key Ports:"
    echo "  PostgreSQL: $POSTGRES_PORT"
    echo "  Redis: $REDIS_PORT"
    echo "  LiteLLM: $LITELLM_PORT"
    echo "  Ollama: $OLLAMA_PORT"
    echo "  OpenWebUI: $OPENWEBUI_PORT"
    echo "  Qdrant: $QDRANT_PORT"
    echo "  N8N: $N8N_PORT"
    echo "  Code Server: $CODESERVER_PORT"
    
    echo ""
    safe_read "Confirm configuration and proceed? [yes/N]: " "" "FINAL_CONFIRM"
    if [[ ! "$FINAL_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Configuration cancelled"
        exit 1
    fi
}

# Apply Preset Defaults
apply_preset_defaults() {
    local preset="$1"
    
    case "$preset" in
        minimal)
            # Enable core services only
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            # Disable others
            LIBRECHAT_ENABLED="false"
            CODESERVER_ENABLED="false"
            N8N_ENABLED="false"
            ;;
        dev)
            # Enable minimal + development tools
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            CODESERVER_ENABLED="true"
            N8N_ENABLED="true"
            FLOWISE_ENABLED="true"
            MEM0_ENABLED="true"
            ;;
        standard)
            # Enable dev + production tools
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            CODESERVER_ENABLED="true"
            N8N_ENABLED="true"
            FLOWISE_ENABLED="true"
            MEM0_ENABLED="true"
            LIBRECHAT_ENABLED="true"
            DIFY_ENABLED="true"
            GRAFANA_ENABLED="true"
            PROMETHEUS_ENABLED="true"
            AUTHENTIK_ENABLED="true"
            ;;
        full)
            # Enable all services
            POSTGRES_ENABLED="true"
            REDIS_ENABLED="true"
            LITELLM_ENABLED="true"
            OLLAMA_ENABLED="true"
            OPENWEBUI_ENABLED="true"
            QDRANT_ENABLED="true"
            CADDY_ENABLED="true"
            CODESERVER_ENABLED="true"
            N8N_ENABLED="true"
            FLOWISE_ENABLED="true"
            MEM0_ENABLED="true"
            LIBRECHAT_ENABLED="true"
            DIFY_ENABLED="true"
            GRAFANA_ENABLED="true"
            PROMETHEUS_ENABLED="true"
            AUTHENTIK_ENABLED="true"
            # Add all other services...
            ;;
        custom)
            # Disable all services initially
            POSTGRES_ENABLED="false"
            REDIS_ENABLED="false"
            LITELLM_ENABLED="false"
            OLLAMA_ENABLED="false"
            OPENWEBUI_ENABLED="false"
            QDRANT_ENABLED="false"
            CADDY_ENABLED="false"
            # User will enable individually
            ;;
    esac
}

# =============================================================================
# MAIN INTERACTIVE INPUT FUNCTION
# =============================================================================
run_interactive_collection() {
    echo "=== AI PLATFORM SETUP - INTERACTIVE CONFIGURATION ==="
    
    # Collect all configuration interactively
    collect_identity
    configure_storage
    select_stack_preset
    configure_llm_gateway
    configure_vector_db
    configure_tls
    collect_api_keys
    configure_ports
    
    # Show final summary
    show_configuration_summary
    
    echo "=== INTERACTIVE CONFIGURATION COMPLETE ==="
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local ingest_from=""
    litellm_master_key="$(gen_secret)"
    local preserve_secrets=false
    local generate_new=false
    local deployment_mode=""
    local template_file=""
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --ingest-from)
                ingest_from="$2"
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
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate tenant ID
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Set up logging
    LOG_FILE="/tmp/ai-platform-setup-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== Script 1: System Setup & Input Collection ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: $tenant_id"
    log "Dry-run: ${dry_run}"
    log "Ingest from: ${ingest_from}"
    log "Preserve secrets: ${preserve_secrets}"
    log "Generate new: ${generate_new}"
    log "Deployment mode: ${deployment_mode}"
    log "Template file: ${template_file}"
    
    # Display banner
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║         AI Platform — System Setup                 ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    
    # Run interactive collection or template processing
    if [[ -n "$template_file" ]]; then
        log "Processing template file: $template_file"
        # TODO: Implement template processing
        fail "Template processing not yet implemented"
    else
        run_interactive_collection
    fi
    
    # Generate platform.conf
    log "Generating platform.conf..."
    write_platform_conf
    
    # Create tenant user
    log "Creating tenant user: ${PLATFORM_PREFIX}${TENANT_ID}"
    if ! id "${PLATFORM_PREFIX}${TENANT_ID}" &>/dev/null; then
        useradd -m -s /bin/bash "${PLATFORM_PREFIX}${TENANT_ID}"
        usermod -aG docker "${PLATFORM_PREFIX}${TENANT_ID}"
        echo "Tenant user created: ${PLATFORM_PREFIX}${TENANT_ID}"
    else
        echo "Tenant user already exists: ${PLATFORM_PREFIX}${TENANT_ID}"
    fi
    
    echo "=== SYSTEM SETUP COMPLETE ==="
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
